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
   // Upgrade 2: ER + Fractal Index
   double             erValue;
   double             fractalIndex;

   RegimeResult() : regime(REGIME_UNKNOWN), score(0), confidence(0.0),
                    label("UNKNOWN"), atrRatio(1.0), adxValue(0.0),
                    chopValue(1.0), autocorr(0.0), emaSlope(0.0),
                    erValue(0.5), fractalIndex(0.5) {}
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
   int    m_hEMA;
   int    m_atrPeriod;
   int    m_adxPeriod;
   int    m_lookback;      // bars for autocorrelation + ATR average
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;

   // Upgrade 1: Rolling mode buffer
   int    m_regimeBuffer[20];
   int    m_bufHead;
   int    m_bufFilled;
   bool   m_useRollingMode;

   // Upgrade 2: ER + Fractal Index
   int  m_erPeriod;
   int  m_fractalPeriod;
   bool m_useERFractal;

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
      m_hEMA              = INVALID_HANDLE;
      m_atrPeriod         = 14;
      m_adxPeriod         = 14;
      m_lookback          = 50;
      m_symbol            = _Symbol;
      m_tf                = PERIOD_CURRENT;
      // Upgrade 1: Rolling mode buffer
      m_bufHead           = 0;
      m_bufFilled         = 0;
      m_useRollingMode    = true;
      ArrayInitialize(m_regimeBuffer, 0);
      // Upgrade 2: ER + Fractal Index
      m_erPeriod          = 10;
      m_fractalPeriod     = 32;
      m_useERFractal      = true;
   }

   //+------------------------------------------------------------------+
   //| Init: create handles internally                                   |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int atrPeriod = 14,
             int adxPeriod = 14, int lookback = 50,
             int hysteresisMinBars = 2, double changeThreshold = 0.62,
             bool useRollingMode = true, bool useERFractal = true)
   {
      m_symbol            = symbol;
      m_tf                = tf;
      m_atrPeriod         = atrPeriod;
      m_adxPeriod         = adxPeriod;
      m_lookback          = lookback;
      m_hysteresisMinBars = hysteresisMinBars;
      m_changeThreshold   = changeThreshold;
      m_useRollingMode    = useRollingMode;
      m_useERFractal      = useERFractal;

      // Upgrade 1: reduce hysteresis when rolling mode active (buffer handles smoothing)
      if(useRollingMode && hysteresisMinBars >= 2) m_hysteresisMinBars = 1;

      m_hATR = iATR(symbol, tf, atrPeriod);
      m_hADX = iADX(symbol, tf, adxPeriod);
      m_hEMA = iMA(symbol, tf, 200, 0, MODE_EMA, PRICE_CLOSE);

      return (m_hATR != INVALID_HANDLE && m_hADX != INVALID_HANDLE && m_hEMA != INVALID_HANDLE);
   }

   void Deinit()
   {
      if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
      if(m_hADX != INVALID_HANDLE) { IndicatorRelease(m_hADX); m_hADX = INVALID_HANDLE; }
      if(m_hEMA != INVALID_HANDLE) { IndicatorRelease(m_hEMA); m_hEMA = INVALID_HANDLE; }
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
      int fetchBars = MathMax(acLen + 2, m_fractalPeriod + 2);
      int copiedCloses = CopyClose(m_symbol, m_tf, 1, fetchBars, closes);
      if(copiedCloses < acLen + 1)
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
      double emaSlope = 0;
      if(m_hEMA != INVALID_HANDLE && CopyBuffer(m_hEMA, 0, 1, 3, emaArr) >= 3)
         emaSlope = (emaArr[0] - emaArr[2]) / avgATR; // normalized slope
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

      // ── Upgrade 2: Kaufman ER + Fractal Index ─────────────────────
      if(m_useERFractal)
      {
         // --- Kaufman Efficiency Ratio ---
         int erN = MathMin(m_erPeriod, copiedCloses - 1);
         double er = 0.5;
         if(erN >= 3)
         {
            double netChange = MathAbs(closes[0] - closes[erN]);
            double pathLen   = 0;
            for(int _i = 0; _i < erN; _i++)
               pathLen += MathAbs(closes[_i] - closes[_i+1]);
            if(pathLen > 0) er = netChange / pathLen;
         }
         result.erValue = er;

         // --- Fractal Index (R/S method, 32 bars) ---
         int fN = MathMin(m_fractalPeriod, copiedCloses - 1);
         double fracH = 0.5;
         if(fN >= 8)
         {
            double mu = 0;
            double logR[]; ArrayResize(logR, fN);
            for(int _i = 0; _i < fN; _i++)
            {
               logR[_i] = (closes[_i+1] > 0) ? MathLog(closes[_i] / closes[_i+1]) : 0;
               mu += logR[_i];
            }
            mu /= fN;

            double cumDev = 0, maxDev = -DBL_MAX, minDev = DBL_MAX, devSS = 0;
            for(int _i = 0; _i < fN; _i++)
            {
               cumDev += (logR[_i] - mu);
               if(cumDev > maxDev) maxDev = cumDev;
               if(cumDev < minDev) minDev = cumDev;
               devSS  += (logR[_i] - mu) * (logR[_i] - mu);
            }
            double R = maxDev - minDev;
            double S = MathSqrt(devSS / fN);
            if(S > 0 && R > 0)
               fracH = MathLog(R / S) / MathLog((double)fN / 2.0);
            fracH = MathMax(0.0, MathMin(1.0, fracH));
         }
         result.fractalIndex = fracH;

         // --- Add ER votes ---
         if(er > 0.7)       { voteTrendStrong += 20; }
         else if(er > 0.5)  { voteTrendWeak   += 15; voteTrendStrong += 5; }
         else if(er < 0.2)  { voteRanging     += 20; }
         else               { voteRanging     += 10; voteVolatile    += 10; }

         // --- Add Fractal votes ---
         if(fracH > 0.65)       { voteTrendStrong += 20; }
         else if(fracH > 0.55)  { voteTrendWeak   += 20; }
         else if(fracH < 0.40)  { voteRanging     += 20; }
         else                   { voteVolatile    += 10; voteRanging += 10; }
      }

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

      // ── Upgrade 1: Rolling Mode Buffer ──────────────────────────
      if(m_useRollingMode)
      {
         m_regimeBuffer[m_bufHead] = (int)candidate;
         m_bufHead = (m_bufHead + 1) % 20;
         if(m_bufFilled < 20) m_bufFilled++;

         // Compute mode (most frequent regime in buffer)
         int counts[5] = {0,0,0,0,0};
         for(int _i = 0; _i < m_bufFilled; _i++)
            counts[m_regimeBuffer[_i]]++;

         int modeRegime = (int)candidate;
         int modeCount  = 0;
         for(int _r = 0; _r < 5; _r++)
            if(counts[_r] > modeCount) { modeCount = counts[_r]; modeRegime = _r; }

         // Per-regime minimum confirmation
         int minConf[5] = {8, 6, 5, 4, 2}; // TREND_STRONG, TREND_WEAK, RANGING, VOLATILE, CRISIS
         if(counts[modeRegime] < minConf[modeRegime])
            modeRegime = (int)m_lastRegime; // not enough confirmation, stick with last

         candidate = (MARKET_REGIME)modeRegime;
      }

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
