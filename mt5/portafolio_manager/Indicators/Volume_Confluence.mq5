//+------------------------------------------------------------------+
//|                                          Volume_Confluence.mq5 |
//|          Volume Analysis - Consolidated Volume Indicator         |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   0  // Data only, no visual plots

//--- Include Volume Analysis module (using relative path)
#include "../Include/Advanced/VolumeAnalysis.mqh"

//--- Input parameters
input int InpRVOL_Lookback = 20;              // RVOL Lookback Days
input int InpMF_Period = 5;                   // Money Flow Period

//--- Indicator buffers
double BufferRVOL[];           // Buffer 0: RVOL Value (ratio)
double BufferMoneyFlow[];      // Buffer 1: Money Flow Index (-1 to +1)
double BufferBuyScore[];       // Buffer 2: Buy Score (0-4.0)
double BufferSellScore[];      // Buffer 3: Sell Score (0-4.0)

//--- Volume analysis instance
CVolumeAnalysis g_volumeAnalysis;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferRVOL, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMoneyFlow, INDICATOR_DATA);
   SetIndexBuffer(2, BufferBuyScore, INDICATOR_DATA);
   SetIndexBuffer(3, BufferSellScore, INDICATOR_DATA);

   //--- Set buffer labels
   PlotIndexSetString(0, PLOT_LABEL, "RVOL");
   PlotIndexSetString(1, PLOT_LABEL, "Money Flow");
   PlotIndexSetString(2, PLOT_LABEL, "Volume Buy Score");
   PlotIndexSetString(3, PLOT_LABEL, "Volume Sell Score");

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferRVOL, true);
   ArraySetAsSeries(BufferMoneyFlow, true);
   ArraySetAsSeries(BufferBuyScore, true);
   ArraySetAsSeries(BufferSellScore, true);

   //--- Set indicator short name
   IndicatorSetString(INDICATOR_SHORTNAME, "Volume Confluence");

   //--- Set indicator digits
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   Print("Volume_Confluence indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Volume_Confluence indicator deinitialized");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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

   //--- Calculate RVOL
   double rvol = CalculateRVOL(InpRVOL_Lookback);
   BufferRVOL[currentBar] = rvol;

   //--- Calculate Money Flow
   double moneyFlow = CalculateRapidMoneyFlow(InpMF_Period);
   BufferMoneyFlow[currentBar] = moneyFlow;

   //--- Calculate scores
   double buyScore = g_volumeAnalysis.GetConfluenceScore(1);
   double sellScore = g_volumeAnalysis.GetConfluenceScore(-1);

   BufferBuyScore[currentBar] = buyScore;
   BufferSellScore[currentBar] = sellScore;

   //--- Return value of prev_calculated for next call
   return rates_total;
}

//+------------------------------------------------------------------+
//| Calculate Relative Volume (Time-Segmented)                       |
//+------------------------------------------------------------------+
double CalculateRVOL(int lookbackDays)
{
   long currentVol = iVolume(_Symbol, PERIOD_CURRENT, 0);
   if(currentVol <= 0) return 1.0;

   long volumeSum = 0;
   int count = 0;

   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   // Loop back 'lookbackDays' to find same time of day
   for(int i = 1; i <= lookbackDays; i++)
   {
      datetime pastTime = currentTime - (i * PeriodSeconds(PERIOD_D1));

      // Find closest bar to that time
      int shift = iBarShift(_Symbol, PERIOD_CURRENT, pastTime, false);

      if(shift > 0)
      {
         volumeSum += iVolume(_Symbol, PERIOD_CURRENT, shift);
         count++;
      }
   }

   double avgVol = (count > 0) ? (double)volumeSum / count : currentVol;
   if(avgVol == 0) return 1.0;

   return (double)currentVol / avgVol;
}

//+------------------------------------------------------------------+
//| Calculate Rapid Money Flow (Simplified CMF)                      |
//+------------------------------------------------------------------+
double CalculateRapidMoneyFlow(int lookback)
{
   double flowSum = 0;
   double volSum = 0;

   for(int i = 0; i < lookback; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      long vol = iVolume(_Symbol, PERIOD_CURRENT, i);

      if(high == low) continue;

      // Multiplier: ((Close - Low) - (High - Close)) / (High - Low)
      // 1 = Closed at High (Max Buying)
      // -1 = Closed at Low (Max Selling)
      double mult = ((close - low) - (high - close)) / (high - low);

      flowSum += mult * (double)vol;
      volSum += (double)vol;
   }

   return (volSum > 0) ? flowSum / volSum : 0;
}
//+------------------------------------------------------------------+
