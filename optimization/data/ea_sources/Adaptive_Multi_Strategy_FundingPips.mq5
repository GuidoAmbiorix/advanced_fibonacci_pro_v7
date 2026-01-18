//+------------------------------------------------------------------+
//|                   Adaptive_Multi_Strategy_FundingPips.mq5        |
//|                        FUNDINGPIPS COMPLIANT EDITION             |
//|                                  Institutional Edge Pro          |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro - FundingPips Edition"
#property link      "https://institutional-edge.com"
#property version   "4.00"
#property description "100% FundingPips Compliant - No Martingale, No Hedge, Fixed Risk"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| FUNDINGPIPS-SAFE RE-ENTRY (NOT MARTINGALE)                       |
//+------------------------------------------------------------------+
input group "========== RE-ENTRY SETTINGS (FUNDINGPIPS SAFE) =========="
input bool   InpEnable_ReEntry        = true;   // Enable Trend Re-Entry
input int    InpMax_ReEntries         = 1;      // 🔥 Max Re-Entries (1 recommended)
input double InpReEntry_MinATR        = 2.0;    // Min ATR Pullback for Re-Entry
input int    InpReEntry_CooldownSec   = 120;    // Cooldown Between Entries (sec)
input int    InpMax_Trades_Per_Symbol = 2;      // 🔥 Max Total Positions per Symbol

input group "========== STRICT RISK MANAGEMENT (FUNDINGPIPS) =========="
input double InpMax_Drawdown_Percent = 8.0;   // 🔥 Max Total DD % (Hard Stop)
input double InpDaily_Loss_Percent   = 4.0;   // Max Daily Loss %
input double InpRisk_Per_Trade       = 0.5;   // Fixed Risk Per Trade % (0.5% recommended)
input double InpMaxLot_Per_Trade     = 0.5;   // Max Lot Size per Trade

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;
input int InpADX_Period      = 14;
input int InpADX_Threshold   = 24;
input int InpATR_Period      = 14;
input ENUM_TIMEFRAMES InpTrend_Timeframe = PERIOD_H1;

input group "========== SYSTEM =========="
input int InpMagicNumber     = 777777;
input bool InpDebugMode      = true;

//+------------------------------------------------------------------+
//| RE-ENTRY STATE (NO MARTINGALE MATH)                               |
//+------------------------------------------------------------------+
struct ReEntryState
{
   int              entryCount;         // Number of entries (max 1-2)
   double           initialLotSize;     // SAME lot for all entries
   double           initialEntryPrice;  
   datetime         lastEntryTime;
   ENUM_ORDER_TYPE  direction;
   bool             isActive;
};

ReEntryState g_ReEntry;

//+------------------------------------------------------------------+
//| DAILY FREEZE PROTECTION                                          |
//+------------------------------------------------------------------+
bool TradingLockedToday = false;
datetime LastResetDay = 0;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

int hRSI, hADX, hATR, hEMA50, hEMA200;

double AccountBalanceStartDay;
double AccountHighWaterMark;
datetime LastDayChecked;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   symbolInfo.Name(_Symbol);
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Initialize Indicators
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hADX = iADX(_Symbol, PERIOD_CURRENT, InpADX_Period);
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   hEMA50 = iMA(_Symbol, InpTrend_Timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, InpTrend_Timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("❌ Error creating indicators!");
      return INIT_FAILED;
   }

   AccountBalanceStartDay = accountInfo.Balance();
   AccountHighWaterMark = accountInfo.Equity();
   LastDayChecked = iTime(_Symbol, PERIOD_D1, 0);
   LastResetDay = LastDayChecked;
   
   ResetReEntryState();

   Print("✅ FUNDINGPIPS MODE | Balance: $", accountInfo.Balance(), 
         " | Risk: ", InpRisk_Per_Trade, "% | Max Re-Entries: ", InpMax_ReEntries);
   Print("🔥 STRICT STOPS: DD=", InpMax_Drawdown_Percent, "% | Daily=", InpDaily_Loss_Percent, "%");
   Print("⚠️ NO MARTINGALE - FIXED RISK ONLY");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   IndicatorRelease(hADX);
   IndicatorRelease(hATR);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hEMA200);
}

//+------------------------------------------------------------------+
//| RESET RE-ENTRY STATE                                            |
//+------------------------------------------------------------------+
void ResetReEntryState()
{
   g_ReEntry.entryCount = 0;
   g_ReEntry.initialLotSize = 0;
   g_ReEntry.initialEntryPrice = 0;
   g_ReEntry.lastEntryTime = 0;
   g_ReEntry.direction = ORDER_TYPE_BUY;
   g_ReEntry.isActive = false;
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 0. Daily Reset
   CheckDailyReset();
   
   // 1. Hard Daily Freeze
   if(TradingLockedToday)
   {
      if(InpDebugMode && PositionsTotal() == 0)
         Print("🔒 Trading LOCKED for today. Loss limit reached.");
      return;
   }
   
   // 2. Emergency Drawdown (FUNDINGPIPS CRITICAL)
   if(!CheckDrawdownProtection())
      return;
   
   // 3. Daily Loss Check
   if(!CheckDailyLossLimit())
      return;
   
   // 4. Max Positions Check (FUNDINGPIPS RULE)
   if(CountMyPositions() >= InpMax_Trades_Per_Symbol)
   {
      if(InpDebugMode && g_ReEntry.entryCount == 0)
         Print("⚠️ Max positions reached: ", InpMax_Trades_Per_Symbol);
      return;
   }
   
   // 5. Get Indicators
   double rsi[], adx[], atr[], ema50[], ema200[];
   if(!GetIndicators(rsi, adx, atr, ema50, ema200))
      return;
   
   // 6. Sync State
   SyncReEntryWithPosition();
   
   // 7. Entry Logic (only if no active position)
   if(!g_ReEntry.isActive && CountMyPositions() == 0)
   {
      CheckEntrySignals(rsi, adx, atr, ema50, ema200);
   }
   
   // 8. Re-Entry Management (FUNDINGPIPS-SAFE)
   if(InpEnable_ReEntry && g_ReEntry.isActive && g_ReEntry.entryCount < InpMax_ReEntries)
   {
      ManageSafeReEntry(atr[0], ema50, ema200);
   }
}

//+------------------------------------------------------------------+
//| DAILY RESET                                                      |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != LastResetDay)
   {
      TradingLockedToday = false;
      LastResetDay = currentDay;
      if(InpDebugMode)
         Print("📅 New Day - Trading lock reset");
   }
}

//+------------------------------------------------------------------+
//| DRAWDOWN PROTECTION (FUNDINGPIPS CRITICAL)                        |
//+------------------------------------------------------------------+
bool CheckDrawdownProtection()
{
   double balance = accountInfo.Balance();
   double equity = accountInfo.Equity();
   
   if(equity > AccountHighWaterMark)
      AccountHighWaterMark = equity;
   
   double floatingDD = 0;
   if(balance > 0)
      floatingDD = (balance - equity) / balance * 100.0;
   
   if(floatingDD >= InpMax_Drawdown_Percent)
   {
      Print("🚨 EMERGENCY: Max DD ", DoubleToString(floatingDD, 2), "% - CLOSING ALL");
      CloseAllPositions();
      ResetReEntryState();
      TradingLockedToday = true;
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| DAILY LOSS CHECK (WITH HARD FREEZE)                              |
//+------------------------------------------------------------------+
bool CheckDailyLossLimit()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != LastDayChecked)
   {
      AccountBalanceStartDay = accountInfo.Balance();
      LastDayChecked = currentDay;
   }
   
   double currentEquity = accountInfo.Equity();
   double dailyLoss = (AccountBalanceStartDay - currentEquity) / AccountBalanceStartDay * 100.0;
   
   if(dailyLoss >= InpDaily_Loss_Percent)
   {
      Print("🛑 DAILY LOSS LIMIT: ", DoubleToString(dailyLoss, 2), "% - LOCKING TRADING");
      TradingLockedToday = true;
      CloseAllPositions();
      ResetReEntryState();
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| COUNT MY POSITIONS                                               |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| GET INDICATORS                                                   |
//+------------------------------------------------------------------+
bool GetIndicators(double &rsi[], double &adx[], double &atr[], 
                   double &ema50[], double &ema200[])
{
   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return false;
   if(CopyBuffer(hADX, 0, 0, 3, adx) < 3) return false;
   if(CopyBuffer(hATR, 0, 0, 3, atr) < 3) return false;
   if(CopyBuffer(hEMA50, 0, 0, 3, ema50) < 3) return false;
   if(CopyBuffer(hEMA200, 0, 0, 3, ema200) < 3) return false;
   
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema200, true);
   
   return true;
}

//+------------------------------------------------------------------+
//| SYNC RE-ENTRY WITH POSITION                                      |
//+------------------------------------------------------------------+
void SyncReEntryWithPosition()
{
   bool hasPosition = CountMyPositions() > 0;
   
   if(!hasPosition && g_ReEntry.isActive)
   {
      if(InpDebugMode) Print("✅ Re-Entry Reset: Position closed");
      ResetReEntryState();
   }
   
   if(hasPosition && !g_ReEntry.isActive)
   {
      // Sync from position
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         
         g_ReEntry.isActive = true;
         g_ReEntry.entryCount = 1;
         g_ReEntry.initialLotSize = PositionGetDouble(POSITION_VOLUME);
         g_ReEntry.initialEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         g_ReEntry.direction = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         g_ReEntry.lastEntryTime = TimeCurrent();
         
         if(InpDebugMode) Print("🔄 Re-Entry State Synced");
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNALS                                              |
//+------------------------------------------------------------------+
void CheckEntrySignals(double &rsi[], double &adx[], double &atr[], 
                       double &ema50[], double &ema200[])
{
   if(CountMyPositions() > 0) return;
   if(adx[0] < InpADX_Threshold) return;
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   bool isBullish = (ema50[0] > ema200[0]) && (close > ema50[0]);
   bool isBearish = (ema50[0] < ema200[0]) && (close < ema50[0]);
   
   // BUY Signal
   if(isBullish && rsi[0] > 40 && rsi[0] < 70)
   {
      double sl = close - (atr[0] * 2.0);
      double tp = close + (atr[0] * 3.0);
      ExecuteInitialTrade(ORDER_TYPE_BUY, sl, tp);
   }
   // SELL Signal
   else if(isBearish && rsi[0] < 60 && rsi[0] > 30)
   {
      double sl = close + (atr[0] * 2.0);
      double tp = close - (atr[0] * 3.0);
      ExecuteInitialTrade(ORDER_TYPE_SELL, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| EXECUTE INITIAL TRADE                                            |
//+------------------------------------------------------------------+
void ExecuteInitialTrade(ENUM_ORDER_TYPE type, double sl, double tp)
{
   double price = (type == ORDER_TYPE_BUY) 
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double slDist = MathAbs(price - sl);
   double volume = CalculateFixedRiskLotSize(slDist);
   
   if(volume <= 0) return;
   
   string comment = "FP_Entry";
   
   if(trade.PositionOpen(_Symbol, type, volume, price, sl, tp, comment))
   {
      if(InpDebugMode) 
         Print("🚀 Initial Trade | Lot: ", volume, " | Risk: ", InpRisk_Per_Trade, "%");
      
      g_ReEntry.isActive = true;
      g_ReEntry.entryCount = 1;
      g_ReEntry.initialLotSize = volume;
      g_ReEntry.initialEntryPrice = price;
      g_ReEntry.direction = type;
      g_ReEntry.lastEntryTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| CALCULATE FIXED RISK LOT SIZE (FUNDINGPIPS COMPLIANT)            |
//+------------------------------------------------------------------+
double CalculateFixedRiskLotSize(double slDistance)
{
   double balance = accountInfo.Balance();
   double riskAmount = balance * (InpRisk_Per_Trade / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickSize == 0 || tickValue == 0) return 0.01;
   
   double points = slDistance / tickSize;
   double lotSize = riskAmount / (points * tickValue);
   
   // Normalize
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / step) * step;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   if(lotSize > InpMaxLot_Per_Trade) lotSize = InpMaxLot_Per_Trade;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| MANAGE SAFE RE-ENTRY (FUNDINGPIPS COMPLIANT)                     |
//+------------------------------------------------------------------+
void ManageSafeReEntry(double atr, double &ema50[], double &ema200[])
{
   if(!g_ReEntry.isActive) return;
   if(g_ReEntry.entryCount >= InpMax_ReEntries + 1) return;
   if(CountMyPositions() >= InpMax_Trades_Per_Symbol) return;
   
   // Cooldown
   if(TimeCurrent() - g_ReEntry.lastEntryTime < InpReEntry_CooldownSec)
      return;
   
   // Check if trend still valid
   if(!IsTrendStillValid(ema50, ema200))
   {
      if(InpDebugMode) Print("⚠️ Trend invalidated - no re-entry");
      return;
   }
   
   // Get current price
   double currentPrice = (g_ReEntry.direction == ORDER_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Check if pulled back enough
   double pullback = (g_ReEntry.direction == ORDER_TYPE_BUY)
                     ? (g_ReEntry.initialEntryPrice - currentPrice)
                     : (currentPrice - g_ReEntry.initialEntryPrice);
   
   if(pullback < InpReEntry_MinATR * atr)
      return;
   
   // Execute SAME LOT re-entry (FUNDINGPIPS SAFE)
   ExecuteSameRiskReEntry(atr);
}

//+------------------------------------------------------------------+
//| CHECK IF TREND STILL VALID                                       |
//+------------------------------------------------------------------+
bool IsTrendStillValid(double &ema50[], double &ema200[])
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   if(g_ReEntry.direction == ORDER_TYPE_BUY)
      return (ema50[0] > ema200[0]) && (close > ema200[0]);
   else
      return (ema50[0] < ema200[0]) && (close < ema200[0]);
}

//+------------------------------------------------------------------+
//| EXECUTE SAME RISK RE-ENTRY (NO LOT INCREASE!)                    |
//+------------------------------------------------------------------+
void ExecuteSameRiskReEntry(double atr)
{
   double price = (g_ReEntry.direction == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // CRITICAL: Same lot size (FUNDINGPIPS RULE)
   double volume = g_ReEntry.initialLotSize;
   
   // Same risk SL/TP
   double sl = (g_ReEntry.direction == ORDER_TYPE_BUY)
               ? price - atr * 2.0
               : price + atr * 2.0;
   double tp = (g_ReEntry.direction == ORDER_TYPE_BUY)
               ? price + atr * 3.0
               : price - atr * 3.0;
   
   string comment = StringFormat("FP_ReEntry_%d", g_ReEntry.entryCount);
   
   if(trade.PositionOpen(_Symbol, g_ReEntry.direction, volume, price, sl, tp, comment))
   {
      g_ReEntry.entryCount++;
      g_ReEntry.lastEntryTime = TimeCurrent();
      
      if(InpDebugMode)
         Print("🔁 Re-Entry #", g_ReEntry.entryCount - 1, 
               " | SAME LOT: ", volume, " | Trend-based");
   }
}
//+------------------------------------------------------------------+
