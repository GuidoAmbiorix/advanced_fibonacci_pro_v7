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

//+------------------------------------------------------------------+
//| INPUTS & CONFIGURATION                                           |
//+------------------------------------------------------------------+
input group "========== STRATEGY TOGGLES =========="
input bool InpEnable_Institutional = true;    // Institutional Sweep (Liquidity+CVD)
input bool InpEnable_VWAP_Scalp    = false;   // VWAP Scalping (Mean Reversion) - DISABLED FOR SAFETY
input bool InpEnable_Fibonacci     = true;    // Fibonacci Golden Zone
input bool InpEnable_Stochastic    = true;    // Stochastic Momentum Burst
input bool InpEnable_Breakout      = false;   // Breakout Momentum (Lower WinRate)
input int  InpSwap_Lookback        = 30;      // Lookback for Swings
// input int  InpMax_Spread_Points    = 50;      // Max Spread removed
input ENUM_TIMEFRAMES InpTrend_Timeframe = PERIOD_H4; // Trend Confirmation TF

input group "========== CONFLUENCE FILTER =========="
input bool InpUse_Confluence_Filter  = true;  // Enable Confluence Scoring
input double InpMin_Confluence_Score = 5.5;   // Min Score to Trade (0-10)

input group "========== RISK MANAGEMENT =========="
input double InpMax_Drawdown_Percent = 6.0;   // Max Total Drawdown % (Funding Rule)
input double InpDaily_Loss_Percent   = 2.5;   // Max Daily Loss % (Funding Rule)
input int    InpMax_Daily_Trades     = 3;     // Max Trades Per Day (0 = Disable)
input double InpTarget_Daily_Profit  = 1.5;   // Daily Profit Target % (0 = Disable)
input double InpRisk_Per_Trade       = 0.5;   // Base Risk Per Trade %
input double InpRisk_Reward_Ratio    = 2.0;   // Base Risk:Reward Ratio
input int    InpCooldownMinutes      = 45;    // Cooldown Minutes after Loss Streak

input group "========== TRAILING STOP TIERS =========="
input double InpTier1_Profit_R = 1.0;   // Tier 1: Profit (R)
input double InpTier1_Lock_R   = 0.25;  // Tier 1: Lock (R)
input double InpTier2_Profit_R = 2.0;   // Tier 2: Profit (R)
input double InpTier2_Lock_R   = 1.3;   // Tier 2: Lock (R)
input double InpTier3_Profit_R = 3.5;   // Tier 3: Profit (R)
input double InpTier3_Lock_R   = 2.8;   // Tier 3: Lock (R)

//+------------------------------------------------------------------+
//| PARTIAL TP INPUTS                                                |
//+------------------------------------------------------------------+
input bool   InpEnablePartialTP      = true;   // Master switch for Partial TP
input bool   InpPartialTP_VWAP       = true;   // Use VWAP level as trigger
input bool   InpPartialTP_Liquidity  = true;   // Use liquidity sweep trigger
input bool   InpPartialTP_Time       = true;   // Time‑based trigger (minutes in trade)
input bool   InpPartialTP_Fib        = true;   // Fibonacci zone trigger
input double InpPartialTP_PercentVWAP   = 0.30; // Close 30% on VWAP trigger
input double InpPartialTP_PercentLiquidity = 0.20; // Close 20% on liquidity trigger
input double InpPartialTP_PercentTime   = 0.15; // Close 15% on time trigger
input double InpPartialTP_PercentFib    = 0.25; // Close 25% on Fib trigger
input int   InpPartialTP_TimeMinutes   = 30;   // Minutes after entry before time trigger fires

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;            // RSI Period
input int InpADX_Period      = 14;            // ADX Period
input int InpADX_Threshold   = 22;            // Trend Threshold (25+)
input int InpATR_Period      = 14;            // ATR Period
input int InpStoch_K         = 14;            // Stochastic %K
input int InpStoch_D         = 3;             // Stochastic %D
input int InpVariable_MA     = 20;            // Variable MA (VWAP Proxy)

input group "========== KILLZONES (EST TIME) =========="
input int    InpServerTimeOffset        = 2;     // Server Time Offset from EST (e.g. +2 for UTC+2)
input bool   InpUse_KillZones           = true;  // Restrict to Kill Zones?
input bool   InpUse_London_Killzone     = true;  // London Killzone (02:00-05:00 EST)
input string InpLondon_Start            = "02:00";
input string InpLondon_End              = "05:00";
input bool   InpUse_NY_Killzone         = true;  // NY Killzone (08:00-11:00 EST)
input string InpNY_Start                = "08:00";
input string InpNY_End                  = "11:00";
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
   hVWAP = iMA(_Symbol, PERIOD_CURRENT, InpVariable_MA, 0, MODE_SMA, PRICE_TYPICAL); // SMA of Typical Price as VWAP Proxy
   
   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE || 
      hStoch == INVALID_HANDLE || hMACD == INVALID_HANDLE || hEMA20 == INVALID_HANDLE || hVWAP == INVALID_HANDLE) 
   {
      Print("Error creating indicators!");
      return INIT_FAILED;
   }

   // Initialize Account Tracking
   AccountBalanceStartDay = accountInfo.Balance();
   LastDayChecked = iTime(_Symbol, PERIOD_D1, 0);

   Print("Adaptive Multi-Strategy EA Initialized");
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
   IndicatorRelease(hVWAP);
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Manage Open Trades (Trailing Stop) - Always run management!
   ManageTrade();
   
   // 2. Session Close Check
   CheckSessionClose();

   // 3. Check Funding Rules (Daily Loss, Max DD, Daily Limits)
   if(!CheckFundingRules()) return;
   
   // 4. Data Gathering
   double rsi[], adx[], atr[], stochK[], stochD[], macd[], macdSig[], ema20[], ema50[], ema200[], vwap[];
   if(!GetIndicators(rsi, adx, atr, stochK, stochD, macd, macdSig, ema20, ema50, ema200, vwap)) return;
   
   // 3. Detect Market Regime
   ENUM_REGIME regime = DetectRegime(adx[0], atr[0]);
   
   // 4. Update Smart State (e.g., Daily High/Low for CVD)
   // ...
   
   // 5. Execute Strategies
   if(InpEnable_Institutional) RunInstitutionalStrategy(regime, rsi, atr, ema20, ema50, ema200, adx, stochK, stochD, macd, macdSig, vwap);
   if(InpEnable_VWAP_Scalp)    RunVWAPStrategy(regime, vwap, rsi, ema20, ema50, ema200, atr, adx, stochK, stochD, macd, macdSig);
   if(InpEnable_Fibonacci)     RunFibonacciStrategy(regime, ema20, ema50, ema200, atr, rsi, adx, stochK, stochD, macd, macdSig, vwap);
   if(InpEnable_Stochastic)    RunStochasticStrategy(regime, stochK, stochD, ema20, ema50, ema200, atr, adx, rsi, macd, macdSig, vwap);
   
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
ENUM_REGIME DetectRegime(double adxVal, double atrVal)
{
   // Enhanced Regime Detection
   // 1. Trend Strength (ADX)
   bool isTrending = (adxVal > InpADX_Threshold);
   
   // 2. Volatility (ATR vs Average ATR) - Simplifying for now without history array access
   // Ideally we maintain a running average or use another indicator handle
   
   if(isTrending) return REGIME_TRENDING;
   
   // If not trending, check if it's dead or chopping
   // For now, default to Ranging
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
double CalculateConfluenceScore(bool isBuy, ENUM_REGIME regime, double &rsi[], double &stochK[], double &stochD[], double &macd[], double &macdSig[], double &ema20[], double &ema50[], double &ema200[], double &adx[], double &vwap[])
{
   double score = 0.0;
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // 1. HTF Trend (Base 2.5) - Weighted by Regime
   // EMA50 > EMA200
   double trendWeight = 2.5 * GetRegimeMultiplier(regime, "TREND");
   if(isBuy && ema50[0] > ema200[0]) score += trendWeight;
   if(!isBuy && ema50[0] < ema200[0]) score += trendWeight;
   
   // 2. Killzone Active (Base 2.0)
   if(IsKillZone()) score += 2.0;
   
   // 3. Setup Core / Local Momentum (Base 3.0) 
   // We assume the caller already validated the Specific Trigger (e.g., Sweep, Cross).
   // Here we rate the "Context" of that trigger:
   // Local Trend Alignment: Price vs EMA20
   double coreWeight = 3.0 * GetRegimeMultiplier(regime, "TREND");
   if(isBuy && close > ema20[0]) score += 1.5; // Split core weight
   if(!isBuy && close < ema20[0]) score += 1.5;
   
   // 4. Momentum (MACD+RSI) (Base 1.5)
   double momWeight = 1.5;
   bool macdAligned = (isBuy && macd[0] > macdSig[0]) || (!isBuy && macd[0] < macdSig[0]);
   bool rsiAligned  = (isBuy && rsi[0] > 50) || (!isBuy && rsi[0] < 50);
   
   if(macdAligned && rsiAligned) score += momWeight;
   else if(macdAligned || rsiAligned) score += (momWeight * 0.5);
   
   // 5. VWAP (Base 1.0) - Weighted by Mean Reversion Regime
   // If Ranging, VWAP signals are strong mean reversion targets or anchors.
   // If Trending, VWAP is dynamic support.
   double vwapWeight = 1.0 * GetRegimeMultiplier(regime, "MEAN"); 
   // Note: User logic says 'Mean Reversion' gets more weight in Range.
   
   // Logic: Position relative to VWAP
   if(isBuy && close > vwap[0]) score += vwapWeight; // Bullish context
   if(!isBuy && close < vwap[0]) score += vwapWeight; // Bearish context
   
   // 6. ADX Quality (Base 1.0)
   if(adx[0] > InpADX_Threshold) score += 1.0;
   
   // 7. PENALTIES (Conflicts)
   // RSI Extreme Conflict
   if(isBuy && rsi[0] > 70) score -= 2.0;       // Buying Top?
   if(!isBuy && rsi[0] < 30) score -= 2.0;      // Selling Bottom?
   
   // Regime Conflict (e.g. Buying High in Range)
   if(regime == REGIME_RANGING)
   {
       // If Buying but Price > VWAP (Expensive in Range), penalize?
       // This depends on strategy type. For now follow general guidance:
       // "if Buying and Price > VWAP and Range -> -1.5"
       if(isBuy && close > vwap[0]) score -= 1.5;
       if(!isBuy && close < vwap[0]) score -= 1.5;
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
      // LOGIC FIX:
      // Only trigger a NEW cooldown if the latest loss happened AFTER the previous cooldown was set.
      // If we haven't traded since the last cooldown, we shouldn't be penalized again for the same old history.
      
      datetime lastTradeTime = GetLastTradeTime();
      if(lastTradeTime < EngineCooldownUntil)
      {
         // We have already served the time for these losses.
         // Allow trading to resume to try and break the streak.
         return true;
      }
      
      EngineCooldownUntil = now + (InpCooldownMinutes * 60);
      if(InpDebugMode)
         Print("🔥 Cooldown TRIGGERED for ", InpCooldownMinutes, " minutes (loss streak)");
      return false;
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
   
   double volume = CalculateLotSizeWithRisk(slDist, effectiveRisk);
   
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
      
      // Confirmation 2: RSI Oversold (Cheap)
      bool rsiOk = rsi[0] < 45; // Flexible oversold
      
      if(trendOk && rsiOk)
      {
         // CONFLUENCE CHECK
         double score = 0.0;
         double minScore = GetAdaptiveMinScore("Inst");
         
         if(InpUse_Confluence_Filter)
         {
             score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
             if(score < minScore)
             {
                 if(InpDebugMode) Print("⚠️ Inst. Buy Skipped: Score ", score, " < ", minScore);
                 return;
             }
         }
         else
         {
             score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
         }

         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "Inst");
         double riskPct = GetDynamicRisk(quality, regime);
         double dynRR   = GetDynamicRR(quality, regime);

         double sl = swingLow - (atr[0] * 0.5); // Tight SL behind the sweep
         double tp = close + (close - sl) * dynRR;
         
         string comment = StringFormat("Inst_Buy_Q%.2f", quality);
         
         if(InpDebugMode) Print("⚡ Institutional BUY: Sweep Low ", swingLow, " SL=", sl);
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, comment, riskPct);
      }
   }
   
   // --- BEARISH SWEEP ---
   // High sweeps SwingHigh, but Close is below SwingHigh
   else if(high > swingHigh && close < swingHigh)
   {
      // Confirmation 1: Trend
      bool trendOk = ema50[0] < ema200[0];
      
      // Confirmation 2: RSI Overbought (Expensive)
      bool rsiOk = rsi[0] > 55;
      
      if(trendOk && rsiOk)
      {
         // CONFLUENCE CHECK
         double score = 0.0;
         double minScore = GetAdaptiveMinScore("Inst");
         
         if(InpUse_Confluence_Filter)
         {
             score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
             if(score < minScore)
             {
                 if(InpDebugMode) Print("⚠️ Inst. Sell Skipped: Score ", score, " < ", minScore);
                 return;
             }
         }
         else
         {
             score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
         }
         
         // DYNAMIC PARAMS
         double quality = GetQualityIndex(score, "Inst");
         double riskPct = GetDynamicRisk(quality, regime);
         double dynRR   = GetDynamicRR(quality, regime);

         double sl = swingHigh + (atr[0] * 0.5);
         double tp = close - (sl - close) * dynRR;
         
         string comment = StringFormat("Inst_Sell_Q%.2f", quality);
         
         if(InpDebugMode) Print("⚡ Institutional SELL: Sweep High ", swingHigh, " SL=", sl);
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, comment, riskPct);
      }
   }
}

// Kill Zone Logic (London 02-05, NY 08-11, Close 10-12 EST)
bool IsKillZone()
{
   // Current Server Time
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   // Convert Server Time to EST Estimate (Simple Hour Offset)
   // If Server is UTC+2 and EST is UTC-5, Offset should be -7? 
   // User Input InpServerTimeOffset is "Server Offset from EST".
   // e.g. If Server=14:00 and EST=07:00. Server is +7 hours ahead of EST.
   // So EST_Time = Server_Time - Offset.
   
   int estHour = dt.hour - InpServerTimeOffset;
   if(estHour < 0) estHour += 24;
   if(estHour >= 24) estHour -= 24;
   
   // Create a string "HH:MM" for comparison
   string currentEST = StringFormat("%02d:%02d", estHour, dt.min);
   
   bool inLondon = false;
   bool inNY = false;
   bool inLondonClose = false;
   
   // London (02:00 - 05:00)
   if(InpUse_London_Killzone) {
      if(CheckTimeRange(currentEST, InpLondon_Start, InpLondon_End)) inLondon = true;
   }
   
   // NY (08:00 - 11:00)
   if(InpUse_NY_Killzone) {
      if(CheckTimeRange(currentEST, InpNY_Start, InpNY_End)) inNY = true;
   }
   
   // London Close (10:00 - 12:00)
   if(InpUse_LondonClose_Killzone) {
      if(CheckTimeRange(currentEST, InpLondonClose_Start, InpLondonClose_End)) inLondonClose = true;
   }
   
   return (inLondon || inNY || inLondonClose);
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
   // Iterate ALL open positions (Multi-Strategy Aware)
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      // Parameters
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      string comment = PositionGetString(POSITION_COMMENT);
      
      double risk = MathAbs(open - sl);
      if(risk == 0) continue; // Safety
      
      double profitPoints = isBuy ? (currentPrice - open) : (open - currentPrice);
      double profitR = profitPoints / risk;
   // ---- Partial TP Evaluation ----
   double partialFrac = ComputePartialTP(isBuy, quality, r, profitR, ticket, open, currentPrice, comment);
   if(partialFrac > 0)
   {
      double vol = PositionGetDouble(POSITION_VOLUME);
      double closeVol = MathMax(vol * partialFrac, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      // Close part of the position
      if(trade.PositionClosePartial(ticket, closeVol))
      {
         if(InpDebugMode) Print("🪙 Partial TP closed ", DoubleToString(closeVol,2), " lots (", DoubleToString(partialFrac*100,1), "% of position)");
      }
   }
      
      // Context
      double quality = ParseQualityFromComment(comment);
      double boost = GetTrailBoost(quality);
      
      // Helper Regime (Local Recalculation or use Global if updated)
      // We can check ADX locally for boost
      double adxArr[], atrArr[]; // temp
      if(CopyBuffer(hADX, 0, 0, 1, adxArr) > 0 && CopyBuffer(hATR, 0, 0, 1, atrArr) > 0)
      {
          ENUM_REGIME r = DetectRegime(adxArr[0], atrArr[0]);
          if(r == REGIME_RANGING) boost *= 0.85; // Tighten
          if(r == REGIME_TRENDING) boost *= 1.15; // Loosen
      }
      
      double newSL = sl;
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      // 🔹 Phase 1 – BE+ (Bank Scalp)
      if(profitR >= 1.0)
      {
         double beLevel = open + (isBuy ? risk*0.15 : -risk*0.15);
         if(isBuy) newSL = MathMax(newSL, beLevel);
         else      newSL = MathMin(newSL, beLevel);
      }

      // 🔹 Phase 2 – Structure Lock (Institutional)
      if(profitR >= 2.0)
      {
         double structure = GetLastStructureSL(isBuy);
         double atrBuf = GetATRBuffer() * boost;

         if(isBuy) newSL = MathMax(newSL, structure - atrBuf);
         else      newSL = MathMin(newSL, structure + atrBuf);
      }

      // 🔹 Phase 3 – Run Mode (Protect Runners)
      if(profitR >= 3.0)
      {
         // Trail closer: Price - 1.2R (Adjusted by Boost)
         double trailDist = risk * 1.2 * boost;
         if(isBuy) newSL = MathMax(newSL, currentPrice - trailDist);
         else      newSL = MathMin(newSL, currentPrice + trailDist);
      }
      
      // 🔄 EXECUTE UPDATE
      // Only modify if significant change (> 2 points) to avoid spam
      if(MathAbs(newSL - sl) > 2 * point)
      {
         bool modify = false;
         if(isBuy && newSL > sl) modify = true;
         if(!isBuy && (sl == 0 || newSL < sl)) modify = true;
         
         if(modify)
         {
             trade.PositionModify(_Symbol, newSL, tp);
             if(InpDebugMode) 
               Print("🦅 GOD MODE TSL (", isBuy?"BUY":"SELL", "): ", DoubleToString(profitR,1), "R -> Locked @ ", newSL);
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
          double score = 0.0;
          double minScore = GetAdaptiveMinScore("VWAP");
          
          if(InpUse_Confluence_Filter)
          {
              score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ VWAP Buy Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }
          else
          {
              score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
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
          double score = 0.0;
          double minScore = GetAdaptiveMinScore("VWAP");
          
          if(InpUse_Confluence_Filter)
          {
              score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ VWAP Sell Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }
          else
          {
              score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
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
          double score = 0.0;
          double minScore = GetAdaptiveMinScore("Stoch");
          
          if(InpUse_Confluence_Filter)
          {
              score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ Stoch Buy Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }
          else
          {
              score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
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
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, comment, riskPct);
      }
   }
   
   // --- SELL ZONE ---
   else if(downtrend && stochK[1] > 75 && stochD[1] > 75)
   {
      if(stochK[1] > stochD[1] && stochK[0] < stochD[0])
      {
          // CONFLUENCE CHECK
          double score = 0.0;
          double minScore = GetAdaptiveMinScore("Stoch");
          
          if(InpUse_Confluence_Filter)
          {
              score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
              if(score < minScore)
              {
                  if(InpDebugMode) Print("⚠️ Stoch Sell Skipped: Score ", score, " < ", minScore);
                  return;
              }
          }
          else
          {
              score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
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
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, comment, riskPct);
      }
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 3: FIBONACCI GOLDEN ZONE                                |
//+------------------------------------------------------------------+
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
         if(rsi[0] < 45) // Oversold confirmation in uptrend
         {
             // CONFLUENCE CHECK
             double score = 0.0;
             double minScore = GetAdaptiveMinScore("Fib");
             
             if(InpUse_Confluence_Filter)
             {
                 score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
                 if(score < minScore)
                 {
                     if(InpDebugMode) Print("⚠️ Fib Buy Skipped: Score ", score, " < ", minScore);
                     return;
                 }
             }
             else
             {
                 score = CalculateConfluenceScore(true, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
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
         if(rsi[0] > 55)
         {
             // CONFLUENCE CHECK
             double score = 0.0;
             double minScore = GetAdaptiveMinScore("Fib");
             
             if(InpUse_Confluence_Filter)
             {
                 score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
                 if(score < minScore)
                 {
                     if(InpDebugMode) Print("⚠️ Fib Sell Skipped: Score ", score, " < ", minScore);
                     return;
                 }
             }
             else
             {
                 score = CalculateConfluenceScore(false, regime, rsi, stochK, stochD, macd, macdSig, ema20, ema50, ema200, adx, vwap);
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
