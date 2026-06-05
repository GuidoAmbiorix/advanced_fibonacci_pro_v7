//+------------------------------------------------------------------+
//|                                            CurrencyStrength.mqh  |
//|                                  Copyright 2026, Infernal Portfolio Governor  |
//+------------------------------------------------------------------+
#ifndef CURRENCY_STRENGTH_MQH
#define CURRENCY_STRENGTH_MQH

//+------------------------------------------------------------------+
//| Get Base Currency (first 3 characters)                           |
//+------------------------------------------------------------------+
string GetBaseCurrency(string symbol)
{
   string normalized = StripBrokerSuffix(symbol);
   StringReplace(normalized, ".pro", "");
   StringReplace(normalized, ".PRO", "");
   StringReplace(normalized, ".x", "");
   StringReplace(normalized, ".X", "");

   if(StringLen(normalized) >= 3)
      return StringSubstr(normalized, 0, 3);

   return "";
}

//+------------------------------------------------------------------+
//| Get Quote Currency (characters 3-5 after stripping suffix)       |
//+------------------------------------------------------------------+
string GetQuoteCurrency(string symbol)
{
   string normalized = StripBrokerSuffix(symbol);
   StringReplace(normalized, ".pro", "");
   StringReplace(normalized, ".PRO", "");
   StringReplace(normalized, ".x", "");
   StringReplace(normalized, ".X", "");

   int len = StringLen(normalized);
   if(len >= 6)
      return StringSubstr(normalized, 3, 3);

   return "";
}

//+------------------------------------------------------------------+
//| Check if currency is quote currency in pair                      |
//+------------------------------------------------------------------+
bool IsQuoteCurrency(string pair, string currency)
{
   string quoteCurr = GetQuoteCurrency(pair);
   StringToUpper(quoteCurr);
   StringToUpper(currency);
   return (quoteCurr == currency);
}

//+------------------------------------------------------------------+
//| Calculate Individual Currency Strength                           |
//+------------------------------------------------------------------+
double CalculateCurrencyStrength(string currency, int lookbackBars = 24)
{
   // Define all major pairs for each currency
   string pairs[];

   StringToUpper(currency);

   if(currency == "USD")
   {
      ArrayResize(pairs, 6);
      pairs[0] = BrokerSymbol("EURUSD"); pairs[1] = BrokerSymbol("GBPUSD"); pairs[2] = BrokerSymbol("AUDUSD");
      pairs[3] = BrokerSymbol("USDJPY"); pairs[4] = BrokerSymbol("USDCAD"); pairs[5] = BrokerSymbol("XAUUSD");
   }
   else if(currency == "EUR")
   {
      ArrayResize(pairs, 3);
      pairs[0] = BrokerSymbol("EURUSD"); pairs[1] = BrokerSymbol("EURJPY"); pairs[2] = BrokerSymbol("EURGBP");
   }
   else if(currency == "GBP")
   {
      ArrayResize(pairs, 3);
      pairs[0] = BrokerSymbol("GBPUSD"); pairs[1] = BrokerSymbol("GBPJPY"); pairs[2] = BrokerSymbol("EURGBP");
   }
   else if(currency == "JPY")
   {
      ArrayResize(pairs, 3);
      pairs[0] = BrokerSymbol("USDJPY"); pairs[1] = BrokerSymbol("EURJPY"); pairs[2] = BrokerSymbol("GBPJPY");
   }
   else if(currency == "AUD")
   {
      ArrayResize(pairs, 2);
      pairs[0] = BrokerSymbol("AUDUSD"); pairs[1] = BrokerSymbol("AUDCAD");
   }
   else if(currency == "CAD")
   {
      ArrayResize(pairs, 2);
      pairs[0] = BrokerSymbol("USDCAD"); pairs[1] = BrokerSymbol("AUDCAD");
   }
   else
   {
      return 0; // Unknown currency
   }

   double strengthSum = 0;
   int count = 0;

   for(int i = 0; i < ArraySize(pairs); i++)
   {
      // Try to get price data
      double currentPrice = iClose(pairs[i], PERIOD_H1, 0);
      double pastPrice = iClose(pairs[i], PERIOD_H1, lookbackBars);

      if(currentPrice == 0 || pastPrice == 0) continue;

      // Calculate percentage move
      double percentMove = ((currentPrice - pastPrice) / pastPrice) * 100.0;

      // If currency is quote currency, invert the sign
      if(IsQuoteCurrency(pairs[i], currency))
         percentMove *= -1.0;

      strengthSum += percentMove;
      count++;
   }

   // Return average strength
   return (count > 0) ? strengthSum / count : 0;
}

//+------------------------------------------------------------------+
//| Calculate Currency Divergence for a Pair                         |
//+------------------------------------------------------------------+
double CalculateCurrencyDivergence(string symbol, double &baseStrength, double &quoteStrength)
{
   // Skip non-FX instruments
   if(StringFind(symbol, "XAU") >= 0) return 0;
   if(StringFind(symbol, "USD30") >= 0) return 0;

   string base = GetBaseCurrency(symbol);
   string quote = GetQuoteCurrency(symbol);

   if(base == "" || quote == "") return 0;

   // Calculate individual currency strengths
   baseStrength = CalculateCurrencyStrength(base, 24);
   quoteStrength = CalculateCurrencyStrength(quote, 24);

   // Divergence = absolute difference
   return MathAbs(baseStrength - quoteStrength);
}

//+------------------------------------------------------------------+
//| Get Expected Direction Based on Currency Strength                |
//+------------------------------------------------------------------+
double GetExpectedDirection(string symbol)
{
   double baseStrength, quoteStrength;
   CalculateCurrencyDivergence(symbol, baseStrength, quoteStrength);

   // If base stronger than quote, expect bullish
   return (baseStrength > quoteStrength) ? 1.0 : -1.0;
}

#endif
