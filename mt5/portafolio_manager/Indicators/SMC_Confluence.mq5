//+------------------------------------------------------------------+
//|                                             SMC_Confluence.mq5 |
//|          Smart Money Concepts - Consolidated SMC Indicator       |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   0  // Data only, no visual plots

//--- Include SMC modules (using relative paths)
#include "../Include/SMC_StructureBreak.mqh"
#include "../Include/SMC_OrderBlocks.mqh"
#include "../Include/SMC_FairValueGap.mqh"
#include "../Include/SMC_LiquiditySweep.mqh"

//--- Input parameters
input int    InpSwingLookback = 20;           // Swing Point Lookback
input double InpMinImpulseATR = 2.0;          // Min Impulse ATR Multiple
input double InpMinFVG_ATR = 0.5;             // Min FVG ATR Multiple
input int    InpMaxOrderBlocks = 5;           // Max Order Blocks to Track
input int    InpMaxFVGs = 10;                 // Max FVGs to Track

//--- Indicator buffers
double BufferStructureBreak[];    // Buffer 0: Structure Break Score (0-1.5)
double BufferOrderBlocks[];       // Buffer 1: Order Blocks Score (0-1.5)
double BufferFVG[];               // Buffer 2: FVG Score (0-1.0)
double BufferLiquiditySweep[];    // Buffer 3: Liquidity Sweep Score (0-1.5)
double BufferCombinedScore[];     // Buffer 4: Combined SMC Score (0-5.5)

//--- SMC module instances
CSMCStructureBreak    g_smcStructure;
CSMCOrderBlocks       g_smcOrderBlocks;
CSMCFairValueGap      g_smcFVG;
CSMCLiquiditySweep    g_smcLiquidity;

//--- Bar tracking
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferStructureBreak, INDICATOR_DATA);
   SetIndexBuffer(1, BufferOrderBlocks, INDICATOR_DATA);
   SetIndexBuffer(2, BufferFVG, INDICATOR_DATA);
   SetIndexBuffer(3, BufferLiquiditySweep, INDICATOR_DATA);
   SetIndexBuffer(4, BufferCombinedScore, INDICATOR_DATA);

   //--- Set buffer labels
   PlotIndexSetString(0, PLOT_LABEL, "SMC Structure");
   PlotIndexSetString(1, PLOT_LABEL, "SMC OrderBlocks");
   PlotIndexSetString(2, PLOT_LABEL, "SMC FVG");
   PlotIndexSetString(3, PLOT_LABEL, "SMC Liquidity");
   PlotIndexSetString(4, PLOT_LABEL, "SMC Combined");

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferStructureBreak, true);
   ArraySetAsSeries(BufferOrderBlocks, true);
   ArraySetAsSeries(BufferFVG, true);
   ArraySetAsSeries(BufferLiquiditySweep, true);
   ArraySetAsSeries(BufferCombinedScore, true);

   //--- Initialize SMC modules
   if(!g_smcStructure.Init(_Symbol, PERIOD_CURRENT, InpSwingLookback, 5, 0.5))
   {
      Print("ERROR: Failed to initialize Structure Break module");
      return INIT_FAILED;
   }

   if(!g_smcOrderBlocks.Init(_Symbol, PERIOD_CURRENT, 50, InpMaxOrderBlocks, InpMinImpulseATR))
   {
      Print("ERROR: Failed to initialize Order Blocks module");
      return INIT_FAILED;
   }

   if(!g_smcFVG.Init(_Symbol, PERIOD_CURRENT, 50, InpMaxFVGs, InpMinFVG_ATR))
   {
      Print("ERROR: Failed to initialize FVG module");
      return INIT_FAILED;
   }

   if(!g_smcLiquidity.Init(_Symbol, PERIOD_CURRENT, InpSwingLookback, 0.0002))
   {
      Print("ERROR: Failed to initialize Liquidity Sweep module");
      return INIT_FAILED;
   }

   //--- Set indicator short name
   IndicatorSetString(INDICATOR_SHORTNAME, "SMC Confluence");

   //--- Set indicator digits
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   Print("SMC_Confluence indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Cleanup SMC modules
   g_smcStructure.Deinit();
   g_smcOrderBlocks.Deinit();
   g_smcFVG.Deinit();
   g_smcLiquidity.Deinit();

   Print("SMC_Confluence indicator deinitialized");
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
   //--- Check for new bar
   datetime currentBarTime = time[rates_total - 1];
   bool isNewBar = (currentBarTime != g_lastBarTime);

   if(isNewBar)
   {
      g_lastBarTime = currentBarTime;

      //--- Update all SMC modules on new bar
      g_smcStructure.Update();
      g_smcOrderBlocks.Update();
      g_smcFVG.Update();
      g_smcLiquidity.Update();
   }

   //--- Calculate scores for both directions
   int currentBar = 0;  // We calculate for current bar

   //--- Bullish scores (direction = 1)
   double structureScoreBull = g_smcStructure.GetConfluenceScore(1);
   double obScoreBull = g_smcOrderBlocks.GetConfluenceScore(1);
   double fvgScoreBull = g_smcFVG.GetConfluenceScore(1);
   double liqScoreBull = g_smcLiquidity.GetConfluenceScore(1);
   double combinedBull = structureScoreBull + obScoreBull + fvgScoreBull + liqScoreBull;

   //--- Bearish scores (direction = -1)
   double structureScoreBear = g_smcStructure.GetConfluenceScore(-1);
   double obScoreBear = g_smcOrderBlocks.GetConfluenceScore(-1);
   double fvgScoreBear = g_smcFVG.GetConfluenceScore(-1);
   double liqScoreBear = g_smcLiquidity.GetConfluenceScore(-1);
   double combinedBear = structureScoreBear + obScoreBear + fvgScoreBear + liqScoreBear;

   //--- Use the higher score (direction with more confluence)
   // Store individual component scores from the dominant direction
   if(combinedBull > combinedBear)
   {
      BufferStructureBreak[currentBar] = structureScoreBull;
      BufferOrderBlocks[currentBar] = obScoreBull;
      BufferFVG[currentBar] = fvgScoreBull;
      BufferLiquiditySweep[currentBar] = liqScoreBull;
      BufferCombinedScore[currentBar] = combinedBull;
   }
   else
   {
      BufferStructureBreak[currentBar] = -structureScoreBear;  // Negative for bearish
      BufferOrderBlocks[currentBar] = -obScoreBear;
      BufferFVG[currentBar] = -fvgScoreBear;
      BufferLiquiditySweep[currentBar] = -liqScoreBear;
      BufferCombinedScore[currentBar] = -combinedBear;
   }

   //--- Return value of prev_calculated for next call
   return rates_total;
}
//+------------------------------------------------------------------+
