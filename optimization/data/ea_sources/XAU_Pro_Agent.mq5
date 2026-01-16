//+------------------------------------------------------------------+
//|                                                 XAU_Pro_Agent.mq5 |
//|          XAU Pro Engine v7.0 - FRONTEND SLOTS ALIGNED            |
//|            SMC + EMA200 + Killzones (70% WR Target)              |
//+------------------------------------------------------------------+
#property copyright "XAU Pro Engine"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "7.00"
#property description "v7.0: Inputs match Frontend Slots exactly. SMC + EMA200 Trend."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
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
//| INPUT PARAMETERS (Match Frontend Slots EXACTLY)                   |
//+------------------------------------------------------------------+

input group "========== CORE =========="
input int               InpMagicNumber = 888888;           // Magic Number
input ENUM_DIRECTION    InpDirection = DIR_BOTH;           // Trade Direction
input int               InpBrokerOffset = 2;               // Broker UTC Offset

input group "========== SESSION CONTROL =========="
input ENUM_SESSION_MODE InpSessionMode = SESSION_BOTH_KZ;  // Session Killzone
input ENUM_SESSION_END  InpSessionEnd = END_DISABLE_NEW;   // Session End Action
input bool              InpUseDailyBias = false;           // Use D1 Trend Bias

input group "========== RISK / TP / SL =========="
input double            InpRiskPercent = 0.2;              // Risk %
input double            InpTPRatio = 1.5;                  // TP Ratio (R)
input double            InpSL_ATR = 0.5;                   // SL ATR Multiplier
input ENUM_TSL_MODE     InpTSLMode = TSL_ATR;              // TSL Mode

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


//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

// Indicator Handles
int hRSI, hMACD, hATR, hEMA;

// State Variables
double g_RSI, g_MACD_Main, g_MACD_Signal, g_ATR;
double g_Prev_MACD_Main, g_Prev_MACD_Signal, g_Prev_MACD_Hist_Value; 
double g_EMA200;  // EMA200 for trend detection

// Market Structure (V5.1: CHoCH Added)
enum ENUM_STRUCT_TREND { TREND_BULLISH, TREND_BEARISH, TREND_NEUTRAL };
ENUM_STRUCT_TREND marketStructure = TREND_NEUTRAL;
string lastStructEvent = "None"; // "BOS UP", "CHoCH DOWN", etc.

// SMC Arrays (Persistent)
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
datetime lastTradeDate = 0;
double dailyStartEquity = 0;
int dailyTrades = 0;

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

   hRSI = iRSI(NULL, 0, InpRSI_Period, PRICE_CLOSE);
   hMACD = iMACD(NULL, 0, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
   hATR = iATR(NULL, 0, 14);
   hEMA = iMA(NULL, 0, 200, 0, MODE_EMA, PRICE_CLOSE); 

   if(hRSI == INVALID_HANDLE || hMACD == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE)
   {
      Print("Error initializing indicators");
      return INIT_FAILED;
   }

   dailyStartEquity = account.Equity();
   Print("🥇 XAU Pro Agent v7.0 Initialized | Frontend Slots Aligned");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   IndicatorRelease(hMACD);
   IndicatorRelease(hATR);
   IndicatorRelease(hEMA);
   ObjectsDeleteAll(0, "XAUPro_");
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, 0, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   symbolInfo.RefreshRates();
   
   // Dashboard update (always show)
   UpdateDashboard();
   
   // Trade Management
   ManageTrade();

   // New Bar Check
   if(!IsNewBar()) return;

   // 1. Session Filter
   inKillzone = CheckKillzone();
   if(!inKillzone && InpSessionMode != SESSION_ALL) 
   {
      return; 
   }

   // 2. Update Data & Structure
   UpdateIndicators();
   UpdateStructureV5(); 
   
   // 3. SMC Zone Management
   if(InpUseOB || InpUseFVG)
   {
      ManageOrderBlocks(); 
      ManageFVGs();        
   }

   // 4. Entry Logic
   if(position.Select(_Symbol)) return; 

   bool signalBuy = false;
   bool signalSell = false;
   string strategy = "";

   // Check SMC Entry
   if(InpUseOB || InpUseSweep || InpUseFVG)
   {
      if(CheckSMCEntry("BUY")) { signalBuy = true; strategy = "SMC_OB_Liquidity"; }
      else if(CheckSMCEntry("SELL")) { signalSell = true; strategy = "SMC_OB_Liquidity"; }
   }

   // Check Fib Entry if SMC didn't trigger
   if(!signalBuy && !signalSell)
   {
      if(CheckFibEntry("BUY")) { signalBuy = true; strategy = "FIB_GoldenZone"; }
      else if(CheckFibEntry("SELL")) { signalSell = true; strategy = "FIB_GoldenZone"; }
   }

   // 5. Direction Filter
   if(InpDirection == DIR_BUY_ONLY && signalSell) { signalSell = false; }
   if(InpDirection == DIR_SELL_ONLY && signalBuy) { signalBuy = false; }

   // 6. Execution
   if(signalBuy) ExecuteTrade(ORDER_TYPE_BUY, strategy);
   if(signalSell) ExecuteTrade(ORDER_TYPE_SELL, strategy);
}

//+------------------------------------------------------------------+
//| Trade Management - TSL Modes (ATR/TIERED)                        |
//+------------------------------------------------------------------+
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
   
   double currentProfitPoints = 0;
   if(type == POSITION_TYPE_BUY) currentProfitPoints = currentPrice - openPrice;
   else                          currentProfitPoints = openPrice - currentPrice;
   
   double initialRisk = MathAbs(openPrice - sl);
   if(initialRisk == 0) return;
   
   // ATR TSL Mode: Trail SL by ATR distance
   if(InpTSLMode == TSL_ATR && currentProfitPoints > initialRisk)
   {
      double atrDistance = g_ATR * InpSL_ATR;
      double newSL = 0;
      
      if(type == POSITION_TYPE_BUY)
      {
         newSL = currentPrice - atrDistance;
         if(newSL > sl && newSL < currentPrice)
         {
            trade.PositionModify(_Symbol, newSL, tp);
         }
      }
      else
      {
         newSL = currentPrice + atrDistance;
         if(newSL < sl && newSL > currentPrice)
         {
            trade.PositionModify(_Symbol, newSL, tp);
         }
      }
   }
   
   // TIERED TSL Mode: Move to BE at 1R, then trail
   if(InpTSLMode == TSL_TIERED)
   {
      if(currentProfitPoints >= initialRisk && sl != openPrice)
      {
         // Move to Break-Even
         trade.PositionModify(_Symbol, openPrice, tp);
         Print("�️ TSL TIERED: SL moved to Break-Even");
      }
      else if(currentProfitPoints >= initialRisk * 1.5)
      {
         // Trail with ATR at 1.5R+
         double atrDistance = g_ATR * InpSL_ATR;
         double newSL = 0;
         
         if(type == POSITION_TYPE_BUY) newSL = currentPrice - atrDistance;
         else                           newSL = currentPrice + atrDistance;
         
         if((type == POSITION_TYPE_BUY && newSL > sl) || (type == POSITION_TYPE_SELL && newSL < sl))
         {
            trade.PositionModify(_Symbol, newSL, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| V5.1 UPDATED: Structure Engine (BOS + CHoCH)                     |
//+------------------------------------------------------------------+
void UpdateStructureV5()
{
   // 1. Get Latest Swing High/Low
   int hb = iHighest(_Symbol, 0, MODE_HIGH, InpZigZagLookback, 1);
   int lb = iLowest(_Symbol, 0, MODE_LOW, InpZigZagLookback, 1);
   
   double hVal = iHigh(_Symbol, 0, hb);
   double lVal = iLow(_Symbol, 0, lb);
   
   static double activeHigh = 0;
   static double activeLow = 0;
   
   if(activeHigh == 0 || activeLow == 0)
   {
      activeHigh = hVal;
      activeLow = lVal;
      return; 
   }
   
   double close = iClose(_Symbol, 0, 1);
   
   // --- BOS LOGIC ---
   // Continuation of Trend
   if(close > activeHigh && marketStructure == TREND_BULLISH)
   {
       lastStructEvent = "BOS UP (Continuat)";
       activeHigh = hVal; activeLow = lVal;
   }
   else if(close < activeLow && marketStructure == TREND_BEARISH)
   {
       lastStructEvent = "BOS DOWN (Continuat)";
       activeHigh = hVal; activeLow = lVal;
   }
   
   // --- CHoCH LOGIC (Reversals) ---
   // Break of Low in Bullish Trend -> CHoCH DOWN
   else if(close < activeLow && marketStructure == TREND_BULLISH)
   {
       marketStructure = TREND_BEARISH;
       lastStructEvent = "CHoCH DOWN (Reversal)";
       Print("🔄 CHoCH DOWN! Trend Flip to Bearish");
       activeHigh = hVal; activeLow = lVal;
   }
   // Break of High in Bearish Trend -> CHoCH UP
   else if(close > activeHigh && marketStructure == TREND_BEARISH)
   {
       marketStructure = TREND_BULLISH;
       lastStructEvent = "CHoCH UP (Reversal)";
       Print("🔄 CHoCH UP! Trend Flip to Bullish");
       activeHigh = hVal; activeLow = lVal;
   }
   
   // Initialize Neutral State
   else if(marketStructure == TREND_NEUTRAL)
   {
       if(close > activeHigh) { marketStructure = TREND_BULLISH; lastStructEvent = "BOS UP (Init)"; }
       else if(close < activeLow) { marketStructure = TREND_BEARISH; lastStructEvent = "BOS DOWN (Init)"; }
   }
   
   if(hVal > activeHigh) activeHigh = hVal; 
   if(lVal < activeLow) activeLow = lVal;   
}

//+------------------------------------------------------------------+
//| V5.1 RESTORED: Functional Logic Core                             |
//+------------------------------------------------------------------+

bool CheckLiquiditySweep(string dir)
{
   // Logic from V4.2 Enhanced
   int lookback = 10;
   double currentClose = iClose(_Symbol, 0, 1);
   double currentOpen = iOpen(_Symbol, 0, 1);
   double currentBody = MathAbs(currentClose - currentOpen);
   
   // Weak Sweep Filter
   if(currentBody < (g_ATR * 0.3)) return false; 

   if(dir == "BUY")
   {
      double prevLow = iLow(_Symbol, 0, 1);
      int lowestBar = iLowest(_Symbol, 0, MODE_LOW, lookback, 2); 
      if(lowestBar < 0) return false;
      double recentLow = iLow(_Symbol, 0, lowestBar);
      
      return (prevLow < recentLow) && (currentClose > recentLow);
   }
   else // SELL
   {
      double prevHigh = iHigh(_Symbol, 0, 1);
      int highestBar = iHighest(_Symbol, 0, MODE_HIGH, lookback, 2);
      if(highestBar < 0) return false;
      double recentHigh = iHigh(_Symbol, 0, highestBar);
      
      return (prevHigh > recentHigh) && (currentClose < recentHigh);
   }
}

bool CheckCandleTrigger(string dir)
{
   double open = iOpen(_Symbol, 0, 1);
   double close = iClose(_Symbol, 0, 1);
   double high = iHigh(_Symbol, 0, 1);
   double low = iLow(_Symbol, 0, 1);
   
   double body = MathAbs(close - open);
   if(body == 0) return false;

   double openPrev = iOpen(_Symbol, 0, 2);
   double closePrev = iClose(_Symbol, 0, 2);
   double bodyPrev = MathAbs(closePrev - openPrev);

   // Engulfing
   bool engulfing = false;
   if(dir == "BUY")
      engulfing = (close > open) && (closePrev < openPrev) && (body > bodyPrev) && (close > openPrev);
   else
      engulfing = (close < open) && (closePrev > openPrev) && (body > bodyPrev) && (close < openPrev);

   // Pinbar
   bool pinbar = false;
   if(dir == "BUY")
   {
      double lowerWick = MathMin(open, close) - low;
      pinbar = (lowerWick > body * 2.0); 
   }
   else
   {
      double upperWick = high - MathMax(open, close);
      pinbar = (upperWick > body * 2.0); 
   }

   return engulfing || pinbar;
}

bool CheckFibEntry(string dir)
{
   // =============================================================
   // PYTHON ENGINE LOGIC: EMA200 Trend Filter (not structure-based)
   // Python: is_bullish = current['close'] > current['ema200']
   // =============================================================
   double currentPrice = symbolInfo.Bid();
   bool isEMABullish = currentPrice > g_EMA200;
   bool isEMABearish = currentPrice < g_EMA200;
   
   if(dir == "BUY" && !isEMABullish) return false;
   if(dir == "SELL" && !isEMABearish) return false;

   // Swing Range Calculation
   int hb = iHighest(_Symbol, 0, MODE_HIGH, InpZigZagLookback, 1);
   int lb = iLowest(_Symbol, 0, MODE_LOW, InpZigZagLookback, 1);
   double hVal = iHigh(_Symbol, 0, hb);
   double lVal = iLow(_Symbol, 0, lb);
   
   double range = hVal - lVal;
   if(range <= g_ATR) return false;

   // =============================================================
   // PYTHON ENGINE LOGIC: Zone Tolerance = ATR * 0.25
   // Python: tolerance_price = current['atr'] * 0.25
   // =============================================================
   double tolerance = g_ATR * 0.25;
   double price = currentPrice;
   
   // Golden Zone: 61.8% - 78.6% retracement
   if(dir == "BUY")
   {
      // BUY: Price retraces DOWN from high -> look for deep discount
      double level618 = hVal - (range * 0.618);
      double level786 = hVal - (range * 0.786);
      
      // Python: if abs(current_price - zone['price']) < tolerance_price
      bool inZone = (price <= level618 + tolerance && price >= level786 - tolerance);
      
      if(inZone)
      {
          if(!CheckTripleConfirmation(dir)) return false;
          return CheckCandleTrigger(dir);
      }
   }
   else // SELL
   {
      // SELL: Price retraces UP from low -> look for premium zone
      double level618 = lVal + (range * 0.618);
      double level786 = lVal + (range * 0.786);
      
      bool inZone = (price >= level618 - tolerance && price <= level786 + tolerance);
      
      if(inZone)
      {
          if(!CheckTripleConfirmation(dir)) return false;
          return CheckCandleTrigger(dir);
      }
   }
   return false;
}

bool CheckTripleConfirmation(string dir)
{
   bool rsiOk = (dir == "BUY") ? (g_RSI <= InpRSI_BuyLevel) : (g_RSI >= InpRSI_SellLevel);
   double currentHist = g_MACD_Main - g_MACD_Signal;
   bool macdOk = (dir == "BUY") ? (currentHist > g_Prev_MACD_Hist_Value) : (currentHist < g_Prev_MACD_Hist_Value);
   
   return rsiOk && macdOk;
}

void UpdateIndicators()
{
   double bufRSI[1], bufMACD_M[2], bufMACD_S[2], bufATR[1], bufEMA[1];
   CopyBuffer(hRSI, 0, 1, 1, bufRSI);
   CopyBuffer(hMACD, 0, 1, 2, bufMACD_M); CopyBuffer(hMACD, 1, 1, 2, bufMACD_S);
   CopyBuffer(hATR, 0, 1, 1, bufATR);
   CopyBuffer(hEMA, 0, 1, 1, bufEMA);  // EMA200

   g_RSI = bufRSI[0]; g_MACD_Main = bufMACD_M[1]; g_MACD_Signal = bufMACD_S[1];
   g_Prev_MACD_Main = bufMACD_M[0]; g_Prev_MACD_Signal = bufMACD_S[0];
   g_Prev_MACD_Hist_Value = g_Prev_MACD_Main - g_Prev_MACD_Signal;
   g_ATR = bufATR[0];
   g_EMA200 = bufEMA[0];
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
   return true; // SESSION_ALL
}

//+------------------------------------------------------------------+
//| Trade Execution (v7.0 - Uses InpSL_ATR and InpTPRatio)           |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, string comment)
{
   double sl=0, tp=0;
   double price = (type == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
   
   double slDist = g_ATR * InpSL_ATR;
   double tpDist = slDist * InpTPRatio;
   
   if(type == ORDER_TYPE_BUY) { sl = price - slDist; tp = price + tpDist; }
   else                       { sl = price + slDist; tp = price - tpDist; }
   
   double equity = account.Equity();
   double riskAmount = equity * (InpRiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lotSize = 0.01;
   if(tickSize > 0 && tickValue > 0)
   {
      double ticksRisk = slDist / tickSize;
      lotSize = riskAmount / (ticksRisk * tickValue);
   }
   
   lotSize = NormalizeDouble(lotSize, 2);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot; 
   if(lotSize > maxLot) lotSize = maxLot;
   lotSize = MathFloor(lotSize / stepLot) * stepLot;

   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, comment))
   {
      dailyTrades++;
      Print("🟢 TRADE OPENED: ", comment, " Lots: ", lotSize, " SL: ", slDist/_Point, "pts TP: ", tpDist/_Point, "pts");
   }
}

// ... ManageOBs, ManageFVGs, CheckSMCEntry (Same as v5.0, just ensure they call the restored functions)
bool CheckSMCEntry(string dir)
{
   // =============================================================
   // PYTHON ENGINE LOGIC: EMA200 Trend Filter (not structure-based)
   // Python: is_bullish = current['close'] > current['ema200']
   // =============================================================
   double currentPrice = symbolInfo.Bid();
   bool isEMABullish = currentPrice > g_EMA200;
   bool isEMABearish = currentPrice < g_EMA200;
   
   if(dir == "BUY" && !isEMABullish) return false;
   if(dir == "SELL" && !isEMABearish) return false;

   bool inZone = false;
   double price = currentPrice;
   
   // Check Order Blocks
   for(int i=0; i<ArraySize(activeOBs); i++)
   {
      if(activeOBs[i].mitigated || activeOBs[i].invalidated) continue;
      bool correctDir = (dir == "BUY") ? activeOBs[i].isBullish : !activeOBs[i].isBullish;
      if(correctDir && price <= activeOBs[i].top && price >= activeOBs[i].bottom)
      {
         inZone = true; break;
      }
   }
   
   // Check FVGs if not in OB
   if(!inZone)
   {
       for(int i=0; i<ArraySize(activeFVGs); i++)
       {
           if(activeFVGs[i].filled || activeFVGs[i].invalidated) continue;
           bool correctDir = (dir == "BUY") ? activeFVGs[i].isBullish : !activeFVGs[i].isBullish;
           if(correctDir && price <= activeFVGs[i].top && price >= activeFVGs[i].bottom)
           {
               inZone = true; break;
           }
       }
   }
   
   if(!inZone) return false;

   // =============================================================
   // PYTHON ENGINE LOGIC: SMC requires Zone + Liquidity Sweep
   // Python: if (smc_result['in_order_block'] or smc_result['in_fvg']) and smc_result['liquidity_swept']
   // =============================================================
   if(InpUseSweep)
   {
      if(!CheckLiquiditySweep(dir)) return false;
   }

   return CheckCandleTrigger(dir);
}

void ManageOrderBlocks() { /* Same as V5.0 */ 
   double o1=iOpen(NULL,0,2), c1=iClose(NULL,0,2); 
   double o0=iOpen(NULL,0,1), c0=iClose(NULL,0,1); 
   double body0 = MathAbs(c0-o0);
   bool displacement = body0 > (g_ATR * 1.5); // Fixed displacement multiplier
   
   if(displacement)
   {
      double h1 = iHigh(NULL,0,2); double l1 = iLow(NULL,0,2);
      if(c1 < o1 && c0 > o0) 
      {
         OrderBlock ob; ob.isBullish = true; ob.top = h1; ob.bottom = l1; ob.time = iTime(NULL,0,2);
         ob.mitigated = false; ob.invalidated = false; ob.creationBar = iBarShift(NULL,0,ob.time);
         bool exists = false; if(ArraySize(activeOBs) > 0 && activeOBs[ArraySize(activeOBs)-1].time == ob.time) exists = true;
         if(!exists) { ArrayResize(activeOBs, ArraySize(activeOBs)+1); activeOBs[ArraySize(activeOBs)-1] = ob; }
      }
      else if(c1 > o1 && c0 < o0) 
      {
         OrderBlock ob; ob.isBullish = false; ob.top = h1; ob.bottom = l1; ob.time = iTime(NULL,0,2);
         ob.mitigated = false; ob.invalidated = false; ob.creationBar = iBarShift(NULL,0,ob.time);
         bool exists = false; if(ArraySize(activeOBs) > 0 && activeOBs[ArraySize(activeOBs)-1].time == ob.time) exists = true;
         if(!exists) { ArrayResize(activeOBs, ArraySize(activeOBs)+1); activeOBs[ArraySize(activeOBs)-1] = ob; }
      }
   }
   // Cleanup...
   double currentHigh = iHigh(NULL,0,0); double currentLow = iLow(NULL,0,0);
   for(int i=ArraySize(activeOBs)-1; i>=0; i--)
   {
      if(activeOBs[i].invalidated || activeOBs[i].mitigated) continue;
      if(activeOBs[i].isBullish) { if(currentLow < activeOBs[i].bottom) activeOBs[i].invalidated = true; else if(currentLow <= activeOBs[i].top) activeOBs[i].mitigated = true; }
      else { if(currentHigh > activeOBs[i].top) activeOBs[i].invalidated = true; else if(currentHigh >= activeOBs[i].bottom) activeOBs[i].mitigated = true; }
      if(iTime(NULL,0,0) - activeOBs[i].time > PeriodSeconds() * 100) activeOBs[i].invalidated = true;
   }
}

void ManageFVGs() { /* Same as V5.0 */ 
   double h3 = iHigh(NULL,0,3); double l3 = iLow(NULL,0,3);
   double h1 = iHigh(NULL,0,1); double l1 = iLow(NULL,0,1);
   bool c1Bullish = (iClose(NULL,0,1) > iOpen(NULL,0,1));
   bool c1Bearish = (iClose(NULL,0,1) < iOpen(NULL,0,1));
   if(l1 > h3 && c1Bullish && (l1 - h3) > g_ATR * 0.3) 
   {
         FVG fvg; fvg.isBullish = true; fvg.top = l1; fvg.bottom = h3; fvg.time = iTime(NULL,0,2);
         fvg.filled = false; fvg.invalidated = false;
         bool exists = false; if(ArraySize(activeFVGs) > 0 && activeFVGs[ArraySize(activeFVGs)-1].time == fvg.time) exists = true;
         if(!exists) { ArrayResize(activeFVGs, ArraySize(activeFVGs)+1); activeFVGs[ArraySize(activeFVGs)-1] = fvg; }
   }
   if(l3 > h1 && c1Bearish && (l3 - h1) > g_ATR * 0.3)
   {
         FVG fvg; fvg.isBullish = false; fvg.top = l3; fvg.bottom = h1; fvg.time = iTime(NULL,0,2);
         fvg.filled = false; fvg.invalidated = false;
         bool exists = false; if(ArraySize(activeFVGs) > 0 && activeFVGs[ArraySize(activeFVGs)-1].time == fvg.time) exists = true;
         if(!exists) { ArrayResize(activeFVGs, ArraySize(activeFVGs)+1); activeFVGs[ArraySize(activeFVGs)-1] = fvg; }
   }
   double cHigh = iHigh(NULL,0,0); double cLow = iLow(NULL,0,0);
   for(int i=ArraySize(activeFVGs)-1; i>=0; i--)
   {
      if(activeFVGs[i].invalidated || activeFVGs[i].filled) continue;
      if(activeFVGs[i].isBullish) { if(cLow < activeFVGs[i].bottom) activeFVGs[i].invalidated = true; else if(cLow <= activeFVGs[i].top) activeFVGs[i].filled = true; }
      else { if(cHigh > activeFVGs[i].top) activeFVGs[i].invalidated = true; else if(cHigh >= activeFVGs[i].bottom) activeFVGs[i].filled = true; }
      if(iTime(NULL,0,0) - activeFVGs[i].time > PeriodSeconds() * 50) activeFVGs[i].invalidated = true;
   }
}

void UpdateDashboard()
{
   // EMA200 Trend (Python engine logic)
   string emaTrend = (symbolInfo.Bid() > g_EMA200) ? "📈 BULLISH (Above EMA200)" : "📉 BEARISH (Below EMA200)";
   
   // Structure info (kept for reference)
   string structStr = "NEUTRAL";
   if(marketStructure == TREND_BULLISH) structStr = "BOS/CHoCH UP";
   if(marketStructure == TREND_BEARISH) structStr = "BOS/CHoCH DOWN";

   string text = "🥇 XAU PRO v6.0 (PYTHON ENGINE) | " + EnumToString(InpSessionMode) + "\n";
   text += "--------------------------------------\n";
   text += "Price: " + DoubleToString(symbolInfo.Bid(), 2) + " | EMA200: " + DoubleToString(g_EMA200, 2) + "\n";
   text += "Trend: " + emaTrend + "\n";
   text += "Structure: " + structStr + " (" + lastStructEvent + ")\n";
   text += "Active OBs: " + IntegerToString(ArraySize(activeOBs)) + " | FVGs: " + IntegerToString(ArraySize(activeFVGs)) + "\n";
   text += "Killzone: " + (inKillzone ? "YES ✅" : "NO ⏳") + "\n";
   
   Comment(text);
}

// End of file
