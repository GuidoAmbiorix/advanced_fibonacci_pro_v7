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
         string scoreKey = GV_SCORE_PREFIX + sym;
         
         double score = 0;
         if(GlobalVariableCheck(scoreKey))
            score = GlobalVariableGet(scoreKey);
            
         m_ranks[i].symbol = sym;
         m_ranks[i].score = score;
      }

      // 2. Sort Bubble Sort (Simple for small N < 50)
      // Descending Order (High Score First)
      for(int i=0; i<m_symbolCount-1; i++)
      {
         for(int j=0; j<m_symbolCount-i-1; j++)
         {
            if(m_ranks[j].score < m_ranks[j+1].score)
            {
               SymbolRank temp = m_ranks[j];
               m_ranks[j] = m_ranks[j+1];
               m_ranks[j+1] = temp;
            }
         }
      }

      // 3. Assign Ranks and Publish
      for(int i=0; i<m_symbolCount; i++)
      {
         m_ranks[i].rank = i + 1; // 1-based rank (1st, 2nd, 3rd...)
         
         // Publish Rank to GV
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
};

#endif
