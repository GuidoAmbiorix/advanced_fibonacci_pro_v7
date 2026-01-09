//+------------------------------------------------------------------+
//|                                                 XAU_Pro_Agent.mq5 |
//|          XAU Pro Engine v5.1 - ELITE TIER INSTITUTIONAL           |
//|               "The Gold Standard" for XAUUSD Scalping            |
//+------------------------------------------------------------------+
#property copyright "XAU Pro Engine"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "5.10"
#property description "Elite Tier v5.1 (BOS/CHoCH + Partials + First Tap OB + Full Logic)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_SESSION_MODE
{
   SESSION_LONDON = 0,     // 07:00 - 10:00 UTC
   SESSION_NY = 1,         // 12:00 - 15:00 UTC
   SESSION_OVERLAP = 2,    // 13:00 - 16:00 UTC
   SESSION_BOTH = 3,       // London + NY
   SESSION_ALL = 4         // 24/7 (Not Recommended)
};

enum ENUM_ENTRY_PATH
{
   PATH_AUTO = 0,          // Check both SMC and Fib
   PATH_SMC_ONLY = 1,      // Order Blocks / FVG / Sweeps Only
   PATH_FIB_ONLY = 2       // Golden Zone + Triple Confirmation Only
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "========== ELITE CONFIG v5.1 =========="
input int             InpMagicNumber = 888888;            // Magic Number
input ENUM_SESSION_MODE InpSessionMode = SESSION_BOTH;    // Trading Session (Killzones)
input int             InpBrokerOffset = 2;                // Broker UTC Offset (e.g. 2 or 3)
input ENUM_ENTRY_PATH InpEntryPath = PATH_AUTO;           // Entry Logic Path
input int             InpMaxSpread = 25;                  // Max Spread (Points) - Safety

input group "========== TRADE MANAGEMENT (ELITE) =========="
input bool     InpUsePartials = true;         // Enable Partial TP
input double   InpPartialRR = 1.5;            // Partial TP at 1.5R 
input double   InpPartialPct = 50.0;          // Close 50% of position
input bool     InpMoveToBE = true;            // Move SL to BE after Partial
input double   InpBECushion = 100;            // BE Cushion (points) -> Spread cover

input group "========== RISK MANAGEMENT =========="
input double   InpRiskPercent = 1.0;          // Risk Per Trade (%)
input double   InpRiskReward = 2.0;           // Risk:Reward Ratio (Final TP)
input double   InpSL_ATR_Mult = 1.4;          // Stop Loss ATR Multiplier
input double   InpMaxDailyDD = 3.0;           // Max Daily Drawdown (%)
input int      InpMaxPositions = 1;           // Max Concurrent Positions

input group "========== INDICATOR SETTINGS =========="
// RSI
input int      InpRSI_Period = 14;            // RSI Period
input int      InpRSI_BuyLevel = 40;          // RSI Buy Level (Deep Discount)
input int      InpRSI_SellLevel = 60;         // RSI Sell Level (Premium)
// MACD (Fast Tuning)
input int      InpMACD_Fast = 6;              // MACD Fast EMA
input int      InpMACD_Slow = 18;             // MACD Slow EMA
input int      InpMACD_Signal = 9;            // MACD Signal
// Stochastic
input int      InpStoch_K = 14;               // Stochastic %K
input int      InpStoch_D = 3;                // Stochastic %D
input int      InpStoch_Slowing = 3;          // Stochastic Slowing

input group "========== SMC SETTINGS =========="
input bool     InpUseSMC = true;              // Enable SMC Logic
input int      InpOB_Lookback = 20;           // Order Block Lookback (Detection)
input double   InpDisplacement_Mult = 1.5;    // Displacement ATR Multiplier
input bool     InpUseLiquiditySweeps = true;  // Require Liquidity Sweep

input group "========== FIBONACCI SETTINGS =========="
input int      InpSwingLookback = 20;         // Swing Detection Lookback (Tighter for Structure)
input bool     InpUseFibEntry = true;         // Enable Fib Golden Zone Entry

input group "========== DISPLAY =========="
input bool     InpShowDashboard = true;       // Show Dashboard
input bool     InpShowZones = true;           // Draw Zones on Chart

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

// Indicator Handles
int hRSI, hMACD, hStoch, hATR, hEMA;

// State Variables
double g_RSI, g_MACD_Main, g_MACD_Signal, g_Stoch_K, g_Stoch_D, g_ATR;
double g_Prev_MACD_Main, g_Prev_MACD_Signal, g_Prev_MACD_Hist_Value; 
double g_Prev_Stoch_K;

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
   hStoch = iStochastic(NULL, 0, InpStoch_K, InpStoch_D, InpStoch_Slowing, MODE_SMA, STO_LOWHIGH);
   hATR = iATR(NULL, 0, 14);
   hEMA = iMA(NULL, 0, 200, 0, MODE_EMA, PRICE_CLOSE); 

   if(hRSI == INVALID_HANDLE || hMACD == INVALID_HANDLE || hStoch == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE)
   {
      Print("Error initializing indicators");
      return INIT_FAILED;
   }

   dailyStartEquity = account.Equity();
   Print("🥇 XAU Pro Agent v5.1 Initialized | ELITE TIER Logic Active");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   IndicatorRelease(hMACD);
   IndicatorRelease(hStoch);
   IndicatorRelease(hATR);
   IndicatorRelease(hEMA);
   ObjectsDeleteAll(0, "XAUPro_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   symbolInfo.RefreshRates();
   
   // Dashboard update
   if(InpShowDashboard) UpdateDashboard();
   
   // Trade Management
   ManageTrade();

   // New Bar Check
   if(!IsNewBar()) return;

   // 1. Session Filter
   inKillzone = CheckKillzone();
   if(!inKillzone && InpSessionMode != SESSION_ALL) 
   {
      if(InpShowDashboard) Comment("⏳ OUTSIDE KILLZONE: Waiting for Session...");
      return; 
   }

   // 2. Risk Check
   if(!CheckRisk()) return;
   if(symbolInfo.Spread() > InpMaxSpread) return;

   // 3. Update Data & Structure
   UpdateIndicators();
   UpdateStructureV5(); 
   
   if(InpUseSMC)
   {
      ManageOrderBlocks(); 
      ManageFVGs();        
   }

   // 4. Entry Logic
   if(position.Select(_Symbol)) return; 
   if(dailyTrades >= 5) return; 

   bool signalBuy = false;
   bool signalSell = false;
   string strategy = "";

   if((InpEntryPath == PATH_AUTO || InpEntryPath == PATH_SMC_ONLY) && InpUseSMC)
   {
      if(CheckSMCEntry("BUY")) { signalBuy = true; strategy = "SMC_OB_Liquidity"; }
      else if(CheckSMCEntry("SELL")) { signalSell = true; strategy = "SMC_OB_Liquidity"; }
   }

   if(!signalBuy && !signalSell && (InpEntryPath == PATH_AUTO || InpEntryPath == PATH_FIB_ONLY) && InpUseFibEntry)
   {
      if(CheckFibEntry("BUY")) { signalBuy = true; strategy = "FIB_GoldenZone"; }
      else if(CheckFibEntry("SELL")) { signalSell = true; strategy = "FIB_GoldenZone"; }
   }

   // 5. Execution
   if(signalBuy) ExecuteTrade(ORDER_TYPE_BUY, strategy);
   if(signalSell) ExecuteTrade(ORDER_TYPE_SELL, strategy);
}

//+------------------------------------------------------------------+
//| V5.0: Trade Management (Partials/BE)                             |
//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!position.Select(_Symbol)) return;
   if(position.Magic() != InpMagicNumber) return;
   
   string comment = position.Comment();
   double openPrice = position.PriceOpen();
   double currentPrice = position.PriceCurrent();
   double sl = position.StopLoss();
   double tp = position.TakeProfit();
   long type = position.PositionType();
   double vol = position.Volume();
   
   double initialRisk = MathAbs(openPrice - sl);
   if(initialRisk == 0) return; 
   
   double currentProfitPoints = 0;
   if(type == POSITION_TYPE_BUY) currentProfitPoints = currentPrice - openPrice;
   else                          currentProfitPoints = openPrice - currentPrice;
   
   bool takenPartial = (StringFind(comment, "PARTIAL") >= 0);
   
   if(InpUsePartials && !takenPartial)
   {
      double targetPoints = initialRisk * InpPartialRR;
      if(currentProfitPoints >= targetPoints)
      {
         double closeVol = NormalizeDouble(vol * (InpPartialPct / 100.0), 2);
         double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         
         closeVol = MathFloor(closeVol / step) * step;
         
         if(closeVol >= minVol)
         {
            trade.PositionClosePartial(_Symbol, closeVol);
            Print("💰 PARTIAL TAKEN: ", closeVol, " lots @ ", InpPartialRR, "R");
            
            if(InpMoveToBE)
            {
               double newSL = 0;
               if(type == POSITION_TYPE_BUY) newSL = openPrice + (InpBECushion * _Point);
               else                          newSL = openPrice - (InpBECushion * _Point);
               
               trade.PositionModify(_Symbol, newSL, tp);
               Print("🛡️ SL MOVED TO BE (+Cushion)");
            }
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
   int hb = iHighest(_Symbol, 0, MODE_HIGH, InpSwingLookback, 1);
   int lb = iLowest(_Symbol, 0, MODE_LOW, InpSwingLookback, 1);
   
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
   // Structural Filter: Trend must align (V5.1 strict)
   if(dir == "BUY" && marketStructure == TREND_BEARISH) return false;
   if(dir == "SELL" && marketStructure == TREND_BULLISH) return false;

   // Simple Range Calc (Use active structure range?)
   // For now, use simple swing loop
   
   int hb = iHighest(_Symbol, 0, MODE_HIGH, InpSwingLookback, 1);
   int lb = iLowest(_Symbol, 0, MODE_LOW, InpSwingLookback, 1);
   double hVal = iHigh(_Symbol, 0, hb);
   double lVal = iLow(_Symbol, 0, lb);
   
   double range = hVal - lVal;
   if(range <= g_ATR) return false;

   double fib618, fib786;
   double price = symbolInfo.Bid();
   
   // Buying Pullback
   if(dir == "BUY")
   {
      fib618 = lVal + range * 0.618;
      fib786 = lVal + range * 0.786; // Note: In BUY, higher price is LESS retracement? 
      // Retracement from Low to High? No.
      // Move is Low -> High. Retracement checks levels from High down to Low.
      // 0 = High, 1 = Low.
      // 61.8% Retracement = High - Range * 0.618.
      // 78.6% Retracement = High - Range * 0.786.
      
      // My previous logic was: lVal + range * 0.618. That is 61.8% UP from Low.
      // A deep pullback goes down.
      // So Level = lVal + (range * (1.0 - 0.618)) = lVal + range*0.382 ?
      // Let's stick to standard visuals.
      // Golden Zone for BUY is usually 61.8% - 78.6% OF THE MOVE.
      // Move = lVal to hVal.
      // Price Retracts DOWN from hVal.
      // So we want price to be between (hVal - range*0.618) and (hVal - range*0.786).
      // Let's fix this math for V5.1 precision.
      
      double level618 = hVal - (range * 0.618);
      double level786 = hVal - (range * 0.786);
      
      if(price <= level618 && price >= level786) // Inside Deep Discount
      {
          if(!CheckTripleConfirmation(dir)) return false;
          return CheckCandleTrigger(dir);
      }
   }
   else // SELL
   {
      double level618 = lVal + (range * 0.618);
      double level786 = lVal + (range * 0.786);
      
      if(price >= level618 && price <= level786) // Inside Premium
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
   
   bool stochOk = false;
   if(dir == "BUY") stochOk = (g_Stoch_K > g_Prev_Stoch_K) && (g_Stoch_K < 80);
   else             stochOk = (g_Stoch_K < g_Prev_Stoch_K) && (g_Stoch_K > 20);

   return rsiOk && macdOk && stochOk;
}

void UpdateIndicators()
{
   double bufRSI[1], bufMACD_M[2], bufMACD_S[2], bufStoch_K[2], bufStoch_D[1], bufATR[1];
   CopyBuffer(hRSI, 0, 1, 1, bufRSI);
   CopyBuffer(hMACD, 0, 1, 2, bufMACD_M); CopyBuffer(hMACD, 1, 1, 2, bufMACD_S);
   CopyBuffer(hStoch, 0, 1, 2, bufStoch_K); CopyBuffer(hStoch, 1, 1, 1, bufStoch_D); 
   CopyBuffer(hATR, 0, 1, 1, bufATR);

   g_RSI = bufRSI[0]; g_MACD_Main = bufMACD_M[1]; g_MACD_Signal = bufMACD_S[1];
   g_Prev_MACD_Main = bufMACD_M[0]; g_Prev_MACD_Signal = bufMACD_S[0];
   g_Prev_MACD_Hist_Value = g_Prev_MACD_Main - g_Prev_MACD_Signal;
   g_Stoch_K = bufStoch_K[1]; g_Prev_Stoch_K = bufStoch_K[0]; g_Stoch_D = bufStoch_D[0];
   g_ATR = bufATR[0];
}

bool CheckKillzone()
{
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   int utcHour = (dt.hour - InpBrokerOffset + 24) % 24;
   
   if(utcHour >= 24) utcHour -= 24; // logic fix just in case
   
   bool london = (utcHour >= 7 && utcHour < 10);
   bool ny = (utcHour >= 12 && utcHour < 15);
   
   if(InpSessionMode == SESSION_LONDON) return london;
   if(InpSessionMode == SESSION_NY) return ny;
   if(InpSessionMode == SESSION_OVERLAP) return (utcHour >= 13 && utcHour < 16); 
   if(InpSessionMode == SESSION_BOTH) return (london || ny);
   return true;
}

bool CheckRisk()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != lastTradeDate)
   {
      lastTradeDate = today; dailyTrades = 0; dailyStartEquity = account.Equity();
   }
   double dd = (dailyStartEquity - account.Equity()) / dailyStartEquity * 100.0;
   if(dd >= InpMaxDailyDD) { Comment("⛔ DAILY DD HIT"); return false; }
   return true;
}

//+------------------------------------------------------------------+
//| UTILS: Execution (V5.1 Tick Value Fixed)                         |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, string comment)
{
   double sl=0, tp=0;
   double price = (type == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
   
   double slDist = g_ATR * InpSL_ATR_Mult;
   double tpDist = slDist * InpRiskReward;
   
   if(type == ORDER_TYPE_BUY) { sl = price - slDist; tp = price + tpDist; }
   else                       { sl = price + slDist; tp = price - tpDist; }
   
   double equity = account.Equity();
   double riskAmount = equity * (InpRiskPercent / 100.0);
   
   // V5.1 PRECISION: Tick Value Normalization
   // LotSize = Risk / (SL_Points * TickValue)
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0) 
   {
       // Fallback to contract size method if TickValue broken
       double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
       if(contractSize==0) contractSize=100;
       double lotSize = riskAmount / (slDist * contractSize); // Approx
   }
   
   double slPoints = slDist / _Point; 
   // Note: TickValue is usually per 1 Lot per TickSize movement.
   // Risk = Lots * (SL_Points * Point / TickSize) * TickValue 
   // Simplify: Risk = Lots * SL_Points * TickValue (if Point=TickSize, or adjusted)
   // Safe formula: Lots = Risk / ( (SL / TickSize) * TickValue )
   
   double lotSize = 0;
   if(tickSize > 0 && tickValue > 0)
   {
      double ticksRisk = slDist / tickSize;
      lotSize = riskAmount / (ticksRisk * tickValue);
   }
   else
   {
       // Basic fallback
       lotSize = 0.01; 
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
   }
}

// ... ManageOBs, ManageFVGs, CheckSMCEntry (Same as v5.0, just ensure they call the restored functions)
bool CheckSMCEntry(string dir)
{
   if(dir == "BUY" && marketStructure == TREND_BEARISH) return false;
   if(dir == "SELL" && marketStructure == TREND_BULLISH) return false;

   bool inZone = false;
   double price = symbolInfo.Bid();
   
   for(int i=0; i<ArraySize(activeOBs); i++)
   {
      if(activeOBs[i].mitigated || activeOBs[i].invalidated) continue;
      bool correctDir = (dir == "BUY") ? activeOBs[i].isBullish : !activeOBs[i].isBullish;
      if(correctDir && price <= activeOBs[i].top && price >= activeOBs[i].bottom)
      {
         inZone = true; break;
      }
   }
   
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

   if(InpUseLiquiditySweeps)
   {
      if(!CheckLiquiditySweep(dir)) return false;
   }

   return CheckCandleTrigger(dir);
}

void ManageOrderBlocks() { /* Same as V5.0 */ 
   double o1=iOpen(NULL,0,2), c1=iClose(NULL,0,2); 
   double o0=iOpen(NULL,0,1), c0=iClose(NULL,0,1); 
   double body0 = MathAbs(c0-o0);
   bool displacement = body0 > (g_ATR * InpDisplacement_Mult);
   
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
   string trendStr = "NEUTRAL";
   if(marketStructure == TREND_BULLISH) trendStr = "BULLISH (" + lastStructEvent + ")";
   if(marketStructure == TREND_BEARISH) trendStr = "BEARISH (" + lastStructEvent + ")";

   string text = "🥇 XAU PRO v5.1 (FUNCTIONAL) | " + EnumToString(InpSessionMode) + "\n";
   text += "--------------------------------------\n";
   text += "Price: " + DoubleToString(symbolInfo.Bid(), 2) + "\n";
   text += "Structure: " + trendStr + "\n";
   text += "Active OBs: " + IntegerToString(ArraySize(activeOBs)) + " | FVGs: " + IntegerToString(ArraySize(activeFVGs)) + "\n";
   text += "Killzone: " + (inKillzone ? "YES" : "NO") + "\n";
   
   Comment(text);
}
