//+------------------------------------------------------------------+
//|                                      Market_Phase_Analyzer.mq5 |
//|          Advanced Market Regime Detection Indicator              |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 12
#property indicator_plots 4

//+------------------------------------------------------------------+
//| Market Phase Enumeration                                          |
//+------------------------------------------------------------------+
enum MARKET_PHASE {
   PHASE_DORMANT = 0,       // Volume < MinVolume, skip trading
   PHASE_TRENDING = 1,      // ADX > 25 + Positive Autocorrelation
   PHASE_RANGING = 2,       // ADX < 20 + Price in Fib 0-100% box
   PHASE_VOLATILE = 3,      // BBW expansion + Price breaking Fib levels
   PHASE_UNDEFINED = 4      // Transition state
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int    InpLookbackPeriod = 50;         // Autocorrelation Window
input double InpTrendThreshold = 0.2;        // Autocorrelation Threshold
input int    InpADXPeriod = 14;              // ADX Period
input double InpADXTrendLevel = 25.0;        // ADX Trend Threshold
input double InpADXRangeLevel = 20.0;        // ADX Range Threshold
input int    InpBBPeriod = 20;               // Bollinger Period
input double InpBBDeviation = 2.0;           // Bollinger Std Deviation
input double InpBBExpansionPercentile = 90;  // BBW Expansion Percentile
input double InpMinVolume = 100;             // Min Volume (Dormant Filter)
input int    InpSwingLookback = 50;          // Bars for Fib Swing Detection

//+------------------------------------------------------------------+
//| Indicator Buffers                                                 |
//+------------------------------------------------------------------+
// EA-Accessible Buffers (INDICATOR_DATA)
double BufferMarketPhase[];         // Buffer 0: Market Phase (0-4 enum)
double BufferTrendStrength[];       // Buffer 1: Trend Strength (0-100%)
double BufferVolatilityState[];     // Buffer 2: Volatility State (0-100%)
double BufferADXValue[];            // Buffer 3: ADX Value (0-100)
double BufferFibStructure[];        // Buffer 4: Fib Structure (-1 to +1)
double BufferPriceLocationInSwing[];// Buffer 5: Price Location (0-100%)
double BufferRecommendedStrategy[]; // Buffer 6: Recommended Strategy (0-2)
double BufferConfluenceMultiplier[];// Buffer 7: Confluence Adjustment (0.5-1.5)

// Internal Calculation Buffers (INDICATOR_CALCULATIONS)
double BufferReturns[];             // Buffer 8: Price returns
double BufferAutocorrelation[];     // Buffer 9: Lag-1 autocorr
double BufferBBW[];                 // Buffer 10: Bollinger Bandwidth
double BufferSwingRange[];          // Buffer 11: Current swing range

//+------------------------------------------------------------------+
//| Indicator Handles                                                 |
//+------------------------------------------------------------------+
int g_hADX = INVALID_HANDLE;
int g_hBands = INVALID_HANDLE;
int g_hATR = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferMarketPhase, INDICATOR_DATA);
   SetIndexBuffer(1, BufferTrendStrength, INDICATOR_DATA);
   SetIndexBuffer(2, BufferVolatilityState, INDICATOR_DATA);
   SetIndexBuffer(3, BufferADXValue, INDICATOR_DATA);
   SetIndexBuffer(4, BufferFibStructure, INDICATOR_DATA);
   SetIndexBuffer(5, BufferPriceLocationInSwing, INDICATOR_DATA);
   SetIndexBuffer(6, BufferRecommendedStrategy, INDICATOR_DATA);
   SetIndexBuffer(7, BufferConfluenceMultiplier, INDICATOR_DATA);

   SetIndexBuffer(8, BufferReturns, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, BufferAutocorrelation, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, BufferBBW, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, BufferSwingRange, INDICATOR_CALCULATIONS);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferMarketPhase, true);
   ArraySetAsSeries(BufferTrendStrength, true);
   ArraySetAsSeries(BufferVolatilityState, true);
   ArraySetAsSeries(BufferADXValue, true);
   ArraySetAsSeries(BufferFibStructure, true);
   ArraySetAsSeries(BufferPriceLocationInSwing, true);
   ArraySetAsSeries(BufferRecommendedStrategy, true);
   ArraySetAsSeries(BufferConfluenceMultiplier, true);
   ArraySetAsSeries(BufferReturns, true);
   ArraySetAsSeries(BufferAutocorrelation, true);
   ArraySetAsSeries(BufferBBW, true);
   ArraySetAsSeries(BufferSwingRange, true);

   //--- Create indicator handles
   g_hADX = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   g_hBands = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   g_hATR = iATR(_Symbol, PERIOD_CURRENT, 14);

   if(g_hADX == INVALID_HANDLE || g_hBands == INVALID_HANDLE || g_hATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   //--- Indicator settings
   IndicatorSetString(INDICATOR_SHORTNAME, "Market Phase Analyzer");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   //--- Plot settings
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, STYLE_SOLID);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetString(0, PLOT_LABEL, "Phase");

   Print("Market_Phase_Analyzer indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hADX != INVALID_HANDLE) IndicatorRelease(g_hADX);
   if(g_hBands != INVALID_HANDLE) IndicatorRelease(g_hBands);
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   Print("Market_Phase_Analyzer indicator deinitialized");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                        |
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
   //--- Check for minimum bars
   if(rates_total < InpLookbackPeriod + 10) return 0;

   //--- Set arrays as series
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(tick_volume, true);

   //--- Calculate for current bar
   int currentBar = 0;

   //--- 1. Calculate Returns
   double returns[50];
   ArrayInitialize(returns, 0);
   for(int i = 0; i < InpLookbackPeriod - 1; i++)
   {
      if(close[i+1] != 0)
         returns[i] = (close[i] - close[i+1]) / close[i+1];
   }
   BufferReturns[currentBar] = returns[0];

   //--- 2. Calculate Lag-1 Autocorrelation
   double autocorr = CalculateAutocorrelation(returns, InpLookbackPeriod - 1);
   BufferAutocorrelation[currentBar] = autocorr;

   //--- 3. Get ADX Value
   double adxBuf[1];
   if(CopyBuffer(g_hADX, 0, 0, 1, adxBuf) <= 0) return 0;
   double adx = adxBuf[0];
   BufferADXValue[currentBar] = adx;

   //--- 4. Calculate Bollinger Bandwidth
   double upperBuf[1], lowerBuf[1], middleBuf[1];
   if(CopyBuffer(g_hBands, 1, 0, 1, upperBuf) <= 0) return 0;
   if(CopyBuffer(g_hBands, 2, 0, 1, lowerBuf) <= 0) return 0;
   if(CopyBuffer(g_hBands, 0, 0, 1, middleBuf) <= 0) return 0;

   double bbw = 0;
   if(middleBuf[0] != 0)
      bbw = (upperBuf[0] - lowerBuf[0]) / middleBuf[0];
   BufferBBW[currentBar] = bbw;

   //--- 5. Calculate BBW Percentile
   double bbwPercentile = CalculateBBWPercentile(bbw);
   BufferVolatilityState[currentBar] = bbwPercentile;

   //--- 6. Calculate Fibonacci Structure
   double swingHigh = high[ArrayMaximum(high, 0, InpSwingLookback)];
   double swingLow = low[ArrayMinimum(low, 0, InpSwingLookback)];
   double swingRange = swingHigh - swingLow;
   BufferSwingRange[currentBar] = swingRange;

   double priceLocation = 0;
   if(swingRange > 0)
      priceLocation = (close[currentBar] - swingLow) / swingRange * 100.0;
   BufferPriceLocationInSwing[currentBar] = priceLocation;

   // Fib structure: +1 (bullish), 0 (neutral), -1 (bearish)
   double fibStructure = 0;
   if(priceLocation > 60) fibStructure = 1.0;
   else if(priceLocation < 40) fibStructure = -1.0;
   BufferFibStructure[currentBar] = fibStructure;

   //--- 7. Detect Market Phase (Hierarchical)
   MARKET_PHASE phase = DetectPhase(tick_volume[currentBar], bbwPercentile, adx, autocorr, priceLocation);
   BufferMarketPhase[currentBar] = (double)phase;

   //--- DEBUG: Log phase calculations every 30 minutes
   static datetime lastDebugLog = 0;
   static MARKET_PHASE lastLoggedPhase = PHASE_UNDEFINED;

   if(TimeCurrent() - lastDebugLog > 1800 || phase != lastLoggedPhase)  // Every 30 min or on phase change
   {
      string phaseNames[] = {"DORMANT", "TRENDING", "RANGING", "VOLATILE", "UNDEFINED"};
      Print("=== MARKET PHASE ANALYSIS ===");
      Print("  Phase: ", phaseNames[phase]);
      Print("  Volume: ", tick_volume[currentBar], " (Min: ", InpMinVolume, ")");
      Print("  ADX: ", DoubleToString(adx, 1), " (Trend>", InpADXTrendLevel, ", Range<", InpADXRangeLevel, ")");
      Print("  Autocorr: ", DoubleToString(autocorr, 3), " (Threshold: ", InpTrendThreshold, ")");
      Print("  BBW%: ", DoubleToString(bbwPercentile, 1), " (Volatile>", InpBBExpansionPercentile, ")");
      Print("  Price Location: ", DoubleToString(priceLocation, 1), "%");
      Print("=============================");

      lastDebugLog = TimeCurrent();
      lastLoggedPhase = phase;
   }

   //--- 8. Calculate Trend Strength (Normalized Autocorrelation)
   double trendStrength = MathMin(100.0, MathAbs(autocorr) / InpTrendThreshold * 100.0);
   BufferTrendStrength[currentBar] = trendStrength;

   //--- 9. Recommend Strategy Based on Phase
   int recommendedStrategy = GetRecommendedStrategy(phase);
   BufferRecommendedStrategy[currentBar] = (double)recommendedStrategy;

   //--- 10. Calculate Confluence Multiplier
   double confluenceMultiplier = GetConfluenceMultiplier(phase);
   BufferConfluenceMultiplier[currentBar] = confluenceMultiplier;

   return rates_total;
}

//+------------------------------------------------------------------+
//| Calculate Lag-1 Autocorrelation                                   |
//+------------------------------------------------------------------+
double CalculateAutocorrelation(double &returns[], int size)
{
   if(size < 2) return 0.0;

   // Calculate mean
   double mean = 0;
   for(int i = 0; i < size; i++)
      mean += returns[i];
   mean /= size;

   // Calculate variance and covariance
   double variance = 0;
   double covariance = 0;

   for(int i = 0; i < size - 1; i++)
   {
      double dev1 = returns[i] - mean;
      double dev2 = returns[i+1] - mean;
      variance += dev1 * dev1;
      covariance += dev1 * dev2;
   }

   // Last term for variance
   double devLast = returns[size-1] - mean;
   variance += devLast * devLast;

   if(variance == 0) return 0.0;

   return covariance / variance;
}

//+------------------------------------------------------------------+
//| Calculate BBW Percentile (Historical Ranking)                     |
//+------------------------------------------------------------------+
double CalculateBBWPercentile(double currentBBW)
{
   // Get historical BBW values
   double historicalBBW[100];
   ArrayInitialize(historicalBBW, 0);

   int copied = CopyBuffer(g_hBands, 1, 1, 100, historicalBBW);  // Upper band
   if(copied <= 0) return 50.0;  // Default to median

   // Calculate BBW for historical bars
   double lowerBuf[100], middleBuf[100];
   CopyBuffer(g_hBands, 2, 1, 100, lowerBuf);
   CopyBuffer(g_hBands, 0, 1, 100, middleBuf);

   int count = 0;
   for(int i = 0; i < copied; i++)
   {
      if(middleBuf[i] != 0)
      {
         double bbw = (historicalBBW[i] - lowerBuf[i]) / middleBuf[i];
         if(bbw < currentBBW) count++;
      }
   }

   return (double)count / copied * 100.0;
}

//+------------------------------------------------------------------+
//| Detect Market Phase (Hierarchical Classification)                 |
//+------------------------------------------------------------------+
MARKET_PHASE DetectPhase(long currentVolume, double bbwPercentile, double adx,
                        double autocorr, double priceLocation)
{
   // Priority 1: Check Dormancy (Volume Filter)
   if(currentVolume < InpMinVolume)
      return PHASE_DORMANT;

   // Priority 2: Check Volatility Expansion
   if(bbwPercentile > InpBBExpansionPercentile)
      return PHASE_VOLATILE;

   // Priority 3: Check Trend Strength
   if(adx > InpADXTrendLevel && MathAbs(autocorr) > InpTrendThreshold)
      return PHASE_TRENDING;

   // Priority 4: Check Range Conditions
   if(adx < InpADXRangeLevel && priceLocation > 10 && priceLocation < 90)
      return PHASE_RANGING;

   // Default: Undefined transition state
   return PHASE_UNDEFINED;
}

//+------------------------------------------------------------------+
//| Get Recommended Strategy Based on Phase                           |
//+------------------------------------------------------------------+
int GetRecommendedStrategy(MARKET_PHASE phase)
{
   // 0 = None, 1 = Sniper, 2 = Rubber Band, 3 = Breakout
   switch(phase)
   {
      case PHASE_TRENDING:  return 1;  // Sniper
      case PHASE_RANGING:   return 2;  // Rubber Band
      case PHASE_VOLATILE:  return 3;  // Breakout
      default:              return 0;  // None
   }
}

//+------------------------------------------------------------------+
//| Get Confluence Multiplier for Phase                               |
//+------------------------------------------------------------------+
double GetConfluenceMultiplier(MARKET_PHASE phase)
{
   switch(phase)
   {
      case PHASE_TRENDING:  return 0.8;   // Lower threshold in trends
      case PHASE_RANGING:   return 1.2;   // Higher threshold in ranges
      case PHASE_VOLATILE:  return 1.5;   // Much higher in chaos
      case PHASE_DORMANT:   return 999.0; // Effectively disable
      default:              return 1.0;   // Normal
   }
}
//+------------------------------------------------------------------+
