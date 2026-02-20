//+------------------------------------------------------------------+
//|                                              Market_Regime.mq5 |
//|          Market Regime Detection Indicator                        |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   0  // Data only

//--- Include Market Regime module (using relative path)
#include "../Include/MarketRegime.mqh"

//--- Input parameters
input int InpATRPeriod = 14;                    // ATR Period
input int InpEMAPeriod = 50;                    // EMA Period for Regime Detection

//--- Indicator buffers
double BufferRegime[];           // Buffer 0: Current Regime (0-3 enum)
double BufferStrength[];         // Buffer 1: Regime Strength (0-100%)
double BufferVolatilityRank[];   // Buffer 2: Volatility Rank (0-10)
double BufferTrendStrength[];    // Buffer 3: Trend Strength (0-100%)

//--- Module instance
CMarketRegime g_marketRegime;

//--- Indicator handles
int g_hATR = INVALID_HANDLE;
int g_hEMA = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferRegime, INDICATOR_DATA);
   SetIndexBuffer(1, BufferStrength, INDICATOR_DATA);
   SetIndexBuffer(2, BufferVolatilityRank, INDICATOR_DATA);
   SetIndexBuffer(3, BufferTrendStrength, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferRegime, true);
   ArraySetAsSeries(BufferStrength, true);
   ArraySetAsSeries(BufferVolatilityRank, true);
   ArraySetAsSeries(BufferTrendStrength, true);

   //--- Create indicator handles
   g_hATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   g_hEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(g_hATR == INVALID_HANDLE || g_hEMA == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Market Regime");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   Print("Market_Regime indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hEMA != INVALID_HANDLE) IndicatorRelease(g_hEMA);
   Print("Market_Regime indicator deinitialized");
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
   //--- Get ATR values
   double atrBuf[2];
   if(CopyBuffer(g_hATR, 0, 0, 2, atrBuf) <= 0) return 0;

   double currentATR = atrBuf[0];

   // Calculate average ATR (simple average of last 14 bars)
   double atrAvgBuf[14];
   if(CopyBuffer(g_hATR, 0, 0, 14, atrAvgBuf) <= 0) return 0;

   double avgATR = 0.0;
   for(int i = 0; i < 14; i++)
      avgATR += atrAvgBuf[i];
   avgATR /= 14.0;

   //--- Get EMA values
   double emaBuf[2];
   if(CopyBuffer(g_hEMA, 0, 0, 2, emaBuf) <= 0) return 0;

   double currentEMA = emaBuf[0];
   double prevEMA = emaBuf[1];

   //--- Calculate for current bar
   int currentBar = 0;

   //--- Detect regime
   MARKET_REGIME regime = g_marketRegime.Detect(currentATR, avgATR, currentEMA, prevEMA);
   BufferRegime[currentBar] = (double)regime;

   //--- Calculate regime strength (0-100%)
   double strength = 50.0;  // Default medium strength

   if(regime == REGIME_TREND)
   {
      double emaSlope = MathAbs(currentEMA - prevEMA);
      strength = MathMin(100.0, (emaSlope / avgATR) * 100.0);
   }
   else if(regime == REGIME_RANGE)
   {
      double atrRatio = (avgATR > 0) ? currentATR / avgATR : 1.0;
      strength = (1.0 - atrRatio) * 100.0;
      if(strength < 0) strength = 0;
   }
   else if(regime == REGIME_CHAOS)
   {
      double atrRatio = (avgATR > 0) ? currentATR / avgATR : 1.0;
      strength = MathMin(100.0, (atrRatio - 1.0) * 50.0);
   }

   BufferStrength[currentBar] = strength;

   //--- Calculate volatility rank (0-10 scale)
   double atrRatio = (avgATR > 0) ? currentATR / avgATR : 1.0;
   double volRank = atrRatio * 5.0;  // 1.0 ratio = 5.0 rank (medium)
   if(volRank > 10.0) volRank = 10.0;
   if(volRank < 0) volRank = 0;

   BufferVolatilityRank[currentBar] = volRank;

   //--- Calculate trend strength (0-100%)
   double emaSlope = MathAbs(currentEMA - prevEMA);
   double trendStrength = MathMin(100.0, (emaSlope / avgATR) * 100.0);
   BufferTrendStrength[currentBar] = trendStrength;

   return rates_total;
}
//+------------------------------------------------------------------+
