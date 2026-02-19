//+------------------------------------------------------------------+
//|                                           Session_Optimizer.mq5 |
//|          Session Quality Indicator for Metals Trading             |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   0  // Data only

//--- Include Session module (using relative path)
#include "../Include/SessionOptimizer.mqh"

//--- Input parameters
input int InpBrokerUTCOffset = 2;               // Broker UTC Offset

//--- Indicator buffers
double BufferCurrentSession[];   // Buffer 0: Current Session (0-5 enum)
double BufferQuality[];          // Buffer 1: Session Quality (0-3)
double BufferMetalsScore[];      // Buffer 2: Metals Score (0-3.0)

//--- Module instance
CSessionOptimizer g_sessionOpt;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferCurrentSession, INDICATOR_DATA);
   SetIndexBuffer(1, BufferQuality, INDICATOR_DATA);
   SetIndexBuffer(2, BufferMetalsScore, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferCurrentSession, true);
   ArraySetAsSeries(BufferQuality, true);
   ArraySetAsSeries(BufferMetalsScore, true);

   //--- Initialize Session Optimizer
   if(!g_sessionOpt.Init(_Symbol, InpBrokerUTCOffset))
   {
      Print("ERROR: Failed to initialize Session Optimizer");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Session Optimizer");
   IndicatorSetInteger(INDICATOR_DIGITS, 1);

   Print("Session_Optimizer indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_sessionOpt.Deinit();
   Print("Session_Optimizer indicator deinitialized");
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
   //--- Update session optimizer
   g_sessionOpt.Update();

   //--- Calculate for current bar
   int currentBar = 0;

   //--- Get session information
   BufferCurrentSession[currentBar] = (double)g_sessionOpt.GetCurrentSession();
   BufferQuality[currentBar] = (double)g_sessionOpt.GetSessionQuality();
   BufferMetalsScore[currentBar] = g_sessionOpt.GetMetalsConfluenceBonus();

   return rates_total;
}
//+------------------------------------------------------------------+
