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
   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-4.0 pts)                                 |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0.0;
      
      // 1. INSTITUTIONAL RVOL (Time-Segmented)
      // Checks if volume is high relative to THIS time of day
      double rvol = CalculateRVOL(20); // 20-day lookback
      
      if(rvol >= 1.5) score += 1.5;    // Active Participation
      if(rvol >= 3.0) score += 1.0;    // Institutional Ignition (Bonus)
      
      // 2. MONEY FLOW PRESSURE (Rapid CMF)
      // Checks if money is flowing in the direction of the trade
      // Lookback: 5 candles (Rapid Flow)
      double flow = CalculateRapidMoneyFlow(5);
      
      if(direction == 1 && flow > 0.1) score += 1.5;   // Buying Pressure
      if(direction == -1 && flow < -0.1) score += 1.5; // Selling Pressure
      
      return score; // Max 4.0
   }

   //+------------------------------------------------------------------+
   //| Calculate Relative Volume (Time-Segmented)                       |
   //+------------------------------------------------------------------+
   double CalculateRVOL(int lookbackDays)
   {
      long currentVol = iVolume(_Symbol, PERIOD_CURRENT, 0);
      if(currentVol <= 0) return 1.0;
      
      long volumeSum = 0;
      int count = 0;
      
      datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      
      // Loop back 'lookbackDays' to find same time of day
      for(int i = 1; i <= lookbackDays; i++)
      {
         datetime pastTime = currentTime - (i * PeriodSeconds(PERIOD_D1));
         
         // Find closest bar to that time
         int shift = iBarShift(_Symbol, PERIOD_CURRENT, pastTime, false);
         
         if(shift > 0)
         {
             volumeSum += iVolume(_Symbol, PERIOD_CURRENT, shift);
             count++;
         }
      }
      
      double avgVol = (count > 0) ? (double)volumeSum / count : currentVol;
      if(avgVol == 0) return 1.0;
      
      return (double)currentVol / avgVol;
   }

   //+------------------------------------------------------------------+
   //| Calculate Rapid Money Flow (Simplified CMF)                      |
   //+------------------------------------------------------------------+
   double CalculateRapidMoneyFlow(int lookback)
   {
      double flowSum = 0;
      double volSum = 0;
      
      for(int i = 0; i < lookback; i++)
      {
         double high = iHigh(_Symbol, PERIOD_CURRENT, i);
         double low = iLow(_Symbol, PERIOD_CURRENT, i);
         double close = iClose(_Symbol, PERIOD_CURRENT, i);
         long vol = iVolume(_Symbol, PERIOD_CURRENT, i);
         
         if(high == low) continue;
         
         // Multiplier: ((Close - Low) - (High - Close)) / (High - Low)
         // 1 = Closed at High (Max Buying)
         // -1 = Closed at Low (Max Selling)
         double mult = ((close - low) - (high - close)) / (high - low);
         
         flowSum += mult * (double)vol;
         volSum += (double)vol;
      }
      
      return (volSum > 0) ? flowSum / volSum : 0;
   }
};

#endif
