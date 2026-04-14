//+------------------------------------------------------------------+
//|                                              MarketRegime.mqh    |
//|              Adaptive Market Regime Detector — 5 regimes         |
//|  Inputs: ATR ratio, ADX, Chop Index, Autocorrelation, EMA slope  |
//|  Output: RegimeResult (regime + score 0-100 + confidence 0-1)    |
//+------------------------------------------------------------------+
#ifndef MARKET_REGIME_MQH_INCLUDED
#define MARKET_REGIME_MQH_INCLUDED

//───────────────────────────────────────────────────────────────────
// ENUMS & STRUCTS
//───────────────────────────────────────────────────────────────────
enum MARKET_REGIME
{
   REGIME_UNKNOWN      = -1,
   REGIME_TREND_STRONG =  0,   // ~25% of time — momentum, ADX high, autocorr positive
   REGIME_TREND_WEAK   =  1,   // ~15% of time — directional but fading
   REGIME_RANGING      =  2,   // ~35% of time — chop, flat EMA, ATR compressed
   REGIME_VOLATILE     =  3,   // ~20% of time — ATR spike, no clear direction
   REGIME_CRISIS       =  4    //  ~5% of time — extreme spike, stay out
};
// Backward compatibility — old enum values used by Adaptive modules
#define REGIME_TREND  REGIME_TREND_STRONG
#define REGIME_RANGE  REGIME_RANGING
#define REGIME_CHAOS  REGIME_CRISIS

struct RegimeResult
{
   MARKET_REGIME regime;
   int                score;       // 0-100: how strong the regime signal is
   double             confidence;  // 0.0-1.0: agreement between indicators
   string             label;
   // individual metric votes (for dashboard)
   double             atrRatio;
   double             adxValue;
   double             chopValue;
   double             autocorr;
   double             emaSlope;
};

//───────────────────────────────────────────────────────────────────
// ESCALATOR CONFIG per regime
//───────────────────────────────────────────────────────────────────
struct EscalatorConfig
{
   bool   enabled;
   double firstR;
   double firstSL_R;
   double stepR;
   double growthFactor;
   double baseHarvest;
   double harvestDecay;
   double minHarvest;
   int    maxStages;
   double runnerTrailTight;
   double timeStaleMins;
};

//───────────────────────────────────────────────────────────────────
// MAIN CLASS
//───────────────────────────────────────────────────────────────────
class CMarketRegime
{
private:
   // hysteresis: don't flip regime on every tick
   MARKET_REGIME m_lastRegime;
   double             m_lastConfidence;
   int                m_barsSinceChange;
   int                m_hysteresisMinBars;  // min bars before regime can change
   double             m_changeThreshold;    // confidence required to flip

   // indicator handles (created externally, passed in)
   int    m_hATR;
   int    m_hADX;
   int    m_atrPeriod;
   int    m_adxPeriod;
   int    m_lookback;      // bars for autocorrelation + ATR average
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;

public:
   CMarketRegime()
   {
      m_lastRegime        = REGIME_UNKNOWN;
      m_lastConfidence    = 0.0;
      m_barsSinceChange   = 0;
      m_hysteresisMinBars = 2;     // wait at least 2 bars before regime switch
      m_changeThreshold   = 0.62;  // need 62% confidence to switch
      m_hATR              = INVALID_HANDLE;
      m_hADX              = INVALID_HANDLE;
      m_atrPeriod         = 14;
      m_adxPeriod         = 14;
      m_lookback          = 50;
      m_symbol            = _Symbol;
      m_tf                = PERIOD_CURRENT;
   }

   //+------------------------------------------------------------------+
   //| Init: create handles internally                                   |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int atrPeriod = 14,
             int adxPeriod = 14, int lookback = 50,
             int hysteresisMinBars = 2, double changeThreshold = 0.62)
   {
      m_symbol            = symbol;
      m_tf                = tf;
      m_atrPeriod         = atrPeriod;
      m_adxPeriod         = adxPeriod;
      m_lookback          = lookback;
      m_hysteresisMinBars = hysteresisMinBars;
      m_changeThreshold   = changeThreshold;

      m_hATR = iATR(symbol, tf, atrPeriod);
      m_hADX = iADX(symbol, tf, adxPeriod);

      return (m_hATR != INVALID_HANDLE && m_hADX != INVALID_HANDLE);
   }

   void Deinit()
   {
      if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
      if(m_hADX != INVALID_HANDLE) { IndicatorRelease(m_hADX); m_hADX = INVALID_HANDLE; }
   }

   //+------------------------------------------------------------------+
   //| MAIN: Detect current market regime                                |
   //+------------------------------------------------------------------+
   RegimeResult Detect()
   {
      RegimeResult result;
      result.regime     = m_lastRegime;
      result.score      = 0;
      result.confidence = 0.0;
      result.label      = "UNKNOWN";

      if(m_hATR == INVALID_HANDLE || m_hADX == INVALID_HANDLE)
         return result;

      // ── 1. ATR ratio (current vs historical average) ──────────────
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(m_hATR, 0, 1, m_lookback, atrBuf) < m_lookback)
         return result;

      double currentATR = atrBuf[0];
      double avgATR     = 0;
      for(int i = 1; i < m_lookback; i++) avgATR += atrBuf[i];
      avgATR /= (m_lookback - 1);
      double atrRatio = (avgATR > 0) ? currentATR / avgATR : 1.0;
      result.atrRatio = atrRatio;

      // ── 2. ADX ─────────────────────────────────────────────────────
      double adxMain[], diPlus[], diMinus[];
      ArraySetAsSeries(adxMain,  true);
      ArraySetAsSeries(diPlus,   true);
      ArraySetAsSeries(diMinus,  true);
      if(CopyBuffer(m_hADX, 0, 1, 3, adxMain)  < 3) return result;
      if(CopyBuffer(m_hADX, 1, 1, 3, diPlus)   < 3) return result;
      if(CopyBuffer(m_hADX, 2, 1, 3, diMinus)  < 3) return result;
      double adxNow   = adxMain[0];
      double adxSlope = adxMain[0] - adxMain[2]; // rising or falling
      result.adxValue = adxNow;

      // ── 3. Autocorrelation of close returns (lag-1) ────────────────
      // Positive → trending, Negative → mean-reverting
      double closes[];
      ArraySetAsSeries(closes, true);
      int acLen = 20;
      if(CopyClose(m_symbol, m_tf, 1, acLen + 1, closes) < acLen + 1)
         return result;

      double returns[];
      ArrayResize(returns, acLen);
      for(int i = 0; i < acLen; i++)
         returns[i] = (closes[i] > 0) ? (closes[i] - closes[i+1]) / closes[i+1] : 0;

      double autocorr = _CalcAutocorr(returns, acLen, 1);
      result.autocorr = autocorr;

      // ── 4. Chop (simple: ATR range vs high-low range) ─────────────
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows,  true);
      int chopLen = 14;
      if(CopyHigh(m_symbol, m_tf, 1, chopLen, highs) < chopLen) return result;
      if(CopyLow(m_symbol,  m_tf, 1, chopLen, lows)  < chopLen) return result;

      double highestHigh = highs[ArrayMaximum(highs, 0, chopLen)];
      double lowestLow   = lows[ArrayMinimum(lows,   0, chopLen)];
      double totalRange  = highestHigh - lowestLow;
      double atrSum      = 0;
      for(int i = 0; i < chopLen; i++) atrSum += atrBuf[i];
      double chopIndex = (totalRange > 0) ? atrSum / totalRange : 1.0;
      result.chopValue = chopIndex;

      // ── 5. EMA slope (200 EMA) ─────────────────────────────────────
      double emaArr[];
      ArraySetAsSeries(emaArr, true);
      int hEMALocal = iMA(m_symbol, m_tf, 200, 0, MODE_EMA, PRICE_CLOSE);
      double emaSlope = 0;
      if(hEMALocal != INVALID_HANDLE)
      {
         if(CopyBuffer(hEMALocal, 0, 1, 3, emaArr) >= 3)
            emaSlope = (emaArr[0] - emaArr[2]) / avgATR; // normalized slope
         IndicatorRelease(hEMALocal);
      }
      result.emaSlope = emaSlope;

      // ── SCORING: Each metric votes 0-20 for a regime ───────────────
      int voteTrendStrong = 0;
      int voteTrendWeak   = 0;
      int voteRanging     = 0;
      int voteVolatile    = 0;
      int voteCrisis      = 0;

      // ATR ratio votes
      if(atrRatio > 2.5)       { voteCrisis    += 20; }
      else if(atrRatio > 1.7)  { voteVolatile  += 20; }
      else if(atrRatio > 1.2)  { voteTrendStrong += 10; voteVolatile += 10; }
      else if(atrRatio < 0.75) { voteRanging    += 20; }
      else                     { voteTrendWeak  += 10; voteRanging += 10; }

      // ADX votes
      if(adxNow > 35 && adxSlope > 0)       { voteTrendStrong += 20; }
      else if(adxNow > 25)                   { voteTrendStrong += 12; voteTrendWeak += 8; }
      else if(adxNow > 20 && adxSlope >= 0)  { voteTrendWeak   += 20; }
      else if(adxNow < 18)                   { voteRanging     += 20; }
      else                                   { voteRanging     += 12; voteTrendWeak += 8; }

      // Autocorrelation votes
      if(autocorr > 0.3)       { voteTrendStrong += 20; }
      else if(autocorr > 0.1)  { voteTrendWeak   += 20; }
      else if(autocorr < -0.2) { voteRanging     += 20; }
      else                     { voteRanging     += 10; voteVolatile += 10; }

      // Chop Index votes (higher = more choppy)
      if(chopIndex > 1.1)      { voteRanging     += 20; }
      else if(chopIndex > 0.9) { voteTrendWeak   += 10; voteRanging += 10; }
      else if(chopIndex < 0.6) { voteTrendStrong += 20; }
      else                     { voteTrendWeak   += 20; }

      // EMA slope votes
      if(MathAbs(emaSlope) > 0.5)       { voteTrendStrong += 20; }
      else if(MathAbs(emaSlope) > 0.2)  { voteTrendWeak   += 20; }
      else if(MathAbs(emaSlope) < 0.08) { voteRanging     += 20; }
      else                              { voteTrendWeak   += 12; voteRanging += 8; }

      // ── Find winning regime ────────────────────────────────────────
      int totalVotes = voteTrendStrong + voteTrendWeak + voteRanging + voteVolatile + voteCrisis;
      if(totalVotes == 0) return result;

      int maxVote = voteTrendStrong;
      MARKET_REGIME candidate = REGIME_TREND_STRONG;
      if(voteTrendWeak  > maxVote) { maxVote = voteTrendWeak;  candidate = REGIME_TREND_WEAK; }
      if(voteRanging    > maxVote) { maxVote = voteRanging;    candidate = REGIME_RANGING; }
      if(voteVolatile   > maxVote) { maxVote = voteVolatile;   candidate = REGIME_VOLATILE; }
      if(voteCrisis     > maxVote) { maxVote = voteCrisis;     candidate = REGIME_CRISIS; }

      double confidence = (double)maxVote / (double)totalVotes;
      int    score      = (int)MathRound(confidence * 100.0);

      // ── Hysteresis: resist regime whipsaws ────────────────────────
      m_barsSinceChange++;
      bool canChange = (m_barsSinceChange >= m_hysteresisMinBars);
      bool shouldChange = (candidate != m_lastRegime && confidence >= m_changeThreshold);

      if(m_lastRegime == REGIME_UNKNOWN || (canChange && shouldChange))
      {
         m_lastRegime      = candidate;
         m_lastConfidence  = confidence;
         m_barsSinceChange = 0;
      }

      result.regime     = m_lastRegime;
      result.score      = score;
      result.confidence = confidence;
      result.label      = RegimeToString(m_lastRegime);
      return result;
   }

   //+------------------------------------------------------------------+
   //| Returns escalator config calibrated for the current regime        |
   //+------------------------------------------------------------------+
   EscalatorConfig GetEscalatorConfig(MARKET_REGIME regime)
   {
      EscalatorConfig cfg;

      switch(regime)
      {
         case REGIME_TREND_STRONG:
            // Let it run — full aggressive escalator
            cfg.enabled         = true;
            cfg.firstR          = 0.15;
            cfg.firstSL_R       = -0.02;
            cfg.stepR           = 0.20;
            cfg.growthFactor    = 1.7;
            cfg.baseHarvest     = 65.0;
            cfg.harvestDecay    = 0.62;
            cfg.minHarvest      = 20.0;
            cfg.maxStages       = 15;
            cfg.runnerTrailTight = 0.93;
            cfg.timeStaleMins   = 120.0;
            break;

         case REGIME_TREND_WEAK:
            // Trend fading — tighten runner, harvest more per stage
            cfg.enabled         = true;
            cfg.firstR          = 0.20;
            cfg.firstSL_R       = -0.015;
            cfg.stepR           = 0.25;
            cfg.growthFactor    = 1.5;
            cfg.baseHarvest     = 75.0;
            cfg.harvestDecay    = 0.70;
            cfg.minHarvest      = 30.0;
            cfg.maxStages       = 10;
            cfg.runnerTrailTight = 0.88;
            cfg.timeStaleMins   = 90.0;
            break;

         case REGIME_RANGING:
            // Quick harvest — price WILL reverse, no runner
            cfg.enabled         = true;
            cfg.firstR          = 0.30;
            cfg.firstSL_R       = -0.01;
            cfg.stepR           = 0.35;
            cfg.growthFactor    = 1.2;
            cfg.baseHarvest     = 90.0;
            cfg.harvestDecay    = 0.85;
            cfg.minHarvest      = 70.0;
            cfg.maxStages       = 4;
            cfg.runnerTrailTight = 0.0;  // no runner in range
            cfg.timeStaleMins   = 45.0;
            break;

         case REGIME_VOLATILE:
            // Capture the spike, exit immediately
            cfg.enabled         = true;
            cfg.firstR          = 0.10;
            cfg.firstSL_R       = -0.005;
            cfg.stepR           = 0.15;
            cfg.growthFactor    = 1.1;
            cfg.baseHarvest     = 95.0;
            cfg.harvestDecay    = 0.90;
            cfg.minHarvest      = 80.0;
            cfg.maxStages       = 3;
            cfg.runnerTrailTight = 0.98;
            cfg.timeStaleMins   = 20.0;
            break;

         case REGIME_CRISIS:
         default:
            // Escalator OFF — only momentum exit decides
            cfg.enabled         = false;
            cfg.firstR          = 0.0;
            cfg.firstSL_R       = 0.0;
            cfg.stepR           = 0.0;
            cfg.growthFactor    = 1.0;
            cfg.baseHarvest     = 0.0;
            cfg.harvestDecay    = 0.0;
            cfg.minHarvest      = 0.0;
            cfg.maxStages       = 0;
            cfg.runnerTrailTight = 0.0;
            cfg.timeStaleMins   = 0.0;
            break;
      }
      return cfg;
   }

   //+------------------------------------------------------------------+
   //| Adaptive confluence weights per regime                            |
   //+------------------------------------------------------------------+
   void GetAdaptiveWeights(MARKET_REGIME regime, double &weights[])
   {
      // weights[0]=Trend, [1]=Structure/OB, [2]=PriceAction, [3]=Volume, [4]=MTF
      ArrayResize(weights, 5);
      switch(regime)
      {
         case REGIME_TREND_STRONG:
            weights[0]=1.4; weights[1]=0.8; weights[2]=1.0; weights[3]=1.2; weights[4]=1.5;
            break;
         case REGIME_TREND_WEAK:
            weights[0]=1.1; weights[1]=1.0; weights[2]=1.1; weights[3]=1.0; weights[4]=1.2;
            break;
         case REGIME_RANGING:
            weights[0]=0.6; weights[1]=1.5; weights[2]=1.4; weights[3]=0.8; weights[4]=0.7;
            break;
         case REGIME_VOLATILE:
            weights[0]=0.8; weights[1]=1.2; weights[2]=0.9; weights[3]=0.9; weights[4]=1.3;
            break;
         case REGIME_CRISIS:
         default:
            weights[0]=0.5; weights[1]=0.5; weights[2]=0.5; weights[3]=0.5; weights[4]=0.5;
            break;
      }
   }

   //+------------------------------------------------------------------+
   //| Minimum confluence score required per regime                      |
   //+------------------------------------------------------------------+
   int GetMinConfluenceForRegime(MARKET_REGIME regime, int baseMin)
   {
      switch(regime)
      {
         case REGIME_TREND_STRONG: return baseMin;          // use configured value
         case REGIME_TREND_WEAK:   return baseMin + 2;      // need more confirmation
         case REGIME_RANGING:      return baseMin - 2;      // mean reversion: easier entry
         case REGIME_VOLATILE:     return baseMin + 4;      // very selective
         case REGIME_CRISIS:       return 999;              // no entries in crisis
         default:                  return baseMin;
      }
   }

   //+------------------------------------------------------------------+
   //| Risk size multiplier per regime                                   |
   //+------------------------------------------------------------------+
   double GetRiskMultiplier(MARKET_REGIME regime)
   {
      switch(regime)
      {
         case REGIME_TREND_STRONG: return 1.0;   // full risk
         case REGIME_TREND_WEAK:   return 0.75;  // 75% of normal risk
         case REGIME_RANGING:      return 0.6;   // smaller — TP is closer
         case REGIME_VOLATILE:     return 0.4;   // spike: small size
         case REGIME_CRISIS:       return 0.0;   // no trading
         default:                  return 0.5;
      }
   }

   //+------------------------------------------------------------------+
   //| Time decay factor for signal age                                  |
   //+------------------------------------------------------------------+
   double GetTimeDecayFactor(datetime signalTime, int maxAgeBars = 5)
   {
      long ageSeconds = TimeCurrent() - signalTime;
      int  barAge     = (int)(ageSeconds / PeriodSeconds(PERIOD_CURRENT));
      if(barAge >= maxAgeBars) return 0.1;
      return MathMax(1.0 - (0.9 * (double)barAge / (double)maxAgeBars), 0.1);
   }

   string RegimeToString(MARKET_REGIME r)
   {
      switch(r)
      {
         case REGIME_TREND_STRONG: return "TREND STRONG";
         case REGIME_TREND_WEAK:   return "TREND WEAK";
         case REGIME_RANGING:      return "RANGING";
         case REGIME_VOLATILE:     return "VOLATILE";
         case REGIME_CRISIS:       return "CRISIS";
         default:                  return "UNKNOWN";
      }
   }

   // How many bars the current regime has been active (0 = just changed)
   int GetPersistenceBars() { return m_barsSinceChange; }

private:
   //+------------------------------------------------------------------+
   //| Pearson autocorrelation at lag k                                  |
   //+------------------------------------------------------------------+
   double _CalcAutocorr(double &series[], int n, int lag)
   {
      if(n <= lag) return 0.0;
      double mean = 0;
      for(int i = 0; i < n; i++) mean += series[i];
      mean /= n;

      double num = 0, den = 0;
      for(int i = 0; i < n - lag; i++)
         num += (series[i] - mean) * (series[i + lag] - mean);
      for(int i = 0; i < n; i++)
         den += (series[i] - mean) * (series[i] - mean);

      return (den > 0) ? num / den : 0.0;
   }
};


#endif
