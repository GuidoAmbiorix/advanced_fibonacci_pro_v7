//+------------------------------------------------------------------+
//|                                                  RankManager.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                         ENHANCED with MTF, Performance, Currency |
//+------------------------------------------------------------------+
#ifndef RANK_MANAGER_MQH
#define RANK_MANAGER_MQH

#include "PortfolioGlobals.mqh"
#include "PerformanceMetrics.mqh"
#include "CurrencyStrength.mqh"

//+------------------------------------------------------------------+
//| SYMBOL RANK STRUCTURE - ENHANCED                                 |
//+------------------------------------------------------------------+
struct SymbolRank
{
   string symbol;
   double score;
   double adjScore;          // Penalized Score
   double reqScore;
   double direction;         // 1.0 = Buy, -1.0 = Sell
   long   timeRemaining;     // Seconds to next bar
   bool   isKZOpen;          // Killzone active?
   int    rank;

   // ENHANCED: Multi-timeframe scores
   double scoreTF1;          // H1 score
   double scoreTF2;          // H4 score
   double scoreTF3;          // D1 score
   double mtfConfluence;     // 0-1.0 MTF alignment
   double mtfBonus;          // MTF multiplier applied

   // ENHANCED: Performance tracking
   double performanceMult;   // 0.7-1.3x based on recent performance
   double profitFactor;      // Recent PF
   double winRate;           // Recent win rate

   // ENHANCED: Currency strength
   double currencyDivergence;  // Currency strength divergence
   double currencyBonus;       // Currency strength multiplier

   // Phase 2: Original enhanced ranking fields
   double volatilityNormScore;
   double timeWeightedScore;
   double momentumFactor;
   datetime lastRankChange;
   int    consecutiveBars;
};

//+------------------------------------------------------------------+
//| RANK MANAGER CLASS - FULLY ENHANCED                              |
//+------------------------------------------------------------------+
class CRankManager
{
private:
   SymbolRank m_ranks[];
   SymbolRank m_prevRanks[];
   string     m_symbols[];
   int        m_symbolCount;

   // Ranking parameters
   double     m_hysteresisThreshold;
   int        m_hysteresisCooldown;
   int        m_minSlots;
   int        m_maxSlots;

   // Performance optimization: cached values
   double     m_cachedAtrAvg;
   datetime   m_atrCacheTime;
   PerformanceMetrics m_perfCache[];
   datetime   m_perfCacheTime[];

public:
   CRankManager() : m_symbolCount(0), m_hysteresisThreshold(0.5),
                    m_hysteresisCooldown(1), m_minSlots(2), m_maxSlots(10),
                    m_cachedAtrAvg(0), m_atrCacheTime(0) {}

   //+------------------------------------------------------------------+
   //| Get correlation using semantic correlation                       |
   //+------------------------------------------------------------------+
   double GetEnhancedCorrelation(string symbol1, string symbol2)
   {
      return GetSemanticCorrelation(symbol1, symbol2);
   }

   //+------------------------------------------------------------------+
   //| OPTIMIZED: Cached Pool ATR Average                               |
   //+------------------------------------------------------------------+
   double GetPoolAverageATR()
   {
      // Cache for 60 seconds
      if(TimeCurrent() - m_atrCacheTime >= 60)
      {
         double sum = 0;
         int count = 0;

         for(int i=0; i<m_symbolCount; i++)
         {
            double a = GlobalVariableGet("PG_ATR_" + m_symbols[i]);
            if(a > 0) { sum += a; count++; }
         }

         m_cachedAtrAvg = (count > 0) ? sum / count : 1.0;
         m_atrCacheTime = TimeCurrent();
      }

      return m_cachedAtrAvg;
   }

   //+------------------------------------------------------------------+
   //| OPTIMIZED: Cached Performance Metrics                            |
   //+------------------------------------------------------------------+
   PerformanceMetrics GetCachedPerformance(string symbol)
   {
      // Ensure cache arrays match symbol count
      if(ArraySize(m_perfCache) != m_symbolCount)
      {
         ArrayResize(m_perfCache, m_symbolCount);
         ArrayResize(m_perfCacheTime, m_symbolCount);
         ArrayInitialize(m_perfCacheTime, 0);
      }

      // Find symbol index
      int symIdx = -1;
      for(int i=0; i<m_symbolCount; i++)
      {
         if(m_symbols[i] == symbol)
         {
            symIdx = i;
            break;
         }
      }

      if(symIdx >= 0)
      {
         // Check if cache is fresh (< 5 minutes old)
         if(TimeCurrent() - m_perfCacheTime[symIdx] < 300 && m_perfCacheTime[symIdx] > 0)
            return m_perfCache[symIdx];

         // Cache expired or empty, recalculate
         m_perfCache[symIdx] = GetSymbolPerformance(symbol, 30);
         m_perfCacheTime[symIdx] = TimeCurrent();
         return m_perfCache[symIdx];
      }

      // Fallback: calculate without caching
      return GetSymbolPerformance(symbol, 30);
   }

   //+------------------------------------------------------------------+
   //| Discover Active Symbols (Auto-Discovery)                          |
   //+------------------------------------------------------------------+
   void DiscoverSymbols()
   {
      int totalGV = GlobalVariablesTotal();
      m_symbolCount = 0;

      for(int i=0; i<totalGV; i++)
      {
         string gvName = GlobalVariableName(i);

         if(StringFind(gvName, GV_SCORE_PREFIX) == 0)
         {
            string symbol = StringSubstr(gvName, StringLen(GV_SCORE_PREFIX));

            // GHOST SYMBOL GUARD
            if(!GlobalVariableCheck(GV_REQ_PREFIX + symbol)) continue;
            if(!GlobalVariableCheck(GV_DIR_PREFIX + symbol)) continue;

            m_symbolCount++;
            ArrayResize(m_symbols, m_symbolCount);
            ArrayResize(m_ranks, m_symbolCount);

            m_symbols[m_symbolCount-1] = symbol;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| ENHANCED: Calculate MTF Confluence                               |
   //+------------------------------------------------------------------+
   double CalculateMTFConfluence(string symbol)
   {
      // Read scores from each timeframe (if available)
      double h1Score = GlobalVariableGet("PG_Score_H1_" + symbol);
      double h4Score = GlobalVariableGet("PG_Score_H4_" + symbol);
      double d1Score = GlobalVariableGet("PG_Score_D1_" + symbol);

      // Read directions
      double h1Dir = GlobalVariableGet("PG_Dir_H1_" + symbol);
      double h4Dir = GlobalVariableGet("PG_Dir_H4_" + symbol);
      double d1Dir = GlobalVariableGet("PG_Dir_D1_" + symbol);

      // If no MTF data available, return neutral
      if(h4Score == 0 && d1Score == 0) return 0.5;

      // Count direction alignment
      int alignment = 0;
      int dirChecks = 0;

      if(h1Dir != 0 && h4Dir != 0)
      {
         if(h1Dir == h4Dir) alignment++;
         dirChecks++;
      }
      if(h1Dir != 0 && d1Dir != 0)
      {
         if(h1Dir == d1Dir) alignment++;
         dirChecks++;
      }
      if(h4Dir != 0 && d1Dir != 0)
      {
         if(h4Dir == d1Dir) alignment++;
         dirChecks++;
      }

      double directionAlignment = (dirChecks > 0) ? (double)alignment / dirChecks : 0;

      // Check score strength alignment
      double scoreAlignment = 0;
      int scoreChecks = 0;

      if(h1Score >= 12 && h4Score >= 12) { scoreAlignment += 1.0; scoreChecks++; }
      if(h1Score >= 12 && d1Score >= 12) { scoreAlignment += 1.0; scoreChecks++; }
      if(h4Score >= 12 && d1Score >= 12) { scoreAlignment += 1.0; scoreChecks++; }

      scoreAlignment = (scoreChecks > 0) ? scoreAlignment / scoreChecks : 0;

      // Combined confluence: 60% direction + 40% strength
      return (directionAlignment * 0.6) + (scoreAlignment * 0.4);
   }

   //+------------------------------------------------------------------+
   //| ENHANCED: Regime Multiplier with Volatility Context              |
   //+------------------------------------------------------------------+
   double GetEnhancedRegimeMultiplier(string symbol)
   {
      double regime = GlobalVariableGet("PG_Regime_" + symbol);
      double atr = GlobalVariableGet("PG_ATR_" + symbol);
      double atrAvg = GetPoolAverageATR();
      double atrRatio = (atrAvg > 0) ? atr / atrAvg : 1.0;

      // REGIME_TREND (0) - Best for trading
      if(regime == 0.0)
      {
         // High volatility trend = BEST opportunity
         if(atrRatio > 1.2)
            return 1.35; // 35% bonus

         // Normal volatility trend = GOOD
         return 1.15; // 15% bonus
      }

      // REGIME_RANGE (1) - Neutral
      if(regime == 1.0)
      {
         // Low volatility range = potential breakout
         if(atrRatio < 0.8)
            return 1.05; // 5% bonus

         return 1.0; // Neutral
      }

      // REGIME_TRANSITION (2) - Uncertain
      if(regime == 2.0)
         return 0.90; // 10% penalty

      // REGIME_CHAOS (3) - Avoid
      if(regime == 3.0)
         return 0.75; // 25% penalty

      return 1.0; // Fallback
   }

   //+------------------------------------------------------------------+
   //| Update Ranks (Main Engine) - FULLY ENHANCED                      |
   //+------------------------------------------------------------------+
   void UpdateRanks()
   {
      // 1. Discover Symbols
      static datetime lastDiscover = 0;
      if(TimeCurrent() - lastDiscover >= 60 || m_symbolCount == 0)
      {
         DiscoverSymbols();
         lastDiscover = TimeCurrent();
      }

      if(m_symbolCount == 0) return;

      // 2. Read Scores with ALL enhancements
      double atrAvg = GetPoolAverageATR();

      for(int i=0; i<m_symbolCount; i++)
      {
         string sym = m_symbols[i];

         double score = GlobalVariableGet(GV_SCORE_PREFIX + sym);
         double req   = GlobalVariableGet(GV_REQ_PREFIX + sym);
         double dir   = GlobalVariableGet(GV_DIR_PREFIX + sym);
         bool   kz    = (GlobalVariableGet(GV_KZ_PREFIX + sym) != 0.0);

         // Timer Calc
         datetime open = (datetime)GlobalVariableGet(GV_BAROPEN_PREFIX + sym);
         long period   = (long)GlobalVariableGet(GV_PERIOD_PREFIX + sym);
         long rem      = 0;

         if(open > 0 && period > 0)
         {
            rem = (open + period) - TimeCurrent();
            if(rem < 0) rem = 0;
         }

         m_ranks[i].symbol = sym;
         m_ranks[i].score = score;
         m_ranks[i].reqScore = req;
         m_ranks[i].direction = dir;
         m_ranks[i].timeRemaining = rem;
         m_ranks[i].isKZOpen = kz;

         // Volatility-normalized score
         double atr = GlobalVariableGet("PG_ATR_" + sym);
         double atrRatio = MathMax(0.5, MathMin(1.5, (atr > 0 ? atr / atrAvg : 1.0)));
         m_ranks[i].volatilityNormScore = score * atrRatio;

         m_ranks[i].timeWeightedScore = score;

         // Momentum factor
         m_ranks[i].momentumFactor = 0;
         for(int j=0; j<ArraySize(m_prevRanks); j++)
         {
            if(m_prevRanks[j].symbol == sym)
            {
               m_ranks[i].momentumFactor = score - m_prevRanks[j].score;
               m_ranks[i].consecutiveBars = m_prevRanks[j].consecutiveBars;
               m_ranks[i].lastRankChange = m_prevRanks[j].lastRankChange;
               break;
            }
         }

         // ENHANCEMENT 1: MTF Confluence
         m_ranks[i].scoreTF1 = score; // H1 (current)
         m_ranks[i].scoreTF2 = GlobalVariableGet("PG_Score_H4_" + sym);
         m_ranks[i].scoreTF3 = GlobalVariableGet("PG_Score_D1_" + sym);
         m_ranks[i].mtfConfluence = CalculateMTFConfluence(sym);
         m_ranks[i].mtfBonus = 1.0 + (m_ranks[i].mtfConfluence * 0.20); // 0-20% bonus

         // ENHANCEMENT 2: Performance-based multiplier
         PerformanceMetrics perf = GetCachedPerformance(sym);
         m_ranks[i].performanceMult = perf.performanceMult;
         m_ranks[i].profitFactor = perf.profitFactor;
         m_ranks[i].winRate = perf.winRate;

         // ENHANCEMENT 3: Currency strength
         double baseStr, quoteStr;
         m_ranks[i].currencyDivergence = CalculateCurrencyDivergence(sym, baseStr, quoteStr);

         // Currency bonus multiplier
         m_ranks[i].currencyBonus = 1.0;
         if(m_ranks[i].currencyDivergence > 2.0)
            m_ranks[i].currencyBonus = 1.20; // 20% bonus for strong divergence
         else if(m_ranks[i].currencyDivergence > 1.0)
            m_ranks[i].currencyBonus = 1.10; // 10% bonus for moderate divergence

         // Direction alignment bonus
         double expectedDir = (baseStr > quoteStr) ? 1.0 : -1.0;
         if(m_ranks[i].direction == expectedDir && m_ranks[i].currencyDivergence > 0.5)
            m_ranks[i].currencyBonus *= 1.05; // Additional 5%

         // Publish MTF and currency metrics
         GlobalVariableSet("PG_MTF_" + sym, m_ranks[i].mtfConfluence);
         GlobalVariableSet("PG_CurrDiv_" + sym, m_ranks[i].currencyDivergence);
         GlobalVariableSet("PG_PerfMult_" + sym, m_ranks[i].performanceMult);
      }

      // 3. DYNAMIC DRAFT SYSTEM
      int maxSlots = CalculateDynamicSlots();
      GlobalVariableSet("PG_ActiveSlots", (double)maxSlots);

      // 4. Calculate adjScore with ALL multipliers
      for(int i=0; i<m_symbolCount; i++)
      {
         string sym2 = m_ranks[i].symbol;

         // Base score
         double baseScore = m_ranks[i].volatilityNormScore;

         // Apply ENHANCED regime multiplier
         double regimeMult = GetEnhancedRegimeMultiplier(sym2);

         // Momentum multiplier
         double momentumMult = 1.0;
         if(m_ranks[i].momentumFactor >  2.0) momentumMult = 1.25;
         if(m_ranks[i].momentumFactor < -2.0) momentumMult = 0.85;

         // Quality multiplier
         double quality = GlobalVariableGet("PG_Quality_" + sym2);
         double qualityMult = (quality >= 3.0) ? 1.20
                            : (quality >= 2.0) ? 1.10
                                               : 1.0;

         // APPLY ALL MULTIPLIERS
         m_ranks[i].adjScore = baseScore
                              * regimeMult
                              * momentumMult
                              * qualityMult
                              * m_ranks[i].mtfBonus
                              * m_ranks[i].performanceMult
                              * m_ranks[i].currencyBonus;

         m_ranks[i].rank = 99;
      }

      // 5. Draft Loop - OPTIMIZED with static array
      static bool isPicked[];
      if(ArraySize(isPicked) != m_symbolCount)
         ArrayResize(isPicked, m_symbolCount);
      ArrayInitialize(isPicked, false);

      for(int round=1; round<=maxSlots; round++)
      {
         int bestIdx = -1;
         double maxScore = -999.0;

         // Find best remaining ADJ SCORE
         for(int i=0; i<m_symbolCount; i++)
         {
            if(!m_ranks[i].isKZOpen) continue;

            if(!isPicked[i] && m_ranks[i].adjScore > maxScore)
            {
               maxScore = m_ranks[i].adjScore;
               bestIdx = i;
            }
         }

         // Quality control
         if(bestIdx == -1) break;
         if(m_ranks[bestIdx].score < m_ranks[bestIdx].reqScore) break;

         // Pick winner with hysteresis
         isPicked[bestIdx] = true;
         int prevRank = 99;
         for(int j=0; j<ArraySize(m_prevRanks); j++)
         {
            if(m_prevRanks[j].symbol == m_ranks[bestIdx].symbol)
            {
               prevRank = m_prevRanks[j].rank;
               break;
            }
         }

         if(prevRank < 99 && !ShouldChangeRank(prevRank, round, m_ranks[bestIdx].symbol))
            m_ranks[bestIdx].rank = prevRank;
         else
         {
            m_ranks[bestIdx].rank = round;
            m_ranks[bestIdx].lastRankChange = TimeCurrent();
         }

         // Apply correlation penalty
         string winnerSym = m_ranks[bestIdx].symbol;
         double winnerDir = m_ranks[bestIdx].direction;

         for(int i=0; i<m_symbolCount; i++)
         {
            if(!isPicked[i])
            {
               double factor = GetEnhancedCorrelation(winnerSym, m_ranks[i].symbol);

               // Directional sensitivity
               if(winnerDir != 0 && m_ranks[i].direction != 0 && winnerDir != m_ranks[i].direction)
                  factor *= 0.5;

               factor = MathMax(0.0, MathMin(1.0, factor));

               m_ranks[i].adjScore *= (1.0 - factor);
               if(m_ranks[i].adjScore < 0.0) m_ranks[i].adjScore = 0.0;
            }
         }
      }

      // 6. Assign remaining ranks
      int nextRank = maxSlots + 1;

      for(int i=0; i<m_symbolCount; i++)
      {
         if(isPicked[i]) continue;

         int better = 0;
         for(int j=0; j<m_symbolCount; j++)
         {
            if(!isPicked[j] && m_ranks[j].adjScore > m_ranks[i].adjScore) better++;
         }
         m_ranks[i].rank = nextRank + better;
      }

      // 7. Sort by rank
      for(int i=0; i<m_symbolCount-1; i++)
      {
         for(int j=0; j<m_symbolCount-i-1; j++)
         {
            if(m_ranks[j].rank > m_ranks[j+1].rank)
            {
               SymbolRank temp = m_ranks[j];
               m_ranks[j] = m_ranks[j+1];
               m_ranks[j+1] = temp;
            }
         }
      }

      // 8. Publish ranks
      for(int i=0; i<m_symbolCount; i++)
      {
         string rankKey = GV_RANK_PREFIX + m_ranks[i].symbol;
         GlobalVariableSet(rankKey, (double)m_ranks[i].rank);
      }

      GlobalVariableSet(GV_RANK_UPDATE, (double)TimeCurrent());

      // 9. Store for hysteresis
      StorePreviousRanks();
   }

   //+------------------------------------------------------------------+
   //| Get Formatted Ranking Table                                       |
   //+------------------------------------------------------------------+
   string GetRankingTable(int topN = 5)
   {
      string text = "-----------------------------------------------\n";
      text += " LIVE RANKING (Top " + IntegerToString(topN) + ")\n";
      text += "-----------------------------------------------\n";
      text += " #  | Symbol   | Score | Status\n";

      for(int i=0; i<MathMin(m_symbolCount, topN); i++)
      {
         string status = (m_ranks[i].rank <= 3) ? "ACTIVE" : "WAIT";

         string line = StringFormat(" %-2d | %-8s | %-5.1f | %s\n",
                                    m_ranks[i].rank,
                                    m_ranks[i].symbol,
                                    m_ranks[i].score,
                                    status);
         text += line;
      }
      return text;
   }

   //+------------------------------------------------------------------+
   //| Get Raw Ranks                                                     |
   //+------------------------------------------------------------------+
   int GetRanks(SymbolRank &outRanks[])
   {
      int count = ArraySize(m_ranks);
      ArrayResize(outRanks, count);
      for(int i=0; i<count; i++) outRanks[i] = m_ranks[i];
      return count;
   }

   //+------------------------------------------------------------------+
   //| Get Symbol At Rank                                                |
   //+------------------------------------------------------------------+
   string GetSymbolAtRank(int rankIndex)
   {
      if(rankIndex >= m_symbolCount || rankIndex < 0) return "";

      string sym = m_ranks[rankIndex].symbol;
      double profit = 0;
      int wins = 0, losses = 0;

      datetime weekAgo = TimeCurrent() - 7 * 24 * 3600;
      HistorySelect(weekAgo, TimeCurrent());
      int total = HistoryDealsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         string dealSym = HistoryDealGetString(ticket, DEAL_SYMBOL);
         if(StringFind(dealSym, sym) < 0) continue;

         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);

         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

         double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         profit += pnl;

         if(pnl > 0)
            wins++;
         else if(pnl < 0)
            losses++;
      }

      int totalTrades = wins + losses;
      double winRate = totalTrades > 0 ? (double)wins / totalTrades * 100.0 : 0;

      double grossProfit = 0, grossLoss = 0;
      HistorySelect(weekAgo, TimeCurrent());
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         string dealSym = HistoryDealGetString(ticket, DEAL_SYMBOL);
         if(StringFind(dealSym, sym) < 0) continue;

         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);

         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

         double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT);

         if(pnl > 0)
            grossProfit += pnl;
         else if(pnl < 0)
            grossLoss += MathAbs(pnl);
      }

      double pf = grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? 2.0 : 0);

      string cleanSym = sym;
      StringReplace(cleanSym, ".pro", "");
      StringReplace(cleanSym, ".PRO", "");
      StringReplace(cleanSym, ".x", "");
      StringReplace(cleanSym, ".X", "");

      return StringFormat("%s|%.0f|%.0f|%d|%.2f", cleanSym, profit, winRate, totalTrades, pf);
   }

   //+------------------------------------------------------------------+
   //| Calculate Dynamic Slots                                           |
   //+------------------------------------------------------------------+
   int CalculateDynamicSlots()
   {
      int strongSignals = 0;
      int trendingSymbols = 0;
      int choppySymbols = 0;

      for(int i=0; i<m_symbolCount; i++)
      {
         if(m_ranks[i].score >= m_ranks[i].reqScore) strongSignals++;
         double regime = GlobalVariableGet("PG_Regime_" + m_ranks[i].symbol);
         if(regime == 0.0) trendingSymbols++;
         if(regime == 3.0) choppySymbols++;
      }

      int slots = MathMax(m_minSlots, strongSignals);

      return MathMax(m_minSlots, MathMin(m_maxSlots, slots));
   }

   //+------------------------------------------------------------------+
   //| Should Change Rank (Hysteresis)                                   |
   //+------------------------------------------------------------------+
   bool ShouldChangeRank(int currentRank, int newRank, string symbol)
   {
      for(int i=0; i<ArraySize(m_prevRanks); i++)
      {
         if(m_prevRanks[i].symbol == symbol)
         {
            if(newRank < currentRank)
            {
               int delta = currentRank - newRank;
               if(delta >= 2) return true;

               for(int j=0; j<m_symbolCount; j++)
               {
                  if(m_ranks[j].symbol == symbol)
                  {
                     double scoreDelta = m_ranks[j].adjScore - m_prevRanks[i].adjScore;
                     return (scoreDelta >= m_hysteresisThreshold);
                  }
               }
            }
            else if(newRank > currentRank)
            {
               long barsSinceChange = (TimeCurrent() - m_prevRanks[i].lastRankChange) / 60;
               return (barsSinceChange >= m_hysteresisCooldown);
            }

            return true;
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Store Previous Ranks                                              |
   //+------------------------------------------------------------------+
   void StorePreviousRanks()
   {
      int count = ArraySize(m_ranks);
      ArrayResize(m_prevRanks, count);
      for(int i=0; i<count; i++)
      {
         m_prevRanks[i] = m_ranks[i];
         m_prevRanks[i].consecutiveBars++;
      }
   }
};

#endif
