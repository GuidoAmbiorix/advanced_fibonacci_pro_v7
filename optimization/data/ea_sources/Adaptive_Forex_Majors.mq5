//+------------------------------------------------------------------+
//|                                     Adaptive_Forex_Majors.mq5    |
//|                                  Based on Institutional Edge Pro  |
//|                       Optimized for EURUSD, GBPUSD, AUDUSD       |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro"
#property link      "https://institutional-edge.com"
#property version   "1.30"
#property description "Forex Majors Optimized EA - Institutional Grade + Elliott"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_TRAIL_STATE
{
   TS_ENTRY_PROTECT    = 0, // Initial Stop (Wait for breakout)
   TS_STRUCTURE_LOCK   = 1, // Move to BE / Structure
   TS_MOMENTUM_TRAIL   = 2, // Tight trail on momentum
   TS_EXHAUSTION_LOCK  = 3  // Lock profit on trend death
};

//+------------------------------------------------------------------+
//| INPUTS & CONFIGURATION                                           |
//+------------------------------------------------------------------+
input group "========== ELLIOTT WAVE MODE =========="
input bool InpUse_Elliott_Mode     = false;   // 🌊 WAVE 3 FILTER (Strict)

input group "========== STRATEGY TOGGLES =========="
input bool InpEnable_Institutional = true;    // Institutional Sweep
input bool InpEnable_VWAP_Scalp    = true;    // Mean Reversion (VWAP Proxy)
input bool InpEnable_Fibonacci     = true;    // Fibonacci Golden Zone
input bool InpEnable_Stochastic    = true;    // Stochastic Momentum
input int  InpSwap_Lookback        = 20;      // Lookback: 20 (Slower for Forex)
input ENUM_TIMEFRAMES InpTrend_Timeframe = PERIOD_H4; 
input ENUM_TIMEFRAMES InpContext_Timeframe = PERIOD_H1; 

input group "========== RISK MANAGEMENT =========="
input double InpMax_Drawdown_Percent = 10.0;  // Max Equity Drawdown %
input double InpDaily_Loss_Percent   = 5.0;   // Max Daily Loss %
input double InpRisk_Per_Trade       = 1.0;   // Risk 1.0%
input double InpRisk_Reward_Ratio    = 3.0;   // 1:3.0 (Trend Following)
input double InpMaxLot_Per_Trade     = 0.5;   // Max Lot Cap
input int    InpCooldownMinutes      = 30;    // Cooldown after loss
input int    InpMaxSpread_Points     = 20;    // Max Spread (Points)

input group "========== ADVANCED TRAILING =========="
input bool   InpUse_Advanced_Trail   = true;  // Enable State Machine Trail
input double InpTrail_Structure_R    = 1.0;   // R-Multiple to start Structure Trail
input double InpTrail_Momentum_R     = 2.0;   // R-Multiple to start Momentum Trail (Tight)

input group "========== TRAILING CONFIGURATION (Basic) =========="
input double InpATR_SL_Mult          = 1.5;   // Tighter Stop (1.5x ATR)
input double InpATR_TP_Mult          = 4.5;   // Wider Target (4.5x ATR)

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;
input int InpADX_Period      = 14;
input int InpADX_Threshold   = 20;            // Lower Threshold (20) for Forex Trends
input int InpATR_Period      = 14;
input int InpStoch_K         = 14;
input int InpStoch_D         = 3;
input int InpVariable_MA     = 20;            // VWAP Proxy (SMA)

input group "========== KILLZONES (EST TIME) =========="
input int    InpServerTimeOffset        = 2;     // Server Time Offset
input bool   InpUse_KillZones           = true;  // Enabled mainly for Majors
input string InpAsian_Start             = "19:00"; // Asian (AUD/NZD/JPY)
input string InpAsian_End               = "02:00";
input string InpLondon_Start            = "03:00"; // London Open
input string InpLondon_End              = "08:00";
input string InpNY_Start                = "08:00"; // NY Open (Overlap)
input string InpNY_End                  = "12:00";
input bool   InpUse_Asian_Session       = true;  // Enable Asian for AUD pairs

input group "========== SYSTEM =========="
input int InpMagicNumber     = 777777;        // Unique Magic for Forex
input bool InpDebugMode      = true;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

// Indicator Handles
int hRSI, hADX, hATR, hStoch, hMACD, hEMA20;
int hEMA50_Trend, hEMA200_Trend; 
int hADX_Context, hEMA50_Context, hEMA200_Context;
int hVWAP;

// State
double AccountBalanceStartDay;
double AccountHighWaterMark;
datetime LastDayChecked;
datetime EngineCooldownUntil = 0;

// Trailing State (Single Position - Netting Optimized)
ENUM_TRAIL_STATE g_CurrentTrailState = TS_ENTRY_PROTECT;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   symbolInfo.Name(_Symbol);
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   if(!IsValidForexMajor())
   {
      Print("❌ Error: This EA is optimized for Forex Major Pairs (EUR, GBP, AUD, etc).");
      return INIT_FAILED;
   }

   // Initialize Indicators
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hADX = iADX(_Symbol, PERIOD_CURRENT, InpADX_Period); 
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   hStoch = iStochastic(_Symbol, PERIOD_CURRENT, InpStoch_K, InpStoch_D, 3, MODE_SMA, STO_LOWHIGH);
   hMACD = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   hEMA20 = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   
   hEMA50_Trend = iMA(_Symbol, InpTrend_Timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200_Trend = iMA(_Symbol, InpTrend_Timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   hADX_Context    = iADX(_Symbol, InpContext_Timeframe, 14); 
   hEMA50_Context  = iMA(_Symbol, InpContext_Timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200_Context = iMA(_Symbol, InpContext_Timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   hVWAP = iMA(_Symbol, PERIOD_CURRENT, InpVariable_MA, 0, MODE_SMA, PRICE_TYPICAL);

   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE || 
      hStoch == INVALID_HANDLE || hEMA50_Trend == INVALID_HANDLE)
   {
      Print("❌ Error creating indicators!");
      return INIT_FAILED;
   }

   AccountBalanceStartDay = accountInfo.Balance();
   AccountHighWaterMark = accountInfo.Equity();
   LastDayChecked = iTime(_Symbol, PERIOD_D1, 0);

   Print("✅ Forex Majors EA v1.3 (Elliott Mode) Initialized");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI); IndicatorRelease(hADX); IndicatorRelease(hATR);
   IndicatorRelease(hStoch); IndicatorRelease(hMACD);
   IndicatorRelease(hEMA20); 
   IndicatorRelease(hEMA50_Trend); IndicatorRelease(hEMA200_Trend);
   IndicatorRelease(hADX_Context); IndicatorRelease(hEMA50_Context); IndicatorRelease(hEMA200_Context);
   IndicatorRelease(hVWAP);
}

//+------------------------------------------------------------------+
//| UTILS                                                            |
//+------------------------------------------------------------------+
bool IsValidForexMajor()
{
   string sym = _Symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") >= 0) return false;
   if(StringFind(sym, "XAG") >= 0) return false;
   if(StringFind(sym, "OIL") >= 0) return false;
   if(StringFind(sym, "US30") >= 0) return false;
   if(StringFind(sym, "US500") >= 0) return false;
   if(StringFind(sym, "BTC") >= 0) return false;
   return true;
}

bool CheckFundingRules()
{
   double equity = accountInfo.Equity();
   if(equity > AccountHighWaterMark) AccountHighWaterMark = equity;
   
   double bal = accountInfo.Balance();
   double dd = (bal - equity) / bal * 100.0;
   
   if(dd >= InpMax_Drawdown_Percent) return false; 
   
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != LastDayChecked)
   {
      AccountBalanceStartDay = bal;
      LastDayChecked = currentDay;
   }
   
   double dailyLoss = (AccountBalanceStartDay - equity) / AccountBalanceStartDay * 100.0;
   if(dailyLoss >= InpDaily_Loss_Percent) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   if(InpUse_KillZones && !IsKillZone()) return;
   if(TimeCurrent() < EngineCooldownUntil) return;
   if(!CheckFundingRules()) return;
   
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread_Points) return;

   double rsi[], adx[], atr[], stochK[], stochD[],  ema20[], ema50_htf[], ema200_htf[], vwap[];
   if(!GetIndicators(rsi, adx, atr, stochK, stochD, ema20, ema50_htf, ema200_htf, vwap)) return;
   
   // --- POSITION MANAGEMENT & TRAILING ---
   if(IsPositionOpen())
   {
      if(InpUse_Advanced_Trail) ManageAdvancedTrail(atr[0], adx[0]);
      return; 
   }
   else
   {
      if(g_CurrentTrailState != TS_ENTRY_PROTECT)
         g_CurrentTrailState = TS_ENTRY_PROTECT;
   }
   
   // --- ELLIOTT MODE FILTER ---
   if(InpUse_Elliott_Mode)
   {
      // Wave 3 Logic: ADX MUST be rising and > 25
      bool adxRising = (adx[0] > adx[1]);
      bool strongTrend = (adx[0] > 25);
      
      if(!adxRising || !strongTrend) return; // Skip if no impulse
      
      // ONLY Run Trend Strategies (Fib + Institutional)
      RunInstitutional(rsi, atr, ema20, ema50_htf, ema200_htf, adx, stochK, stochD, vwap);
      RunFibonacci(rsi, atr, ema20, ema50_htf, ema200_htf, adx, stochK, stochD, vwap);
      
      // SKIP Range Strategies in Elliott Mode
      return; 
   }

   // --- STANDARD MODE ---
   bool isTrend = (adx[0] > InpADX_Threshold);
   bool isRange = (adx[0] <= InpADX_Threshold);
   
   if(isTrend)
   {
      if(InpEnable_Institutional) RunInstitutional(rsi, atr, ema20, ema50_htf, ema200_htf, adx, stochK, stochD, vwap);
      if(InpEnable_Fibonacci)     RunFibonacci(rsi, atr, ema20, ema50_htf, ema200_htf, adx, stochK, stochD, vwap);
   }
   
   if(isRange)
   {
      if(InpEnable_VWAP_Scalp)    RunMeanReversion(rsi, atr, ema20, stochK, stochD, vwap);
      if(InpEnable_Stochastic)    RunStochastic(rsi, atr, ema20, stochK, stochD, vwap);
   }
}

//+------------------------------------------------------------------+
//| MARKET STRUCTURE CHECK (HH/HL or LH/LL)                          |
//+------------------------------------------------------------------+
bool CheckStructure(bool isBuy, int lookback=30)
{
   double highArr[], lowArr[];
   CopyHigh(_Symbol, PERIOD_CURRENT, 1, lookback, highArr);
   CopyLow(_Symbol, PERIOD_CURRENT, 1, lookback, lowArr);
   
   int h1 = ArrayMaximum(highArr, 0, lookback/2); // Recent High
   int h2 = ArrayMaximum(highArr, lookback/2, lookback/2); // Old High
   
   int l1 = ArrayMinimum(lowArr, 0, lookback/2); // Recent Low
   int l2 = ArrayMinimum(lowArr, lookback/2, lookback/2); // Old Low
   
   if(isBuy)
   {
      // Expect Higher High and Higher Low? 
      // Actually for Pullback (Fib): We want Higher High established, then pullback (Higher Low forming)
      // So Previous High (Old) < Recent High (Swing).
      // And Recent Low (current Pullback) > Old Low.
      return (highArr[h1] >= highArr[h2] && lowArr[l1] > lowArr[l2]);
   }
   else
   {
      // Sell: Lower Low and Lower High
      return (lowArr[l1] <= lowArr[l2] && highArr[h1] < highArr[h2]);
   }
}

//+------------------------------------------------------------------+
//| STRATEGIES                                                       |
//+------------------------------------------------------------------+
void RunInstitutional(double &rsi[], double &atr[], double &ema20[], double &ema50_htf[], double &ema200_htf[], double &adx[], double &stochK[], double &stochD[], double &vwap[])
{
   int lookback = InpSwap_Lookback;
   double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 1));
   double swingLow  = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 1));
   double close = iClose(_Symbol, PERIOD_CURRENT, 0); 
   double high = iHigh(_Symbol, PERIOD_CURRENT, 0); double low = iLow(_Symbol, PERIOD_CURRENT, 0);
   
   bool uptrend = (ema50_htf[0] > ema200_htf[0]);
   bool downtrend = (ema50_htf[0] < ema200_htf[0]);

   if(low < swingLow && close > swingLow && uptrend)
   {
      // Elliott: Check Structure
      if(InpUse_Elliott_Mode && !CheckStructure(true)) return;
      ExecuteTrade(ORDER_TYPE_BUY, close - InpATR_SL_Mult*atr[0], close + InpATR_TP_Mult*atr[0], "Inst_Buy");
   }
   else if(high > swingHigh && close < swingHigh && downtrend)
   {
      // Elliott: Check Structure
      if(InpUse_Elliott_Mode && !CheckStructure(false)) return;
      ExecuteTrade(ORDER_TYPE_SELL, close + InpATR_SL_Mult*atr[0], close - InpATR_TP_Mult*atr[0], "Inst_Sell");
   }
}

void RunFibonacci(double &rsi[], double &atr[], double &ema20[], double &ema50_htf[], double &ema200_htf[], double &adx[], double &stochK[], double &stochD[], double &vwap[])
{
   int lookback = 30; 
   double high = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 1));
   double low  = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 1));
   double range = high - low;
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(range == 0) return;
   
   bool uptrend = (ema50_htf[0] > ema200_htf[0]);
   bool downtrend = (ema50_htf[0] < ema200_htf[0]);
   
   if(uptrend)
   {
      double fib50 = low + range*0.50; double fib618 = low + range*0.618;
      if(close >= fib50 && close <= fib618) 
      {
         if(InpUse_Elliott_Mode && !CheckStructure(true)) return;
         
         double sl = low - atr[0];
         double tp = close + (InpRisk_Reward_Ratio * (close - sl)); 
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Fib_Buy"); 
      }
   }
   else if(downtrend)
   {
      double fib50 = high - range*0.50; double fib618 = high - range*0.618;
      if(close <= fib50 && close >= fib618)
      {
         if(InpUse_Elliott_Mode && !CheckStructure(false)) return;
         
         double sl = high + atr[0];
         double tp = close - (InpRisk_Reward_Ratio * (sl - close));
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Fib_Sell"); 
      }
   }
}

void RunMeanReversion(double &rsi[], double &atr[], double &ema20[], double &stochK[], double &stochD[], double &vwap[])
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(close < vwap[0] && rsi[0] < 35)
       ExecuteTrade(ORDER_TYPE_BUY, close - InpATR_SL_Mult*atr[0], vwap[0], "VWAP_Buy"); 
   else if(close > vwap[0] && rsi[0] > 65)
       ExecuteTrade(ORDER_TYPE_SELL, close + InpATR_SL_Mult*atr[0], vwap[0], "VWAP_Sell");
}

void RunStochastic(double &rsi[], double &atr[], double &ema20[], double &stochK[], double &stochD[], double &vwap[])
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(stochK[1] < 20 && stochD[1] < 20 && stochK[0] > stochD[0])
       ExecuteTrade(ORDER_TYPE_BUY, close - InpATR_SL_Mult*atr[0], close + InpATR_TP_Mult*atr[0], "Stoch_Buy");
   else if(stochK[1] > 80 && stochD[1] > 80 && stochK[0] < stochD[0])
       ExecuteTrade(ORDER_TYPE_SELL, close + InpATR_SL_Mult*atr[0], close - InpATR_TP_Mult*atr[0], "Stoch_Sell");
}

//+------------------------------------------------------------------+
//| EXECUTION                                                        |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl, double tp, string comment)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = MathAbs(price - sl);
   
   double balance = accountInfo.Balance();
   double riskVal = balance * (InpRisk_Per_Trade / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSz == 0 || tickVal == 0) return;
   
   double points = slDist / tickSz;
   double vol = riskVal / (points * tickVal);
   
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   vol = MathFloor(vol / step) * step;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(vol < minLot) vol = minLot; 
   if(vol > maxLot) vol = maxLot;
   if(vol > InpMaxLot_Per_Trade) vol = InpMaxLot_Per_Trade;
   
   trade.PositionOpen(_Symbol, type, vol, price, sl, tp, comment);
}

//+------------------------------------------------------------------+
//| ADVANCED TRAILING STOP (Ported from God Mode)                    |
//+------------------------------------------------------------------+
void ManageAdvancedTrail(double atr, double adx)
{
   // Get current position (Netting = Only 1)
   if(!position.Select(_Symbol)) return;
   if(position.Magic() != InpMagicNumber) return;
   
   double entry = position.PriceOpen();
   double current = position.PriceCurrent();
   double sl = position.StopLoss();
   double tp = position.TakeProfit();
   bool isBuy = (position.PositionType() == POSITION_TYPE_BUY);
   
   // Calculate Profilt in R (Risk Multiples)
   // Assuming Initial Risk was ~1.5 ATR (Estimated)
   double riskUnit = atr * InpATR_SL_Mult;
   if(riskUnit == 0) riskUnit = _Point * 100;
   
   double profitPoints = isBuy ? (current - entry) : (entry - current);
   double profitR = profitPoints / riskUnit; // Current R multiple
   
   // 1. UPDATE STATE
   if(g_CurrentTrailState == TS_ENTRY_PROTECT)
   {
      if(profitR >= InpTrail_Structure_R) g_CurrentTrailState = TS_STRUCTURE_LOCK;
   }
   else if(g_CurrentTrailState == TS_STRUCTURE_LOCK)
   {
      if(profitR >= InpTrail_Momentum_R) g_CurrentTrailState = TS_MOMENTUM_TRAIL;
   }
   else if(g_CurrentTrailState == TS_MOMENTUM_TRAIL)
   {
      if(adx < 20) g_CurrentTrailState = TS_EXHAUSTION_LOCK;
   }
   
   // 2. CALCULATE NEW SL BASED ON STATE
   double newSL = sl;
   
   switch(g_CurrentTrailState)
   {
      case TS_ENTRY_PROTECT:
         if(profitR >= 0.8) 
         {
             double be = entry + (isBuy ? riskUnit*0.1 : -riskUnit*0.1); 
             newSL = isBuy ? MathMax(sl, be) : MathMin(sl, be);
         }
         break;
         
      case TS_STRUCTURE_LOCK: 
         {
             double trailDist = atr * 1.0;
             double level = isBuy ? (current - trailDist) : (current + trailDist);
             newSL = isBuy ? MathMax(sl, level) : MathMin(sl, level);
         }
         break;
         
      case TS_MOMENTUM_TRAIL: 
         {
             double trailDist = atr * 0.5;
             double level = isBuy ? (current - trailDist) : (current + trailDist);
             newSL = isBuy ? MathMax(sl, level) : MathMin(sl, level);
         }
         break;
         
      case TS_EXHAUSTION_LOCK: 
         {
             double trailDist = atr * 0.3;
             double level = isBuy ? (current - trailDist) : (current + trailDist);
             newSL = isBuy ? MathMax(sl, level) : MathMin(sl, level);
         }
         break;
   }
   
   // 3. APPLY UPDATE
   if(MathAbs(newSL - sl) > _Point)
   {
      trade.PositionModify(position.Ticket(), newSL, tp);
      if(InpDebugMode) Print("🔄 Trail Update: State ", EnumToString(g_CurrentTrailState), " | R: ", DoubleToString(profitR, 2));
   }
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION (Cooldown Logic)                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong ticket = trans.deal;
      if(HistoryDealSelect(ticket))
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         {
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
            {
               double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               if(profit < 0)
               {
                  EngineCooldownUntil = TimeCurrent() + (InpCooldownMinutes * 60);
                  Print("🛑 Loss Detected (", DoubleToString(profit, 2), ") -> Cooldown for ", InpCooldownMinutes, " mins");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
bool IsKillZone()
{
   datetime estTime = TimeCurrent() - (InpServerTimeOffset * 3600);
   MqlDateTime dt;
   TimeToStruct(estTime, dt);
   string cur = StringFormat("%02d:%02d", dt.hour, dt.min);
   if(InpUse_Asian_Session && CheckTime(cur, InpAsian_Start, InpAsian_End)) return true;
   if(CheckTime(cur, InpLondon_Start, InpLondon_End)) return true;
   if(CheckTime(cur, InpNY_Start, InpNY_End)) return true;
   return false;
}

bool CheckTime(string cur, string start, string end)
{
   if(start < end) return (cur >= start && cur <= end);
   else return (cur >= start || cur <= end);
}

bool GetIndicators(double &rsi[], double &adx[], double &atr[], double &stochK[], double &stochD[], double &ema20[], double &ema50_htf[], double &ema200_htf[], double &vwap[])
{
   if(CopyBuffer(hRSI,0,0,3,rsi)<3) return false;
   if(CopyBuffer(hADX,0,0,3,adx)<3) return false; 
   if(CopyBuffer(hATR,0,0,3,atr)<3) return false;
   if(CopyBuffer(hStoch,0,0,3,stochK)<3) return false;
   if(CopyBuffer(hStoch,1,0,3,stochD)<3) return false;
   CopyBuffer(hEMA20,0,0,3,ema20);
   CopyBuffer(hVWAP,0,0,3,vwap);
   if(CopyBuffer(hEMA50_Trend, 0, 0, 3, ema50_htf) < 3) return false;
   if(CopyBuffer(hEMA200_Trend, 0, 0, 3, ema200_htf) < 3) return false;
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(adx,true); ArraySetAsSeries(atr,true);
   ArraySetAsSeries(stochK,true); ArraySetAsSeries(stochD,true);
   ArraySetAsSeries(ema20,true); ArraySetAsSeries(vwap,true);
   ArraySetAsSeries(ema50_htf,true); ArraySetAsSeries(ema200_htf,true);
   return true;
}

bool IsPositionOpen()
{
   return (PositionsTotal() > 0 && PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}
//+------------------------------------------------------------------+
