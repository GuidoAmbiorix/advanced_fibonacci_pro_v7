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
   double GetDivergenceScore(int direction, int rsiHandle)
   {
      double score = 0;
      
      if(direction == 1) // BULLISH
      {
         // Regular Bullish: Price Lower Low, RSI Higher Low
         if(CheckRegularBullish(rsiHandle)) score += 1.0;
         
         // Hidden Bullish: Price Higher Low, RSI Lower Low
         if(CheckHiddenBullish(rsiHandle)) score += 0.5;
      }
      else // BEARISH
      {
         // Regular Bearish: Price Higher High, RSI Lower High
         if(CheckRegularBearish(rsiHandle)) score += 1.0;
         
         // Hidden Bearish: Price Lower High, RSI Higher High
         if(CheckHiddenBearish(rsiHandle)) score += 0.5;
      }
      
      return MathMin(score, 1.5);
   }
   
private:
   // Helper to get RSI value at shift
   double GetRSI(int handle, int shift)
   {
      double buf[1];
      if(CopyBuffer(handle, 0, shift, 1, buf) == 1) return buf[0];
      return 50.0; // Default fallback
   }

   bool CheckRegularBullish(int rsiHandle)
   {
      // Detect lowest low in last 20 bars
      int llBar = iLowest(NULL, 0, MODE_LOW, 20, 1);
      if(llBar < 3) return false; 
      
      double lowOld = iLow(NULL, 0, llBar);
      double rsiOld = GetRSI(rsiHandle, llBar);
      
      double lowCurr = iLow(NULL, 0, 0);
      double rsiCurr = GetRSI(rsiHandle, 0);
      
      // Regular Bullish: Price makes Lower Low, RSI makes Higher Low
      if(lowCurr < lowOld && rsiCurr > rsiOld) return true;
      return false;
   }
   
   bool CheckRegularBearish(int rsiHandle)
   {
      int hhBar = iHighest(NULL, 0, MODE_HIGH, 20, 1);
      if(hhBar < 3) return false;
      
      double highOld = iHigh(NULL, 0, hhBar);
      double rsiOld = GetRSI(rsiHandle, hhBar);
      
      double highCurr = iHigh(NULL, 0, 0);
      double rsiCurr = GetRSI(rsiHandle, 0);
      
      // Regular Bearish: Price makes Higher High, RSI makes Lower High
      if(highCurr > highOld && rsiCurr < rsiOld) return true;
      return false;
   }
   
   // Placeholder for Hidden Divergence (Complexity reduction)
   bool CheckHiddenBullish(int rsiHandle) { return false; }
   bool CheckHiddenBearish(int rsiHandle) { return false; }
};

#endif
