//+------------------------------------------------------------------+
//|                                       AdaptiveFilterManager.mqh   |
//|                  Smart Entry Filtering with Pattern Learning      |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef ADAPTIVE_FILTER_MANAGER_MQH
#define ADAPTIVE_FILTER_MANAGER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "../PortfolioGlobals.mqh"
#include "../Learning/PatternRecognizer.mqh"
#include "../Learning/PerformanceAnalyzer.mqh"
#include "../Memory/PatternMemory.mqh"

//+------------------------------------------------------------------+
//| FILTER DECISION STRUCTURE                                         |
//+------------------------------------------------------------------+
struct FilterDecision
{
   bool     allowEntry;             // Final decision
   double   adjustedConfluence;     // Confluence after pattern bonus/penalty
   double   patternBonus;           // Bonus/penalty applied
   double   minThreshold;           // Dynamic minimum threshold
   string   reason;                 // Reason if entry blocked

   FilterDecision() : allowEntry(true), adjustedConfluence(0),
                      patternBonus(0), minThreshold(5.0), reason("") {}
};

//+------------------------------------------------------------------+
//| ADAPTIVE FILTER MANAGER CLASS                                     |
//| Responsibility: Smart entry filtering using learned patterns     |
//+------------------------------------------------------------------+
class CAdaptiveFilterManager
{
private:
   string                m_symbol;
   CPatternRecognizer*   m_patternRecognizer;
   CPerformanceAnalyzer* m_performanceAnalyzer;
   bool                  m_adaptationEnabled;
   int                   m_minSampleSize;

   // Thresholds
   double                m_baseMinConfluence;
   double                m_strictMinConfluence;
   double                m_relaxedMinConfluence;

public:
   CAdaptiveFilterManager() : m_symbol(""), m_patternRecognizer(NULL),
                              m_performanceAnalyzer(NULL),
                              m_adaptationEnabled(false), m_minSampleSize(50),
                              m_baseMinConfluence(5.0), m_strictMinConfluence(6.0),
                              m_relaxedMinConfluence(4.0) {}

   //+------------------------------------------------------------------+
   //| Initialize Adaptive Filter Manager                               |
   //+------------------------------------------------------------------+
   bool Init(string symbol, CPatternRecognizer* patternRecog,
             CPerformanceAnalyzer* perfAnalyzer,
             double baseMinConfluence = 5.0, bool enableAdaptation = false)
   {
      m_symbol = symbol;
      m_patternRecognizer = patternRecog;
      m_performanceAnalyzer = perfAnalyzer;
      m_baseMinConfluence = baseMinConfluence;
      m_adaptationEnabled = enableAdaptation;

      m_strictMinConfluence = m_baseMinConfluence + 1.0;
      m_relaxedMinConfluence = m_baseMinConfluence - 1.0;

      if(m_patternRecognizer == NULL)
      {
         Print("AdaptiveFilterManager ERROR: PatternRecognizer pointer is NULL");
         return false;
      }

      if(m_performanceAnalyzer == NULL)
      {
         Print("AdaptiveFilterManager ERROR: PerformanceAnalyzer pointer is NULL");
         return false;
      }

      Print("AdaptiveFilterManager initialized: ", m_symbol,
            " | Base Confluence: ", DoubleToString(m_baseMinConfluence, 1),
            " | Adaptation: ", m_adaptationEnabled ? "ENABLED" : "DISABLED");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Evaluate Entry with Adaptive Filtering                           |
   //+------------------------------------------------------------------+
   FilterDecision EvaluateEntry(double rawConfluence, ConfluenceFactors &factors,
                                 ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      FilterDecision decision;
      decision.adjustedConfluence = rawConfluence;

      // If adaptation disabled, use base threshold
      if(!m_adaptationEnabled)
      {
         decision.minThreshold = m_baseMinConfluence;
         decision.allowEntry = (rawConfluence >= decision.minThreshold);
         if(!decision.allowEntry)
            decision.reason = "Below minimum confluence";
         return decision;
      }

      // Check if we have enough learning data
      if(!m_performanceAnalyzer.IsLearningActive())
      {
         decision.minThreshold = m_baseMinConfluence;
         decision.allowEntry = (rawConfluence >= decision.minThreshold);
         if(!decision.allowEntry)
            decision.reason = "Below minimum (Learning inactive)";
         return decision;
      }

      // Get pattern bonus/penalty
      decision.patternBonus = m_patternRecognizer.GetPatternBonus(factors);
      decision.adjustedConfluence = rawConfluence + decision.patternBonus;

      // Calculate dynamic minimum threshold
      decision.minThreshold = CalculateDynamicThreshold(factors, killzone, mktRegime);

      // Make decision
      decision.allowEntry = (decision.adjustedConfluence >= decision.minThreshold);

      if(!decision.allowEntry)
      {
         decision.reason = "Adjusted confluence " + DoubleToString(decision.adjustedConfluence, 1) +
                          " < threshold " + DoubleToString(decision.minThreshold, 1);
      }

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Should Take Entry (Simplified)                                   |
   //+------------------------------------------------------------------+
   bool ShouldTakeEntry(double rawConfluence, ConfluenceFactors &factors,
                        ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      FilterDecision decision = EvaluateEntry(rawConfluence, factors, killzone, mktRegime);
      return decision.allowEntry;
   }

   //+------------------------------------------------------------------+
   //| Get Adjusted Confluence Score                                    |
   //+------------------------------------------------------------------+
   double GetAdjustedConfluence(double rawConfluence, ConfluenceFactors &factors)
   {
      if(!m_adaptationEnabled)
         return rawConfluence;

      double patternBonus = m_patternRecognizer.GetPatternBonus(factors);
      return rawConfluence + patternBonus;
   }

   //+------------------------------------------------------------------+
   //| Calculate Dynamic Minimum Confluence Threshold                   |
   //+------------------------------------------------------------------+
   double CalculateDynamicThreshold(ConfluenceFactors &factors,
                                     ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      double threshold = m_baseMinConfluence;

      if(!m_adaptationEnabled)
         return threshold;

      // Check if pattern is high probability
      if(m_patternRecognizer.IsHighProbabilitySetup(factors))
      {
         // Lower threshold for proven patterns
         threshold = m_relaxedMinConfluence;
      }
      else
      {
         // Check pattern expectancy
         double expectancy = m_patternRecognizer.GetPatternExpectancy(factors);

         if(expectancy < -0.2)
         {
            // Raise threshold for weak patterns
            threshold = m_strictMinConfluence;
         }
         else if(expectancy > 0.4)
         {
            // Lower threshold for solid patterns
            threshold = m_baseMinConfluence - 0.5;
         }
      }

      // Adjust threshold by killzone performance
      ContextStats kzStats = m_performanceAnalyzer.GetStatsByKillzone(killzone);
      if(kzStats.tradeCount >= m_minSampleSize)
      {
         if(kzStats.expectancy < 0)
            threshold += 0.5;  // Stricter in poor killzones
         else if(kzStats.expectancy > 0.6)
            threshold -= 0.3;  // More lenient in excellent killzones
      }

      // Adjust threshold by regime performance
      ContextStats regStats = m_performanceAnalyzer.GetStatsByRegime(mktRegime);
      if(regStats.tradeCount >= m_minSampleSize)
      {
         if(regStats.expectancy < 0)
            threshold += 0.5;  // Stricter in poor regimes
         else if(regStats.expectancy > 0.5)
            threshold -= 0.3;  // More lenient in good regimes
      }

      // Clamp to reasonable range
      if(threshold < 3.5) threshold = 3.5;   // Never too lenient
      if(threshold > 7.0) threshold = 7.0;   // Never too strict

      return threshold;
   }

   //+------------------------------------------------------------------+
   //| Should Skip Low Quality Pattern                                  |
   //+------------------------------------------------------------------+
   bool ShouldSkipPattern(ConfluenceFactors &factors)
   {
      if(!m_adaptationEnabled)
         return false;

      if(!m_performanceAnalyzer.IsLearningActive())
         return false;

      // Check pattern expectancy
      double expectancy = m_patternRecognizer.GetPatternExpectancy(factors);

      // Skip if pattern has strong negative expectancy
      if(expectancy < -0.3)
      {
         Print("AdaptiveFilter: Skipping known weak pattern (E: ",
               DoubleToString(expectancy, 2), "R)");
         return true;
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get Recommended Entry Quality Adjustment                         |
   //+------------------------------------------------------------------+
   ENTRY_QUALITY GetAdjustedQuality(ENTRY_QUALITY baseQuality, ConfluenceFactors &factors)
   {
      if(!m_adaptationEnabled)
         return baseQuality;

      if(!m_performanceAnalyzer.IsLearningActive())
         return baseQuality;

      // Check if high probability pattern
      if(m_patternRecognizer.IsHighProbabilitySetup(factors))
      {
         // Upgrade quality
         if(baseQuality == EQ_GOOD) return EQ_STRONG;
         if(baseQuality == EQ_STRONG) return EQ_ELITE;
      }
      else
      {
         // Check pattern expectancy
         double expectancy = m_patternRecognizer.GetPatternExpectancy(factors);

         if(expectancy < -0.1 && expectancy > -999)  // Known negative pattern
         {
            // Downgrade quality
            if(baseQuality == EQ_ELITE) return EQ_STRONG;
            if(baseQuality == EQ_STRONG) return EQ_GOOD;
            if(baseQuality == EQ_GOOD) return EQ_WEAK;
         }
      }

      return baseQuality;
   }

   //+------------------------------------------------------------------+
   //| Get Filter Status String for Dashboard                           |
   //+------------------------------------------------------------------+
   string GetFilterStatus(ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      if(!m_adaptationEnabled)
         return "Adaptive Filters: OFF";

      if(!m_performanceAnalyzer.IsLearningActive())
         return "Adaptive Filters: Collecting Data";

      string txt = "Adaptive Filters: ACTIVE\n";

      // Current threshold
      ConfluenceFactors dummyFactors;  // Empty factors for generic threshold
      dummyFactors.killzone = killzone;
      dummyFactors.regime = mktRegime;
      double currentThreshold = CalculateDynamicThreshold(dummyFactors, killzone, mktRegime);

      txt += "Current Threshold: " + DoubleToString(currentThreshold, 1) + "/12";

      return txt;
   }

   //+------------------------------------------------------------------+
   //| Get Entry Recommendation String                                  |
   //+------------------------------------------------------------------+
   string GetRecommendation(FilterDecision &decision)
   {
      string txt = "";

      if(decision.allowEntry)
      {
         txt = "ENTRY APPROVED";
         if(decision.patternBonus > 0)
            txt += " (Pattern bonus: +" + DoubleToString(decision.patternBonus, 1) + ")";
      }
      else
      {
         txt = "ENTRY BLOCKED: " + decision.reason;
         if(decision.patternBonus < 0)
            txt += " (Pattern penalty: " + DoubleToString(decision.patternBonus, 1) + ")";
      }

      return txt;
   }

   //+------------------------------------------------------------------+
   //| Enable/Disable Adaptation                                        |
   //+------------------------------------------------------------------+
   void EnableAdaptation(bool enable) { m_adaptationEnabled = enable; }
   bool IsAdaptationEnabled() { return m_adaptationEnabled; }

   //+------------------------------------------------------------------+
   //| Set Base Minimum Confluence                                      |
   //+------------------------------------------------------------------+
   void SetBaseMinConfluence(double minConfluence)
   {
      m_baseMinConfluence = minConfluence;
      m_strictMinConfluence = minConfluence + 1.0;
      m_relaxedMinConfluence = minConfluence - 1.0;
   }

   //+------------------------------------------------------------------+
   //| PHASE 3.3 ENHANCEMENTS: ADAPTIVE INDICATORS                     |
   //+------------------------------------------------------------------+

   //+------------------------------------------------------------------+
   //| Calculate Dominant Cycle using Autocorrelation                  |
   //+------------------------------------------------------------------+
   int CalculateDominantCycle(string symbol, ENUM_TIMEFRAMES timeframe, int maxPeriod = 50)
   {
      double prices[];
      ArraySetAsSeries(prices, true);

      int copied = CopyClose(symbol, timeframe, 0, maxPeriod * 2, prices);
      if(copied < maxPeriod * 2) return 14; // Default fallback

      double maxCorrelation = -1;
      int dominantPeriod = 14;

      // Test periods from 8 to maxPeriod
      for(int period = 8; period <= maxPeriod; period++)
      {
         double correlation = CalculateAutocorrelation(prices, period);

         if(correlation > maxCorrelation)
         {
            maxCorrelation = correlation;
            dominantPeriod = period;
         }
      }

      return dominantPeriod;
   }

   //+------------------------------------------------------------------+
   //| Calculate Autocorrelation for given lag                         |
   //+------------------------------------------------------------------+
   double CalculateAutocorrelation(double &data[], int lag)
   {
      int n = ArraySize(data) - lag;
      if(n <= 0) return 0;

      // Calculate mean
      double mean = 0;
      for(int i = 0; i < n; i++)
         mean += data[i];
      mean /= n;

      // Calculate autocorrelation
      double numerator = 0;
      double denominator = 0;

      for(int i = 0; i < n; i++)
      {
         numerator += (data[i] - mean) * (data[i + lag] - mean);
         denominator += (data[i] - mean) * (data[i] - mean);
      }

      if(denominator == 0) return 0;

      return numerator / denominator;
   }

   //+------------------------------------------------------------------+
   //| Get Adaptive RSI Period (0.5x cycle length)                     |
   //+------------------------------------------------------------------+
   int GetAdaptiveRSIPeriod(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      int cycle = CalculateDominantCycle(symbol, timeframe, 50);

      // RSI period = 0.5 * cycle length
      int adaptiveRSI = (int)(cycle * 0.5);

      // Clamp to reasonable range
      if(adaptiveRSI < 7) adaptiveRSI = 7;
      if(adaptiveRSI > 28) adaptiveRSI = 28;

      return adaptiveRSI;
   }

   //+------------------------------------------------------------------+
   //| Get Adaptive EMA Period based on Volatility Regime              |
   //+------------------------------------------------------------------+
   int GetAdaptiveEMAPeriod(string symbol, ENUM_TIMEFRAMES timeframe, MARKET_REGIME regime)
   {
      int basePeriod = 200; // Standard long-term EMA

      // Calculate current volatility
      double atr[];
      ArraySetAsSeries(atr, true);

      int hATR = iATR(symbol, timeframe, 14);
      if(hATR == INVALID_HANDLE) return basePeriod;

      if(CopyBuffer(hATR, 0, 0, 20, atr) < 20)
      {
         IndicatorRelease(hATR);
         return basePeriod;
      }

      IndicatorRelease(hATR);

      // Calculate average ATR
      double avgATR = 0;
      for(int i = 0; i < 20; i++)
         avgATR += atr[i];
      avgATR /= 20;

      // Adjust EMA period based on regime
      int adaptiveEMA = basePeriod;

      if(regime == MR_TRENDING_HIGH_VOL || regime == MR_TRENDING_LOW_VOL)
      {
         // Faster EMA in trending markets
         adaptiveEMA = (int)(basePeriod * 0.75); // 150
      }
      else if(regime == MR_RANGING_HIGH_VOL)
      {
         // Slower EMA in choppy high vol
         adaptiveEMA = (int)(basePeriod * 1.25); // 250
      }
      else if(regime == MR_RANGING_LOW_VOL)
      {
         // Standard in ranging low vol
         adaptiveEMA = basePeriod; // 200
      }

      // Clamp to reasonable range
      if(adaptiveEMA < 100) adaptiveEMA = 100;
      if(adaptiveEMA > 300) adaptiveEMA = 300;

      return adaptiveEMA;
   }

   //+------------------------------------------------------------------+
   //| Get Adaptive Indicator Periods                                  |
   //+------------------------------------------------------------------+
   void GetAdaptivePeriods(string symbol, ENUM_TIMEFRAMES timeframe, MARKET_REGIME regime,
                          int &rsiPeriod, int &emaPeriod)
   {
      rsiPeriod = GetAdaptiveRSIPeriod(symbol, timeframe);
      emaPeriod = GetAdaptiveEMAPeriod(symbol, timeframe, regime);
   }

   //+------------------------------------------------------------------+
   //| Get Cycle Info for Dashboard                                    |
   //+------------------------------------------------------------------+
   string GetCycleInfo(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      string info = "=== ADAPTIVE INDICATORS ===\n";

      int cycle = CalculateDominantCycle(symbol, timeframe, 50);
      int adaptiveRSI = GetAdaptiveRSIPeriod(symbol, timeframe);

      info += StringFormat("Dominant Cycle: %d bars\n", cycle);
      info += StringFormat("Adaptive RSI: %d (vs 14 static)\n", adaptiveRSI);

      return info;
   }
};

#endif
