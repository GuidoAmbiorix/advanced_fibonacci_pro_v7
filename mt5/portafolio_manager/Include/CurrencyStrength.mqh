//+------------------------------------------------------------------+
//|                                         CurrencyStrength.mqh     |
//|                          Currency Strength Meter Module           |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Currency Strength Class                                          |
//+------------------------------------------------------------------+
class CCurrencyStrength
{
private:
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_period;              // Lookback period for strength calculation

   // 8 Major Currencies
   string            m_currencies[8];

   // Currency pair matrix (28 pairs)
   string            m_pairs[];

   // Strength values (-100 to +100)
   double            m_strength[8];

   struct CurrencyIndex
   {
      string name;
      int index;
   };

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CCurrencyStrength()
   {
      m_period = 24;  // 24 bars lookback
      m_timeframe = PERIOD_H1;

      // Initialize 8 major currencies
      m_currencies[0] = "USD";
      m_currencies[1] = "EUR";
      m_currencies[2] = "GBP";
      m_currencies[3] = "JPY";
      m_currencies[4] = "AUD";
      m_currencies[5] = "CAD";
      m_currencies[6] = "CHF";
      m_currencies[7] = "NZD";

      // Initialize strength array
      for(int i = 0; i < 8; i++)
         m_strength[i] = 0;

      BuildPairList();
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(ENUM_TIMEFRAMES timeframe, int period = 24)
   {
      m_timeframe = timeframe;
      m_period = period;
   }

   //+------------------------------------------------------------------+
   //| Build list of tradeable pairs                                   |
   //+------------------------------------------------------------------+
   void BuildPairList()
   {
      string tempPairs[];
      ArrayResize(tempPairs, 0);

      // Build all possible combinations (28 pairs)
      for(int i = 0; i < 8; i++)
      {
         for(int j = i + 1; j < 8; j++)
         {
            string pair1 = m_currencies[i] + m_currencies[j];
            string pair2 = m_currencies[j] + m_currencies[i];

            // Check if pair exists in Market Watch
            if(SymbolSelect(pair1, true))
            {
               int size = ArraySize(tempPairs);
               ArrayResize(tempPairs, size + 1);
               tempPairs[size] = pair1;
            }
            else if(SymbolSelect(pair2, true))
            {
               int size = ArraySize(tempPairs);
               ArrayResize(tempPairs, size + 1);
               tempPairs[size] = pair2;
            }
         }
      }

      ArrayResize(m_pairs, ArraySize(tempPairs));
      ArrayCopy(m_pairs, tempPairs);
   }

   //+------------------------------------------------------------------+
   //| Calculate Currency Strength                                      |
   //+------------------------------------------------------------------+
   bool CalculateStrength()
   {
      // Reset strength values
      for(int i = 0; i < 8; i++)
         m_strength[i] = 0;

      int pairCount[8];
      for(int i = 0; i < 8; i++)
         pairCount[i] = 0;

      // Calculate percentage change for each pair
      for(int p = 0; p < ArraySize(m_pairs); p++)
      {
         string pair = m_pairs[p];

         MqlRates rates[];
         ArraySetAsSeries(rates, true);

         int copied = CopyRates(pair, m_timeframe, 0, m_period + 1, rates);
         if(copied < m_period + 1) continue;

         double oldPrice = rates[m_period].close;
         double newPrice = rates[0].close;

         if(oldPrice == 0) continue;

         double percentChange = ((newPrice - oldPrice) / oldPrice) * 100;

         // Extract base and quote currency
         string baseCurrency = StringSubstr(pair, 0, 3);
         string quoteCurrency = StringSubstr(pair, 3, 3);

         // Update strength
         int baseIdx = GetCurrencyIndex(baseCurrency);
         int quoteIdx = GetCurrencyIndex(quoteCurrency);

         if(baseIdx >= 0)
         {
            m_strength[baseIdx] += percentChange;
            pairCount[baseIdx]++;
         }

         if(quoteIdx >= 0)
         {
            m_strength[quoteIdx] -= percentChange;
            pairCount[quoteIdx]++;
         }
      }

      // Average the strength
      for(int i = 0; i < 8; i++)
      {
         if(pairCount[i] > 0)
            m_strength[i] /= pairCount[i];
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Currency Index                                               |
   //+------------------------------------------------------------------+
   int GetCurrencyIndex(string currency)
   {
      for(int i = 0; i < 8; i++)
      {
         if(m_currencies[i] == currency)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Get Pair Strength Differential                                  |
   //+------------------------------------------------------------------+
   double GetPairStrength(string symbol)
   {
      CalculateStrength();

      if(StringLen(symbol) < 6) return 0;

      string baseCurrency = StringSubstr(symbol, 0, 3);
      string quoteCurrency = StringSubstr(symbol, 3, 3);

      int baseIdx = GetCurrencyIndex(baseCurrency);
      int quoteIdx = GetCurrencyIndex(quoteCurrency);

      if(baseIdx < 0 || quoteIdx < 0) return 0;

      // Positive = base stronger than quote (bullish)
      // Negative = quote stronger than base (bearish)
      return m_strength[baseIdx] - m_strength[quoteIdx];
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-1.5 points)                             |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(string symbol, int signalDir)
   {
      double pairStrength = GetPairStrength(symbol);
      double absStrength = MathAbs(pairStrength);

      // Check alignment with signal direction
      bool aligned = (signalDir == 1 && pairStrength > 0) ||
                     (signalDir == -1 && pairStrength < 0);

      if(!aligned) return 0;

      // Strong alignment (>50): +1.5
      if(absStrength > 50)
         return 1.5;

      // Moderate (30-50): +1.0
      if(absStrength > 30)
         return 1.0;

      // Weak (15-30): +0.5
      if(absStrength > 15)
         return 0.5;

      return 0;
   }

   //+------------------------------------------------------------------+
   //| Check if Strong Alignment                                       |
   //+------------------------------------------------------------------+
   bool IsStrongAlignment(string symbol, int signalDir)
   {
      double pairStrength = GetPairStrength(symbol);

      bool aligned = (signalDir == 1 && pairStrength > 30) ||
                     (signalDir == -1 && pairStrength < -30);

      return aligned;
   }

   //+------------------------------------------------------------------+
   //| Get Currency Strength                                           |
   //+------------------------------------------------------------------+
   double GetCurrencyStrength(string currency)
   {
      CalculateStrength();

      int idx = GetCurrencyIndex(currency);
      if(idx < 0) return 0;

      return m_strength[idx];
   }

   //+------------------------------------------------------------------+
   //| Get Strongest Currency                                          |
   //+------------------------------------------------------------------+
   string GetStrongestCurrency()
   {
      CalculateStrength();

      int maxIdx = 0;
      double maxStrength = m_strength[0];

      for(int i = 1; i < 8; i++)
      {
         if(m_strength[i] > maxStrength)
         {
            maxStrength = m_strength[i];
            maxIdx = i;
         }
      }

      return m_currencies[maxIdx];
   }

   //+------------------------------------------------------------------+
   //| Get Weakest Currency                                            |
   //+------------------------------------------------------------------+
   string GetWeakestCurrency()
   {
      CalculateStrength();

      int minIdx = 0;
      double minStrength = m_strength[0];

      for(int i = 1; i < 8; i++)
      {
         if(m_strength[i] < minStrength)
         {
            minStrength = m_strength[i];
            minIdx = i;
         }
      }

      return m_currencies[minIdx];
   }
};
