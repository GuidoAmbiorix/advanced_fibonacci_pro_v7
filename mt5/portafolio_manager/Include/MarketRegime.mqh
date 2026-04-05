//+------------------------------------------------------------------+
//|                                                MarketRegime.mqh  |
//|                                  Copyright 2026, Infernal Portfolio Governor  |
//|                                     https://www.mql5.com |
//+------------------------------------------------------------------+
#ifndef MARKET_REGIME_MQH
#define MARKET_REGIME_MQH

#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

enum MARKET_REGIME
{
   REGIME_UNKNOWN  = -1,
   REGIME_TREND    = 0,
   REGIME_RANGE    = 1,
   REGIME_VOLATILE = 2,
   REGIME_CHAOS    = 3
};

//+------------------------------------------------------------------+
//| MARKET REGIME MODULE                                              |
//| Responsibility: "What is the current market environment?"        |
//+------------------------------------------------------------------+
class CMarketRegime
{
public:
   MARKET_REGIME Detect(double currentATR, double avgATR, double currentEMA, double prevEMA)
   {
      // 1. Check for Chaos (High Volatility Expansion)
      if(currentATR > avgATR * 1.5)
         return REGIME_CHAOS;

      // 2. Check for Trend (EMA Slope)
      double emaSlope = MathAbs(currentEMA - prevEMA);
      if(emaSlope > 0.1 * avgATR) // Significant slope
         return REGIME_TREND;

      // 3. RANGE DETECTION
      // Compressed volatility or flat slope
      double atrRatio = (avgATR > 0) ? currentATR / avgATR : 1.0;
      if(atrRatio < 0.9 || emaSlope < (currentATR * 0.05))
         return REGIME_RANGE;

      return REGIME_RANGE; // Default
   }

   //+------------------------------------------------------------------+
   //| PHASE 3: Get regime-adaptive confluence weights                   |
   //+------------------------------------------------------------------+
   void GetAdaptiveWeights(MARKET_REGIME regimeType, double &weights[])
   {
      // weights[0] = Trend weight
      // weights[1] = Structure weight
      // weights[2] = Price action weight
      // weights[3] = Volume weight
      // weights[4] = MTF weight

      ArrayResize(weights, 5);

      switch(regimeType)
      {
         case REGIME_TREND:
            // In trends: Emphasize MTF alignment and momentum
            weights[0] = 1.3;  // Boost trend following
            weights[1] = 0.8;  // Reduce structure importance
            weights[2] = 1.0;  // Normal price action
            weights[3] = 1.2;  // Boost volume (confirms trend)
            weights[4] = 1.4;  // Strong boost to MTF alignment
            break;

         case REGIME_RANGE:
            // In ranges: Emphasize structure and mean reversion
            weights[0] = 0.7;  // Reduce trend following
            weights[1] = 1.4;  // Strong boost to structure (OB, FVG)
            weights[2] = 1.3;  // Boost price action (reversals)
            weights[3] = 0.9;  // Reduce volume weight
            weights[4] = 0.8;  // Reduce MTF (HTF may be ranging)
            break;

         case REGIME_VOLATILE:
         case REGIME_CHAOS:
            // In chaos: Conservative, require multiple confirmations
            weights[0] = 0.9;
            weights[1] = 1.1;
            weights[2] = 0.8;
            weights[3] = 1.0;
            weights[4] = 1.2;  // Rely more on HTF for direction
            break;

         default:
            // Unknown/Neutral: Equal weights
            weights[0] = 1.0;
            weights[1] = 1.0;
            weights[2] = 1.0;
            weights[3] = 1.0;
            weights[4] = 1.0;
            break;
      }
   }

   //+------------------------------------------------------------------+
   //| PHASE 3: Calculate time-based score decay                         |
   //+------------------------------------------------------------------+
   double GetTimeDecayFactor(datetime signalTime, int maxAgeBars = 5)
   {
      datetime currentTime = TimeCurrent();
      long ageSeconds = currentTime - signalTime;

      // Calculate bar age (approximate)
      long barPeriod = PeriodSeconds(PERIOD_CURRENT);
      int barAge = (int)(ageSeconds / barPeriod);

      if(barAge >= maxAgeBars) return 0.1; // Very old signal, minimal weight

      // Linear decay: 1.0 at bar 0, down to 0.1 at maxAgeBars
      double decayFactor = 1.0 - (0.9 * (double)barAge / (double)maxAgeBars);

      return MathMax(decayFactor, 0.1); // Minimum 10% weight
   }

   string RegimeToString(MARKET_REGIME r)
   {
      switch(r)
      {
         case REGIME_TREND:    return "TRENDING";
         case REGIME_RANGE:    return "RANGING";
         case REGIME_VOLATILE: return "VOLATILE";
         case REGIME_CHAOS:    return "CHAOS";
         default:              return "UNKNOWN";
      }
   }
};

#endif
