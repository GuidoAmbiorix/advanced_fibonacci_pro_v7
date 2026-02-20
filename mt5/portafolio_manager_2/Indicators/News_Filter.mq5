//+------------------------------------------------------------------+
//|                                              News_Filter.mq5 |
//|          News Event and Volatility Spike Detection Indicator      |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   0  // Data only

//--- Include News Filter module (using relative path)
#include "../Include/NewsFilter.mqh"

//--- Input parameters
input int  InpMinutesBefore = 30;               // Minutes Before News
input int  InpMinutesAfter = 30;                // Minutes After News
input bool InpEnableNewsFilter = true;          // Enable News Filter
input bool InpEnableVolatilityFilter = true;    // Enable Volatility Spike Detection
input double InpVolatilityThreshold = 3.0;      // Volatility Spike Threshold (ATR multiplier)
input int  InpSpikeCooldownMinutes = 15;        // Spike Cooldown Minutes

//--- Indicator buffers
double BufferNewsEvent[];        // Buffer 0: News Event Detected (0/1)
double BufferMinutesToNews[];    // Buffer 1: Minutes Until Next Event
double BufferRiskLevel[];        // Buffer 2: Risk Level (0-3: None/Low/Med/High)
double BufferVolatilitySpike[];  // Buffer 3: Volatility Spike Active (0/1)
double BufferTradingAllowed[];   // Buffer 4: Trading Allowed (0/1)

//--- Module instance
CNewsFilter g_newsFilter;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferNewsEvent, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMinutesToNews, INDICATOR_DATA);
   SetIndexBuffer(2, BufferRiskLevel, INDICATOR_DATA);
   SetIndexBuffer(3, BufferVolatilitySpike, INDICATOR_DATA);
   SetIndexBuffer(4, BufferTradingAllowed, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferNewsEvent, true);
   ArraySetAsSeries(BufferMinutesToNews, true);
   ArraySetAsSeries(BufferRiskLevel, true);
   ArraySetAsSeries(BufferVolatilitySpike, true);
   ArraySetAsSeries(BufferTradingAllowed, true);

   //--- Initialize News Filter
   if(!g_newsFilter.Init(_Symbol, InpMinutesBefore, InpMinutesAfter, InpEnableNewsFilter))
   {
      Print("ERROR: Failed to initialize News Filter");
      return INIT_FAILED;
   }

   // Configure volatility filter
   g_newsFilter.EnableVolatilityFilter(InpEnableVolatilityFilter);
   g_newsFilter.SetVolatilityThreshold(InpVolatilityThreshold);
   g_newsFilter.SetVolatilityCooldown(InpSpikeCooldownMinutes);

   IndicatorSetString(INDICATOR_SHORTNAME, "News Filter");
   IndicatorSetInteger(INDICATOR_DIGITS, 0);

   Print("News_Filter indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("News_Filter indicator deinitialized");
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
   //--- Update news filter
   g_newsFilter.Update();

   //--- Calculate for current bar
   int currentBar = 0;

   //--- Get news information
   BufferNewsEvent[currentBar] = g_newsFilter.IsInNewsWindow() ? 1.0 : 0.0;
   BufferMinutesToNews[currentBar] = (double)g_newsFilter.GetMinutesToNextNews();

   //--- Get next news event details
   datetime eventTime;
   string eventName;
   ENUM_NEWS_IMPACT impact;

   if(g_newsFilter.GetNextNewsEvent(eventTime, eventName, impact))
   {
      BufferRiskLevel[currentBar] = (double)impact;
   }
   else
   {
      BufferRiskLevel[currentBar] = 0.0;
   }

   //--- Volatility spike status
   BufferVolatilitySpike[currentBar] = g_newsFilter.IsInVolatilitySpike() ? 1.0 : 0.0;

   //--- Trading allowed status
   BufferTradingAllowed[currentBar] = g_newsFilter.IsTradingAllowed() ? 1.0 : 0.0;

   return rates_total;
}
//+------------------------------------------------------------------+
