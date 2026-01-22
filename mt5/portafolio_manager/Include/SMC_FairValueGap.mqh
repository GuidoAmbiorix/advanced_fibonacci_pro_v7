//+------------------------------------------------------------------+
//|                                             SMC_FairValueGap.mqh |
//|          Smart Money Concepts - Fair Value Gap Detection          |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef SMC_FAIR_VALUE_GAP_MQH
#define SMC_FAIR_VALUE_GAP_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| FVG TYPES                                                         |
//+------------------------------------------------------------------+
enum ENUM_FVG_TYPE
{
   FVG_NONE = 0,
   FVG_BULLISH = 1,    // Gap up (price tends to retrace down to fill)
   FVG_BEARISH = 2     // Gap down (price tends to retrace up to fill)
};

//+------------------------------------------------------------------+
//| FVG MITIGATION STATUS                                             |
//+------------------------------------------------------------------+
enum ENUM_FVG_STATUS
{
   FVG_OPEN = 0,        // Gap still exists
   FVG_PARTIAL = 1,     // Partially filled (50% rule)
   FVG_FILLED = 2       // Completely filled
};

//+------------------------------------------------------------------+
//| FAIR VALUE GAP STRUCTURE                                          |
//+------------------------------------------------------------------+
struct FairValueGap
{
   ENUM_FVG_TYPE   type;
   double          top;           // Top of the gap
   double          bottom;        // Bottom of the gap
   double          midline;       // 50% of the gap (key level)
   double          size;          // Gap size in price
   datetime        time;          // When FVG was created
   int             barIndex;      // Bar index when created
   ENUM_FVG_STATUS status;        // Current status
   double          fillPercent;   // How much has been filled (0-100)
   double          consequentEncroachment; // CE level (50% of FVG)
};

//+------------------------------------------------------------------+
//| FAIR VALUE GAP MODULE                                             |
//| Responsibility: Detect and track FVGs (imbalances)                |
//+------------------------------------------------------------------+
class CSMCFairValueGap
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_lookback;        // Bars to scan for FVGs
   int             m_maxFVGs;         // Max FVGs to track
   double          m_minFVGATR;       // Min FVG size (ATR multiple)

   FairValueGap    m_bullishFVGs[];   // Active bullish FVGs
   FairValueGap    m_bearishFVGs[];   // Active bearish FVGs

   int             m_hATR;
   double          m_currentATR;

public:
   CSMCFairValueGap() : m_lookback(50), m_maxFVGs(10), m_minFVGATR(0.5),
                        m_hATR(INVALID_HANDLE) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 50,
             int maxFVGs = 10, double minFVGATR = 0.5)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_lookback = lookback;
      m_maxFVGs = maxFVGs;
      m_minFVGATR = minFVGATR;

      ArrayResize(m_bullishFVGs, 0);
      ArrayResize(m_bearishFVGs, 0);

      m_hATR = iATR(m_symbol, m_timeframe, 14);
      if(m_hATR == INVALID_HANDLE) return false;

      // Initial scan for existing FVGs
      ScanForFVGs();

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

      // Check for new FVGs at bar 2 (confirmed)
      CheckForNewFVG(2);

      // Update mitigation status
      UpdateFVGStatus();

      // Cleanup filled FVGs
      CleanupFVGs();
   }

   //+------------------------------------------------------------------+
   //| Scan for FVGs in history                                          |
   //+------------------------------------------------------------------+
   void ScanForFVGs()
   {
      double atrBuf[1];
      if(CopyBuffer(m_hATR, 0, 1, 1, atrBuf) != 1) return;
      m_currentATR = atrBuf[0];

      for(int i = m_lookback; i >= 2; i--)
      {
         CheckForNewFVG(i);
      }
   }

   //+------------------------------------------------------------------+
   //| Check for new FVG at specific bar                                 |
   //+------------------------------------------------------------------+
   void CheckForNewFVG(int barIndex)
   {
      // FVG requires 3 candles: bar+1 (left), bar (middle), bar-1 (right)
      // The gap is between the wick of bar+1 and bar-1

      if(barIndex < 1) return;

      double highLeft = iHigh(m_symbol, m_timeframe, barIndex + 1);
      double lowLeft = iLow(m_symbol, m_timeframe, barIndex + 1);
      double highMiddle = iHigh(m_symbol, m_timeframe, barIndex);
      double lowMiddle = iLow(m_symbol, m_timeframe, barIndex);
      double highRight = iHigh(m_symbol, m_timeframe, barIndex - 1);
      double lowRight = iLow(m_symbol, m_timeframe, barIndex - 1);

      // Bullish FVG: Low of bar-1 > High of bar+1
      // This means there's a gap that price didn't trade through
      if(lowRight > highLeft)
      {
         double gapSize = lowRight - highLeft;
         if(gapSize >= m_currentATR * m_minFVGATR)
         {
            AddFVG(FVG_BULLISH, lowRight, highLeft, barIndex, gapSize);
         }
      }

      // Bearish FVG: High of bar-1 < Low of bar+1
      if(highRight < lowLeft)
      {
         double gapSize = lowLeft - highRight;
         if(gapSize >= m_currentATR * m_minFVGATR)
         {
            AddFVG(FVG_BEARISH, lowLeft, highRight, barIndex, gapSize);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add FVG to tracking                                               |
   //+------------------------------------------------------------------+
   void AddFVG(ENUM_FVG_TYPE type, double top, double bottom,
               int barIndex, double size)
   {
      // Create new FVG
      FairValueGap fvg;
      fvg.type = type;
      fvg.top = top;
      fvg.bottom = bottom;
      fvg.midline = (top + bottom) / 2.0;
      fvg.size = size;
      fvg.time = iTime(m_symbol, m_timeframe, barIndex);
      fvg.barIndex = barIndex;
      fvg.status = FVG_OPEN;
      fvg.fillPercent = 0;
      fvg.consequentEncroachment = fvg.midline;  // CE = 50% of FVG

      if(type == FVG_BULLISH)
         AddToBullishFVGArray(fvg);
      else
         AddToBearishFVGArray(fvg);
   }

   //+------------------------------------------------------------------+
   //| Add to Bullish FVG Array                                          |
   //+------------------------------------------------------------------+
   void AddToBullishFVGArray(FairValueGap &fvg)
   {
      // Check if similar FVG already exists
      for(int i = 0; i < ArraySize(m_bullishFVGs); i++)
      {
         if(MathAbs(m_bullishFVGs[i].top - fvg.top) < m_currentATR * 0.3 &&
            MathAbs(m_bullishFVGs[i].bottom - fvg.bottom) < m_currentATR * 0.3)
            return;
      }

      int sz = ArraySize(m_bullishFVGs);
      if(sz >= m_maxFVGs)
      {
         for(int i = m_maxFVGs - 1; i > 0; i--)
            m_bullishFVGs[i] = m_bullishFVGs[i-1];
         m_bullishFVGs[0] = fvg;
      }
      else
      {
         ArrayResize(m_bullishFVGs, sz + 1);
         for(int i = sz; i > 0; i--)
            m_bullishFVGs[i] = m_bullishFVGs[i-1];
         m_bullishFVGs[0] = fvg;
      }
   }

   //+------------------------------------------------------------------+
   //| Add to Bearish FVG Array                                          |
   //+------------------------------------------------------------------+
   void AddToBearishFVGArray(FairValueGap &fvg)
   {
      // Check if similar FVG already exists
      for(int i = 0; i < ArraySize(m_bearishFVGs); i++)
      {
         if(MathAbs(m_bearishFVGs[i].top - fvg.top) < m_currentATR * 0.3 &&
            MathAbs(m_bearishFVGs[i].bottom - fvg.bottom) < m_currentATR * 0.3)
            return;
      }

      int sz = ArraySize(m_bearishFVGs);
      if(sz >= m_maxFVGs)
      {
         for(int i = m_maxFVGs - 1; i > 0; i--)
            m_bearishFVGs[i] = m_bearishFVGs[i-1];
         m_bearishFVGs[0] = fvg;
      }
      else
      {
         ArrayResize(m_bearishFVGs, sz + 1);
         for(int i = sz; i > 0; i--)
            m_bearishFVGs[i] = m_bearishFVGs[i-1];
         m_bearishFVGs[0] = fvg;
      }
   }

   //+------------------------------------------------------------------+
   //| Update FVG mitigation status                                      |
   //+------------------------------------------------------------------+
   void UpdateFVGStatus()
   {
      double currentHigh = iHigh(m_symbol, m_timeframe, 0);
      double currentLow = iLow(m_symbol, m_timeframe, 0);

      // Check Bullish FVGs (looking for price to retrace down into gap)
      for(int i = 0; i < ArraySize(m_bullishFVGs); i++)
      {
         if(m_bullishFVGs[i].status == FVG_FILLED) continue;

         // Calculate fill percentage
         if(currentLow <= m_bullishFVGs[i].top)
         {
            double penetration = m_bullishFVGs[i].top - MathMax(currentLow, m_bullishFVGs[i].bottom);
            double fillPct = (penetration / m_bullishFVGs[i].size) * 100.0;
            m_bullishFVGs[i].fillPercent = MathMax(m_bullishFVGs[i].fillPercent, fillPct);

            if(m_bullishFVGs[i].fillPercent >= 50.0)
               m_bullishFVGs[i].status = FVG_PARTIAL;

            if(currentLow <= m_bullishFVGs[i].bottom)
               m_bullishFVGs[i].status = FVG_FILLED;
         }
      }

      // Check Bearish FVGs (looking for price to retrace up into gap)
      for(int i = 0; i < ArraySize(m_bearishFVGs); i++)
      {
         if(m_bearishFVGs[i].status == FVG_FILLED) continue;

         // Calculate fill percentage
         if(currentHigh >= m_bearishFVGs[i].bottom)
         {
            double penetration = MathMin(currentHigh, m_bearishFVGs[i].top) - m_bearishFVGs[i].bottom;
            double fillPct = (penetration / m_bearishFVGs[i].size) * 100.0;
            m_bearishFVGs[i].fillPercent = MathMax(m_bearishFVGs[i].fillPercent, fillPct);

            if(m_bearishFVGs[i].fillPercent >= 50.0)
               m_bearishFVGs[i].status = FVG_PARTIAL;

            if(currentHigh >= m_bearishFVGs[i].top)
               m_bearishFVGs[i].status = FVG_FILLED;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Cleanup filled FVGs                                               |
   //+------------------------------------------------------------------+
   void CleanupFVGs()
   {
      // Remove filled bullish FVGs
      for(int i = ArraySize(m_bullishFVGs) - 1; i >= 0; i--)
      {
         if(m_bullishFVGs[i].status == FVG_FILLED)
         {
            for(int j = i; j < ArraySize(m_bullishFVGs) - 1; j++)
               m_bullishFVGs[j] = m_bullishFVGs[j+1];
            ArrayResize(m_bullishFVGs, ArraySize(m_bullishFVGs) - 1);
         }
      }

      // Remove filled bearish FVGs
      for(int i = ArraySize(m_bearishFVGs) - 1; i >= 0; i--)
      {
         if(m_bearishFVGs[i].status == FVG_FILLED)
         {
            for(int j = i; j < ArraySize(m_bearishFVGs) - 1; j++)
               m_bearishFVGs[j] = m_bearishFVGs[j+1];
            ArrayResize(m_bearishFVGs, ArraySize(m_bearishFVGs) - 1);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check if price is in FVG zone                                     |
   //+------------------------------------------------------------------+
   bool IsInFVG(int direction, double &fvgTop, double &fvgBottom)
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);

      // For bullish trade: look for bullish FVG (price retracing into gap = buy opportunity)
      if(direction == 1)
      {
         for(int i = 0; i < ArraySize(m_bullishFVGs); i++)
         {
            if(m_bullishFVGs[i].status == FVG_FILLED) continue;

            // Price is in the gap zone (potential bounce area)
            if(currentPrice <= m_bullishFVGs[i].top &&
               currentPrice >= m_bullishFVGs[i].bottom)
            {
               fvgTop = m_bullishFVGs[i].top;
               fvgBottom = m_bullishFVGs[i].bottom;
               return true;
            }
         }
      }
      // For bearish trade: look for bearish FVG
      else if(direction == -1)
      {
         for(int i = 0; i < ArraySize(m_bearishFVGs); i++)
         {
            if(m_bearishFVGs[i].status == FVG_FILLED) continue;

            if(currentPrice >= m_bearishFVGs[i].bottom &&
               currentPrice <= m_bearishFVGs[i].top)
            {
               fvgTop = m_bearishFVGs[i].top;
               fvgBottom = m_bearishFVGs[i].bottom;
               return true;
            }
         }
      }

      fvgTop = 0;
      fvgBottom = 0;
      return false;
   }

   //+------------------------------------------------------------------+
   //| Check if near CE level (Consequent Encroachment)                  |
   //+------------------------------------------------------------------+
   bool IsNearCE(int direction, double tolerance)
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);

      if(direction == 1)
      {
         for(int i = 0; i < ArraySize(m_bullishFVGs); i++)
         {
            if(m_bullishFVGs[i].status == FVG_FILLED) continue;
            if(MathAbs(currentPrice - m_bullishFVGs[i].consequentEncroachment) <= tolerance)
               return true;
         }
      }
      else
      {
         for(int i = 0; i < ArraySize(m_bearishFVGs); i++)
         {
            if(m_bearishFVGs[i].status == FVG_FILLED) continue;
            if(MathAbs(currentPrice - m_bearishFVGs[i].consequentEncroachment) <= tolerance)
               return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get confluence score contribution (0-1.0)                         |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;
      double fvgTop, fvgBottom;

      if(IsInFVG(direction, fvgTop, fvgBottom))
      {
         score = 0.75;  // Base score for being in FVG

         // Bonus if near CE level (optimal entry)
         if(IsNearCE(direction, m_currentATR * 0.2))
            score += 0.25;
      }

      return MathMin(score, 1.0);  // Cap at 1.0
   }

   //+------------------------------------------------------------------+
   //| Get nearest FVG for potential entry                               |
   //+------------------------------------------------------------------+
   bool GetNearestFVG(int direction, FairValueGap &fvg)
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      double nearestDist = 999999;
      int nearestIdx = -1;

      if(direction == 1)
      {
         for(int i = 0; i < ArraySize(m_bullishFVGs); i++)
         {
            if(m_bullishFVGs[i].status == FVG_FILLED) continue;
            double dist = currentPrice - m_bullishFVGs[i].top;
            if(dist > 0 && dist < nearestDist)
            {
               nearestDist = dist;
               nearestIdx = i;
            }
         }
         if(nearestIdx >= 0)
         {
            fvg = m_bullishFVGs[nearestIdx];
            return true;
         }
      }
      else
      {
         for(int i = 0; i < ArraySize(m_bearishFVGs); i++)
         {
            if(m_bearishFVGs[i].status == FVG_FILLED) continue;
            double dist = m_bearishFVGs[i].bottom - currentPrice;
            if(dist > 0 && dist < nearestDist)
            {
               nearestDist = dist;
               nearestIdx = i;
            }
         }
         if(nearestIdx >= 0)
         {
            fvg = m_bearishFVGs[nearestIdx];
            return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get active FVG count                                              |
   //+------------------------------------------------------------------+
   int GetActiveBullishFVGCount()
   {
      int count = 0;
      for(int i = 0; i < ArraySize(m_bullishFVGs); i++)
         if(m_bullishFVGs[i].status != FVG_FILLED) count++;
      return count;
   }

   int GetActiveBearishFVGCount()
   {
      int count = 0;
      for(int i = 0; i < ArraySize(m_bearishFVGs); i++)
         if(m_bearishFVGs[i].status != FVG_FILLED) count++;
      return count;
   }

   //+------------------------------------------------------------------+
   //| Get string representation                                         |
   //+------------------------------------------------------------------+
   string ToString()
   {
      return "FVG: Bull=" + IntegerToString(GetActiveBullishFVGCount()) +
             " Bear=" + IntegerToString(GetActiveBearishFVGCount());
   }
};

#endif
