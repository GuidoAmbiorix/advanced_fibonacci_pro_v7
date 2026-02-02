//+------------------------------------------------------------------+
//|                                            VolumeAnalysis.mqh    |
//|                         Volume Profile & VWAP Analysis Module     |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Volume Analysis Class                                             |
//+------------------------------------------------------------------+
class CVolumeAnalysis
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_profilePeriod;      // Bars to analyze for Volume Profile
   int               m_vwapPeriod;         // VWAP lookback period

   // Volume Profile Data
   double            m_poc;                // Point of Control (highest volume price)
   double            m_vah;                // Value Area High (70% volume top)
   double            m_val;                // Value Area Low (70% volume bottom)
   double            m_avgVolume;          // Average volume

   // VWAP Data
   double            m_vwap;               // Volume Weighted Average Price
   double            m_vwapUpper;          // VWAP upper band
   double            m_vwapLower;          // VWAP lower band

   // OBV
   double            m_obv[];              // On-Balance Volume array

   struct PriceVolumeNode
   {
      double price;
      double volume;
   };

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CVolumeAnalysis()
   {
      m_profilePeriod = 100;
      m_vwapPeriod = 100;
      m_poc = 0;
      m_vah = 0;
      m_val = 0;
      m_vwap = 0;
      m_avgVolume = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, ENUM_TIMEFRAMES timeframe, int profilePeriod = 100, int vwapPeriod = 100)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_profilePeriod = profilePeriod;
      m_vwapPeriod = vwapPeriod;

      ArraySetAsSeries(m_obv, true);
      ArrayResize(m_obv, vwapPeriod);
   }

   //+------------------------------------------------------------------+
   //| Calculate Volume Profile (POC, VAH, VAL)                        |
   //+------------------------------------------------------------------+
   bool CalculateVolumeProfile()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, m_profilePeriod, rates);
      if(copied < m_profilePeriod) return false;

      // Find price range
      int maxIdx = ArrayMaximum(rates, 0, m_profilePeriod);
      int minIdx = ArrayMinimum(rates, 0, m_profilePeriod);

      if(maxIdx < 0 || minIdx < 0 || maxIdx >= copied || minIdx >= copied)
         return false;

      double highPrice = rates[maxIdx].high;
      double lowPrice = rates[minIdx].low;

      // Create price bins (50 levels)
      int numBins = 50;
      double binSize = (highPrice - lowPrice) / numBins;
      if(binSize <= 0) return false;

      PriceVolumeNode nodes[];
      ArrayResize(nodes, numBins);

      // Initialize bins
      for(int i = 0; i < numBins; i++)
      {
         nodes[i].price = lowPrice + (binSize * i) + (binSize / 2);
         nodes[i].volume = 0;
      }

      // Accumulate volume in bins
      double totalVolume = 0;
      for(int i = 0; i < m_profilePeriod; i++)
      {
         double barMid = (rates[i].high + rates[i].low) / 2;
         long barVol = rates[i].tick_volume;

         int binIndex = (int)((barMid - lowPrice) / binSize);
         if(binIndex >= 0 && binIndex < numBins)
         {
            nodes[binIndex].volume += (double)barVol;
            totalVolume += (double)barVol;
         }
      }

      if(totalVolume == 0) return false;

      // Find POC (highest volume bin)
      int maxBin = 0;
      double maxVolume = 0;
      for(int i = 0; i < numBins; i++)
      {
         if(nodes[i].volume > maxVolume)
         {
            maxVolume = nodes[i].volume;
            maxBin = i;
         }
      }

      m_poc = nodes[maxBin].price;

      // Calculate Value Area (70% of volume)
      double targetVolume = totalVolume * 0.70;
      double accumulatedVolume = nodes[maxBin].volume;
      int upperBin = maxBin;
      int lowerBin = maxBin;

      while(accumulatedVolume < targetVolume && (upperBin < numBins - 1 || lowerBin > 0))
      {
         double upperVol = (upperBin < numBins - 1) ? nodes[upperBin + 1].volume : 0;
         double lowerVol = (lowerBin > 0) ? nodes[lowerBin - 1].volume : 0;

         if(upperVol > lowerVol && upperBin < numBins - 1)
         {
            upperBin++;
            accumulatedVolume += upperVol;
         }
         else if(lowerBin > 0)
         {
            lowerBin--;
            accumulatedVolume += lowerVol;
         }
         else
            break;
      }

      m_vah = nodes[upperBin].price;
      m_val = nodes[lowerBin].price;

      // Calculate average volume
      m_avgVolume = totalVolume / m_profilePeriod;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate VWAP and Bands                                        |
   //+------------------------------------------------------------------+
   bool CalculateVWAP()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, m_vwapPeriod, rates);
      if(copied < m_vwapPeriod) return false;

      double sumPV = 0;  // Sum of (Price * Volume)
      double sumV = 0;   // Sum of Volume
      double sumPV2 = 0; // Sum of (Price^2 * Volume) for std dev

      for(int i = 0; i < m_vwapPeriod; i++)
      {
         double typicalPrice = (rates[i].high + rates[i].low + rates[i].close) / 3;
         double volume = (double)rates[i].tick_volume;

         sumPV += typicalPrice * volume;
         sumV += volume;
         sumPV2 += typicalPrice * typicalPrice * volume;
      }

      if(sumV == 0) return false;

      m_vwap = sumPV / sumV;

      // Calculate standard deviation
      double variance = (sumPV2 / sumV) - (m_vwap * m_vwap);
      double stdDev = (variance > 0) ? MathSqrt(variance) : 0;

      m_vwapUpper = m_vwap + (stdDev * 2.0);
      m_vwapLower = m_vwap - (stdDev * 2.0);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate On-Balance Volume                                      |
   //+------------------------------------------------------------------+
   bool CalculateOBV()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, m_vwapPeriod, rates);
      if(copied < m_vwapPeriod) return false;

      m_obv[m_vwapPeriod - 1] = (double)rates[m_vwapPeriod - 1].tick_volume;

      for(int i = m_vwapPeriod - 2; i >= 0; i--)
      {
         if(rates[i].close > rates[i + 1].close)
            m_obv[i] = m_obv[i + 1] + rates[i].tick_volume;
         else if(rates[i].close < rates[i + 1].close)
            m_obv[i] = m_obv[i + 1] - rates[i].tick_volume;
         else
            m_obv[i] = m_obv[i + 1];
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check Volume Breakout (1.5x average)                            |
   //+------------------------------------------------------------------+
   bool IsVolumeBreakout()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, 2, rates);
      if(copied < 2) return false;

      if(m_avgVolume == 0) CalculateVolumeProfile();

      return (rates[0].tick_volume >= m_avgVolume * 1.5);
   }

   //+------------------------------------------------------------------+
   //| Get Volume Rate of Change                                        |
   //+------------------------------------------------------------------+
   double GetVolumeROC(int period = 10)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, period + 1, rates);
      if(copied < period + 1) return 0;

      double currentVol = (double)rates[0].tick_volume;
      double pastVol = (double)rates[period].tick_volume;

      if(pastVol == 0) return 0;

      return ((currentVol - pastVol) / pastVol) * 100;
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-2.5 points)                             |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int signalDir)
   {
      // Update calculations
      CalculateVolumeProfile();
      CalculateVWAP();
      CalculateOBV();

      double score = 0;
      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double atr = GetATR();
      if(atr == 0) return 0;

      // 1. POC Confluence (+1.0 point)
      double pocDist = MathAbs(currentPrice - m_poc);
      if(pocDist < atr * 0.5) score += 1.0;

      // 2. Value Area Edges (+0.5 point)
      bool nearVAH = MathAbs(currentPrice - m_vah) < atr * 0.5;
      bool nearVAL = MathAbs(currentPrice - m_val) < atr * 0.5;

      if((signalDir == 1 && nearVAL) || (signalDir == -1 && nearVAH))
         score += 0.5;

      // 3. VWAP Reversion (+0.5 point)
      bool aboveVWAP = currentPrice > m_vwap;
      bool belowVWAP = currentPrice < m_vwap;

      if((signalDir == 1 && belowVWAP && currentPrice > m_vwapLower) ||
         (signalDir == -1 && aboveVWAP && currentPrice < m_vwapUpper))
         score += 0.5;

      // 4. Volume Breakout (+0.5 point)
      if(IsVolumeBreakout())
         score += 0.5;

      return score;
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
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   double GetPOC() { return m_poc; }
   double GetVAH() { return m_vah; }
   double GetVAL() { return m_val; }
   double GetVWAP() { return m_vwap; }
   double GetVWAPUpper() { return m_vwapUpper; }
   double GetVWAPLower() { return m_vwapLower; }
   double GetOBV() { return m_obv[0]; }
   double GetAvgVolume() { return m_avgVolume; }
};
