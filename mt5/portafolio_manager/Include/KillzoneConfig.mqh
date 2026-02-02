//+------------------------------------------------------------------+
//|                                              KillzoneConfig.mqh  |
//|                          ICT Killzone Configuration              |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef KILLZONE_CONFIG_MQH
#define KILLZONE_CONFIG_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| ICT KILLZONES ENUM                                                |
//+------------------------------------------------------------------+
enum ENUM_KILLZONE
{
   KILLZONE_NONE = 0,           // No active killzone
   KILLZONE_ASIAN = 1,          // Asian Killzone (00:00-03:00 UTC EST)
   KILLZONE_LONDON_OPEN = 2,    // London Open Killzone (07:00-10:00 UTC EST)
   KILLZONE_NY = 3,             // NY Killzone - Forex (12:00-15:00 UTC EST)
   KILLZONE_LONDON_CLOSE = 4,   // London Close Killzone (16:00-19:00 UTC EST)
   KILLZONE_NY_INDICES = 5      // NY Killzone - Indices (13:30-16:00 UTC EST)
};

//+------------------------------------------------------------------+
//| KILLZONE QUALITY RATING                                           |
//+------------------------------------------------------------------+
enum ENUM_KILLZONE_QUALITY
{
   KZ_QUALITY_WEAK = 0,         // Weak killzone (off-hours, low volume)
   KZ_QUALITY_FAIR = 1,         // Fair killzone (Asian session)
   KZ_QUALITY_STRONG = 2,       // Strong killzone (single major session)
   KZ_QUALITY_PRIME = 3         // Prime killzone (overlap periods)
};

//+------------------------------------------------------------------+
//| KILLZONE TIME CONSTANTS (GMT+2 BASELINE - FundingPips Server)   |
//| Note: These are adjusted +1 hour during DST (March-November)     |
//| Server: FundingPips (fundingpips2-sim) - GMT+2 Winter / GMT+3 DST|
//+------------------------------------------------------------------+

// Asian Killzone (Tokyo/Hong Kong/Singapore)
// Real time: 01:00-05:00 UTC → 03:00-07:00 GMT+2 / 04:00-08:00 GMT+3
const int KZ_ASIAN_START_SRV = 3;      // 03:00 GMT+2 / 04:00 GMT+3
const int KZ_ASIAN_END_SRV = 7;        // 07:00 GMT+2 / 08:00 GMT+3

// London Open Killzone (Frankfurt/London open)
// Real time: 07:00-10:00 UTC → 09:00-12:00 GMT+2 / 10:00-13:00 GMT+3
const int KZ_LONDON_START_SRV = 9;     // 09:00 GMT+2 / 10:00 GMT+3
const int KZ_LONDON_END_SRV = 12;      // 12:00 GMT+2 / 13:00 GMT+3

// New York Killzone - Forex (US macro data + futures activity)
// Real time: 13:30-16:00 UTC → 15:30-18:00 GMT+2 / 16:30-19:00 GMT+3
const int KZ_NY_START_SRV = 15;        // 15:00 GMT+2 / 16:00 GMT+3 - hour component
const int KZ_NY_START_MINUTE = 30;     // 30 minutes past the hour (15:30)
const int KZ_NY_END_SRV = 18;          // 18:00 GMT+2 / 19:00 GMT+3

// London Close Killzone (London close/Fix)
// Real time: 15:00-17:00 UTC → 17:00-19:00 GMT+2 / 18:00-20:00 GMT+3
const int KZ_LONDON_CLOSE_START_SRV = 17;  // 17:00 GMT+2 / 18:00 GMT+3
const int KZ_LONDON_CLOSE_END_SRV = 19;    // 19:00 GMT+2 / 20:00 GMT+3

// New York Killzone - Indices (US Market open at 9:30 AM EST)
// Real time: 13:30-16:00 UTC → 15:30-18:00 GMT+2 / 16:30-19:00 GMT+3
const int KZ_NY_INDICES_START_SRV = 15;    // 15:00 GMT+2 - hour component
const int KZ_NY_INDICES_START_MINUTE = 30; // 30 minutes past the hour (15:30)
const int KZ_NY_INDICES_END_SRV = 18;      // 18:00 GMT+2 / 19:00 GMT+3

// DST Offset (for GMT+2/GMT+3 servers)
const int DST_OFFSET = 1;              // Add +1 hour during DST (GMT+2→GMT+3)

//+------------------------------------------------------------------+
//| KILLZONE OVERLAP DETECTION                                        |
//+------------------------------------------------------------------+
// Prime overlaps for highest quality trades (GMT+2 server times)
const int KZ_LONDON_NY_OVERLAP_START_SRV = 15;  // 15:30 GMT+2 (London+NY overlap)
const int KZ_LONDON_NY_OVERLAP_END_SRV = 18;    // 18:00 GMT+2
const int KZ_ASIAN_LONDON_OVERLAP_START_SRV = 9; // 09:00 GMT+2 (Asian+London)
const int KZ_ASIAN_LONDON_OVERLAP_END_SRV = 11;  // 11:00 GMT+2

//+------------------------------------------------------------------+
//| DST DETECTION HELPER                                              |
//| European DST: Last Sunday in March (01:00) to Last Sunday in Oct |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get last Sunday of a given month                                 |
//+------------------------------------------------------------------+
int GetLastSundayOfMonth(int year, int month)
{
   // Start from the last day of the month and work backwards
   int daysInMonth[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
   
   // Adjust February for leap year
   if(month == 2 && ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)))
      daysInMonth[1] = 29;
   
   int lastDay = daysInMonth[month - 1];
   
   // Find last Sunday by checking backwards from last day
   for(int day = lastDay; day >= 1; day--)
   {
      datetime testDate = StringToTime(IntegerToString(year) + "." +
                                       IntegerToString(month) + "." +
                                       IntegerToString(day) + " 00:00");
      MqlDateTime dt;
      TimeToStruct(testDate, dt);
      
      if(dt.day_of_week == 0)  // Sunday
         return day;
   }
   
   return lastDay;  // Fallback (should never happen)
}

//+------------------------------------------------------------------+
//| Check if currently in DST (European rules)                       |
//| DST Start: Last Sunday of March at 01:00 UTC                     |
//| DST End:   Last Sunday of October at 01:00 UTC                   |
//+------------------------------------------------------------------+
bool IsDST(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);

   // No DST in January, February, November, December
   if(dt.mon < 3 || dt.mon > 10) return false;

   // DST definitely active in April through September
   if(dt.mon > 3 && dt.mon < 10) return true;

   // March: DST starts last Sunday at 01:00 UTC
   if(dt.mon == 3)
   {
      int lastSunday = GetLastSundayOfMonth(dt.year, 3);
      if(dt.day > lastSunday) return true;
      if(dt.day < lastSunday) return false;
      // On the last Sunday, DST starts at 01:00 UTC
      return (dt.hour >= 1);
   }

   // October: DST ends last Sunday at 01:00 UTC
   if(dt.mon == 10)
   {
      int lastSunday = GetLastSundayOfMonth(dt.year, 10);
      if(dt.day > lastSunday) return false;
      if(dt.day < lastSunday) return true;
      // On the last Sunday, DST ends at 01:00 UTC
      return (dt.hour < 1);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get DST-adjusted killzone time                                    |
//+------------------------------------------------------------------+
int GetAdjustedKillzoneTime(int gmt2Time, bool isDST)
{
   if(isDST)
      return (gmt2Time + DST_OFFSET) % 24;  // Add 1 hour during DST (GMT+2→GMT+3)
   return gmt2Time;
}

//+------------------------------------------------------------------+
//| SYMBOL TYPE DETECTION                                             |
//+------------------------------------------------------------------+
enum ENUM_SYMBOL_TYPE
{
   SYMBOL_TYPE_FOREX_STANDARD = 0,    // Standard forex pairs
   SYMBOL_TYPE_FOREX_JPY = 1,         // JPY pairs (Asian-sensitive)
   SYMBOL_TYPE_FOREX_EUR_GBP = 2,     // EUR/GBP pairs (London-focused)
   SYMBOL_TYPE_METALS = 3,            // Gold, Silver
   SYMBOL_TYPE_INDICES_US = 4,        // US Indices (different hours)
   SYMBOL_TYPE_INDICES_EU = 5,        // EU Indices
   SYMBOL_TYPE_OTHER = 6              // Unclassified
};

//+------------------------------------------------------------------+
//| Detect symbol type for optimal killzone selection                |
//+------------------------------------------------------------------+
ENUM_SYMBOL_TYPE GetSymbolType(string symbol)
{
   string sym = symbol;
   StringToUpper(sym);

   // Metals
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0 ||
      StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
      return SYMBOL_TYPE_METALS;

   // US Indices
   if(StringFind(sym, "NAS") >= 0 || StringFind(sym, "US30") >= 0 ||
      StringFind(sym, "US100") >= 0 || StringFind(sym, "SP500") >= 0 ||
      StringFind(sym, "SPX") >= 0 || StringFind(sym, "USTEC") >= 0 ||
      StringFind(sym, "US500") >= 0 || StringFind(sym, "DOW") >= 0)
      return SYMBOL_TYPE_INDICES_US;

   // EU Indices
   if(StringFind(sym, "DAX") >= 0 || StringFind(sym, "FTSE") >= 0 ||
      StringFind(sym, "CAC") >= 0 || StringFind(sym, "STOXX") >= 0 ||
      StringFind(sym, "DE30") >= 0 || StringFind(sym, "UK100") >= 0)
      return SYMBOL_TYPE_INDICES_EU;

   // JPY pairs
   if(StringFind(sym, "JPY") >= 0)
      return SYMBOL_TYPE_FOREX_JPY;

   // EUR/GBP focused pairs
   if(StringFind(sym, "EUR") >= 0 || StringFind(sym, "GBP") >= 0)
      return SYMBOL_TYPE_FOREX_EUR_GBP;

   // Standard forex (USD pairs, etc.)
   if(StringFind(sym, "USD") >= 0 || StringFind(sym, "AUD") >= 0 ||
      StringFind(sym, "NZD") >= 0 || StringFind(sym, "CAD") >= 0 ||
      StringFind(sym, "CHF") >= 0)
      return SYMBOL_TYPE_FOREX_STANDARD;

   return SYMBOL_TYPE_OTHER;
}

//+------------------------------------------------------------------+
//| Get default killzones for symbol type                            |
//| Returns array of killzones that should be enabled by default     |
//+------------------------------------------------------------------+
void GetDefaultKillzonesForSymbol(string symbol, bool &enableAsian, bool &enableLondon,
                                  bool &enableNY, bool &enableLondonClose)
{
   ENUM_SYMBOL_TYPE symType = GetSymbolType(symbol);

   // Initialize all to false
   enableAsian = false;
   enableLondon = false;
   enableNY = false;
   enableLondonClose = false;

   switch(symType)
   {
      case SYMBOL_TYPE_FOREX_JPY:
         // JPY pairs: Asian + London + NY (all major sessions)
         enableAsian = true;
         enableLondon = true;
         enableNY = true;
         enableLondonClose = false;
         break;

      case SYMBOL_TYPE_FOREX_EUR_GBP:
         // EUR/GBP pairs: London Open + NY + London Close
         enableAsian = false;
         enableLondon = true;
         enableNY = true;
         enableLondonClose = true;
         break;

      case SYMBOL_TYPE_METALS:
         // Gold/Silver: London Open + NY + London Close (best liquidity)
         enableAsian = false;
         enableLondon = true;
         enableNY = true;
         enableLondonClose = true;
         break;

      case SYMBOL_TYPE_INDICES_US:
         // US Indices: NY Killzone only (13:30-16:00)
         enableAsian = false;
         enableLondon = false;
         enableNY = true;
         enableLondonClose = false;
         break;

      case SYMBOL_TYPE_INDICES_EU:
         // EU Indices: London Open primarily
         enableAsian = false;
         enableLondon = true;
         enableNY = false;
         enableLondonClose = false;
         break;

      case SYMBOL_TYPE_FOREX_STANDARD:
      case SYMBOL_TYPE_OTHER:
      default:
         // Default: London Open + NY
         enableAsian = false;
         enableLondon = true;
         enableNY = true;
         enableLondonClose = false;
         break;
   }
}

//+------------------------------------------------------------------+
//| Check if symbol is a US index (needs special timing)             |
//+------------------------------------------------------------------+
bool IsUSIndex(string symbol)
{
   return (GetSymbolType(symbol) == SYMBOL_TYPE_INDICES_US);
}

//+------------------------------------------------------------------+
//| Check if symbol is Forex pair                                    |
//+------------------------------------------------------------------+
bool IsForexPair(string symbol)
{
   ENUM_SYMBOL_TYPE type = GetSymbolType(symbol);
   return (type == SYMBOL_TYPE_FOREX_STANDARD ||
           type == SYMBOL_TYPE_FOREX_JPY ||
           type == SYMBOL_TYPE_FOREX_EUR_GBP);
}

//+------------------------------------------------------------------+
//| Get killzone name as string                                      |
//+------------------------------------------------------------------+
string KillzoneToString(ENUM_KILLZONE kz)
{
   switch(kz)
   {
      case KILLZONE_ASIAN:         return "ASIAN";
      case KILLZONE_LONDON_OPEN:   return "LONDON OPEN";
      case KILLZONE_NY:            return "NEW YORK";
      case KILLZONE_LONDON_CLOSE:  return "LONDON CLOSE";
      case KILLZONE_NY_INDICES:    return "NY INDICES";
      case KILLZONE_NONE:
      default:                     return "OFF HOURS";
   }
}

//+------------------------------------------------------------------+
//| Get quality name as string                                       |
//+------------------------------------------------------------------+
string QualityToString(ENUM_KILLZONE_QUALITY quality)
{
   switch(quality)
   {
      case KZ_QUALITY_PRIME:    return "PRIME";
      case KZ_QUALITY_STRONG:   return "STRONG";
      case KZ_QUALITY_FAIR:     return "FAIR";
      case KZ_QUALITY_WEAK:
      default:                  return "WEAK";
   }
}

#endif
