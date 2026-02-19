//+------------------------------------------------------------------+
//|                                              ICT_Advanced.mq5 |
//|          ICT Advanced Concepts Indicator                          |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   0  // Data only

//--- Include ICT modules (using relative path)
#include "../Include/Advanced/Inst_Concepts.mqh"

//--- Indicator buffers
double BufferBreakerScore[];     // Buffer 0: Breaker Block Score (0-1.0)
double BufferPowerOf3Score[];    // Buffer 1: Power of 3 Score (0-1.0)
double BufferMacroActive[];      // Buffer 2: Macro Window Active (0/1)
double BufferCombinedScore[];    // Buffer 3: Combined Score (0-6.0)

//--- Module instances
CBreakerBlocks  g_breakerBlocks;
CPowerOf3       g_powerOf3;
CMacroWindows   g_macroWindows;
CWyckoff        g_wyckoff;

//--- ATR handle
int g_hATR = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferBreakerScore, INDICATOR_DATA);
   SetIndexBuffer(1, BufferPowerOf3Score, INDICATOR_DATA);
   SetIndexBuffer(2, BufferMacroActive, INDICATOR_DATA);
   SetIndexBuffer(3, BufferCombinedScore, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferBreakerScore, true);
   ArraySetAsSeries(BufferPowerOf3Score, true);
   ArraySetAsSeries(BufferMacroActive, true);
   ArraySetAsSeries(BufferCombinedScore, true);

   //--- Create ATR handle
   g_hATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(g_hATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR handle");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "ICT Advanced");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   Print("ICT_Advanced indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   Print("ICT_Advanced indicator deinitialized");
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
   //--- Get ATR value
   double atrBuf[1];
   if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf) <= 0) return 0;
   double atr = atrBuf[0];

   //--- Calculate for current bar
   int currentBar = 0;

   //--- Calculate individual scores (directional - positive for bullish, negative for bearish)
   double breakerBuy = g_breakerBlocks.GetBreakerScore(1, atr);
   double breakerSell = g_breakerBlocks.GetBreakerScore(-1, atr);
   double breakerScore = breakerBuy - breakerSell;  // Net score

   double powerOf3Score = g_powerOf3.GetPhaseScore(atr);
   double macroScore = g_macroWindows.GetMacroScore();
   double wyckoffBuy = g_wyckoff.GetWyckoffScore(1, atr);
   double wyckoffSell = g_wyckoff.GetWyckoffScore(-1, atr);
   double wyckoffScore = wyckoffBuy - wyckoffSell;  // Net score

   //--- Store in buffers
   BufferBreakerScore[currentBar] = breakerScore;
   BufferPowerOf3Score[currentBar] = powerOf3Score;
   BufferMacroActive[currentBar] = (macroScore > 0) ? 1.0 : 0.0;

   //--- Combined score (positive for bullish bias, negative for bearish)
   BufferCombinedScore[currentBar] = (breakerScore * 3.0) + (powerOf3Score * 3.0) + (wyckoffScore * 2.0);

   return rates_total;
}
//+------------------------------------------------------------------+
