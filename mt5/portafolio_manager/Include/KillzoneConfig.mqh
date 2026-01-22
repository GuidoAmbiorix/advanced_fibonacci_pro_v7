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
//| KILLZONE TIME CONSTANTS (EST BASELINE)                           |
//| Note: These are adjusted -1 hour during EDT (March-November)     |
//+------------------------------------------------------------------+

// Asian Killzone (Tokyo/Hong Kong/Singapore)
const int KZ_ASIAN_START_EST = 0;      // 00:00 UTC (EST) / 23:00 UTC (EDT)
const int KZ_ASIAN_END_EST = 3;        // 03:00 UTC (EST) / 02:00 UTC (EDT)

// London Open Killzone (Frankfurt/London open)
const int KZ_LONDON_START_EST = 7;     // 07:00 UTC (EST) / 06:00 UTC (EDT)
const int KZ_LONDON_END_EST = 10;      // 10:00 UTC (EST) / 09:00 UTC (EDT)

// New York Killzone - Forex (NY open)
const int KZ_NY_START_EST = 12;        // 12:00 UTC (EST) / 11:00 UTC (EDT)
const int KZ_NY_END_EST = 15;          // 15:00 UTC (EST) / 14:00 UTC (EDT)

// London Close Killzone (London close/Fix)
const int KZ_LONDON_CLOSE_START_EST = 16;  // 16:00 UTC (EST) / 15:00 UTC (EDT)
const int KZ_LONDON_CLOSE_END_EST = 19;    // 19:00 UTC (EST) / 18:00 UTC (EDT)

// New York Killzone - Indices (US Market open at 9:30 AM EST)
const int KZ_NY_INDICES_START_EST = 13;    // 13:00 UTC (EST) - hour component
const int KZ_NY_INDICES_START_MINUTE = 30; // 30 minutes past the hour
const int KZ_NY_INDICES_END_EST = 16;      // 16:00 UTC (EST) / 15:00 UTC (EDT)

// DST Offset
const int DST_OFFSET = 1;              // Subtract 1 hour during EDT

//+------------------------------------------------------------------+
//| KILLZONE OVERLAP DETECTION                                        |
//+------------------------------------------------------------------+
// Prime overlaps for highest quality trades
const int KZ_LONDON_NY_OVERLAP_START_EST = 12;  // 12:00 UTC (London+NY)
const int KZ_LONDON_NY_OVERLAP_END_EST = 16;    // 16:00 UTC
const int KZ_ASIAN_LONDON_OVERLAP_START_EST = 7; // 07:00 UTC (Asian+London)
const int KZ_ASIAN_LONDON_OVERLAP_END_EST = 9;   // 09:00 UTC

//+------------------------------------------------------------------+
//| DST DETECTION HELPER                                              |
//| US DST: 2nd Sunday in March to 1st Sunday in November            |
//+------------------------------------------------------------------+
int GetNthDayOfWeekInMonth(int year, int month, int dayOfWeek, int nth)
{
   // Find the nth occurrence of dayOfWeek in the given month
   // dayOfWeek: 0=Sunday, 1=Monday, etc.
   datetime firstDay = StringToTime(IntegerToString(year) + "." +
                                     IntegerToString(month) + ".01 00:00");
   MqlDateTime dt;
   TimeToStruct(firstDay, dt);

   int firstWeekday = dt.day_of_week;
   int daysToAdd = (dayOfWeek - firstWeekday + 7) % 7;
   int targetDay = 1 + daysToAdd + (nth - 1) * 7;

   return targetDay;
}

//+------------------------------------------------------------------+
//| Check if currently in DST (Daylight Saving Time)                 |
//+------------------------------------------------------------------+
bool IsDST(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);

   // No DST in January, February, December
   if(dt.mon < 3 || dt.mon > 11) return false;

   // DST active in April through October
   if(dt.mon > 3 && dt.mon < 11) return true;

   // March: DST starts 2nd Sunday at 2:00 AM
   if(dt.mon == 3)
   {
      int secondSunday = GetNthDayOfWeekInMonth(dt.year, 3, 0, 2);
      if(dt.day > secondSunday) return true;
      if(dt.day < secondSunday) return false;
      // On the 2nd Sunday, DST starts at 2:00 AM
      return (dt.hour >= 2);
   }

   // November: DST ends 1st Sunday at 2:00 AM
   if(dt.mon == 11)
   {
      int firstSunday = GetNthDayOfWeekInMonth(dt.year, 11, 0, 1);
      if(dt.day > firstSunday) return false;
      if(dt.day < firstSunday) return true;
      // On the 1st Sunday, DST ends at 2:00 AM
      return (dt.hour < 2);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get DST-adjusted killzone time                                    |
//+------------------------------------------------------------------+
int GetAdjustedKillzoneTime(int estTime, bool isDST)
{
   if(isDST)
      return (estTime - DST_OFFSET + 24) % 24;  // Shift 1 hour earlier during EDT
   return estTime;
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
