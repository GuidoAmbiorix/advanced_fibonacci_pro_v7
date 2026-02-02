//+------------------------------------------------------------------+
//|                                        DivergenceDetector.mqh   |
//|                    RSI/MACD Divergence Detection Module           |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Divergence Types                                                 |
//+------------------------------------------------------------------+
enum ENUM_DIVERGENCE_TYPE
{
   DIV_NONE = 0,              // No divergence
   DIV_REGULAR_BULLISH = 1,   // Price LL, Indicator HL (reversal up)
   DIV_REGULAR_BEARISH = 2,   // Price HH, Indicator LH (reversal down)
   DIV_HIDDEN_BULLISH = 3,    // Price HL, Indicator LL (continuation up)
   DIV_HIDDEN_BEARISH = 4     // Price LH, Indicator HH (continuation down)
};

//+------------------------------------------------------------------+
//| Divergence Detector Class                                        |
//+------------------------------------------------------------------+
class CDivergenceDetector
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_lookback;

   // Indicator handles
   int               m_hRSI;
   int               m_hMACD;

   // Divergence detection parameters
   int               m_rsiPeriod;
   int               m_macdFast;
   int               m_macdSlow;
   int               m_macdSignal;

   struct DivergencePoint
   {
      int bar;
      double price;
      double indicator;
      bool isHigh;  // true = high, false = low
   };

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CDivergenceDetector()
   {
      m_lookback = 50;
      m_rsiPeriod = 14;
      m_macdFast = 12;
      m_macdSlow = 26;
      m_macdSignal = 9;
      m_hRSI = INVALID_HANDLE;
      m_hMACD = INVALID_HANDLE;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CDivergenceDetector()
   {
      if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hMACD != INVALID_HANDLE) IndicatorRelease(m_hMACD);
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 50)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_lookback = lookback;

      // Create indicator handles
      if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hMACD != INVALID_HANDLE) IndicatorRelease(m_hMACD);

      m_hRSI = iRSI(m_symbol, m_timeframe, m_rsiPeriod, PRICE_CLOSE);
      m_hMACD = iMACD(m_symbol, m_timeframe, m_macdFast, m_macdSlow, m_macdSignal, PRICE_CLOSE);
   }

   //+------------------------------------------------------------------+
   //| Detect RSI Divergence                                           |
   //+------------------------------------------------------------------+
   ENUM_DIVERGENCE_TYPE DetectRSIDivergence()
   {
      if(m_hRSI == INVALID_HANDLE) return DIV_NONE;

      double rsi[];
      double prices[];
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(prices, true);

      // Copy data
      if(CopyBuffer(m_hRSI, 0, 0, m_lookback, rsi) < m_lookback) return DIV_NONE;
      if(CopyClose(m_symbol, m_timeframe, 0, m_lookback, prices) < m_lookback) return DIV_NONE;

      // Find recent swing highs and lows
      DivergencePoint pricePoints[];
      DivergencePoint rsiPoints[];

      FindSwingPoints(prices, pricePoints);
      FindSwingPoints(rsi, rsiPoints);

      // Analyze divergence patterns
      return AnalyzeDivergence(pricePoints, rsiPoints);
   }

   //+------------------------------------------------------------------+
   //| Detect MACD Divergence                                          |
   //+------------------------------------------------------------------+
   ENUM_DIVERGENCE_TYPE DetectMACDDivergence()
   {
      if(m_hMACD == INVALID_HANDLE) return DIV_NONE;

      double macd[];
      double prices[];
      ArraySetAsSeries(macd, true);
      ArraySetAsSeries(prices, true);

      // Copy data (MACD main line)
      if(CopyBuffer(m_hMACD, 0, 0, m_lookback, macd) < m_lookback) return DIV_NONE;
      if(CopyClose(m_symbol, m_timeframe, 0, m_lookback, prices) < m_lookback) return DIV_NONE;

      // Find recent swing highs and lows
      DivergencePoint pricePoints[];
      DivergencePoint macdPoints[];

      FindSwingPoints(prices, pricePoints);
      FindSwingPoints(macd, macdPoints);

      // Analyze divergence patterns
      return AnalyzeDivergence(pricePoints, macdPoints);
   }

   //+------------------------------------------------------------------+
   //| Find Swing Points (highs and lows)                              |
   //+------------------------------------------------------------------+
   void FindSwingPoints(double &data[], DivergencePoint &points[])
   {
      ArrayResize(points, 0);
      int lookbackBars = 5; // Check 5 bars left and right

      for(int i = lookbackBars; i < ArraySize(data) - lookbackBars; i++)
      {
         bool isSwingHigh = true;
         bool isSwingLow = true;

         // Check if this is a swing high
         for(int j = i - lookbackBars; j <= i + lookbackBars; j++)
         {
            if(j == i) continue;
            if(data[j] >= data[i])
            {
               isSwingHigh = false;
               break;
            }
         }

         // Check if this is a swing low
         for(int j = i - lookbackBars; j <= i + lookbackBars; j++)
         {
            if(j == i) continue;
            if(data[j] <= data[i])
            {
               isSwingLow = false;
               break;
            }
         }

         // Add to points array
         if(isSwingHigh || isSwingLow)
         {
            int size = ArraySize(points);
            ArrayResize(points, size + 1);
            points[size].bar = i;
            points[size].price = data[i];
            points[size].indicator = data[i];
            points[size].isHigh = isSwingHigh;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Analyze Divergence Pattern                                      |
   //+------------------------------------------------------------------+
   ENUM_DIVERGENCE_TYPE AnalyzeDivergence(DivergencePoint &pricePoints[], DivergencePoint &indPoints[])
   {
      if(ArraySize(pricePoints) < 2 || ArraySize(indPoints) < 2)
         return DIV_NONE;

      // Find last two highs
      DivergencePoint lastPriceHigh, prevPriceHigh;
      DivergencePoint lastIndHigh, prevIndHigh;
      if(!GetLastTwoHighs(pricePoints, lastPriceHigh, prevPriceHigh))
         return DIV_NONE;
      if(!GetLastTwoHighs(indPoints, lastIndHigh, prevIndHigh))
         return DIV_NONE;

      // Find last two lows
      DivergencePoint lastPriceLow, prevPriceLow;
      DivergencePoint lastIndLow, prevIndLow;
      if(!GetLastTwoLows(pricePoints, lastPriceLow, prevPriceLow))
         return DIV_NONE;
      if(!GetLastTwoLows(indPoints, lastIndLow, prevIndLow))
         return DIV_NONE;

      // Check for Regular Bullish Divergence (Price LL, Indicator HL)
      if(lastPriceLow.price < prevPriceLow.price &&
         lastIndLow.indicator > prevIndLow.indicator)
      {
         return DIV_REGULAR_BULLISH;
      }

      // Check for Regular Bearish Divergence (Price HH, Indicator LH)
      if(lastPriceHigh.price > prevPriceHigh.price &&
         lastIndHigh.indicator < prevIndHigh.indicator)
      {
         return DIV_REGULAR_BEARISH;
      }

      // Check for Hidden Bullish Divergence (Price HL, Indicator LL)
      if(lastPriceLow.price > prevPriceLow.price &&
         lastIndLow.indicator < prevIndLow.indicator)
      {
         return DIV_HIDDEN_BULLISH;
      }

      // Check for Hidden Bearish Divergence (Price LH, Indicator HH)
      if(lastPriceHigh.price < prevPriceHigh.price &&
         lastIndHigh.indicator > prevIndHigh.indicator)
      {
         return DIV_HIDDEN_BEARISH;
      }

      return DIV_NONE;
   }

   //+------------------------------------------------------------------+
   //| Get Last Two Highs                                              |
   //+------------------------------------------------------------------+
   bool GetLastTwoHighs(DivergencePoint &points[], DivergencePoint &last, DivergencePoint &prev)
   {
      int highCount = 0;
      for(int i = 0; i < ArraySize(points); i++)
      {
         if(points[i].isHigh)
         {
            if(highCount == 0)
               last = points[i];
            else if(highCount == 1)
            {
               prev = points[i];
               return true;
            }
            highCount++;
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Get Last Two Lows                                               |
   //+------------------------------------------------------------------+
   bool GetLastTwoLows(DivergencePoint &points[], DivergencePoint &last, DivergencePoint &prev)
   {
      int lowCount = 0;
      for(int i = 0; i < ArraySize(points); i++)
      {
         if(!points[i].isHigh)
         {
            if(lowCount == 0)
               last = points[i];
            else if(lowCount == 1)
            {
               prev = points[i];
               return true;
            }
            lowCount++;
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-1.5 points)                             |
   //+------------------------------------------------------------------+
   double GetDivergenceScore(int signalDir)
   {
      ENUM_DIVERGENCE_TYPE rsiDiv = DetectRSIDivergence();
      ENUM_DIVERGENCE_TYPE macdDiv = DetectMACDDivergence();

      double score = 0;

      // Regular Divergence (reversal signals): +1.5 points
      if(signalDir == 1 && (rsiDiv == DIV_REGULAR_BULLISH || macdDiv == DIV_REGULAR_BULLISH))
         score += 1.5;
      else if(signalDir == -1 && (rsiDiv == DIV_REGULAR_BEARISH || macdDiv == DIV_REGULAR_BEARISH))
         score += 1.5;

      // Hidden Divergence (continuation signals): +1.0 point
      else if(signalDir == 1 && (rsiDiv == DIV_HIDDEN_BULLISH || macdDiv == DIV_HIDDEN_BULLISH))
         score += 1.0;
      else if(signalDir == -1 && (rsiDiv == DIV_HIDDEN_BEARISH || macdDiv == DIV_HIDDEN_BEARISH))
         score += 1.0;

      return score;
   }

   //+------------------------------------------------------------------+
   //| Get Divergence Type Name                                        |
   //+------------------------------------------------------------------+
   string GetDivergenceName(ENUM_DIVERGENCE_TYPE type)
   {
      switch(type)
      {
         case DIV_REGULAR_BULLISH:
            return "Regular Bullish (Reversal Up)";
         case DIV_REGULAR_BEARISH:
            return "Regular Bearish (Reversal Down)";
         case DIV_HIDDEN_BULLISH:
            return "Hidden Bullish (Continuation Up)";
         case DIV_HIDDEN_BEARISH:
            return "Hidden Bearish (Continuation Down)";
         default:
            return "No Divergence";
      }
   }

   //+------------------------------------------------------------------+
   //| Get Divergence Info for Dashboard                               |
   //+------------------------------------------------------------------+
   string GetDivergenceInfo()
   {
      string info = "=== DIVERGENCE ANALYSIS ===\n";

      ENUM_DIVERGENCE_TYPE rsiDiv = DetectRSIDivergence();
      ENUM_DIVERGENCE_TYPE macdDiv = DetectMACDDivergence();

      info += "RSI: " + GetDivergenceName(rsiDiv) + "\n";
      info += "MACD: " + GetDivergenceName(macdDiv) + "\n";

      return info;
   }
};
