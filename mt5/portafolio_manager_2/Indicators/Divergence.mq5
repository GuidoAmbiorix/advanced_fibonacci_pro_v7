//+------------------------------------------------------------------+
//|                                                 Divergence.mq5 |
//|          RSI Divergence Detector Indicator                        |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   0  // Data only

//--- Include Divergence module (using relative path)
#include "../Include/Advanced/Divergence.mqh"

//--- Input parameters
input int InpRSIPeriod = 14;                    // RSI Period
input int InpDivLookback = 10;                  // Divergence Lookback Bars

//--- Indicator buffers
double BufferBullishDiv[];       // Buffer 0: Bullish Divergence (0-1.0)
double BufferBearishDiv[];       // Buffer 1: Bearish Divergence (0-1.0)
double BufferCombinedScore[];    // Buffer 2: Combined Score (0-2.0)

//--- Module instance
CDivergence g_divergence;

//--- RSI handle
int g_hRSI = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferBullishDiv, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBearishDiv, INDICATOR_DATA);
   SetIndexBuffer(2, BufferCombinedScore, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferBullishDiv, true);
   ArraySetAsSeries(BufferBearishDiv, true);
   ArraySetAsSeries(BufferCombinedScore, true);

   //--- Create RSI handle
   g_hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   if(g_hRSI == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create RSI handle");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Divergence Detector");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   Print("Divergence indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hRSI != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   Print("Divergence indicator deinitialized");
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

   //--- Calculate divergence scores
   double bullishDiv = g_divergence.GetDivergenceScore(1, g_hRSI);
   double bearishDiv = g_divergence.GetDivergenceScore(-1, g_hRSI);

   //--- Store in buffers
   BufferBullishDiv[currentBar] = bullishDiv;
   BufferBearishDiv[currentBar] = bearishDiv;
   BufferCombinedScore[currentBar] = (bullishDiv > bearishDiv) ? bullishDiv : -bearishDiv;

   return rates_total;
}
//+------------------------------------------------------------------+
