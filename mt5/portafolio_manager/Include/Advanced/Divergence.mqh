//+------------------------------------------------------------------+
//|                                                   Divergence.mqh |
//|          RSI Divergence Detection                                 |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef DIVERGENCE_MQH
#define DIVERGENCE_MQH

#property copyright "Guido Ambiorix"
#property strict

class CDivergence
{
public:
   CDivergence() {}
   ~CDivergence() {}

   //+------------------------------------------------------------------+
   //| Get Divergence Score (0-1.5 pts)                                 |
   //+------------------------------------------------------------------+
   double GetDivergenceScore(int direction)
   {
      // Simplified Divergence Check
      // Needs access to price and RSI buffers ideally, but we'll use iRSI directly
      
      double score = 0;
      
      if(direction == 1) // BULLISH
      {
         // Regular Bullish: Lower Low in Price, Higher Low in RSI
         if(CheckRegularBullish()) score += 1.0;
         
         // Hidden Bullish: Higher Low in Price, Lower Low in RSI (Trend Continuation)
         if(CheckHiddenBullish()) score += 0.5;
      }
      else // BEARISH
      {
         // Regular Bearish: Higher High in Price, Lower High in RSI
         if(CheckRegularBearish()) score += 1.0;
         
         // Hidden Bearish: Lower High in Price, Higher High in RSI
         if(CheckHiddenBearish()) score += 0.5;
      }
      
      return MathMin(score, 1.5);
   }
   
private:
   bool CheckRegularBullish()
   {
      // Detect lowest low in last 20 bars
      int llBar = iLowest(NULL, 0, MODE_LOW, 20, 1);
      if(llBar < 3) return false; // Too recent
      
      double low1 = iLow(NULL, 0, llBar);
      double rsi1 = iRSI(NULL, 0, 14, PRICE_CLOSE, llBar);
      
      double lowCurrent = iLow(NULL, 0, 0);
      double rsiCurrent = iRSI(NULL, 0, 14, PRICE_CLOSE, 0);
      
      // Lower Low in Price, Higher Low in RSI (approx)
      if(lowCurrent < low1 && rsiCurrent > rsi1) return true;
      return false;
   }
   
   bool CheckRegularBearish()
   {
      int hhBar = iHighest(NULL, 0, MODE_HIGH, 20, 1);
      if(hhBar < 3) return false;
      
      double high1 = iHigh(NULL, 0, hhBar);
      double rsi1 = iRSI(NULL, 0, 14, PRICE_CLOSE, hhBar);
      
      double highCurrent = iHigh(NULL, 0, 0);
      double rsiCurrent = iRSI(NULL, 0, 14, PRICE_CLOSE, 0);
      
      // Higher High in Price, Lower High in RSI
      if(highCurrent > high1 && rsiCurrent < rsi1) return true;
      return false;
   }
   
   bool CheckHiddenBullish()
   {
      // Trend continuation logic
      return false; // Stub
   }
   
   bool CheckHiddenBearish()
   {
      return false; // Stub
   }
};

#endif
