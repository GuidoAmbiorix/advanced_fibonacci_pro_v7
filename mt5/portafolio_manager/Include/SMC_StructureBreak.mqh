//+------------------------------------------------------------------+
//|                                            SMC_StructureBreak.mqh |
//|          Smart Money Concepts - Break of Structure & CHoCH        |
//|                                  Copyright 2026, Infernal Portfolio Governor   |
//+------------------------------------------------------------------+
#ifndef SMC_STRUCTURE_BREAK_MQH
#define SMC_STRUCTURE_BREAK_MQH

#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| STRUCTURE BREAK TYPES                                             |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_TYPE
{
   STRUCT_NONE = 0,         // No significant structure
   STRUCT_BOS_BULLISH = 1,  // Break of Structure - Bullish (continuation)
   STRUCT_BOS_BEARISH = 2,  // Break of Structure - Bearish (continuation)
   STRUCT_CHOCH_BULLISH = 3,// Change of Character - Bullish (reversal)
   STRUCT_CHOCH_BEARISH = 4 // Change of Character - Bearish (reversal)
};

//+------------------------------------------------------------------+
//| SWING POINT STRUCTURE                                             |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;      // true = swing high, false = swing low
   bool     isBroken;    // Has this level been broken?
};

//+------------------------------------------------------------------+
//| MARKET STRUCTURE STATE                                            |
//+------------------------------------------------------------------+
enum ENUM_MARKET_STRUCTURE
{
   MS_UNKNOWN = 0,
   MS_BULLISH = 1,   // Higher highs, higher lows
   MS_BEARISH = 2    // Lower lows, lower highs
};

//+------------------------------------------------------------------+
//| STRUCTURE BREAK MODULE                                            |
//| Responsibility: Detect BOS and CHoCH for trade confirmation      |
//+------------------------------------------------------------------+
class CSMCStructureBreak
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int      m_swingLookback;      // Bars to look back for swing points
   int      m_maxSwingPoints;     // Max swing points to track
   double   m_minSwingATRMult;    // Min ATR multiple for valid swing

   SwingPoint m_swingHighs[];     // Recent swing highs
   SwingPoint m_swingLows[];      // Recent swing lows

   ENUM_MARKET_STRUCTURE m_currentStructure;
   ENUM_STRUCTURE_TYPE   m_lastBreak;
   datetime              m_lastBreakTime;
   double                m_lastBreakPrice;

   int      m_hATR;
   double   m_currentATR;

public:
   CSMCStructureBreak() : m_swingLookback(20), m_maxSwingPoints(5),
                          m_minSwingATRMult(0.5), m_currentStructure(MS_UNKNOWN),
                          m_lastBreak(STRUCT_NONE), m_hATR(INVALID_HANDLE) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 20,
             int maxPoints = 5, double minATRMult = 0.5)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_swingLookback = lookback;
      m_maxSwingPoints = maxPoints;
      m_minSwingATRMult = minATRMult;

      ArrayResize(m_swingHighs, 0);
      ArrayResize(m_swingLows, 0);

      m_hATR = iATR(m_symbol, m_timeframe, 14);
      if(m_hATR == INVALID_HANDLE) return false;

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

      // Identify new swing points
      IdentifySwingPoints();

      // Check for structure breaks
      CheckStructureBreak();
   }

   //+------------------------------------------------------------------+
   //| Identify Swing Points                                             |
   //+------------------------------------------------------------------+
   void IdentifySwingPoints()
   {
      // Check bar 2 (confirmed swing - need bars on both sides)
      int checkBar = 2;

      double high = iHigh(m_symbol, m_timeframe, checkBar);
      double low = iLow(m_symbol, m_timeframe, checkBar);
      datetime time = iTime(m_symbol, m_timeframe, checkBar);

      // Check for swing high
      bool isSwingHigh = true;
      bool isSwingLow = true;

      for(int i = 1; i <= m_swingLookback/2; i++)
      {
         // Left side
         if(iHigh(m_symbol, m_timeframe, checkBar + i) >= high) isSwingHigh = false;
         if(iLow(m_symbol, m_timeframe, checkBar + i) <= low) isSwingLow = false;

         // Right side (only 1 bar confirmed for now)
         if(i == 1)
         {
            if(iHigh(m_symbol, m_timeframe, checkBar - i) >= high) isSwingHigh = false;
            if(iLow(m_symbol, m_timeframe, checkBar - i) <= low) isSwingLow = false;
         }
      }

      // Validate with ATR
      double minSwing = m_currentATR * m_minSwingATRMult;

      // Add swing high if valid
      if(isSwingHigh)
      {
         if(ArraySize(m_swingHighs) == 0 ||
            MathAbs(high - m_swingHighs[0].price) > minSwing)
         {
            AddSwingPoint(m_swingHighs, high, time, checkBar, true);
         }
      }

      // Add swing low if valid
      if(isSwingLow)
      {
         if(ArraySize(m_swingLows) == 0 ||
            MathAbs(low - m_swingLows[0].price) > minSwing)
         {
            AddSwingPoint(m_swingLows, low, time, checkBar, false);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add Swing Point                                                   |
   //+------------------------------------------------------------------+
   void AddSwingPoint(SwingPoint &arr[], double price, datetime time, int bar, bool isHigh)
   {
      // Shift array and add new point at front
      int size = ArraySize(arr);
      if(size >= m_maxSwingPoints)
      {
         ArrayResize(arr, m_maxSwingPoints);
         for(int i = m_maxSwingPoints - 1; i > 0; i--)
            arr[i] = arr[i-1];
      }
      else
      {
         ArrayResize(arr, size + 1);
         for(int i = size; i > 0; i--)
            arr[i] = arr[i-1];
      }

      arr[0].price = price;
      arr[0].time = time;
      arr[0].barIndex = bar;
      arr[0].isHigh = isHigh;
      arr[0].isBroken = false;
   }

   //+------------------------------------------------------------------+
   //| Check for Structure Break                                         |
   //+------------------------------------------------------------------+
   void CheckStructureBreak()
   {
      if(ArraySize(m_swingHighs) < 2 || ArraySize(m_swingLows) < 2) return;

      double currentPrice = iClose(m_symbol, m_timeframe, 1);

      // Determine current market structure first
      bool makingHH = m_swingHighs[0].price > m_swingHighs[1].price;
      bool makingHL = m_swingLows[0].price > m_swingLows[1].price;
      bool makingLL = m_swingLows[0].price < m_swingLows[1].price;
      bool makingLH = m_swingHighs[0].price < m_swingHighs[1].price;

      ENUM_MARKET_STRUCTURE prevStructure = m_currentStructure;

      if(makingHH && makingHL) m_currentStructure = MS_BULLISH;
      else if(makingLL && makingLH) m_currentStructure = MS_BEARISH;

      // Check for BOS - Break of recent swing point
      // Bullish BOS: Price breaks above recent swing high
      if(!m_swingHighs[0].isBroken && currentPrice > m_swingHighs[0].price)
      {
         m_swingHighs[0].isBroken = true;

         if(prevStructure == MS_BEARISH)
         {
            // CHoCH - Breaking structure against prevailing trend
            m_lastBreak = STRUCT_CHOCH_BULLISH;
         }
         else
         {
            // BOS - Continuation in trend direction
            m_lastBreak = STRUCT_BOS_BULLISH;
         }

         m_lastBreakTime = iTime(m_symbol, m_timeframe, 0);
         m_lastBreakPrice = m_swingHighs[0].price;
      }

      // Bearish BOS: Price breaks below recent swing low
      if(!m_swingLows[0].isBroken && currentPrice < m_swingLows[0].price)
      {
         m_swingLows[0].isBroken = true;

         if(prevStructure == MS_BULLISH)
         {
            // CHoCH - Breaking structure against prevailing trend
            m_lastBreak = STRUCT_CHOCH_BEARISH;
         }
         else
         {
            // BOS - Continuation in trend direction
            m_lastBreak = STRUCT_BOS_BEARISH;
         }

         m_lastBreakTime = iTime(m_symbol, m_timeframe, 0);
         m_lastBreakPrice = m_swingLows[0].price;
      }
   }

   //+------------------------------------------------------------------+
   //| Get confluence score contribution (0-1.5)                         |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;

      // BOS aligned with direction: +1.0
      if(direction == 1)
      {
         if(m_lastBreak == STRUCT_BOS_BULLISH) score += 1.0;
         if(m_lastBreak == STRUCT_CHOCH_BULLISH) score += 1.5; // CHoCH more significant
         if(m_currentStructure == MS_BULLISH) score += 0.5;
      }
      else if(direction == -1)
      {
         if(m_lastBreak == STRUCT_BOS_BEARISH) score += 1.0;
         if(m_lastBreak == STRUCT_CHOCH_BEARISH) score += 1.5;
         if(m_currentStructure == MS_BEARISH) score += 0.5;
      }

      // Check recency - break within last 10 bars is more relevant
      int barsSinceBreak = iBarShift(m_symbol, m_timeframe, m_lastBreakTime, false);
      if(barsSinceBreak > 10) score *= 0.5;
      if(barsSinceBreak > 20) score *= 0.25;

      return MathMin(score, 1.5); // Cap at 1.5
   }

   //+------------------------------------------------------------------+
   //| Check if direction aligns with recent BOS                         |
   //+------------------------------------------------------------------+
   bool IsBOSAligned(int direction)
   {
      if(direction == 1)
         return (m_lastBreak == STRUCT_BOS_BULLISH || m_lastBreak == STRUCT_CHOCH_BULLISH);
      else if(direction == -1)
         return (m_lastBreak == STRUCT_BOS_BEARISH || m_lastBreak == STRUCT_CHOCH_BEARISH);
      return false;
   }

   //+------------------------------------------------------------------+
   //| Check if CHoCH occurred (potential reversal)                      |
   //+------------------------------------------------------------------+
   bool IsCHoCH()
   {
      return (m_lastBreak == STRUCT_CHOCH_BULLISH || m_lastBreak == STRUCT_CHOCH_BEARISH);
   }

   //+------------------------------------------------------------------+
   //| Get current market structure                                      |
   //+------------------------------------------------------------------+
   ENUM_MARKET_STRUCTURE GetMarketStructure()
   {
      return m_currentStructure;
   }

   //+------------------------------------------------------------------+
   //| Get last break type                                               |
   //+------------------------------------------------------------------+
   ENUM_STRUCTURE_TYPE GetLastBreakType()
   {
      return m_lastBreak;
   }

   //+------------------------------------------------------------------+
   //| Get last break price                                              |
   //+------------------------------------------------------------------+
   double GetLastBreakPrice()
   {
      return m_lastBreakPrice;
   }

   datetime GetLastBreakTime()
   {
      return m_lastBreakTime;
   }

   //+------------------------------------------------------------------+
   //| Get most recent swing high                                        |
   //+------------------------------------------------------------------+
   double GetRecentSwingHigh()
   {
      if(ArraySize(m_swingHighs) > 0) return m_swingHighs[0].price;
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get most recent swing low                                         |
   //+------------------------------------------------------------------+
   double GetRecentSwingLow()
   {
      if(ArraySize(m_swingLows) > 0) return m_swingLows[0].price;
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get string representation of structure                            |
   //+------------------------------------------------------------------+
   string StructureToString()
   {
      string str = "";

      switch(m_currentStructure)
      {
         case MS_BULLISH: str = "BULLISH"; break;
         case MS_BEARISH: str = "BEARISH"; break;
         default: str = "UNKNOWN"; break;
      }

      str += " | Last: ";

      switch(m_lastBreak)
      {
         case STRUCT_BOS_BULLISH: str += "BOS+"; break;
         case STRUCT_BOS_BEARISH: str += "BOS-"; break;
         case STRUCT_CHOCH_BULLISH: str += "CHoCH+"; break;
         case STRUCT_CHOCH_BEARISH: str += "CHoCH-"; break;
         default: str += "NONE"; break;
      }

      return str;
   }
};

#endif
