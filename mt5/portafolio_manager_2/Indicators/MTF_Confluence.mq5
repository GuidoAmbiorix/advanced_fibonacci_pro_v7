//+------------------------------------------------------------------+
//|                                            MTF_Confluence.mq5 |
//|          Multi-Timeframe Confluence Indicator                     |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   0  // Data only

//--- Include MTF module (using relative path)
#include "../Include/MTF_Confluence.mqh"

//--- Input parameters
input ENUM_TIMEFRAMES InpHTF = PERIOD_H4;      // Higher Timeframe
input ENUM_TIMEFRAMES InpMTF = PERIOD_H1;      // Medium Timeframe
input ENUM_TIMEFRAMES InpLTF = PERIOD_M15;     // Lower Timeframe
input int InpEMAPeriod = 50;                    // EMA Period
input int InpRSIPeriod = 14;                    // RSI Period

//--- Indicator buffers
double BufferHTFBias[];          // Buffer 0: HTF Bias (-4 to +4)
double BufferMTFBias[];          // Buffer 1: MTF Bias (-4 to +4)
double BufferLTFBias[];          // Buffer 2: LTF Bias (-4 to +4)
double BufferAlignment[];        // Buffer 3: Alignment Score (0-100%)
double BufferBuyScore[];         // Buffer 4: Buy Score (0-2.0)
double BufferSellScore[];        // Buffer 5: Sell Score (0-2.0)

//--- MTF module instance
CMTFConfluence g_mtfAnalysis;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferHTFBias, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMTFBias, INDICATOR_DATA);
   SetIndexBuffer(2, BufferLTFBias, INDICATOR_DATA);
   SetIndexBuffer(3, BufferAlignment, INDICATOR_DATA);
   SetIndexBuffer(4, BufferBuyScore, INDICATOR_DATA);
   SetIndexBuffer(5, BufferSellScore, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferHTFBias, true);
   ArraySetAsSeries(BufferMTFBias, true);
   ArraySetAsSeries(BufferMTFBias, true);
   ArraySetAsSeries(BufferLTFBias, true);
   ArraySetAsSeries(BufferAlignment, true);
   ArraySetAsSeries(BufferBuyScore, true);
   ArraySetAsSeries(BufferSellScore, true);

   //--- Initialize MTF module
   if(!g_mtfAnalysis.Init(_Symbol, InpHTF, InpMTF, InpLTF, InpEMAPeriod, InpRSIPeriod))
   {
      Print("ERROR: Failed to initialize MTF module");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "MTF Confluence");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   Print("MTF_Confluence indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_mtfAnalysis.Deinit();
   Print("MTF_Confluence indicator deinitialized");
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
   //--- Update MTF analysis
   g_mtfAnalysis.Update();

   //--- Calculate for current bar
   int currentBar = 0;

   //--- Get bias values (simplified representation)
   BufferHTFBias[currentBar] = g_mtfAnalysis.GetHTFBias();
   BufferMTFBias[currentBar] = g_mtfAnalysis.GetMTFBias();
   BufferLTFBias[currentBar] = g_mtfAnalysis.GetLTFBias();
   BufferAlignment[currentBar] = g_mtfAnalysis.GetAlignmentScore();

   //--- Calculate scores
   BufferBuyScore[currentBar] = g_mtfAnalysis.GetConfluenceScore(1);
   BufferSellScore[currentBar] = g_mtfAnalysis.GetConfluenceScore(-1);

   return rates_total;
}
//+------------------------------------------------------------------+
