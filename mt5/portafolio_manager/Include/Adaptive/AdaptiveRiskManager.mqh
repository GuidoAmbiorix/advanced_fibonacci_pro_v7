//+------------------------------------------------------------------+
//|                                        AdaptiveRiskManager.mqh   |
//|                  Context-Aware Dynamic Position Sizing            |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef ADAPTIVE_RISK_MANAGER_MQH
#define ADAPTIVE_RISK_MANAGER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "../Learning/PerformanceAnalyzer.mqh"
#include "../Learning/PatternRecognizer.mqh"
#include "../Memory/PatternMemory.mqh"
#include "../KillzoneConfig.mqh"
#include "../MarketRegime.mqh"

//+------------------------------------------------------------------+
//| ADAPTIVE RISK MANAGER CLASS                                       |
//| Responsibility: Dynamically adjust position sizing based on      |
//|                 learned performance by context                    |
//+------------------------------------------------------------------+
class CAdaptiveRiskManager
{
private:
   string                m_symbol;
   CPerformanceAnalyzer* m_performanceAnalyzer;
   CPatternRecognizer*   m_patternRecognizer;
   double                m_baseRisk;           // Base risk %
   double                m_minRisk;            // Minimum allowed risk
   double                m_maxRisk;            // Maximum allowed risk
   bool                  m_adaptationEnabled;
   int                   m_minSampleSize;      // Min trades before adapting

   // Recent performance tracking
   double                m_recentPerformanceMultiplier;
   datetime              m_lastUpdate;

public:
   CAdaptiveRiskManager() : m_symbol(""), m_performanceAnalyzer(NULL),
                            m_patternRecognizer(NULL), m_baseRisk(0.25),
                            m_minRisk(0.1), m_maxRisk(0.5),
                            m_adaptationEnabled(false), m_minSampleSize(50),
                            m_recentPerformanceMultiplier(1.0), m_lastUpdate(0) {}

   //+------------------------------------------------------------------+
   //| Initialize Adaptive Risk Manager                                 |
   //+------------------------------------------------------------------+
   bool Init(string symbol, CPerformanceAnalyzer* perfAnalyzer,
             CPatternRecognizer* patternRecog, double baseRisk,
             double minRisk = 0.1, double maxRisk = 0.5,
             bool enableAdaptation = false)
   {
      m_symbol = symbol;
      m_performanceAnalyzer = perfAnalyzer;
      m_patternRecognizer = patternRecog;
      m_baseRisk = baseRisk;
      m_minRisk = minRisk;
      m_maxRisk = maxRisk;
      m_adaptationEnabled = enableAdaptation;

      if(m_performanceAnalyzer == NULL)
      {
         Print("AdaptiveRiskManager ERROR: PerformanceAnalyzer pointer is NULL");
         return false;
      }

      if(m_patternRecognizer == NULL)
      {
         Print("AdaptiveRiskManager ERROR: PatternRecognizer pointer is NULL");
         return false;
      }

      Print("AdaptiveRiskManager initialized: ", m_symbol,
            " | Base Risk: ", DoubleToString(m_baseRisk, 2), "%",
            " | Adaptation: ", m_adaptationEnabled ? "ENABLED" : "DISABLED");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate Adaptive Risk for Entry                                |
   //+------------------------------------------------------------------+
   double CalculateAdaptiveRisk(ENUM_KILLZONE killzone, MARKET_REGIME mktRegime,
                                 ConfluenceFactors &factors, ENUM_ENTRY_TIER quality)
   {
      // Start with base risk
      double risk = m_baseRisk;

      // If adaptation disabled, return base risk only
      if(!m_adaptationEnabled)
         return risk;

      // Check if we have enough data
      if(!m_performanceAnalyzer.IsLearningActive())
         return risk;

      // Apply killzone multiplier
      double killzoneMultiplier = GetKillzoneMultiplier(killzone);
      risk *= killzoneMultiplier;

      // Apply regime multiplier
      double regimeMultiplier = GetRegimeMultiplier(mktRegime);
      risk *= regimeMultiplier;

      // Apply pattern multiplier
      double patternMultiplier = m_patternRecognizer.GetRecommendedRiskMultiplier(factors);
      risk *= patternMultiplier;

      // Apply entry quality multiplier
      double qualityMultiplier = GetQualityMultiplier(quality);
      risk *= qualityMultiplier;

      // Apply recent performance multiplier
      UpdateRecentPerformance();
      risk *= m_recentPerformanceMultiplier;

      // Clamp to safe limits
      if(risk < m_minRisk) risk = m_minRisk;
      if(risk > m_maxRisk) risk = m_maxRisk;

      return risk;
   }

   //+------------------------------------------------------------------+
   //| Calculate Risk for Add-On Position                               |
   //+------------------------------------------------------------------+
   double CalculateAddOnRisk(ENUM_KILLZONE killzone, MARKET_REGIME mktRegime,
                             ConfluenceFactors &factors, int addOnLevel)
   {
      // Add-ons are more conservative
      double baseAddOnRisk = m_baseRisk * (addOnLevel == 1 ? 0.6 : 0.4);

      if(!m_adaptationEnabled)
         return baseAddOnRisk;

      if(!m_performanceAnalyzer.IsLearningActive())
         return baseAddOnRisk;

      // Apply same multipliers but more conservatively
      double killzoneMultiplier = GetKillzoneMultiplier(killzone);
      double regimeMultiplier = GetRegimeMultiplier(mktRegime);
      double patternMultiplier = m_patternRecognizer.GetRecommendedRiskMultiplier(factors);

      // Average the multipliers (more conservative)
      double avgMultiplier = (killzoneMultiplier + regimeMultiplier + patternMultiplier) / 3.0;

      double risk = baseAddOnRisk * avgMultiplier;

      // Tighter limits for add-ons
      double minAddOnRisk = m_minRisk * 0.5;
      double maxAddOnRisk = m_maxRisk * 0.7;

      if(risk < minAddOnRisk) risk = minAddOnRisk;
      if(risk > maxAddOnRisk) risk = maxAddOnRisk;

      return risk;
   }

   //+------------------------------------------------------------------+
   //| Should Skip Trade Based on Poor Context Performance              |
   //+------------------------------------------------------------------+
   bool ShouldSkipTrade(ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      if(!m_adaptationEnabled) return false;
      if(!m_performanceAnalyzer.IsLearningActive()) return false;

      // Check killzone performance
      ContextStats kzStats = m_performanceAnalyzer.GetStatsByKillzone(killzone);
      if(kzStats.tradeCount >= m_minSampleSize)
      {
         // Skip if killzone has consistent negative expectancy
         if(kzStats.expectancy < -0.2 && kzStats.winRate < 0.40)
         {
            Print("AdaptiveRisk: Skipping trade - Poor killzone performance (E: ",
                  DoubleToString(kzStats.expectancy, 2), "R)");
            return true;
         }
      }

      // Check regime performance
      ContextStats regStats = m_performanceAnalyzer.GetStatsByRegime(mktRegime);
      if(regStats.tradeCount >= m_minSampleSize)
      {
         // Skip if regime has very negative expectancy
         if(regStats.expectancy < -0.3 && regStats.winRate < 0.35)
         {
            Print("AdaptiveRisk: Skipping trade - Poor regime performance (E: ",
                  DoubleToString(regStats.expectancy, 2), "R)");
            return true;
         }
      }

      // Check combined context
      ContextStats contextStats = m_performanceAnalyzer.GetStatsByContext(killzone, mktRegime);
      if(contextStats.tradeCount >= 20)  // Lower threshold for combined
      {
         // Skip if specific context is very bad
         if(contextStats.expectancy < -0.4 && contextStats.winRate < 0.30)
         {
            Print("AdaptiveRisk: Skipping trade - Poor context combination (E: ",
                  DoubleToString(contextStats.expectancy, 2), "R)");
            return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get Risk Adjustment Summary for Dashboard                        |
   //+------------------------------------------------------------------+
   string GetAdjustmentSummary(ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      if(!m_adaptationEnabled)
         return "Adaptation: OFF";

      if(!m_performanceAnalyzer.IsLearningActive())
         return "Adaptation: Collecting Data";

      string txt = "Risk Adjustments:\n";

      // Killzone adjustment
      double kzMult = GetKillzoneMultiplier(killzone);
      txt += "Killzone: " + DoubleToString((kzMult - 1.0) * 100, 0) + "%";

      // Regime adjustment
      double regMult = GetRegimeMultiplier(mktRegime);
      txt += " | Regime: " + DoubleToString((regMult - 1.0) * 100, 0) + "%\n";

      // Recent performance
      txt += "Recent Perf: " + DoubleToString((m_recentPerformanceMultiplier - 1.0) * 100, 0) + "%";

      return txt;
   }

   //+------------------------------------------------------------------+
   //| Enable/Disable Adaptation                                        |
   //+------------------------------------------------------------------+
   void EnableAdaptation(bool enable) { m_adaptationEnabled = enable; }
   bool IsAdaptationEnabled() { return m_adaptationEnabled; }

private:
   //+------------------------------------------------------------------+
   //| Get Killzone Performance Multiplier                              |
   //+------------------------------------------------------------------+
   double GetKillzoneMultiplier(ENUM_KILLZONE killzone)
   {
      ContextStats stats = m_performanceAnalyzer.GetStatsByKillzone(killzone);

      if(stats.tradeCount < m_minSampleSize)
         return 1.0;  // Not enough data

      // Scale risk based on expectancy
      if(stats.expectancy > 0.8) return 1.25;      // Exceptional
      if(stats.expectancy > 0.6) return 1.15;      // Excellent
      if(stats.expectancy > 0.4) return 1.10;      // Strong
      if(stats.expectancy > 0.2) return 1.0;       // Good
      if(stats.expectancy > 0) return 0.9;         // Marginal
      if(stats.expectancy > -0.1) return 0.75;     // Slightly negative
      return 0.5;                                   // Poor
   }

   //+------------------------------------------------------------------+
   //| Get Regime Performance Multiplier                                |
   //+------------------------------------------------------------------+
   double GetRegimeMultiplier(MARKET_REGIME mktRegime)
   {
      ContextStats stats = m_performanceAnalyzer.GetStatsByRegime(mktRegime);

      if(stats.tradeCount < m_minSampleSize)
         return 1.0;  // Not enough data

      // Scale risk based on expectancy
      if(stats.expectancy > 0.8) return 1.20;      // Exceptional
      if(stats.expectancy > 0.6) return 1.12;      // Excellent
      if(stats.expectancy > 0.4) return 1.08;      // Strong
      if(stats.expectancy > 0.2) return 1.0;       // Good
      if(stats.expectancy > 0) return 0.92;        // Marginal
      if(stats.expectancy > -0.1) return 0.8;      // Slightly negative
      return 0.6;                                   // Poor
   }

   //+------------------------------------------------------------------+
   //| Get Entry Quality Multiplier                                     |
   //+------------------------------------------------------------------+
   double GetQualityMultiplier(ENUM_ENTRY_TIER quality)
   {
      ContextStats stats = m_performanceAnalyzer.GetStatsByQuality(quality);

      if(stats.tradeCount < 20)  // Lower threshold for quality
      {
         // Use default scaling if not enough data
         switch(quality)
         {
            case TIER_ELITE:  return 1.2;
            case TIER_STRONG: return 1.1;
            case TIER_GOOD:   return 1.0;
            case TIER_WEAK:   return 0.7;
            default:        return 1.0;
         }
      }

      // Use learned performance
      if(stats.expectancy > 0.7) return 1.25;
      if(stats.expectancy > 0.5) return 1.15;
      if(stats.expectancy > 0.3) return 1.08;
      if(stats.expectancy > 0.1) return 1.0;
      if(stats.expectancy > 0) return 0.9;
      if(stats.expectancy > -0.1) return 0.75;
      return 0.6;
   }

   //+------------------------------------------------------------------+
   //| Update Recent Performance Multiplier                             |
   //+------------------------------------------------------------------+
   void UpdateRecentPerformance()
   {
      // Update only once per hour
      if(TimeCurrent() - m_lastUpdate < 3600)
         return;

      m_lastUpdate = TimeCurrent();

      // Get overall stats
      ContextStats overall = m_performanceAnalyzer.GetOverallStats();

      if(overall.tradeCount < 30)
      {
         m_recentPerformanceMultiplier = 1.0;
         return;
      }

      // Adjust based on recent win rate and expectancy
      // Winning streak - increase risk slightly
      if(overall.winRate > 0.65 && overall.expectancy > 0.5)
      {
         m_recentPerformanceMultiplier = 1.08;
      }
      // Solid performance - slight increase
      else if(overall.winRate > 0.55 && overall.expectancy > 0.3)
      {
         m_recentPerformanceMultiplier = 1.04;
      }
      // Breakeven - neutral
      else if(overall.expectancy > 0.1)
      {
         m_recentPerformanceMultiplier = 1.0;
      }
      // Slight drawdown - reduce
      else if(overall.expectancy > -0.1)
      {
         m_recentPerformanceMultiplier = 0.92;
      }
      // Losing streak - reduce significantly
      else
      {
         m_recentPerformanceMultiplier = 0.75;
      }
   }
};

#endif
