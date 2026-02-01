//+------------------------------------------------------------------+
//|                                         SMC_MarketStructure.mqh  |
//|          Market Structure Shift (MSS) & Change of Character      |
//|                                  Copyright 2026, Guido Ambiorix  |
//+------------------------------------------------------------------+
#ifndef SMC_MARKET_STRUCTURE_MQH
#define SMC_MARKET_STRUCTURE_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_MSS_TYPE
{
   MSS_NONE = 0,
   MSS_BULLISH = 1,           // Market Structure Shift to bullish
   MSS_BEARISH = 2,           // Market Structure Shift to bearish
   MSS_CHOCH_BULLISH = 3,     // Change of Character to bullish
   MSS_CHOCH_BEARISH = 4      // Change of Character to bearish
};

//+------------------------------------------------------------------+
//| Structure Event Data                                             |
//+------------------------------------------------------------------+
struct MSSEvent
{
   ENUM_MSS_TYPE        type;
   double               level;          // Price level of break
   datetime             time;           // When it occurred
   int                  barIndex;       // Bar index
   double               displacement;   // ATR multiple of break
   bool                 confirmed;      // Has follow-through confirmed it?
};

//+------------------------------------------------------------------+
//| MARKET STRUCTURE ANALYZER                                         |
//+------------------------------------------------------------------+
class CSMCMarketStructure
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_swingLookback;
   double            m_minDisplacementATR;  // Min displacement for MSS
   
   int               m_hATR;
   double            m_currentATR;
   
   // Track recent swing points
   double            m_lastSwingHigh;
   double            m_lastSwingLow;
   int               m_lastSwingHighBar;
   int               m_lastSwingLowBar;
   
   // Current structure bias
   int               m_currentBias;  // 1=Bullish, -1=Bearish, 0=Neutral
   
   // Recent events
   MSSEvent          m_recentEvents[];
   int               m_maxEvents;

public:
   CSMCMarketStructure() : m_swingLookback(20), m_minDisplacementATR(2.0),
                           m_hATR(INVALID_HANDLE), m_maxEvents(10),
                           m_currentBias(0)
   {
      m_lastSwingHigh = 0;
      m_lastSwingLow = 0;
      m_lastSwingHighBar = -1;
      m_lastSwingLowBar = -1;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int swingLookback = 20,
             double minDisplacement = 2.0)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_swingLookback = swingLookback;
      m_minDisplacementATR = minDisplacement;
      
      ArrayResize(m_recentEvents, 0);
      
      m_hATR = iATR(m_symbol, m_timeframe, 14);
      if(m_hATR == INVALID_HANDLE) return false;
      
      // Initialize swing points
      UpdateSwingPoints();
      
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
      
      // Update swing points
      UpdateSwingPoints();
      
      // Check for structure breaks
      CheckForStructureBreak();
      
      // Confirm pending events
      ConfirmEvents();
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score                                             |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;
      
      // Check for recent MSS aligned with direction
      for(int i = 0; i < ArraySize(m_recentEvents); i++)
      {
         if(!m_recentEvents[i].confirmed) continue;
         
         // Only consider events from last 10 bars
         int barsSince = iBarShift(m_symbol, m_timeframe, m_recentEvents[i].time);
         if(barsSince > 10) continue;
         
         // MSS aligned with direction
         if(direction == 1 && m_recentEvents[i].type == MSS_BULLISH)
         {
            score = 2.0;  // Full score for confirmed bullish MSS
            break;
         }
         else if(direction == -1 && m_recentEvents[i].type == MSS_BEARISH)
         {
            score = 2.0;  // Full score for confirmed bearish MSS
            break;
         }
         // ChoCh aligned
         else if(direction == 1 && m_recentEvents[i].type == MSS_CHOCH_BULLISH)
         {
            score = MathMax(score, 1.0);  // Partial score for ChoCh
         }
         else if(direction == -1 && m_recentEvents[i].type == MSS_CHOCH_BEARISH)
         {
            score = MathMax(score, 1.0);  // Partial score for ChoCh
         }
      }
      
      return score;
   }

   //+------------------------------------------------------------------+
   //| Get Current Bias                                                 |
   //+------------------------------------------------------------------+
   int GetCurrentBias() { return m_currentBias; }
   
   //+------------------------------------------------------------------+
   //| Get Last MSS Event                                               |
   //+------------------------------------------------------------------+
   bool GetLastMSS(MSSEvent &event)
   {
      for(int i = 0; i < ArraySize(m_recentEvents); i++)
      {
         if(m_recentEvents[i].type == MSS_BULLISH || 
            m_recentEvents[i].type == MSS_BEARISH)
         {
            event = m_recentEvents[i];
            return true;
         }
      }
      return false;
   }

private:
   //+------------------------------------------------------------------+
   //| Update Swing Points                                              |
   //+------------------------------------------------------------------+
   void UpdateSwingPoints()
   {
      // Find most recent swing high
      int highBar = iHighest(m_symbol, m_timeframe, MODE_HIGH, m_swingLookback, 1);
      if(highBar >= 0)
      {
         double swingHigh = iHigh(m_symbol, m_timeframe, highBar);
         
         // Update if new swing or higher high
         if(highBar != m_lastSwingHighBar || swingHigh > m_lastSwingHigh)
         {
            m_lastSwingHigh = swingHigh;
            m_lastSwingHighBar = highBar;
         }
      }
      
      // Find most recent swing low
      int lowBar = iLowest(m_symbol, m_timeframe, MODE_LOW, m_swingLookback, 1);
      if(lowBar >= 0)
      {
         double swingLow = iLow(m_symbol, m_timeframe, lowBar);
         
         // Update if new swing or lower low
         if(lowBar != m_lastSwingLowBar || swingLow < m_lastSwingLow)
         {
            m_lastSwingLow = swingLow;
            m_lastSwingLowBar = lowBar;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check for Structure Break                                        |
   //+------------------------------------------------------------------+
   void CheckForStructureBreak()
   {
      if(m_lastSwingHigh == 0 || m_lastSwingLow == 0) return;
      
      double currentHigh = iHigh(m_symbol, m_timeframe, 0);
      double currentLow = iLow(m_symbol, m_timeframe, 0);
      double currentClose = iClose(m_symbol, m_timeframe, 0);
      
      // Check for BULLISH structure break (break of swing high)
      if(currentClose > m_lastSwingHigh)
      {
         double displacement = (currentClose - m_lastSwingHigh) / m_currentATR;
         
         // MSS requires strong displacement
         if(displacement >= m_minDisplacementATR)
         {
            AddEvent(MSS_BULLISH, m_lastSwingHigh, displacement);
            m_currentBias = 1;
         }
         // Weaker break = ChoCh
         else if(displacement >= m_minDisplacementATR * 0.5)
         {
            AddEvent(MSS_CHOCH_BULLISH, m_lastSwingHigh, displacement);
         }
      }
      
      // Check for BEARISH structure break (break of swing low)
      if(currentClose < m_lastSwingLow)
      {
         double displacement = (m_lastSwingLow - currentClose) / m_currentATR;
         
         // MSS requires strong displacement
         if(displacement >= m_minDisplacementATR)
         {
            AddEvent(MSS_BEARISH, m_lastSwingLow, displacement);
            m_currentBias = -1;
         }
         // Weaker break = ChoCh
         else if(displacement >= m_minDisplacementATR * 0.5)
         {
            AddEvent(MSS_CHOCH_BEARISH, m_lastSwingLow, displacement);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add Structure Event                                              |
   //+------------------------------------------------------------------+
   void AddEvent(ENUM_MSS_TYPE type, double level, double displacement)
   {
      // Check if similar event already exists (avoid duplicates)
      for(int i = 0; i < ArraySize(m_recentEvents); i++)
      {
         if(m_recentEvents[i].type == type && 
            MathAbs(m_recentEvents[i].level - level) < m_currentATR * 0.5)
            return;
      }
      
      MSSEvent evt;
      evt.type = type;
      evt.level = level;
      evt.time = iTime(m_symbol, m_timeframe, 0);
      evt.barIndex = 0;
      evt.displacement = displacement;
      evt.confirmed = false;  // Needs follow-through
      
      // Add to array (newest first)
      int size = ArraySize(m_recentEvents);
      if(size >= m_maxEvents)
      {
         // Remove oldest
         ArrayResize(m_recentEvents, size - 1);
      }
      
      ArrayResize(m_recentEvents, ArraySize(m_recentEvents) + 1);
      
      // Shift existing events
      for(int i = ArraySize(m_recentEvents) - 1; i > 0; i--)
      {
         m_recentEvents[i] = m_recentEvents[i-1];
      }
      
      m_recentEvents[0] = evt;
      
      Print("📊 MSS: ", EnumToString(type), " @ ", DoubleToString(level, 5), 
            " | Displacement: ", DoubleToString(displacement, 2), " ATR");
   }

   //+------------------------------------------------------------------+
   //| Confirm Events (check follow-through)                            |
   //+------------------------------------------------------------------+
   void ConfirmEvents()
   {
      double currentClose = iClose(m_symbol, m_timeframe, 0);
      
      for(int i = 0; i < ArraySize(m_recentEvents); i++)
      {
         if(m_recentEvents[i].confirmed) continue;
         
         int barsSince = iBarShift(m_symbol, m_timeframe, m_recentEvents[i].time);
         
         // Require 2-3 bars of follow-through
         if(barsSince < 2) continue;
         
         bool hasFollowThrough = false;
         
         // Bullish events need price to stay above level
         if(m_recentEvents[i].type == MSS_BULLISH || 
            m_recentEvents[i].type == MSS_CHOCH_BULLISH)
         {
            if(currentClose > m_recentEvents[i].level)
               hasFollowThrough = true;
         }
         // Bearish events need price to stay below level
         else
         {
            if(currentClose < m_recentEvents[i].level)
               hasFollowThrough = true;
         }
         
         if(hasFollowThrough)
         {
            m_recentEvents[i].confirmed = true;
            Print("✅ Structure Confirmed: ", EnumToString(m_recentEvents[i].type));
         }
         else if(barsSince > 5)
         {
            // Failed to confirm after 5 bars - mark as invalid
            // Remove from array
            for(int j = i; j < ArraySize(m_recentEvents) - 1; j++)
            {
               m_recentEvents[j] = m_recentEvents[j+1];
            }
            ArrayResize(m_recentEvents, ArraySize(m_recentEvents) - 1);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get String Representation                                        |
   //+------------------------------------------------------------------+
   string ToString()
   {
      string bias = "NEUTRAL";
      if(m_currentBias == 1) bias = "BULLISH";
      else if(m_currentBias == -1) bias = "BEARISH";
      
      return "Structure: " + bias + " | Events: " + IntegerToString(ArraySize(m_recentEvents));
   }
};

#endif
