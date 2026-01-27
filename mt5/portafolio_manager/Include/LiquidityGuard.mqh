//+------------------------------------------------------------------+
//|                                               LiquidityGuard.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef LIQUIDITY_GUARD_MQH
#define LIQUIDITY_GUARD_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| LIQUIDITY GUARD MODULE                                            |
//| Responsibility: Avoid trading during liquidity crises             |
//+------------------------------------------------------------------+
class CLiquidityGuard
{
private:
   int      m_maxSpreadPoints;
   double   m_minVolumeThreshold; // vs Avg
   
public:
   CLiquidityGuard() : m_maxSpreadPoints(50), m_minVolumeThreshold(0.3) {}
   
   void Init(int maxSpread, double minVolRatio)
   {
      m_maxSpreadPoints = maxSpread;
      m_minVolumeThreshold = minVolRatio;
   }

   //+------------------------------------------------------------------+
   //| Check if symbol is safe to trade                                  |
   //+------------------------------------------------------------------+
   bool IsSafe(string symbol)
   {
      // 1. Check Spread
      long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(spread > m_maxSpreadPoints)
      {
          // Check if JPY exception needed, otherwise strict
          if(!(StringFind(symbol, "JPY") >= 0 && spread < m_maxSpreadPoints * 1.5))
          {
             return false;
          }
      }
      
      // 2. Volume Analysis (True Liquidity)
      // Get current M1 volume vs Moving Average (20 periods)
      // MQL5: iVolume is simpler for direct access
      long currentVol = iVolume(symbol, PERIOD_M1, 0);
      
      // Robust Loop for Avg
      long totalVol = 0;
      int periods = 20;
      for(int i = 1; i <= periods; i++)
      {
         totalVol += iVolume(symbol, PERIOD_M1, i);
      }
      double avgVol = (double)totalVol / periods;
      
      // Avoid division by zero
      if(avgVol < 1) avgVol = 1;
      
      // Crisis Condition: Volume collapsed (< 30% of avg)
      if(currentVol < avgVol * m_minVolumeThreshold)
      {
         // Could be dead market or pre-news silence
         // Double check if its simply night session
         // For now, assume critical if strict 'God Mode'
         return false; 
      }
      
      // 3. Flash Crash Pattern (High Range + Low Volume)
      double high = iHigh(symbol, PERIOD_M1, 0);
      double low = iLow(symbol, PERIOD_M1, 0);
      double range = (high - low);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      // If range > 50 pips in 1 min (extreme)
      if(range > 500 * point) 
      {
         return false; 
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Get Liquidity Score (0-100)                                       |
   //+------------------------------------------------------------------+
   double GetLiquidityScore(string symbol)
   {
      long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(spread <= 0) return 0;
      
      double baseline = 10.0; // "Good" spread
      double score = 100.0 * (baseline / (double)spread);
      
      return MathMin(100.0, score);
   }
};

#endif
