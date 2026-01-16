//+------------------------------------------------------------------+
//|                        Adaptive_Multi_Strategy_Martingale_V2.mq5 |
//|                                  NETTING-SAFE INSTITUTIONAL GRADE |
//|                                       Institutional Edge Pro     |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro"
#property link      "https://institutional-edge.com"
#property version   "2.10"
#property description "NETTING-SAFE Martingale Recovery with Prop Firm Protection"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ACCOUNT MODE CHECK                                               |
//+------------------------------------------------------------------+
// This EA supports BOTH netting and hedging, but behavior differs

//+------------------------------------------------------------------+
//| MARTINGALE CONFIGURATION                                         |
//+------------------------------------------------------------------+
input group "========== MARTINGALE RECOVERY =========="
input bool   InpEnable_Martingale     = true;   // Enable Martingale Recovery
input int    InpMartingale_MaxLevels  = 3;      // Max Recovery Levels (N)
input double InpMartingale_Multiplier = 1.5;    // Lot Multiplier per Level
input double InpMartingale_DistATR    = 1.5;    // Distance ATR Multiplier
input double InpMartingale_MaxLot     = 1.0;    // Max Total Lot Exposure
input bool   InpMartingale_HedgeMode  = true;   // Hedge Recovery (true=opposite, false=same)
input double InpMartingale_TPFactor   = 0.8;    // TP ATR Factor (quick exit)
input double InpMartingale_SLFactor   = 3.0;    // SL ATR Factor (wide protection)
input int    InpMartingale_CooldownSec = 60;    // Cooldown Between Recoveries (seconds)

input group "========== RISK MANAGEMENT =========="
input double InpMax_Drawdown_Percent = 10.0;  // Max Total Drawdown % (Emergency Close)
input double InpDaily_Loss_Percent   = 5.0;   // Max Daily Loss %
input double InpRisk_Per_Trade       = 0.5;   // Base Risk Per Trade %
input double InpMaxLot_Per_Trade     = 0.2;   // Max Initial Lot Size

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;            // RSI Period
input int InpADX_Period      = 14;            // ADX Period
input int InpADX_Threshold   = 24;            // ADX Trend Threshold
input int InpATR_Period      = 14;            // ATR Period
input ENUM_TIMEFRAMES InpTrend_Timeframe = PERIOD_H4; // Trend Filter TF

input group "========== SYSTEM =========="
input int InpMagicNumber     = 888888;        // Magic Number
input bool InpDebugMode      = true;          // Enable Detailed Logs

//+------------------------------------------------------------------+
//| NETTING-SAFE MARTINGALE STATE (Per Symbol, Not Per Comment)      |
//+------------------------------------------------------------------+
struct NettingMartingaleState
{
   int              currentLevel;       // 0=Initial, 1-N=Recovery levels
   double           baseLotSize;        // Original lot size
   double           initialEntryPrice;  // First entry price
   double           lastRecoveryPrice;  // Last recovery trigger price
   double           totalLotsEntered;   // Cumulative lots added
   ENUM_ORDER_TYPE  initialDirection;   // Original trade direction
   datetime         lastRecoveryTime;   // Cooldown tracking
   bool             isActive;           // Is martingale sequence active?
};

NettingMartingaleState g_MartState;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

// Indicator Handles
int hRSI, hADX, hATR, hEMA50, hEMA200;

// Account Tracking
double AccountBalanceStartDay;
double AccountHighWaterMark;
datetime LastDayChecked;
bool IsHedgingAccount = false;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   symbolInfo.Name(_Symbol);
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Detect Account Mode
   IsHedgingAccount = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   
   if(InpDebugMode)
      Print("📊 Account Mode: ", IsHedgingAccount ? "HEDGING" : "NETTING");
   
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
   
   // Initialize Martingale State
   ResetMartingaleState();

   Print("✅ Martingale V2 Initialized | NETTING-SAFE | Max Levels: ", InpMartingale_MaxLevels, 
         " | Hedge Mode: ", InpMartingale_HedgeMode);
   
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
//| RESET MARTINGALE STATE                                           |
//+------------------------------------------------------------------+
void ResetMartingaleState()
{
   g_MartState.currentLevel = 0;
   g_MartState.baseLotSize = 0;
   g_MartState.initialEntryPrice = 0;
   g_MartState.lastRecoveryPrice = 0;
   g_MartState.totalLotsEntered = 0;
   g_MartState.initialDirection = ORDER_TYPE_BUY;
   g_MartState.lastRecoveryTime = 0;
   g_MartState.isActive = false;
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. EMERGENCY: Check Max Drawdown (Floating DD)
   if(!CheckDrawdownProtection())
   {
      return;
   }
   
   // 2. Check Daily Loss Rules
   if(!CheckDailyLossLimit()) return;
   
   // 3. Get Indicator Data
   double rsi[], adx[], atr[], ema50[], ema200[];
   if(!GetIndicators(rsi, adx, atr, ema50, ema200)) return;
   
   // 4. Check NETTING position state
   SyncMartingaleWithPosition();
   
   // 5. Entry Logic (only if no active martingale)
   if(!g_MartState.isActive)
   {
      CheckEntrySignals(rsi, adx, atr, ema50, ema200);
   }
   
   // 6. Martingale Recovery Management
   if(InpEnable_Martingale && g_MartState.isActive)
   {
      ManageMartingaleRecovery(atr[0]);
   }
}

//+------------------------------------------------------------------+
//| DRAWDOWN PROTECTION (CRITICAL FIX #3)                            |
//+------------------------------------------------------------------+
bool CheckDrawdownProtection()
{
   double balance = accountInfo.Balance();
   double equity = accountInfo.Equity();
   
   // Update high water mark
   if(equity > AccountHighWaterMark)
      AccountHighWaterMark = equity;
   
   // Calculate floating drawdown from balance
   double floatingDD = 0;
   if(balance > 0)
      floatingDD = (balance - equity) / balance * 100.0;
   
   if(floatingDD >= InpMax_Drawdown_Percent)
   {
      Print("🚨 EMERGENCY: Max Drawdown ", DoubleToString(floatingDD, 2), "% - CLOSING ALL POSITIONS");
      CloseAllPositions();
      ResetMartingaleState();
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS (Emergency)                                  |
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
//| DAILY LOSS CHECK                                                 |
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
      if(InpDebugMode) Print("🛑 Daily Loss Limit: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   return true;
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
//| SYNC MARTINGALE STATE WITH ACTUAL POSITION (NETTING-SAFE)        |
//+------------------------------------------------------------------+
void SyncMartingaleWithPosition()
{
   // Get the NET position for this symbol (NETTING account = 1 position max)
   bool hasPosition = false;
   double posVolume = 0;
   double posPrice = 0;
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
      break; // Only one position per symbol in NETTING
   }
   
   // If no position but martingale thinks it's active -> reset
   if(!hasPosition && g_MartState.isActive)
   {
      if(InpDebugMode) Print("✅ Martingale Reset: Position closed");
      ResetMartingaleState();
   }
   
   // If position exists but martingale not active -> something wrong, sync
   if(hasPosition && !g_MartState.isActive)
   {
      // External position or state lost - initialize from position
      g_MartState.isActive = true;
      g_MartState.baseLotSize = posVolume;
      g_MartState.totalLotsEntered = posVolume;
      g_MartState.initialEntryPrice = posPrice;
      g_MartState.lastRecoveryPrice = posPrice;
      g_MartState.initialDirection = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      g_MartState.currentLevel = 0;
      
      if(InpDebugMode) Print("🔄 Martingale State Synced from Position");
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
      double sl = close - (atr[0] * 2.0);
      double tp = close + (atr[0] * 3.0);
      ExecuteInitialTrade(ORDER_TYPE_BUY, sl, tp, atr[0]);
   }
   // SELL Signal
   else if(isBearish && rsi[0] < 60 && rsi[0] > 30)
   {
      double sl = close + (atr[0] * 2.0);
      double tp = close - (atr[0] * 3.0);
      ExecuteInitialTrade(ORDER_TYPE_SELL, sl, tp, atr[0]);
   }
}

//+------------------------------------------------------------------+
//| EXECUTE INITIAL TRADE                                            |
//+------------------------------------------------------------------+
void ExecuteInitialTrade(ENUM_ORDER_TYPE type, double sl, double tp, double atr)
{
   double price = (type == ORDER_TYPE_BUY) 
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double slDist = MathAbs(price - sl);
   double volume = CalculateLotSize(slDist);
   
   if(volume <= 0) return;
   
   // Use magic number only, no comment dependency
   string comment = StringFormat("M%d_L0", InpMagicNumber);
   
   if(trade.PositionOpen(_Symbol, type, volume, price, sl, tp, comment))
   {
      if(InpDebugMode) Print("🚀 Initial Trade | Lot: ", volume, " | Price: ", price);
      
      // Initialize Martingale State
      g_MartState.isActive = true;
      g_MartState.currentLevel = 0;
      g_MartState.baseLotSize = volume;
      g_MartState.totalLotsEntered = volume;
      g_MartState.initialEntryPrice = price;
      g_MartState.lastRecoveryPrice = price;
      g_MartState.initialDirection = type;
      g_MartState.lastRecoveryTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
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
//| MANAGE MARTINGALE RECOVERY (NETTING-SAFE)                        |
//+------------------------------------------------------------------+
void ManageMartingaleRecovery(double atr)
{
   if(!g_MartState.isActive) return;
   if(g_MartState.currentLevel >= InpMartingale_MaxLevels) return;
   
   // COOLDOWN CHECK (CRITICAL FIX #4)
   if(TimeCurrent() - g_MartState.lastRecoveryTime < InpMartingale_CooldownSec)
      return;
   
   // Get current net position data
   double posVolume = 0, posPrice = 0;
   ENUM_POSITION_TYPE posType = POSITION_TYPE_BUY;
   double posSL = 0, posTP = 0;
   
   if(!GetNetPosition(posVolume, posPrice, posType, posSL, posTP))
      return;
   
   // Calculate distance with SPREAD (CRITICAL FIX #6)
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double triggerDistance = (InpMartingale_DistATR * atr) + spread;
   
   double currentPrice = (posType == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double priceDiff = (posType == POSITION_TYPE_BUY)
                      ? (g_MartState.lastRecoveryPrice - currentPrice)
                      : (currentPrice - g_MartState.lastRecoveryPrice);
   
   // Check if price moved against enough
   if(priceDiff < triggerDistance)
      return;
   
   // Calculate recovery lot
   double recoveryLot = GetRecoveryLotSize();
   if(recoveryLot <= 0) return;
   
   // HEDGE MODE LOGIC (CRITICAL FIX #5)
   if(InpMartingale_HedgeMode)
   {
      // Open OPPOSITE direction to hedge/recover
      ExecuteHedgeRecovery(posType, recoveryLot, atr, currentPrice);
   }
   else
   {
      // Same direction averaging (DANGEROUS - user choice)
      ExecuteSameDirectionRecovery(posType, recoveryLot, atr, currentPrice);
   }
}

//+------------------------------------------------------------------+
//| GET NET POSITION (NETTING-SAFE) (CRITICAL FIX #1 & #2)           |
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
//| CALCULATE RECOVERY LOT SIZE                                      |
//+------------------------------------------------------------------+
double GetRecoveryLotSize()
{
   int level = g_MartState.currentLevel;
   double baseLot = g_MartState.baseLotSize;
   
   // Martingale: base * multiplier^(level+1)
   double recoveryLot = baseLot * MathPow(InpMartingale_Multiplier, level + 1);
   
   // Normalize
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   recoveryLot = MathFloor(recoveryLot / step) * step;
   
   // Check total exposure
   double projectedTotal = g_MartState.totalLotsEntered + recoveryLot;
   if(projectedTotal > InpMartingale_MaxLot)
   {
      recoveryLot = InpMartingale_MaxLot - g_MartState.totalLotsEntered;
      recoveryLot = MathFloor(recoveryLot / step) * step;
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(recoveryLot < minLot)
   {
      if(InpDebugMode) Print("❌ Max Lot Reached, Cannot Add Recovery");
      return 0;
   }
   
   return recoveryLot;
}

//+------------------------------------------------------------------+
//| EXECUTE HEDGE RECOVERY (OPPOSITE DIRECTION)                      |
//+------------------------------------------------------------------+
void ExecuteHedgeRecovery(ENUM_POSITION_TYPE currentType, double lot, double atr, double currentPrice)
{
   // HEDGE: Open opposite direction
   ENUM_ORDER_TYPE recoveryType = (currentType == POSITION_TYPE_BUY) 
                                  ? ORDER_TYPE_SELL 
                                  : ORDER_TYPE_BUY;
   
   double price = (recoveryType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Short TP, wide SL for hedge
   double sl = (recoveryType == ORDER_TYPE_BUY)
               ? price - atr * InpMartingale_SLFactor
               : price + atr * InpMartingale_SLFactor;
   double tp = (recoveryType == ORDER_TYPE_BUY)
               ? price + atr * InpMartingale_TPFactor
               : price - atr * InpMartingale_TPFactor;
   
   int nextLevel = g_MartState.currentLevel + 1;
   string comment = StringFormat("M%d_L%d_H", InpMagicNumber, nextLevel);
   
   if(trade.PositionOpen(_Symbol, recoveryType, lot, price, sl, tp, comment))
   {
      g_MartState.currentLevel = nextLevel;
      g_MartState.totalLotsEntered += lot;
      g_MartState.lastRecoveryPrice = currentPrice;
      g_MartState.lastRecoveryTime = TimeCurrent();
      
      if(InpDebugMode)
         Print("🔁 HEDGE Recovery L", nextLevel, " | ", EnumToString(recoveryType), 
               " | Lot: ", lot, " | Total: ", g_MartState.totalLotsEntered);
   }
}

//+------------------------------------------------------------------+
//| EXECUTE SAME DIRECTION RECOVERY (AVERAGING)                       |
//+------------------------------------------------------------------+
void ExecuteSameDirectionRecovery(ENUM_POSITION_TYPE currentType, double lot, double atr, double currentPrice)
{
   // WARNING: This mode accelerates drawdown
   ENUM_ORDER_TYPE recoveryType = (currentType == POSITION_TYPE_BUY) 
                                  ? ORDER_TYPE_BUY 
                                  : ORDER_TYPE_SELL;
   
   double price = (recoveryType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   int nextLevel = g_MartState.currentLevel + 1;
   string comment = StringFormat("M%d_L%d_A", InpMagicNumber, nextLevel);
   
   // In NETTING: This will ADD to the position, MT5 recalculates average
   if(trade.PositionOpen(_Symbol, recoveryType, lot, price, 0, 0, comment))
   {
      g_MartState.currentLevel = nextLevel;
      g_MartState.totalLotsEntered += lot;
      g_MartState.lastRecoveryPrice = currentPrice;
      g_MartState.lastRecoveryTime = TimeCurrent();
      
      // On NETTING, we must update SL/TP on the MERGED position
      UpdateNetPositionSLTP(atr);
      
      if(InpDebugMode)
         Print("🔁 AVG Recovery L", nextLevel, " | Lot: ", lot, 
               " | Total: ", g_MartState.totalLotsEntered);
   }
}

//+------------------------------------------------------------------+
//| UPDATE NET POSITION SL/TP (NETTING-SAFE)                         |
//+------------------------------------------------------------------+
void UpdateNetPositionSLTP(double atr)
{
   double posVolume = 0, posPrice = 0, posSL = 0, posTP = 0;
   ENUM_POSITION_TYPE posType = POSITION_TYPE_BUY;
   
   if(!GetNetPosition(posVolume, posPrice, posType, posSL, posTP))
      return;
   
   // Calculate new SL/TP based on CURRENT average price (from MT5)
   double newSL = (posType == POSITION_TYPE_BUY)
                  ? posPrice - atr * InpMartingale_SLFactor
                  : posPrice + atr * InpMartingale_SLFactor;
   double newTP = (posType == POSITION_TYPE_BUY)
                  ? posPrice + atr * InpMartingale_TPFactor
                  : posPrice - atr * InpMartingale_TPFactor;
   
   // Find and modify THE net position (single position in NETTING)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      trade.PositionModify(ticket, newSL, newTP);
      
      if(InpDebugMode)
         Print("📊 Net Position Updated | Avg: ", posPrice, " | SL: ", newSL, " | TP: ", newTP);
      
      break; // Only one position in NETTING
   }
}

//+------------------------------------------------------------------+
//| HELPER: Check if we have a position                              |
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
