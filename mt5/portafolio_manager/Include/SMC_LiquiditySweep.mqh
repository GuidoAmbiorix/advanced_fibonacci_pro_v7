//+------------------------------------------------------------------+
//|                                           SMC_LiquiditySweep.mqh |
//|          Smart Money Concepts - Liquidity Sweep Detection         |
//|                                  Copyright 2026, Infernal Portfolio Governor   |
//+------------------------------------------------------------------+
#ifndef SMC_LIQUIDITY_SWEEP_MQH
#define SMC_LIQUIDITY_SWEEP_MQH

#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| LIQUIDITY LEVEL TYPES                                             |
//+------------------------------------------------------------------+
enum ENUM_LIQUIDITY_TYPE
{
   LIQ_NONE = 0,
   LIQ_PDH = 1,         // Previous Day High
   LIQ_PDL = 2,         // Previous Day Low
   LIQ_PWH = 3,         // Previous Week High
   LIQ_PWL = 4,         // Previous Week Low
   LIQ_SESSION_HIGH = 5, // Session High (Asian, London, NY)
   LIQ_SESSION_LOW = 6,  // Session Low
   LIQ_SWING_HIGH = 7,   // Recent Swing High
   LIQ_SWING_LOW = 8,    // Recent Swing Low
   LIQ_EQUAL_HIGHS = 9,  // Equal Highs (liquidity pool)
   LIQ_EQUAL_LOWS = 10   // Equal Lows (liquidity pool)
};

//+------------------------------------------------------------------+
//| SWEEP STATUS                                                      |
//+------------------------------------------------------------------+
enum ENUM_SWEEP_STATUS
{
   SWEEP_NONE = 0,
   SWEEP_IN_PROGRESS = 1,  // Price is sweeping (wick beyond level)
   SWEEP_CONFIRMED = 2,    // Sweep + rejection confirmed
   SWEEP_FAILED = 3        // Sweep but no rejection (breakout)
};

//+------------------------------------------------------------------+
//| LIQUIDITY LEVEL STRUCTURE                                         |
//+------------------------------------------------------------------+
struct LiquidityLevel
{
   ENUM_LIQUIDITY_TYPE type;
   double              price;
   datetime            time;
   bool                isHighSide;      // true = resistance, false = support
   bool                swept;           // Has been swept
   datetime            sweepTime;       // When it was swept
   bool                rejectionConfirmed; // Price rejected after sweep
   double              sweepWickSize;   // Size of the sweep wick
};

//+------------------------------------------------------------------+
//| LIQUIDITY SWEEP MODULE                                            |
//| Responsibility: Detect liquidity pools and sweeps                 |
//+------------------------------------------------------------------+
class CSMCLiquiditySweep
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_swingLookback;     // Bars to look for swing points
   double          m_equalLevelTolerance; // Tolerance for "equal" highs/lows
   int             m_rejectionBars;     // Bars to confirm rejection

   LiquidityLevel  m_levels[];          // Active liquidity levels
   int             m_maxLevels;

   // Previous period data
   double          m_pdh, m_pdl;        // Previous Day High/Low
   double          m_pwh, m_pwl;        // Previous Week High/Low
   double          m_asianHigh, m_asianLow;
   double          m_londonHigh, m_londonLow;

   // Recent sweep info
   ENUM_SWEEP_STATUS m_lastSweepStatus;
   ENUM_LIQUIDITY_TYPE m_lastSweptType;
   double          m_lastSweptPrice;
   datetime        m_lastSweepTime;
   bool            m_bullishSweepActive;  // Bearish sweep = bullish signal
   bool            m_bearishSweepActive;  // Bullish sweep = bearish signal

   int             m_hATR;
   double          m_currentATR;

public:
   CSMCLiquiditySweep() : m_swingLookback(20), m_equalLevelTolerance(0.0002),
                          m_rejectionBars(3), m_maxLevels(20),
                          m_lastSweepStatus(SWEEP_NONE), m_hATR(INVALID_HANDLE) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int swingLookback = 20,
             double equalTolerance = 0.0002)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_swingLookback = swingLookback;
      m_equalLevelTolerance = equalTolerance;

      ArrayResize(m_levels, 0);

      m_hATR = iATR(m_symbol, m_timeframe, 14);
      if(m_hATR == INVALID_HANDLE) return false;

      // Initial calculation of key levels
      CalculatePDLevels();
      CalculatePWLevels();
      IdentifySwingLevels();
      IdentifyEqualLevels();

      return true;
   }

   //+------------------------------------------------------------------+
   //| Deinitialize                                                      |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      if(m_hATR != INVALID_HANDLE)
      {
         IndicatorRelease(m_hATR);
         m_hATR = INVALID_HANDLE;
      }
   }

   //+------------------------------------------------------------------+
   //| Update - Call on each new bar                                     |
   //+------------------------------------------------------------------+
   void Update()
   {
      // Update ATR
      double atrBuf[1];
      if(CopyBuffer(m_hATR, 0, 1, 1, atrBuf) != 1) return;
      m_currentATR = atrBuf[0];

      // Check for new day/week
      CheckPeriodChange();

      // Update swing and equal levels
      IdentifySwingLevels();
      IdentifyEqualLevels();

      // Check for sweeps
      CheckForSweeps();

      // Confirm rejections
      ConfirmRejections();

      // Cleanup old levels
      CleanupLevels();
   }

   //+------------------------------------------------------------------+
   //| Calculate Previous Day High/Low                                   |
   //+------------------------------------------------------------------+
   void CalculatePDLevels()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Find yesterday's range
      datetime todayStart = StringToTime(IntegerToString(dt.year) + "." +
                                         IntegerToString(dt.mon) + "." +
                                         IntegerToString(dt.day));
      datetime yesterdayStart = todayStart - 86400;

      int startBar = iBarShift(m_symbol, PERIOD_D1, yesterdayStart, false);
      if(startBar >= 0)
      {
         m_pdh = iHigh(m_symbol, PERIOD_D1, startBar);
         m_pdl = iLow(m_symbol, PERIOD_D1, startBar);

         AddLiquidityLevel(LIQ_PDH, m_pdh, true);
         AddLiquidityLevel(LIQ_PDL, m_pdl, false);
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Previous Week High/Low                                  |
   //+------------------------------------------------------------------+
   void CalculatePWLevels()
   {
      // Get last week's range
      int startBar = iBarShift(m_symbol, PERIOD_W1, TimeCurrent() - 604800, false);
      if(startBar >= 0 && startBar < iBars(m_symbol, PERIOD_W1))
      {
         m_pwh = iHigh(m_symbol, PERIOD_W1, startBar);
         m_pwl = iLow(m_symbol, PERIOD_W1, startBar);

         AddLiquidityLevel(LIQ_PWH, m_pwh, true);
         AddLiquidityLevel(LIQ_PWL, m_pwl, false);
      }
   }

   //+------------------------------------------------------------------+
   //| Identify Swing High/Low levels                                    |
   //+------------------------------------------------------------------+
   void IdentifySwingLevels()
   {
      // Find swing highs
      for(int i = 2; i < m_swingLookback - 2; i++)
      {
         double high = iHigh(m_symbol, m_timeframe, i);
         bool isSwingHigh = true;

         for(int j = 1; j <= 2; j++)
         {
            if(iHigh(m_symbol, m_timeframe, i - j) >= high ||
               iHigh(m_symbol, m_timeframe, i + j) >= high)
            {
               isSwingHigh = false;
               break;
            }
         }

         if(isSwingHigh)
            AddLiquidityLevel(LIQ_SWING_HIGH, high, true);
      }

      // Find swing lows
      for(int i = 2; i < m_swingLookback - 2; i++)
      {
         double low = iLow(m_symbol, m_timeframe, i);
         bool isSwingLow = true;

         for(int j = 1; j <= 2; j++)
         {
            if(iLow(m_symbol, m_timeframe, i - j) <= low ||
               iLow(m_symbol, m_timeframe, i + j) <= low)
            {
               isSwingLow = false;
               break;
            }
         }

         if(isSwingLow)
            AddLiquidityLevel(LIQ_SWING_LOW, low, false);
      }
   }

   //+------------------------------------------------------------------+
   //| Identify Equal Highs/Lows (liquidity pools)                       |
   //+------------------------------------------------------------------+
   void IdentifyEqualLevels()
   {
      double tolerance = m_currentATR * 0.1;  // Dynamic tolerance

      // Look for equal highs
      for(int i = 2; i < m_swingLookback - 2; i++)
      {
         double high1 = iHigh(m_symbol, m_timeframe, i);

         for(int j = i + 3; j < m_swingLookback; j++)
         {
            double high2 = iHigh(m_symbol, m_timeframe, j);

            if(MathAbs(high1 - high2) <= tolerance)
            {
               // Found equal highs - strong liquidity pool
               double avgLevel = (high1 + high2) / 2.0;
               AddLiquidityLevel(LIQ_EQUAL_HIGHS, avgLevel, true);
               break;
            }
         }
      }

      // Look for equal lows
      for(int i = 2; i < m_swingLookback - 2; i++)
      {
         double low1 = iLow(m_symbol, m_timeframe, i);

         for(int j = i + 3; j < m_swingLookback; j++)
         {
            double low2 = iLow(m_symbol, m_timeframe, j);

            if(MathAbs(low1 - low2) <= tolerance)
            {
               double avgLevel = (low1 + low2) / 2.0;
               AddLiquidityLevel(LIQ_EQUAL_LOWS, avgLevel, false);
               break;
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add liquidity level                                               |
   //+------------------------------------------------------------------+
   void AddLiquidityLevel(ENUM_LIQUIDITY_TYPE type, double price, bool isHighSide)
   {
      // Check if level already exists
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(MathAbs(m_levels[i].price - price) < m_currentATR * 0.2)
            return;  // Similar level exists
      }

      LiquidityLevel lvl;
      lvl.type = type;
      lvl.price = price;
      lvl.time = TimeCurrent();
      lvl.isHighSide = isHighSide;
      lvl.swept = false;
      lvl.sweepTime = 0;
      lvl.rejectionConfirmed = false;
      lvl.sweepWickSize = 0;

      int size = ArraySize(m_levels);
      if(size >= m_maxLevels)
      {
         // Remove oldest
         for(int i = 0; i < size - 1; i++)
            m_levels[i] = m_levels[i+1];
         ArrayResize(m_levels, m_maxLevels);
         m_levels[m_maxLevels - 1] = lvl;
      }
      else
      {
         ArrayResize(m_levels, size + 1);
         m_levels[size] = lvl;
      }
   }

   //+------------------------------------------------------------------+
   //| Check for period change (new day/week)                            |
   //+------------------------------------------------------------------+
   void CheckPeriodChange()
   {
      static datetime lastDay = 0;
      static datetime lastWeek = 0;

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      datetime currentDay = StringToTime(IntegerToString(dt.year) + "." +
                                         IntegerToString(dt.mon) + "." +
                                         IntegerToString(dt.day));

      if(currentDay != lastDay)
      {
         lastDay = currentDay;
         CalculatePDLevels();
      }

      // Check for new week (Monday)
      if(dt.day_of_week == 1)
      {
         datetime weekStart = currentDay;
         if(weekStart != lastWeek)
         {
            lastWeek = weekStart;
            CalculatePWLevels();
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check for sweeps                                                  |
   //+------------------------------------------------------------------+
   void CheckForSweeps()
   {
      double currentHigh = iHigh(m_symbol, m_timeframe, 0);
      double currentLow = iLow(m_symbol, m_timeframe, 0);
      double currentClose = iClose(m_symbol, m_timeframe, 0);
      double currentOpen = iOpen(m_symbol, m_timeframe, 0);

      m_bullishSweepActive = false;
      m_bearishSweepActive = false;

      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(m_levels[i].swept) continue;

         // Check for sweep of high-side liquidity (sweep up = bearish signal)
         if(m_levels[i].isHighSide)
         {
            // Wick above the level but close below = sweep
            if(currentHigh > m_levels[i].price && currentClose < m_levels[i].price)
            {
               m_levels[i].swept = true;
               m_levels[i].sweepTime = TimeCurrent();
               m_levels[i].sweepWickSize = currentHigh - m_levels[i].price;

               m_lastSweepStatus = SWEEP_IN_PROGRESS;
               m_lastSweptType = m_levels[i].type;
               m_lastSweptPrice = m_levels[i].price;
               m_lastSweepTime = TimeCurrent();
               m_bearishSweepActive = true;  // Sweep of highs = bearish signal
            }
         }
         // Check for sweep of low-side liquidity (sweep down = bullish signal)
         else
         {
            // Wick below the level but close above = sweep
            if(currentLow < m_levels[i].price && currentClose > m_levels[i].price)
            {
               m_levels[i].swept = true;
               m_levels[i].sweepTime = TimeCurrent();
               m_levels[i].sweepWickSize = m_levels[i].price - currentLow;

               m_lastSweepStatus = SWEEP_IN_PROGRESS;
               m_lastSweptType = m_levels[i].type;
               m_lastSweptPrice = m_levels[i].price;
               m_lastSweepTime = TimeCurrent();
               m_bullishSweepActive = true;  // Sweep of lows = bullish signal
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Confirm rejections after sweep                                    |
   //+------------------------------------------------------------------+
   void ConfirmRejections()
   {
      if(m_lastSweepStatus != SWEEP_IN_PROGRESS) return;

      int barsSinceSweep = iBarShift(m_symbol, m_timeframe, m_lastSweepTime, false);

      if(barsSinceSweep >= m_rejectionBars)
      {
         double closeNow = iClose(m_symbol, m_timeframe, 0);

         // For high-side sweep: confirm if price moved away (down)
         for(int i = 0; i < ArraySize(m_levels); i++)
         {
            if(!m_levels[i].swept || m_levels[i].rejectionConfirmed) continue;

            if(m_levels[i].isHighSide)
            {
               if(closeNow < m_levels[i].price - m_currentATR * 0.5)
               {
                  m_levels[i].rejectionConfirmed = true;
                  m_lastSweepStatus = SWEEP_CONFIRMED;
               }
               else if(closeNow > m_levels[i].price + m_currentATR * 0.3)
               {
                  m_lastSweepStatus = SWEEP_FAILED;  // Breakout, not sweep
               }
            }
            else
            {
               if(closeNow > m_levels[i].price + m_currentATR * 0.5)
               {
                  m_levels[i].rejectionConfirmed = true;
                  m_lastSweepStatus = SWEEP_CONFIRMED;
               }
               else if(closeNow < m_levels[i].price - m_currentATR * 0.3)
               {
                  m_lastSweepStatus = SWEEP_FAILED;
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Cleanup old levels                                                |
   //+------------------------------------------------------------------+
   void CleanupLevels()
   {
      // Remove swept and confirmed levels (already used)
      for(int i = ArraySize(m_levels) - 1; i >= 0; i--)
      {
         if(m_levels[i].swept && m_levels[i].rejectionConfirmed)
         {
            for(int j = i; j < ArraySize(m_levels) - 1; j++)
               m_levels[j] = m_levels[j+1];
            ArrayResize(m_levels, ArraySize(m_levels) - 1);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check if sweep supports direction                                 |
   //+------------------------------------------------------------------+
   bool IsSweepAligned(int direction)
   {
      // Bullish direction: need sweep of lows
      if(direction == 1 && m_bullishSweepActive) return true;

      // Bearish direction: need sweep of highs
      if(direction == -1 && m_bearishSweepActive) return true;

      // Also check recent confirmed sweeps
      int barsSinceSweep = iBarShift(m_symbol, m_timeframe, m_lastSweepTime, false);

      if(barsSinceSweep <= 10 && m_lastSweepStatus == SWEEP_CONFIRMED)
      {
         // Check if the sweep direction aligns
         for(int i = 0; i < ArraySize(m_levels); i++)
         {
            if(m_levels[i].swept && m_levels[i].rejectionConfirmed)
            {
               if(direction == 1 && !m_levels[i].isHighSide) return true;
               if(direction == -1 && m_levels[i].isHighSide) return true;
            }
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get confluence score contribution (0-1.5)                         |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;

      if(IsSweepAligned(direction))
      {
         score = 1.0;  // Base score for aligned sweep

         // Bonus for PDH/PDL sweep (most significant)
         if(m_lastSweptType == LIQ_PDH || m_lastSweptType == LIQ_PDL)
            score += 0.3;

         // Bonus for PWH/PWL sweep (weekly is major)
         if(m_lastSweptType == LIQ_PWH || m_lastSweptType == LIQ_PWL)
            score += 0.5;

         // Bonus for equal highs/lows (strongest liquidity pools)
         if(m_lastSweptType == LIQ_EQUAL_HIGHS || m_lastSweptType == LIQ_EQUAL_LOWS)
            score += 0.4;
      }

      return MathMin(score, 1.5);  // Cap at 1.5
   }

   //+------------------------------------------------------------------+
   //| Get nearest liquidity level                                       |
   //+------------------------------------------------------------------+
   bool GetNearestLevel(int direction, double &levelPrice, ENUM_LIQUIDITY_TYPE &levelType)
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      double nearestDist = 999999;
      int nearestIdx = -1;

      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(m_levels[i].swept) continue;

         double dist;
         if(direction == 1)  // Looking for support (liquidity below)
         {
            if(!m_levels[i].isHighSide)
            {
               dist = currentPrice - m_levels[i].price;
               if(dist > 0 && dist < nearestDist)
               {
                  nearestDist = dist;
                  nearestIdx = i;
               }
            }
         }
         else  // Looking for resistance (liquidity above)
         {
            if(m_levels[i].isHighSide)
            {
               dist = m_levels[i].price - currentPrice;
               if(dist > 0 && dist < nearestDist)
               {
                  nearestDist = dist;
                  nearestIdx = i;
               }
            }
         }
      }

      if(nearestIdx >= 0)
      {
         levelPrice = m_levels[nearestIdx].price;
         levelType = m_levels[nearestIdx].type;
         return true;
      }

      levelPrice = 0;
      levelType = LIQ_NONE;
      return false;
   }

   //+------------------------------------------------------------------+
   //| Get PDH/PDL                                                       |
   //+------------------------------------------------------------------+
   double GetPDH() { return m_pdh; }
   double GetPDL() { return m_pdl; }
   double GetPWH() { return m_pwh; }
   double GetPWL() { return m_pwl; }

   //+------------------------------------------------------------------+
   //| Get string representation                                         |
   //+------------------------------------------------------------------+
   string ToString()
   {
      string sweepStr = "NONE";
      if(m_bullishSweepActive) sweepStr = "BULL";
      if(m_bearishSweepActive) sweepStr = "BEAR";

      return "LIQ: Levels=" + IntegerToString(ArraySize(m_levels)) +
             " Sweep=" + sweepStr;
   }

   //+------------------------------------------------------------------+
   //| Get liquidity type as string                                      |
   //+------------------------------------------------------------------+
   string TypeToString(ENUM_LIQUIDITY_TYPE type)
   {
      switch(type)
      {
         case LIQ_PDH: return "PDH";
         case LIQ_PDL: return "PDL";
         case LIQ_PWH: return "PWH";
         case LIQ_PWL: return "PWL";
         case LIQ_SWING_HIGH: return "SwingH";
         case LIQ_SWING_LOW: return "SwingL";
         case LIQ_EQUAL_HIGHS: return "EQH";
         case LIQ_EQUAL_LOWS: return "EQL";
         default: return "?";
      }
   }
};

#endif
