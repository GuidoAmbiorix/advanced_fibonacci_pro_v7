//+------------------------------------------------------------------+
//|                                               VolumeAnalysis.mqh |
//|          Basic Volume Price Analysis for Confluence               |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef VOLUME_ANALYSIS_MQH
#define VOLUME_ANALYSIS_MQH

class CVolumeAnalysis
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   double            m_cachedRVOL;
   double            m_cachedMoneyFlow;
   datetime          m_lastRVOLCalc;
   datetime          m_lastMoneyFlowCalc;

public:
   CVolumeAnalysis()
   {
      m_symbol = _Symbol;
      m_timeframe = PERIOD_CURRENT;
      m_cachedRVOL = 0;
      m_cachedMoneyFlow = 0;
      m_lastRVOLCalc = 0;
      m_lastMoneyFlowCalc = 0;
   }

   bool Init(string symbol, ENUM_TIMEFRAMES tf)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-4 pts)                                   |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;
      double rvol = CalculateRVOL(20);
      double flow = CalculateRapidMoneyFlow(5);

      // RVOL: 0-2 pts
      if(rvol > 2.5) score += 2.0; // institutional ignition
      else if(rvol > 1.5) score += 1.0; // above average

      // Money Flow Alignment: 0-2 pts
      if(direction == 1 && flow > 0.3) score += 2.0;
      if(direction == -1 && flow < -0.3) score += 2.0;
      else if(direction == 1 && flow > 0.1) score += 1.0;
      else if(direction == -1 && flow < -0.1) score += 1.0;

      return score;
   }

   //+------------------------------------------------------------------+
   //| Calculate Relative Volume (RVOL)                                 |
   //+------------------------------------------------------------------+
   double CalculateRVOL(int period)
   {
      datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
      if(currentBarTime == m_lastRVOLCalc) return m_cachedRVOL;

      long currentVol = iVolume(m_symbol, m_timeframe, 0);
      double volSum = 0;

      // Calculate average volume for same time of day over last N days
      // For simplicity here, use last N bars
      for(int i = 1; i <= period; i++)
      {
         volSum += (double)iVolume(m_symbol, m_timeframe, i);
      }

      double avgVol = volSum / period;
      double rvol = (avgVol > 0) ? (double)currentVol / avgVol : 1.0;

      // Cache result
      m_cachedRVOL = rvol;
      m_lastRVOLCalc = currentBarTime;

      return rvol;
   }

   //+------------------------------------------------------------------+
   //| Calculate Rapid Money Flow (-1 to 1)                             |
   //+------------------------------------------------------------------+
   double CalculateRapidMoneyFlow(int bars)
   {
      datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
      if(currentBarTime == m_lastMoneyFlowCalc) return m_cachedMoneyFlow;

      double flowSum = 0;
      double volSum = 0;

      for(int i = 0; i < bars; i++)
      {
         double close = iClose(m_symbol, m_timeframe, i);
         double open = iOpen(m_symbol, m_timeframe, i);
         long vol = iVolume(m_symbol, m_timeframe, i);

         // Directional volume
         double dir = (close > open) ? 1.0 : (close < open) ? -1.0 : 0;
         flowSum += dir * (double)vol;
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
