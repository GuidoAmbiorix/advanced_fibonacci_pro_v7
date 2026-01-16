//+------------------------------------------------------------------+
//|                              Adaptive_Multi_Strategy_Martingale.mq5 |
//|                                  Based on Python Adaptive Engine |
//|                                       Institutional Edge Pro     |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro"
#property link      "https://institutional-edge.com"
#property version   "2.00"
#property description "Martingale Recovery System with Configurable Levels"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| MARTINGALE CONFIGURATION                                         |
//+------------------------------------------------------------------+
input group "========== MARTINGALE RECOVERY =========="
input bool   InpEnable_Martingale     = true;   // Enable Martingale Recovery
input int    InpMartingale_MaxLevels  = 3;      // Max Recovery Levels (N)
input double InpMartingale_Multiplier = 1.5;    // Lot Multiplier per Level
input double InpMartingale_DistATR    = 1.5;    // Distance ATR Multiplier (trigger)
input double InpMartingale_MaxLot     = 1.0;    // Max Total Lot Exposure
input bool   InpMartingale_SameDir    = true;   // Same Direction (false=Hedge)
input double InpMartingale_TPFactor   = 1.0;    // TP ATR Factor (quick exit)
input double InpMartingale_SLFactor   = 3.0;    // SL ATR Factor (wide protection)

input group "========== RISK MANAGEMENT =========="
input double InpMax_Drawdown_Percent = 10.0;  // Max Total Drawdown %
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
//| MARTINGALE STATE STRUCTURE                                        |
//+------------------------------------------------------------------+
struct MartingaleInfo
{
   string           strategy;         // Strategy tag
   int              currentLevel;     // 0=Initial, 1-N=Recovery levels
   double           baseLotSize;      // Original lot size
   double           averagePrice;     // Weighted average entry
   double           totalLots;        // Total position size
   double           lastEntryPrice;   // Last entry for distance calc
   ENUM_ORDER_TYPE  direction;        // BUY or SELL
   datetime         lastEntryTime;    // Timestamp of last entry
};

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

// Indicator Handles
int hRSI, hADX, hATR, hEMA50, hEMA200;

// Martingale State Array
MartingaleInfo g_MartingaleState[];

// Account Tracking
double AccountBalanceStartDay;
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
   LastDayChecked = iTime(_Symbol, PERIOD_D1, 0);

   Print("✅ Martingale EA Initialized | Max Levels: ", InpMartingale_MaxLevels, 
         " | Multiplier: ", InpMartingale_Multiplier);
   
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
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Check Funding Rules
   if(!CheckFundingRules()) return;
   
   // 2. Get Indicator Data
   double rsi[], adx[], atr[], ema50[], ema200[];
   if(!GetIndicators(rsi, adx, atr, ema50, ema200)) return;
   
   // 3. Check for New Entry Signals (simplified - trend following)
   CheckEntrySignals(rsi, adx, atr, ema50, ema200);
   
   // 4. Martingale Recovery Management
   if(InpEnable_Martingale)
   {
      ManageMartingaleRecovery(atr[0]);
   }
   
   // 5. Position Management
   ManagePositions();
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
//| CHECK FUNDING RULES                                              |
//+------------------------------------------------------------------+
bool CheckFundingRules()
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
      if(InpDebugMode) Print("🛑 Daily Loss Limit Hit: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNALS (Simplified Trend Following)                 |
//+------------------------------------------------------------------+
void CheckEntrySignals(double &rsi[], double &adx[], double &atr[], 
                       double &ema50[], double &ema200[])
{
   // Only enter if no position and ADX shows trend
   if(HasOpenTrade("Main")) return;
   if(adx[0] < InpADX_Threshold) return;
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   bool isBullish = (ema50[0] > ema200[0]) && (close > ema50[0]);
   bool isBearish = (ema50[0] < ema200[0]) && (close < ema50[0]);
   
   // BUY Signal
   if(isBullish && rsi[0] > 40 && rsi[0] < 70)
   {
      double sl = close - (atr[0] * 2.0);
      double tp = close + (atr[0] * 3.0);
      ExecuteInitialTrade(ORDER_TYPE_BUY, sl, tp, "Main_Buy", atr[0]);
   }
   // SELL Signal
   else if(isBearish && rsi[0] < 60 && rsi[0] > 30)
   {
      double sl = close + (atr[0] * 2.0);
      double tp = close - (atr[0] * 3.0);
      ExecuteInitialTrade(ORDER_TYPE_SELL, sl, tp, "Main_Sell", atr[0]);
   }
}

//+------------------------------------------------------------------+
//| EXECUTE INITIAL TRADE                                            |
//+------------------------------------------------------------------+
void ExecuteInitialTrade(ENUM_ORDER_TYPE type, double sl, double tp, string comment, double atr)
{
   double price = (type == ORDER_TYPE_BUY) 
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double slDist = MathAbs(price - sl);
   double volume = CalculateLotSize(slDist);
   
   if(volume <= 0) return;
   
   if(trade.PositionOpen(_Symbol, type, volume, price, sl, tp, comment))
   {
      if(InpDebugMode) Print("🚀 Initial Trade: ", comment, " | Lot: ", volume);
      
      // Initialize Martingale State
      if(InpEnable_Martingale)
      {
         InitMartingale("Main", volume, price, type);
      }
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
//| MARTINGALE FUNCTIONS                                             |
//+------------------------------------------------------------------+

// Get index in state array
int GetMartingaleIndex(string strategy)
{
   int size = ArraySize(g_MartingaleState);
   for(int i = 0; i < size; i++)
   {
      if(g_MartingaleState[i].strategy == strategy)
         return i;
   }
   return -1;
}

// Initialize state for new trade
void InitMartingale(string strategy, double baseLot, double entryPrice, ENUM_ORDER_TYPE dir)
{
   int idx = GetMartingaleIndex(strategy);
   
   if(idx < 0)
   {
      idx = ArraySize(g_MartingaleState);
      ArrayResize(g_MartingaleState, idx + 1);
   }
   
   g_MartingaleState[idx].strategy       = strategy;
   g_MartingaleState[idx].currentLevel   = 0;
   g_MartingaleState[idx].baseLotSize    = baseLot;
   g_MartingaleState[idx].averagePrice   = entryPrice;
   g_MartingaleState[idx].totalLots      = baseLot;
   g_MartingaleState[idx].lastEntryPrice = entryPrice;
   g_MartingaleState[idx].direction      = dir;
   g_MartingaleState[idx].lastEntryTime  = TimeCurrent();
   
   if(InpDebugMode) Print("📊 Martingale Init: ", strategy, " @ ", entryPrice);
}

// Calculate recovery lot size
double GetMartingaleLot(string strategy, double baseLot)
{
   int idx = GetMartingaleIndex(strategy);
   if(idx < 0) return baseLot;
   
   int level = g_MartingaleState[idx].currentLevel;
   if(level >= InpMartingale_MaxLevels) return 0.0;
   
   // Martingale formula: baseLot * multiplier^(level+1)
   double recoveryLot = baseLot * MathPow(InpMartingale_Multiplier, level + 1);
   
   // Normalize
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   recoveryLot = MathFloor(recoveryLot / step) * step;
   
   // Safety cap
   double currentTotal = g_MartingaleState[idx].totalLots;
   if((currentTotal + recoveryLot) > InpMartingale_MaxLot)
   {
      recoveryLot = InpMartingale_MaxLot - currentTotal;
      recoveryLot = MathFloor(recoveryLot / step) * step;
      if(recoveryLot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         return 0.0;
   }
   
   return recoveryLot;
}

// Check if recovery should trigger
bool ShouldOpenRecovery(string strategy, double atr)
{
   int idx = GetMartingaleIndex(strategy);
   if(idx < 0) return false;
   if(g_MartingaleState[idx].currentLevel >= InpMartingale_MaxLevels) return false;
   if(g_MartingaleState[idx].totalLots <= 0) return false;
   
   double distance = InpMartingale_DistATR * atr;
   
   double currentPrice = SymbolInfoDouble(_Symbol, 
      g_MartingaleState[idx].direction == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double lastEntry = g_MartingaleState[idx].lastEntryPrice;
   
   bool isBuy = (g_MartingaleState[idx].direction == ORDER_TYPE_BUY);
   
   // BUY: Price dropped -> recover lower
   // SELL: Price rose -> recover higher
   if(isBuy && currentPrice <= (lastEntry - distance))
      return true;
   if(!isBuy && currentPrice >= (lastEntry + distance))
      return true;
   
   return false;
}

// Execute recovery trade
void ExecuteRecovery(string strategy, double atr)
{
   int idx = GetMartingaleIndex(strategy);
   if(idx < 0) return;
   
   double baseLot = g_MartingaleState[idx].baseLotSize;
   double recoveryLot = GetMartingaleLot(strategy, baseLot);
   
   if(recoveryLot <= 0) 
   {
      if(InpDebugMode) Print("❌ Martingale Max Lot Reached");
      return;
   }
   
   ENUM_ORDER_TYPE type = InpMartingale_SameDir 
                          ? g_MartingaleState[idx].direction 
                          : (g_MartingaleState[idx].direction == ORDER_TYPE_BUY 
                             ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   
   double price = (type == ORDER_TYPE_BUY) 
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate new weighted average
   double avgPrice = g_MartingaleState[idx].averagePrice;
   double totalLots = g_MartingaleState[idx].totalLots;
   double newAvg = ((avgPrice * totalLots) + (price * recoveryLot)) / (totalLots + recoveryLot);
   
   // SL/TP based on new average
   double sl = (type == ORDER_TYPE_BUY) 
               ? (newAvg - atr * InpMartingale_SLFactor) 
               : (newAvg + atr * InpMartingale_SLFactor);
   double tp = (type == ORDER_TYPE_BUY) 
               ? (newAvg + atr * InpMartingale_TPFactor) 
               : (newAvg - atr * InpMartingale_TPFactor);
   
   int nextLevel = g_MartingaleState[idx].currentLevel + 1;
   string comment = StringFormat("%s_M%d", strategy, nextLevel);
   
   if(trade.PositionOpen(_Symbol, type, recoveryLot, price, sl, tp, comment))
   {
      if(InpDebugMode) 
         Print("🔁 Recovery L", nextLevel, " | Lot: ", recoveryLot, 
               " | Total: ", totalLots + recoveryLot, " | Avg: ", newAvg);
      
      // Update state
      g_MartingaleState[idx].currentLevel = nextLevel;
      g_MartingaleState[idx].totalLots += recoveryLot;
      g_MartingaleState[idx].averagePrice = newAvg;
      g_MartingaleState[idx].lastEntryPrice = price;
      g_MartingaleState[idx].lastEntryTime = TimeCurrent();
      
      // Update SL/TP for ALL positions in this strategy
      UpdateAllPositionsSLTP(strategy, sl, tp);
   }
}

// Update SL/TP for all positions of a strategy
void UpdateAllPositionsSLTP(string strategy, double newSL, double newTP)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, strategy) >= 0)
      {
         trade.PositionModify(ticket, newSL, newTP);
      }
   }
}

// Manage Martingale Recovery
void ManageMartingaleRecovery(double atr)
{
   // Check each tracked strategy
   int size = ArraySize(g_MartingaleState);
   for(int i = 0; i < size; i++)
   {
      string strategy = g_MartingaleState[i].strategy;
      
      // Check if all positions closed -> reset
      if(!HasOpenTrade(strategy))
      {
         if(g_MartingaleState[i].totalLots > 0)
         {
            if(InpDebugMode) 
               Print("✅ Martingale Reset: ", strategy, " (All positions closed)");
            
            g_MartingaleState[i].currentLevel = 0;
            g_MartingaleState[i].totalLots = 0;
            g_MartingaleState[i].averagePrice = 0;
         }
         continue;
      }
      
      // Check for recovery trigger
      if(ShouldOpenRecovery(strategy, atr))
      {
         ExecuteRecovery(strategy, atr);
      }
   }
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+
bool HasOpenTrade(string commentFilter)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, commentFilter) >= 0) return true;
         }
      }
   }
   return false;
}

void ManagePositions()
{
   // Basic position management - could add trailing here
   // Currently just monitoring
}
//+------------------------------------------------------------------+
