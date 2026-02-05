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
      
      long volume = iVolume(NULL, 0, 0);
      long prevVolume = iVolume(NULL, 0, 1);
      
      // Calculate Volume MA (20)
      long volSum = 0;
      for(int i=0; i<20; i++) volSum += iVolume(NULL, 0, i);
      double volMA = volSum / 20.0;
      
      // 1. High Volume Support (+1.0)
      if(volume > volMA * 1.5)
      {
         score += 1.0;
      }
      
      // 2. Rising Volume Trend (+1.0)
      if(volume > prevVolume && prevVolume > iVolume(NULL, 0, 2))
      {
         score += 1.0;
      }
      
      // 3. Ultra High Volume Climax (+0.5) - Potential stopping volume? 
      // Actually for trend following we want consistent high volume.
      // If Ultra high, might be reversal. 
      // Let's reward consistent above average volume.
      if(volume > volMA * 1.2 && volume < volMA * 3.0) 
      {
         score += 0.5;
      }
      
      return MathMin(score, 2.5);
   }
};

#endif
