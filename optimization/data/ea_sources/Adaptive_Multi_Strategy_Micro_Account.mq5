//+------------------------------------------------------------------+
//|                   Adaptive_Multi_Strategy_Micro_Account.mq5      |
//|                        MICRO ACCOUNT EDITION ($10-$20 SAFE)      |
//|                                  Institutional Edge Pro          |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro - Micro Account Edition"
#property link      "https://institutional-edge.com"
#property version   "3.00"
#property description "MICRO ACCOUNT SAFE: 1 Recovery Max, No Hedge, Daily Freeze"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| MICRO ACCOUNT MARTINGALE (SOFT RECOVERY)                         |
//+------------------------------------------------------------------+
input group "========== MICRO RECOVERY (NOT TRUE MARTINGALE) =========="
input bool   InpEnable_Martingale     = true;   // Enable Soft Recovery
input int    InpMartingale_MaxLevels  = 1;      // 🔥 Max 1 Recovery Only
input double InpMartingale_Multiplier = 1.2;    // Soft Multiplier (1.2x)
input double InpMartingale_DistATR    = 2.0;    // Distance ATR (avoid noise)
input double InpMartingale_MaxLot     = 0.02;   // 🔥 HARD CAP Total Exposure
input bool   InpMartingale_HedgeMode  = false;  // ❌ NEVER HEDGE SMALL ACCOUNTS
input double InpMartingale_TPFactor   = 0.6;    // Quick TP
input double InpMartingale_SLFactor   = 1.8;    // Tight SL
input int    InpMartingale_CooldownSec = 120;   // Cooldown (seconds)

input group "========== ULTRA-TIGHT RISK MANAGEMENT =========="
input double InpMax_Drawdown_Percent = 5.0;   // 🔥 HARD STOP at 5% DD
input double InpDaily_Loss_Percent   = 2.0;   // Max Daily Loss (Prop-style)
input double InpRisk_Per_Trade       = 0.25;  // 0.25% per trade
input double InpMaxLot_Per_Trade     = 0.01;  // Micro lots only

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;
input int InpADX_Period      = 14;
input int InpADX_Threshold   = 20;            // Lower for M1/M5
input int InpATR_Period      = 14;
input ENUM_TIMEFRAMES InpTrend_Timeframe = PERIOD_M15;

input group "========== SYSTEM =========="
input int InpMagicNumber     = 999999;
input bool InpDebugMode      = true;

//+------------------------------------------------------------------+
//| MICRO RECOVERY STATE                                             |
//+------------------------------------------------------------------+
struct MicroRecoveryState
{
   int              currentLevel;
   double           baseLotSize;
   double           initialEntryPrice;
   double           lastRecoveryPrice;
   double           totalLotsEntered;
   ENUM_ORDER_TYPE  initialDirection;
   datetime         lastRecoveryTime;
   bool             isActive;
};

MicroRecoveryState g_RecoveryState;

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
   
   // Initialize Indicators (Force current TF for tight control)
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
   
   ResetRecoveryState();

   Print("✅ MICRO ACCOUNT MODE | Balance: $", accountInfo.Balance(), 
         " | Max Risk: ", InpRisk_Per_Trade, "% | Max Lot: ", InpMaxLot_Per_Trade);
   Print("🔥 HARD STOPS: DD=", InpMax_Drawdown_Percent, "% | Daily=", InpDaily_Loss_Percent, "%");
   
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
//| RESET RECOVERY STATE                                            |
//+------------------------------------------------------------------+
void ResetRecoveryState()
{
   g_RecoveryState.currentLevel = 0;
   g_RecoveryState.baseLotSize = 0;
   g_RecoveryState.initialEntryPrice = 0;
   g_RecoveryState.lastRecoveryPrice = 0;
   g_RecoveryState.totalLotsEntered = 0;
   g_RecoveryState.initialDirection = ORDER_TYPE_BUY;
   g_RecoveryState.lastRecoveryTime = 0;
   g_RecoveryState.isActive = false;
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 0. Check Daily Reset
   CheckDailyReset();
   
   // 1. Hard Daily Freeze Check
   if(TradingLockedToday)
   {
      if(InpDebugMode && PositionsTotal() == 0)
         Print("🔒 Trading LOCKED for today. Daily loss limit reached.");
      return;
   }
   
   // 2. Emergency Drawdown Protection
   if(!CheckDrawdownProtection())
      return;
   
   // 3. Daily Loss Check
   if(!CheckDailyLossLimit())
      return;
   
   // 4. Get Indicators
   double rsi[], adx[], atr[], ema50[], ema200[];
   if(!GetIndicators(rsi, adx, atr, ema50, ema200))
      return;
   
   // 5. Sync Recovery State
   SyncRecoveryWithPosition();
   
   // 6. Entry Logic (only if no active recovery)
   if(!g_RecoveryState.isActive)
   {
      CheckEntrySignals(rsi, adx, atr, ema50, ema200);
   }
   
   // 7. Recovery Management
   if(InpEnable_Martingale && g_RecoveryState.isActive)
   {
      ManageMicroRecovery(atr[0]);
   }
}

//+------------------------------------------------------------------+
//| DAILY RESET CHECK                                                |
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
//| DRAWDOWN PROTECTION                                              |
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
      ResetRecoveryState();
      TradingLockedToday = true;  // Lock for rest of day
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
      ResetRecoveryState();
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
//| SYNC RECOVERY WITH POSITION                                      |
//+------------------------------------------------------------------+
void SyncRecoveryWithPosition()
{
   bool hasPosition = false;
   double posVolume = 0, posPrice = 0;
   ENUM_POSITION_TYPE posType = POSITION_TYPE_BUY;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      hasPosition = true;
      posVolume = PositionGetDouble(POSITION_VOLUME);
      posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      break;
   }
   
   if(!hasPosition && g_RecoveryState.isActive)
   {
      if(InpDebugMode) Print("✅ Recovery Reset: Position closed");
      ResetRecoveryState();
   }
   
   if(hasPosition && !g_RecoveryState.isActive)
   {
      g_RecoveryState.isActive = true;
      g_RecoveryState.baseLotSize = posVolume;
      g_RecoveryState.totalLotsEntered = posVolume;
      g_RecoveryState.initialEntryPrice = posPrice;
      g_RecoveryState.lastRecoveryPrice = posPrice;
      g_RecoveryState.initialDirection = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      g_RecoveryState.currentLevel = 0;
      
      if(InpDebugMode) Print("🔄 Recovery State Synced");
   }
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNALS                                              |
//+------------------------------------------------------------------+
void CheckEntrySignals(double &rsi[], double &adx[], double &atr[], 
                       double &ema50[], double &ema200[])
{
   if(HasPosition()) return;
   if(adx[0] < InpADX_Threshold) return;
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   bool isBullish = (ema50[0] > ema200[0]) && (close > ema50[0]);
   bool isBearish = (ema50[0] < ema200[0]) && (close < ema50[0]);
   
   // BUY Signal
   if(isBullish && rsi[0] > 40 && rsi[0] < 70)
   {
      double sl = close - (atr[0] * InpMartingale_SLFactor);
      double tp = close + (atr[0] * InpMartingale_TPFactor * 2);
      ExecuteInitialTrade(ORDER_TYPE_BUY, sl, tp);
   }
   // SELL Signal
   else if(isBearish && rsi[0] < 60 && rsi[0] > 30)
   {
      double sl = close + (atr[0] * InpMartingale_SLFactor);
      double tp = close - (atr[0] * InpMartingale_TPFactor * 2);
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
   double volume = CalculateMicroLotSize(slDist);
   
   if(volume <= 0) return;
   
   string comment = "Micro_L0";
   
   if(trade.PositionOpen(_Symbol, type, volume, price, sl, tp, comment))
   {
      if(InpDebugMode) Print("🚀 Initial | Lot: ", volume, " | Price: ", price);
      
      g_RecoveryState.isActive = true;
      g_RecoveryState.currentLevel = 0;
      g_RecoveryState.baseLotSize = volume;
      g_RecoveryState.totalLotsEntered = volume;
      g_RecoveryState.initialEntryPrice = price;
      g_RecoveryState.lastRecoveryPrice = price;
      g_RecoveryState.initialDirection = type;
      g_RecoveryState.lastRecoveryTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| CALCULATE MICRO LOT SIZE (ULTRA SAFE)                            |
//+------------------------------------------------------------------+
double CalculateMicroLotSize(double slDistance)
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
   
   // HARD CAP for micro accounts
   if(lotSize > InpMaxLot_Per_Trade) 
      lotSize = InpMaxLot_Per_Trade;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| MANAGE MICRO RECOVERY (1 LEVEL MAX, NO HEDGE)                    |
//+------------------------------------------------------------------+
void ManageMicroRecovery(double atr)
{
   if(!g_RecoveryState.isActive) return;
   if(g_RecoveryState.currentLevel >= InpMartingale_MaxLevels) return;  // Max 1
   
   // Cooldown
   if(TimeCurrent() - g_RecoveryState.lastRecoveryTime < InpMartingale_CooldownSec)
      return;
   
   // Get position
   double posVolume = 0, posPrice = 0;
   ENUM_POSITION_TYPE posType = POSITION_TYPE_BUY;
   double posSL = 0, posTP = 0;
   
   if(!GetNetPosition(posVolume, posPrice, posType, posSL, posTP))
      return;
   
   // Calculate trigger with spread
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double triggerDistance = (InpMartingale_DistATR * atr) + spread;
   
   double currentPrice = (posType == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double priceDiff = (posType == POSITION_TYPE_BUY)
                      ? (g_RecoveryState.lastRecoveryPrice - currentPrice)
                      : (currentPrice - g_RecoveryState.lastRecoveryPrice);
   
   if(priceDiff < triggerDistance)
      return;
   
   // SOFT RECOVERY LOT (CAPPED)
   double recoveryLot = g_RecoveryState.baseLotSize * InpMartingale_Multiplier;
   
   // HARD CAP at 0.01 for micro accounts
   if(recoveryLot > 0.01)
      recoveryLot = 0.01;
   
   // Normalize
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   recoveryLot = MathFloor(recoveryLot / step) * step;
   
   // Check total exposure
   double projectedTotal = g_RecoveryState.totalLotsEntered + recoveryLot;
   if(projectedTotal > InpMartingale_MaxLot)
   {
      recoveryLot = InpMartingale_MaxLot - g_RecoveryState.totalLotsEntered;
      recoveryLot = MathFloor(recoveryLot / step) * step;
   }
   
   if(recoveryLot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      if(InpDebugMode) Print("❌ Cannot add recovery - lot too small");
      return;
   }
   
   // Execute SAME DIRECTION recovery (NO HEDGE on micro accounts)
   ExecuteSameDirectionRecovery(posType, recoveryLot, atr, currentPrice);
}

//+------------------------------------------------------------------+
//| EXECUTE SAME DIRECTION RECOVERY                                  |
//+------------------------------------------------------------------+
void ExecuteSameDirectionRecovery(ENUM_POSITION_TYPE currentType, double lot, double atr, double currentPrice)
{
   ENUM_ORDER_TYPE recoveryType = (currentType == POSITION_TYPE_BUY) 
                                  ? ORDER_TYPE_BUY 
                                  : ORDER_TYPE_SELL;
   
   double price = (recoveryType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   int nextLevel = g_RecoveryState.currentLevel + 1;
   string comment = StringFormat("Micro_L%d", nextLevel);
   
   if(trade.PositionOpen(_Symbol, recoveryType, lot, price, 0, 0, comment))
   {
      g_RecoveryState.currentLevel = nextLevel;
      g_RecoveryState.totalLotsEntered += lot;
      g_RecoveryState.lastRecoveryPrice = currentPrice;
      g_RecoveryState.lastRecoveryTime = TimeCurrent();
      
      // Update SL/TP on merged position
      UpdateNetPositionSLTP(atr);
      
      if(InpDebugMode)
         Print("🔁 Soft Recovery L", nextLevel, " | Lot: ", lot, 
               " | Total: ", g_RecoveryState.totalLotsEntered);
   }
}

//+------------------------------------------------------------------+
//| GET NET POSITION                                                 |
//+------------------------------------------------------------------+
bool GetNetPosition(double &volume, double &price, ENUM_POSITION_TYPE &type, double &sl, double &tp)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      volume = PositionGetDouble(POSITION_VOLUME);
      price = PositionGetDouble(POSITION_PRICE_OPEN);
      type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| UPDATE NET POSITION SL/TP                                        |
//+------------------------------------------------------------------+
void UpdateNetPositionSLTP(double atr)
{
   double posVolume = 0, posPrice = 0, posSL = 0, posTP = 0;
   ENUM_POSITION_TYPE posType = POSITION_TYPE_BUY;
   
   if(!GetNetPosition(posVolume, posPrice, posType, posSL, posTP))
      return;
   
   double newSL = (posType == POSITION_TYPE_BUY)
                  ? posPrice - atr * InpMartingale_SLFactor
                  : posPrice + atr * InpMartingale_SLFactor;
   double newTP = (posType == POSITION_TYPE_BUY)
                  ? posPrice + atr * InpMartingale_TPFactor
                  : posPrice - atr * InpMartingale_TPFactor;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      trade.PositionModify(ticket, newSL, newTP);
      
      if(InpDebugMode)
         Print("📊 Position Updated | Avg: ", posPrice, " | SL: ", newSL, " | TP: ", newTP);
      
      break;
   }
}

//+------------------------------------------------------------------+
//| HAS POSITION                                                     |
//+------------------------------------------------------------------+
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
