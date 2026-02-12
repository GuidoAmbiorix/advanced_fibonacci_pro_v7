//+------------------------------------------------------------------+
//| KillzoneConfig.mqh - STUB FILE (Killzones Disabled)              |
//| Minimal definitions for backward compatibility                    |
//+------------------------------------------------------------------+
#property copyright "Guido"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Killzone Enumeration (DISABLED - For compatibility only)         |
//+------------------------------------------------------------------+
enum ENUM_KILLZONE
{
   KILLZONE_NONE = 0,
   KILLZONE_ASIAN = 1,
   KILLZONE_LONDON_OPEN = 2,
   KILLZONE_NY = 3,
   KILLZONE_LONDON_CLOSE = 4
};

//+------------------------------------------------------------------+
//| Convert Killzone to String                                        |
//+------------------------------------------------------------------+
string KillzoneToString(ENUM_KILLZONE kz)
{
   switch(kz)
   {
      case KILLZONE_ASIAN: return "ASIAN";
      case KILLZONE_LONDON_OPEN: return "LONDON_OPEN";
      case KILLZONE_NY: return "NY";
      case KILLZONE_LONDON_CLOSE: return "LONDON_CLOSE";
      default: return "NONE";
   }
}

//+------------------------------------------------------------------+
//| Convert String to Killzone                                        |
//+------------------------------------------------------------------+
ENUM_KILLZONE StringToKillzone(string str)
{
   if(str == "ASIAN") return KILLZONE_ASIAN;
   if(str == "LONDON_OPEN") return KILLZONE_LONDON_OPEN;
   if(str == "NY") return KILLZONE_NY;
   if(str == "LONDON_CLOSE") return KILLZONE_LONDON_CLOSE;
   return KILLZONE_NONE;
}
