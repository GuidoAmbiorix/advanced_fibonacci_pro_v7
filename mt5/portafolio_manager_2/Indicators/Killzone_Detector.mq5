//+------------------------------------------------------------------+
//|                                         Killzone_Detector.mq5 |
//|          ICT Killzone Detection Indicator                         |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   0  // Data only

//--- Include Killzone config (using relative path)
#include "../Include/KillzoneConfig.mqh"

//--- Input parameters
input int  InpBrokerUTCOffset = 2;              // Broker UTC Offset
input bool InpEnableAsianKZ = false;            // Enable Asian Killzone
input bool InpEnableLondonOpenKZ = true;        // Enable London Open Killzone
input bool InpEnableNYKZ = true;                // Enable NY Killzone
input bool InpEnableLondonCloseKZ = false;      // Enable London Close Killzone

//--- Indicator buffers
double BufferCurrentKZ[];        // Buffer 0: Current Killzone (0-4 enum)
double BufferIsActive[];         // Buffer 1: Killzone Active (0/1)
double BufferQuality[];          // Buffer 2: Killzone Quality (0-3)

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferCurrentKZ, INDICATOR_DATA);
   SetIndexBuffer(1, BufferIsActive, INDICATOR_DATA);
   SetIndexBuffer(2, BufferQuality, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferCurrentKZ, true);
   ArraySetAsSeries(BufferIsActive, true);
   ArraySetAsSeries(BufferQuality, true);

   IndicatorSetString(INDICATOR_SHORTNAME, "Killzone Detector");
   IndicatorSetInteger(INDICATOR_DIGITS, 0);

   Print("Killzone_Detector indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Killzone_Detector indicator deinitialized");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Calculate for current bar
   int currentBar = 0;

   //--- Get current killzone
   ENUM_KILLZONE kz = GetActiveKillzone();

   BufferCurrentKZ[currentBar] = (double)kz;
   BufferIsActive[currentBar] = (kz != KILLZONE_NONE) ? 1.0 : 0.0;

   //--- Calculate quality (NY and London Open are prime, others are lower quality)
   double quality = 0.0;
   switch(kz)
   {
      case KILLZONE_NY:
      case KILLZONE_LONDON_OPEN:
         quality = 3.0;  // Prime killzones
         break;
      case KILLZONE_LONDON_CLOSE:
         quality = 2.0;  // Good killzone
         break;
      case KILLZONE_ASIAN:
         quality = 1.0;  // Fair killzone
         break;
      default:
         quality = 0.0;  // No killzone
         break;
   }

   BufferQuality[currentBar] = quality;

   return rates_total;
}

//+------------------------------------------------------------------+
//| Get Active Killzone (extracted from EA logic)                    |
//+------------------------------------------------------------------+
ENUM_KILLZONE GetActiveKillzone()
{
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
