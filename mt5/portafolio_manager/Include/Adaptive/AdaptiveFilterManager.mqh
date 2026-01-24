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
};

#endif
