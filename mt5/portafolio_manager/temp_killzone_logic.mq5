
//+------------------------------------------------------------------+
//| Get Active Killzone                                               |
//+------------------------------------------------------------------+
ENUM_KILLZONE GetActiveKillzone()
{
   if(!InpUseKillzoneFilter) return KILLZONE_NONE;

   datetime utcTime = TimeCurrent() - (InpBrokerUTCOffset * 3600);
   MqlDateTime utcDt;
   TimeToStruct(utcTime, utcDt);

   // EST Calculation (Standard UTC-5)
   int estHour = (utcDt.hour - 5 + 24) % 24;

   // 1. Asian Session (20:00 - 00:00 EST)
   if(InpEnableAsianKZ && (estHour >= 20 || estHour < 0)) return KILLZONE_ASIAN;

   // 2. London Open (02:00 - 05:00 EST)
   if(InpEnableLondonOpenKZ && (estHour >= 2 && estHour < 5)) return KILLZONE_LONDON_OPEN;

   // 3. NY Open (07:00 - 10:00 EST)
   if(InpEnableNYKZ && (estHour >= 7 && estHour < 10)) return KILLZONE_NY;

   // 4. London Close (10:00 - 12:00 EST)
   if(InpEnableLondonCloseKZ && (estHour >= 10 && estHour < 12)) return KILLZONE_LONDON_CLOSE;

   return KILLZONE_NONE;
}

//+------------------------------------------------------------------+
//| Check Killzone Time (Wrapper)                                     |
//+------------------------------------------------------------------+
bool CheckKillzone()
{
   return GetActiveKillzone() != KILLZONE_NONE;
}
