//+------------------------------------------------------------------+
//|                                              SymbolScanner.mqh   |
//|                         Multi-Symbol Engine - Symbol Discovery   |
//|                    Discovers and validates symbols for trading   |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7 - Multi-Symbol Engine"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Discovery Mode Enumeration (Global scope for input compatibility)|
//+------------------------------------------------------------------+
enum ENUM_DISCOVERY_MODE {
   MODE_MANUAL_LIST,      // Parse from input string
   MODE_MARKET_WATCH,     // Scan visible symbols in Market Watch
   MODE_FILE_CONFIG,      // Load from external file (symbols.txt)
   MODE_HYBRID            // Market Watch + manual whitelist filter
};

//+------------------------------------------------------------------+
//| Symbol Scanner Class                                             |
//| Discovers symbols from input list, Market Watch, or config file  |
//+------------------------------------------------------------------+
class CSymbolScanner {
public:

private:
   string m_symbols[];
   ENUM_DISCOVERY_MODE m_mode;
   int m_minHistoryBars;

   //+------------------------------------------------------------------+
   //| Parse comma-separated symbol list                                |
   //+------------------------------------------------------------------+
   void ParseSymbolList(string input) {
      string parts[];
      ushort separator = StringGetCharacter(",", 0);
      int count = StringSplit(input, separator, parts);

      if(count <= 0) {
         Print("WARNING: No symbols in input list");
         return;
      }

      ArrayResize(m_symbols, 0);

      for(int i = 0; i < count; i++) {
         string sym = parts[i];

         // Trim whitespace
         StringTrimLeft(sym);
         StringTrimRight(sym);

         if(StringLen(sym) > 0) {
            int sz = ArraySize(m_symbols);
            ArrayResize(m_symbols, sz + 1);
            m_symbols[sz] = sym;
         }
      }

      Print("Parsed ", ArraySize(m_symbols), " symbols from input list");
   }

   //+------------------------------------------------------------------+
   //| Scan Market Watch for tradable symbols                           |
   //+------------------------------------------------------------------+
   void ScanMarketWatch() {
      int total = SymbolsTotal(true);  // Market Watch only (true)

      Print("Scanning Market Watch: ", total, " symbols visible");

      ArrayResize(m_symbols, 0);

      for(int i = 0; i < total; i++) {
         string sym = SymbolName(i, true);

         if(IsValidForTrading(sym)) {
            int sz = ArraySize(m_symbols);
            ArrayResize(m_symbols, sz + 1);
            m_symbols[sz] = sym;
         } else {
            Print("  Skipped: ", sym, " (not valid for trading)");
         }
      }

      Print("Market Watch scan complete: ", ArraySize(m_symbols), " tradable symbols");
   }

   //+------------------------------------------------------------------+
   //| Load symbols from external file                                  |
   //+------------------------------------------------------------------+
   bool LoadFromFile(string filename) {
      // Check if file exists in MQL5/Files directory
      int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);

      if(handle == INVALID_HANDLE) {
         Print("ERROR: Cannot open ", filename, " - Error: ", GetLastError());
         return false;
      }

      ArrayResize(m_symbols, 0);
      int lineCount = 0;

      while(!FileIsEnding(handle)) {
         string line = FileReadString(handle);
         lineCount++;

         // Trim whitespace
         StringTrimLeft(line);
         StringTrimRight(line);

         // Skip empty lines and comments (lines starting with #)
         if(StringLen(line) == 0 || StringSubstr(line, 0, 1) == "#")
            continue;

         // Parse line: SYMBOL,ENABLED (simple format for now)
         string parts[];
         ushort separator = StringGetCharacter(",", 0);
         int partCount = StringSplit(line, separator, parts);

         if(partCount >= 1) {
            string sym = parts[0];
            StringTrimLeft(sym);
            StringTrimRight(sym);

            // Check if enabled (if format has enable flag)
            bool enabled = true;
            if(partCount >= 2) {
               string enabledStr = parts[1];
               StringTrimLeft(enabledStr);
               enabled = (enabledStr == "1" || StringToUpper(enabledStr) == "TRUE");
            }

            if(enabled && StringLen(sym) > 0) {
               int sz = ArraySize(m_symbols);
               ArrayResize(m_symbols, sz + 1);
               m_symbols[sz] = sym;
            }
         }
      }

      FileClose(handle);

      Print("Loaded ", ArraySize(m_symbols), " symbols from ", filename,
            " (", lineCount, " lines processed)");

      return ArraySize(m_symbols) > 0;
   }

   //+------------------------------------------------------------------+
   //| Check if symbol is valid for trading                             |
   //+------------------------------------------------------------------+
   bool IsValidForTrading(string symbol) {
      // Check if symbol exists and can be selected
      if(!SymbolSelect(symbol, true)) {
         return false;
      }

      // Check trade mode
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);

      if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) {
         return false;
      }

      // Check if symbol has sufficient history
      int bars = Bars(symbol, PERIOD_H1);

      if(bars < m_minHistoryBars) {
         Print("  ", symbol, ": Insufficient history (", bars, " bars < ", m_minHistoryBars, " required)");
         return false;
      }

      // Check if we can get current price
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

      if(bid <= 0 || ask <= 0) {
         Print("  ", symbol, ": Invalid price (Bid=", bid, " Ask=", ask, ")");
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Validate and filter symbol list                                  |
   //+------------------------------------------------------------------+
   void ValidateSymbols() {
      Print("Validating ", ArraySize(m_symbols), " symbols...");

      for(int i = ArraySize(m_symbols) - 1; i >= 0; i--) {
         string sym = m_symbols[i];

         if(!IsValidForTrading(sym)) {
            Print("  ❌ Removed: ", sym, " (failed validation)");

            // Remove from array
            for(int j = i; j < ArraySize(m_symbols) - 1; j++)
               m_symbols[j] = m_symbols[j + 1];

            ArrayResize(m_symbols, ArraySize(m_symbols) - 1);
         } else {
            Print("  ✅ Valid: ", sym);
         }
      }

      Print("Validation complete: ", ArraySize(m_symbols), " symbols ready for trading");
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSymbolScanner() : m_mode(MODE_MANUAL_LIST), m_minHistoryBars(200) {
      ArrayResize(m_symbols, 0);
   }

   //+------------------------------------------------------------------+
   //| Initialize scanner with discovery mode                           |
   //+------------------------------------------------------------------+
   bool Init(string symbolList, ENUM_DISCOVERY_MODE mode = MODE_MANUAL_LIST, int minHistoryBars = 200) {
      m_mode = mode;
      m_minHistoryBars = minHistoryBars;

      Print("========================================");
      Print("  Symbol Scanner Initialization");
      Print("========================================");
      Print("Mode: ", EnumToString(mode));
      Print("Min History Bars: ", minHistoryBars);

      // Discover symbols based on mode
      switch(mode) {
         case MODE_MANUAL_LIST:
            ParseSymbolList(symbolList);
            break;

         case MODE_MARKET_WATCH:
            ScanMarketWatch();
            break;

         case MODE_FILE_CONFIG:
            if(!LoadFromFile("symbols.txt")) {
               Print("WARNING: File load failed, falling back to manual list");
               if(StringLen(symbolList) > 0)
                  ParseSymbolList(symbolList);
            }
            break;

         case MODE_HYBRID:
            // First scan Market Watch, then filter by whitelist
            ScanMarketWatch();
            if(StringLen(symbolList) > 0) {
               // Parse whitelist
               string whitelist[];
               ushort separator = StringGetCharacter(",", 0);
               int count = StringSplit(symbolList, separator, whitelist);

               // Filter symbols: keep only those in whitelist
               for(int i = ArraySize(m_symbols) - 1; i >= 0; i--) {
                  bool inWhitelist = false;
                  for(int j = 0; j < count; j++) {
                     string wlSym = whitelist[j];
                     StringTrimLeft(wlSym);
                     StringTrimRight(wlSym);

                     if(m_symbols[i] == wlSym) {
                        inWhitelist = true;
                        break;
                     }
                  }

                  if(!inWhitelist) {
                     // Remove
                     for(int k = i; k < ArraySize(m_symbols) - 1; k++)
                        m_symbols[k] = m_symbols[k + 1];
                     ArrayResize(m_symbols, ArraySize(m_symbols) - 1);
                  }
               }

               Print("Hybrid mode: Filtered to ", ArraySize(m_symbols), " whitelisted symbols");
            }
            break;
      }

      // Validate all symbols
      ValidateSymbols();

      bool success = ArraySize(m_symbols) > 0;

      if(success) {
         Print("✅ Symbol Scanner Ready: ", ArraySize(m_symbols), " symbols");
         PrintSymbolList();
      } else {
         Print("❌ Symbol Scanner Failed: No valid symbols found");
      }

      Print("========================================");

      return success;
   }

   //+------------------------------------------------------------------+
   //| Get number of discovered symbols                                 |
   //+------------------------------------------------------------------+
   int GetSymbolCount() const {
      return ArraySize(m_symbols);
   }

   //+------------------------------------------------------------------+
   //| Get symbol by index                                              |
   //+------------------------------------------------------------------+
   string GetSymbol(int index) const {
      if(index >= 0 && index < ArraySize(m_symbols))
         return m_symbols[index];
      return "";
   }

   //+------------------------------------------------------------------+
   //| Check if specific symbol is in list                              |
   //+------------------------------------------------------------------+
   bool HasSymbol(string symbol) const {
      for(int i = 0; i < ArraySize(m_symbols); i++)
         if(m_symbols[i] == symbol)
            return true;
      return false;
   }

   //+------------------------------------------------------------------+
   //| Print discovered symbols for debugging                           |
   //+------------------------------------------------------------------+
   void PrintSymbolList() const {
      Print("Discovered Symbols:");
      for(int i = 0; i < ArraySize(m_symbols); i++) {
         string sym = m_symbols[i];
         int bars = Bars(sym, PERIOD_H1);
         double spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);

         Print("  [", i+1, "] ", sym, " - ", bars, " bars, spread=", spread, " points");
      }
   }

   //+------------------------------------------------------------------+
   //| Get all symbols as array (for external use)                      |
   //+------------------------------------------------------------------+
   void GetSymbolArray(string &outSymbols[]) {
      ArrayResize(outSymbols, ArraySize(m_symbols));
      for(int i = 0; i < ArraySize(m_symbols); i++)
         outSymbols[i] = m_symbols[i];
   }
};
//+------------------------------------------------------------------+
