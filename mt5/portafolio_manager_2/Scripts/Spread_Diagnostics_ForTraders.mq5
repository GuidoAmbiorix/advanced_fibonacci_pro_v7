//+------------------------------------------------------------------+
//| Spread_Diagnostics_ForTraders.mq5                                |
//| Copyright 2024, MetaQuotes Ltd.                                  |
//| https://www.mql5.com                                             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

//--- Input parameters
input bool InpCheckAllSymbols = false;  // Check All Available Symbols
input string InpCustomSymbols = "EURUSD,GBPUSD,USDJPY,XAUUSD,GBPJPY";  // Custom Symbols (comma-separated)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("===============================================");
   Print("  SPREAD DIAGNOSTICS - ForTraders Server");
   Print("===============================================");
   Print("Purpose: Identify broker digit format & optimal spread limits");
   Print("");

   string symbols[];
   int symbolCount = 0;

   // Parse symbol list
   if(InpCheckAllSymbols)
   {
      // Get all available symbols
      symbolCount = SymbolsTotal(true);
      ArrayResize(symbols, symbolCount);
      for(int i = 0; i < symbolCount; i++)
         symbols[i] = SymbolName(i, true);
   }
   else
   {
      // Parse custom symbol list
      string symbolList = InpCustomSymbols;
      symbolCount = ParseSymbols(symbolList, symbols);
   }

   Print("Checking ", symbolCount, " symbols...");
   Print("");

   // Check each symbol
   for(int i = 0; i < symbolCount; i++)
   {
      CheckSymbol(symbols[i]);
   }

   Print("===============================================");
   Print("  RECOMMENDATIONS");
   Print("===============================================");
   Print("");
   Print("SPREAD CONFIGURATION GUIDE:");
   Print("");
   Print("5-DIGIT BROKER (10 points = 1 pip):");
   Print("  EURUSD:  InpMaxSpreadPoints=20-30  (2-3 pips)");
   Print("  GBPUSD:  InpMaxSpreadPoints=30-40  (3-4 pips)");
   Print("  USDJPY:  InpMaxSpreadPoints=20-30  (2-3 pips)");
   Print("  GBPJPY:  InpMaxSpreadPoints=40-50  (4-5 pips)");
   Print("  XAUUSD:  InpMaxSpreadPoints=200-300 (20-30 cents)");
   Print("");
   Print("3-DIGIT BROKER (1 point = 1 pip):");
   Print("  EURUSD:  InpMaxSpreadPoints=2-3");
   Print("  GBPUSD:  InpMaxSpreadPoints=3-4");
   Print("  USDJPY:  InpMaxSpreadPoints=2-3");
   Print("  GBPJPY:  InpMaxSpreadPoints=4-5");
   Print("  XAUUSD:  InpMaxSpreadPoints=20-30");
   Print("");
   Print("Current InpMaxSpreadPoints=50 analysis:");
   Print("  - If 5-digit broker: 50 points = 5 pips (NORMAL for majors)");
   Print("  - If 3-digit broker: 50 points = 50 pips (TOO HIGH - blocks trading)");
   Print("");
   Print("Check the 'Digits' column above to determine your broker format.");
   Print("===============================================");
}

//+------------------------------------------------------------------+
//| Parse comma-separated symbol list                                |
//+------------------------------------------------------------------+
int ParseSymbols(string symbolList, string &symbols[])
{
   int count = 0;
   string temp[];

   // Remove spaces
   StringReplace(symbolList, " ", "");

   // Split by comma
   int result = StringSplit(symbolList, ',', temp);

   if(result > 0)
   {
      ArrayResize(symbols, result);
      for(int i = 0; i < result; i++)
      {
         symbols[i] = temp[i];
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Check individual symbol                                          |
//+------------------------------------------------------------------+
void CheckSymbol(string symbol)
{
   // Verify symbol exists
   if(!SymbolSelect(symbol, true))
   {
      Print("⚠️ Symbol ", symbol, " not found or not available");
      return;
   }

   // Get symbol info
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      Print("⚠️ Failed to get tick data for ", symbol);
      return;
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double spreadValue = spread * point;

   // Determine broker type
   string brokerType = "";
   double spreadInPips = 0;
   string recommendedPoints = "";

   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
   {
      // Gold calculation (in cents)
      spreadInPips = spread * 10.0;  // Convert to cents
      brokerType = (digits == 2) ? "3-digit (1pt=1cent)" : "5-digit (1pt=0.1cent)";
      recommendedPoints = (digits == 2) ? "20-30" : "200-300";
   }
   else if(StringFind(symbol, "JPY") >= 0)
   {
      // JPY pairs
      brokerType = (digits == 3) ? "3-digit (1pt=1pip)" : "5-digit (10pt=1pip)";
      spreadInPips = (digits == 3) ? spread : spread / 10.0;

      if(StringFind(symbol, "GBP") >= 0)
         recommendedPoints = (digits == 3) ? "4-5" : "40-50";
      else
         recommendedPoints = (digits == 3) ? "2-3" : "20-30";
   }
   else
   {
      // Standard forex pairs
      brokerType = (digits == 3) ? "3-digit (1pt=1pip)" : "5-digit (10pt=1pip)";
      spreadInPips = (digits == 3) ? spread : spread / 10.0;

      if(StringFind(symbol, "GBP") >= 0)
         recommendedPoints = (digits == 3) ? "3-4" : "30-40";
      else
         recommendedPoints = (digits == 3) ? "2-3" : "20-30";
   }

   // Print results
   Print("─────────────────────────────────────────────");
   Print("Symbol: ", symbol);
   Print("  Digits: ", digits, " (", brokerType, ")");
   Print("  Current Spread: ", spread, " points");
   Print("  Spread in Pips: ", DoubleToString(spreadInPips, 1));
   Print("  Spread Value: ", DoubleToString(spreadValue, digits));
   Print("  Point Size: ", DoubleToString(point, digits));
   Print("  Tick Size: ", DoubleToString(tickSize, digits));
   Print("  ");
   Print("  ✅ RECOMMENDED: InpMaxSpreadPoints = ", recommendedPoints);
   Print("  ");

   // Warning if current spread is unusual
   if(StringFind(symbol, "XAU") >= 0)
   {
      if(spread > 300)
         Print("  ⚠️ WARNING: Spread unusually high (>30 cents)");
   }
   else if(spreadInPips > 10)
   {
      Print("  ⚠️ WARNING: Spread unusually high (>10 pips)");
   }
}
