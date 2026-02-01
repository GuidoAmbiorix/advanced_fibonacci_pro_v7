//+------------------------------------------------------------------+
//|                                            SMC_Inducement.mqh    |
//|          Liquidity Grabs & Stop Hunts (Inducement Detection)     |
//|                                  Copyright 2026, Guido Ambiorix  |
//+------------------------------------------------------------------+
#ifndef SMC_INDUCEMENT_MQH
#define SMC_INDUCEMENT_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Inducement Event                                                  |
//+------------------------------------------------------------------+
struct InducementEvent
{
   int      direction;      // 1=bullish sweep (buy inducement), -1=bearish sweep
   double   level;          // Swing level that was swept
   double   sweepDepth;     // How far beyond level (ATR multiple)
   datetime time;           // When sweep occurred
   bool     reversing;      // Is price reversing after sweep?
};

//+------------------------------------------------------------------+
//| INDUCEMENT DETECTOR                                               |
//+------------------------------------------------------------------+
class CSMCInducement
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_lookbackBars;     // Bars to scan for swings
   double            m_minSweepATR;      // Min sweep depth to qualify
   
   int               m_hATR;
   double            m_currentATR;
   
   // Recent swing levels (potential liquidity pools)
   double            m_recentHighs[10];
   double            m_recentLows[10];
   int               m_highCount;
   int               m_lowCount;
   
   // Recent inducement events
   InducementEvent   m_recentSweeps[5];
   int               m_sweepCount;

public:
   CSMCInducement() : m_lookbackBars(10), m_minSweepATR(0.3),
                      m_hATR(INVALID_HANDLE), m_highCount(0),
                      m_lowCount(0), m_sweepCount(0) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 10,
             double minSweep = 0.3)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_lookbackBars = lookback;
      m_minSweepATR = minSweep;
      
      m_hATR = iATR(m_symbol, m_timeframe, 14);
      if(m_hATR == INVALID_HANDLE) return false;
      
      // Initialize swing tracking
      UpdateSwingLevels();
      
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update - Call on new bar                                         |
   //+------------------------------------------------------------------+
   void Update()
   {
      // Update ATR
      double atrBuf[1];
      if(CopyBuffer(m_hATR, 0, 1, 1, atrBuf) != 1) return;
      m_currentATR = atrBuf[0];
      
      // Update swing levels
      UpdateSwingLevels();
      
      // Check for liquidity sweeps
      CheckForSweeps();
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score                                             |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;
      
      // Check recent sweeps aligned with direction
      for(int i = 0; i < m_sweepCount; i++)
      {
         // Only consider very recent sweeps (last 3 bars)
         int barsSince = iBarShift(m_symbol, m_timeframe, m_recentSweeps[i].time);
         if(barsSince > 3) continue;
         
         // Bullish inducement: swept lows, now reversing up
         if(direction == 1 && m_recentSweeps[i].direction == 1)
         {
            if(m_recentSweeps[i].reversing)
               score = 1.5;  // Strong inducement
            else
               score = MathMax(score, 0.5);  // Sweep detected but not confirmed
         }
         // Bearish inducement: swept highs, now reversing down
         else if(direction == -1 && m_recentSweeps[i].direction == -1)
         {
            if(m_recentSweeps[i].reversing)
               score = 1.5;  // Strong inducement
            else
               score = MathMax(score, 0.5);  // Sweep detected but not confirmed
         }
      }
      
      return score;
   }

   //+------------------------------------------------------------------+
   //| Get Last Inducement                                              |
   //+------------------------------------------------------------------+
   bool GetLastInducement(InducementEvent &evt)
   {
      if(m_sweepCount == 0) return false;
      evt = m_recentSweeps[0];
      return true;
   }

private:
   //+------------------------------------------------------------------+
   //| Update Swing Levels                                              |
   //+------------------------------------------------------------------+
   void UpdateSwingLevels()
   {
      // Reset arrays
      m_highCount = 0;
      m_lowCount = 0;
      
      // Scan recent bars for swing highs/lows
      for(int i = 2; i <= m_lookbackBars; i++)
      {
         double h1 = iHigh(m_symbol, m_timeframe, i-1);
         double h2 = iHigh(m_symbol, m_timeframe, i);
         double h3 = iHigh(m_symbol, m_timeframe, i+1);
         
         double l1 = iLow(m_symbol, m_timeframe, i-1);
         double l2 = iLow(m_symbol, m_timeframe, i);
         double l3 = iLow(m_symbol, m_timeframe, i+1);
         
         // Swing high (local peak)
         if(h2 > h1 && h2 > h3 && m_highCount < 10)
         {
            m_recentHighs[m_highCount++] = h2;
         }
         
         // Swing low (local trough)
         if(l2 < l1 && l2 < l3 && m_lowCount < 10)
         {
            m_recentLows[m_lowCount++] = l2;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check for Liquidity Sweeps                                       |
   //+------------------------------------------------------------------+
   void CheckForSweeps()
   {
      double currentHigh = iHigh(m_symbol, m_timeframe, 0);
      double currentLow = iLow(m_symbol, m_timeframe, 0);
      double prevClose = iClose(m_symbol, m_timeframe, 1);
      double currentClose = iClose(m_symbol, m_timeframe, 0);
      
      // Check for sweep of LOWS (bullish inducement)
      for(int i = 0; i < m_lowCount; i++)
      {
         double swingLow = m_recentLows[i];
         
         // Price pushed below swing low
         if(currentLow < swingLow)
         {
            double sweepDepth = (swingLow - currentLow) / m_currentATR;
            
            if(sweepDepth >= m_minSweepATR)
            {
               // Check if reversing (close back above swing low)
               bool reversing = (currentClose > swingLow);
               
               AddSweep(1, swingLow, sweepDepth, reversing);
               break;  // Only one sweep per update
            }
         }
      }
      
      // Check for sweep of HIGHS (bearish inducement)
      for(int i = 0; i < m_highCount; i++)
      {
         double swingHigh = m_recentHighs[i];
         
         // Price pushed above swing high
         if(currentHigh > swingHigh)
         {
            double sweepDepth = (currentHigh - swingHigh) / m_currentATR;
            
            if(sweepDepth >= m_minSweepATR)
            {
               // Check if reversing (close back below swing high)
               bool reversing = (currentClose < swingHigh);
               
               AddSweep(-1, swingHigh, sweepDepth, reversing);
               break;  // Only one sweep per update
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add Sweep Event                                                  |
   //+------------------------------------------------------------------+
   void AddSweep(int direction, double level, double depth, bool reversing)
   {
      // Check if duplicate
      for(int i = 0; i < m_sweepCount; i++)
      {
         if(m_recentSweeps[i].direction == direction &&
            MathAbs(m_recentSweeps[i].level - level) < m_currentATR * 0.5)
            return;
      }
      
      InducementEvent evt;
      evt.direction = direction;
      evt.level = level;
      evt.sweepDepth = depth;
      evt.time = iTime(m_symbol, m_timeframe, 0);
      evt.reversing = reversing;
      
      // Add to array (newest first)
      if(m_sweepCount >= 5)
      {
         // Shift old events
         for(int i = 4; i > 0; i--)
            m_recentSweeps[i] = m_recentSweeps[i-1];
         m_recentSweeps[0] = evt;
      }
      else
      {
         // Shift and add
         for(int i = m_sweepCount; i > 0; i--)
            m_recentSweeps[i] = m_recentSweeps[i-1];
         m_recentSweeps[0] = evt;
         m_sweepCount++;
      }
      
      string dir = (direction == 1) ? "BULLISH" : "BEARISH";
      string rev = reversing ? " [REVERSING]" : "";
      Print("🎣 INDUCEMENT: ", dir, " sweep @ ", DoubleToString(level, 5),
            " | Depth: ", DoubleToString(depth, 2), " ATR", rev);
   }

   //+------------------------------------------------------------------+
   //| String Representation                                            |
   //+------------------------------------------------------------------+
   string ToString()
   {
      return "Inducement: " + IntegerToString(m_sweepCount) + " recent sweeps";
   }
};

#endif
