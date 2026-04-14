//+------------------------------------------------------------------+
//|                                              RegimeEngine.mqh    |
//|  Master coordinator: detects regime, selects analysis module,    |
//|  returns EscalatorConfig + adjusted risk + confluence threshold. |
//|                                                                  |
//|  USAGE in Symbol_Engine.mq5:                                     |
//|    #include "Include/Regime/RegimeEngine.mqh"                    |
//|    CRegimeEngine g_regime;                                       |
//|    g_regime.Init(_Symbol, PERIOD_CURRENT);                       |
//|    RegimeContext ctx = g_regime.Evaluate(InpMinConfluenceEntry); |
//|    // use ctx.escalator, ctx.riskMult, ctx.minConfluence, etc.   |
//+------------------------------------------------------------------+
#ifndef REGIME_ENGINE_MQH_INCLUDED
#define REGIME_ENGINE_MQH_INCLUDED

#include "../MarketRegime.mqh"
#include "AnalysisMeanReversion.mqh"
#include "AnalysisVolatility.mqh"

//───────────────────────────────────────────────────────────────────
// Complete context returned to the EA each bar
//───────────────────────────────────────────────────────────────────
struct RegimeContext
{
   // What is the market doing right now?
   MARKET_REGIME regime;
   string             regimeLabel;
   int                regimeScore;       // 0-100 confidence
   double             regimeConfidence;  // 0.0-1.0
   int                regimePersistenceBars; // bars since last regime change

   // Higher-timeframe context (D1)
   MARKET_REGIME htfRegime;      // D1 regime
   bool          htfConflict;    // true: D1=TREND but H4=RANGING → suppress MR entries

   // What should the EA do?
   EscalatorConfig    escalator;         // dynamic escalator for this regime
   double             riskMultiplier;    // scale lot size by this
   int                minConfluence;     // adjusted entry threshold
   bool               allowEntries;      // false in CRISIS

   // Are there active regime-specific signals?
   bool               mrSignalValid;     // mean reversion signal available
   MRSignal           mrSignal;          // if RANGING and setup found
   bool               volSignalValid;    // volatility breakout signal available
   VolSignal          volSignal;         // if VOLATILE and breakout found
};

class CRegimeEngine
{
private:
   CMarketRegime          m_detector;    // H4 regime detector
   CMarketRegime          m_detectorD1;  // D1 regime detector (HTF confirmation)
   CAnalysisMeanReversion m_mr;
   CAnalysisVolatility    m_vol;

   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   bool            m_initialized;

   // Last result (to avoid recomputing on every tick)
   RegimeContext   m_lastCtx;
   datetime        m_lastBarTime;

public:
   CRegimeEngine()
   {
      m_initialized = false;
      m_lastBarTime = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize all sub-modules                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf)
   {
      m_symbol = symbol;
      m_tf     = tf;

      bool ok = true;
      ok &= m_detector.Init(symbol, tf,
                            /*atrPeriod*/14, /*adxPeriod*/14, /*lookback*/50,
                            /*hysteresisMinBars*/2, /*changeThreshold*/0.62);
      // D1 detector: looser hysteresis (daily bars change slowly)
      m_detectorD1.Init(symbol, PERIOD_D1,
                        /*atrPeriod*/14, /*adxPeriod*/14, /*lookback*/30,
                        /*hysteresisMinBars*/1, /*changeThreshold*/0.55);
      ok &= m_mr.Init(symbol, tf,
                      /*bbPeriod*/20, /*bbDev*/2.0,
                      /*rsiPeriod*/14, /*rsiOS*/35.0, /*rsiOB*/65.0,
                      /*atrPeriod*/14, /*slATR*/0.5);
      ok &= m_vol.Init(symbol, tf,
                       /*atrSlow*/50, /*atrFast*/5, /*adxPeriod*/14,
                       /*squeezeRatio*/0.70, /*breakoutRatio*/1.30,
                       /*compressionBars*/3, /*slMult*/1.2, /*tpMult*/2.0);

      m_initialized = ok;
      return ok;
   }

   void Deinit()
   {
      m_detector.Deinit();
      m_detectorD1.Deinit();
      m_mr.Deinit();
      m_vol.Deinit();
      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   //| Call once per bar (or per tick if needed).                        |
   //| Returns full context: regime + escalator + signals.               |
   //+------------------------------------------------------------------+
   RegimeContext Evaluate(int baseMinConfluence, double maxSpreadPoints = 50)
   {
      if(!m_initialized) return m_lastCtx;

      // Only recompute on new bar
      datetime barTime = iTime(m_symbol, m_tf, 0);
      if(barTime == m_lastBarTime) return m_lastCtx;
      m_lastBarTime = barTime;

      RegimeContext ctx;

      // ── 1. Detect H4 regime ───────────────────────────────────────
      RegimeResult rr = m_detector.Detect();
      ctx.regime                = rr.regime;
      ctx.regimeLabel           = rr.label;
      ctx.regimeScore           = rr.score;
      ctx.regimeConfidence      = rr.confidence;
      ctx.regimePersistenceBars = m_detector.GetPersistenceBars();

      // ── 2. Detect D1 regime (HTF confirmation) ────────────────────
      RegimeResult rrD1 = m_detectorD1.Detect();
      ctx.htfRegime   = rrD1.regime;
      // HTF conflict: D1 is trending but H4 is ranging
      // → MR entries would be counter-trend on D1 — suppress them
      bool d1Trending = (rrD1.regime == REGIME_TREND_STRONG || rrD1.regime == REGIME_TREND_WEAK);
      ctx.htfConflict = d1Trending && (rr.regime == REGIME_RANGING);

      // ── 3. Get escalator for this regime ─────────────────────────
      ctx.escalator        = m_detector.GetEscalatorConfig(rr.regime);

      // ── 4. Adjusted risk and confluence ──────────────────────────
      ctx.riskMultiplier   = m_detector.GetRiskMultiplier(rr.regime);
      ctx.minConfluence    = m_detector.GetMinConfluenceForRegime(rr.regime, baseMinConfluence);
      ctx.allowEntries     = (rr.regime != REGIME_CRISIS);

      // ── 4. Module-specific signals ────────────────────────────────
      ctx.mrSignalValid  = false;
      ctx.volSignalValid = false;

      if(rr.regime == REGIME_RANGING)
      {
         ctx.mrSignal      = m_mr.Analyze(maxSpreadPoints);
         ctx.mrSignalValid = ctx.mrSignal.valid;
      }
      else if(rr.regime == REGIME_VOLATILE || rr.regime == REGIME_TREND_WEAK)
      {
         ctx.volSignal      = m_vol.Analyze(maxSpreadPoints);
         ctx.volSignalValid = ctx.volSignal.valid;
      }

      m_lastCtx = ctx;
      return ctx;
   }

   // Accessors
   MARKET_REGIME GetCurrentRegime()     { return m_lastCtx.regime; }
   string        GetCurrentLabel()      { return m_lastCtx.regimeLabel; }
   string        GetD1Label()           { return m_detectorD1.RegimeToString(m_lastCtx.htfRegime); }
   bool          IsInCompression()      { return m_vol.IsInCompression(); }
   int           GetCompressionBars()   { return m_vol.GetCompressionBars(); }
   double        GetBBWidthPct()        { return m_mr.GetBBWidthPct(); }

   // Proxy — allows Symbol_Engine to call g_regimeEngine.GetAdaptiveWeights()
   void GetAdaptiveWeights(MARKET_REGIME regime, double &weights[])
   {
      m_detector.GetAdaptiveWeights(regime, weights);
   }
};

#endif
