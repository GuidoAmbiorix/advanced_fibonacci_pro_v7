//+------------------------------------------------------------------+
//|                                              SMC_OrderBlocks.mqh |
//|          Smart Money Concepts - Order Block Detection             |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef SMC_ORDER_BLOCKS_MQH
#define SMC_ORDER_BLOCKS_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| ORDER BLOCK TYPES                                                 |
//+------------------------------------------------------------------+
enum ENUM_OB_TYPE
{
   OB_NONE = 0,
   OB_BULLISH = 1,    // Last bearish candle before bullish impulse
   OB_BEARISH = 2     // Last bullish candle before bearish impulse
};

//+------------------------------------------------------------------+
//| ORDER BLOCK STRUCTURE                                             |
//+------------------------------------------------------------------+
struct OrderBlock
{
   ENUM_OB_TYPE type;
   double       top;           // Top of OB zone (High for bullish, Close for bearish)
   double       bottom;        // Bottom of OB zone (Open for bullish, Low for bearish)
   double       midline;       // Middle of the zone (optimal entry)
   datetime     time;          // When OB was created
   int          barIndex;      // Bar index when created
   bool         mitigated;     // Has price returned and mitigated?
   bool         respected;     // Did price react at this level?
   double       impulseStrength; // Strength of the following impulse (in ATR)
   int          touchCount;    // How many times price has touched this zone
};

//+------------------------------------------------------------------+
//| ORDER BLOCKS MODULE                                               |
//| Responsibility: Detect and track institutional order blocks       |
//+------------------------------------------------------------------+
class CSMCOrderBlocks
{
private:
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int            m_lookback;          // Bars to scan for OBs
   int            m_maxOBs;            // Max OBs to track
   double         m_minImpulseATR;     // Min impulse size (ATR multiple)
   double         m_maxMitigationATR;  // Max penetration before OB invalid

   OrderBlock     m_bullishOBs[];      // Active bullish OBs
   OrderBlock     m_bearishOBs[];      // Active bearish OBs

   int            m_hATR;
   double         m_currentATR;

public:
   CSMCOrderBlocks() : m_lookback(50), m_maxOBs(5), m_minImpulseATR(2.0),
                       m_maxMitigationATR(0.5), m_hATR(INVALID_HANDLE) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 50,
             int maxOBs = 5, double minImpulse = 2.0)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_lookback = lookback;
      m_maxOBs = maxOBs;
      m_minImpulseATR = minImpulse;

      ArrayResize(m_bullishOBs, 0);
      ArrayResize(m_bearishOBs, 0);

      m_hATR = iATR(m_symbol, m_timeframe, 14);
      if(m_hATR == INVALID_HANDLE) return false;

      // Initial scan for existing OBs
      ScanForOrderBlocks();

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

      // Check for new OBs at recent bars
      CheckForNewOB(3);  // Check bar 3 for confirmed OB

      // Update mitigation status of existing OBs
      UpdateOBStatus();

      // Clean up old/mitigated OBs
      CleanupOBs();
   }

   //+------------------------------------------------------------------+
   //| Scan for Order Blocks in history                                  |
   //+------------------------------------------------------------------+
   void ScanForOrderBlocks()
   {
      double atrBuf[1];
      if(CopyBuffer(m_hATR, 0, 1, 1, atrBuf) != 1) return;
      m_currentATR = atrBuf[0];

      for(int i = m_lookback; i >= 3; i--)
      {
         CheckForNewOB(i);
      }
   }

   //+------------------------------------------------------------------+
   //| Check for new Order Block at specific bar                         |
   //+------------------------------------------------------------------+
   void CheckForNewOB(int barIndex)
   {
      // Need at least 2 bars after for impulse confirmation
      if(barIndex < 2) return;

      double open = iOpen(m_symbol, m_timeframe, barIndex);
      double close = iClose(m_symbol, m_timeframe, barIndex);
      double high = iHigh(m_symbol, m_timeframe, barIndex);
      double low = iLow(m_symbol, m_timeframe, barIndex);

      bool isBearishCandle = close < open;
      bool isBullishCandle = close > open;

      // Check for Bullish OB: Bearish candle followed by bullish impulse
      if(isBearishCandle)
      {
         double impulseHigh = 0;
         double impulseLow = high;  // Start from current high

         // Check next 2 bars for bullish impulse
         for(int i = 1; i <= 2; i++)
         {
            int checkBar = barIndex - i;
            if(checkBar < 0) break;

            double h = iHigh(m_symbol, m_timeframe, checkBar);
            double l = iLow(m_symbol, m_timeframe, checkBar);

            if(h > impulseHigh) impulseHigh = h;
            if(l < impulseLow) impulseLow = l;
         }

         double impulseSize = impulseHigh - high;  // Impulse above the OB candle

         if(impulseSize >= m_currentATR * m_minImpulseATR)
         {
            // Valid Bullish OB found
            AddOrderBlock(OB_BULLISH, high, low, barIndex, impulseSize / m_currentATR);
         }
      }

      // Check for Bearish OB: Bullish candle followed by bearish impulse
      if(isBullishCandle)
      {
         double impulseHigh = low;  // Start from current low
         double impulseLow = 999999;

         // Check next 2 bars for bearish impulse
         for(int i = 1; i <= 2; i++)
         {
            int checkBar = barIndex - i;
            if(checkBar < 0) break;

            double h = iHigh(m_symbol, m_timeframe, checkBar);
            double l = iLow(m_symbol, m_timeframe, checkBar);

            if(l < impulseLow) impulseLow = l;
            if(h > impulseHigh) impulseHigh = h;
         }

         double impulseSize = low - impulseLow;  // Impulse below the OB candle

         if(impulseSize >= m_currentATR * m_minImpulseATR)
         {
            // Valid Bearish OB found
            AddOrderBlock(OB_BEARISH, high, low, barIndex, impulseSize / m_currentATR);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add Order Block to tracking                                       |
   //+------------------------------------------------------------------+
   void AddOrderBlock(ENUM_OB_TYPE type, double top, double bottom,
                      int barIndex, double impulseStrength)
   {
      // Create new OB
      OrderBlock ob;
      ob.type = type;
      ob.top = top;
      ob.bottom = bottom;
      ob.midline = (top + bottom) / 2.0;
      ob.time = iTime(m_symbol, m_timeframe, barIndex);
      ob.barIndex = barIndex;
      ob.mitigated = false;
      ob.respected = false;
      ob.impulseStrength = impulseStrength;
      ob.touchCount = 0;

      if(type == OB_BULLISH)
         AddToBullishOBArray(ob);
      else
         AddToBearishOBArray(ob);
   }

   //+------------------------------------------------------------------+
   //| Invalidate Block (Smart Invalidation after Loss)                  |
   //+------------------------------------------------------------------+
   void InvalidateBlock(int barIndex)
   {
      // Search in bullish blocks
      for(int i = 0; i < ArraySize(m_bullishOBs); i++)
      {
         if(m_bullishOBs[i].barIndex == barIndex)
         {
            m_bullishOBs[i].mitigated = true; // Mark as "used up" so we don't trade it again
            Print("Smart Invalidation: Bullish OB at bar ", barIndex, " removed due to loss.");
            return;
         }
      }

      // Search in bearish blocks
      for(int i = 0; i < ArraySize(m_bearishOBs); i++)
      {
         if(m_bearishOBs[i].barIndex == barIndex)
         {
            m_bearishOBs[i].mitigated = true; // Mark as "used up" so we don't trade it again
            Print("Smart Invalidation: Bearish OB at bar ", barIndex, " removed due to loss.");
            return;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add to Bullish OB Array                                           |
   //+------------------------------------------------------------------+
   void AddToBullishOBArray(OrderBlock &ob)
   {
      // Check if similar OB already exists
      for(int i = 0; i < ArraySize(m_bullishOBs); i++)
      {
         if(MathAbs(m_bullishOBs[i].top - ob.top) < m_currentATR * 0.5 &&
            MathAbs(m_bullishOBs[i].bottom - ob.bottom) < m_currentATR * 0.5)
            return;
      }

      int size = ArraySize(m_bullishOBs);
      if(size >= m_maxOBs)
      {
         for(int i = m_maxOBs - 1; i > 0; i--)
            m_bullishOBs[i] = m_bullishOBs[i-1];
         m_bullishOBs[0] = ob;
      }
      else
      {
         ArrayResize(m_bullishOBs, size + 1);
         for(int i = size; i > 0; i--)
            m_bullishOBs[i] = m_bullishOBs[i-1];
         m_bullishOBs[0] = ob;
      }
   }

   //+------------------------------------------------------------------+
   //| Add to Bearish OB Array                                           |
   //+------------------------------------------------------------------+
   void AddToBearishOBArray(OrderBlock &ob)
   {
      // Check if similar OB already exists
      for(int i = 0; i < ArraySize(m_bearishOBs); i++)
      {
         if(MathAbs(m_bearishOBs[i].top - ob.top) < m_currentATR * 0.5 &&
            MathAbs(m_bearishOBs[i].bottom - ob.bottom) < m_currentATR * 0.5)
            return;
      }

      int size = ArraySize(m_bearishOBs);
      if(size >= m_maxOBs)
      {
         for(int i = m_maxOBs - 1; i > 0; i--)
            m_bearishOBs[i] = m_bearishOBs[i-1];
         m_bearishOBs[0] = ob;
      }
      else
      {
         ArrayResize(m_bearishOBs, size + 1);
         for(int i = size; i > 0; i--)
            m_bearishOBs[i] = m_bearishOBs[i-1];
         m_bearishOBs[0] = ob;
      }
   }

   //+------------------------------------------------------------------+
   //| Update OB mitigation status                                       |
   //+------------------------------------------------------------------+
   void UpdateOBStatus()
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      double currentLow = iLow(m_symbol, m_timeframe, 0);
      double currentHigh = iHigh(m_symbol, m_timeframe, 0);

      // Check Bullish OBs
      for(int i = 0; i < ArraySize(m_bullishOBs); i++)
      {
         if(m_bullishOBs[i].mitigated) continue;

         // Price touched the OB zone
         if(currentLow <= m_bullishOBs[i].top && currentLow >= m_bullishOBs[i].bottom)
         {
            m_bullishOBs[i].touchCount++;

            // Check if respected (bounced from zone)
            if(currentPrice > m_bullishOBs[i].top)
               m_bullishOBs[i].respected = true;
         }

         // Mitigated if price closes below bottom by significant amount
         if(currentPrice < m_bullishOBs[i].bottom - m_currentATR * m_maxMitigationATR)
         {
            m_bullishOBs[i].mitigated = true;
         }
      }

      // Check Bearish OBs
      for(int i = 0; i < ArraySize(m_bearishOBs); i++)
      {
         if(m_bearishOBs[i].mitigated) continue;

         // Price touched the OB zone
         if(currentHigh >= m_bearishOBs[i].bottom && currentHigh <= m_bearishOBs[i].top)
         {
            m_bearishOBs[i].touchCount++;

            // Check if respected (rejected from zone)
            if(currentPrice < m_bearishOBs[i].bottom)
               m_bearishOBs[i].respected = true;
         }

         // Mitigated if price closes above top by significant amount
         if(currentPrice > m_bearishOBs[i].top + m_currentATR * m_maxMitigationATR)
         {
            m_bearishOBs[i].mitigated = true;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Cleanup old/mitigated OBs                                         |
   //+------------------------------------------------------------------+
   void CleanupOBs()
   {
      // Remove mitigated bullish OBs
      for(int i = ArraySize(m_bullishOBs) - 1; i >= 0; i--)
      {
         if(m_bullishOBs[i].mitigated)
         {
            for(int j = i; j < ArraySize(m_bullishOBs) - 1; j++)
               m_bullishOBs[j] = m_bullishOBs[j+1];
            ArrayResize(m_bullishOBs, ArraySize(m_bullishOBs) - 1);
         }
      }

      // Remove mitigated bearish OBs
      for(int i = ArraySize(m_bearishOBs) - 1; i >= 0; i--)
      {
         if(m_bearishOBs[i].mitigated)
         {
            for(int j = i; j < ArraySize(m_bearishOBs) - 1; j++)
               m_bearishOBs[j] = m_bearishOBs[j+1];
            ArrayResize(m_bearishOBs, ArraySize(m_bearishOBs) - 1);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check if price is in Order Block zone                             |
   //+------------------------------------------------------------------+
   bool IsInOrderBlock(int direction, double &obTop, double &obBottom)
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);

      if(direction == 1)  // Looking for bullish OB
      {
         for(int i = 0; i < ArraySize(m_bullishOBs); i++)
         {
            if(m_bullishOBs[i].mitigated) continue;

            if(currentPrice >= m_bullishOBs[i].bottom &&
               currentPrice <= m_bullishOBs[i].top)
            {
               obTop = m_bullishOBs[i].top;
               obBottom = m_bullishOBs[i].bottom;
               return true;
            }
         }
      }
      else if(direction == -1)  // Looking for bearish OB
      {
         for(int i = 0; i < ArraySize(m_bearishOBs); i++)
         {
            if(m_bearishOBs[i].mitigated) continue;

            if(currentPrice >= m_bearishOBs[i].bottom &&
               currentPrice <= m_bearishOBs[i].top)
            {
               obTop = m_bearishOBs[i].top;
               obBottom = m_bearishOBs[i].bottom;
               return true;
            }
         }
      }

      obTop = 0;
      obBottom = 0;
      return false;
   }

   //+------------------------------------------------------------------+
   //| Get confluence score contribution (0-1.5)                         |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;
      double obTop, obBottom;

      if(IsInOrderBlock(direction, obTop, obBottom))
      {
         score = 1.0;  // Base score for being in OB
         double currentClose = iClose(m_symbol, m_timeframe, 0);

         // Bonus for strong impulse - check appropriate array
         if(direction == 1)
         {
            for(int i = 0; i < ArraySize(m_bullishOBs); i++)
            {
               if(!m_bullishOBs[i].mitigated &&
                  currentClose >= m_bullishOBs[i].bottom &&
                  currentClose <= m_bullishOBs[i].top)
               {
                  if(m_bullishOBs[i].impulseStrength >= 3.0) score += 0.5;
                  if(m_bullishOBs[i].touchCount == 1) score += 0.25;
                  break;
               }
            }
         }
         else
         {
            for(int i = 0; i < ArraySize(m_bearishOBs); i++)
            {
               if(!m_bearishOBs[i].mitigated &&
                  currentClose >= m_bearishOBs[i].bottom &&
                  currentClose <= m_bearishOBs[i].top)
               {
                  if(m_bearishOBs[i].impulseStrength >= 3.0) score += 0.5;
                  if(m_bearishOBs[i].touchCount == 1) score += 0.25;
                  break;
               }
            }
         }
      }

      return MathMin(score, 1.5);  // Cap at 1.5
   }

   //+------------------------------------------------------------------+
   //| Get nearest Order Block                                           |
   //+------------------------------------------------------------------+
   bool GetNearestOB(int direction, OrderBlock &ob)
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      double nearestDist = 999999;
      int nearestIdx = -1;

      if(direction == 1)
      {
         for(int i = 0; i < ArraySize(m_bullishOBs); i++)
         {
            if(m_bullishOBs[i].mitigated) continue;
            double dist = currentPrice - m_bullishOBs[i].top;
            if(dist > 0 && dist < nearestDist)
            {
               nearestDist = dist;
               nearestIdx = i;
            }
         }
         if(nearestIdx >= 0)
         {
            ob = m_bullishOBs[nearestIdx];
            return true;
         }
      }
      else
      {
         for(int i = 0; i < ArraySize(m_bearishOBs); i++)
         {
            if(m_bearishOBs[i].mitigated) continue;
            double dist = m_bearishOBs[i].bottom - currentPrice;
            if(dist > 0 && dist < nearestDist)
            {
               nearestDist = dist;
               nearestIdx = i;
            }
         }
         if(nearestIdx >= 0)
         {
            ob = m_bearishOBs[nearestIdx];
            return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get active OB count                                               |
   //+------------------------------------------------------------------+
   int GetActiveBullishOBCount() { return ArraySize(m_bullishOBs); }
   int GetActiveBearishOBCount() { return ArraySize(m_bearishOBs); }

   //+------------------------------------------------------------------+
   //| Get string representation                                         |
   //+------------------------------------------------------------------+
   string ToString()
   {
      return "OB: Bull=" + IntegerToString(ArraySize(m_bullishOBs)) +
             " Bear=" + IntegerToString(ArraySize(m_bearishOBs));
   }
};

#endif
