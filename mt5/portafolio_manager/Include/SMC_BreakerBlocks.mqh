//+------------------------------------------------------------------+
//|                                        SMC_BreakerBlocks.mqh     |
//|                         ICT Breaker Blocks Module                 |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Breaker Block Structure                                          |
//+------------------------------------------------------------------+
struct BreakerBlock
{
   double   highPrice;      // Top of breaker zone
   double   lowPrice;       // Bottom of breaker zone
   int      barsAgo;        // When it was created
   int      type;           // 1=Bullish Breaker (was bear OB), -1=Bearish Breaker (was bull OB)
   bool     isValid;        // Still active
   string   description;    // Description for logging
};

//+------------------------------------------------------------------+
//| Breaker Blocks Class                                             |
//+------------------------------------------------------------------+
class CBreakerBlocks
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_lookback;
   double            m_minImpulseATR;

   BreakerBlock      m_breakers[];          // Active breaker blocks
   int               m_maxBreakers;         // Maximum number to track

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CBreakerBlocks()
   {
      m_lookback = 50;
      m_minImpulseATR = 2.0;
      m_maxBreakers = 5;
      ArrayResize(m_breakers, 0);
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 50, double minImpulseATR = 2.0)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_lookback = lookback;
      m_minImpulseATR = minImpulseATR;
   }

   //+------------------------------------------------------------------+
   //| Detect Breaker Blocks                                            |
   //| A breaker is a failed Order Block that becomes opposite S/R     |
   //+------------------------------------------------------------------+
   void DetectBreakerBlocks()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookback, rates);
      if(copied < m_lookback) return;

      double atr = GetATR();
      if(atr == 0) return;

      // Clear old breakers
      InvalidateOldBreakers();

      // Look for failed order blocks
      for(int i = 10; i < m_lookback - 5; i++)
      {
         // Check for bullish order block that failed (became bearish breaker)
         if(IsBullishOrderBlock(rates, i, atr))
         {
            // Check if price violated this OB from below
            bool violated = false;
            for(int j = i - 1; j >= 1; j--)
            {
               if(rates[j].close < rates[i].low)
               {
                  violated = true;
                  // This is now a Bearish Breaker
                  AddBreaker(rates[i].high, rates[i].low, i, -1,
                             "Bearish Breaker (failed bull OB)");
                  break;
               }
            }
         }

         // Check for bearish order block that failed (became bullish breaker)
         if(IsBearishOrderBlock(rates, i, atr))
         {
            // Check if price violated this OB from above
            bool violated = false;
            for(int j = i - 1; j >= 1; j--)
            {
               if(rates[j].close > rates[i].high)
               {
                  violated = true;
                  // This is now a Bullish Breaker
                  AddBreaker(rates[i].high, rates[i].low, i, 1,
                             "Bullish Breaker (failed bear OB)");
                  break;
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check if bar is Bullish Order Block                             |
   //+------------------------------------------------------------------+
   bool IsBullishOrderBlock(MqlRates &rates[], int index, double atr)
   {
      if(index >= ArraySize(rates) - 5) return false;

      // Strong down move followed by up move
      bool strongDown = (rates[index + 1].close - rates[index + 1].open) < -atr * m_minImpulseATR;
      bool bullishBar = rates[index].close > rates[index].open;
      bool strongUp = (rates[index - 1].close - rates[index - 1].open) > atr * m_minImpulseATR;

      return strongDown && bullishBar && strongUp;
   }

   //+------------------------------------------------------------------+
   //| Check if bar is Bearish Order Block                             |
   //+------------------------------------------------------------------+
   bool IsBearishOrderBlock(MqlRates &rates[], int index, double atr)
   {
      if(index >= ArraySize(rates) - 5) return false;

      // Strong up move followed by down move
      bool strongUp = (rates[index + 1].close - rates[index + 1].open) > atr * m_minImpulseATR;
      bool bearishBar = rates[index].close < rates[index].open;
      bool strongDown = (rates[index - 1].close - rates[index - 1].open) < -atr * m_minImpulseATR;

      return strongUp && bearishBar && strongDown;
   }

   //+------------------------------------------------------------------+
   //| Add Breaker to Array                                            |
   //+------------------------------------------------------------------+
   void AddBreaker(double high, double low, int barsAgo, int type, string desc)
   {
      // Check if already exists
      for(int i = 0; i < ArraySize(m_breakers); i++)
      {
         if(m_breakers[i].isValid &&
            MathAbs(m_breakers[i].highPrice - high) < 0.00001 &&
            MathAbs(m_breakers[i].lowPrice - low) < 0.00001)
         {
            return; // Already exists
         }
      }

      // Limit number of breakers
      if(ArraySize(m_breakers) >= m_maxBreakers)
      {
         // Remove oldest
         ArrayRemove(m_breakers, 0, 1);
      }

      int size = ArraySize(m_breakers);
      ArrayResize(m_breakers, size + 1);

      m_breakers[size].highPrice = high;
      m_breakers[size].lowPrice = low;
      m_breakers[size].barsAgo = barsAgo;
      m_breakers[size].type = type;
      m_breakers[size].isValid = true;
      m_breakers[size].description = desc;
   }

   //+------------------------------------------------------------------+
   //| Invalidate Old Breakers                                         |
   //+------------------------------------------------------------------+
   void InvalidateOldBreakers()
   {
      // Invalidate breakers older than lookback period
      for(int i = 0; i < ArraySize(m_breakers); i++)
      {
         if(m_breakers[i].barsAgo > m_lookback)
            m_breakers[i].isValid = false;
      }

      // Remove invalid breakers
      for(int i = ArraySize(m_breakers) - 1; i >= 0; i--)
      {
         if(!m_breakers[i].isValid)
            ArrayRemove(m_breakers, i, 1);
      }
   }

   //+------------------------------------------------------------------+
   //| Check if current price is at a Breaker                          |
   //+------------------------------------------------------------------+
   bool IsPriceAtBreaker(int signalDir, double &breakerHigh, double &breakerLow)
   {
      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double atr = GetATR();
      if(atr == 0) return false;

      for(int i = 0; i < ArraySize(m_breakers); i++)
      {
         if(!m_breakers[i].isValid) continue;

         // Check if direction matches
         if(m_breakers[i].type != signalDir) continue;

         // Check if price is within breaker zone
         double buffer = atr * 0.3;
         bool inZone = (currentPrice >= m_breakers[i].lowPrice - buffer &&
                       currentPrice <= m_breakers[i].highPrice + buffer);

         if(inZone)
         {
            breakerHigh = m_breakers[i].highPrice;
            breakerLow = m_breakers[i].lowPrice;
            return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-2.0 points)                             |
   //+------------------------------------------------------------------+
   double GetBreakerScore(int signalDir)
   {
      DetectBreakerBlocks();

      double breakerHigh, breakerLow;
      if(IsPriceAtBreaker(signalDir, breakerHigh, breakerLow))
         return 2.0;  // Strong confluence for breaker at current price

      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get ATR Helper                                                   |
   //+------------------------------------------------------------------+
   double GetATR()
   {
      double atr[];
      ArraySetAsSeries(atr, true);

      int handle = iATR(m_symbol, m_timeframe, 14);
      if(handle == INVALID_HANDLE) return 0;

      if(CopyBuffer(handle, 0, 0, 1, atr) <= 0)
      {
         IndicatorRelease(handle);
         return 0;
      }

      IndicatorRelease(handle);
      return atr[0];
   }

   //+------------------------------------------------------------------+
   //| Get Active Breakers                                             |
   //+------------------------------------------------------------------+
   int GetActiveBreakerCount()
   {
      int count = 0;
      for(int i = 0; i < ArraySize(m_breakers); i++)
      {
         if(m_breakers[i].isValid)
            count++;
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Get Breaker Info for Dashboard                                  |
   //+------------------------------------------------------------------+
   string GetBreakerInfo()
   {
      string info = "=== BREAKER BLOCKS ===\n";
      int count = 0;

      for(int i = 0; i < ArraySize(m_breakers); i++)
      {
         if(!m_breakers[i].isValid) continue;

         string typeStr = (m_breakers[i].type == 1) ? "BULL" : "BEAR";
         info += StringFormat("%s: %.5f - %.5f (%d bars ago)\n",
                              typeStr,
                              m_breakers[i].lowPrice,
                              m_breakers[i].highPrice,
                              m_breakers[i].barsAgo);
         count++;
      }

      if(count == 0)
         info += "No active breakers\n";

      return info;
   }
};
