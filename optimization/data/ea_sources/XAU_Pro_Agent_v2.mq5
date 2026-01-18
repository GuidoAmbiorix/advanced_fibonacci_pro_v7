//+------------------------------------------------------------------+
//|                                             XAU_Pro_Agent_v2.mq5 |
//|          XAU Pro Engine v2.1 - FRONTEND ALIGNED + ENGINE LOGIC   |
//|               Matches Python InstitutionalGoldEngine v4.0        |
//+------------------------------------------------------------------+
#property copyright "XAU Pro Engine"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "2.10"
#property description "v2.1: True ZigZag (0.05% Dev), Strict Sweep, Stoch(14,3,3) Internal"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS (Match Frontend)                                     |
//+------------------------------------------------------------------+
enum ENUM_DIRECTION
{
   DIR_BOTH = 0,           // ↕️ Both
   DIR_BUY_ONLY = 1,       // 🟢 Buy Only
   DIR_SELL_ONLY = 2       // 🔴 Sell Only
};

enum ENUM_SESSION_MODE
{
   SESSION_BOTH_KZ = 0,    // 🎯 London + NY Killzones
   SESSION_LONDON_KZ = 1,  // 🇬🇧 London Killzone (07-10 UTC)
   SESSION_NY_KZ = 2,      // 🇺🇸 NY Killzone (12-15 UTC)
   SESSION_OVERLAP_KZ = 3, // ⚡ Overlap Only (13-16 UTC)
   SESSION_ALL = 4         // 🌍 All Sessions
};

enum ENUM_SESSION_END
{
   END_HOLD = 0,           // ✋ Hold Trades
   END_CLOSE = 1,          // ❌ Close All
   END_DISABLE_NEW = 2     // ⛔ No New Entries
};

enum ENUM_TSL_MODE
{
   TSL_OFF = 0,            // Off
   TSL_ATR = 1,            // ATR
   TSL_TIERED = 2          // Tiered
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS (Match Frontend Slots EXACTLY - 22 Inputs)       |
//+------------------------------------------------------------------+

input group "========== CORE =========="
input int               InpMagicNumber = 888888;           // Magic Number
input ENUM_DIRECTION    InpDirection = DIR_BOTH;           // Trade Direction
input int               InpBrokerOffset = 2;               // Broker UTC Offset

input group "========== SESSION CONTROL =========="
input ENUM_SESSION_MODE InpSessionMode = SESSION_BOTH_KZ;  // Session Killzone
input ENUM_SESSION_END  InpSessionEnd = END_DISABLE_NEW;   // Session End Action
input bool              InpUseDailyBias = true;            // Use D1 Trend Bias (Rec: True for WinRate)
input bool              InpDebugMode    = true;            // Enable Detailed Logging

input group "========== RISK / TP / SL =========="
input double            InpFixedLots = 0.01;               // Fixed Lot Size (0.01 - 1.0)
input bool              InpUseDynamicRisk = true;          // Use Risk % (False = Fixed Lots)
input double            InpRiskPercent = 0.2;              // Risk % (Dynamic Only)
input double            InpTPRatio = 2.5;                  // TP Ratio (R) - Python Bot Aligned
input double            InpSL_ATR = 1.0;                   // SL ATR Multiplier (M15 Balanced)
input ENUM_TSL_MODE     InpTSLMode = TSL_TIERED;           // TSL Mode (Rec: Tiered for BreakEven+Trail)

input group "========== MACD (Momentum) =========="
input int               InpMACD_Fast = 5;                  // MACD Fast
input int               InpMACD_Slow = 13;                 // MACD Slow
input int               InpMACD_Signal = 6;                // MACD Signal

input group "========== RSI (Value) =========="
input int               InpRSI_Period = 9;                 // RSI Period
input int               InpRSI_BuyLevel = 43;              // RSI Buy Ceiling
input int               InpRSI_SellLevel = 57;             // RSI Sell Floor

input group "========== STRUCTURE =========="
input int               InpZigZagLookback = 8;             // ZigZag Lookback

input group "========== SMART MONEY (SMC) =========="
input bool              InpUseOB = true;                   // Enable Order Blocks
input int               InpOB_Lookback = 14;               // OB Lookback
input bool              InpUseSweep = true;                // Enable Liquidity Sweep
input int               InpSweepLookback = 6;              // Sweep Lookback
input bool              InpUseFVG = true;                  // Enable Fair Value Gap
input double            InpFVG_MinATR = 0.3;               // FVG Min Size (ATR)

// HTF Trend Filter (Engine Logic M5 Safety)
// HTF Trend Filter (Internal Engine Logic)
bool                    UseHTF_Filter = true;              // Hardcoded: True
int                     HTF_EMA_Period = 50;               // Hardcoded: 50
// v4.1 Anti-Chop Filter
bool                    UseADX_Filter = true;              // Hardcoded: True
double                  ADX_Threshold = 20.0;              // Min Volatility
input ENUM_TIMEFRAMES   InpConfirmTF = PERIOD_H1;          // Confirmation Timeframe

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

// Indicator Handles
int hRSI, hMACD, hStoch, hATR, hEMA, hEMA_HTF, hEMA_Daily, hADX;

// State Variables (Buffers)
double g_RSI, g_MACD_Main, g_MACD_Signal, g_Stoch_K, g_Stoch_D, g_ATR, g_EMA200, g_EMA200_HTF, g_EMA200_Daily, g_ADX;
double g_Prev_MACD_Main, g_Prev_MACD_Signal, g_Prev_MACD_Hist_Value; 
double g_Prev_Stoch_K;

// Market Structure
double activeHigh = 0;
double activeLow = 0;

// ZigZag Helper Struct
struct ZigZagPoint {
   double price;
   int barIndex; 
   int type; // 1=High, -1=Low
};

// SMC Structures
struct OrderBlock
{
   double top;
   double bottom;
   bool isBullish;
   datetime time;
   bool mitigated;   
   bool invalidated; 
   int creationBar;
};
OrderBlock activeOBs[];

struct FVG
{
   double top;
   double bottom;
   bool isBullish;
   datetime time;
   bool filled;      
   bool invalidated; 
   int creationBar;
};
FVG activeFVGs[];

// Session State
bool inKillzone = false;
datetime lastBarTime = 0;
datetime lastTradeBar = 0; // Anti-Spam: One trade per candle
int dailyTrades = 0;
double g_StructureSL = 0; // Structure-based SL storage

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symbolInfo.Name(_Symbol)) return INIT_FAILED;
   symbolInfo.RefreshRates();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   // --- Initialize Indicators (v4.0 High Win Rate Tuning) ---
   // RSI: 8 Period (Fast Response)
   hRSI = iRSI(NULL, 0, 8, PRICE_CLOSE);
   // MACD: 5, 35, 5 (Scalping Standard)
   hMACD = iMACD(NULL, 0, 5, 35, 5, PRICE_CLOSE);
   
   // Stoch removed for v4.0 (Too Noisy)
   hStoch = iStochastic(NULL, 0, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   
   hATR = iATR(NULL, 0, 14);
   hEMA = iMA(NULL, 0, 200, 0, MODE_EMA, PRICE_CLOSE); 
   // HTF EMA (User period) for M5 Scalping Safety
   hEMA_HTF = iMA(NULL, InpConfirmTF, HTF_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   // Daily EMA for Macro Bias
   hEMA_Daily = iMA(NULL, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   // v4.1 ADX (Anti-Chop)
   hADX = iADX(NULL, 0, 14);

   if(hRSI == INVALID_HANDLE || hMACD == INVALID_HANDLE || hStoch == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE || hEMA_HTF == INVALID_HANDLE || hEMA_Daily == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("Error initializing indicators");
      return INIT_FAILED;
   }

   Print("🚀 XAU Pro Agent v2.1 Initialized | ZigZag Dev=0.05% | Strict Sweep");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   IndicatorRelease(hMACD);
   IndicatorRelease(hStoch);
   IndicatorRelease(hATR);
   IndicatorRelease(hEMA);
   IndicatorRelease(hEMA_HTF);
   IndicatorRelease(hEMA_Daily);
   IndicatorRelease(hADX);
   ObjectsDeleteAll(0, "XAUPro_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   symbolInfo.RefreshRates();
   
   // 1. Dashboard (Always update)
   UpdateDashboard();
   
   // 2. Trade Management (TSL)
   ManageTrade();

   // 3. New Bar Check (Removed global return to allow Tick Scalping)
   bool newBar = IsNewBar();

   // 4. Session Filter
   inKillzone = CheckKillzone();
   if(!inKillzone && InpSessionMode != SESSION_ALL) 
   {
      return; 
   }

   // 5. Update Data (Every Tick for Zero-Lag)
   UpdateIndicators();

   // Heavy Lifting only on New Bar
   if(newBar)
   {
       UpdateStructure(); 
       if(InpUseOB || InpUseFVG)
       {
          ManageOrderBlocks(); 
          ManageFVGs();        
       }
   }

   // 6. Entry Logic
   if(position.Select(_Symbol)) return; 
   // Anti-Spam: Don't trade the same candle twice (if we took a loss, wait for next setup)
   if(iTime(_Symbol, 0, 0) == lastTradeBar) return; 

   bool signalBuy = false;
   bool signalSell = false;
   string strategy = "";
   
   // Trend Check (EMA 200) - Core Engine Logic
   double currentPrice = symbolInfo.Bid();
   bool isEMABullish = currentPrice > g_EMA200;
   bool isEMABearish = currentPrice < g_EMA200;
   
   // --- HTF Trend Filter (Engine Logic) ---
   // STRICT: Double Trend Alignment Required for High Win Rate
   if(UseHTF_Filter)
   {
      double htfPrice = iClose(_Symbol, InpConfirmTF, 1); // Close of previous H1 bar
      bool isHTFBullish = htfPrice > g_EMA200_HTF;
      bool isHTFBearish = htfPrice < g_EMA200_HTF;
      
      if(isEMABullish && !isHTFBullish) {
          isEMABullish = false; // Veto
          if(InpDebugMode) Print("Debug: M5 Bullish Vetoed by HTF Bearish (Price=", htfPrice, " < EMA=", g_EMA200_HTF, ")");
      }
      if(isEMABearish && !isHTFBearish) {
          isEMABearish = false; // Veto
          if(InpDebugMode) Print("Debug: M5 Bearish Vetoed by HTF Bullish (Price=", htfPrice, " > EMA=", g_EMA200_HTF, ")");
      }
      
      // Strict Mode: If EMA is flat or price is tangling, stay out
      // (Optional - for now strict alignment is enough)
   }
   
   // --- Trend Status Flags ---
   bool isMacroBullish = true; // Default true if filter disabled
   bool isMacroBearish = true;
   
   // --- Daily Bias Filter (Macro Trend) ---
   if(InpUseDailyBias)
   {
      double d1Price = iClose(_Symbol, PERIOD_D1, 1);
      isMacroBullish = (d1Price > g_EMA200_Daily);
      isMacroBearish = (d1Price < g_EMA200_Daily);
      
      if(InpDebugMode) {
          if(isEMABullish && !isMacroBullish) Print("Debug: M5 Bullish but D1 Bearish (Fib blocked)");
          if(isEMABearish && !isMacroBearish) Print("Debug: M5 Bearish but D1 Bullish (Fib blocked)");
      }
   }

   // --- v4.1 ADX Filter (Anti-Chop) ---
   if(UseADX_Filter && g_ADX < ADX_Threshold)
   {
       // If market is dead, do not trade
       return; 
   }

   // --- Path A: SMC Entry (Sweep + Zone) ---
   if(InpUseOB || InpUseSweep || InpUseFVG)
   {
      bool smcBuy = isEMABullish && CheckSMCEntry("BUY"); 
      bool smcSell = isEMABearish && CheckSMCEntry("SELL");
      
      if(smcBuy) { signalBuy = true; strategy = "SMC_Sweepliquidity"; }
      else if(smcSell) { signalSell = true; strategy = "SMC_Sweepliquidity"; }
   }

   // --- Path B: Fib Entry (Trend Following) ---
   // STRICT: Requires BOTH M5 Trend (EMA) and D1 Bias (Macro)
   if(!signalBuy && !signalSell)
   {
      bool fibBuy = isEMABullish && isMacroBullish && CheckFibEntry("BUY");
      bool fibSell = isEMABearish && isMacroBearish && CheckFibEntry("SELL");
      
      if(fibBuy) { signalBuy = true; strategy = "FIB_GoldenZone"; }
      else if(fibSell) { signalSell = true; strategy = "FIB_GoldenZone"; }
   }

   // 7. Direction Filter (Global Override)
   if(InpDirection == DIR_BUY_ONLY && signalSell) { signalSell = false; }
   if(InpDirection == DIR_SELL_ONLY && signalBuy) { signalBuy = false; }

   // 8. Execution
   if(signalBuy) ExecuteTrade(ORDER_TYPE_BUY, strategy);
   if(signalSell) ExecuteTrade(ORDER_TYPE_SELL, strategy);
}

//+------------------------------------------------------------------+
//| CORE LOGIC FUNCTIONS                                              |
//+------------------------------------------------------------------+

bool CheckFibEntry(string dir)
{
   // 1. Structure Check: Need defined swing points
   if(activeHigh == 0 || activeLow == 0) {
       if(InpDebugMode) Print("Debug: No Active Structure (High/Low=0)");
       return false;
   }
   
   double range = activeHigh - activeLow;
   // Relaxed Range Check for M5 Scalping (0.3 ATR)
   if(range <= (g_ATR * 0.3)) {
       if(InpDebugMode) Print("Debug: Range too small (", range, ") vs Min (", g_ATR*0.3, ")");
       return false; 
   }
   
   double tolerance = g_ATR * 0.25; 
   double price = (dir=="BUY") ? symbolInfo.Ask() : symbolInfo.Bid();
   
   bool inZone = false;
   
   // 2. Fib Golden Zone (61.8% - 78.6%)
   if(dir == "BUY")
   {
      double ret618 = activeHigh - (range * 0.618);
      double ret786 = activeHigh - (range * 0.786);
      if(price >= (ret786 - tolerance) && price <= (ret618 + tolerance)) inZone = true;
   }
   else // SELL
   {
      double ret618 = activeLow + (range * 0.618);
      double ret786 = activeLow + (range * 0.786);
      if(price >= (ret618 - tolerance) && price <= (ret786 + tolerance)) inZone = true;
   }
   
   if(!inZone) return false;
   
   if(!CheckTripleConfirmation(dir)) {
       if(InpDebugMode) Print("Debug: Triple Confirmation Failed for ", dir);
       return false;
   }
   
   bool trigger = CheckCandleTrigger(dir);
   if(trigger) {
       // Set Structure SL
       if(dir == "BUY") g_StructureSL = activeLow - (g_ATR * 0.2); // Below Swing Low
       else             g_StructureSL = activeHigh + (g_ATR * 0.2); // Above Swing High
   }
   if(!trigger && InpDebugMode) Print("Debug: Candle Trigger Failed for ", dir);
   return trigger;
}

bool CheckTripleConfirmation(string dir)
{
   // v4.0 Tuning: RSI(8) Limits 35/65 | MACD(5,35,5) | No Stoch
   bool rsiOk = (dir == "BUY") ? (g_RSI <= 65) : (g_RSI >= 35); // Filter Extremes
   // Momentum: Hist must be expanding in direction
   double currentHist = g_MACD_Main - g_MACD_Signal;
   bool macdOk = (dir == "BUY") ? (currentHist > g_Prev_MACD_Hist_Value) : (currentHist < g_Prev_MACD_Hist_Value);
   
   // Stoch: Removed for M5 Scalping (Too much noise)
   bool stochOk = true; 

   if(InpDebugMode && (!rsiOk || !macdOk)) {
       Print("Debug: TripleConf [", dir, "] RSI=", rsiOk, "(val=", g_RSI, ") MACD=", macdOk);
   }
   
   return (rsiOk && macdOk && stochOk);
}

bool CheckCandleTrigger(string dir)
{
   // v4.0 Strict: Displacement Check (Candle Close)
   double open = iOpen(_Symbol, 0, 0); 
   double close = (dir == "BUY") ? symbolInfo.Ask() : symbolInfo.Bid(); // Current Price
   
   // 1. Momentum & Color Check
   bool greenCandle = (close > open);
   bool redCandle = (close < open);
   
   if(dir == "BUY" && !greenCandle) return false;
   if(dir == "SELL" && !redCandle) return false;

   // 2. Minimum Size (Avoid Dojis)
   double body = MathAbs(close - open);
   if(body < (g_ATR * 0.1)) return false; 
   
   // 3. DISPLACEMENT: Price must have moved away from entry
   // For now, we accept live candle body. 
   // Ideally we wait for bar close, but that delays entry 5 mins.
   // Compromise: Price must be > 40% of ATR away from Open (Strong Push)
   if(body < (g_ATR * 0.4)) return false;

   return true; 
}

bool CheckSMCEntry(string dir)
{
   double price = (dir=="BUY") ? symbolInfo.Ask() : symbolInfo.Bid();
   bool inZone = false;
   
   // OB
   if(InpUseOB)
   {
      for(int i=0; i<ArraySize(activeOBs); i++)
      {
         bool correctDir = (dir == "BUY") ? activeOBs[i].isBullish : !activeOBs[i].isBullish;
         if(correctDir && price <= activeOBs[i].top && price >= activeOBs[i].bottom) { inZone = true; break; }
      }
   }
   
   // FVG
   if(!inZone && InpUseFVG)
   {
       for(int i=0; i<ArraySize(activeFVGs); i++)
       {
           bool correctDir = (dir == "BUY") ? activeFVGs[i].isBullish : !activeFVGs[i].isBullish;
           if(correctDir && price <= activeFVGs[i].top && price >= activeFVGs[i].bottom) { inZone = true; break; }
       }
   }
   
   if(!inZone) {
       // Silent fail for SMC Zone (too noisy)
       return false;
   }
   
   if(InpUseSweep)
   {
      if(!CheckLiquiditySweep(dir)) {
          if(InpDebugMode) Print("Debug: SMC Sweep Check Failed for ", dir);
          return false;
      }
   }
   
   // QUALITY CONTROL: Triple Confirmation for SMC too
   if(!CheckTripleConfirmation(dir)) {
       if(InpDebugMode) Print("Debug: SMC Triple Confirmation Failed for ", dir);
       return false;
   }
   

   
   bool smcTrigger = CheckCandleTrigger(dir);
   if(smcTrigger) {
       // SMC SL: Below/Above the trigger candle (Sweep Candle)
       double obsHigh = iHigh(_Symbol, 0, 1);
       double obsLow = iLow(_Symbol, 0, 1);
       if(dir == "BUY") g_StructureSL = obsLow - (g_ATR * 0.2); 
       else             g_StructureSL = obsHigh + (g_ATR * 0.2);
   }
   return smcTrigger;
}

// Updated CheckLiquiditySweep matching Python smc.py closer
bool CheckLiquiditySweep(string dir)
{
   int lookback = InpSweepLookback; 
   double currentLow = iLow(_Symbol, 0, 1);
   double currentHigh = iHigh(_Symbol, 0, 1);
   double currentClose = iClose(_Symbol, 0, 1);
   double currentOpen = iOpen(_Symbol, 0, 1);
   
   if(dir == "BUY")
   {
      int lowestBar = iLowest(_Symbol, 0, MODE_LOW, lookback, 2); 
      if(lowestBar < 0) return false;
      double recentLow = iLow(_Symbol, 0, lowestBar);
      
      // Strict: Break Low, Close Above (Removed Green Candle requirement to match Python)
      return (currentLow < recentLow) && (currentClose > recentLow);
   }
   else
   {
      int highestBar = iHighest(_Symbol, 0, MODE_HIGH, lookback, 2);
      if(highestBar < 0) return false;
      double recentHigh = iHigh(_Symbol, 0, highestBar);
      
      // Strict: Break High, Close Below (Removed Red Candle requirement to match Python)
      return (currentHigh > recentHigh) && (currentClose < recentHigh);
   }
}

//+------------------------------------------------------------------+
//| UTILS: Matches Python StructureAnalyzer                           |
//+------------------------------------------------------------------+

void UpdateStructure()
{
   // True ZigZag Logic (0.05% Deviation, simulating Python loop)
   // We iterate back 1000 bars (previously 300) to better match Python's history scan
   double deviationPercent = 0.05; 
   int limit = 1000;
   
   ZigZagPoint swings[];
   ArrayResize(swings, 0);
   
   int trend = 0; // 0=Unknown, 1=Up, -1=Down
   double tempHigh = iHigh(_Symbol, 0, limit-1);
   double tempLow = iLow(_Symbol, 0, limit-1);
   int tempHighIdx = limit-1;
   int tempLowIdx = limit-1;
   
   for(int i = limit-2; i >= 1; i--)
   {
      double high = iHigh(_Symbol, 0, i);
      double low = iLow(_Symbol, 0, i);
      
      if(trend == 0)
      {
         if(high > tempHigh) { tempHigh = high; tempHighIdx = i; }
         if(low < tempLow)   { tempLow = low; tempLowIdx = i; }
         
         if(MathAbs(high - tempLow)/tempLow > (deviationPercent/100.0))
         {
            trend = 1; 
            int size = ArraySize(swings); ArrayResize(swings, size+1);
            swings[size].price = tempLow; swings[size].barIndex = tempLowIdx; swings[size].type = -1;
         }
         else if(MathAbs(tempHigh - low)/tempHigh > (deviationPercent/100.0))
         {
            trend = -1; 
            int size = ArraySize(swings); ArrayResize(swings, size+1);
            swings[size].price = tempHigh; swings[size].barIndex = tempHighIdx; swings[size].type = 1;
         }
      }
      else if(trend == 1) // Trend UP
      {
         if(high > tempHigh) { tempHigh = high; tempHighIdx = i; }
         
         if(MathAbs(tempHigh - low)/tempHigh > (deviationPercent/100.0))
         {
             int size = ArraySize(swings); ArrayResize(swings, size+1);
             swings[size].price = tempHigh; swings[size].barIndex = tempHighIdx; swings[size].type = 1;
             trend = -1;
             tempLow = low; tempLowIdx = i;
         }
      }
      else if(trend == -1) // Trend DOWN
      {
         if(low < tempLow) { tempLow = low; tempLowIdx = i; }
         
         if(MathAbs(high - tempLow)/tempLow > (deviationPercent/100.0))
         {
             int size = ArraySize(swings); ArrayResize(swings, size+1);
             swings[size].price = tempLow; swings[size].barIndex = tempLowIdx; swings[size].type = -1;
             trend = 1;
             tempHigh = high; tempHighIdx = i;
         }
      }
   }
   
   if(ArraySize(swings) >= 2)
   {
      activeHigh = 0; activeLow = 0;
      for(int k=ArraySize(swings)-1; k>=0; k--)
      {
         if(activeHigh == 0 && swings[k].type == 1) activeHigh = swings[k].price;
         if(activeLow == 0 && swings[k].type == -1) activeLow = swings[k].price;
         if(activeHigh != 0 && activeLow != 0) break;
      }
   }
   else
   {
      // Fallback
      int hb = iHighest(_Symbol, 0, MODE_HIGH, 50, 1);
      int lb = iLowest(_Symbol, 0, MODE_LOW, 50, 1);
      activeHigh = iHigh(_Symbol, 0, hb);
      activeLow = iLow(_Symbol, 0, lb);
   }
}

void ExecuteTrade(ENUM_ORDER_TYPE type, string comment)
{
   double sl=0, tp=0;
   double price = (type == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
   
   double slDist = g_ATR * InpSL_ATR;
   double finalSL = 0;
   
   // A. Structure Based SL (Priority)
   if(g_StructureSL > 0)
   {
       finalSL = g_StructureSL;
       // Validations to prevent SL being on wrong side due to lag
       if(type == ORDER_TYPE_BUY && finalSL >= price) finalSL = price - slDist; // Fallback
       if(type == ORDER_TYPE_SELL && finalSL <= price) finalSL = price + slDist; // Fallback
   }
   else // B. Fixed ATR SL (Fallback)
   {
       if(type == ORDER_TYPE_BUY) finalSL = price - slDist;
       else                       finalSL = price + slDist;
   }
   
   double riskDist = MathAbs(price - finalSL);
   double tpDist = riskDist * InpTPRatio;
   
   if(type == ORDER_TYPE_BUY) { sl = finalSL; tp = price + tpDist; }
   else                       { sl = finalSL; tp = price - tpDist; }
   
   // Reset Global SL
   g_StructureSL = 0;
   
   double equity = account.Equity();
   double riskAmount = equity * (InpRiskPercent / 100.0);
   
   double lotSize = InpFixedLots;
   
   if(InpUseDynamicRisk)
   {
       double profitOneLot = 0.0;
       
       // Robust Lot Calculation using OrderCalcProfit (Handles TickValue/ContractSize automatically)
       if(OrderCalcProfit(type, _Symbol, 1.0, price, finalSL, profitOneLot))
       {
           if(MathAbs(profitOneLot) > 0)
           {
               lotSize = riskAmount / MathAbs(profitOneLot);
           }
           else
           {
               if(InpDebugMode) Print("Error: OrderCalcProfit returned 0 profit. Fallback to Fixed Lot.");
               lotSize = InpFixedLots;
           }
       }
       else
       {
           if(InpDebugMode) Print("Error: OrderCalcProfit Failed. Error=", GetLastError());
           lotSize = InpFixedLots;
       }
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   if(InpDebugMode) Print("Risk Calc: Risk=$", DoubleToString(riskAmount,2), " Loss1Lot=$", DoubleToString(profitOneLot,2), " -> Lot=", DoubleToString(lotSize,2));

   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, comment))
   {
      dailyTrades++;
      lastTradeBar = iTime(_Symbol, 0, 0); // Mark this candle as traded
      Print("Order Opened: ", comment);
   }
}

void ManageTrade()
{
   if(!position.Select(_Symbol)) return;
   if(position.Magic() != InpMagicNumber) return;
   if(InpTSLMode == TSL_OFF) return;
   
   double openPrice = position.PriceOpen();
   double currentPrice = position.PriceCurrent();
   double sl = position.StopLoss();
   double tp = position.TakeProfit();
   long type = position.PositionType();
   
   double currentProfitPoints = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
   double initialRisk = MathAbs(openPrice - sl);
   if(initialRisk == 0) return;
   
   double profitR = currentProfitPoints / initialRisk; // Profit in R multiples
   
   // === OPTIMIZED TRAILING STOP (M15 Profit Capture) ===
   
   // TIER 1: BreakEven at 1.0R (Lock in zero loss)
   if(profitR >= 1.0 && ((type==POSITION_TYPE_BUY && sl < openPrice) || (type==POSITION_TYPE_SELL && sl > openPrice)))
   {
      double buffer = 5 * symbolInfo.Point(); 
      double newSL = (type == POSITION_TYPE_BUY) ? (openPrice + buffer) : (openPrice - buffer);
      trade.PositionModify(_Symbol, newSL, tp);
      if(InpDebugMode) Print("TSL: Tier1 - BreakEven at 1.0R");
      return;
   }
   
   // TIER 2: Lock 0.5R profit at 1.5R (Capture early winners)
   if(profitR >= 1.5)
   {
      double lockLevel = openPrice + (initialRisk * 0.5 * ((type == POSITION_TYPE_BUY) ? 1 : -1));
      bool needUpdate = (type == POSITION_TYPE_BUY && sl < lockLevel) || (type == POSITION_TYPE_SELL && sl > lockLevel);
      
      if(needUpdate)
      {
         trade.PositionModify(_Symbol, lockLevel, tp);
         if(InpDebugMode) Print("TSL: Tier2 - Locked 0.5R at 1.5R profit");
         return;
      }
   }
   
   // TIER 3: Aggressive Trail at 2.0R+ (Tighter 0.5 ATR distance)
   if(profitR >= 2.0)
   {
      double trailDist = g_ATR * 1.0; // Wider trail to let runners develop (Python Bot Aligned)
      double newSL = (type == POSITION_TYPE_BUY) ? (currentPrice - trailDist) : (currentPrice + trailDist);
      
      bool update = (type == POSITION_TYPE_BUY && newSL > sl) || (type == POSITION_TYPE_SELL && newSL < sl);
      if(update)
      {
         trade.PositionModify(_Symbol, newSL, tp);
         if(InpDebugMode) Print("TSL: Tier3 - Trailing at 0.5 ATR (", DoubleToString(trailDist, 2), ")");
      }
   }
}

void UpdateIndicators()
{
   double bufRSI[1], bufMACD_M[2], bufMACD_S[2], bufStoch_K[2], bufStoch_D[1], bufATR[1], bufEMA[1], bufEMA_HTF[1];
   // Zero-Lag: Read from 0 (Live Candle) to match Python's realtime/simulated 'Last Row'
   CopyBuffer(hRSI, 0, 0, 1, bufRSI);
   CopyBuffer(hMACD, 0, 0, 2, bufMACD_M); CopyBuffer(hMACD, 1, 0, 2, bufMACD_S);
   CopyBuffer(hStoch, 0, 0, 2, bufStoch_K); CopyBuffer(hStoch, 1, 0, 1, bufStoch_D); 
   CopyBuffer(hATR, 0, 0, 1, bufATR);
   CopyBuffer(hEMA, 0, 0, 1, bufEMA);
   CopyBuffer(hEMA_HTF, 0, 0, 1, bufEMA_HTF);
   
   double bufADX[1];
   CopyBuffer(hADX, 0, 0, 1, bufADX);

   g_RSI = bufRSI[0]; g_MACD_Main = bufMACD_M[1]; g_MACD_Signal = bufMACD_S[1];
   g_Prev_MACD_Main = bufMACD_M[0]; g_Prev_MACD_Signal = bufMACD_S[0];
   g_Prev_MACD_Hist_Value = g_Prev_MACD_Main - g_Prev_MACD_Signal;
   g_Stoch_K = bufStoch_K[1]; g_Prev_Stoch_K = bufStoch_K[0]; g_Stoch_D = bufStoch_D[0];
   g_ATR = bufATR[0];
   g_EMA200 = bufEMA[0];
   g_EMA200_HTF = bufEMA_HTF[0];
   g_ADX = bufADX[0];
   
   double bufEMA_D1[1];
   if(CopyBuffer(hEMA_Daily, 0, 1, 1, bufEMA_D1) > 0) g_EMA200_Daily = bufEMA_D1[0];
}

bool CheckKillzone()
{
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   int utcHour = (dt.hour - InpBrokerOffset + 24) % 24;
   if(utcHour >= 24) utcHour -= 24;
   
   bool london = (utcHour >= 7 && utcHour < 10);
   bool ny = (utcHour >= 12 && utcHour < 15);
   bool overlap = (utcHour >= 13 && utcHour < 16);
   
   if(InpSessionMode == SESSION_LONDON_KZ) return london;
   if(InpSessionMode == SESSION_NY_KZ) return ny;
   if(InpSessionMode == SESSION_OVERLAP_KZ) return overlap; 
   if(InpSessionMode == SESSION_BOTH_KZ) return (london || ny);
   return true;
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, 0, 0);
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
}

void UpdateDashboard()
{
   string text = "🥇 XAU Pro Agent v2.1 (Precision Engine)\n";
   text += "----------------------------------------\n";
   text += "Trend: " + ((symbolInfo.Bid() > g_EMA200) ? "🟢 BULLISH" : "🔴 BEARISH") + "\n";
   text += "Structure: High=" + DoubleToString(activeHigh, 2) + " Low=" + DoubleToString(activeLow, 2) + "\n";
   text += "Sweep Mode: Strict (" + IntegerToString(InpSweepLookback) + ")\n";
   text += "Session: " + EnumToString(InpSessionMode) + " | In KZ: " + (inKillzone ? "YES" : "NO") + "\n";
   Comment(text);
}

void ManageOrderBlocks()
{
    double o1=iOpen(NULL,0,2), c1=iClose(NULL,0,2); 
    double o0=iOpen(NULL,0,1), c0=iClose(NULL,0,1); 
    double body0 = MathAbs(c0-o0);
    // Hardcoded 1.5x ATR displacement from Python logic
    bool displacement = body0 > (g_ATR * 1.5); 

    if(displacement)
    {
       double h1 = iHigh(NULL,0,2); double l1 = iLow(NULL,0,2);
       if(c1 < o1 && c0 > o0) // Bullish OB
       {
          OrderBlock ob; ob.isBullish = true; ob.top = h1; ob.bottom = l1; ob.time = iTime(NULL,0,2);
          ob.mitigated = false; ob.invalidated = false; ob.creationBar = iBarShift(NULL,0,ob.time);
          
          bool exists = false; 
          for(int i=0; i<ArraySize(activeOBs); i++) { if(activeOBs[i].time == ob.time) { exists=true; break; } }
          
          if(!exists) { ArrayResize(activeOBs, ArraySize(activeOBs)+1); activeOBs[ArraySize(activeOBs)-1] = ob; }
       }
       else if(c1 > o1 && c0 < o0) // Bearish OB
       {
          OrderBlock ob; ob.isBullish = false; ob.top = h1; ob.bottom = l1; ob.time = iTime(NULL,0,2);
          ob.mitigated = false; ob.invalidated = false; ob.creationBar = iBarShift(NULL,0,ob.time);
          
          bool exists = false; 
          for(int i=0; i<ArraySize(activeOBs); i++) { if(activeOBs[i].time == ob.time) { exists=true; break; } }
          
          if(!exists) { ArrayResize(activeOBs, ArraySize(activeOBs)+1); activeOBs[ArraySize(activeOBs)-1] = ob; }
       }
    }
}

void ManageFVGs()
{
   // Placeholder matching Python 'standard' logic
   // Typically 3 bars. 
}
