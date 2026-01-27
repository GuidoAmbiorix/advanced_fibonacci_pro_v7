//+------------------------------------------------------------------+
//|                                        PerformanceAnalyzer.mqh   |
//|                   Context-Aware Performance Analytics            |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef PERFORMANCE_ANALYZER_MQH
#define PERFORMANCE_ANALYZER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "../Memory/TradeJournal.mqh"

//+------------------------------------------------------------------+
//| CONTEXT STATISTICS STRUCTURE                                      |
//+------------------------------------------------------------------+
struct ContextStats
{
   int      tradeCount;
   int      wins;
   int      losses;
   double   winRate;
   double   avgRWin;
   double   avgRLoss;
   double   avgR;
   double   expectancy;
   double   profitFactor;
   double   maxConsecutiveWins;
   double   maxConsecutiveLosses;

   // Initialize
   ContextStats() : tradeCount(0), wins(0), losses(0), winRate(0),
                    avgRWin(0), avgRLoss(0), avgR(0), expectancy(0),
                    profitFactor(0), maxConsecutiveWins(0), maxConsecutiveLosses(0) {}
};

//+------------------------------------------------------------------+
//| PERFORMANCE ANALYZER CLASS                                        |
//| Responsibility: Analyze trades by context (killzone, regime, etc)|
//+------------------------------------------------------------------+
class CPerformanceAnalyzer
{
private:
   string         m_symbol;
   CTradeJournal* m_journal;              // Reference to trade journal
   TradeRecord    m_trades[];             // Cached trades for analysis
   int            m_tradeCount;
   int            m_minSampleSize;        // Minimum trades for reliable stats

public:
   CPerformanceAnalyzer() : m_symbol(""), m_journal(NULL), m_tradeCount(0),
                            m_minSampleSize(20) {}

   //+------------------------------------------------------------------+
   //| Initialize Performance Analyzer                                   |
   //+------------------------------------------------------------------+
   bool Init(string symbol, CTradeJournal* journal, int minSampleSize = 20)
   {
      m_symbol = symbol;
      m_journal = journal;
      m_minSampleSize = minSampleSize;

      if(m_journal == NULL)
      {
         Print("PerformanceAnalyzer ERROR: Journal pointer is NULL");
         return false;
      }

      // Load trades from journal
      RefreshData();

      Print("PerformanceAnalyzer initialized: ", m_tradeCount, " trades loaded");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Refresh data from journal                                        |
   //+------------------------------------------------------------------+
   void RefreshData()
   {
      if(m_journal == NULL) return;

      // Get all closed trades from journal
      m_journal.GetTrades(m_trades);
      m_tradeCount = ArraySize(m_trades);
   }

   //+------------------------------------------------------------------+
   //| Get statistics by killzone                                       |
   //+------------------------------------------------------------------+
   ContextStats GetStatsByKillzone(ENUM_KILLZONE killzone)
   {
      ContextStats stats;

      for(int i = 0; i < m_tradeCount; i++)
      {
         if(m_trades[i].entry.killzone == killzone)
         {
            AddTradeToStats(m_trades[i], stats);
         }
      }

      FinalizeStats(stats);
      return stats;
   }

   //+------------------------------------------------------------------+
   //| Get statistics by market regime                                  |
   //+------------------------------------------------------------------+
   ContextStats GetStatsByRegime(MARKET_REGIME mktRegime)
   {
      ContextStats stats;

      for(int i = 0; i < m_tradeCount; i++)
      {
         if(m_trades[i].entry.regime == mktRegime)
         {
            AddTradeToStats(m_trades[i], stats);
         }
      }

      FinalizeStats(stats);
      return stats;
   }

   //+------------------------------------------------------------------+
   //| Get statistics by day of week                                    |
   //+------------------------------------------------------------------+
   ContextStats GetStatsByDayOfWeek(int dayOfWeek)
   {
      ContextStats stats;

      for(int i = 0; i < m_tradeCount; i++)
      {
         if(m_trades[i].entry.dayOfWeek == dayOfWeek)
         {
            AddTradeToStats(m_trades[i], stats);
         }
      }

      FinalizeStats(stats);
      return stats;
   }

   //+------------------------------------------------------------------+
   //| Get statistics by entry quality                                  |
   //+------------------------------------------------------------------+
   ContextStats GetStatsByQuality(ENUM_ENTRY_TIER quality)
   {
      ContextStats stats;

      for(int i = 0; i < m_tradeCount; i++)
      {
         if(m_trades[i].entry.quality == quality)
         {
            AddTradeToStats(m_trades[i], stats);
         }
      }

      FinalizeStats(stats);
      return stats;
   }

   //+------------------------------------------------------------------+
   //| Get statistics by confluence score range                         |
   //+------------------------------------------------------------------+
   ContextStats GetStatsByConfluenceRange(double minScore, double maxScore)
   {
      ContextStats stats;

      for(int i = 0; i < m_tradeCount; i++)
      {
         double score = m_trades[i].entry.confluenceScore;
         if(score >= minScore && score < maxScore)
         {
            AddTradeToStats(m_trades[i], stats);
         }
      }

      FinalizeStats(stats);
      return stats;
   }

   //+------------------------------------------------------------------+
   //| Get statistics by combined context                               |
   //+------------------------------------------------------------------+
   ContextStats GetStatsByContext(ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      ContextStats stats;

      for(int i = 0; i < m_tradeCount; i++)
      {
         if(m_trades[i].entry.killzone == killzone &&
            m_trades[i].entry.regime == mktRegime)
         {
            AddTradeToStats(m_trades[i], stats);
         }
      }

      FinalizeStats(stats);
      return stats;
   }

   //+------------------------------------------------------------------+
   //| Get overall statistics                                           |
   //+------------------------------------------------------------------+
   ContextStats GetOverallStats()
   {
      ContextStats stats;

      for(int i = 0; i < m_tradeCount; i++)
      {
         AddTradeToStats(m_trades[i], stats);
      }

      FinalizeStats(stats);
      return stats;
   }

   //+------------------------------------------------------------------+
   //| Get expectancy for specific context                              |
   //+------------------------------------------------------------------+
   double GetExpectancy(ENUM_KILLZONE killzone, MARKET_REGIME mktRegime)
   {
      ContextStats stats = GetStatsByContext(killzone, mktRegime);
      return stats.expectancy;
   }

   //+------------------------------------------------------------------+
   //| Get best killzone (by expectancy)                                |
   //+------------------------------------------------------------------+
   ENUM_KILLZONE GetBestKillzone()
   {
      ENUM_KILLZONE best = KILLZONE_NONE;
      double bestExpectancy = -999;

      ENUM_KILLZONE killzones[] = {KILLZONE_ASIAN, KILLZONE_LONDON_OPEN,
                                    KILLZONE_NY, KILLZONE_LONDON_CLOSE};

      for(int i = 0; i < ArraySize(killzones); i++)
      {
         ContextStats stats = GetStatsByKillzone(killzones[i]);

         if(stats.tradeCount >= m_minSampleSize && stats.expectancy > bestExpectancy)
         {
            bestExpectancy = stats.expectancy;
            best = killzones[i];
         }
      }

      return best;
   }

   //+------------------------------------------------------------------+
   //| Get best regime (by expectancy)                                  |
   //+------------------------------------------------------------------+
   MARKET_REGIME GetBestRegime()
   {
      MARKET_REGIME best = REGIME_UNKNOWN;
      double bestExpectancy = -999;

      MARKET_REGIME regimes[] = {REGIME_TREND, REGIME_RANGE, REGIME_VOLATILE};

      for(int i = 0; i < ArraySize(regimes); i++)
      {
         ContextStats stats = GetStatsByRegime(regimes[i]);

         if(stats.tradeCount >= m_minSampleSize && stats.expectancy > bestExpectancy)
         {
            bestExpectancy = stats.expectancy;
            best = regimes[i];
         }
      }

      return best;
   }

   //+------------------------------------------------------------------+
   //| Get optimal risk multiplier for context                          |
   //+------------------------------------------------------------------+
   double GetOptimalRiskMultiplier(ENUM_KILLZONE killzone)
   {
      ContextStats stats = GetStatsByKillzone(killzone);

      if(stats.tradeCount < m_minSampleSize)
         return 1.0;  // Not enough data, use default

      // Adjust multiplier based on expectancy
      if(stats.expectancy > 0.6) return 1.2;      // Excellent
      if(stats.expectancy > 0.4) return 1.0;      // Good
      if(stats.expectancy > 0.2) return 0.8;      // Fair
      if(stats.expectancy > 0) return 0.6;        // Marginal
      return 0.5;                                  // Negative expectancy
   }

   //+------------------------------------------------------------------+
   //| Check if learning is active (enough data)                        |
   //+------------------------------------------------------------------+
   bool IsLearningActive()
   {
      return (m_tradeCount >= m_minSampleSize);
   }

   //+------------------------------------------------------------------+
   //| Get total trade count                                            |
   //+------------------------------------------------------------------+
   int GetTradeCount() { return m_tradeCount; }

   //+------------------------------------------------------------------+
   //| Get statistics string for dashboard                              |
   //+------------------------------------------------------------------+
   string GetStatsString()
   {
      if(m_tradeCount < m_minSampleSize)
      {
         return "Collecting data: " + IntegerToString(m_tradeCount) + "/" +
                IntegerToString(m_minSampleSize) + " trades";
      }

      ContextStats overall = GetOverallStats();
      ENUM_KILLZONE bestKZ = GetBestKillzone();
      MARKET_REGIME bestRegime = GetBestRegime();

      string txt = "Win Rate: " + DoubleToString(overall.winRate * 100, 1) + "% | ";
      txt += "Avg R: " + DoubleToString(overall.avgR, 2) + " | ";
      txt += "Expect: " + DoubleToString(overall.expectancy, 3) + "R\n";
      txt += "Best KZ: " + KillzoneToString(bestKZ) + " | ";
      txt += "Best Regime: " + IntegerToString((int)bestRegime);

      return txt;
   }

private:
   //+------------------------------------------------------------------+
   //| Add single trade to statistics                                   |
   //+------------------------------------------------------------------+
   void AddTradeToStats(TradeRecord &tradeRec, ContextStats &stats)
   {
      stats.tradeCount++;

      double profitR = tradeRec.exit.profitR;

      if(profitR > 0)
      {
         stats.wins++;
         stats.avgRWin += profitR;
      }
      else
      {
         stats.losses++;
         stats.avgRLoss += MathAbs(profitR);
      }

      stats.avgR += profitR;
   }

   //+------------------------------------------------------------------+
   //| Finalize statistics calculations                                 |
   //+------------------------------------------------------------------+
   void FinalizeStats(ContextStats &stats)
   {
      if(stats.tradeCount == 0) return;

      // Calculate averages
      stats.winRate = (double)stats.wins / stats.tradeCount;
      stats.avgR = stats.avgR / stats.tradeCount;

      if(stats.wins > 0)
         stats.avgRWin = stats.avgRWin / stats.wins;

      if(stats.losses > 0)
         stats.avgRLoss = stats.avgRLoss / stats.losses;

      // Calculate expectancy: (Win% * Avg Win) - (Loss% * Avg Loss)
      double lossRate = 1.0 - stats.winRate;
      stats.expectancy = (stats.winRate * stats.avgRWin) - (lossRate * stats.avgRLoss);

      // Calculate profit factor: Gross Profit / Gross Loss
      double grossProfit = stats.wins * stats.avgRWin;
      double grossLoss = stats.losses * stats.avgRLoss;

      if(grossLoss > 0)
         stats.profitFactor = grossProfit / grossLoss;
      else
         stats.profitFactor = (grossProfit > 0) ? 999 : 0;
   }
};

#endif
