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
#include "HMM.mqh"
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

   // Upgrade 3: H1 execution trigger
   MARKET_REGIME h1Regime;
   int           mtfAlignmentScore;
   bool          h1H4Aligned;
   // Upgrade 4: Volatility targeting
   double realizedVol;
   double targetVol;
   double volTargetMultiplier;
   // Upgrade 5: HMM overlay
   HMM_STATE hmm_state;
   double    hmm_confidence;
};

class CRegimeEngine
{
private:
   CMarketRegime          m_detector;    // H4 regime detector
   CMarketRegime          m_detectorD1;  // D1 regime detector (HTF confirmation)
   CMarketRegime          m_detectorH1;  // H1 execution trigger
   CHMM                   m_hmm;
   CAnalysisMeanReversion m_mr;
   CAnalysisVolatility    m_vol;

   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   bool            m_initialized;
   bool            m_useH1Trigger;
   bool            m_useVolTarget;
   bool            m_useHMM;

   // Last result (to avoid recomputing on every tick)
   RegimeContext   m_lastCtx;
   datetime        m_lastBarTime;

public:
   CRegimeEngine()
   {
      m_initialized  = false;
      m_lastBarTime  = 0;
      m_useH1Trigger = true;
      m_useVolTarget = true;
      m_useHMM       = true;
   }

   int RegimeCat(MARKET_REGIME r)
   {
      if(r == REGIME_TREND_STRONG || r == REGIME_TREND_WEAK) return 1;
      if(r == REGIME_RANGING) return 2;
      return 0;
   }

   double TargetVolForRegime(MARKET_REGIME regime)
   {
      switch(regime)
      {
         case REGIME_TREND_STRONG: return 12.0;
         case REGIME_TREND_WEAK:   return  9.0;
         case REGIME_RANGING:      return  7.0;
         case REGIME_VOLATILE:     return  5.0;
         case REGIME_CRISIS:       return  0.0;
         default:                  return  7.0;
      }
   }

   double ComputeRealizedVol(string symbol, ENUM_TIMEFRAMES tf, int bars = 20)
   {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(symbol, tf, 1, bars + 1, closes) < bars + 1) return -1.0;
      double logRet[]; ArrayResize(logRet, bars);
      double mu = 0;
      for(int i = 0; i < bars; i++)
      {
         logRet[i] = (closes[i+1] > 0) ? MathLog(closes[i] / closes[i+1]) : 0;
         mu += logRet[i];
      }
      mu /= bars;
      double variance = 0;
      for(int i = 0; i < bars; i++)
         variance += (logRet[i] - mu) * (logRet[i] - mu);
      variance /= (bars > 1 ? bars - 1 : 1);
      int barsPerYear = (tf == PERIOD_D1) ? 252 :
                        (tf == PERIOD_H4) ? 1512 :
                        (tf == PERIOD_H1) ? 6048 : 1512;
      return MathSqrt(variance * barsPerYear) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Initialize all sub-modules                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf,
             int baseMinConfluence = 4, double maxSpreadPoints = 50,
             bool useRollingMode = true, bool useERFractal = true,
             bool useH1Trigger = true, bool useVolTarget = true, bool useHMM = true)
   {
      m_symbol       = symbol;
      m_tf           = tf;
      m_useH1Trigger = useH1Trigger;
      m_useVolTarget = useVolTarget;
      m_useHMM       = useHMM;

      bool ok = true;
      ok &= m_detector.Init(symbol, tf,
                            /*atrPeriod*/14, /*adxPeriod*/14, /*lookback*/50,
                            /*hysteresisMinBars*/2, /*changeThreshold*/0.62,
                            useRollingMode, useERFractal);
      // D1 detector: looser hysteresis (daily bars change slowly)
      m_detectorD1.Init(symbol, PERIOD_D1,
                        /*atrPeriod*/14, /*adxPeriod*/14, /*lookback*/30,
                        /*hysteresisMinBars*/1, /*changeThreshold*/0.55,
                        useRollingMode, useERFractal);
      ok &= m_mr.Init(symbol, tf,
                      /*bbPeriod*/20, /*bbDev*/2.0,
                      /*rsiPeriod*/14, /*rsiOS*/35.0, /*rsiOB*/65.0,
                      /*atrPeriod*/14, /*slATR*/0.5);
      ok &= m_vol.Init(symbol, tf,
                       /*atrSlow*/50, /*atrFast*/5, /*adxPeriod*/14,
                       /*squeezeRatio*/0.70, /*breakoutRatio*/1.30,
                       /*compressionBars*/3, /*slMult*/1.2, /*tpMult*/2.0);

      if(m_useH1Trigger)
         m_detectorH1.Init(symbol, PERIOD_H1, 14, 14, 30, 1, 0.58,
                           useRollingMode, useERFractal);

      if(m_useHMM)
         m_hmm.Init(20);

      m_initialized = ok;
      return ok;
   }

   void Deinit()
   {
      m_detector.Deinit();
      m_detectorD1.Deinit();
      if(m_useH1Trigger) m_detectorH1.Deinit();
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
      // Upgrade defaults
      ctx.h1Regime          = REGIME_UNKNOWN;
      ctx.h1H4Aligned       = true;
      ctx.mtfAlignmentScore = 2;
      ctx.realizedVol       = 0;
      ctx.targetVol         = 0;
      ctx.volTargetMultiplier = 1.0;
      ctx.hmm_state         = HMM_LOW_VOL;
      ctx.hmm_confidence    = 0.5;

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

      // ── 3. H1 execution trigger ──────────────────────────────────
      if(m_useH1Trigger)
      {
         RegimeResult rrH1  = m_detectorH1.Detect();
         ctx.h1Regime       = rrH1.regime;
         int d1Cat = RegimeCat(rrD1.regime);
         int h4Cat = RegimeCat(rr.regime);
         int h1Cat = RegimeCat(rrH1.regime);
         ctx.h1H4Aligned    = (h1Cat == h4Cat && h4Cat != 0);
         ctx.mtfAlignmentScore = 0;
         if(d1Cat == h4Cat && h4Cat != 0) ctx.mtfAlignmentScore++;
         if(h1Cat == h4Cat && h4Cat != 0) ctx.mtfAlignmentScore++;
         if(d1Cat == h4Cat && h1Cat == h4Cat && h4Cat != 0) ctx.mtfAlignmentScore++;
      }
      else
      {
         ctx.h1Regime          = REGIME_UNKNOWN;
         ctx.h1H4Aligned       = true;
         ctx.mtfAlignmentScore = 2;
      }

      // ── 4. Volatility targeting ───────────────────────────────────
      if(m_useVolTarget)
      {
         double rv = ComputeRealizedVol(m_symbol, m_tf, 20);
         double tv = TargetVolForRegime(rr.regime);
         ctx.realizedVol  = (rv > 0) ? rv : 0;
         ctx.targetVol    = tv;
         if(rv > 0.5 && tv > 0)
            ctx.volTargetMultiplier = MathMax(0.3, MathMin(2.0, tv / rv));
         else
            ctx.volTargetMultiplier = (tv == 0.0) ? 0.0 : 1.0;
         ctx.riskMultiplier = ctx.volTargetMultiplier;
      }
      else
      {
         ctx.realizedVol         = 0;
         ctx.targetVol           = 0;
         ctx.volTargetMultiplier = 1.0;
      }

      // ── 5. HMM overlay ───────────────────────────────────────────
      if(m_useHMM && ctx.realizedVol > 0)
      {
         m_hmm.UpdateObservation(ctx.realizedVol);
         ctx.hmm_state      = m_hmm.GetState();
         ctx.hmm_confidence = m_hmm.GetConfidence();
      }
      else
      {
         ctx.hmm_state      = HMM_LOW_VOL;
         ctx.hmm_confidence = 0.5;
      }

      m_lastCtx = ctx;
      return ctx;
   }

   // Accessors
   MARKET_REGIME GetCurrentRegime()     { return m_lastCtx.regime; }
   string        GetCurrentLabel()      { return m_lastCtx.regimeLabel; }
   string        GetD1Label()           { return m_detectorD1.RegimeToString(m_lastCtx.htfRegime); }
   string        GetH1Label()           { return m_detectorH1.RegimeToString(m_lastCtx.h1Regime); }
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
