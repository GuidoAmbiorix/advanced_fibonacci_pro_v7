//+------------------------------------------------------------------+
//|                                               VolumeAnalysis.mqh |
//|          Basic Volume Price Analysis for Confluence               |
//|                                  Copyright 2026, Infernal Portfolio Governor   |
//+------------------------------------------------------------------+
#ifndef VOLUME_ANALYSIS_MQH
#define VOLUME_ANALYSIS_MQH

#property copyright "Infernal Portfolio Governor"
#property strict

class CVolumeAnalysis
{
private:
   // PHASE 4: Volume cache with time-of-day bucketing
   struct VolumeCache {
      long avgVolume[24];      // Hourly average volumes
      int sampleCount[24];     // Sample counts per hour
      datetime lastUpdate;
   };
   VolumeCache m_cache;

   // Cache for RVOL calculation
   double m_cachedRVOL;
   datetime m_lastRVOLCalc;

   // Cache for Money Flow
   double m_cachedMoneyFlow;
   datetime m_lastMoneyFlowCalc;

public:
   CVolumeAnalysis()
   {
      ArrayInitialize(m_cache.avgVolume, 0);
      ArrayInitialize(m_cache.sampleCount, 0);
      m_cache.lastUpdate = 0;
      m_cachedRVOL = 1.0;
      m_lastRVOLCalc = 0;
      m_cachedMoneyFlow = 0;
      m_lastMoneyFlowCalc = 0;
   }
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
   //| PHASE 4: Calculate RVOL with hourly bucketing cache              |
   //+------------------------------------------------------------------+
   double CalculateRVOL(int lookbackDays)
   {
      datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

      // Return cached value if same bar
      if(currentBarTime == m_lastRVOLCalc)
         return m_cachedRVOL;

      long currentVol = iVolume(_Symbol, PERIOD_CURRENT, 0);
      if(currentVol <= 0)
      {
         m_cachedRVOL = 1.0;
         m_lastRVOLCalc = currentBarTime;
         return 1.0;
      }

      // Get current hour
      MqlDateTime dt;
      TimeToStruct(currentBarTime, dt);
      int currentHour = dt.hour;

      // Build/update hourly cache if stale
      datetime cacheAge = currentBarTime - m_cache.lastUpdate;
      if(cacheAge > 86400) // Update cache once per day
      {
         UpdateVolumeCache(lookbackDays);
      }

      // Get average volume for this hour from cache
      double avgVol = 0;
      if(m_cache.sampleCount[currentHour] > 0)
      {
         avgVol = (double)m_cache.avgVolume[currentHour] / m_cache.sampleCount[currentHour];
      }
      else
      {
         // Fallback to simple average if no cached data for this hour
         avgVol = (double)currentVol;
      }

      if(avgVol <= 0) avgVol = (double)currentVol;

      double rvol = (double)currentVol / avgVol;

      // Cache result
      m_cachedRVOL = rvol;
      m_lastRVOLCalc = currentBarTime;

      return rvol;
   }

   //+------------------------------------------------------------------+
   //| PHASE 4: Update volume cache with time-of-day bucketing          |
   //+------------------------------------------------------------------+
   void UpdateVolumeCache(int lookbackDays)
   {
      // Clear cache
      ArrayInitialize(m_cache.avgVolume, 0);
      ArrayInitialize(m_cache.sampleCount, 0);

      datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

      // Scan historical data and bucket by hour
      int totalBars = lookbackDays * 24 * (60 / PeriodSeconds(PERIOD_CURRENT) * 60);
      if(totalBars > 10000) totalBars = 10000; // Cap for performance

      for(int i = 1; i < totalBars; i++)
      {
         datetime barTime = iTime(_Symbol, PERIOD_CURRENT, i);
         if(barTime <= 0) break;

         MqlDateTime dt;
         TimeToStruct(barTime, dt);
         int hour = dt.hour;

         long vol = iVolume(_Symbol, PERIOD_CURRENT, i);
         if(vol > 0)
         {
            m_cache.avgVolume[hour] += vol;
            m_cache.sampleCount[hour]++;
         }
      }

      m_cache.lastUpdate = currentTime;
   }

   //+------------------------------------------------------------------+
   //| PHASE 4: Calculate Rapid Money Flow with caching                 |
   //+------------------------------------------------------------------+
   double CalculateRapidMoneyFlow(int lookback)
   {
      datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

      // Return cached value if same bar
      if(currentBarTime == m_lastMoneyFlowCalc)
         return m_cachedMoneyFlow;

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

      double flow = (volSum > 0) ? flowSum / volSum : 0;

      // Cache result
      m_cachedMoneyFlow = flow;
      m_lastMoneyFlowCalc = currentBarTime;

      return flow;
   }
};

#endif
