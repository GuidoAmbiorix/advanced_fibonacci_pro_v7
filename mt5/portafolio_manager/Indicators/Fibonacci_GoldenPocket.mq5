//+------------------------------------------------------------------+
//|                                     Fibonacci_GoldenPocket.mq5 |
//|          Automatic Fibonacci Golden Pocket Detector               |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 20
#property indicator_plots 9

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int    InpZigZagDepth = 12;            // ZigZag Depth
input int    InpZigZagDeviation = 5;         // ZigZag Deviation
input int    InpZigZagBackstep = 3;          // ZigZag Backstep
input int    InpMaxSwingAge = 100;           // Max Swing Age (bars)
input bool   InpUseGoldenPocket618 = true;   // Use 61.8-78.6% (vs 50-61.8%)
input bool   InpDetectFakeouts = true;       // Enable 127.2% Extension Detection
input double InpMinSwingSize = 50;           // Min Swing Size (pips)

//+------------------------------------------------------------------+
//| Indicator Buffers                                                 |
//+------------------------------------------------------------------+
// EA-Accessible Buffers (INDICATOR_DATA)
double BufferSwingHigh[];           // Buffer 0: Swing High (price)
double BufferSwingLow[];            // Buffer 1: Swing Low (price)
double BufferSwingDirection[];      // Buffer 2: Swing Direction (1/-1)
double BufferFib_0[];               // Buffer 3: 0% (swing high)
double BufferFib_236[];             // Buffer 4: 23.6%
double BufferFib_382[];             // Buffer 5: 38.2%
double BufferFib_500[];             // Buffer 6: 50%
double BufferFib_618[];             // Buffer 7: 61.8% (Golden pocket start)
double BufferFib_786[];             // Buffer 8: 78.6% (Golden pocket end)
double BufferFib_100[];             // Buffer 9: 100% (swing low)
double BufferFib_1272[];            // Buffer 10: 127.2% (fake-out zone)
double BufferInGoldenPocket[];      // Buffer 11: In golden pocket (1/0)
double BufferNearestFibLevel[];     // Buffer 12: Nearest level index (0-10)
double BufferDistanceToGoldenPocket[];// Buffer 13: Distance in pips
double BufferSwingAge[];            // Buffer 14: Bars since swing
double BufferSwingStrength[];       // Buffer 15: Swing strength (0-100%)

// Internal Calculation Buffers
double BufferZigZagValues[];        // Buffer 16: ZigZag values
double BufferSwingHighTime[];       // Buffer 17: Swing high time
double BufferSwingLowTime[];        // Buffer 18: Swing low time
double BufferHistoricalSwings[];    // Buffer 19: Historical swings

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int g_hZigZag = INVALID_HANDLE;

double g_currentSwingHigh = 0;
double g_currentSwingLow = 0;
int g_swingHighBar = 0;
int g_swingLowBar = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferSwingHigh, INDICATOR_DATA);
   SetIndexBuffer(1, BufferSwingLow, INDICATOR_DATA);
   SetIndexBuffer(2, BufferSwingDirection, INDICATOR_DATA);
   SetIndexBuffer(3, BufferFib_0, INDICATOR_DATA);
   SetIndexBuffer(4, BufferFib_236, INDICATOR_DATA);
   SetIndexBuffer(5, BufferFib_382, INDICATOR_DATA);
   SetIndexBuffer(6, BufferFib_500, INDICATOR_DATA);
   SetIndexBuffer(7, BufferFib_618, INDICATOR_DATA);
   SetIndexBuffer(8, BufferFib_786, INDICATOR_DATA);
   SetIndexBuffer(9, BufferFib_100, INDICATOR_DATA);
   SetIndexBuffer(10, BufferFib_1272, INDICATOR_DATA);
   SetIndexBuffer(11, BufferInGoldenPocket, INDICATOR_DATA);
   SetIndexBuffer(12, BufferNearestFibLevel, INDICATOR_DATA);
   SetIndexBuffer(13, BufferDistanceToGoldenPocket, INDICATOR_DATA);
   SetIndexBuffer(14, BufferSwingAge, INDICATOR_DATA);
   SetIndexBuffer(15, BufferSwingStrength, INDICATOR_DATA);

   SetIndexBuffer(16, BufferZigZagValues, INDICATOR_CALCULATIONS);
   SetIndexBuffer(17, BufferSwingHighTime, INDICATOR_CALCULATIONS);
   SetIndexBuffer(18, BufferSwingLowTime, INDICATOR_CALCULATIONS);
   SetIndexBuffer(19, BufferHistoricalSwings, INDICATOR_CALCULATIONS);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferSwingHigh, true);
   ArraySetAsSeries(BufferSwingLow, true);
   ArraySetAsSeries(BufferSwingDirection, true);
   ArraySetAsSeries(BufferFib_0, true);
   ArraySetAsSeries(BufferFib_236, true);
   ArraySetAsSeries(BufferFib_382, true);
   ArraySetAsSeries(BufferFib_500, true);
   ArraySetAsSeries(BufferFib_618, true);
   ArraySetAsSeries(BufferFib_786, true);
   ArraySetAsSeries(BufferFib_100, true);
   ArraySetAsSeries(BufferFib_1272, true);
   ArraySetAsSeries(BufferInGoldenPocket, true);
   ArraySetAsSeries(BufferNearestFibLevel, true);
   ArraySetAsSeries(BufferDistanceToGoldenPocket, true);
   ArraySetAsSeries(BufferSwingAge, true);
   ArraySetAsSeries(BufferSwingStrength, true);
   ArraySetAsSeries(BufferZigZagValues, true);

   //--- Create ZigZag indicator handle
   g_hZigZag = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\ZigZag",
      InpZigZagDepth, InpZigZagDeviation, InpZigZagBackstep);

   if(g_hZigZag == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ZigZag handle");
      return INIT_FAILED;
   }

   //--- Indicator settings
   IndicatorSetString(INDICATOR_SHORTNAME, "Fibonacci Golden Pocket");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   //--- Plot settings for Fibonacci levels
   for(int i = 3; i <= 10; i++)
   {
      PlotIndexSetInteger(i, PLOT_DRAW_TYPE, DRAW_LINE);
      PlotIndexSetInteger(i, PLOT_LINE_STYLE, STYLE_DOT);
      PlotIndexSetInteger(i, PLOT_LINE_WIDTH, 1);
   }

   // Golden pocket levels highlighted
   PlotIndexSetInteger(7, PLOT_LINE_WIDTH, 2);  // 61.8%
   PlotIndexSetInteger(8, PLOT_LINE_WIDTH, 2);  // 78.6%

   Print("Fibonacci_GoldenPocket indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hZigZag != INVALID_HANDLE) IndicatorRelease(g_hZigZag);
   Print("Fibonacci_GoldenPocket indicator deinitialized");
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
   if(rates_total < InpMaxSwingAge) return 0;

   //--- Set arrays as series
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(tick_volume, true);

   //--- Get ZigZag values
   double zigzagBuf[200];
   ArraySetAsSeries(zigzagBuf, true);
   int copied = CopyBuffer(g_hZigZag, 0, 0, 200, zigzagBuf);
   if(copied <= 0) return 0;

   //--- Detect swing points from ZigZag
   DetectSwingPoints(zigzagBuf, copied);

   //--- Calculate for current bar
   int currentBar = 0;

   //--- Store swing data
   BufferSwingHigh[currentBar] = g_currentSwingHigh;
   BufferSwingLow[currentBar] = g_currentSwingLow;

   // Determine swing direction (1 = bullish, -1 = bearish)
   int swingDirection = (g_currentSwingHigh > g_currentSwingLow) ? 1 : -1;
   BufferSwingDirection[currentBar] = swingDirection;

   //--- Calculate swing age
   int swingAge = (swingDirection == 1) ? g_swingLowBar : g_swingHighBar;
   BufferSwingAge[currentBar] = swingAge;

   //--- Validate swing (age and size checks)
   if(swingAge > InpMaxSwingAge)
   {
      // Swing too old, reset
      BufferInGoldenPocket[currentBar] = 0.0;
      return rates_total;
   }

   double swingSize = MathAbs(g_currentSwingHigh - g_currentSwingLow);
   double swingSizePips = swingSize / _Point;

   if(swingSizePips < InpMinSwingSize)
   {
      // Swing too small, invalid
      BufferInGoldenPocket[currentBar] = 0.0;
      return rates_total;
   }

   //--- Calculate swing strength (based on range and volume)
   double avgVolume = CalculateAverageVolume(tick_volume, 20);
   double maxVolume = 0;
   for(int i = MathMin(g_swingHighBar, g_swingLowBar); i <= MathMax(g_swingHighBar, g_swingLowBar); i++)
   {
      if(tick_volume[i] > maxVolume) maxVolume = tick_volume[i];
   }

   double volumeStrength = (avgVolume > 0) ? MathMin(100.0, maxVolume / avgVolume * 50.0) : 50.0;
   double rangeStrength = MathMin(100.0, swingSizePips / InpMinSwingSize * 50.0);
   double swingStrength = (volumeStrength + rangeStrength) / 2.0;
   BufferSwingStrength[currentBar] = swingStrength;

   //--- Calculate Fibonacci levels
   double range = g_currentSwingHigh - g_currentSwingLow;

   BufferFib_0[currentBar] = g_currentSwingHigh;
   BufferFib_236[currentBar] = g_currentSwingHigh - (range * 0.236);
   BufferFib_382[currentBar] = g_currentSwingHigh - (range * 0.382);
   BufferFib_500[currentBar] = g_currentSwingHigh - (range * 0.500);
   BufferFib_618[currentBar] = g_currentSwingHigh - (range * 0.618);
   BufferFib_786[currentBar] = g_currentSwingHigh - (range * 0.786);
   BufferFib_100[currentBar] = g_currentSwingLow;

   // Extension for fake-out detection
   if(InpDetectFakeouts)
      BufferFib_1272[currentBar] = g_currentSwingLow - (range * 0.272);
   else
      BufferFib_1272[currentBar] = g_currentSwingLow;

   //--- Check if price is in golden pocket
   double currentPrice = close[currentBar];
   double goldenPocketLow = InpUseGoldenPocket618 ? BufferFib_786[currentBar] : BufferFib_618[currentBar];
   double goldenPocketHigh = BufferFib_618[currentBar];

   bool inGoldenPocket = (currentPrice >= goldenPocketLow && currentPrice <= goldenPocketHigh);
   BufferInGoldenPocket[currentBar] = inGoldenPocket ? 1.0 : 0.0;

   //--- Find nearest Fibonacci level
   double fibLevels[11];
   fibLevels[0] = BufferFib_0[currentBar];
   fibLevels[1] = BufferFib_236[currentBar];
   fibLevels[2] = BufferFib_382[currentBar];
   fibLevels[3] = BufferFib_500[currentBar];
   fibLevels[4] = BufferFib_618[currentBar];
   fibLevels[5] = BufferFib_786[currentBar];
   fibLevels[6] = BufferFib_100[currentBar];
   fibLevels[7] = BufferFib_1272[currentBar];

   int nearestIndex = 0;
   double minDistance = MathAbs(currentPrice - fibLevels[0]);

   for(int i = 1; i < 8; i++)
   {
      double distance = MathAbs(currentPrice - fibLevels[i]);
      if(distance < minDistance)
      {
         minDistance = distance;
         nearestIndex = i;
      }
   }

   BufferNearestFibLevel[currentBar] = nearestIndex;

   //--- Calculate distance to golden pocket (in pips)
   double distanceToGP = 0;
   if(!inGoldenPocket)
   {
      if(currentPrice > goldenPocketHigh)
         distanceToGP = (currentPrice - goldenPocketHigh) / _Point;
      else
         distanceToGP = (goldenPocketLow - currentPrice) / _Point;
   }
   BufferDistanceToGoldenPocket[currentBar] = distanceToGP;

   return rates_total;
}

//+------------------------------------------------------------------+
//| Detect Swing Points from ZigZag                                   |
//+------------------------------------------------------------------+
void DetectSwingPoints(double &zigzagBuffer[], int size)
{
   int pointsFound = 0;
   double points[2];
   int bars[2];

   for(int i = 0; i < size && pointsFound < 2; i++)
   {
      if(zigzagBuffer[i] != 0 && zigzagBuffer[i] != EMPTY_VALUE)
      {
         points[pointsFound] = zigzagBuffer[i];
         bars[pointsFound] = i;
         pointsFound++;
      }
   }

   if(pointsFound >= 2)
   {
      // Determine which is high and which is low
      if(points[0] > points[1])
      {
         g_currentSwingHigh = points[0];
         g_swingHighBar = bars[0];
         g_currentSwingLow = points[1];
         g_swingLowBar = bars[1];
      }
      else
      {
         g_currentSwingHigh = points[1];
         g_swingHighBar = bars[1];
         g_currentSwingLow = points[0];
         g_swingLowBar = bars[0];
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Average Volume                                          |
//+------------------------------------------------------------------+
double CalculateAverageVolume(const long &volume[], int period)
{
   long sum = 0;
   for(int i = 0; i < period; i++)
      sum += volume[i];

   return (double)sum / period;
}
//+------------------------------------------------------------------+
