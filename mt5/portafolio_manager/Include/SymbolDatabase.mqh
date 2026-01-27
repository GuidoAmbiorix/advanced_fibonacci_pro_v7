//+------------------------------------------------------------------+
//|                                               SymbolDatabase.mqh |
//|          Database of Top Liquid Assets for Portfolio Governor    |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Get List of Top 50 Liquid Symbols                                 |
//+------------------------------------------------------------------+
void GetTop50Symbols(string &symbols[])
{
   string list[] = {
      // --- MAJORS (7) ---
      "EURUSD", "USDJPY", "GBPUSD", "AUDUSD", "USDCHF", "USDCAD", "NZDUSD",
      
      // --- YEN CROSSES (7) ---
      "EURJPY", "GBPJPY", "AUDJPY", "CADJPY", "CHFJPY", "NZDJPY",
      
      // --- EURO CROSSES (6) ---
      "EURGBP", "EURAUD", "EURNZD", "EURCAD", "EURCHF", 
      
      // --- POUND CROSSES (4) ---
      "GBPAUD", "GBPNZD", "GBPCAD", "GBPCHF",
      
      // --- AUD/NZD/CAD CROSSES (6) ---
      "AUDNZD", "AUDCAD", "AUDCHF", "NZDCAD", "NZDCHF", "CADCHF",
      
      // --- METALS (2) ---
      "XAUUSD", "XAGUSD",
      
      // --- LIQUID EXOTICS (Optional - typically spread is higher) ---
      "USDCNH", "USDSGD", "USDMXN", "USDZAR", "USDNOK", "USDSEK",
      
      // --- INDICES (Common Names - Broker Dependent) ---
      // Note: Indices names vary wildly (US500, SPX500, .US500Cash, etc.)
      // We list common ones, but they might fail to select if name differs.
      "US500", "US30", "US100", "DE30", "UK100", "JP225", "DE40", "DAX40", "DJ30"
   };
   
   int size = ArraySize(list);
   ArrayResize(symbols, size);
   for(int i=0; i<size; i++) symbols[i] = list[i];
}

//+------------------------------------------------------------------+
//| Add Top Symbols to Market Watch                                   |
//+------------------------------------------------------------------+
void EnsureMarketWatch()
{
   string candidates[];
   GetTop50Symbols(candidates);
   
   int added = 0;
   Print("🌍 Governor: Validating Market Watch Universe...");
   
   for(int i=0; i<ArraySize(candidates); i++)
   {
      string sym = candidates[i];
      
      // Check if symbol exists in Market Watch already
      if(SymbolInfoInteger(sym, SYMBOL_SELECT)) continue;
      
      // Try to select it
      ResetLastError();
      if(SymbolSelect(sym, true))
      {
         added++;
         // Print("   + Added to Market Watch: ", sym);
      }
      else
      {
         // Optional: Try common suffix variations if simple name fails
         // e.g. EURUSD.pro, EURUSD+, EURUSD.r
         // This is complex to guess, so we rely on exact match for now.
      }
   }
   
   if(added > 0)
      Print("🌍 Governor: Auto-added ", added, " active symbols to Market Watch.");
}
