//+------------------------------------------------------------------+
//|                                                 XAU_Pro_Agent.mq5 |
//|          XAU Pro Engine v4.2 - Institutional Gold Engine          |
//|               "The Gold Standard" for XAUUSD Scalping            |
//+------------------------------------------------------------------+
#property copyright "XAU Pro Engine"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "4.20"
#property description "Institutional Gold Engine v4.2 (Production Polish + Safety)"
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

//--- v4.2 Configuration
input group "========== INSTITUTIONAL CONFIG v4.2 =========="
input int             InpMagicNumber = 888888;            // Magic Number
input ENUM_SESSION_MODE InpSessionMode = SESSION_BOTH;    // Trading Session (Killzones)
input int             InpBrokerOffset = 2;                // Broker UTC Offset (e.g. 2 or 3)
input ENUM_ENTRY_PATH InpEntryPath = PATH_AUTO;           // Entry Logic Path
input int             InpMaxSpread = 25;                  // Max Spread (Points) - Safety

//--- Risk Management (Strict v4.0)
input group "========== RISK MANAGEMENT =========="
input double   InpRiskPercent = 1.0;          // Risk Per Trade (%)
input double   InpRiskReward = 2.0;           // Risk:Reward Ratio
input double   InpSL_ATR_Mult = 1.4;          // Stop Loss ATR Multiplier
input double   InpMaxDailyDD = 3.0;           // Max Daily Drawdown (%)
input int      InpMaxPositions = 1;           // Max Concurrent Positions

//--- Indicator Settings (Institutional Tuned)
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

//--- SMC Settings
input group "========== SMC SETTINGS =========="
input bool     InpUseSMC = true;              // Enable SMC Logic
input int      InpOB_Lookback = 20;           // Order Block Lookback (Detection)
input double   InpDisplacement_Mult = 1.5;    // Displacement ATR Multiplier
input bool     InpUseLiquiditySweeps = true;  // Require Liquidity Sweep

//--- Fibonacci Settings
input group "========== FIBONACCI SETTINGS =========="
input int      InpSwingLookback = 50;         // Swing Detection Lookback
input bool     InpUseFibEntry = true;         // Enable Fib Golden Zone Entry

//--- Display
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

// Market Structure
struct SwingPoint { double price; int bar; bool isHigh; };
SwingPoint swingHigh, swingLow;
bool trendBullish;

// SMC Arrays (Persistent)
struct OrderBlock
{
   double top;
   double bottom;
   bool isBullish;
   datetime time;
   bool mitigated;   // USED/TOUCHED - Still visible but maybe inactive?
   bool invalidated; // BROKEN - Should be deleted/ignored
   int creationBar;
};
OrderBlock activeOBs[];

struct FVG
{
   double top;
   double bottom;
   bool isBullish;
   datetime time;
   bool filled;      // Touched/Used
   bool invalidated; // Broken
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
   // Validate Symbol
   if(!symbolInfo.Name(_Symbol)) return INIT_FAILED;
   symbolInfo.RefreshRates();

   // Initialize Inputs/Trade Mode
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   // Initialize Indicators
   hRSI = iRSI(NULL, 0, InpRSI_Period, PRICE_CLOSE);
   hMACD = iMACD(NULL, 0, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
   hStoch = iStochastic(NULL, 0, InpStoch_K, InpStoch_D, InpStoch_Slowing, MODE_SMA, STO_LOWHIGH);
   hATR = iATR(NULL, 0, 14);
   hEMA = iMA(NULL, 0, 200, 0, MODE_EMA, PRICE_CLOSE); // Persistent EMA Handle

   if(hRSI == INVALID_HANDLE || hMACD == INVALID_HANDLE || hStoch == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE)
   {
      Print("Error initializing indicators");
      return INIT_FAILED;
   }

   dailyStartEquity = account.Equity();
   Print("🥇 XAU Pro Agent v4.2 Initialized | Production Logic Active");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
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
   
   // Dashboard update (realtime)
   if(InpShowDashboard) UpdateDashboard();

   // New Bar Check
   if(!IsNewBar()) return;

   // 1. Session Filter (Killzone)
   inKillzone = CheckKillzone();
   if(!inKillzone && InpSessionMode != SESSION_ALL) 
   {
      if(InpShowDashboard) Comment("⏳ OUTSIDE KILLZONE: Waiting for Session...");
      return; 
   }

   // 2. Risk Check (Daily DD + Spread)
   if(!CheckRisk()) return;
   if(symbolInfo.Spread() > InpMaxSpread) 
   {
       // Print("Spread too high: ", symbolInfo.Spread());
       return;
   }

   // 3. Update Data
   UpdateIndicators();
   UpdateStructure();
   
   if(InpUseSMC)
   {
      ManageOrderBlocks(); // Update and cleanup
      ManageFVGs();        // Update and cleanup
   }

   // 4. Entry Logic
   if(position.Select(_Symbol)) return; // Already in a trade
   if(dailyTrades >= 5) return; // Hard limit 5 trades/day

   bool signalBuy = false;
   bool signalSell = false;
   string strategy = "";

   // --- PATH A: SMC STRATEGY ---
   if((InpEntryPath == PATH_AUTO || InpEntryPath == PATH_SMC_ONLY) && InpUseSMC)
   {
      // SMC Strategy: Structure + Valid Zone (OB/FVG) + Displacement Sweep + Trigger
      if(CheckSMCEntry("BUY"))
      {
         signalBuy = true;
         strategy = "SMC_OB_Liquidity";
      }
      else if(CheckSMCEntry("SELL"))
      {
         signalSell = true;
         strategy = "SMC_OB_Liquidity";
      }
   }

   // --- PATH B: FIB STRATEGY (Fallback or Primary) ---
   if(!signalBuy && !signalSell && (InpEntryPath == PATH_AUTO || InpEntryPath == PATH_FIB_ONLY) && InpUseFibEntry)
   {
      // Fib Strategy: Structure + Golden Zone + Indicators + Trigger
      if(CheckFibEntry("BUY"))
      {
         signalBuy = true;
         strategy = "FIB_GoldenZone";
      }
      else if(CheckFibEntry("SELL"))
      {
         signalSell = true;
         strategy = "FIB_GoldenZone";
      }
   }

   // 5. Execution
   if(signalBuy) ExecuteTrade(ORDER_TYPE_BUY, strategy);
   if(signalSell) ExecuteTrade(ORDER_TYPE_SELL, strategy);
}

//+------------------------------------------------------------------+
//| CORE LOGIC: Triple Confirmation (Fib Path)                       |
//+------------------------------------------------------------------+
bool CheckTripleConfirmation(string dir)
{
   // 1. RSI Check (Institutional Zones)
   bool rsiOk = (dir == "BUY") ? (g_RSI <= InpRSI_BuyLevel) : (g_RSI >= InpRSI_SellLevel);
   
   // 2. MACD Check (Momentum Shift)
   double currentHist = g_MACD_Main - g_MACD_Signal;
   bool macdOk = (dir == "BUY") ? (currentHist > g_Prev_MACD_Hist_Value) : (currentHist < g_Prev_MACD_Hist_Value);

   // 3. Stochastic Check (Momentum Continuation)
   bool stochOk = false;
   if(dir == "BUY")
      stochOk = (g_Stoch_K > g_Prev_Stoch_K) && (g_Stoch_K < 80);
   else
      stochOk = (g_Stoch_K < g_Prev_Stoch_K) && (g_Stoch_K > 20);

   return rsiOk && macdOk && stochOk;
}

//+------------------------------------------------------------------+
//| CORE LOGIC: Candlestick Trigger                                  |
//+------------------------------------------------------------------+
bool CheckCandleTrigger(string dir)
{
   double open = iOpen(_Symbol, 0, 1);
   double close = iClose(_Symbol, 0, 1);
   double high = iHigh(_Symbol, 0, 1);
   double low = iLow(_Symbol, 0, 1);
   
   double body = MathAbs(close - open);
   double range = high - low;
   if(range == 0) return false;

   // Previous Candle (for Engulfing)
   double openPrev = iOpen(_Symbol, 0, 2);
   double closePrev = iClose(_Symbol, 0, 2);
   double bodyPrev = MathAbs(closePrev - openPrev);

   // 1. Engulfing
   bool engulfing = false;
   if(dir == "BUY")
      engulfing = (close > open) && (closePrev < openPrev) && (body > bodyPrev) && (close > openPrev);
   else
      engulfing = (close < open) && (closePrev > openPrev) && (body > bodyPrev) && (close < openPrev);

   // 2. Pinbar (Hammer/Shooting Star)
   bool pinbar = false;
   if(dir == "BUY")
   {
      double lowerWick = MathMin(open, close) - low;
      pinbar = (lowerWick > body * 2.0); // Wicked rejection from lows
   }
   else
   {
      double upperWick = high - MathMax(open, close);
      pinbar = (upperWick > body * 2.0); // Wicked rejection from highs
   }

   return engulfing || pinbar;
}

//+------------------------------------------------------------------+
//| CORE LOGIC: SMC Entry                                            |
//+------------------------------------------------------------------+
bool CheckSMCEntry(string dir)
{
   // v4.2 Strict Trend Rule:
   // Don't buy if trend is Bearish (Price < EMA), Don't sell if Bullish.
   if(dir == "BUY" && !trendBullish) return false;
   if(dir == "SELL" && trendBullish) return false;

   // 1. Must likely be active in a Persistent Zone (OB or FVG)
   bool inZone = false;
   double price = symbolInfo.Bid();
   
   // Check Order Blocks
   for(int i=0; i<ArraySize(activeOBs); i++)
   {
      if(activeOBs[i].invalidated) continue;
      // We ALLOW mitigated blocks if they are "Freshly" mitigated (just touched now)
      // But typically we want the FIRST reaction. 
      // Simplified: If Price effectively inside zone.
      
      bool correctDir = (dir == "BUY") ? activeOBs[i].isBullish : !activeOBs[i].isBullish;
      
      if(correctDir && price <= activeOBs[i].top && price >= activeOBs[i].bottom)
      {
         inZone = true;
         // Mark as mitigated? Only if we actually EXECUTE.
         // We'll mark mitigation in ManageOrderBlocks based on price action anyway.
         break;
      }
   }
   
   // Check FVGs (If OB not found)
   if(!inZone)
   {
      for(int i=0; i<ArraySize(activeFVGs); i++)
      {
         if(activeFVGs[i].invalidated || activeFVGs[i].filled) continue;
         bool correctDir = (dir == "BUY") ? activeFVGs[i].isBullish : !activeFVGs[i].isBullish;
         
         if(correctDir && price <= activeFVGs[i].top && price >= activeFVGs[i].bottom)
         {
            inZone = true;
            break;
         }
      }
   }
   
   if(!inZone) return false;

   // 2. Liquidity Sweep (Displacement Required)
   if(InpUseLiquiditySweeps)
   {
      if(!CheckLiquiditySweep(dir)) return false;
   }

   // 3. Candlestick Trigger
   return CheckCandleTrigger(dir);
}

//+------------------------------------------------------------------+
//| CORE LOGIC: Liquidity Sweep (Enhanced)                           |
//+------------------------------------------------------------------+
bool CheckLiquiditySweep(string dir)
{
   // Look back 10 bars for specific sweep pattern with DISPLACEMENT
   int lookback = 10;
   double currentClose = iClose(_Symbol, 0, 1);
   double currentOpen = iOpen(_Symbol, 0, 1);
   double currentBody = MathAbs(currentClose - currentOpen);
   
   // Displacement Check: Body must be > 30% or 50% of ATR?
   // Reviewer suggested body > X% of ATR.
   if(currentBody < (g_ATR * 0.3)) return false; // Weak move

   if(dir == "BUY")
   {
      int lowestBar = iLowest(_Symbol, 0, MODE_LOW, lookback, 2); 
      if(lowestBar < 0) return false;
      double recentLow = iLow(_Symbol, 0, lowestBar);
      
      double prevLow = iLow(_Symbol, 0, 1);
      
      // We swept the low but closed above
      return (prevLow < recentLow) && (currentClose > recentLow);
   }
   else // SELL
   {
      int highestBar = iHighest(_Symbol, 0, MODE_HIGH, lookback, 2);
      if(highestBar < 0) return false;
      double recentHigh = iHigh(_Symbol, 0, highestBar);
      
      double prevHigh = iHigh(_Symbol, 0, 1);
      
      // We swept high but closed below
      return (prevHigh > recentHigh) && (currentClose < recentHigh);
   }
}

//+------------------------------------------------------------------+
//| CORE LOGIC: Fib Entry                                            |
//+------------------------------------------------------------------+
bool CheckFibEntry(string dir)
{
   double range = swingHigh.price - swingLow.price;
   if(range <= g_ATR) return false; // Range too small

   double fib618, fib786;
   double price = symbolInfo.Bid();
   
   if(trendBullish) // Looking for Pullback to Buy
   {
      if(dir != "BUY") return false;
      fib618 = swingLow.price + range * 0.618;
      fib786 = swingLow.price + range * 0.786;
      
      if(price > fib618 || price < fib786) return false; 
   }
   else // Bearish
   {
      if(dir != "SELL") return false;
      fib618 = swingHigh.price - range * 0.618;
      fib786 = swingHigh.price - range * 0.786;
      
      if(price < fib618 || price > fib786) return false;
   }

   if(!CheckTripleConfirmation(dir)) return false;
   return CheckCandleTrigger(dir);
}

//+------------------------------------------------------------------+
//| UTILS: Updates                                                   |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   double bufRSI[1], bufMACD_M[2], bufMACD_S[2], bufStoch_K[2], bufStoch_D[1], bufATR[1];
   
   CopyBuffer(hRSI, 0, 1, 1, bufRSI);
   CopyBuffer(hMACD, 0, 1, 2, bufMACD_M);
   CopyBuffer(hMACD, 1, 1, 2, bufMACD_S);
   CopyBuffer(hStoch, 0, 1, 2, bufStoch_K); 
   CopyBuffer(hStoch, 1, 1, 1, bufStoch_D); 
   CopyBuffer(hATR, 0, 1, 1, bufATR);

   g_RSI = bufRSI[0];
   g_MACD_Main = bufMACD_M[1]; 
   g_MACD_Signal = bufMACD_S[1];
   g_Prev_MACD_Main = bufMACD_M[0];
   g_Prev_MACD_Signal = bufMACD_S[0];
   g_Prev_MACD_Hist_Value = g_Prev_MACD_Main - g_Prev_MACD_Signal;
   
   g_Stoch_K = bufStoch_K[1];
   g_Prev_Stoch_K = bufStoch_K[0]; 
   g_Stoch_D = bufStoch_D[0];
   g_ATR = bufATR[0];
}

void UpdateStructure()
{
   int hb = iHighest(_Symbol, 0, MODE_HIGH, InpSwingLookback, 1);
   int lb = iLowest(_Symbol, 0, MODE_LOW, InpSwingLookback, 1);
   
   swingHigh.price = iHigh(_Symbol, 0, hb);
   swingHigh.bar = hb;
   
   swingLow.price = iLow(_Symbol, 0, lb);
   swingLow.bar = lb;
   
   // Efficient EMA Call
   double emaBuf[1];
   CopyBuffer(hEMA, 0, 1, 1, emaBuf);
   trendBullish = (iClose(_Symbol, 0, 1) > emaBuf[0]);
}

void ManageOrderBlocks()
{
   // 1. Detect New OB
   // Bullish OB: Bearish Candle (1) followed by Strong Bullish Candle (0)
   double o1=iOpen(NULL,0,2), c1=iClose(NULL,0,2); 
   double o0=iOpen(NULL,0,1), c0=iClose(NULL,0,1); 
   double body0 = MathAbs(c0-o0);
   
   bool displacement = body0 > (g_ATR * InpDisplacement_Mult);
   
   if(displacement)
   {
      double h1 = iHigh(NULL,0,2);
      double l1 = iLow(NULL,0,2);
      
      // Bullish OB
      if(c1 < o1 && c0 > o0) 
      {
         OrderBlock ob;
         ob.isBullish = true;
         ob.top = h1;
         ob.bottom = l1;
         ob.time = iTime(NULL,0,2);
         ob.mitigated = false;
         ob.invalidated = false;
         ob.creationBar = iBarShift(NULL,0,ob.time);
         
         bool exists = false;
         int total = ArraySize(activeOBs);
         if(total > 0 && activeOBs[total-1].time == ob.time) exists = true;
         
         if(!exists) 
         {
            ArrayResize(activeOBs, total+1);
            activeOBs[total] = ob;
            // Print("New Bullish OB Created: ", ob.top);
         }
      }
      // Bearish OB
      else if(c1 > o1 && c0 < o0)
      {
         OrderBlock ob;
         ob.isBullish = false;
         ob.top = h1;
         ob.bottom = l1;
         ob.time = iTime(NULL,0,2);
         ob.mitigated = false;
         ob.invalidated = false;
         ob.creationBar = iBarShift(NULL,0,ob.time);

         bool exists = false;
         int total = ArraySize(activeOBs);
         if(total > 0 && activeOBs[total-1].time == ob.time) exists = true;
         
         if(!exists) 
         {
            ArrayResize(activeOBs, total+1);
            activeOBs[total] = ob;
            // Print("New Bearish OB Created: ", ob.bottom);
         }
      }
   }
   
   // 2. Cleanup / Mitigation / Invalidation
   // Price action: 0 (Current)
   double currentHigh = iHigh(NULL,0,0);
   double currentLow = iLow(NULL,0,0);
   
   for(int i=ArraySize(activeOBs)-1; i>=0; i--)
   {
      if(activeOBs[i].invalidated) continue;
      
      // v4.2 Logic: 
      // Invalidated = BROKEN (Price moves past the zone)
      // Mitigated = TOUCHED (Price enters zone)
      
      if(activeOBs[i].isBullish)
      {
         // Break of structure below OB Low = Invalidated
         if(currentLow < activeOBs[i].bottom) 
         {
             activeOBs[i].invalidated = true;
             continue; // Done
         }
         
         // Touch inside OB = Mitigated
         if(currentLow <= activeOBs[i].top && !activeOBs[i].mitigated)
             activeOBs[i].mitigated = true;
      }
      else // Bearish
      {
         // Break of structure above OB High = Invalidated
         if(currentHigh > activeOBs[i].top) 
         {
             activeOBs[i].invalidated = true;
             continue;
         }
         
         // Touch inside OB = Mitigated
         if(currentHigh >= activeOBs[i].bottom && !activeOBs[i].mitigated)
             activeOBs[i].mitigated = true;
      }
      
      // Remove old blocks (older than 100 bars)
      datetime now = iTime(NULL,0,0);
      if(now - activeOBs[i].time > PeriodSeconds() * 100)
         activeOBs[i].invalidated = true;
   }
}

void ManageFVGs()
{
   // FVG Logic: Gap between 2 candles. 
   // Index 3 (Left), 2 (Mid/Gap), 1 (Right/Current Completed)
   
   double h3 = iHigh(NULL,0,3);
   double l3 = iLow(NULL,0,3);
   
   double h1 = iHigh(NULL,0,1);
   double l1 = iLow(NULL,0,1);
   
   // v4.2 Fix: Verify Candle Direction (Displacement Candle 1)
   bool c1Bullish = (iClose(NULL,0,1) > iOpen(NULL,0,1));
   bool c1Bearish = (iClose(NULL,0,1) < iOpen(NULL,0,1));
   
   // Bullish FVG
   if(l1 > h3) 
   {
      double gapSize = l1 - h3;
      // Added Check: Candle 1 must be Bullish to justify a Bullish FVG (strong move UP)
      if(gapSize > g_ATR * 0.3 && c1Bullish) 
      {
         FVG fvg;
         fvg.isBullish = true;
         fvg.top = l1;
         fvg.bottom = h3;
         fvg.time = iTime(NULL,0,2);
         fvg.filled = false;
         fvg.invalidated = false;
         
         bool exists = false;
         int total = ArraySize(activeFVGs);
         if(total > 0 && activeFVGs[total-1].time == fvg.time) exists = true;
         
         if(!exists)
         {
            ArrayResize(activeFVGs, total+1);
            activeFVGs[total] = fvg;
         }
      }
   }
   
   // Bearish FVG
   if(l3 > h1) 
   {
       double gapSize = l3 - h1;
       // Added Check: Candle 1 must be Bearish to justify a Bearish FVG (strong move DOWN)
       if(gapSize > g_ATR * 0.3 && c1Bearish)
       {
         FVG fvg;
         fvg.isBullish = false;
         fvg.top = l3;
         fvg.bottom = h1;
         fvg.time = iTime(NULL,0,2);
         fvg.filled = false;
         fvg.invalidated = false;
         
         bool exists = false;
         int total = ArraySize(activeFVGs);
         if(total > 0 && activeFVGs[total-1].time == fvg.time) exists = true;
         
         if(!exists)
         {
            ArrayResize(activeFVGs, total+1);
            activeFVGs[total] = fvg;
         }
       }
   }
   
   // Cleanup FVGs
   double cHigh = iHigh(NULL,0,0);
   double cLow = iLow(NULL,0,0);
   
   for(int i=ArraySize(activeFVGs)-1; i>=0; i--)
   {
      if(activeFVGs[i].invalidated || activeFVGs[i].filled) continue;
      
      if(activeFVGs[i].isBullish)
      {
         // Invalidated if price closes/moves below bottom? Usually "filled" means touched.
         // Let's say filled if touched, invalidated if CRUSHED.
         if(cLow < activeFVGs[i].bottom) activeFVGs[i].invalidated = true; // Broken
         else if(cLow <= activeFVGs[i].top) activeFVGs[i].filled = true;   // Filled
      }
      else
      {
         if(cHigh > activeFVGs[i].top) activeFVGs[i].invalidated = true; // Broken
         else if(cHigh >= activeFVGs[i].bottom) activeFVGs[i].filled = true; // Filled
      }
      
      if(iTime(NULL,0,0) - activeFVGs[i].time > PeriodSeconds() * 50)
         activeFVGs[i].invalidated = true;
   }
}

//+------------------------------------------------------------------+
//| UTILS: Execution                                                 |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, string comment)
{
   double sl=0, tp=0;
   double price = (type == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
   
   // ATR Based SL
   double slDist = g_ATR * InpSL_ATR_Mult;
   double tpDist = slDist * InpRiskReward;
   
   if(type == ORDER_TYPE_BUY)
   {
      sl = price - slDist;
      tp = price + tpDist;
   }
   else
   {
      sl = price + slDist;
      tp = price - tpDist;
   }
   
   // Gold-Safe Lot Calculation
   double equity = account.Equity();
   double riskAmount = equity * (InpRiskPercent / 100.0);
   
   // Critical: Handle Contract Size (e.g. 100 for Standard, 10 for Mini, 1 for Micro)
   // Profit = (Close - Open) * ContractSize * Lots
   // Risk = (SL_Dist) * ContractSize * Lots
   // Lots = Risk / (SL_Dist * ContractSize)
   
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contractSize == 0) contractSize = 100; // Default fallback
   
   double lotSize = riskAmount / (slDist * contractSize);
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Safety Caps
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot; // Or return if too small
   if(lotSize > maxLot) lotSize = maxLot;
   
   // Step Normalization
   lotSize = MathFloor(lotSize / stepLot) * stepLot;

   trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, comment);
   dailyTrades++;
}

//+------------------------------------------------------------------+
//| UTILS: Helpers                                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, 0, 0);
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

bool CheckKillzone()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   int utcHour = (dt.hour - InpBrokerOffset + 24) % 24;
   
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
      lastTradeDate = today;
      dailyTrades = 0;
      dailyStartEquity = account.Equity();
   }
   
   double currentEq = account.Equity();
   double dd = (dailyStartEquity - currentEq) / dailyStartEquity * 100.0;
   
   if(dd >= InpMaxDailyDD)
   {
      Comment("⛔ DAILY DRAWDOWN HIT: ", DoubleToString(dd, 2), "%");
      return false;
   }
   
   return true;
}

void UpdateDashboard()
{
   string text = "🥇 XAU PRO v4.2 (Production) | " + EnumToString(InpSessionMode) + "\n";
   text += "--------------------------------------\n";
   text += "Price: " + DoubleToString(symbolInfo.Bid(), 2) + "\n";
   text += "Trend: " + (trendBullish ? "BULLISH (Buy OBs Only)" : "BEARISH (Sell OBs Only)") + "\n";
   text += "Active OBs: " + IntegerToString(ArraySize(activeOBs)) + " | FVGs: " + IntegerToString(ArraySize(activeFVGs)) + "\n";
   text += "Spread: " + IntegerToString(symbolInfo.Spread()) + (symbolInfo.Spread() > InpMaxSpread ? " (HIGH!)" : " (OK)") + "\n";
   
   Comment(text);
}
