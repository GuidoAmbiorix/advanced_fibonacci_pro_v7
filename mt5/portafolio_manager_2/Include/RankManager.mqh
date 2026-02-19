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
};

//+------------------------------------------------------------------+
//| RANK MANAGER CLASS                                                |
//| Responsibility: Central Judge of Trade Quality                   |
//+------------------------------------------------------------------+
class CRankManager
{
private:
   SymbolRank m_ranks[];
   string     m_symbols[];
   int        m_symbolCount;

public:
   CRankManager() : m_symbolCount(0) {}

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
      // 1. Discover Symbols first
      DiscoverSymbols();
   
      if(m_symbolCount == 0) return;

      // 2. Read Scores from Global Variables
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
      }

      // 3. DYNAMIC DRAFT SYSTEM (Risk Allocator Model - Optimized)
      // Init adjScore with raw score first
      for(int i=0; i<m_symbolCount; i++) {
         m_ranks[i].adjScore = m_ranks[i].score;
         m_ranks[i].rank = 99; // Default low rank
      }

      // Working arrays
      bool isPicked[];
      ArrayResize(isPicked, m_symbolCount);
      ArrayInitialize(isPicked, false);
      
      int maxSlots = 3;
      
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
         
         // Pick Winner
         isPicked[bestIdx] = true;
         m_ranks[bestIdx].rank = round;
         
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
};

#endif
