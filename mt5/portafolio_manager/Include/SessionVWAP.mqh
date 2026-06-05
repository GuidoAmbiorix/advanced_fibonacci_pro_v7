//+------------------------------------------------------------------+
//|                                                 SessionVWAP.mqh  |
//|  Session VWAP — Volume Weighted Average Price for current day.   |
//|  Institutional fair value anchor: OBs/FVGs near VWAP are        |
//|  significantly stronger than those far from it.                  |
//+------------------------------------------------------------------+
#ifndef SESSION_VWAP_MQH
#define SESSION_VWAP_MQH

class CSessionVWAP
{
private:
   string   m_symbol;
   double   m_vwap;
   datetime m_lastUpdate;
   datetime m_lastSessionDay;

public:
   CSessionVWAP()
   {
      m_symbol         = "";
      m_vwap           = 0;
      m_lastUpdate     = 0;
      m_lastSessionDay = 0;
   }

   bool Init(string symbol)
   {
      m_symbol = symbol;
      return true;
   }

   //+----------------------------------------------------------------+
   //| Recalculate VWAP for today's session.                          |
   //| Uses M5 tick-volume bars since D1 open (Exness UTC+0 friendly) |
   //+----------------------------------------------------------------+
   void Update()
   {
      if(m_symbol == "") return;

      // Session start = today's D1 bar open time
      datetime sessionStart = iTime(m_symbol, PERIOD_D1, 0);
      if(sessionStart <= 0) return;

      // Throttle: recompute at most once per minute
      if(TimeCurrent() - m_lastUpdate < 60 && m_lastSessionDay == sessionStart) return;
      m_lastUpdate     = TimeCurrent();
      m_lastSessionDay = sessionStart;

      // Collect M5 bar times to determine how many bars belong to today
      datetime times[];
      ArraySetAsSeries(times, true);
      int fetched = CopyTime(m_symbol, PERIOD_M5, 0, 500, times);
      if(fetched <= 0) return;

      int todayBars = 0;
      for(int i = 0; i < fetched; i++)
      {
         if(times[i] >= sessionStart) todayBars++;
         else break; // series is newest-first; older bars come after, stop here
      }
      if(todayBars <= 0) return;

      // Fetch OHLC + tick volume for today's bars
      double   highs[], lows[], closes[];
      long     volumes[];
      ArraySetAsSeries(highs,   true);
      ArraySetAsSeries(lows,    true);
      ArraySetAsSeries(closes,  true);
      ArraySetAsSeries(volumes, true);

      if(CopyHigh(m_symbol,       PERIOD_M5, 0, todayBars, highs)       < todayBars) return;
      if(CopyLow(m_symbol,        PERIOD_M5, 0, todayBars, lows)        < todayBars) return;
      if(CopyClose(m_symbol,      PERIOD_M5, 0, todayBars, closes)      < todayBars) return;
      if(CopyTickVolume(m_symbol, PERIOD_M5, 0, todayBars, volumes)     < todayBars) return;

      double cumTP  = 0.0;
      double cumVol = 0.0;
      for(int i = 0; i < todayBars; i++)
      {
         double tp = (highs[i] + lows[i] + closes[i]) / 3.0;
         double v  = (double)volumes[i];
         if(v <= 0) v = 1; // avoid zero-volume bars killing the calc
         cumTP  += tp * v;
         cumVol += v;
      }

      if(cumVol > 0) m_vwap = cumTP / cumVol;
   }

   double GetVWAP() { return m_vwap; }

   //+----------------------------------------------------------------+
   //| Confluence score contribution: -1 to +2                        |
   //|  +2 = price at VWAP (institutional anchor, strongest)          |
   //|  +1 = price on correct side of VWAP (value zone)              |
   //|  -1 = price on wrong side (extended, mean-reversion risk)      |
   //+----------------------------------------------------------------+
   double GetConfluenceScore(int direction, double currentPrice, double atr)
   {
      if(m_vwap <= 0.0 || atr <= 0.0) return 0.0;

      double dist  = currentPrice - m_vwap;
      bool atVWAP  = (MathAbs(dist) <= atr * 0.30); // within 0.3 ATR = "at VWAP"

      if(direction == 1) // Buy
      {
         if(atVWAP)   return  2.0;  // Price at VWAP anchor — strongest buy zone
         if(dist < 0) return  1.0;  // Below VWAP — value area, institutions buying
         return -1.0;                // Above VWAP — extended, buying into distribution
      }
      else // Sell
      {
         if(atVWAP)   return  2.0;  // At VWAP anchor
         if(dist > 0) return  1.0;  // Above VWAP — premium area, institutions selling
         return -1.0;                // Below VWAP — extended, selling into accumulation
      }
   }
};

#endif
