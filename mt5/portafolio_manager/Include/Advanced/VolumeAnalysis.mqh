//+------------------------------------------------------------------+
//|                                               VolumeAnalysis.mqh |
//|          Basic Volume Price Analysis for Confluence               |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef VOLUME_ANALYSIS_MQH
#define VOLUME_ANALYSIS_MQH

#property copyright "Guido Ambiorix"
#property strict

class CVolumeAnalysis
{
public:
   CVolumeAnalysis() {}
   ~CVolumeAnalysis() {}

   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-2.5 pts)                                 |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0.0;

      // Basic VPA: Check if volume supports the move
      // High volume on up-move = valid buy
      // High volume on down-move = valid sell

      // FIX: Use _Symbol instead of NULL for better compatibility
      long volume = iVolume(_Symbol, PERIOD_CURRENT, 0);
      long prevVolume = iVolume(_Symbol, PERIOD_CURRENT, 1);

      // Calculate Volume MA (20)
      // FIX: Validate volume data before calculation
      long volSum = 0;
      int validBars = 0;
      for(int i=0; i<20; i++)
      {
         long v = iVolume(_Symbol, PERIOD_CURRENT, i);
         if(v > 0)
         {
            volSum += v;
            validBars++;
         }
      }
      double volMA = (validBars >= 10) ? (volSum / (double)validBars) : volume;

      // 1. High Volume Support (+1.0)
      if(volMA > 0 && volume > volMA * 1.5)
      {
         score += 1.0;
      }

      // 2. Rising Volume Trend (+1.0)
      if(volume > prevVolume && prevVolume > iVolume(_Symbol, PERIOD_CURRENT, 2))
      {
         score += 1.0;
      }
      
      // 3. Consistent Above-Average Volume (+0.5)
      // Reward steady volume increases, not climactic spikes
      // FIX: Add volMA validation
      if(volMA > 0 && volume > volMA * 1.2 && volume < volMA * 3.0)
      {
         score += 0.5;
      }
      
      return MathMin(score, 2.5);
   }
};

#endif
