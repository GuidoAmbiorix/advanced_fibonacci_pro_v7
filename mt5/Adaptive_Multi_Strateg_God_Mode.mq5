//+------------------------------------------------------------------+
//|                                      Adaptive_Multi_Strategy.mq5 |
//|                                  Based on Python Adaptive Engine |
//|                                       Institutional Edge Pro     |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro"
#property link      "https://institutional-edge.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

// --- STATE MACHINE ENUMS ---
enum ENUM_TRAIL_STATE
{
   TS_ENTRY_PROTECT,    // Survival Mode (Soft BE)
   TS_STRUCTURE_LOCK,   // Institutional Trail (Swing Lows)
   TS_MOMENTUM_TRAIL,   // Expansion Phase (Tight ATR)
   TS_EXHAUSTION_LOCK,  // Reversal Danger (Lock Profits)
   TS_SESSION_EXIT      // Killzone End (Hard Exit)
};

enum ENUM_TRAIL_PROFILE
{
   TRAIL_SCALP,         // Aggressive, tight stops, quick BE
   TRAIL_INTRADAY,      // Balanced, standard swings
   TRAIL_SWING          // Loose, deep swings, slow transition
};

//+------------------------------------------------------------------+
//| INPUTS & CONFIGURATION                                           |
//+------------------------------------------------------------------+
input group "========== STRATEGY TOGGLES =========="
input bool InpEnable_Institutional = true;    // Institutional Sweep
input bool InpEnable_VWAP_Scalp    = false;   // VWAP Scalping
input bool InpEnable_Fibonacci     = true;    // Fibonacci Golden Zone
input bool InpEnable_Stochastic    = false;   // Stochastic Momentum - DISABLED for M15 Trend focus
input bool InpEnable_Breakout      = false;   // Breakout Momentum
input int  InpSwap_Lookback        = 10;      // User Preference: 10 (Faster swings for M15)
// input int  InpMax_Spread_Points    = 50;      // Max Spread removed
input ENUM_TIMEFRAMES InpTrend_Timeframe = PERIOD_H4; // M15 Optimized: H4 Trend Filter
// --- CONTEXT FILTER (The Gatekeeper) ---
input ENUM_TIMEFRAMES InpContext_Timeframe = PERIOD_H1; // Context TF (H1 recommended for M15)
input int InpContext_Lookback = 50;                     // Bars for Context Range (Donchian)

input group "========== CONFLUENCE FILTER =========="
input bool InpUse_Confluence_Filter  = true;  // Enable Confluence Scoring
input double InpMin_Confluence_Score = 6.5;   // Score 6.5 (M15 Optimized: High Probability Only)

input group "========== RISK MANAGEMENT =========="
input double InpMax_Drawdown_Percent = 10.0;  // Max Total Drawdown % (Funding Rule)
input double InpDaily_Loss_Percent   = 5.0;   // Max Daily Loss % (Funding Rule)
input int    InpMax_Daily_Trades     = 0;     // Max Trades Per Day
input double InpTarget_Daily_Profit  = 0;     // Daily Profit Target %
input double InpRisk_Per_Trade       = 0.5;   // Base Risk Per Trade %
input double InpRisk_Reward_Ratio    = 2.5;   // 1:2.5 (Stretching wins for higher PF)
input int    InpCooldownMinutes      = 30;    // Cooldown Minutes
input double InpMaxLot_Per_Trade     = 0.2;   // Max Lot Size (Safety Cap)

input group "========== TRAILING CONFIGURATION =========="
input ENUM_TRAIL_PROFILE InpTrailProfile = TRAIL_SWING; // Swing Profile (M15 Optimized: 1.5 ATR Buffer)
// input double InpTier1_Profit_R = 1.0;   // REMOVED: Auto-Calculated by State
// input double InpTier1_Lock_R   = 0.25;  // REMOVED
// input double InpTier2_Profit_R = 2.0;   // REMOVED
// input double InpTier2_Lock_R   = 1.3;   // REMOVED
// input double InpTier3_Profit_R = 3.5;   // REMOVED
// input double InpTier3_Lock_R   = 2.8;   // REMOVED

//+------------------------------------------------------------------+
//| PARTIAL TP INPUTS                                                |
//+------------------------------------------------------------------+
input bool   InpEnablePartialTP      = false;  // DISABLED: Force full wins for Max Profit Factor (>1.10)
input bool   InpPartialTP_VWAP       = false;
input bool   InpPartialTP_Liquidity  = false;
input bool   InpPartialTP_Time       = false;
input bool   InpPartialTP_Fib        = false;
input double InpPartialTP_PercentVWAP   = 0.0;
input double InpPartialTP_PercentLiquidity = 0.0;
input double InpPartialTP_PercentTime   = 0.0;
input double InpPartialTP_PercentFib    = 0.0;
// Total Closed: 0%. Runner: 100% (This is the key to PF > 1.10)
input int   InpPartialTP_TimeMinutes   = 30;

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;            // RSI Period
input int InpADX_Period      = 14;            // ADX Period
input int InpADX_Threshold   = 24;            // User: 24
input int InpATR_Period      = 14;            // ATR Period
input int InpStoch_K         = 14;            // Stochastic %K
input int InpStoch_D         = 3;             // Stochastic %D
input int InpVariable_MA     = 20;            // Variable MA (VWAP Proxy)

input group "========== KILLZONES (EST TIME) =========="
input int    InpServerTimeOffset        = 2;     // Server Time Offset from EST (e.g. +2 for UTC+2)
input bool   InpUse_KillZones           = false; // User Preference: OFF
input bool   InpUse_London_Killzone     = false;
input string InpLondon_Start            = "01:00";
input string InpLondon_End              = "06:00";
input bool   InpUse_NY_Killzone         = false;
input string InpNY_Start                = "07:00"; // User: 07:00
input string InpNY_End                  = "12:00";
input bool   InpUse_LondonClose_Killzone= false; // London Close (10:00-12:00 EST)
input string InpLondonClose_Start       = "10:00";
input string InpLondonClose_End         = "12:00";
input bool   InpCloseTrades_At_SessionEnd = true; // Close all trades outside Killzones?

input group "========== NEWS FILTER =========="
input bool   InpUse_NewsFilter       = true;  // Enable News Filter
input bool   InpNews_HighImpact_Only = true;  // High Impact Only
input int    InpNews_Before_Mins     = 45;    // Pause Minutes Before News
input int    InpNews_After_Mins      = 45;    // Pause Minutes After News

input group "========== SYSTEM =========="
input int InpMagicNumber     = 999999;        // Magic Number
input bool InpDebugMode      = true;          // Enable Detailed Logs

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

// Indicator Handles
int hRSI, hADX, hATR, hStoch, hMACD, hEMA20, hEMA50, hEMA200;
int hADX_Context, hEMA50_Context, hEMA200_Context; // NEW: HTF Context Handles
int hVWAP; // Custom or approximation

// State Variables
double AccountBalanceStartDay;
datetime LastDayChecked;
int DailyTradeCount;   // New: Track trades today
double       DailyRealizedPL; // New: Track Profit today
datetime     EngineCooldownUntil = 0; // Cooldown Timer

enum ENUM_REGIME {
   REGIME_TRENDING,
   REGIME_RANGING,
   REGIME_VOLATILE,
   REGIME_BREAKOUT,
   REGIME_UNKNOWN
};

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize Objects
   symbolInfo.Name(_Symbol);
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Initialize Indicators
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hADX = iADX(_Symbol, PERIOD_CURRENT, InpADX_Period);
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   hStoch = iStochastic(_Symbol, PERIOD_CURRENT, InpStoch_K, InpStoch_D, 3, MODE_SMA, STO_LOWHIGH);
   hMACD = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   hEMA20 = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, InpTrend_Timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, InpTrend_Timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   // Context TF Handles
   hADX_Context    = iADX(_Symbol, InpContext_Timeframe, 14); 
   hEMA50_Context  = iMA(_Symbol, InpContext_Timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200_Context = iMA(_Symbol, InpContext_Timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   hVWAP = iMA(_Symbol, PERIOD_CURRENT, InpVariable_MA, 0, MODE_SMA, PRICE_TYPICAL); // SMA of Typical Price as VWAP Proxy
   
   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE || 
      hStoch == INVALID_HANDLE || hMACD == INVALID_HANDLE || hEMA20 == INVALID_HANDLE || hVWAP == INVALID_HANDLE || 
      hADX_Context == INVALID_HANDLE || hEMA50_Context == INVALID_HANDLE || hEMA200_Context == INVALID_HANDLE) 
   {
      Print("Error creating indicators!");
      return INIT_FAILED;
   }

   // Initialize Account Tracking
   AccountBalanceStartDay = accountInfo.Balance();
   LastDayChecked = iTime(_Symbol, PERIOD_D1, 0);

   Print("Adaptive Multi-Strategy EA Initialized");
   
   // ⏰ Timer for Heartbeat (in case Market is closed/silent)
   EventSetTimer(60);
   
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
   IndicatorRelease(hStoch);
   IndicatorRelease(hMACD);
   IndicatorRelease(hEMA20);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hEMA200);
   IndicatorRelease(hADX_Context);
   IndicatorRelease(hEMA50_Context);
   IndicatorRelease(hEMA200_Context);
   IndicatorRelease(hVWAP);
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| ON TIMER (Independent of Ticks)                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpDebugMode) return;
   
   // Check when was the last tick
   datetime lastTick = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
   datetime now = TimeCurrent();
   
   if(now - lastTick > 60) // No ticks for 60s
   {
       Print("⏳ Timer Heartbeat: No ticks received for ", (int)(now-lastTick), "s. Market may be CLOSED, on BREAK, or Disconnected.");
       Print("   Server Time: ", TimeToString(now, TIME_MINUTES));
   }
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 0. Update Trailing States (Housekeeping)
   // Managed at end of OnTick
   
   // 1. Session & Time Logic
   CheckSessionClose();

   // 💤 UX Improvement: Heartbeat IF outside KillZone
   if(InpUse_KillZones && !IsKillZone())
   {
       static datetime lastHeartbeat = 0;
       if(TimeCurrent() - lastHeartbeat >= 300) // Every 5 mins
       {
           Print("💤 Outside KillZone (London/NY) - Strategy Paused | Server Time: ", TimeToString(TimeCurrent(), TIME_MINUTES));
           lastHeartbeat = TimeCurrent();
       }
   }

   // 3. Check Funding Rules (Daily Loss, Max DD, Daily Limits)
   if(!CheckFundingRules()) return;
   
   // 4. Data Gathering
   double rsi[], adx[], atr[], stochK[], stochD[], macd[], macdSig[], ema20[], ema50[], ema200[], vwap[];
   if(!GetIndicators(rsi, adx, atr, stochK, stochD, macd, macdSig, ema20, ema50, ema200, vwap)) return;
   
   // 3. Detect Market Regime
   ENUM_REGIME regime = DetectRegime(adx[0], atr[0]);

   // 🔎 DEBUG: Show that we are alive and scanning
   static datetime lastStatLog = 0;
   if(InpDebugMode && (TimeCurrent() - lastStatLog > 60)) 
   {
       Print("🔎 Analyzing... | Regime: ", EnumToString(regime), " | ADX: ", DoubleToString(adx[0],1), " | ATR: ", DoubleToString(atr[0],5));
       lastStatLog = TimeCurrent();
   }
   
   // 4. Update Smart State (e.g., Daily High/Low for CVD)
   // ...
   
   // 5. Execute Strategies (INSTITUTIONAL REGIME FILTER)
   // 🧠 BRAIN: ADX Decides what runs.
   // Rule: Trend Strategies need ADX > Threshold. Range strategies need ADX < Threshold.
   
   bool isTrending = (adx[0] > InpADX_Threshold);
   bool isRanging  = (adx[0] < InpADX_Threshold); // or use a buffer like < 20
   
   // Local Flags based on Inputs + Regime
   bool runInstitutional = InpEnable_Institutional && isTrending; // Sweep needs trend continuation
   bool runFibonacci     = InpEnable_Fibonacci     && isTrending; // Fib is for trend pullbacks
   bool runBreakout      = InpEnable_Breakout      && isTrending; // Breakout needs momentum
   
   bool runVWAP          = InpEnable_VWAP_Scalp    && isRanging;  // VWAP Mean Reversion needs Range
   bool runStoch         = InpEnable_Stochastic    && isRanging;  // Stoch Burst works best in Chop/Range
   
   // Override: If high impact news nearby, maybe disable scalps? (Already handled by NewsFilter inside strategies)
   
   if(InpDebugMode && (TimeCurrent() - lastStatLog < 2)) // Print only once per log cycle
   {
       string active = "";
       if(runInstitutional) active += "[Inst] ";
       if(runFibonacci)     active += "[Fib] ";
       if(runVWAP)          active += "[VWAP] ";
       if(runStoch)         active += "[Stoch] ";
       Print("🧠 Brain Active Modes: ", active);
   }

   if(runInstitutional) RunInstitutionalStrategy(regime, rsi, atr, ema20, ema50, ema200, adx, stochK, stochD, macd, macdSig, vwap);
   if(runVWAP)          RunVWAPStrategy(regime, vwap, rsi, ema20, ema50, ema200, atr, adx, stochK, stochD, macd, macdSig);
   if(runFibonacci)     RunFibonacciStrategy(regime, ema20, ema50, ema200, atr, rsi, adx, stochK, stochD, macd, macdSig, vwap);
   if(runStoch)         RunStochasticStrategy(regime, stochK, stochD, ema20, ema50, ema200, atr, adx, rsi, macd, macdSig, vwap);
   
   // 6. Manage Open Trades (Trailing Stop)
   // ManageTrade(); // Removed duplicate call
}

//+------------------------------------------------------------------+
//| DATA & INDICATORS                                                |
//+------------------------------------------------------------------+
bool GetIndicators(double &rsi[], double &adx[], double &atr[], 
                  double &stochK[], double &stochD[], 
                  double &macd[], double &macdSig[],
                  double &ema20[], double &ema50[], double &ema200[], double &vwap[])
{
   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return false;
   if(CopyBuffer(hADX, 0, 0, 3, adx) < 3) return false;
   if(CopyBuffer(hATR, 0, 0, 3, atr) < 3) return false;
   if(CopyBuffer(hStoch, 0, 0, 3, stochK) < 3) return false;
   if(CopyBuffer(hStoch, 1, 0, 3, stochD) < 3) return false;
   if(CopyBuffer(hMACD, 0, 0, 3, macd) < 3) return false;
   if(CopyBuffer(hMACD, 1, 0, 3, macdSig) < 3) return false;
   if(CopyBuffer(hEMA20, 0, 0, 3, ema20) < 3) return false;
   if(CopyBuffer(hEMA50, 0, 0, 3, ema50) < 3) return false;
   if(CopyBuffer(hEMA200, 0, 0, 3, ema200) < 3) return false;
   if(CopyBuffer(hVWAP, 0, 0, 3, vwap) < 3) return false;
   
   // Set Array Series
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(macdSig, true);
   ArraySetAsSeries(ema20, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema200, true);
   ArraySetAsSeries(vwap, true);
   
   return true;
}

//+------------------------------------------------------------------+
//| LOGIC FUNCTIONS                                                  |
//+------------------------------------------------------------------+

// Check Funding Firm Rules
bool CheckFundingRules()
{
   // Check New Day for Daily Loss Reset
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != LastDayChecked)
   {
      AccountBalanceStartDay = accountInfo.Balance();
      LastDayChecked = currentDay;
   }
   
   double currentEquity = accountInfo.Equity();
   
   // Daily Loss Limit
   double dailyLoss = (AccountBalanceStartDay - currentEquity) / AccountBalanceStartDay * 100.0;
   if(dailyLoss >= InpDaily_Loss_Percent)
   {
      if(InpDebugMode) Print("STOP: Daily Loss Limit Hit (" + DoubleToString(dailyLoss, 2) + "%)");
      return false;
   }
   
   // --- NEW: Daily Limits Calculation ---
   CalculateDailyStats();
   
   // 1. Max Daily Trades
   if(InpMax_Daily_Trades > 0 && DailyTradeCount >= InpMax_Daily_Trades)
   {
      if(InpDebugMode) Print("STOP: Max Daily Trades Reached (" + IntegerToString(DailyTradeCount) + ")");
      return false;
   }
   
   // 2. Daily Profit Target
   if(InpTarget_Daily_Profit > 0)
   {
      double profitSide = (DailyRealizedPL + (currentEquity - accountInfo.Balance())); // Realized + Floating? Usually target is Realized.
      // Let's stick to Realized for "Target Reached, Stop Trading".
      
      double profitPct = (DailyRealizedPL / AccountBalanceStartDay) * 100.0;
      if(profitPct >= InpTarget_Daily_Profit)
      {
         if(InpDebugMode) Print("STOP: Daily Profit Target Hit (" + DoubleToString(profitPct, 2) + "%)");
         return false;
      }
   }
   
   // Max Drawdown (Total)
   // NOTE: This assumes Deposit is initial. For true prop firm, usually fixed value or high water mark.
   
   return true;
}

//+------------------------------------------------------------------+
//| UTILS                                                            |
//+------------------------------------------------------------------+
void CalculateDailyStats()
{
   DailyTradeCount = 0;
   DailyRealizedPL = 0.0;
   
   // Get History for Today
   HistorySelect(LastDayChecked, TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i=0; i<total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         
         if(magic == InpMagicNumber)
         {
            // Count Exits (Out or Out/By) as closed trades
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
            {
               DailyTradeCount++;
               DailyRealizedPL += HistoryDealGetDouble(ticket, DEAL_PROFIT);
               DailyRealizedPL += HistoryDealGetDouble(ticket, DEAL_SWAP);
               DailyRealizedPL += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            }
         }
      }
   }
}

datetime GetLastTradeTime()
{
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
         {
             return (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         }
      }
   }
   return 0;
}

bool HasOpenTrade(string commentFilter)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, commentFilter) >= 0) return true;
         }
      }
   }
   return false;
}

// Check Funding Firm Rules (Block New Entries)
double GetAverageATR(int periods)
{
   double atrArr[];
   if(CopyBuffer(hATR, 0, 0, periods, atrArr) < periods) return 0;
   
   double sum = 0;
   for(int i = 0; i < periods; i++) sum += atrArr[i];
   return sum / periods;
}

bool IsADXRising()
{
   double adxArr[];
   if(CopyBuffer(hADX, 0, 0, 3, adxArr) < 3) return false;
   ArraySetAsSeries(adxArr, true);
   
   return (adxArr[0] > adxArr[1] && adxArr[1] > adxArr[2]);
}

ENUM_REGIME DetectRegime(double adxVal, double atrVal)
{
   // Enhanced Regime Detection
   double atrAvg = GetAverageATR(14);
   double atrRatio = (atrAvg > 0) ? atrVal / atrAvg : 1.0;
   
   // 1. Volatility Detection
   if(atrRatio > 1.5) return REGIME_VOLATILE;
   
   // 2. Breakout Detection
   if(adxVal > InpADX_Threshold && IsADXRising()) return REGIME_BREAKOUT;
   
   // 3. Trend vs Range
   if(adxVal > InpADX_Threshold) return REGIME_TRENDING;
   
   return REGIME_RANGING;
}

//+------------------------------------------------------------------+
//| CONFLUENCE HELPERS                                               |
//+------------------------------------------------------------------+
double GetRegimeMultiplier(ENUM_REGIME regime, string factor)
{
   if(regime == REGIME_TRENDING)
   {
      if(factor == "TREND") return 1.4;
      if(factor == "MEAN")  return 0.6;
   }
   if(regime == REGIME_RANGING)
   {
      if(factor == "TREND") return 0.6;
      if(factor == "MEAN")  return 1.4;
   }
   return 1.0;
}

int GetRecentLosses(string commentFilter, int count)
{
   int losses = 0;
   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent()); // Check today's history or wider? Let's check last N deals
   // Actually simpler to check last N unique trades.
   // Simplified: check last 'count' closed deals for this symbol/magic
   
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   int checked = 0;
   
   for(int i = total - 1; i >= 0; i--)
   {
      if(checked >= count) break;
      
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue; // Only exits
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      if(commentFilter != "" && StringFind(comment, commentFilter) < 0) continue; // Filter by strategy tag if set
      
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit < 0) losses++;
      else losses = 0; // Reset streak on win? User logic says "last 2 trades were SL". 
                       // Usually "consecutive losses". Let's assume consecutive.
      
      checked++;
   }
   return losses;
}

double GetAdaptiveMinScore(string setupTag)
{
   int losses = GetRecentLosses(setupTag, 2);
   if(losses >= 2) return InpMin_Confluence_Score + 1.5; // Adaptive: Require higher score after losses
   return InpMin_Confluence_Score;
}

//+------------------------------------------------------------------+
//| CONFLUENCE SCORE CALCULATOR V2 (Weighted & Adaptive)             |
//+------------------------------------------------------------------+
double CalculateConfluenceScore(string strategy, bool isBuy, ENUM_REGIME regime, double &rsi[], double &stochK[], double &stochD[], double &macd[], double &macdSig[], double &ema20[], double &ema50[], double &ema200[], double &adx[], double &vwap[])
{
   double score = 0.0;
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);

   // --- INSTITUTIONAL & FIB (Internal Structure) ---
   if(strategy == "Inst" || strategy == "Fib")
   {
       // 1. Trend Alignment (Weight 3.0)
       bool trendAligned = (isBuy && ema50[0] > ema200[0]) || (!isBuy && ema50[0] < ema200[0]);
       if(trendAligned) score += 3.0;

       // 2. VWAP Confluence (Weight 2.0)
       bool vwapAligned = (isBuy && close > vwap[0]) || (!isBuy && close < vwap[0]);
       if(vwapAligned) score += 2.0;

       // 3. ADX Trend Strength (Weight 2.0)
       if(adx[0] > InpADX_Threshold) score += 2.0;
       
       // 4. Killzone (Weight 2.0)
       if(IsKillZone()) score += 2.0;
       
       // Max: 9.0. Min Req: 6.0
   }
   
   // --- SCALPERS (Oscillators) ---
   else if(strategy == "VWAP" || strategy == "Stoch")
   {
       // 1. RSI Extreme/Reversion (Weight 2.5)
       // For VWAP Reversion: We want RSI Extreme (Oversold for Buy).
       if(isBuy && rsi[0] < 45) score += 2.5; 
       if(!isBuy && rsi[0] > 55) score += 2.5;
       
       // 2. Stoch Cross (Weight 2.0)
       bool stochCross = (isBuy && stochK[0] > stochD[0]) || (!isBuy && stochK[0] < stochD[0]);
       if(stochCross) score += 2.0;
       
       // 3. Regime Range (Weight 2.0)
       if(regime == REGIME_RANGING) score += 2.0;
        
       // 4. VWAP Reversion Potential (Weight 2.5)
       // Verify we are deviating from VWAP
       bool reversionSetup = (isBuy && close < vwap[0]) || (!isBuy && close > vwap[0]);
       if(reversionSetup) score += 2.5;
       
       // 5. 🔒 MACRO TREND FILTER (The 60% Win Rate Fix)
       // Even for scalps, we must respect the H4 Trend (Gold is directional).
       bool trendAligned = (isBuy && ema50[0] > ema200[0]) || (!isBuy && ema50[0] < ema200[0]);
       if(trendAligned) score += 2.0; 
       else             score -= 10.0; // ⛔ VETO: Do not scalp against the H4 Train.
   }
   
   return score; 
}

//+------------------------------------------------------------------+
//| QUALITY INDEX & DYNAMIC ENGINE                                   |
//+------------------------------------------------------------------+
double GetMaxScore(string setup)
{
   if(setup == "Inst")   return 9.5;
   if(setup == "VWAP")   return 8.0;
   if(setup == "Fib")    return 9.0;
   if(setup == "Stoch")  return 7.5;
   return 8.0;
}

double GetQualityIndex(double score, string setup)
{
   double maxScore = GetMaxScore(setup);
   if(maxScore <= 0) return 0.0;
   return MathMin(score / maxScore, 1.0);
}

double GetDynamicRisk(double quality, ENUM_REGIME regime)
{
   double base = InpRisk_Per_Trade;

   // Quality scaling
   if(quality >= 0.85) base *= 1.4;
   else if(quality >= 0.75) base *= 1.2;
   else if(quality <= 0.60) base *= 0.7;

   // Regime safety
   if(regime == REGIME_RANGING) base *= 0.9; // Range often choppier
   // If we had REGIME_VOLATILE, we'd reduce more. Assuming current regimes:
   // Trending vs Ranging vs Breakout.
   
   // Hard safety caps
   base = MathMax(0.25, base);
   base = MathMin(1.0, base);

   return base;
}

double GetDynamicRR(double quality, ENUM_REGIME regime)
{
   double rr = InpRisk_Reward_Ratio;

   // Quality Boost
   if(quality >= 0.85) rr += 0.7;
   else if(quality >= 0.75) rr += 0.4;
   else if(quality <= 0.60) rr -= 0.3;

   // Regime Adjustment
   if(regime == REGIME_RANGING) rr -= 0.3; // Take profit sooner in range
   if(regime == REGIME_TRENDING) rr += 0.3; // Let trend runs run

   // Safety Caps
   rr = MathMax(1.5, rr);
   rr = MathMin(3.5, rr);

   return rr;
}

bool IsEngineHealthy()
{
   datetime now = TimeCurrent();

   // If cooldown active -> block trading
   if(EngineCooldownUntil > now)
   {
      // Optional: Reduce log spam
      return false; 
   }

   // Check recent loss streak
   int losses = GetRecentLosses("", 5);

   if(losses >= 3)
   {
       datetime lastTrade = GetLastTradeTime();
       // Only trigger cooldown if last loss was RECENT (e.g., < 5 mins ago)
       if(now - lastTrade < 300) 
       {
           EngineCooldownUntil = now + (InpCooldownMinutes * 60);
           if(InpDebugMode) Print("🔥 Cooldown ACTIVATED: ", InpCooldownMinutes, " min");
           return false;
       }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| EXECUTION WRAPPER (Dynamic Risk)                                 |
//+------------------------------------------------------------------+
// Modified to accept custom Risk %
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl, double tp, string comment, double riskPct = 0.0)
{
   // 0. Engine Health Check
   if(!IsEngineHealthy())
   {
      if(InpDebugMode) Print("🛑 Engine Cooldown Active: Too many recent losses.");
      return;
   }

   // 1. Spread Check REMOVED per user request
   // int spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   // if(spread > InpMax_Spread_Points) ...

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = MathAbs(price - sl);
   
   // Use Dynamic Risk if passed, otherwise default to InpRisk_Per_Trade
   double effectiveRisk = (riskPct > 0.0) ? riskPct : InpRisk_Per_Trade;

   // 🔒 CRITICAL: Cap XAUUSD Risk to 0.5% max if requested, or just rely on InpMaxLot check later.
   // We will implement this safety cap for Gold specifically as requested.
   if(StringFind(_Symbol, "XAU") >= 0) effectiveRisk = MathMin(effectiveRisk, 0.5);
   
   double volume = CalculateLotSizeWithRisk(slDist, effectiveRisk);

   // 🔒 CRITICAL: Check Margin before trying to open
   double marginRequired = 0.0;
   if(!OrderCalcMargin(type, _Symbol, volume, price, marginRequired))
   {
       Print("❌ Margin Calc Failed for ", volume, " lots");
       return;
   }
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(marginRequired > freeMargin)
   {
       // 💡 SMART FIX: Instead of rejecting, AUTO-REDUCE the lot to fit available margin
       // We aim to use max 95% of available free margin to be safe
       double maxMarginUsable = freeMargin * 0.95; 
       double ratio = maxMarginUsable / marginRequired;
       
       double safeVol = volume * ratio;
       
       // Normalize Safe Vol
       double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
       safeVol = MathFloor(safeVol / step) * step;
       double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

       if(safeVol < minLot)
       {
          if(InpDebugMode) Print("⛔ MARGIN FAIL: Even Min Lot is too expensive! Need ", DoubleToString(marginRequired, 2), " | Free ", DoubleToString(freeMargin, 2));
          return;
       }
       
       if(InpDebugMode) Print("⚠️ MARGIN ADAPT: Reduced Lot ", volume, " -> ", safeVol, " to fit FreeMargin (", DoubleToString(freeMargin,2), ")");
       volume = safeVol;
       
       // Re-verify strictly? No, the ratio math is solid enough for M5 execution.
   }
   
   if(InpDebugMode) Print("🚀 Executing ", comment, " | Risk: ", DoubleToString(effectiveRisk, 2), "% | Lot: ", volume);
   
   trade.PositionOpen(_Symbol, type, volume, price, sl, tp, comment);
}

// Helper to calc lot size based on risk % of Balance
double CalculateLotSizeWithRisk(double slDistance, double riskPerc)
{
   double balance = accountInfo.Balance();
   double riskAmount = balance * (riskPerc / 100.0);
   
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
   
   // Safety Cap
   if(lotSize > InpMaxLot_Per_Trade) lotSize = InpMaxLot_Per_Trade;
   
   // MARGIN SAFETY CHECK (IMPROVED)
   double marginRequired = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
   {
       double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
       double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
       
       // Block if Margin Level Critical (< 200%)
       if(marginLevel > 0 && marginLevel < 200) return 0.0;
       
       // Reduce if exceeds 80% of free margin
       if(marginRequired > freeMargin * 0.8)
       {
           double ratio = (freeMargin * 0.7) / marginRequired;
           lotSize = MathFloor((lotSize * ratio) / step) * step;
           if(InpDebugMode) Print("⚠️ Margin Adapt: Reduced Lot to ", lotSize);
           
           if(lotSize < minLot) return 0.0;
       }
   }
   
   return lotSize;
}

void RunInstitutionalStrategy(ENUM_REGIME regime, double &rsi[], double &atr[], double &ema20[], double &ema50[], double &ema200[], double &adx[], double &stochK[], double &stochD[], double &macd[], double &macdSig[], double &vwap[])
{
   // 0. Kill Zone Filter (Critical)
   if(InpUse_KillZones && !IsKillZone()) return;
   
   // 0b. News Filter
   if(InpUse_NewsFilter && IsNewsTime()) {
       if(InpDebugMode) Print("⚠️ News Filter Active: Trade Blocked");
       return;
   }
   
   if(HasOpenTrade("Inst")) return; // Only one Institutional trade at a time
   
   // 1. Identify Liquidity POOLS (20 candle High/Low)
   // We look back 20 candles EXCLUDING current (1 to 21)
   double swingHigh = 0;
   double swingLow = 999999;
   
   int lookback = InpSwap_Lookback;
   
   // Get Highs/Lows
   double highs[], lows[];
   CopyHigh(_Symbol, PERIOD_CURRENT, 1, lookback, highs);
   CopyLow(_Symbol, PERIOD_CURRENT, 1, lookback, lows);
   
   for(int i=0; i<lookback; i++) {
      if(highs[i] > swingHigh) swingHigh = highs[i];
      if(lows[i] < swingLow) swingLow = lows[i];
   }
   
   // 2. Logic: Price Breaks Level but Closes Inside
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double high  = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double low   = iLow(_Symbol, PERIOD_CURRENT, 0);
   
   // --- BULLISH SWEEP ---
   // Low sweeps SwingLow, but Close is above SwingLow
   if(low < swingLow && close > swingLow)
   {
      // Confirmation 1: H1/H4 Trend (EMA50 > EMA200)
      bool trendOk = ema50[0] > ema200[0];
      
      // Confirmation 2: REPLACED RSI with PURE STRUCTURE
      // We rely on the Sweep + Trend. 
      
      if(trendOk)
      {
         // CONFLUENCE CHECK
         double score = CalculateConfluenceScore("Inst", true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
         
         if(InpUse_Confluence_Filter)
         {
             double minScore = GetAdaptiveMinScore("Inst");
             if(score < minScore)
             {
                 if(InpDebugMode) Print("⚠️ Inst. Buy Skipped: Score ", score, " < ", minScore);
                 return;
             }
         }

         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "Inst");
         double riskPct = GetDynamicRisk(quality, regime);
         double dynRR   = GetDynamicRR(quality, regime);

         double sl = swingLow - (atr[0] * 0.5); // Tight SL behind the sweep
         double tp = close + (close - sl) * dynRR;
         
         string comment = StringFormat("Inst_Buy_Q%.2f", quality);
         
         if(InpDebugMode) Print("⚡ Institutional BUY: Sweep Low ", swingLow, " SL=", sl);
         
         // 🛑 CONTEXT CHECK 🛑
         if(!IsContextFavorable(true)) return;
         
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, comment, riskPct);
      }
   }
   
   // --- BEARISH SWEEP ---
   // High sweeps SwingHigh, but Close is below SwingHigh
   else if(high > swingHigh && close < swingHigh)
   {
      // Confirmation 1: Trend
      bool trendOk = ema50[0] < ema200[0];
      
      // Confirmation 2: REPLACED RSI with PURE STRUCTURE
      
      if(trendOk)
      {
         // CONFLUENCE CHECK
         double score = CalculateConfluenceScore("Inst", false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
         
         if(InpUse_Confluence_Filter)
         {
             double minScore = GetAdaptiveMinScore("Inst");
             if(score < minScore)
             {
                 if(InpDebugMode) Print("⚠️ Inst. Sell Skipped: Score ", score, " < ", minScore);
                 return;
             }
         }
         
         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "Inst");
         double riskPct = GetDynamicRisk(quality, regime);
         double dynRR   = GetDynamicRR(quality, regime);

         double sl = swingHigh + (atr[0] * 0.5);
         double tp = close - (sl - close) * dynRR;
         
         string comment = StringFormat("Inst_Sell_Q%.2f", quality);
         
         if(InpDebugMode) Print("⚡ Institutional SELL: Sweep High ", swingHigh, " SL=", sl);
         
         // 🛑 CONTEXT CHECK 🛑
         if(!IsContextFavorable(false)) return;
         
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, comment, riskPct);
      }
   }
}

// Kill Zone Logic (London 02-05, NY 08-11, Close 10-12 EST)
bool IsKillZone()
{
   // EST Calculation: TimeCurrent (Server) - Offset
   datetime estTime = TimeCurrent() - (InpServerTimeOffset * 3600);
   MqlDateTime dtEST;
   TimeToStruct(estTime, dtEST);
   
   string currentEST = StringFormat("%02d:%02d", dtEST.hour, dtEST.min);
   
   if(InpUse_London_Killzone && CheckTimeRange(currentEST, InpLondon_Start, InpLondon_End)) return true;
   if(InpUse_NY_Killzone && CheckTimeRange(currentEST, InpNY_Start, InpNY_End)) return true;
   if(InpUse_LondonClose_Killzone && CheckTimeRange(currentEST, InpLondonClose_Start, InpLondonClose_End)) return true;
   
   return false;
}

// Helper: Check if Current "HH:MM" is inside Start "HH:MM" and End "HH:MM"
bool CheckTimeRange(string current, string start, string end)
{
   if(start < end) {
      // Normal range: 08:00 to 11:00
      return (current >= start && current <= end);
   } else {
      // Overnight range: 22:00 to 02:00
      return (current >= start || current <= end);
   }
}

// Session Close Logic
void CheckSessionClose()
{
   if(!InpCloseTrades_At_SessionEnd) return;
   if(!InpUse_KillZones) return; // ✅ FIX: If KillZones disabled, don't enforce session close

   
   // If we are NOT in a KillZone, Close All
   if(!IsKillZone())
   {
      if(position.Select(_Symbol) && position.Magic() == InpMagicNumber) // If we have a position with our Magic
      {
          // Close it
          trade.PositionClose(_Symbol);
          if(InpDebugMode) Print("⌛ Session End: Forced Close of " + _Symbol);
      }
   }
}

// Duplicate ExecuteTrade and CalculateLotSize removed. 
// Using top-level dynamic ExecuteTrade and CalculateLotSizeWithRisk instead.

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT (Tiered Trailing Stop)                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| TRADE MANAGEMENT (GOD MODE - Adaptive Trailing)                  |
//+------------------------------------------------------------------+
double GetTrailBoost(double quality)
{
   if(quality >= 0.85) return 1.35;
   if(quality >= 0.75) return 1.15;
   if(quality >= 0.65) return 1.00;
   return 0.85;
}

//+------------------------------------------------------------------+
//| COMPUTE PARTIAL TP                                               |
//+------------------------------------------------------------------+
// Returns fraction of position to close (0‑1). 0 means no partial close.
double ComputePartialTP(bool isBuy, double quality, ENUM_REGIME regime, double profitR, ulong ticket, double openPrice, double currentPrice, string comment)
{
   double fraction = 0.0;
   // VWAP trigger: price has moved beyond VWAP in direction of trade and profitR >= 1.5
   if(InpPartialTP_VWAP && profitR >= 1.5)
   {
      double vwap = 0.0;
      // vwap is passed via global array; we can fetch latest value
      double vwapArr[];
      if(CopyBuffer(hVWAP, 0, 0, 1, vwapArr) > 0)
      {
         vwap = vwapArr[0];
         if(isBuy && currentPrice > vwap) fraction = MathMax(fraction, InpPartialTP_PercentVWAP);
         if(!isBuy && currentPrice < vwap) fraction = MathMax(fraction, InpPartialTP_PercentVWAP);
      }
   }
   // Liquidity sweep trigger: use profitR >= 2.0 as proxy for sweep completion
   if(InpPartialTP_Liquidity && profitR >= 2.0)
   {
      fraction = MathMax(fraction, InpPartialTP_PercentLiquidity);
   }
   // Time‑based trigger: close after certain minutes in trade
   if(InpPartialTP_Time)
   {
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int minutesInTrade = (int)((TimeCurrent() - openTime) / 60);
      if(minutesInTrade >= InpPartialTP_TimeMinutes)
         fraction = MathMax(fraction, InpPartialTP_PercentTime);
   }
   // Fibonacci zone trigger: simple check using recent swing high/low and quality
   if(InpPartialTP_Fib && profitR >= 1.0)
   {
      // Approximate: if quality high and regime trending, consider fib trigger
      if(quality >= 0.8 && regime == REGIME_TRENDING)
         fraction = MathMax(fraction, InpPartialTP_PercentFib);
   }
   // Debug label
   if(InpDebugMode && fraction > 0)
   {
      Print("🔹 Partial TP trigger activated: fraction=", DoubleToString(fraction,2));
   }
   return fraction;
}

double GetLastStructureSL(bool isBuy)
{
   int lookback = 10; // 10 candles
   double level = isBuy ? iHigh(_Symbol, PERIOD_CURRENT, 1) : iLow(_Symbol, PERIOD_CURRENT, 1);
   
   // We look for LOCAL EXTREMES.
   // For Buy: We want the recent LOWEST LOW to hide behind? 
   // Actually for Trailing Buy: We want to trail behind HIGHER LOWS.
   // But simple logic: Find lowest low in last N candles to protect against deep pullback?
   // Standard Structure Trail: 
   // Buy -> Trail below Lows. Sell -> Trail above Highs.
   
   if(isBuy) 
   {
       level = iLow(_Symbol, PERIOD_CURRENT, 1);
       for(int i=2; i<=lookback; i++)
       {
          double low = iLow(_Symbol, PERIOD_CURRENT, i);
          if(low < level) level = low;
       }
   }
   else 
   {
       level = iHigh(_Symbol, PERIOD_CURRENT, 1);
       for(int i=2; i<=lookback; i++)
       {
          double high = iHigh(_Symbol, PERIOD_CURRENT, i);
          if(high > level) level = high;
       }
   }
   return level;
}

double GetATRBuffer()
{
   double atrArr[];
   if(CopyBuffer(hATR, 0, 0, 1, atrArr) > 0)
   {
      return atrArr[0] * 0.35; // 35% of ATR as buffer
   }
   return 0;
}

double ParseQualityFromComment(string comment)
{
   // Format: "Type_Side_Q0.95"
   int start = StringFind(comment, "_Q");
   if(start < 0) return 0.5; // Default if not found
   
   string qStr = StringSubstr(comment, start + 2); // Skip "_Q"
   return StringToDouble(qStr);
}

void ManageTrade()
{
   if(InpDebugMode) Print(" --- ManageTrade Upgrade ---");

   // Cache ADX/ATR once per tick
   double adx[], atr[];
   ArraySetAsSeries(adx, true); ArraySetAsSeries(atr, true);
   int adxHandle = iADX(_Symbol, PERIOD_CURRENT, 14);
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
   CopyBuffer(adxHandle, 0, 0, 1, adx);
   CopyBuffer(atrHandle, 0, 0, 1, atr);
   double currentADX = adx[0];
   double currentATR = atr[0];

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      // 1. Initial Data
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      long type = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (type == POSITION_TYPE_BUY);
      string comment = PositionGetString(POSITION_COMMENT);
      
      double riskDist = MathAbs(openPrice - sl); // Initial Risk
      if(riskDist == 0) riskDist = currentATR; // Fallback

      double profitPoints = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double profitR = profitPoints / riskDist;

      // 2. State Machine Update
      // Get Current State (From Cache)
      ENUM_TRAIL_STATE currentState = (ENUM_TRAIL_STATE)GetStateFromCache(ticket);
      
      // Calculate Next State
      ENUM_TRAIL_STATE nextState = UpdateTrailState(ticket, currentState, profitR, currentADX, currentATR, InpRisk_Per_Trade);
      
      // Update Cache if Changed
      if(nextState != currentState)
      {
          UpdateStateCache(ticket, (int)nextState);
          if(InpDebugMode) Print("🔄 State Transition [", ticket, "]: ", EnumToString(currentState), " -> ", EnumToString(nextState));
      }
      
      // 3. Execution (Get New SL)
      double newSL = GetTrailingSL(nextState, isBuy, openPrice, currentPrice, sl, tp, currentATR);
      
      // 4. Modify Order (Only if SL changes significantly)
      double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      bool isValidSL = false;
      if(isBuy && newSL > sl && newSL < currentPrice - minStopLevel) isValidSL = true;
      if(!isBuy && newSL < sl && newSL > currentPrice + minStopLevel) isValidSL = true;
      // Note: Logic handles "Don't move SL back" implicitly by MathMax/Min in GetTrailingSL
      
      if(isValidSL && MathAbs(newSL - sl) > SymbolInfoDouble(_Symbol, SYMBOL_POINT))
      {
          trade.PositionModify(ticket, newSL, tp);
          if(InpDebugMode) Print("🛡️ Trail Update [", EnumToString(nextState), "]: SL ", sl, " -> ", newSL);
      }
      
      // 5. Partial TP Logic
      // Detect Regime for this logic
      ENUM_REGIME regime = DetectRegime(currentADX, currentATR);
      double quality = ParseQualityFromComment(comment);
      if(quality == 0) quality = 0.5;

      double partialFrac = ComputePartialTP(isBuy, quality, regime, profitR, ticket, openPrice, currentPrice, comment);
      
      if(partialFrac > 0 && !WasPartialExecuted(ticket))
      {
         double vol = PositionGetDouble(POSITION_VOLUME);
         if(vol > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) // Only if we can scale out
         {
             double closeVol = vol * partialFrac;
             // Normalize
             double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
             closeVol = MathFloor(closeVol / step) * step;
             double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
             
             if(closeVol < minVol) closeVol = minVol;
             
             if((vol - closeVol) >= minVol) // Ensure remainder is valid
             {
                if(trade.PositionClosePartial(ticket, closeVol))
                {
                   SetPartialExecuted(ticket, true);
                   if(InpDebugMode) Print("💰 Partial TP Executed: ", DoubleToString(closeVol, 2), " lots (", (int)(partialFrac*100), "%)");
                }
             }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| NEWS FILTER                                                      |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   if(!InpUse_NewsFilter) return false;
   
   datetime now = TimeCurrent();
   datetime start = now - (InpNews_After_Mins * 60); // Look back (for "After" impact)
   datetime end   = now + (InpNews_Before_Mins * 60); // Look forward (for "Before" impact)
   
   // Get Calendar Values
   MqlCalendarValue values[];
   
   // We search for events in the range [now - After, now + Before]
   // If any High Impact event exists in this range, we are "In News Time".
   
   // Filter by Currency
   string base = StringSubstr(_Symbol, 0, 3);
   string quote = StringSubstr(_Symbol, 3, 3);
   
   if(CalendarValueHistory(values, start, end, NULL, NULL))
   {
      int total = ArraySize(values);
      for(int i=0; i<total; i++)
      {
         ulong eventId = values[i].event_id;
         MqlCalendarEvent event;
         if(CalendarEventById(eventId, event))
         {
             MqlCalendarCountry countryDesc;
             if(!CalendarCountryById(event.country_id, countryDesc)) continue;
             string currency = countryDesc.currency; 
             if(currency == "") continue;

             // Check Currency
             if(StringFind(base, currency) < 0 && StringFind(quote, currency) < 0 && currency != "USD") // Always check USD? Optional.
                continue;
             // But actually "USD" is usually in the pair if it matters.
             
             // Check Importance
             if(InpNews_HighImpact_Only && event.importance != CALENDAR_IMPORTANCE_HIGH)
                continue;
                
             // If we found a relevant event in the danger zone
             // Check precise time:
             // Danger Start = EventTime - Before
             // Danger End   = EventTime + After
             // We are at 'now'.
             // EventTime is values[i].time (or event.time?) -> values[i].time refers to period usually.
             // event.time_mode?
             // Actually values[i].time is the event timestamp.
             
             datetime eventTime = values[i].time;
             
             if(now >= (eventTime - InpNews_Before_Mins*60) && now <= (eventTime + InpNews_After_Mins*60))
             {
                if(InpDebugMode) Print("📰 News Active: ", event.name, " (", currency, ")");
                return true;
             }
         }
      }
   }
   
   return false;
}
//+------------------------------------------------------------------+
//| STRATEGY 2: VWAP SCALPING (Mean Reversion)                       |
//+------------------------------------------------------------------+
void RunVWAPStrategy(ENUM_REGIME regime, double &vwap[], double &rsi[], double &ema20[], double &ema50[], double &ema200[], double &atr[], double &adx[], double &stochK[], double &stochD[], double &macd[], double &macdSig[])
{
   // Only trade in Range/Trend, not Breakout
   if(regime == REGIME_BREAKOUT) return;
   if(HasOpenTrade("VWAP")) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   // vwap[], rsi[], etc. passed as arrays
   
   // --- BUY SCALP ---
   // Uptrend (EMA20 > EMA50) but Price is 'Cheap' (Below VWAP)
   if(ema20[0] > ema50[0] && close < vwap[0])
   {
      // Confirmation: RSI Oversold
      if(rsi[0] < 35)
      {
          // CONFLUENCE CHECK
          double score = CalculateConfluenceScore("VWAP", true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
          
          if(InpUse_Confluence_Filter)
          {
              double minScore = GetAdaptiveMinScore("VWAP");
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ VWAP Buy Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }

         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "VWAP");
         double riskPct = GetDynamicRisk(quality, regime);
         // double dynRR = GetDynamicRR(quality, regime); // VWAP usually target is VWAP line, unless we want extension.
         // Current logic: tp = vwap[0] + (vwap[0] - close) * 0.5;
         
         double sl = close - (atr[0] * 1.5);
         double tp = vwap[0] + (vwap[0] - close) * 0.5; 
         
         string comment = StringFormat("VWAP_Buy_Q%.2f", quality);
         
         if(InpDebugMode) Print("⚡ VWAP Scalp BUY: Price ", close, " < VWAP ", vwap[0]);
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, comment, riskPct);
      }
   }
   
   // --- SELL SCALP ---
   // Downtrend but Price is 'Expensive' (Above VWAP)
   else if(ema20[0] < ema50[0] && close > vwap[0])
   {
      if(rsi[0] > 65)
      {
          // CONFLUENCE CHECK
          double score = CalculateConfluenceScore("VWAP", false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
          
          if(InpUse_Confluence_Filter)
          {
              double minScore = GetAdaptiveMinScore("VWAP");
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ VWAP Sell Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }
          
         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "VWAP");
         double riskPct = GetDynamicRisk(quality, regime);

         double sl = close + (atr[0] * 1.5);
         double tp = vwap[0] - (close - vwap[0]) * 0.5;
         
         string comment = StringFormat("VWAP_Sell_Q%.2f", quality);
         
         if(InpDebugMode) Print("⚡ VWAP Scalp SELL: Price ", close, " > VWAP ", vwap[0]);
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, comment, riskPct);
      }
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 4: STOCHASTIC MOMENTUM                                  |
//+------------------------------------------------------------------+
void RunStochasticStrategy(ENUM_REGIME regime, double &stochK[], double &stochD[], double &ema20[], double &ema50[], double &ema200[], double &atr[], double &adx[], double &rsi[], double &macd[], double &macdSig[], double &vwap[])
{
   if(HasOpenTrade("Stoch")) return;
   
   bool uptrend = ema20[0] > ema50[0];
   bool downtrend = ema20[0] < ema50[0];
   
   // BUY: Uptrend + Stoch Cross UP in oversold (< 25)
   if(uptrend && stochK[1] < 25 && stochD[1] < 25)
   {
      // Cross Check: K crosses above D
      if(stochK[1] < stochD[1] && stochK[0] > stochD[0])
      {
          // CONFLUENCE CHECK
          double score = CalculateConfluenceScore("Stoch", true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
          
          if(InpUse_Confluence_Filter)
          {
              double minScore = GetAdaptiveMinScore("Stoch");
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ Stoch Buy Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }
          
         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "Stoch");
         double riskPct = GetDynamicRisk(quality, regime);
         double dynRR   = GetDynamicRR(quality, regime);

         double close = iClose(_Symbol, PERIOD_CURRENT, 0);
         double sl = close - (atr[0] * 1.5);
         double tp = close + (atr[0] * (1.5 * dynRR)); // Adjust ATR multiplier by RR? Original was close + atr*3 (so RR ~2). 
         // Let's us SL distance * RR
         // SL dist = atr*1.5. TP dist = slDist * dynRR.
         tp = close + ((atr[0] * 1.5) * dynRR);
         
         string comment = StringFormat("Stoch_Buy_Q%.2f", quality);
         
         if(InpDebugMode) Print("🚀 Stoch Buy: Cross Up in Trend");
         
         if(!IsContextFavorable(true)) return; // 🛑 CTF
         
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, comment, riskPct);
      }
   }
   
   // --- SELL ZONE ---
   else if(downtrend && stochK[1] > 75 && stochD[1] > 75)
   {
      if(stochK[1] > stochD[1] && stochK[0] < stochD[0])
      {
          // CONFLUENCE CHECK
          double score = CalculateConfluenceScore("Stoch", false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
          
          if(InpUse_Confluence_Filter)
          {
              double minScore = GetAdaptiveMinScore("Stoch");
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ Stoch Sell Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }
          
         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "Stoch");
         double riskPct = GetDynamicRisk(quality, regime);
         double dynRR   = GetDynamicRR(quality, regime);

         double close = iClose(_Symbol, PERIOD_CURRENT, 0);
         double sl = close + (atr[0] * 1.5);
         double tp = close - ((atr[0] * 1.5) * dynRR);
         
         string comment = StringFormat("Stoch_Sell_Q%.2f", quality);
         
         if(InpDebugMode) Print("🚀 Stoch Sell: Cross Down in Trend");
         
         if(!IsContextFavorable(false)) return; // 🛑 CTF
         
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, comment, riskPct);
      }
   }
}

//+------------------------------------------------------------------+
//| CONTEXT FILTER (THE GATEKEEPER - H1/H4)                          |
//+------------------------------------------------------------------+
bool IsContextFavorable(bool isBuy)
{
   // 1. Get Context ADX (Regime)
   double adxBuffer[];
   if(CopyBuffer(hADX_Context, 0, 0, 1, adxBuffer) < 1) return true; // Fail safe: Allow trade
   double adx = adxBuffer[0];
   
   // 2. Get Context Price Channel (Donchian)
   // We use iHigh/iLow on Context TF for last N bars
   double high = iHigh(_Symbol, InpContext_Timeframe, iHighest(_Symbol, InpContext_Timeframe, MODE_HIGH, InpContext_Lookback, 1));
   double low  = iLow(_Symbol, InpContext_Timeframe, iLowest(_Symbol, InpContext_Timeframe, MODE_LOW, InpContext_Lookback, 1));
   double current = iClose(_Symbol, InpContext_Timeframe, 0);
   
   double range = high - low;
   if(range <= 0) return true;
   
   double position = (current - low) / range; // 0.0 = Low, 1.0 = High
   
   // --- LOGIC GATE ---
   bool isTrendMode = (adx > 25);
   bool isRangeMode = (adx < 20);
   
   if(isRangeMode)
   {
       // In Range: STRICT FILTER
       if(isBuy && position > 0.75)  { if(InpDebugMode) Print("⛔ Context Veto: Buying at Range High"); return false; }
       if(!isBuy && position < 0.25) { if(InpDebugMode) Print("⛔ Context Veto: Selling at Range Low"); return false; }
   }
   else if(isTrendMode)
   {
       // In Trend: Check H1 Alignment
       // Use Global Handles (hEMA50_Context, hEMA200_Context)
       double ema50Arr[], ema200Arr[];
       if(CopyBuffer(hEMA50_Context, 0, 0, 1, ema50Arr) < 1) return true;
       if(CopyBuffer(hEMA200_Context, 0, 0, 1, ema200Arr) < 1) return true;
       
       double ema50 = ema50Arr[0];
       double ema200 = ema200Arr[0];
       
       bool htfBullish = (ema50 > ema200);
       bool htfBearish = (ema50 < ema200);
       
       if(isBuy && !htfBullish) { if(InpDebugMode) Print("⛔ Context Veto: Buying against H1 Trend"); return false; }
       if(!isBuy && !htfBearish) { if(InpDebugMode) Print("⛔ Context Veto: Selling against H1 Trend"); return false; }
   }
   else
   {
       // Neutral/Chop (ADX 20-25). Use moderate filters.
       if(isBuy && position > 0.90) { if(InpDebugMode) Print("⛔ Context Veto: Buying Extreme High"); return false; }
       if(!isBuy && position < 0.10) { if(InpDebugMode) Print("⛔ Context Veto: Selling Extreme Low"); return false; }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| STATE PERSISTENCE HELPERS (Comment Hack)                         |
//+------------------------------------------------------------------+
// Expected Format: "Strategy_Side_Q0.95_TS:1" (Where 1 is Enum Integer)

ENUM_TRAIL_STATE GetTrailState(string comment)
{
   int start = StringFind(comment, "_TS:");
   if(start < 0) return TS_ENTRY_PROTECT; // Default initial state
   
   string stateStr = StringSubstr(comment, start + 4, 1); // Get single digit
   return (ENUM_TRAIL_STATE)StringToInteger(stateStr);
}

void SetTrailState(ulong ticket, string currentComment, ENUM_TRAIL_STATE newState)
{
   UpdateStateCache(ticket, (int)newState);
}

//+------------------------------------------------------------------+
//| STATE TRANSITION LOGIC (THE BRAIN)                               |
//+------------------------------------------------------------------+
ENUM_TRAIL_STATE UpdateTrailState(ulong ticket, ENUM_TRAIL_STATE currentState, double profitR, double adx, double atr, double riskPct)
{
   ENUM_TRAIL_STATE nextState = currentState;
   
   // PARAMETERS based on Profile
   double structureTrigger = 1.0; 
   double momentumTrigger  = 2.5; 
   double exhaustionTriggerRSI = 70; // (or 30 for sell)
   
   if(InpTrailProfile == TRAIL_SCALP)
   {
       structureTrigger = 1.0; // Was 0.8
       momentumTrigger = 2.0;  // Was 1.5
   }
   else if(InpTrailProfile == TRAIL_SWING)
   {
       structureTrigger = 2.0; // Was 1.5
       momentumTrigger = 5.0;  // Was 4.0
   }
   // Default (INTRADAY) Structure Trigger
   else 
   {
       structureTrigger = 1.5; // Was 1.0
   }

   switch(currentState)
   {
      case TS_ENTRY_PROTECT:
         // Transition to Structure Lock?
         if(profitR >= structureTrigger) nextState = TS_STRUCTURE_LOCK;
         break;
         
      case TS_STRUCTURE_LOCK:
         // Transition to Momentum?
         // If Profit is HUGE (> MomentumTrigger) OR Trend is super strong (ADX > 40)
         if(profitR >= momentumTrigger || adx > 40) nextState = TS_MOMENTUM_TRAIL;
         break;
         
      case TS_MOMENTUM_TRAIL:
         // Transition to Exhaustion?
         // If ADX drops below 20 (trend died)
         if(adx < 20) nextState = TS_EXHAUSTION_LOCK;
         break;
         
      case TS_EXHAUSTION_LOCK:
         // Terminal State (until session close logic)
         break;
   }
   
   return nextState;
}

//+------------------------------------------------------------------+
//| TRAILING EXECUTION (THE EXECUTOR)                                |
//+------------------------------------------------------------------+
double GetTrailingSL(ENUM_TRAIL_STATE state, bool isBuy, double open, double currentPrice, double sl, double tp, double atr)
{
   double newSL = sl;
   
   switch(state)
   {
      case TS_ENTRY_PROTECT:
      {
         // Soft BE+ logic: If > 0.6R, move to BE+Comm
         // Wait, state transition to Structure handles >1.0R.
         // Here we just ensure we don't lose full risk if we are up a bit?
         // Or just leave initial SL until Structure Lock? 
         // "Survival Mode". Let's do Soft BE at 0.5R for Scalp.
         // For Intraday/Swing, maybe just hold SL.
         
         double risk = MathAbs(open - sl);
         if(risk > 0)
         {
             double profitR = isBuy ? (currentPrice - open)/risk : (open - currentPrice)/risk;
             // HARDENED BE: Don't move to BE until we are well in profit (1.5R)
             // This prevents Gold volatility from wicking us out early.
             // Strategy: Trust validation. If it goes 1.5R, it's likely real.
             if(profitR >= 1.5) // Was 0.6 - TOO TIGHT for Gold
             {
                 double be = open + (isBuy ? risk*0.1 : -risk*0.1); 
                 newSL = isBuy ? MathMax(sl, be) : MathMin(sl, be);
             }
         }
         break;
      }
      
      case TS_STRUCTURE_LOCK:
      {
         // Trail behind Structure (Swing Lows)
         // Use our helper: GetLastStructureSL(isBuy)
         // But buffer it by ATR fraction based on profile
         double structureLevel = GetLastStructureSL(isBuy);
         double buffer = atr * 0.5; // Default buffer
         if(InpTrailProfile == TRAIL_SWING) buffer = atr * 1.5; // Was 0.8 -> Now 1.5 (Very Loose)
         if(InpTrailProfile == TRAIL_SCALP) buffer = atr * 0.5; // Was 0.2 -> Now 0.5
         
         if(isBuy) newSL = MathMax(sl, structureLevel - buffer);
         else      newSL = MathMin(sl, structureLevel + buffer);
         
         break;
      }
      
      case TS_MOMENTUM_TRAIL:
      {
         // Tight Trail on recent candles (EMA or ATR)
         // Let's use ATR trail: Price - 2*ATR (Adjustable)
         // WIDENED TRAILING: Give more room for 2.5R target
         double mult = 3.0; // Was 1.5 (Intraday/Swing) -> Now 3.0 for better breathing room
         if(InpTrailProfile == TRAIL_SCALP) mult = 2.0; // Was 1.0 -> Now 2.0 (Less choke)
         
         double trailLevel = isBuy ? (currentPrice - atr*mult) : (currentPrice + atr*mult);
         if(isBuy) newSL = MathMax(sl, trailLevel);
         else      newSL = MathMin(sl, trailLevel);
         break;
      }
      
      case TS_EXHAUSTION_LOCK:
      {
         // Tightest Lock - Candle High/Low
         // Or very tight ATR (0.5)
         // WIDENED LOCK: Prevention of premature exit
         // Was 0.5 ATR -> Now 1.5 ATR
         double trailLevel = isBuy ? (currentPrice - atr*1.5) : (currentPrice + atr*1.5);
         if(isBuy) newSL = MathMax(sl, trailLevel);
         else      newSL = MathMin(sl, trailLevel);
         break;
      }
      
      case TS_SESSION_EXIT:
         // Handled by Session Close logic (Hard Close) works too.
         // Or aggressive trail.
         break;
   }
   
   return newSL;
}

// Global Arrays for State Memory
ulong  g_TicketCache[];
int    g_StateCache[];
bool   g_PartialExecuted[];

void UpdateStateCache(ulong ticket, int state)
{
   int size = ArraySize(g_TicketCache);
   for(int i=0; i<size; i++)
   {
      if(g_TicketCache[i] == ticket)
      {
         g_StateCache[i] = state;
         return;
      }
   }
   // Add new
   ArrayResize(g_TicketCache, size+1);
   ArrayResize(g_StateCache, size+1);
   ArrayResize(g_PartialExecuted, size+1);
   g_TicketCache[size] = ticket;
   g_StateCache[size]  = state;
   g_PartialExecuted[size] = false; // Reset partial flag for new ticket
}

void SetPartialExecuted(ulong ticket, bool executed)
{
   int size = ArraySize(g_TicketCache);
   for(int i=0; i<size; i++)
   {
      if(g_TicketCache[i] == ticket) 
      {
          g_PartialExecuted[i] = executed;
          return;
      }
   }
}

bool WasPartialExecuted(ulong ticket)
{
   int size = ArraySize(g_TicketCache);
   for(int i=0; i<size; i++)
   {
      if(g_TicketCache[i] == ticket) return g_PartialExecuted[i];
   }
   return false;
}

int GetStateFromCache(ulong ticket)
{
   int size = ArraySize(g_TicketCache);
   for(int i=0; i<size; i++)
   {
      if(g_TicketCache[i] == ticket) return g_StateCache[i];
   }
   return (int)TS_ENTRY_PROTECT;
}

void RunFibonacciStrategy(ENUM_REGIME regime, double &ema20[], double &ema50[], double &ema200[], double &atr[], double &rsi[], double &adx[], double &stochK[], double &stochD[], double &macd[], double &macdSig[], double &vwap[])
{
   if(HasOpenTrade("Fib")) return;
   
   // Find Swing Points (20 candles)
   int lookback = 20;
   
   // MQL5 Highest/Lowest Implementation
   double highArr[], lowArr[];
   CopyHigh(_Symbol, PERIOD_CURRENT, 1, lookback, highArr);
   CopyLow(_Symbol, PERIOD_CURRENT, 1, lookback, lowArr);
   
   int highIdx = ArrayMaximum(highArr);
   int lowIdx = ArrayMinimum(lowArr);
   
   double swingHigh = highArr[highIdx];
   double swingLow  = lowArr[lowIdx];
   double range     = swingHigh - swingLow;
   
   if(range == 0) return;
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // --- BUY ZONE (Retracement in Uptrend) ---
   if(ema20[0] > ema50[0])
   {
      double fib50 = swingLow + (range * 0.50);
      double fib618 = swingLow + (range * 0.618);
      
      // Price is inside Golden Zone
      if(close >= fib50 && close <= fib618)
      {
         // RSI REMOVED: Fib relies on Wave Structure + Trend, not oversold.
         if(true) 
         {
             // CONFLUENCE CHECK
             
              double score = CalculateConfluenceScore("Fib", true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
              
              if(InpUse_Confluence_Filter)
              {
                  double minScore = GetAdaptiveMinScore("Fib");
                  if(score < minScore)
                  {
                      if(InpDebugMode) Print("⚠️ Fib Buy Skipped: Score ", score, " < ", minScore);
                      return;
                  }
              }
             
             // DYNAMIC PARAMS
             double quality = GetQualityIndex(score, "Fib");
             double riskPct = GetDynamicRisk(quality, regime);
             // Fib Strategy often has FIXED target (Recent High). 
             // We can respect that or use RR. 
             // Logic: tp = swingHigh. 
             // SL = swingLow - atr*0.5.
             // If we force Dynamic RR, we might overshoot swingHigh. 
             // Better to stick to Structure Target for Fib, BUT use dynamic Risk.
             
            double sl = swingLow - (atr[0] * 0.5); // Stop below swing low
            double tp = swingHigh; // Target recent high
            
            string comment = StringFormat("Fib_Buy_Q%.2f", quality);
            
            if(InpDebugMode) Print("📐 Fib Golden Zone BUY @ ", close);
            ExecuteTrade(ORDER_TYPE_BUY, sl, tp, comment, riskPct);
         }
      }
   }
   
   // --- SELL ZONE ---
   else if(ema20[0] < ema50[0])
   {
      double fib50 = swingHigh - (range * 0.50);
      double fib618 = swingHigh - (range * 0.618); 
      
      // If Price is between 50% and 61.8% (Golden Zone)
      if(close >= fib618 && close <= fib50)
      {
         // RSI REMOVED: Fib relies on Wave Structure + Trend.
         if(true)
         {
             // CONFLUENCE CHECK
             
              double score = CalculateConfluenceScore("Fib", false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
              
              if(InpUse_Confluence_Filter)
              {
                  double minScore = GetAdaptiveMinScore("Fib");
                  if(score < minScore)
                  {
                      if(InpDebugMode) Print("⚠️ Fib Sell Skipped: Score ", score, " < ", minScore);
                      return;
                  }
              }
             
             // DYNAMIC PARAMS
             double quality = GetQualityIndex(score, "Fib");
             double riskPct = GetDynamicRisk(quality, regime);

            double sl = swingHigh + (atr[0] * 0.5);
            double tp = swingLow;
            
            string comment = StringFormat("Fib_Sell_Q%.2f", quality);
            
            if(InpDebugMode) Print("📐 Fib Golden Zone SELL @ ", close);
            ExecuteTrade(ORDER_TYPE_SELL, sl, tp, comment, riskPct);
          }
       }
    }
}
