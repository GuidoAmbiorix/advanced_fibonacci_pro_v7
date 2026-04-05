//+------------------------------------------------------------------+
//|                                         AdaptiveExitManager.mqh   |
//|                 Dynamic TP/SL/Trail Based on Learned Behavior     |
//|                                  Copyright 2026, Infernal Portfolio Governor   |
//+------------------------------------------------------------------+
#ifndef ADAPTIVE_EXIT_MANAGER_MQH
#define ADAPTIVE_EXIT_MANAGER_MQH

#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

#include "../Learning_MFE_MAE.mqh"
#include "../MarketRegime.mqh"
#include "../KillzoneConfig.mqh"

//+------------------------------------------------------------------+
//| EXIT PARAMETERS STRUCTURE                                         |
//+------------------------------------------------------------------+
struct ExitParameters
{
   double   trailStartR;         // When to start trailing (in R)
   double   trailDistanceATR;    // Trail distance (ATR multiplier)
   double   beThresholdR;        // Break-even threshold (in R)
   double   partialTPR;          // Partial TP level (in R)
   double   partialPercent;      // % to close at partial TP

   ExitParameters() : trailStartR(2.0), trailDistanceATR(1.2),
                      beThresholdR(1.8), partialTPR(1.5), partialPercent(40.0) {}
};

//+------------------------------------------------------------------+
//| ADAPTIVE EXIT MANAGER CLASS                                       |
//| Responsibility: Dynamic exit management based on learned MFE/MAE |
//+------------------------------------------------------------------+
class CAdaptiveExitManager
{
private:
   string            m_symbol;
   CLearningEngine*  m_learning;
   bool              m_adaptationEnabled;
   int               m_minSampleSize;

   // Base parameters
   ExitParameters    m_baseParams;

   // Symbol-specific learned adjustments
   double            m_symbolVolatilityMultiplier;

public:
   CAdaptiveExitManager() : m_symbol(""), m_learning(NULL),
                            m_adaptationEnabled(false), m_minSampleSize(50),
                            m_symbolVolatilityMultiplier(1.0) {}

   //+------------------------------------------------------------------+
   //| Initialize Adaptive Exit Manager                                 |
   //+------------------------------------------------------------------+
   bool Init(string symbol, CLearningEngine* learningEngine,
             ExitParameters &baseParams, bool enableAdaptation = false)
   {
      m_symbol = symbol;
      m_learning = learningEngine;
      m_baseParams = baseParams;
      m_adaptationEnabled = enableAdaptation;

      if(m_learning == NULL)
      {
         Print("AdaptiveExitManager ERROR: Learning engine pointer is NULL");
         return false;
      }

      // Calculate symbol-specific volatility multiplier
      CalculateSymbolMultiplier();

      Print("AdaptiveExitManager initialized: ", m_symbol,
            " | Vol Mult: ", DoubleToString(m_symbolVolatilityMultiplier, 2),
            " | Adaptation: ", m_adaptationEnabled ? "ENABLED" : "DISABLED");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate Adaptive Trail Start                                   |
   //+------------------------------------------------------------------+
   double CalculateTrailStart(MARKET_REGIME mktRegime, ENTRY_QUALITY quality, double atr)
   {
      // Start with base
      double trailStartR = m_baseParams.trailStartR;

      if(!m_adaptationEnabled)
         return trailStartR;

      // Adjust by regime
      switch(mktRegime)
      {
         case REGIME_TREND:
            trailStartR *= 1.2;  // Trail later in trends (let winners run)
            break;
         case REGIME_RANGE:
            trailStartR *= 0.85;  // Trail earlier in ranges
            break;
         case REGIME_VOLATILE:
            trailStartR *= 1.1;  // Trail slightly later in volatility
            break;
      }

      // Adjust by entry quality
      switch(quality)
      {
         case EQ_ELITE:
            trailStartR *= 1.15;  // Let elite setups run further
            break;
         case EQ_STRONG:
            trailStartR *= 1.08;
            break;
         case EQ_GOOD:
            trailStartR *= 1.0;
            break;
         case EQ_WEAK:
            trailStartR *= 0.9;  // Trail earlier on weak entries
            break;
      }

      // Use learned MFE if available
      double avgMFE = m_learning.GetAvgMFE();
      if(avgMFE > 0 && atr > 0)
      {
         double learnedStartR = (avgMFE / atr) * 0.6;  // Start at 60% of avg MFE
         if(learnedStartR > 1.0 && learnedStartR < 4.0)  // Sanity check
         {
            // Blend with calculated value
            trailStartR = (trailStartR + learnedStartR) / 2.0;
         }
      }

      // Clamp to reasonable range
      if(trailStartR < 1.0) trailStartR = 1.0;
      if(trailStartR > 4.0) trailStartR = 4.0;

      return trailStartR;
   }

   //+------------------------------------------------------------------+
   //| Calculate Adaptive Trail Distance                                |
   //+------------------------------------------------------------------+
   double CalculateTrailDistance(MARKET_REGIME mktRegime, double atr)
   {
      // Start with base
      double trailMult = m_baseParams.trailDistanceATR;

      if(!m_adaptationEnabled)
         return trailMult * atr;

      // Apply symbol volatility adjustment
      trailMult *= m_symbolVolatilityMultiplier;

      // Adjust by regime
      switch(mktRegime)
      {
         case REGIME_TREND:
            trailMult *= 1.4;  // Wider trail in trends
            break;
         case REGIME_RANGE:
            trailMult *= 0.9;  // Tighter trail in ranges
            break;
         case REGIME_VOLATILE:
            trailMult *= 1.3;  // Wider trail in volatility
            break;
      }

      // Use learned MFE for optimal trail distance
      double avgMFE = m_learning.GetAvgMFE();
      if(avgMFE > 0)
      {
         double learnedTrail = m_learning.GetLearnedTrail(atr);
         if(learnedTrail > 0)
         {
            // Blend with calculated value
            double calculatedTrail = trailMult * atr;
            return (calculatedTrail + learnedTrail) / 2.0;
         }
      }

      return trailMult * atr;
   }

   //+------------------------------------------------------------------+
   //| Calculate Adaptive Break-Even Threshold                          |
   //+------------------------------------------------------------------+
   double CalculateBEThreshold(ENTRY_QUALITY quality, double riskPoints)
   {
      // Start with base
      double beR = m_baseParams.beThresholdR;

      if(!m_adaptationEnabled)
         return beR;

      // Adjust by entry quality
      switch(quality)
      {
         case EQ_ELITE:
            beR *= 1.1;  // Move BE later for elite setups
            break;
         case EQ_STRONG:
            beR *= 1.05;
            break;
         case EQ_GOOD:
            beR *= 1.0;
            break;
         case EQ_WEAK:
            beR *= 0.85;  // Move BE earlier for weak entries
            break;
      }

      // Use learned MAE to set optimal BE
      double learnedBE = m_learning.GetLearnedBE(riskPoints);
      if(learnedBE > 0)
      {
         // Blend with calculated value
         beR = (beR + learnedBE) / 2.0;
      }

      // Clamp to reasonable range
      if(beR < 0.8) beR = 0.8;
      if(beR > 2.5) beR = 2.5;

      return beR;
   }

   //+------------------------------------------------------------------+
   //| Calculate Adaptive Partial TP Level                              |
   //+------------------------------------------------------------------+
   double CalculatePartialTPR(MARKET_REGIME mktRegime, ENTRY_QUALITY quality)
   {
      // Start with base
      double partialR = m_baseParams.partialTPR;

      if(!m_adaptationEnabled)
         return partialR;

      // Adjust by regime
      switch(mktRegime)
      {
         case REGIME_TREND:
            partialR *= 1.15;  // Take partial later in trends
            break;
         case REGIME_RANGE:
            partialR *= 0.9;   // Take partial earlier in ranges
            break;
         case REGIME_VOLATILE:
            partialR *= 1.0;
            break;
      }

      // Adjust by quality
      switch(quality)
      {
         case EQ_ELITE:
            partialR *= 1.1;
            break;
         case EQ_STRONG:
            partialR *= 1.05;
            break;
         case EQ_GOOD:
            partialR *= 1.0;
            break;
         case EQ_WEAK:
            partialR *= 0.9;   // Take profits earlier on weak entries
            break;
      }

      // Clamp to reasonable range
      if(partialR < 1.0) partialR = 1.0;
      if(partialR > 2.5) partialR = 2.5;

      return partialR;
   }

   //+------------------------------------------------------------------+
   //| Calculate Adaptive Partial Close Percent                         |
   //+------------------------------------------------------------------+
   double CalculatePartialPercent(MARKET_REGIME mktRegime, ENTRY_QUALITY quality)
   {
      // Start with base
      double percent = m_baseParams.partialPercent;

      if(!m_adaptationEnabled)
         return percent;

      // Adjust by regime
      switch(mktRegime)
      {
         case REGIME_TREND:
            percent *= 0.8;  // Close less in trends (let more run)
            break;
         case REGIME_RANGE:
            percent *= 1.1;  // Close more in ranges
            break;
         case REGIME_VOLATILE:
            percent *= 1.0;
            break;
      }

      // Adjust by quality
      switch(quality)
      {
         case EQ_ELITE:
            percent *= 0.85;  // Let more run on elite setups
            break;
         case EQ_STRONG:
            percent *= 0.95;
            break;
         case EQ_GOOD:
            percent *= 1.0;
            break;
         case EQ_WEAK:
            percent *= 1.15;  // Close more on weak entries
            break;
      }

      // Clamp to reasonable range
      if(percent < 25.0) percent = 25.0;
      if(percent > 60.0) percent = 60.0;

      return percent;
   }

   //+------------------------------------------------------------------+
   //| Get Complete Exit Parameters                                     |
   //+------------------------------------------------------------------+
   ExitParameters GetAdaptiveParameters(MARKET_REGIME mktRegime, ENTRY_QUALITY quality,
                                         double atr, double riskPoints)
   {
      ExitParameters params;

      params.trailStartR = CalculateTrailStart(mktRegime, quality, atr);
      params.trailDistanceATR = CalculateTrailDistance(mktRegime, atr) / atr;  // Convert back to multiplier
      params.beThresholdR = CalculateBEThreshold(quality, riskPoints);
      params.partialTPR = CalculatePartialTPR(mktRegime, quality);
      params.partialPercent = CalculatePartialPercent(mktRegime, quality);

      return params;
   }

   //+------------------------------------------------------------------+
   //| Should Use Fixed TP Instead of Trail                             |
   //+------------------------------------------------------------------+
   bool ShouldUseFixedTP(MARKET_REGIME mktRegime, ENTRY_QUALITY quality)
   {
      if(!m_adaptationEnabled)
         return false;

      // Use fixed TP in ranging markets with weaker entries
      if(mktRegime == REGIME_RANGE && (quality == EQ_WEAK || quality == EQ_GOOD))
         return true;

      // Use fixed TP in highly volatile conditions
      if(mktRegime == REGIME_VOLATILE)
         return true;

      return false;
   }

   //+------------------------------------------------------------------+
   //| Calculate Fixed TP Level                                         |
   //+------------------------------------------------------------------+
   double CalculateFixedTP(MARKET_REGIME mktRegime, ENTRY_QUALITY quality, double atr)
   {
      double tpR = 2.0;  // Default 2R

      if(!m_adaptationEnabled)
         return tpR;

      // Use learned MFE as TP target
      double avgMFE = m_learning.GetAvgMFE();
      if(avgMFE > 0 && atr > 0)
      {
         tpR = (avgMFE / atr) * 0.75;  // 75% of average MFE
      }

      // Adjust by regime
      switch(mktRegime)
      {
         case REGIME_TREND:
            tpR *= 1.3;
            break;
         case REGIME_RANGE:
            tpR *= 0.85;
            break;
         case REGIME_VOLATILE:
            tpR *= 1.1;
            break;
      }

      // Adjust by quality
      switch(quality)
      {
         case EQ_ELITE:   tpR *= 1.2; break;
         case EQ_STRONG:  tpR *= 1.1; break;
         case EQ_GOOD:    tpR *= 1.0; break;
         case EQ_WEAK:    tpR *= 0.8; break;
      }

      // Clamp to reasonable range
      if(tpR < 1.2) tpR = 1.2;
      if(tpR > 4.0) tpR = 4.0;

      return tpR;
   }

   //+------------------------------------------------------------------+
   //| Get Adjustment Summary for Dashboard                             |
   //+------------------------------------------------------------------+
   string GetAdjustmentSummary(MARKET_REGIME mktRegime)
   {
      if(!m_adaptationEnabled)
         return "Exit Adaptation: OFF";

      string txt = "Exit Adjustments:\n";

      double avgMFE = m_learning.GetAvgMFE();
      double avgMAE = m_learning.GetAvgMAE();

      txt += "Learned MFE: " + DoubleToString(avgMFE, 5);
      txt += " | MAE: " + DoubleToString(avgMAE, 5) + "\n";

      // Show regime adjustment
      string regimeAdj = "Regime: ";
      switch(mktRegime)
      {
         case REGIME_TREND:    regimeAdj += "TREND (Wider trail)"; break;
         case REGIME_RANGE:    regimeAdj += "RANGE (Tighter)"; break;
         case REGIME_VOLATILE: regimeAdj += "VOLATILE (Wider)"; break;
         default:              regimeAdj += "UNKNOWN"; break;
      }
      txt += regimeAdj;

      return txt;
   }

   //+------------------------------------------------------------------+
   //| Calculate Reference Price for Chandelier Exit                    |
   //+------------------------------------------------------------------+
   double CalculateChandelierExit(int period, double atr, int direction, double mult)
   {
      // direction: 0 = Buy, 1 = Sell
      if(direction == 0) // Buy: Hang from Highest High
      {
         int highestIndex = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, period, 1);
         if(highestIndex < 0) return 0.0;
         double highestHigh = iHigh(m_symbol, PERIOD_CURRENT, highestIndex);
         return highestHigh - (atr * mult);
      }
      else // Sell: Hang from Lowest Low
      {
         int lowestIndex = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, period, 1);
         if(lowestIndex < 0) return 0.0;
         double lowestLow = iLow(m_symbol, PERIOD_CURRENT, lowestIndex);
         return lowestLow + (atr * mult);
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Step Trailing Stop                                     |
   //+------------------------------------------------------------------+
   double CalculateStepTrail(double current_sl, double proposed_sl, double atr, double stepFactor, int direction)
   {
      if(current_sl == 0.0) return proposed_sl;

      double stepSize = atr * stepFactor;
      
      if(direction == 0) // Buy: proposed must be higher
      {
         if(proposed_sl > current_sl + stepSize) return proposed_sl;
         return current_sl;
      }
      else // Sell: proposed must be lower
      {
         if(proposed_sl < current_sl - stepSize) return proposed_sl;
         return current_sl;
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Volatility-Based Take Profit                           |
   //+------------------------------------------------------------------+
   double CalculateVolatilityTP(double entry_price, double atr, int direction, double multiplier)
   {
      double volTP = 0.0;
      if(direction == 0) // Buy
         volTP = entry_price + (atr * multiplier);
      else // Sell
         volTP = entry_price - (atr * multiplier);
         
      return volTP;
   }

   //+------------------------------------------------------------------+
   //| Enable/Disable Adaptation                                        |
   //+------------------------------------------------------------------+
   void EnableAdaptation(bool enable) { m_adaptationEnabled = enable; }
   bool IsAdaptationEnabled() { return m_adaptationEnabled; }

private:
   //+------------------------------------------------------------------+
   //| Calculate Symbol-Specific Volatility Multiplier                  |
   //+------------------------------------------------------------------+
   void CalculateSymbolMultiplier()
   {
      string sym = m_symbol;
      StringToUpper(sym);

      // Indices are more volatile - wider trails
      if(StringFind(sym, "NAS") >= 0 || StringFind(sym, "USTEC") >= 0)
         m_symbolVolatilityMultiplier = 1.4;
      else if(StringFind(sym, "US30") >= 0 || StringFind(sym, "US500") >= 0)
         m_symbolVolatilityMultiplier = 1.3;
      // Metals
      else if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
         m_symbolVolatilityMultiplier = 1.25;
      else if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
         m_symbolVolatilityMultiplier = 1.3;
      // JPY pairs - tighter trails
      else if(StringFind(sym, "JPY") >= 0)
         m_symbolVolatilityMultiplier = 0.9;
      // GBP pairs - slightly wider
      else if(StringFind(sym, "GBP") >= 0)
         m_symbolVolatilityMultiplier = 1.1;
      // Default majors
      else
         m_symbolVolatilityMultiplier = 1.0;
   }
};

#endif
