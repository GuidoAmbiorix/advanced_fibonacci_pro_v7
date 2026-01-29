//+------------------------------------------------------------------+
//|                                            KillzoneDatabase.mqh  |
//|          Optimal Killzone Assignments for 24/7 Trading           |
//|          Based on 2026 Market Research & ICT Methodology         |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Get Optimal Killzones for Symbol                                 |
//| Returns: Asian, LondonOpen, NY, LondonClose flags                |
//+------------------------------------------------------------------+
void GetOptimalKillzonesForSymbol(string symbol,
                                   bool &enableAsian,
                                   bool &enableLondonOpen,
                                   bool &enableNY,
                                   bool &enableLondonClose)
{
   // Default: all off
   enableAsian = false;
   enableLondonOpen = false;
   enableNY = false;
   enableLondonClose = false;

   string sym = symbol;
   StringToUpper(sym);

   // Remove broker suffixes
   StringReplace(sym, ".PRO", "");
   StringReplace(sym, ".STD", "");
   StringReplace(sym, ".M", "");
   StringReplace(sym, "+", "");
   StringReplace(sym, ".A", "");
   StringReplace(sym, "_OPT", "");

   // ===================================================================
   // FOCUSED 6-PAIR SYSTEM - LONDON + NY KILLZONES ONLY
   // OPTIMIZED FOR M15 TIMEFRAME (ICT Sweet Spot)
   // ===================================================================
   // NO ASIAN SESSION - Quality > Quantity
   // London: 02:00-05:00 EST (07:00-10:00 GMT) = 12 M15 bars
   // NY: 07:00-10:00 EST (12:00-15:00 GMT) = 12 M15 bars

   // === PAIR 1: EURUSD - King of Forex ===
   if(StringFind(sym, "EURUSD") >= 0)
   {
      enableLondonOpen = true;  // EUR strength in London
      enableNY = true;          // Continuation + overlap
      enableAsian = false;      // NO Asian trading
      enableLondonClose = false; // NO London close
   }

   // === PAIR 2: GBPUSD - Cable ===
   else if(StringFind(sym, "GBPUSD") >= 0)
   {
      enableLondonOpen = true;  // GBP volatility in London
      enableNY = true;          // USD strength in NY
      enableAsian = false;
      enableLondonClose = false;
   }

   // === PAIR 3: XAUUSD - Gold ===
   else if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      enableLondonOpen = true;  // London open spike
      enableNY = true;          // NY peak liquidity
      enableAsian = false;
      enableLondonClose = false;
   }

   // === PAIR 4: USDCHF - Swissy ===
   else if(StringFind(sym, "USDCHF") >= 0)
   {
      enableLondonOpen = true;  // Swiss banking hours
      enableNY = true;          // USD strength
      enableAsian = false;
      enableLondonClose = false;
   }

   // === PAIR 5: USDCAD - Loonie ===
   else if(StringFind(sym, "USDCAD") >= 0)
   {
      enableLondonOpen = true;  // Oil correlation starts
      enableNY = true;          // Peak oil trading (strongest)
      enableAsian = false;
      enableLondonClose = false;
   }

   // === PAIR 6: GBPJPY - Volatile Cross ===
   else if(StringFind(sym, "GBPJPY") >= 0)
   {
      enableLondonOpen = true;  // GBP volatility
      enableNY = true;          // Continuation moves
      enableAsian = false;      // NO Asian (focus on quality)
      enableLondonClose = false;
   }

   // === ALL OTHER PAIRS - DISABLED ===
   else
   {
      // Not in the focused 6 = don't trade
      enableAsian = false;
      enableLondonOpen = false;
      enableNY = false;
      enableLondonClose = false;
   }


   // ===================================================================
   // DEFAULT FALLBACK
   // ===================================================================
   // If no killzones matched, enable London + NY (safest default)
   if(!enableAsian && !enableLondonOpen && !enableNY && !enableLondonClose)
   {
      enableLondonOpen = true;
      enableNY = true;
   }
}

//+------------------------------------------------------------------+
//| Get 24/7 Coverage Symbol List                                     |
//| Returns symbols that provide continuous trading opportunities    |
//+------------------------------------------------------------------+
void Get24_7_SymbolList(string &symbols[])
{
   string list[] = {
      // === ASIAN SESSION (8 symbols) ===
      "USDJPY",    // Primary JPY pair
      "EURJPY",    // Crosses Asian + London
      "GBPJPY",    // Volatile crossover
      "AUDJPY",    // Pacific overlap
      "AUDUSD",    // Aussie liquidity
      "NZDUSD",    // Kiwi coverage
      "AUDNZD",    // Regional pair
      "CHFJPY",    // Safe haven cross

      // === LONDON SESSION (8 symbols) ===
      "EURUSD",    // King of forex
      "GBPUSD",    // Cable - high volatility
      "EURGBP",    // Pure European
      "EURAUD",    // EUR cross
      "EURCHF",    // SNB influenced
      "GBPAUD",    // GBP cross
      "EURCAD",    // Euro-North America
      "GBPCAD",    // Pound-CAD

      // === NEW YORK SESSION (8 symbols) ===
      "USDCAD",    // Loonie
      "USDCHF",    // Swissy
      "NZDUSD",    // Also trades NY
      "XAUUSD",    // Gold (London-NY overlap)
      "XAGUSD",    // Silver
      "US30",      // Dow Jones
      "US100",     // NASDAQ (NAS100)
      "US500"      // S&P 500
   };

   int size = ArraySize(list);
   ArrayResize(symbols, size);
   for(int i=0; i<size; i++) symbols[i] = list[i];
}

//+------------------------------------------------------------------+
//| Get Priority Symbols (Highest Liquidity)                         |
//| Top 10 most liquid symbols for Portfolio Governor                |
//+------------------------------------------------------------------+
void GetPrioritySymbols(string &symbols[])
{
   string list[] = {
      // Triple-A Tier (Always trade these)
      "EURUSD",    // 28% of daily forex volume
      "USDJPY",    // 13% of daily forex volume
      "GBPUSD",    // 11% of daily forex volume
      "AUDUSD",    // 5% of daily forex volume
      "USDCAD",    // 4% of daily forex volume

      // High-Quality Tier
      "EURJPY",    // High volatility cross
      "XAUUSD",    // Gold - trending market
      "US30",      // US Index - institutional flow
      "NZDUSD",    // Carry trade favorite
      "EURGBP"     // European stability
   };

   int size = ArraySize(list);
   ArrayResize(symbols, size);
   for(int i=0; i<size; i++) symbols[i] = list[i];
}

//+------------------------------------------------------------------+
//| Detect Current Active Killzone                                   |
//| Returns which session is currently active                        |
//+------------------------------------------------------------------+
enum ENUM_CURRENT_SESSION
{
   SESSION_ASIAN,
   SESSION_LONDON,
   SESSION_NY,
   SESSION_LONDON_CLOSE,
   SESSION_DEAD_ZONE  // Outside all killzones
};

ENUM_CURRENT_SESSION GetCurrentSession(int brokerUTCOffset = 2, bool autoDST = true)
{
   // Get current time
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt); // Get current broker time

   // Check if DST applies (March-October in Northern Hemisphere)
   int dstOffset = 0;
   if(autoDST && (dt.mon >= 3 && dt.mon <= 10))
      dstOffset = 1;

   // Calculate GMT hour from broker time
   int hourGMT = dt.hour - brokerUTCOffset - dstOffset;

   // Normalize to 0-23 range
   if(hourGMT >= 24) hourGMT -= 24;
   if(hourGMT < 0) hourGMT += 24;

   // Debug output
   static datetime lastPrint = 0;
   if(TimeCurrent() - lastPrint > 300) // Print every 5 minutes
   {
      Print("🕐 SESSION DEBUG: Broker Time: ", dt.hour, ":00 | GMT Hour: ", hourGMT, " | DST: ", (dstOffset == 1 ? "Yes" : "No"), " | Month: ", dt.mon);
      lastPrint = TimeCurrent();
   }

   // ICT Killzone Times (GMT):
   // Asian: 01:00-03:00 GMT (Tokyo open)
   // London: 07:00-10:00 GMT (London open) - winter / 08:00-11:00 summer
   // NY: 12:00-15:00 GMT (NY open)
   // London Close: 15:00-17:00 GMT

   int londonStart = (dstOffset == 1) ? 7 : 8;  // 8 GMT winter, 7 GMT summer
   int londonEnd = londonStart + 3;

   // Asian Session (01:00-03:00 GMT)
   if(hourGMT >= 1 && hourGMT < 3)
      return SESSION_ASIAN;

   // London Session (07:00-10:00 or 08:00-11:00 GMT)
   if(hourGMT >= londonStart && hourGMT < londonEnd)
      return SESSION_LONDON;

   // NY Session (12:00-15:00 GMT)
   if(hourGMT >= 12 && hourGMT < 15)
      return SESSION_NY;

   // London Close (15:00-17:00 GMT)
   if(hourGMT >= 15 && hourGMT < 17)
      return SESSION_LONDON_CLOSE;

   return SESSION_DEAD_ZONE;
}

//+------------------------------------------------------------------+
//| Get Symbols for Current Active Killzone                          |
//| Returns only symbols that should trade RIGHT NOW                 |
//+------------------------------------------------------------------+
void GetSymbolsForCurrentSession(string &symbols[], int brokerUTCOffset = 2)
{
   ENUM_CURRENT_SESSION currentSession = GetCurrentSession(brokerUTCOffset, true);

   ArrayResize(symbols, 0);

   switch(currentSession)
   {
      case SESSION_ASIAN:
      {
         // ASIAN SESSION - DISABLED (Focus on London+NY only)
         string asianList[] = {};  // Empty - no trading
         ArrayCopy(symbols, asianList);
         break;
      }

      case SESSION_LONDON:
      {
         // LONDON KILLZONE (02:00-05:00 EST / 07:00-10:00 GMT)
         // FOCUSED 6 PAIRS - ICT Optimized Selection
         string londonList[] = {
            "EURUSD",    // 1. King - EUR strength
            "GBPUSD",    // 2. Cable - GBP volatility
            "XAUUSD",    // 3. Gold - London open beast
            "USDCHF",    // 4. Swissy - EUR inverse
            "USDCAD",    // 5. Loonie - commodity correlation
            "GBPJPY"     // 6. Cross - high volatility scalping
         };
         ArrayCopy(symbols, londonList);
         break;
      }

      case SESSION_NY:
      {
         // NY KILLZONE (07:00-10:00 EST / 12:00-15:00 GMT)
         // SAME 6 PAIRS - London+NY overlap = GOLDEN ZONE
         string nyList[] = {
            "EURUSD",    // 1. King - still liquid
            "GBPUSD",    // 2. Cable - NY continuation
            "XAUUSD",    // 3. Gold - NY peak liquidity
            "USDCHF",    // 4. Swissy - USD strength
            "USDCAD",    // 5. Loonie - oil correlation (strongest in NY)
            "GBPJPY"     // 6. Cross - continuation moves
         };
         ArrayCopy(symbols, nyList);
         break;
      }

      case SESSION_LONDON_CLOSE:
      {
         // LONDON CLOSE - DISABLED (Focus on killzones only)
         string closeList[] = {};  // Empty - no trading
         ArrayCopy(symbols, closeList);
         break;
      }

      case SESSION_DEAD_ZONE:
      {
         // DEAD ZONE - DISABLED (No 24/7 trading)
         string deadList[] = {};  // Empty - rest during low liquidity
         ArrayCopy(symbols, deadList);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Get Session Name String                                          |
//+------------------------------------------------------------------+
string GetSessionName(ENUM_CURRENT_SESSION session)
{
   switch(session)
   {
      case SESSION_ASIAN:        return "ASIAN (Tokyo)";
      case SESSION_LONDON:       return "LONDON (European)";
      case SESSION_NY:           return "NEW YORK (Wall Street)";
      case SESSION_LONDON_CLOSE: return "LONDON CLOSE";
      case SESSION_DEAD_ZONE:    return "DEAD ZONE (Low Liquidity)";
      default:                   return "UNKNOWN";
   }
}
