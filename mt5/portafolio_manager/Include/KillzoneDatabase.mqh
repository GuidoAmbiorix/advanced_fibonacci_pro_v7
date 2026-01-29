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
   // ASIAN SESSION PAIRS (Tokyo: 8:00-10:00 PM NY / 1:00-3:00 AM GMT)
   // ===================================================================
   // Primary: JPY, AUD, NZD pairs
   // Source: https://scribehow.com/page/Best_Forex_Pairs_to_Trade_During_Each_Session_2026__n1ksVWMZSHy03_UEvR4wUw

   if(StringFind(sym, "JPY") >= 0)
   {
      // All JPY pairs: Asian + NY (USD/JPY is liquid globally)
      enableAsian = true;
      enableNY = true;

      // EUR/JPY, GBP/JPY also active in London
      if(StringFind(sym, "EUR") >= 0 || StringFind(sym, "GBP") >= 0)
         enableLondonOpen = true;
   }
   else if(StringFind(sym, "AUD") >= 0 || StringFind(sym, "NZD") >= 0)
   {
      // AUD/NZD pairs: Asian + NY overlap
      enableAsian = true;
      enableNY = true;
   }
   // ===================================================================
   // LONDON SESSION PAIRS (London: 2:00-5:00 AM NY / 8:00-11:00 GMT)
   // ===================================================================
   // Primary: EUR, GBP, CHF
   // Source: https://tradersunion.com/interesting-articles/best-forex-currency-pairs/london-session-forex-pairs/

   else if(StringFind(sym, "EUR") >= 0 || StringFind(sym, "GBP") >= 0 ||
           StringFind(sym, "CHF") >= 0)
   {
      // European pairs: London + NY (overlap is golden)
      enableLondonOpen = true;
      enableNY = true;
   }

   // ===================================================================
   // NEW YORK SESSION PAIRS (NY: 7:00-10:00 AM / 12:00-15:00 GMT)
   // ===================================================================
   // Primary: USD, CAD pairs
   // Source: https://medium.com/coinmonks/the-complete-new-york-session-forex-trading-strategy-2026-guide-927ad6144be4

   else if(StringFind(sym, "USD") >= 0 && StringFind(sym, "CAD") >= 0)
   {
      // USD/CAD: NY session (North American pair)
      enableNY = true;
   }
   else if(StringFind(sym, "USD") >= 0)
   {
      // Other USD pairs: NY primary, London secondary
      enableNY = true;
      enableLondonOpen = true;
   }

   // ===================================================================
   // METALS (Gold/Silver)
   // ===================================================================
   // Best: London-NY overlap (13:00-16:00 GMT)
   // Source: https://acy.com/en/market-news/education/best-time-trade-gold-xauusd-sessions-news-091755/

   else if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0 ||
           StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
   {
      // Metals: London + NY (peak volatility in overlap)
      enableLondonOpen = true;
      enableNY = true;
   }

   // ===================================================================
   // INDICES (US30, NAS100, SPX500, etc.)
   // ===================================================================
   // Best: NY session (8:30-11:00 AM NY / 13:30-16:00 GMT)
   // Source: https://tradingrage.com/learn/ict-killzone-explained

   else if(StringFind(sym, "US30") >= 0 || StringFind(sym, "US500") >= 0 ||
           StringFind(sym, "US100") >= 0 || StringFind(sym, "NAS") >= 0 ||
           StringFind(sym, "SPX") >= 0 || StringFind(sym, "DJ30") >= 0 ||
           StringFind(sym, "USTEC") >= 0)
   {
      // US Indices: NY session only
      enableNY = true;
   }
   else if(StringFind(sym, "DAX") >= 0 || StringFind(sym, "DE30") >= 0 ||
           StringFind(sym, "DE40") >= 0 || StringFind(sym, "UK100") >= 0 ||
           StringFind(sym, "FTSE") >= 0)
   {
      // European Indices: London session
      enableLondonOpen = true;
   }
   else if(StringFind(sym, "JP225") >= 0 || StringFind(sym, "NIKKEI") >= 0)
   {
      // Japanese Index: Asian session
      enableAsian = true;
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
         // Asian Session (01:00-03:00 GMT) - JPY, AUD, NZD pairs
         string asianList[] = {
            "USDJPY",    // Primary JPY
            "EURJPY",    // EUR/JPY cross
            "GBPJPY",    // GBP/JPY cross
            "AUDJPY",    // AUD/JPY cross
            "AUDUSD",    // Aussie
            "NZDUSD",    // Kiwi
            "AUDNZD"     // Regional
         };
         ArrayCopy(symbols, asianList);
         break;
      }

      case SESSION_LONDON:
      {
         // London Session (07:00-10:00 GMT) - EUR, GBP, CHF pairs
         string londonList[] = {
            "EURUSD",    // King of forex
            "GBPUSD",    // Cable
            "EURGBP",    // Pure European
            "EURJPY",    // Also active in London
            "GBPJPY",    // Also active in London
            "EURCHF",    // SNB influenced
            "GBPAUD",    // GBP cross
            "XAUUSD"     // Gold starts moving
         };
         ArrayCopy(symbols, londonList);
         break;
      }

      case SESSION_NY:
      {
         // NY Session (12:00-15:00 GMT) - USD, CAD pairs + Indices
         string nyList[] = {
            "EURUSD",    // Still active
            "GBPUSD",    // Still active
            "USDJPY",    // NY overlap
            "USDCAD",    // Loonie
            "USDCHF",    // Swissy
            "XAUUSD",    // Gold peak
            "XAGUSD",    // Silver
            "US30",      // Dow
            "US100",     // NASDAQ
            "US500"      // S&P
         };
         ArrayCopy(symbols, nyList);
         break;
      }

      case SESSION_LONDON_CLOSE:
      {
         // London Close (15:00-17:00 GMT) - Reduced activity
         string closeList[] = {
            "EURUSD",
            "GBPUSD",
            "XAUUSD"
         };
         ArrayCopy(symbols, closeList);
         break;
      }

      case SESSION_DEAD_ZONE:
      {
         // Dead zone - only most liquid pairs
         string deadList[] = {
            "EURUSD",    // Always liquid
            "USDJPY"     // Asian prep
         };
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
