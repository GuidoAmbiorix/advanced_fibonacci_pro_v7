//+------------------------------------------------------------------+
//|                                          PatternRecognizer.mqh    |
//|                   High-Probability Setup Pattern Recognition      |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef PATTERN_RECOGNIZER_MQH
#define PATTERN_RECOGNIZER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "../Memory/PatternMemory.mqh"

//+------------------------------------------------------------------+
//| PATTERN RECOMMENDATION STRUCTURE                                  |
//+------------------------------------------------------------------+
struct PatternRecommendation
{
   bool     isKnownPattern;      // Pattern exists in database
   bool     isHighProbability;   // Pattern has high win rate
   double   expectancy;          // Expected R per trade
   double   winRate;             // Historical win rate
   double   confidenceBonus;     // Bonus to add to confluence score
   string   patternSignature;    // Pattern signature string
   int      sampleSize;          // Number of trades

   PatternRecommendation() : isKnownPattern(false), isHighProbability(false),
                             expectancy(0), winRate(0), confidenceBonus(0),
                             patternSignature(""), sampleSize(0) {}
};

//+------------------------------------------------------------------+
//| PATTERN RECOGNIZER CLASS                                          |
//| Responsibility: Identify high-probability setups from history    |
//+------------------------------------------------------------------+
class CPatternRecognizer
{
private:
   string            m_symbol;
   CPatternMemory*   m_patternMemory;  // Reference to pattern database
   int               m_minSampleSize;  // Min trades to trust pattern
   double            m_minWinRate;     // Min win rate for high-prob pattern
   double            m_minExpectancy;  // Min expectancy for high-prob pattern
   double            m_maxBonus;       // Max bonus to confluence score

public:
   CPatternRecognizer() : m_symbol(""), m_patternMemory(NULL),
                          m_minSampleSize(15), m_minWinRate(0.65),
                          m_minExpectancy(0.5), m_maxBonus(1.5) {}

   //+------------------------------------------------------------------+
   //| Initialize Pattern Recognizer                                    |
   //+------------------------------------------------------------------+
   bool Init(string symbol, CPatternMemory* pMemory,
             int minSampleSize = 15, double minWinRate = 0.65,
             double minExpectancy = 0.5)
   {
      m_symbol = symbol;
      m_patternMemory = pMemory;
      m_minSampleSize = minSampleSize;
      m_minWinRate = minWinRate;
      m_minExpectancy = minExpectancy;

      if(m_patternMemory == NULL)
      {
         Print("PatternRecognizer ERROR: PatternMemory pointer is NULL");
         return false;
      }

      Print("PatternRecognizer initialized: ", m_symbol,
            " | Min WR: ", DoubleToString(m_minWinRate * 100, 1), "%",
            " | Min E: ", DoubleToString(m_minExpectancy, 2), "R");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Analyze Pattern and Get Recommendation                           |
   //+------------------------------------------------------------------+
   PatternRecommendation AnalyzePattern(ConfluenceFactors &factors)
   {
      PatternRecommendation rec;
      PatternStats stats;

      // Check if pattern exists in database
      if(!m_patternMemory.GetStatsByFactors(factors, stats))
      {
         rec.isKnownPattern = false;
         return rec;  // Unknown pattern, no recommendation
      }

      rec.isKnownPattern = true;
      rec.patternSignature = stats.signature;
      rec.sampleSize = stats.tradeCount;
      rec.expectancy = stats.expectancy;
      rec.winRate = stats.winRate;

      // Check if pattern has sufficient sample size
      if(stats.tradeCount < m_minSampleSize)
      {
         return rec;  // Not enough data yet
      }

      // Check if pattern is high probability
      if(stats.winRate >= m_minWinRate && stats.expectancy >= m_minExpectancy)
      {
         rec.isHighProbability = true;

         // Calculate confidence bonus based on performance
         rec.confidenceBonus = CalculateBonus(stats);
      }
      else if(stats.expectancy < 0)
      {
         // Negative expectancy - apply penalty
         rec.confidenceBonus = CalculatePenalty(stats);
      }

      return rec;
   }

   //+------------------------------------------------------------------+
   //| Get Pattern Confidence Bonus                                     |
   //+------------------------------------------------------------------+
   double GetPatternBonus(ConfluenceFactors &factors)
   {
      PatternRecommendation rec = AnalyzePattern(factors);
      return rec.confidenceBonus;
   }

   //+------------------------------------------------------------------+
   //| Check if High Probability Setup                                  |
   //+------------------------------------------------------------------+
   bool IsHighProbabilitySetup(ConfluenceFactors &factors)
   {
      PatternRecommendation rec = AnalyzePattern(factors);
      return rec.isHighProbability;
   }

   //+------------------------------------------------------------------+
   //| Get Pattern Expectancy                                           |
   //+------------------------------------------------------------------+
   double GetPatternExpectancy(ConfluenceFactors &factors)
   {
      PatternRecommendation rec = AnalyzePattern(factors);
      return rec.expectancy;
   }

   //+------------------------------------------------------------------+
   //| Find Top Patterns in Database                                    |
   //+------------------------------------------------------------------+
   int FindTopPatterns(PatternStats &output[], int limit = 10)
   {
      return m_patternMemory.GetTopPatterns(output, limit);
   }

   //+------------------------------------------------------------------+
   //| Get Best Pattern Signature                                       |
   //+------------------------------------------------------------------+
   string GetBestPatternSignature()
   {
      PatternStats topPatterns[];
      int count = m_patternMemory.GetTopPatterns(topPatterns, 1);

      if(count == 0) return "None";

      return topPatterns[0].signature;
   }

   //+------------------------------------------------------------------+
   //| Get Pattern Database Statistics                                  |
   //+------------------------------------------------------------------+
   string GetStatsString()
   {
      int totalPatterns = m_patternMemory.GetPatternCount();
      int totalTrades = m_patternMemory.GetTotalTrades();

      if(totalPatterns == 0)
         return "No patterns learned yet";

      // Get top pattern
      PatternStats topPatterns[];
      int count = m_patternMemory.GetTopPatterns(topPatterns, 1);

      string txt = "Patterns: " + IntegerToString(totalPatterns) +
                   " | Trades: " + IntegerToString(totalTrades);

      if(count > 0)
      {
         txt += "\nTop: " + topPatterns[0].signature;
         txt += " (WR: " + DoubleToString(topPatterns[0].winRate * 100, 1) + "%";
         txt += ", E: " + DoubleToString(topPatterns[0].expectancy, 2) + "R)";
      }

      return txt;
   }

   //+------------------------------------------------------------------+
   //| Recommend Entry Based on Pattern                                 |
   //+------------------------------------------------------------------+
   bool ShouldTakeEntry(ConfluenceFactors &factors, double currentConfluence)
   {
      PatternRecommendation rec = AnalyzePattern(factors);

      // If unknown pattern, rely on current confluence only
      if(!rec.isKnownPattern)
         return (currentConfluence >= 5.0);  // Default threshold

      // If known pattern with negative expectancy, skip
      if(rec.sampleSize >= m_minSampleSize && rec.expectancy < 0)
         return false;

      // If high probability pattern, lower threshold
      if(rec.isHighProbability)
         return (currentConfluence >= 4.0);  // Lower threshold for proven patterns

      // If known pattern with positive expectancy but not "high prob"
      if(rec.sampleSize >= m_minSampleSize && rec.expectancy > 0.2)
         return (currentConfluence >= 4.5);

      // Default case
      return (currentConfluence >= 5.0);
   }

   //+------------------------------------------------------------------+
   //| Get Recommended Risk Multiplier for Pattern                      |
   //+------------------------------------------------------------------+
   double GetRecommendedRiskMultiplier(ConfluenceFactors &factors)
   {
      PatternRecommendation rec = AnalyzePattern(factors);

      // Unknown pattern - use default
      if(!rec.isKnownPattern || rec.sampleSize < m_minSampleSize)
         return 1.0;

      // Scale risk based on expectancy
      if(rec.expectancy > 0.8) return 1.3;      // Exceptional pattern
      if(rec.expectancy > 0.6) return 1.2;      // Excellent pattern
      if(rec.expectancy > 0.4) return 1.1;      // Strong pattern
      if(rec.expectancy > 0.2) return 1.0;      // Good pattern
      if(rec.expectancy > 0) return 0.8;        // Marginal pattern
      return 0.5;                                // Negative expectancy
   }

   //+------------------------------------------------------------------+
   //| Update Pattern Database (call after trade closes)                |
   //+------------------------------------------------------------------+
   void UpdatePatternDatabase(ConfluenceFactors &factors, double profitR)
   {
      if(m_patternMemory == NULL) return;

      m_patternMemory.RecordPattern(factors, profitR);
   }

private:
   //+------------------------------------------------------------------+
   //| Calculate Confidence Bonus for Strong Pattern                    |
   //+------------------------------------------------------------------+
   double CalculateBonus(PatternStats &stats)
   {
      // Bonus formula: Based on both win rate and expectancy
      // Higher performance = higher bonus

      double bonus = 0;

      // Win rate component (max 0.75 points)
      if(stats.winRate >= 0.75) bonus += 0.75;
      else if(stats.winRate >= 0.70) bonus += 0.60;
      else if(stats.winRate >= 0.65) bonus += 0.45;

      // Expectancy component (max 0.75 points)
      if(stats.expectancy >= 1.0) bonus += 0.75;
      else if(stats.expectancy >= 0.7) bonus += 0.60;
      else if(stats.expectancy >= 0.5) bonus += 0.45;
      else if(stats.expectancy >= 0.3) bonus += 0.30;

      // Sample size confidence (reduce bonus if low sample)
      double sampleConfidence = 1.0;
      if(stats.tradeCount < 30)
         sampleConfidence = (double)stats.tradeCount / 30.0;

      bonus *= sampleConfidence;

      // Cap at max bonus
      if(bonus > m_maxBonus) bonus = m_maxBonus;

      return bonus;
   }

   //+------------------------------------------------------------------+
   //| Calculate Penalty for Weak Pattern                               |
   //+------------------------------------------------------------------+
   double CalculatePenalty(PatternStats &stats)
   {
      // Penalty for patterns with negative expectancy
      // More negative = bigger penalty

      double penalty = 0;

      if(stats.expectancy < -0.5) penalty = -1.5;      // Very bad pattern
      else if(stats.expectancy < -0.3) penalty = -1.0; // Bad pattern
      else if(stats.expectancy < -0.1) penalty = -0.5; // Slightly negative
      else penalty = -0.25;                             // Marginally negative

      // Scale by sample size (more confident in penalty with more trades)
      double sampleConfidence = 1.0;
      if(stats.tradeCount < 30)
         sampleConfidence = (double)stats.tradeCount / 30.0;

      penalty *= sampleConfidence;

      return penalty;
   }
};

#endif
