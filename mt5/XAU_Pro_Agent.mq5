//+------------------------------------------------------------------+
//|                                                 XAU_Pro_Agent.mq5 |
//|                          XAU Pro Engine - Pure MT5 Trading Agent  |
//|                                   Institutional Edge Trading Bot  |
//+------------------------------------------------------------------+
#property copyright "XAU Pro Engine"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property description "Pure MT5 Trading Agent with XAU Pro Engine Logic"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_AGENT_MODE
{
   AGENT_CONSERVATIVE = 0,    // Conservative - High Win Rate
   AGENT_BALANCED = 1,        // Balanced - Mixed Approach  
   AGENT_AGGRESSIVE = 2       // Aggressive - High Risk/Reward
};

enum ENUM_SESSION_FILTER
{
   SESSION_ALL = 0,           // Trade All Sessions
   SESSION_LONDON = 1,        // London Session Only
   SESSION_NEWYORK = 2,       // New York Session Only
   SESSION_OVERLAP = 3        // London-NY Overlap Only
};

enum ENUM_ENTRY_TYPE
{
   ENTRY_FIBONACCI = 0,       // Fibonacci Retracement
   ENTRY_STRUCTURE = 1,       // Market Structure Break
   ENTRY_LIQUIDITY = 2,       // Liquidity Sweep
   ENTRY_CONFLUENCE = 3       // All Factors Combined
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Agent Settings
input group "========== AGENT CONFIGURATION =========="
input ENUM_AGENT_MODE    InpAgentMode = AGENT_BALANCED;      // Agent Trading Mode
input ENUM_SESSION_FILTER InpSessionFilter = SESSION_OVERLAP; // Session Filter
input ENUM_ENTRY_TYPE    InpEntryType = ENTRY_CONFLUENCE;    // Entry Type
input int                InpMagicNumber = 777777;            // Magic Number
input string             InpAgentName = "XAU_PRO_AGENT";     // Agent Name

//--- Risk Management
input group "========== RISK MANAGEMENT =========="
input double   InpRiskPercent = 1.0;          // Risk Per Trade (%)
input double   InpMaxDailyDD = 3.0;           // Max Daily Drawdown (%)
input double   InpMaxTotalDD = 10.0;          // Max Total Drawdown (%)
input int      InpMaxPositions = 1;           // Max Concurrent Positions
input int      InpMaxDailyTrades = 3;         // Max Daily Trades
input bool     InpUseEquityStop = true;       // Enable Equity Stop

//--- Fibonacci Settings
input group "========== FIBONACCI LEVELS =========="
input bool     InpFib_236 = true;             // 23.6% Level
input bool     InpFib_382 = true;             // 38.2% Level (Key Level)
input bool     InpFib_500 = true;             // 50.0% Level (Key Level)
input bool     InpFib_618 = true;             // 61.8% Level (Golden Ratio)
input bool     InpFib_786 = true;             // 78.6% Level (Deep Retracement)
input int      InpSwingLookback = 50;         // Swing Detection Lookback
input int      InpMinSwingBars = 5;           // Min Bars Between Swings

//--- Structure Analysis
input group "========== MARKET STRUCTURE =========="
input bool     InpRequireBOS = true;          // Require Break of Structure
input bool     InpRequireCHoCH = true;        // Require Change of Character
input bool     InpTrackOrderBlocks = true;    // Track Order Blocks
input bool     InpTrackFVG = true;            // Track Fair Value Gaps (FVG)
input int      InpStructureLookback = 100;    // Structure Detection Lookback

//--- Multi-Timeframe
input group "========== MULTI-TIMEFRAME =========="
input bool     InpUseMTF = true;              // Enable Multi-Timeframe
input ENUM_TIMEFRAMES InpHTF = PERIOD_H4;     // Higher Timeframe
input bool     InpRequireHTFAlignment = true; // Require HTF Alignment

//--- Smart Money Concepts
input group "========== SMART MONEY =========="
input bool     InpTrackLiquidity = true;      // Track Liquidity Pools
input bool     InpAvoidLiquiditySweeps = true;// Avoid Before Sweep
input bool     InpEnterAfterSweep = true;     // Enter After Liquidity Sweep
input int      InpLiquidityBuffer = 20;       // Liquidity Buffer (points)

//--- Take Profit & Stop Loss
input group "========== TP/SL MANAGEMENT =========="
input double   InpRiskReward1 = 1.5;          // TP1 Risk:Reward Ratio
input double   InpRiskReward2 = 2.5;          // TP2 Risk:Reward Ratio  
input double   InpRiskReward3 = 4.0;          // TP3 Risk:Reward Ratio
input double   InpTP1Percent = 50;            // Close % at TP1
input double   InpTP2Percent = 30;            // Close % at TP2
input bool     InpTrailAfterTP1 = true;       // Trail Stop After TP1
input double   InpTrailDistance = 30;         // Trail Distance (points)

//--- Indicators
input group "========== CONFIRMATION INDICATORS =========="
input bool     InpUseRSI = true;              // Use RSI Filter
input int      InpRSIPeriod = 14;             // RSI Period
input int      InpRSIOverbought = 70;         // RSI Overbought
input int      InpRSIOversold = 30;           // RSI Oversold
input bool     InpUseMACD = true;             // Use MACD Filter
input bool     InpUseVolume = true;           // Use Volume Filter

//--- Dashboard
input group "========== DISPLAY =========="
input bool     InpShowDashboard = true;       // Show Agent Dashboard
input bool     InpShowLevels = true;          // Show Fib Levels on Chart
input bool     InpShowZones = true;           // Show Order Block Zones
input color    InpBullColor = clrLime;        // Bullish Color
input color    InpBearColor = clrRed;         // Bearish Color

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
COrderInfo     order;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

// Indicator Handles
int handleRSI, handleMACD, handleATR, handleVolume;
int handleRSI_HTF, handleMACD_HTF;

// Fibonacci Levels
double fibLevels[5] = {0.236, 0.382, 0.500, 0.618, 0.786};
double currentFibHigh, currentFibLow;
double fibRetracements[5];
double fibExtensions[3];

// Swing Points
double swingHigh, swingLow;
int swingHighBar, swingLowBar;
bool trendBullish;

// Market Structure
struct StructurePoint
{
   double price;
   datetime time;
   bool isHigh;
   bool broken;
};
StructurePoint structurePoints[];
bool bosConfirmed, chochConfirmed;

// Order Blocks
struct OrderBlock
{
   double high;
   double low;
   datetime time;
   bool bullish;
   bool mitigated;
};
OrderBlock orderBlocks[];

// Fair Value Gaps
struct FVG
{
   double high;
   double low;
   datetime time;
   bool bullish;
   bool filled;
};
FVG fairValueGaps[];

// Liquidity
struct LiquidityPool
{
   double level;
   datetime time;
   bool isHigh;
   bool swept;
};
LiquidityPool liquidityPools[];

// Statistics
int dailyTrades;
double dailyPnL;
double startingEquity;
double peakEquity;
datetime lastTradeDate;

// State
bool isNewBar;
datetime lastBarTime;
string agentStatus;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   // Initialize symbol info
   symbolInfo.Name(_Symbol);
   symbolInfo.RefreshRates();
   
   // Initialize indicators
   if(!InitializeIndicators())
   {
      Print("XAU Pro Agent: Failed to initialize indicators");
      return INIT_FAILED;
   }
   
   // Initialize tracking variables
   startingEquity = account.Equity();
   peakEquity = startingEquity;
   dailyTrades = 0;
   dailyPnL = 0;
   lastTradeDate = 0;
   
   // Initial calculations
   CalculateSwingPoints();
   CalculateFibonacciLevels();
   AnalyzeMarketStructure();
   DetectLiquidityPools();
   
   agentStatus = "INITIALIZED";
   
   Print("✅ XAU Pro Agent Initialized Successfully");
   Print("🎯 Mode: ", EnumToString(InpAgentMode));
   Print("📊 Risk: ", InpRiskPercent, "% per trade");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleMACD != INVALID_HANDLE) IndicatorRelease(handleMACD);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleVolume != INVALID_HANDLE) IndicatorRelease(handleVolume);
   if(handleRSI_HTF != INVALID_HANDLE) IndicatorRelease(handleRSI_HTF);
   if(handleMACD_HTF != INVALID_HANDLE) IndicatorRelease(handleMACD_HTF);
   
   // Clean up chart objects
   ObjectsDeleteAll(0, "XAU_");
   
   Print("🔴 XAU Pro Agent Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update symbol info
   symbolInfo.RefreshRates();
   
   // Check for new bar
   isNewBar = CheckNewBar();
   
   // Update dashboard every tick
   if(InpShowDashboard)
      UpdateDashboard();
   
   // Process only on new bar for main logic
   if(!isNewBar) 
   {
      // Still manage positions on every tick
      ManageOpenPositions();
      return;
   }
   
   // Reset daily counters if new day
   CheckNewDay();
   
   // Check risk limits
   if(!CheckRiskLimits())
   {
      agentStatus = "RISK LIMIT HIT";
      return;
   }
   
   // Check session filter
   if(!IsValidSession())
   {
      agentStatus = "WAITING FOR SESSION";
      return;
   }
   
   // Update analysis
   CalculateSwingPoints();
   CalculateFibonacciLevels();
   AnalyzeMarketStructure();
   DetectOrderBlocks();
   DetectFairValueGaps();
   DetectLiquidityPools();
   
   // Get indicator values
   double rsi = GetRSI();
   double macdMain, macdSignal;
   GetMACD(macdMain, macdSignal);
   double atr = GetATR();
   
   // Analyze confluence
   int buyConfluence = 0;
   int sellConfluence = 0;
   AnalyzeConfluence(buyConfluence, sellConfluence, rsi, macdMain, macdSignal);
   
   // Generate signals
   int requiredConfluence = GetRequiredConfluence();
   bool buySignal = (buyConfluence >= requiredConfluence);
   bool sellSignal = (sellConfluence >= requiredConfluence);
   
   // Execute trades
   if(CanOpenNewPosition())
   {
      if(buySignal)
      {
         ExecuteTrade(ORDER_TYPE_BUY, atr, buyConfluence);
      }
      else if(sellSignal)
      {
         ExecuteTrade(ORDER_TYPE_SELL, atr, sellConfluence);
      }
   }
   
   // Update chart objects
   if(InpShowLevels)
      DrawFibonacciLevels();
   if(InpShowZones)
      DrawOrderBlockZones();
      
   agentStatus = "SCANNING";
}

//+------------------------------------------------------------------+
//| Initialize Indicators                                            |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
   // RSI
   if(InpUseRSI)
   {
      handleRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
      if(handleRSI == INVALID_HANDLE) return false;
      
      if(InpUseMTF)
      {
         handleRSI_HTF = iRSI(_Symbol, InpHTF, InpRSIPeriod, PRICE_CLOSE);
         if(handleRSI_HTF == INVALID_HANDLE) return false;
      }
   }
   
   // MACD
   if(InpUseMACD)
   {
      handleMACD = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
      if(handleMACD == INVALID_HANDLE) return false;
      
      if(InpUseMTF)
      {
         handleMACD_HTF = iMACD(_Symbol, InpHTF, 12, 26, 9, PRICE_CLOSE);
         if(handleMACD_HTF == INVALID_HANDLE) return false;
      }
   }
   
   // ATR (always needed for position sizing)
   handleATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(handleATR == INVALID_HANDLE) return false;
   
   // Volume
   if(InpUseVolume)
   {
      handleVolume = iVolumes(_Symbol, PERIOD_CURRENT, VOLUME_TICK);
      if(handleVolume == INVALID_HANDLE) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for New Bar                                                |
//+------------------------------------------------------------------+
bool CheckNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for New Day                                                |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   datetime currentDate = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(currentDate != lastTradeDate)
   {
      dailyTrades = 0;
      dailyPnL = 0;
      lastTradeDate = currentDate;
   }
}

//+------------------------------------------------------------------+
//| Check Risk Limits                                                |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
   double currentEquity = account.Equity();
   
   // Update peak equity
   if(currentEquity > peakEquity)
      peakEquity = currentEquity;
   
   // Check daily drawdown
   double dailyDD = (startingEquity - currentEquity) / startingEquity * 100;
   if(InpUseEquityStop && dailyDD >= InpMaxDailyDD)
   {
      Print("⚠️ Daily Drawdown Limit Reached: ", DoubleToString(dailyDD, 2), "%");
      return false;
   }
   
   // Check total drawdown
   double totalDD = (peakEquity - currentEquity) / peakEquity * 100;
   if(InpUseEquityStop && totalDD >= InpMaxTotalDD)
   {
      Print("⚠️ Total Drawdown Limit Reached: ", DoubleToString(totalDD, 2), "%");
      return false;
   }
   
   // Check max daily trades
   if(dailyTrades >= InpMaxDailyTrades)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check Session Filter                                             |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   if(InpSessionFilter == SESSION_ALL)
      return true;
      
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   switch(InpSessionFilter)
   {
      case SESSION_LONDON:
         return (hour >= 8 && hour < 16);  // 08:00 - 16:00 UTC
         
      case SESSION_NEWYORK:
         return (hour >= 13 && hour < 21); // 13:00 - 21:00 UTC
         
      case SESSION_OVERLAP:
         return (hour >= 13 && hour < 16); // 13:00 - 16:00 UTC
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate Swing Points                                           |
//+------------------------------------------------------------------+
void CalculateSwingPoints()
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpSwingLookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, InpSwingLookback, low);
   
   // Find swing high
   int highestBar = ArrayMaximum(high, 0, InpSwingLookback);
   swingHigh = high[highestBar];
   swingHighBar = highestBar;
   
   // Find swing low
   int lowestBar = ArrayMinimum(low, 0, InpSwingLookback);
   swingLow = low[lowestBar];
   swingLowBar = lowestBar;
   
   // Determine trend
   if(swingHighBar > swingLowBar)
      trendBullish = true;  // Most recent swing is the low (potential reversal up)
   else
      trendBullish = false; // Most recent swing is the high (potential reversal down)
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                       |
//+------------------------------------------------------------------+
void CalculateFibonacciLevels()
{
   currentFibHigh = swingHigh;
   currentFibLow = swingLow;
   double range = currentFibHigh - currentFibLow;
   
   if(trendBullish)
   {
      // Retracements from high to low (for buy entries)
      for(int i = 0; i < 5; i++)
         fibRetracements[i] = currentFibHigh - (range * fibLevels[i]);
         
      // Extensions above high
      fibExtensions[0] = currentFibHigh + (range * 0.618);
      fibExtensions[1] = currentFibHigh + range;
      fibExtensions[2] = currentFibHigh + (range * 1.618);
   }
   else
   {
      // Retracements from low to high (for sell entries)
      for(int i = 0; i < 5; i++)
         fibRetracements[i] = currentFibLow + (range * fibLevels[i]);
         
      // Extensions below low
      fibExtensions[0] = currentFibLow - (range * 0.618);
      fibExtensions[1] = currentFibLow - range;
      fibExtensions[2] = currentFibLow - (range * 1.618);
   }
}

//+------------------------------------------------------------------+
//| Analyze Market Structure                                         |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure()
{
   bosConfirmed = false;
   chochConfirmed = false;
   
   ArrayResize(structurePoints, 0);
   
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, low);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, close);
   
   // Find structure points (swing highs and lows)
   for(int i = 2; i < InpStructureLookback - 2; i++)
   {
      // Swing high
      if(high[i] > high[i-1] && high[i] > high[i-2] && 
         high[i] > high[i+1] && high[i] > high[i+2])
      {
         StructurePoint sp;
         sp.price = high[i];
         sp.time = iTime(_Symbol, PERIOD_CURRENT, i);
         sp.isHigh = true;
         sp.broken = (close[0] > high[i]);
         
         int size = ArraySize(structurePoints);
         ArrayResize(structurePoints, size + 1);
         structurePoints[size] = sp;
         
         // Check for BOS
         if(sp.broken && trendBullish)
            bosConfirmed = true;
      }
      
      // Swing low
      if(low[i] < low[i-1] && low[i] < low[i-2] && 
         low[i] < low[i+1] && low[i] < low[i+2])
      {
         StructurePoint sp;
         sp.price = low[i];
         sp.time = iTime(_Symbol, PERIOD_CURRENT, i);
         sp.isHigh = false;
         sp.broken = (close[0] < low[i]);
         
         int size = ArraySize(structurePoints);
         ArrayResize(structurePoints, size + 1);
         structurePoints[size] = sp;
         
         // Check for BOS
         if(sp.broken && !trendBullish)
            bosConfirmed = true;
      }
   }
   
   // Detect CHoCH (Change of Character)
   if(ArraySize(structurePoints) >= 3)
   {
      StructurePoint lastHigh, lastLow, prevHigh, prevLow;
      bool foundLastHigh = false, foundLastLow = false;
      bool foundPrevHigh = false, foundPrevLow = false;
      
      for(int i = 0; i < ArraySize(structurePoints); i++)
      {
         if(structurePoints[i].isHigh)
         {
            if(!foundLastHigh) { lastHigh = structurePoints[i]; foundLastHigh = true; }
            else if(!foundPrevHigh) { prevHigh = structurePoints[i]; foundPrevHigh = true; }
         }
         else
         {
            if(!foundLastLow) { lastLow = structurePoints[i]; foundLastLow = true; }
            else if(!foundPrevLow) { prevLow = structurePoints[i]; foundPrevLow = true; }
         }
      }
      
      if(foundPrevHigh && foundPrevLow)
      {
         // CHoCH = Higher low broken in uptrend OR Lower high broken in downtrend
         double currentClose = close[0];
         if(trendBullish && currentClose < lastLow.price)
            chochConfirmed = true;
         if(!trendBullish && currentClose > lastHigh.price)
            chochConfirmed = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Order Blocks                                              |
//+------------------------------------------------------------------+
void DetectOrderBlocks()
{
   if(!InpTrackOrderBlocks)
      return;
      
   ArrayResize(orderBlocks, 0);
   
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, open);
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, low);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, close);
   
   double currentPrice = close[0];
   
   for(int i = 3; i < InpStructureLookback - 1; i++)
   {
      // Bullish Order Block: Last down candle before strong up move
      if(close[i] < open[i] && close[i-1] > open[i-1] && close[i-2] > open[i-2])
      {
         // Check for displacement (strong move)
         if((close[i-2] - close[i]) > 2 * GetATR())
         {
            OrderBlock ob;
            ob.high = high[i];
            ob.low = low[i];
            ob.time = iTime(_Symbol, PERIOD_CURRENT, i);
            ob.bullish = true;
            ob.mitigated = (currentPrice < ob.low);
            
            int size = ArraySize(orderBlocks);
            ArrayResize(orderBlocks, size + 1);
            orderBlocks[size] = ob;
         }
      }
      
      // Bearish Order Block: Last up candle before strong down move
      if(close[i] > open[i] && close[i-1] < open[i-1] && close[i-2] < open[i-2])
      {
         // Check for displacement
         if((close[i] - close[i-2]) > 2 * GetATR())
         {
            OrderBlock ob;
            ob.high = high[i];
            ob.low = low[i];
            ob.time = iTime(_Symbol, PERIOD_CURRENT, i);
            ob.bullish = false;
            ob.mitigated = (currentPrice > ob.high);
            
            int size = ArraySize(orderBlocks);
            ArrayResize(orderBlocks, size + 1);
            orderBlocks[size] = ob;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps                                           |
//+------------------------------------------------------------------+
void DetectFairValueGaps()
{
   if(!InpTrackFVG)
      return;
      
   ArrayResize(fairValueGaps, 0);
   
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, low);
   
   double currentPrice = symbolInfo.Bid();
   
   for(int i = 1; i < InpStructureLookback - 1; i++)
   {
      // Bullish FVG: Gap between candle 3 high and candle 1 low
      if(low[i-1] > high[i+1])
      {
         FVG fvg;
         fvg.high = low[i-1];
         fvg.low = high[i+1];
         fvg.time = iTime(_Symbol, PERIOD_CURRENT, i);
         fvg.bullish = true;
         fvg.filled = (currentPrice <= fvg.low);
         
         int size = ArraySize(fairValueGaps);
         ArrayResize(fairValueGaps, size + 1);
         fairValueGaps[size] = fvg;
      }
      
      // Bearish FVG: Gap between candle 1 high and candle 3 low
      if(high[i-1] < low[i+1])
      {
         FVG fvg;
         fvg.high = low[i+1];
         fvg.low = high[i-1];
         fvg.time = iTime(_Symbol, PERIOD_CURRENT, i);
         fvg.bullish = false;
         fvg.filled = (currentPrice >= fvg.high);
         
         int size = ArraySize(fairValueGaps);
         ArrayResize(fairValueGaps, size + 1);
         fairValueGaps[size] = fvg;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Liquidity Pools                                           |
//+------------------------------------------------------------------+
void DetectLiquidityPools()
{
   if(!InpTrackLiquidity)
      return;
      
   ArrayResize(liquidityPools, 0);
   
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, InpStructureLookback, low);
   
   double currentPrice = symbolInfo.Bid();
   double buffer = InpLiquidityBuffer * symbolInfo.Point();
   
   // Find equal highs (liquidity above)
   for(int i = 5; i < InpStructureLookback - 5; i++)
   {
      if(high[i] > high[i-1] && high[i] > high[i-2] && 
         high[i] > high[i+1] && high[i] > high[i+2])
      {
         // Check for equal high nearby
         for(int j = i + 5; j < MathMin(i + 20, InpStructureLookback); j++)
         {
            if(MathAbs(high[j] - high[i]) < buffer)
            {
               LiquidityPool lp;
               lp.level = MathMax(high[i], high[j]);
               lp.time = iTime(_Symbol, PERIOD_CURRENT, i);
               lp.isHigh = true;
               lp.swept = (currentPrice > lp.level);
               
               int size = ArraySize(liquidityPools);
               ArrayResize(liquidityPools, size + 1);
               liquidityPools[size] = lp;
               break;
            }
         }
      }
   }
   
   // Find equal lows (liquidity below)
   for(int i = 5; i < InpStructureLookback - 5; i++)
   {
      if(low[i] < low[i-1] && low[i] < low[i-2] && 
         low[i] < low[i+1] && low[i] < low[i+2])
      {
         // Check for equal low nearby
         for(int j = i + 5; j < MathMin(i + 20, InpStructureLookback); j++)
         {
            if(MathAbs(low[j] - low[i]) < buffer)
            {
               LiquidityPool lp;
               lp.level = MathMin(low[i], low[j]);
               lp.time = iTime(_Symbol, PERIOD_CURRENT, i);
               lp.isHigh = false;
               lp.swept = (currentPrice < lp.level);
               
               int size = ArraySize(liquidityPools);
               ArrayResize(liquidityPools, size + 1);
               liquidityPools[size] = lp;
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Analyze Confluence                                               |
//+------------------------------------------------------------------+
void AnalyzeConfluence(int &buyScore, int &sellScore, double rsi, double macdMain, double macdSignal)
{
   buyScore = 0;
   sellScore = 0;
   
   double currentPrice = symbolInfo.Bid();
   double atr = GetATR();
   
   // 1. Trend Direction (+1)
   if(trendBullish) buyScore++;
   else sellScore++;
   
   // 2. Fibonacci Level (+2 for key levels)
   for(int i = 0; i < 5; i++)
   {
      double tolerance = atr * 0.5;
      if(MathAbs(currentPrice - fibRetracements[i]) < tolerance)
      {
         bool isKeyLevel = (fibLevels[i] == 0.382 || fibLevels[i] == 0.500 || fibLevels[i] == 0.618);
         if(trendBullish) buyScore += (isKeyLevel ? 2 : 1);
         else sellScore += (isKeyLevel ? 2 : 1);
         break;
      }
   }
   
   // 3. RSI Filter (+1)
   if(InpUseRSI)
   {
      if(rsi < InpRSIOversold) buyScore++;
      if(rsi > InpRSIOverbought) sellScore++;
   }
   
   // 4. MACD Filter (+1)
   if(InpUseMACD)
   {
      if(macdMain > macdSignal && macdMain < 0) buyScore++; // Bullish cross below zero
      if(macdMain < macdSignal && macdMain > 0) sellScore++; // Bearish cross above zero
   }
   
   // 5. Break of Structure (+2)
   if(InpRequireBOS && bosConfirmed)
   {
      if(trendBullish) buyScore += 2;
      else sellScore += 2;
   }
   
   // 6. Order Block (+2)
   if(InpTrackOrderBlocks)
   {
      for(int i = 0; i < ArraySize(orderBlocks); i++)
      {
         if(!orderBlocks[i].mitigated)
         {
            if(orderBlocks[i].bullish && currentPrice >= orderBlocks[i].low && currentPrice <= orderBlocks[i].high)
               buyScore += 2;
            if(!orderBlocks[i].bullish && currentPrice >= orderBlocks[i].low && currentPrice <= orderBlocks[i].high)
               sellScore += 2;
         }
      }
   }
   
   // 7. Fair Value Gap (+1)
   if(InpTrackFVG)
   {
      for(int i = 0; i < ArraySize(fairValueGaps); i++)
      {
         if(!fairValueGaps[i].filled)
         {
            if(fairValueGaps[i].bullish && currentPrice >= fairValueGaps[i].low && currentPrice <= fairValueGaps[i].high)
               buyScore++;
            if(!fairValueGaps[i].bullish && currentPrice >= fairValueGaps[i].low && currentPrice <= fairValueGaps[i].high)
               sellScore++;
         }
      }
   }
   
   // 8. Liquidity Sweep (+2)
   if(InpEnterAfterSweep)
   {
      for(int i = 0; i < ArraySize(liquidityPools); i++)
      {
         if(liquidityPools[i].swept)
         {
            if(!liquidityPools[i].isHigh) buyScore += 2;  // Buy after low sweep
            if(liquidityPools[i].isHigh) sellScore += 2;  // Sell after high sweep
         }
      }
   }
   
   // 9. HTF Alignment (+2)
   if(InpUseMTF && InpRequireHTFAlignment)
   {
      double htfRSI = GetHTFRSI();
      if(htfRSI < 50 && trendBullish) buyScore += 2;
      if(htfRSI > 50 && !trendBullish) sellScore += 2;
   }
}

//+------------------------------------------------------------------+
//| Get Required Confluence Based on Mode                            |
//+------------------------------------------------------------------+
int GetRequiredConfluence()
{
   switch(InpAgentMode)
   {
      case AGENT_CONSERVATIVE: return 8;
      case AGENT_BALANCED:     return 5;
      case AGENT_AGGRESSIVE:   return 3;
   }
   return 5;
}

//+------------------------------------------------------------------+
//| Can Open New Position                                            |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
   // Check position count
   int openPositions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Magic() == InpMagicNumber && position.Symbol() == _Symbol)
            openPositions++;
      }
   }
   
   return (openPositions < InpMaxPositions);
}

//+------------------------------------------------------------------+
//| Execute Trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atr, int confluence)
{
   double price, sl, tp1, tp2, tp3;
   double lotSize = CalculateLotSize(atr);
   
   if(type == ORDER_TYPE_BUY)
   {
      price = symbolInfo.Ask();
      sl = price - (atr * 2);
      tp1 = price + (atr * 2 * InpRiskReward1);
      tp2 = price + (atr * 2 * InpRiskReward2);
      tp3 = price + (atr * 2 * InpRiskReward3);
   }
   else
   {
      price = symbolInfo.Bid();
      sl = price + (atr * 2);
      tp1 = price - (atr * 2 * InpRiskReward1);
      tp2 = price - (atr * 2 * InpRiskReward2);
      tp3 = price - (atr * 2 * InpRiskReward3);
   }
   
   // Normalize prices
   sl = NormalizeDouble(sl, symbolInfo.Digits());
   tp1 = NormalizeDouble(tp1, symbolInfo.Digits());
   
   string comment = StringFormat("%s|C:%d", InpAgentName, confluence);
   
   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp1, comment))
   {
      dailyTrades++;
      Print("✅ ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), " executed | Confluence: ", confluence, " | Lot: ", lotSize);
      agentStatus = "TRADE EXECUTED";
   }
   else
   {
      Print("❌ Trade failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double atr)
{
   double riskAmount = account.Balance() * (InpRiskPercent / 100);
   double slPoints = atr * 2 / symbolInfo.Point();
   double tickValue = symbolInfo.TickValue();
   
   double lotSize = riskAmount / (slPoints * tickValue);
   
   // Normalize lot size
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();
   
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i))
         continue;
         
      if(position.Magic() != InpMagicNumber || position.Symbol() != _Symbol)
         continue;
      
      double currentPrice = (position.PositionType() == POSITION_TYPE_BUY) ? 
                           symbolInfo.Bid() : symbolInfo.Ask();
      double openPrice = position.PriceOpen();
      double sl = position.StopLoss();
      double tp = position.TakeProfit();
      
      // Check if TP1 hit for trailing
      if(InpTrailAfterTP1)
      {
         double slDistance = MathAbs(openPrice - sl);
         double tp1Level = (position.PositionType() == POSITION_TYPE_BUY) ?
                          openPrice + (slDistance * InpRiskReward1) :
                          openPrice - (slDistance * InpRiskReward1);
         
         bool passedTP1 = (position.PositionType() == POSITION_TYPE_BUY) ?
                          (currentPrice >= tp1Level) : (currentPrice <= tp1Level);
         
         if(passedTP1)
         {
            double newSL;
            double trailDist = InpTrailDistance * symbolInfo.Point();
            
            if(position.PositionType() == POSITION_TYPE_BUY)
            {
               newSL = currentPrice - trailDist;
               if(newSL > sl)
                  trade.PositionModify(position.Ticket(), newSL, tp);
            }
            else
            {
               newSL = currentPrice + trailDist;
               if(newSL < sl)
                  trade.PositionModify(position.Ticket(), newSL, tp);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get Indicator Values                                             |
//+------------------------------------------------------------------+
double GetRSI()
{
   if(!InpUseRSI || handleRSI == INVALID_HANDLE)
      return 50;
      
   double buffer[];
   ArraySetAsSeries(buffer, true);
   CopyBuffer(handleRSI, 0, 0, 1, buffer);
   return buffer[0];
}

double GetHTFRSI()
{
   if(!InpUseMTF || handleRSI_HTF == INVALID_HANDLE)
      return 50;
      
   double buffer[];
   ArraySetAsSeries(buffer, true);
   CopyBuffer(handleRSI_HTF, 0, 0, 1, buffer);
   return buffer[0];
}

void GetMACD(double &main, double &signal)
{
   if(!InpUseMACD || handleMACD == INVALID_HANDLE)
   {
      main = 0;
      signal = 0;
      return;
   }
   
   double mainBuffer[], signalBuffer[];
   ArraySetAsSeries(mainBuffer, true);
   ArraySetAsSeries(signalBuffer, true);
   
   CopyBuffer(handleMACD, 0, 0, 1, mainBuffer);
   CopyBuffer(handleMACD, 1, 0, 1, signalBuffer);
   
   main = mainBuffer[0];
   signal = signalBuffer[0];
}

double GetATR()
{
   if(handleATR == INVALID_HANDLE)
      return 0;
      
   double buffer[];
   ArraySetAsSeries(buffer, true);
   CopyBuffer(handleATR, 0, 0, 1, buffer);
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!InpShowDashboard)
      return;
      
   string prefix = "XAU_DASH_";
   int x = 20, y = 30;
   int lineHeight = 20;
   color textColor = clrWhite;
   
   // Background
   ObjectCreate(0, prefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XSIZE, 280);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YSIZE, 300);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BGCOLOR, C'20,20,30');
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_COLOR, clrGold);
   
   // Title
   CreateLabel(prefix + "TITLE", x, y, "🤖 XAU PRO AGENT", clrGold, 12); y += lineHeight + 10;
   CreateLabel(prefix + "LINE1", x, y, "━━━━━━━━━━━━━━━━━", clrGray, 10); y += lineHeight;
   
   // Status
   color statusColor = (agentStatus == "TRADE EXECUTED") ? clrLime : 
                       (agentStatus == "RISK LIMIT HIT") ? clrRed : clrYellow;
   CreateLabel(prefix + "STATUS", x, y, "Status: " + agentStatus, statusColor, 10); y += lineHeight;
   
   // Mode
   CreateLabel(prefix + "MODE", x, y, "Mode: " + EnumToString(InpAgentMode), clrCyan, 10); y += lineHeight;
   
   // Trend
   string trendStr = trendBullish ? "🔼 BULLISH" : "🔽 BEARISH";
   color trendColor = trendBullish ? InpBullColor : InpBearColor;
   CreateLabel(prefix + "TREND", x, y, "Trend: " + trendStr, trendColor, 10); y += lineHeight;
   
   // Structure
   string structStr = bosConfirmed ? "BOS ✓" : "BOS ✗";
   structStr += chochConfirmed ? " | CHoCH ✓" : " | CHoCH ✗";
   CreateLabel(prefix + "STRUCT", x, y, "Structure: " + structStr, clrWhite, 10); y += lineHeight;
   
   // Fibonacci
   CreateLabel(prefix + "FIB", x, y, StringFormat("Fib Range: %.5f - %.5f", currentFibLow, currentFibHigh), clrWhite, 10); y += lineHeight;
   
   // Order Blocks
   int activeOBs = 0;
   for(int i = 0; i < ArraySize(orderBlocks); i++)
      if(!orderBlocks[i].mitigated) activeOBs++;
   CreateLabel(prefix + "OB", x, y, "Order Blocks: " + IntegerToString(activeOBs) + " active", clrOrange, 10); y += lineHeight;
   
   // FVGs
   int activeFVGs = 0;
   for(int i = 0; i < ArraySize(fairValueGaps); i++)
      if(!fairValueGaps[i].filled) activeFVGs++;
   CreateLabel(prefix + "FVG", x, y, "Fair Value Gaps: " + IntegerToString(activeFVGs) + " open", clrMagenta, 10); y += lineHeight;
   
   // Liquidity
   CreateLabel(prefix + "LIQ", x, y, "Liquidity Pools: " + IntegerToString(ArraySize(liquidityPools)), clrAqua, 10); y += lineHeight;
   
   CreateLabel(prefix + "LINE2", x, y, "━━━━━━━━━━━━━━━━━", clrGray, 10); y += lineHeight;
   
   // Daily Stats
   CreateLabel(prefix + "TRADES", x, y, StringFormat("Daily Trades: %d / %d", dailyTrades, InpMaxDailyTrades), clrWhite, 10); y += lineHeight;
   
   double currentEquity = account.Equity();
   double dailyPnLPercent = (currentEquity - startingEquity) / startingEquity * 100;
   color pnlColor = dailyPnLPercent >= 0 ? clrLime : clrRed;
   CreateLabel(prefix + "PNL", x, y, StringFormat("Daily P&L: %.2f%%", dailyPnLPercent), pnlColor, 10); y += lineHeight;
   
   double dd = (peakEquity - currentEquity) / peakEquity * 100;
   CreateLabel(prefix + "DD", x, y, StringFormat("Drawdown: %.2f%% / %.2f%%", dd, InpMaxTotalDD), clrWhite, 10);
}

//+------------------------------------------------------------------+
//| Create Label Helper                                              |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Levels on Chart                                   |
//+------------------------------------------------------------------+
void DrawFibonacciLevels()
{
   string prefix = "XAU_FIB_";
   
   // Delete old levels
   ObjectsDeleteAll(0, prefix);
   
   datetime startTime = iTime(_Symbol, PERIOD_CURRENT, swingHighBar > swingLowBar ? swingHighBar : swingLowBar);
   datetime endTime = TimeCurrent();
   
   // Draw main levels
   for(int i = 0; i < 5; i++)
   {
      string name = prefix + DoubleToString(fibLevels[i] * 100, 1);
      ObjectCreate(0, name, OBJ_TREND, 0, startTime, fibRetracements[i], endTime, fibRetracements[i]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TEXT, DoubleToString(fibLevels[i] * 100, 1) + "%");
   }
}

//+------------------------------------------------------------------+
//| Draw Order Block Zones                                           |
//+------------------------------------------------------------------+
void DrawOrderBlockZones()
{
   string prefix = "XAU_OB_";
   
   // Delete old zones
   ObjectsDeleteAll(0, prefix);
   
   for(int i = 0; i < ArraySize(orderBlocks); i++)
   {
      if(orderBlocks[i].mitigated)
         continue;
         
      string name = prefix + IntegerToString(i);
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, orderBlocks[i].time, orderBlocks[i].high, 
                   TimeCurrent(), orderBlocks[i].low);
      ObjectSetInteger(0, name, OBJPROP_COLOR, orderBlocks[i].bullish ? InpBullColor : InpBearColor);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   }
}

//+------------------------------------------------------------------+
