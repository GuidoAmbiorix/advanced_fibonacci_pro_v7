//+------------------------------------------------------------------+
//|                                                  RankManager.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef RANK_MANAGER_MQH
#define RANK_MANAGER_MQH

#include "PortfolioGlobals.mqh"

//+------------------------------------------------------------------+
//| SYMBOL RANK STRUCTURE                                            |
//+------------------------------------------------------------------+
struct SymbolRank
{
   string symbol;
   double score;
   double adjScore; // Penalized Score
   double reqScore;
   double direction; // 1.0 = Buy, -1.0 = Sell
   long   timeRemaining; // Seconds to next bar
   bool   isKZOpen;      // Killzone active?
   int    rank;

   // PHASE 2: Enhanced ranking fields
   double volatilityNormScore;  // ATR-normalized score
   double timeWeightedScore;    // Score with time-to-bar weighting
   double momentumFactor;       // Recent score improvement
   datetime lastRankChange;     // For hysteresis tracking
   int    consecutiveBars;      // How many bars held rank
};

//+------------------------------------------------------------------+
//| RANK MANAGER CLASS                                                |
//| Responsibility: Central Judge of Trade Quality                   |
//+------------------------------------------------------------------+
class CRankManager
{
private:
   SymbolRank m_ranks[];
   SymbolRank m_prevRanks[];  // PHASE 2: Track previous ranks for hysteresis
   string     m_symbols[];
   int        m_symbolCount;

   // PHASE 2: Ranking parameters
   double     m_hysteresisThreshold;  // Min delta to change rank
   int        m_hysteresisCooldown;   // Cooldown bars before rank change
   int        m_minSlots;             // Minimum active slots
   int        m_maxSlots;             // Maximum active slots

public:
   CRankManager() : m_symbolCount(0), m_hysteresisThreshold(0.5),
                    m_hysteresisCooldown(3), m_minSlots(2), m_maxSlots(10) {}

   //+------------------------------------------------------------------+
   //| Discover Active Symbols (Auto-Discovery)                          |
   //+------------------------------------------------------------------+
   void DiscoverSymbols()
   {
      // We don't clear the list immediately to avoid flickering
      // But we will rebuild it based on active GVs on every pass (or every N seconds)
      
      int totalGV = GlobalVariablesTotal();
      m_symbolCount = 0; // Reset count for rebuild
      
      for(int i=0; i<totalGV; i++)
      {
         string gvName = GlobalVariableName(i);
         
         // Look for keys starting with PG_Score_
         if(StringFind(gvName, GV_SCORE_PREFIX) == 0)
         {
            // Extract Symbol Name (e.g. PG_Score_EURUSD -> EURUSD)
            string symbol = StringSubstr(gvName, StringLen(GV_SCORE_PREFIX));
            
            // GHOST SYMBOL GUARD: Only add if complete data exists
            if(!GlobalVariableCheck(GV_REQ_PREFIX + symbol)) continue;
            if(!GlobalVariableCheck(GV_DIR_PREFIX + symbol)) continue;
            
            // Add to list
            m_symbolCount++;
            ArrayResize(m_symbols, m_symbolCount);
            ArrayResize(m_ranks, m_symbolCount);
            
            m_symbols[m_symbolCount-1] = symbol;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Update Ranks (Call via OnTimer, e.g., every 5-10 sec)            |
   //+------------------------------------------------------------------+
   void UpdateRanks()
   {
      // 1. Discover Symbols — rate-limited to once per 60 s to avoid O(n) GV scan every tick
      static datetime lastDiscover = 0;
      if(TimeCurrent() - lastDiscover >= 60 || m_symbolCount == 0)
      {
         DiscoverSymbols();
         lastDiscover = TimeCurrent();
      }

      if(m_symbolCount == 0) return;

      // 2. Read Scores from Global Variables with PHASE 2 enhancements

      // Fix #1: Compute pool ATR average for relative normalization
      double atrSum = 0; int atrCount = 0;
      for(int i=0; i<m_symbolCount; i++) {
         double a = GlobalVariableGet("PG_ATR_" + m_symbols[i]);
         if(a > 0) { atrSum += a; atrCount++; }
      }
      double atrAvg = (atrCount > 0) ? atrSum / atrCount : 1.0;

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
            if(rem < 0) rem = 0; // Should trigger new bar soon
         }

         m_ranks[i].symbol = sym;
         m_ranks[i].score = score;
         m_ranks[i].reqScore = req;
         m_ranks[i].direction = dir;
         m_ranks[i].timeRemaining = rem;
         m_ranks[i].isKZOpen = kz;

         // Fix #1: Volatility-normalized score — relative to pool ATR average
         double atr = GlobalVariableGet("PG_ATR_" + sym);
         double atrRatio = MathMax(0.5, MathMin(1.5, (atr > 0 ? atr / atrAvg : 1.0)));
         m_ranks[i].volatilityNormScore = score * atrRatio;

         // Bonus: timeWeightedScore simplified — kept for display, not used in adjScore
         m_ranks[i].timeWeightedScore = score;

         // PHASE 2: Calculate momentum (score improvement from previous rank)
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
      }

      // 3. DYNAMIC DRAFT SYSTEM (Risk Allocator Model - Optimized)
      int maxSlots = CalculateDynamicSlots();
      // Fix #4b: Publish active slots so Symbol_Engine can read them
      GlobalVariableSet("PG_ActiveSlots", (double)maxSlots);

      // Fix #2: adjScore with multiplicative regime/momentum/quality factors
      for(int i=0; i<m_symbolCount; i++) {
         string sym2 = m_ranks[i].symbol;

         // Regime multiplier (REGIME_TREND=0 boost, REGIME_CHAOS=3 penalty)
         double regime = GlobalVariableGet("PG_Regime_" + sym2);
         double regimeMult = (regime == 0.0) ? 1.15
                          : (regime == 3.0) ? 0.75
                                            : 1.0;

         // Momentum multiplier
         double momentumMult = 1.0;
         if(m_ranks[i].momentumFactor >  2.0) momentumMult = 1.10;
         if(m_ranks[i].momentumFactor < -2.0) momentumMult = 0.90;

         // Quality multiplier (3=ELITE, 2=STRONG, 1=GOOD)
         double quality = GlobalVariableGet("PG_Quality_" + sym2);
         double qualityMult = (quality >= 3.0) ? 1.20
                            : (quality >= 2.0) ? 1.10
                                               : 1.0;

         m_ranks[i].adjScore = m_ranks[i].volatilityNormScore * regimeMult * momentumMult * qualityMult;
         m_ranks[i].rank = 99; // Default low rank
      }

      // Working arrays
      bool isPicked[];
      ArrayResize(isPicked, m_symbolCount);
      ArrayInitialize(isPicked, false);
      
      // The Draft Loop
      for(int round=1; round<=maxSlots; round++)
      {
         int bestIdx = -1;
         double maxScore = -999.0;
         
         // Find best remaining ADJ SCORE (Must be Actionable)
         for(int i=0; i<m_symbolCount; i++)
         {
            // KILLZONE INTEGRATION: Only draft symbols that are actually open
            if(!m_ranks[i].isKZOpen) continue; 
            
            if(!isPicked[i] && m_ranks[i].adjScore > maxScore)
            {
               maxScore = m_ranks[i].adjScore;
               bestIdx = i;
            }
         }
         
         // QUALITY CONTROL:
         if(bestIdx == -1) break; 
         if(m_ranks[bestIdx].adjScore < m_ranks[bestIdx].reqScore) break; 
         
         // Pick Winner — apply hysteresis to prevent rank flip-flopping
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
            m_ranks[bestIdx].rank = prevRank; // Hysteresis: keep previous rank
         else
         {
            m_ranks[bestIdx].rank = round;
            m_ranks[bestIdx].lastRankChange = TimeCurrent();
         }
         
         // Apply Risk Penalty to remaining
         string winnerSym = m_ranks[bestIdx].symbol;
         double winnerDir = m_ranks[bestIdx].direction;
         
         for(int i=0; i<m_symbolCount; i++)
         {
            if(!isPicked[i])
            {
               double factor = GetSemanticCorrelation(winnerSym, m_ranks[i].symbol);
               
               // DIRECTIONAL SENSITIVITY:
               // If directions are opposite (Buy vs Sell), reduce penalty by 50%
               if(winnerDir != 0 && m_ranks[i].direction != 0 && winnerDir != m_ranks[i].direction)
               {
                  factor *= 0.5; // Hedge logic
               }
               
               // ANTIFRAGILE CLAMP: Prevents bugs if factor logic ever returns out-of-range
               if(factor < 0.0) factor = 0.0;
               if(factor > 1.0) factor = 1.0;
               
               // MULTIPLICATIVE PENALTY:
               // Cleaner math: Score * (1 - Factor)
               m_ranks[i].adjScore *= (1.0 - factor);
               
               if(m_ranks[i].adjScore < 0.0) m_ranks[i].adjScore = 0.0; // Safety Floor
            }
         }
      }
      
      // Assign remaining ranks (Queue)
      int nextRank = maxSlots + 1;
      
      for(int i=0; i<m_symbolCount; i++)
      {
         if(isPicked[i]) continue;
         
         // Rank based on AdjScore compared to other unpicked
         int better = 0;
         for(int j=0; j<m_symbolCount; j++)
         {
            if(!isPicked[j] && m_ranks[j].adjScore > m_ranks[i].adjScore) better++;
         }
         m_ranks[i].rank = nextRank + better;
      }
      
      // Final Sort by Rank for Display Consistency
      for(int i=0; i<m_symbolCount-1; i++) {
         for(int j=0; j<m_symbolCount-i-1; j++) {
            if(m_ranks[j].rank > m_ranks[j+1].rank) {
               SymbolRank temp = m_ranks[j];
               m_ranks[j] = m_ranks[j+1];
               m_ranks[j+1] = temp;
            }
         }
      }

      // 4. Publish Ranks (No Overwrite)
      for(int i=0; i<m_symbolCount; i++)
      {
         string rankKey = GV_RANK_PREFIX + m_ranks[i].symbol;
         GlobalVariableSet(rankKey, (double)m_ranks[i].rank);
      }

      // Update Timestamp
      GlobalVariableSet(GV_RANK_UPDATE, (double)TimeCurrent());

      // PHASE 2: Store current ranks for hysteresis
      StorePreviousRanks();
   }

   //+------------------------------------------------------------------+
   //| Get Formatted Ranking Table (for Dashboard)                       |
   //+------------------------------------------------------------------+
   string GetRankingTable(int topN = 5)
   {
      string text = "-----------------------------------------------\n";
      text += " LIVE RANKING (Top " + IntegerToString(topN) + ")\n";
      text += "-----------------------------------------------\n";
      text += " #  | Symbol   | Score | Status\n";
      
      for(int i=0; i<MathMin(m_symbolCount, topN); i++)
      {
         string status = (m_ranks[i].rank <= 3) ? "ACTIVE" : "WAIT"; // Assuming Top 3 allowed
         
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
   //| Get Raw Ranks (for Canvas)                                        |
   //+------------------------------------------------------------------+
   int GetRanks(SymbolRank &outRanks[])
   {
      int count = ArraySize(m_ranks);
      ArrayResize(outRanks, count);
      for(int i=0; i<count; i++) outRanks[i] = m_ranks[i];
      return count;
   }

   //+------------------------------------------------------------------+
   //| PHASE 2: Calculate dynamic slot allocation                        |
   //+------------------------------------------------------------------+
   int CalculateDynamicSlots()
   {
      // Fix #4: Slot count based on portfolio regime and signal quality
      int strongSignals = 0;
      int trendingSymbols = 0;
      int choppySymbols = 0;

      for(int i=0; i<m_symbolCount; i++) {
         if(m_ranks[i].score >= m_ranks[i].reqScore) strongSignals++;
         double regime = GlobalVariableGet("PG_Regime_" + m_ranks[i].symbol);
         if(regime == 0.0) trendingSymbols++;   // REGIME_TREND
         if(regime == 3.0) choppySymbols++;     // REGIME_CHAOS
      }

      int slots = m_minSlots;

      if(strongSignals >= 4) slots++;           // +1 if 4+ valid signals
      if(trendingSymbols >= 3) slots++;         // +1 if 3+ symbols trending
      if(choppySymbols > trendingSymbols) slots--; // -1 if dominantly choppy
      if(strongSignals >= 8) slots++;           // +1 extra if very active market

      return MathMax(m_minSlots, MathMin(m_maxSlots, slots));
   }

   //+------------------------------------------------------------------+
   //| PHASE 2: Apply ranking hysteresis                                 |
   //+------------------------------------------------------------------+
   bool ShouldChangeRank(int currentRank, int newRank, string symbol)
   {
      // Find previous rank for this symbol
      for(int i=0; i<ArraySize(m_prevRanks); i++)
      {
         if(m_prevRanks[i].symbol == symbol)
         {
            // Check if rank improved significantly
            if(newRank < currentRank)
            {
               // Allow improvement if delta is significant
               int delta = currentRank - newRank;
               if(delta >= 2) return true; // Big jump always allowed

               // Small improvement requires score delta
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
               // Allow demotion after cooldown period
               long barsSinceChange = (TimeCurrent() - m_prevRanks[i].lastRankChange) / 60; // Approximate
               return (barsSinceChange >= m_hysteresisCooldown);
            }

            return true; // No rank change
         }
      }

      return true; // No previous rank found, allow change
   }

   //+------------------------------------------------------------------+
   //| PHASE 2: Store current ranks for next update                      |
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
