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

   // FIX: Rolling window tracking (Phase 5 - last 20 trades)
   double                m_recentResults[20];      // Circular buffer for recent trade results (1=win, 0=loss)
   int                   m_recentTradeCount;       // Total trades processed
   int                   m_bufferHead;             // Current position in circular buffer
   double                m_lastThreshold;          // Last calculated threshold for logging

public:
   CAdaptiveFilterManager() : m_symbol(""), m_patternRecognizer(NULL),
                              m_performanceAnalyzer(NULL),
                              m_adaptationEnabled(false), m_minSampleSize(50),
                              m_baseMinConfluence(5.0), m_strictMinConfluence(6.0),
                              m_relaxedMinConfluence(4.0),
                              m_recentTradeCount(0), m_bufferHead(0), m_lastThreshold(0)
   {
      // FIX: Initialize rolling window buffer (Phase 5)
      ArrayFill(m_recentResults, 0, 20, 0);
   }

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

      // FIX: Add rolling window performance adjustment (Phase 5)
      if(m_recentTradeCount >= 10)  // Need at least 10 trades for rolling stats
      {
         double rollingWR = GetRollingWinRate();

         // Weight: 60% recent performance, 40% lifetime stats
         if(rollingWR > 0.60)
         {
            // Recent performance is strong → lower threshold (allow more entries)
            threshold -= 1.0;
            if(m_recentTradeCount % 20 == 0)
               Print("✅ ", m_symbol, " - Lowering threshold: Rolling WR ", DoubleToString(rollingWR * 100, 1), "% (good)");
         }
         else if(rollingWR < 0.40)
         {
            // Recent performance is weak → raise threshold (stricter filtering)
            threshold += 1.5;
            if(m_recentTradeCount % 20 == 0)
               Print("⚠ ", m_symbol, " - Raising threshold: Rolling WR ", DoubleToString(rollingWR * 100, 1), "% (poor)");
         }
      }

      // Clamp to reasonable range
      // FIX: Use dynamic max based on user input to allow higher thresholds (e.g. 12)
      double maxClamp = MathMax(7.0, m_baseMinConfluence + 3.0);
      
      if(threshold < 3.5) threshold = 3.5;         // Never too lenient
      if(threshold > maxClamp) threshold = maxClamp;   // Respect user's high base setting

      // Store for logging comparison
      m_lastThreshold = threshold;

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
   //| FIX: Update Recent Performance (Phase 5 - Rolling window)        |
   //+------------------------------------------------------------------+
   void UpdateRecentPerformance(double tradeResult)
   {
      // Store in circular buffer (1 = win, 0 = loss)
      m_recentResults[m_bufferHead] = (tradeResult > 0) ? 1.0 : 0.0;
      m_bufferHead = (m_bufferHead + 1) % 20;  // Circular buffer
      m_recentTradeCount++;

      // Log threshold changes every 20 trades
      if(m_recentTradeCount % 20 == 0)
      {
         double rollingWR = GetRollingWinRate();
         Print("📊 ", m_symbol, " - ", m_recentTradeCount, " trades | Rolling WR (20): ",
               DoubleToString(rollingWR * 100, 1), "%");
      }
   }

   //+------------------------------------------------------------------+
   //| Check if Volatility is Safe for Entry                            |
   //+------------------------------------------------------------------+
   bool IsVolatilitySafe(double current_atr, double min_atr_pips, double max_atr_factor, double avg_atr)
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      
      // 1. Check for Dead Market (Too low volatility)
      if(min_atr_pips > 0)
      {
          double minDelta = min_atr_pips * point * 10; // Convert pips to price delta
          if(current_atr < minDelta)
          {
             return false; 
          }
      }

      // 2. Check for Extreme Volatility (Crash/Spike risk)
      if(max_atr_factor > 0 && avg_atr > 0)
      {
         if(current_atr > avg_atr * max_atr_factor)
         {
            return false;
         }
      }

      return true;
   }


   //+------------------------------------------------------------------+
   //| Get Rolling Win Rate (last 20 trades)                            |
   //+------------------------------------------------------------------+
   double GetRollingWinRate()
   {
      int count = (m_recentTradeCount < 20) ? m_recentTradeCount : 20;
      if(count == 0) return 0;

      double wins = 0;
      for(int i = 0; i < count; i++)
      {
         wins += m_recentResults[i];
      }

      return wins / count;
   }
};

#endif
