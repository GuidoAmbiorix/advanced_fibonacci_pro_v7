//+------------------------------------------------------------------+
//|                                          Portfolio_Governor.mq5  |
//|          🧠 CENTRAL BRAIN - Multi-Symbol Risk Controller         |
//|             Manages: DD, Exposure, PF, Correlation Groups        |
//+------------------------------------------------------------------+
#property copyright "Portfolio Governor"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property description "🧠 Portfolio Governor: Central Risk Brain"
#property description "Run on ONE chart only. Controls all Symbol Engines."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Include\PortfolioGlobals.mqh"
#include "Include\GovernorAllocator.mqh"
#include "Include\PortfolioMath.mqh"
#include "Include\Engines\SymbolEngineWrapper.mqh"
#include "Include\SymbolDatabase.mqh"

CGovernorAllocator allocator;
CTrade g_trade;
CSymbolEngineWrapper *g_engines[]; // Array of pointers to engine instances

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "═══════ PORTFOLIO LIMITS ═══════"
input double InpMaxPortfolioRisk = 2.0;        // Max Total Portfolio Risk (%)
input double InpMaxSymbolRisk = 0.6;           // Max Risk Per Symbol (%)
input double InpMaxGroupRisk = 1.0;            // Max Risk Per Correlation Group (%)

input group "═══════ DRAWDOWN GOVERNOR ═══════"
input double InpDD_Normal = 3.0;               // DD Level: Normal Trading (%)
input double InpDD_Reduced = 5.0;              // DD Level: Reduced Risk (%)
input double InpDD_Pause = 8.0;                // DD Level: Pause Trading (%)
input double InpDD_ReducedMult = 0.5;          // Risk Multiplier when DD > Normal

input group "═══════ ROLLING PF GOVERNOR ═══════"
input int    InpRollingTrades = 30;            // Rolling Window (trades)
input double InpPF_Normal = 1.8;               // PF Level: Normal Trading
input double InpPF_Reduced = 1.2;              // PF Level: Reduced Risk
input double InpPF_Pause = 1.0;                // PF Level: Pause Trading
input double InpPF_ReducedMult = 0.7;          // Risk Mult when PF < Normal

input group "═══════ DAILY/WEEKLY LIMITS ═══════"
input double InpDailyMaxDD = 3.0;              // Daily Max Drawdown (%)
input double InpWeeklyMaxDD = 6.0;             // Weekly Max Drawdown (%)
input double InpMonthlyMaxDD = 10.0;           // Monthly Max Drawdown (%)

input group "═══════ CORRELATION GUARD ═══════"
input bool   InpUseCorrelationGuard = true;    // Enable Correlation Guard
input double InpHighCorrelation = 0.70;        // High Correlation Threshold
input double InpCorrelationReduction = 0.50;   // Size Reduction Factor

input group "═══════ MAGIC NUMBER RANGE ═══════"
input int    InpMagicBase = 100000;            // Magic Number Base
input int    InpMagicRange = 999;              // Magic Number Range (Base to Base+Range)

input group "═══════ TRADE MANAGEMENT ═══════"
input bool   InpUseTrailing = true;            // Enable Trailing Stop
input double InpTrailStartR = 2.0;             // Trail Start (R-Multiple)
input double InpTrailATR = 1.5;                // Trail Distance (ATR Multiplier)
input double InpBE_TriggerR = 1.2;             // Break-Even Trigger (R-Multiple)
input bool   InpUsePartials = true;            // Enable Partial Closes
input double InpPartialR = 1.5;                // Partial Close Trigger (R)
input double InpPartialPct = 50.0;             // Partial Close %

input group "═══════ TRADING HOURS ═══════"
input string InpStartTime = "00:00";           // Start Time (HH:MM)
input string InpEndTime   = "23:59";           // End Time (HH:MM)
input bool   InpUseTimer  = false;             // Use Trading Hours

input group "═══════ EXECUTION SETTINGS ═══════"
input ENUM_ORDER_TYPE_FILLING InpFillingType = ORDER_FILLING_FOK; // Order Filling Type
input int    InpDeviation = 10;                // Max Deviation (Points)
input int    InpMaxSpread = 50;                // Max Spread (Points)
input string InpTradeComment = "Gov_SMC";      // Order Comment

input group "═══════ UPDATE FREQUENCY ═══════"
input int    InpUpdateSeconds = 5;             // Update Interval (seconds)

input group "═══════ STRATEGY SETTINGS ═══════"
input int    InpStrat_RSI = 14;                // RSI Period
input int    InpStrat_EMA = 200;               // Trend EMA Period
input int    InpStrat_SMCLookback = 20;        // SMC Swing Lookback
input double InpStrat_Impulse = 2.0;           // SMC Impulse Strength (ATR)
input bool   InpStrat_UseKillzones = true;     // Use Killzones (LDN/NY)

input group "═══════ GOD-LEVEL SETTINGS ═══════"
input int    InpCorrLookback = 100;            // Correlation Lookback (Bars)
input int    InpVaRLookback = 252;             // VaR Lookback (Days)
input double InpMaxVaR = 2.0;                  // Max Portfolio VaR (95%)
input int    InpHeavyUpdateMinutes = 60;       // Heavy Calculation Interval (min)
input bool   InpUseRegimeSwitch = true;        // Enable Regime-Based Limits


//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CPositionInfo position;
CAccountInfo  account;

double g_peakEquity = 0;
datetime g_lastUpdate = 0;

// Trade history for rolling PF
double g_tradeResults[];  // Store last N trade results
int g_tradeCount = 0;

// Daily/Weekly/Monthly tracking
double g_dailyStartEquity = 0;
double g_weeklyStartEquity = 0;
double g_monthlyStartEquity = 0;
datetime g_lastDayCheck = 0;
datetime g_lastWeekCheck = 0;
datetime g_lastMonthCheck = 0;
bool g_dailyLimitHit = false;
bool g_weeklyLimitHit = false;
bool g_monthlyLimitHit = false;

// Correlation matrix (pre-defined known correlations)
struct SymbolCorrelation
{
   string symbol1;
   string symbol2;
   double correlation;
};

// Dynamic Correlation Structure
struct DynamicCorrelation {
   string symbol1;
   string symbol2;
   double correlation;
   double rollingBeta;
   datetime lastUpdate;
};

// Regime Risk Profile
struct RegimeRiskProfile {
   MARKET_REGIME regime;
   double maxPortfolioRisk;
   double maxSymbolRisk;
   double maxGroupRisk;
   double correlationThreshold;
};

// Heat Map Structure
struct RiskHeatMap {
   string symbol;
   double currentRisk;
   double avgDailyRisk;
   double maxDailyRisk;
   int consecutiveDays;
   double heatScore;  // 0-100
};

// Global Arrays
DynamicCorrelation g_liveCorrelations[];
RegimeRiskProfile g_regimeProfiles[];
RiskHeatMap g_heatMap[];
string g_activeSymbols[]; // Populated from Market Watch

// Pre-defined regime profiles
void InitRegimeProfiles() {
   ArrayResize(g_regimeProfiles, 4);
   
   // REGIME_TREND: Aggressive
   g_regimeProfiles[0].regime = REGIME_TREND;
   g_regimeProfiles[0].maxPortfolioRisk = 3.0;
   g_regimeProfiles[0].maxSymbolRisk = 0.8;
   g_regimeProfiles[0].maxGroupRisk = 1.5;
   g_regimeProfiles[0].correlationThreshold = 0.80;
   
   // REGIME_RANGE: Conservative
   g_regimeProfiles[1].regime = REGIME_RANGE;
   g_regimeProfiles[1].maxPortfolioRisk = 1.5;
   g_regimeProfiles[1].maxSymbolRisk = 0.4;
   g_regimeProfiles[1].maxGroupRisk = 0.8;
   g_regimeProfiles[1].correlationThreshold = 0.60;
   
   // REGIME_VOLATILE: Defensive
   g_regimeProfiles[2].regime = REGIME_VOLATILE;
   g_regimeProfiles[2].maxPortfolioRisk = 1.0;
   g_regimeProfiles[2].maxSymbolRisk = 0.3;
   g_regimeProfiles[2].maxGroupRisk = 0.6;
   g_regimeProfiles[2].correlationThreshold = 0.50;
   
   // REGIME_BREAKOUT: Moderate
   g_regimeProfiles[3].regime = REGIME_BREAKOUT;
   g_regimeProfiles[3].maxPortfolioRisk = 2.5;
   g_regimeProfiles[3].maxSymbolRisk = 0.7;
   g_regimeProfiles[3].maxGroupRisk = 1.2;
   g_regimeProfiles[3].correlationThreshold = 0.70;
}

SymbolCorrelation g_correlations[] = {
   {"EURUSD", "GBPUSD", 0.85},
   {"EURUSD", "USDCHF", -0.90},
   {"GBPUSD", "EURGBP", -0.75},
   {"AUDUSD", "NZDUSD", 0.90},
   {"USDJPY", "EURJPY", 0.80},
   {"XAUUSD", "EURUSD", 0.60},
   {"XAUUSD", "USDJPY", -0.50},
   {"XAUUSD", "DXY", -0.80}
};

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // 0. Time Filter Check
   if(InpUseTimer && !CheckTime(InpStartTime, InpEndTime))
   {
      Comment("💤 Outside Trading Hours");
      return(INIT_FAILED); // Return INIT_FAILED to prevent EA from running
   }

   // 1. Initialize & Auto-Add Symbols (Dynamic Universe)
   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 1);
   GlobalVariableSet(GV_TRADING_ENABLED, 1);
   GlobalVariableSet(GV_RISK_MULTIPLIER, 1.0);
   GlobalVariableSet(GV_TOTAL_EXPOSURE, 0);
   GlobalVariableSet(GV_CURRENT_DD, 0);
   GlobalVariableSet(GV_ROLLING_PF, 2.0);
   GlobalVariableSet(GV_PEAK_EQUITY, account.Equity());
   GlobalVariableSet(GV_LAST_UPDATE, (double)TimeCurrent());
   
   // Initialize group risks
   GlobalVariableSet(GV_GROUP_USD_RISK, 0);
   GlobalVariableSet(GV_GROUP_JPY_RISK, 0);
   GlobalVariableSet(GV_GROUP_GBP_RISK, 0);
   GlobalVariableSet(GV_GROUP_METALS_RISK, 0);
   GlobalVariableSet(GV_GROUP_INDICES_RISK, 0);
   
   g_peakEquity = account.Equity();
   ArrayResize(g_tradeResults, InpRollingTrades);
   ArrayInitialize(g_tradeResults, 0);

   g_dailyStartEquity = account.Equity();
   g_weeklyStartEquity = account.Equity();
   g_monthlyStartEquity = account.Equity();
   g_lastDayCheck = TimeCurrent();
   g_lastWeekCheck = TimeCurrent();
   g_lastMonthCheck = TimeCurrent();

   // Set initial GV values for daily/weekly
   GlobalVariableSet(GV_DAILY_DD, 0);
   GlobalVariableSet(GV_WEEKLY_DD, 0);
   GlobalVariableSet(GV_DAILY_START_EQUITY, g_dailyStartEquity);
   GlobalVariableSet(GV_WEEKLY_START_EQUITY, g_weeklyStartEquity);
   
   // Initialize Signals
   // 2. Initialize Engines for Active Symbols
   int totalSymbols = ArraySize(g_activeSymbols);
   ArrayResize(g_engines, totalSymbols);
   
   // Configure Common Params using DEFAULTS
   SymbolEngineParams params = CSymbolEngineWrapper::GetDefaults(); // Load Institutional Defaults
   
   // OVERRIDE WITH GOVERNOR INPUTS (High-Level Control)
   params.Direction = 0; // Both
   
   // Strategy Overrides
   params.RSI_Period = InpStrat_RSI;
   params.EMA_Period = InpStrat_EMA;
   params.SMC_SwingLookback = InpStrat_SMCLookback;
   params.SMC_MinImpulseATR = InpStrat_Impulse;
   params.UseKillzoneFilter = InpStrat_UseKillzones;
   
   // Risk Overrides
   params.RiskBase = InpMaxSymbolRisk;
   params.MaxRisk = InpMaxPortfolioRisk; // Governor limits overall
   // NOTE: We could map InpUseTrailing -> params.TrailingMode here if desired
   // For now, we use the Defaults (Adaptive) which is superior.
   
   // Execution Overrides
   params.FillingType = InpFillingType;
   params.Deviation = InpDeviation;
   params.TradeComment = InpTradeComment;
   
   for(int i=0; i<totalSymbols; i++)
   {
      g_engines[i] = new CSymbolEngineWrapper();
      params.MagicNumber = InpMagicBase + i; // Unique magic per symbol
      
      if(!g_engines[i].Init(g_activeSymbols[i], params))
      {
         Print("Failed to init engine for ", g_activeSymbols[i]);
      }
      else
      {
         Print("Initialized Engine for: ", g_activeSymbols[i]);
      }
   }
   
   g_trade.SetExpertMagicNumber(InpMagicBase);
   g_trade.SetMarginMode();
   g_trade.SetTypeFilling(InpFillingType);
   g_trade.SetDeviationInPoints(InpDeviation);
   
   // Initialize God-Level Features
   InitRegimeProfiles();
   EnsureMarketWatch();    // <--- Auto-add top 50 pairs
   UpdateActiveUniverse(); // First run to populate universe
   
   // Start Timer for heavy calculations
   EventSetTimer(60); // Check every minute, but internal logic will throttle to InpHeavyUpdateMinutes

   Print("===============================================================");
   Print("  PORTFOLIO GOVERNOR v2.1 GOD-LEVEL ACTIVATED");
   Print("===============================================================");
   Print("  Max Portfolio Risk: ", InpMaxPortfolioRisk, "% (Baseline)");
   Print("  Regime Switch: ", InpUseRegimeSwitch ? "ON" : "OFF");
   Print("  Correlation Lookback: ", InpCorrLookback);
   Print("  VaR Lookback: ", InpVaRLookback);
   Print("===============================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Mark governor as inactive
   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 0);
   
   // if(CheckPointer(g_strategy) == POINTER_DYNAMIC) delete g_strategy;
   
   Comment("");
   Print("🧠 Portfolio Governor DEACTIVATED");
}

//+------------------------------------------------------------------+
//| Expert timer function                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   static datetime lastHeavyUpdate = 0;
   
   // Run heavy calculations every InpHeavyUpdateMinutes
   // Also run if empty universe (startup)
   if(TimeCurrent() - lastHeavyUpdate >= InpHeavyUpdateMinutes * 60 || ArraySize(g_activeSymbols) == 0)
   {
      // 1. First calc correlations on ALL market watch (needed for selection)
      // We need a separate list for "Candidates" vs "Active"
      // For simplicity, let's use a specialized function inside UpdateActiveUniverse
      
      UpdateActiveUniverse(); // The Brain that picks the pairs
      
      CalculateLiveCorrelations(); // Update correlations for the NEW active list
      CalculatePortfolioVaR();     // Calculate VaR
      UpdateRiskLimitsByRegime();  // Update limits
      
      lastHeavyUpdate = TimeCurrent();
      Print("⏱️ Heavy Calculations & Universe Updated");
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Throttle updates
   if(TimeCurrent() - g_lastUpdate < InpUpdateSeconds) return;
   g_lastUpdate = TimeCurrent();

   // 0. Check period resets (daily/weekly/monthly)
   CheckPeriodReset();

   // 1. Calculate portfolio metrics
   CalculatePortfolioMetrics();

   // 2. Calculate daily/weekly drawdowns
   CalculatePeriodDrawdowns();

   // 3. Update risk multiplier
   UpdateRiskMultiplier();

   // 4. Update trading enabled status
   UpdateTradingStatus();

   // 7. Execute Engines (Parallel Logic)
   for(int i=0; i<ArraySize(g_engines); i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         g_engines[i].OnTick(); // Logic runs here
      }
   }
   
   // 5. Update Heat Map & Liquidity logic
   UpdateRiskHeatMap();

   // 6. Check Tail Risk
   CheckTailRiskHedge();

   // 8. Update dashboard
   UpdateDashboard();

   // 9. Publish update timestamp
   GlobalVariableSet(GV_LAST_UPDATE, (double)TimeCurrent());
}

//+------------------------------------------------------------------+
//| Scan Signals (Deprecated - Logic moves to Engine.OnTick)          |
//+------------------------------------------------------------------+
/*
//+------------------------------------------------------------------+
//| Scan Signals (Deprecated - Logic moves to Engine.OnTick)          |
//+------------------------------------------------------------------+
void ScanSignals()
{
//   if(CanOpenTrade(sym, requestedRisk, approvedRisk))
//   {
//      // 3. Execute
//      ExecuteTrade(sym, signal, approvedRisk);
//   }
//   else
//   {
//      Print("🚫 Signal BLOCKED by Governor: ", sym);
//   }
}
*/

//+------------------------------------------------------------------+
//| Check if we already have a position in this symbol                |
//+------------------------------------------------------------------+
bool IsSymbolAlreadyTraded(string symbol)
{
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(position.SelectByIndex(i)) {
         if(position.Symbol() == symbol && position.Magic() == InpMagicBase) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Execute Trade (Central Execution)                                 |
//+------------------------------------------------------------------+
/*
//+------------------------------------------------------------------+
//| Execute Trade (Central Execution)                                 |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, int signalDir, double riskPercent)
{
   // Deprecated: Execution is now handled by SymbolEngineWrapper
}
*/

//+------------------------------------------------------------------+
//| Check for period reset (new day/week/month)                       |
//+------------------------------------------------------------------+
void CheckPeriodReset()
{
   MqlDateTime current, lastDay, lastWeek, lastMonth;
   TimeToStruct(TimeCurrent(), current);
   TimeToStruct(g_lastDayCheck, lastDay);
   TimeToStruct(g_lastWeekCheck, lastWeek);
   TimeToStruct(g_lastMonthCheck, lastMonth);

   // New day check
   if(current.day != lastDay.day || current.mon != lastDay.mon)
   {
      g_dailyStartEquity = account.Equity();
      g_dailyLimitHit = false;
      g_lastDayCheck = TimeCurrent();
      GlobalVariableSet(GV_DAILY_START_EQUITY, g_dailyStartEquity);
      Print("New trading day - Daily DD reset. Start Equity: ", g_dailyStartEquity);
   }

   // New week check (Monday)
   if(current.day_of_week == 1 && lastWeek.day_of_week != 1)
   {
      g_weeklyStartEquity = account.Equity();
      g_weeklyLimitHit = false;
      g_lastWeekCheck = TimeCurrent();
      GlobalVariableSet(GV_WEEKLY_START_EQUITY, g_weeklyStartEquity);
      Print("New trading week - Weekly DD reset. Start Equity: ", g_weeklyStartEquity);
   }

   // New month check
   if(current.mon != lastMonth.mon)
   {
      g_monthlyStartEquity = account.Equity();
      g_monthlyLimitHit = false;
      g_lastMonthCheck = TimeCurrent();
      Print("New trading month - Monthly DD reset. Start Equity: ", g_monthlyStartEquity);
   }
}

//+------------------------------------------------------------------+
//| Calculate daily/weekly drawdowns                                  |
//+------------------------------------------------------------------+
void CalculatePeriodDrawdowns()
{
   double currentEquity = account.Equity();

   // Daily DD
   double dailyDD = 0;
   if(g_dailyStartEquity > 0)
   {
      dailyDD = ((g_dailyStartEquity - currentEquity) / g_dailyStartEquity) * 100.0;
      GlobalVariableSet(GV_DAILY_DD, dailyDD);

      if(dailyDD >= InpDailyMaxDD && !g_dailyLimitHit)
      {
         g_dailyLimitHit = true;
         Print("DAILY DD LIMIT HIT: ", DoubleToString(dailyDD, 2), "% >= ", InpDailyMaxDD, "%");
      }
   }

   // Weekly DD
   double weeklyDD = 0;
   if(g_weeklyStartEquity > 0)
   {
      weeklyDD = ((g_weeklyStartEquity - currentEquity) / g_weeklyStartEquity) * 100.0;
      GlobalVariableSet(GV_WEEKLY_DD, weeklyDD);

      if(weeklyDD >= InpWeeklyMaxDD && !g_weeklyLimitHit)
      {
         g_weeklyLimitHit = true;
         Print("WEEKLY DD LIMIT HIT: ", DoubleToString(weeklyDD, 2), "% >= ", InpWeeklyMaxDD, "%");
      }
   }

   // Monthly DD
   if(g_monthlyStartEquity > 0)
   {
      double monthlyDD = ((g_monthlyStartEquity - currentEquity) / g_monthlyStartEquity) * 100.0;
      if(monthlyDD >= InpMonthlyMaxDD && !g_monthlyLimitHit)
      {
         g_monthlyLimitHit = true;
         Print("MONTHLY DD LIMIT HIT: ", DoubleToString(monthlyDD, 2), "% >= ", InpMonthlyMaxDD, "%");
      }
   }
}

//+------------------------------------------------------------------+
//| Get correlation between two symbols                               |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Get correlation between two symbols                               |
//+------------------------------------------------------------------+
double GetSymbolCorrelation(string sym1, string sym2)
{
   string s1 = sym1, s2 = sym2;
   StringToUpper(s1);
   StringToUpper(s2);
   
   // 1. Check Dynamic Matrix
   for(int i = 0; i < ArraySize(g_liveCorrelations); i++) {
      if((g_liveCorrelations[i].symbol1 == s1 && g_liveCorrelations[i].symbol2 == s2) ||
         (g_liveCorrelations[i].symbol1 == s2 && g_liveCorrelations[i].symbol2 == s1)) {
         return g_liveCorrelations[i].correlation;
      }
   }

   // 2. Fallback to Hardcoded Correlations
   for(int i = 0; i < ArraySize(g_correlations); i++)
   {
      if((g_correlations[i].symbol1 == s1 && g_correlations[i].symbol2 == s2) ||
         (g_correlations[i].symbol1 == s2 && g_correlations[i].symbol2 == s1))
      {
         return g_correlations[i].correlation;
      }
   }

   // 3. Fallback to Group Logic
   ENUM_CORR_GROUP group1 = GetCorrelationGroup(s1);
   ENUM_CORR_GROUP group2 = GetCorrelationGroup(s2);

   if(group1 == group2 && group1 != GROUP_OTHER)
      return 0.70;  // Assume moderate correlation within same group

   return 0.0;  // Unknown correlation
}

//+------------------------------------------------------------------+
//| Check if adding position would exceed correlation limits          |
//+------------------------------------------------------------------+
double GetCorrelationAdjustedRisk(string symbol, double requestedRisk)
{
   if(!InpUseCorrelationGuard) return requestedRisk;

   double adjustedRisk = requestedRisk;
   double maxCorrelation = 0;

   // Scan existing positions for correlated pairs
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         string existingSym = position.Symbol();
         if(existingSym == symbol) continue;  // Skip same symbol

         double corr = MathAbs(GetSymbolCorrelation(symbol, existingSym));
         if(corr > maxCorrelation) maxCorrelation = corr;
      }
   }

   // Apply reduction if high correlation exists
   if(maxCorrelation >= InpHighCorrelation)
   {
      adjustedRisk *= InpCorrelationReduction;
      // Print("Correlation guard: ", symbol, " reduced to ", DoubleToString(adjustedRisk, 2),
      //       "% (corr=", DoubleToString(maxCorrelation, 2), ")");
   }

   return adjustedRisk;
}

//+------------------------------------------------------------------+
//| Trade event - capture closed trades for PF calculation            |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Check for newly closed trades
   static int lastHistoryCount = 0;
   static datetime lastCheck = 0;
   
   // Optimize: Check only once per second max
   if(TimeCurrent() == lastCheck) return;
   lastCheck = TimeCurrent();

   int currentCount = HistoryDealsTotal();
   
   if(currentCount > lastHistoryCount)
   {
      // Process new closed trades
      HistorySelect(0, TimeCurrent());
      
      for(int i = lastHistoryCount; i < currentCount; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            
            // Check if it's our trade and an exit
            if(magic >= InpMagicBase && magic <= InpMagicBase + InpMagicRange)
            {
               if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
               {
                  double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                  AddTradeResult(profit);
               }
            }
         }
      }
      lastHistoryCount = currentCount;
   }
}

//+------------------------------------------------------------------+
//| Add trade result to rolling window                                |
//+------------------------------------------------------------------+
void AddTradeResult(double profit)
{
   // Shift array
   for(int i = InpRollingTrades - 1; i > 0; i--)
   {
      g_tradeResults[i] = g_tradeResults[i-1];
   }
   g_tradeResults[0] = profit;
   g_tradeCount++;
   
   // Recalculate rolling PF
   CalculateRollingPF();
}

//+------------------------------------------------------------------+
//| Calculate rolling profit factor                                   |
//+------------------------------------------------------------------+
void CalculateRollingPF()
{
   double grossProfit = 0;
   double grossLoss = 0;
   
   int count = MathMin(g_tradeCount, InpRollingTrades);
   
   for(int i = 0; i < count; i++)
   {
      if(g_tradeResults[i] > 0)
         grossProfit += g_tradeResults[i];
      else
         grossLoss += MathAbs(g_tradeResults[i]);
   }
   
   double pf = (grossLoss > 0) ? (grossProfit / grossLoss) : 2.0;
   GlobalVariableSet(GV_ROLLING_PF, pf);
}

//+------------------------------------------------------------------+
//| Calculate portfolio metrics                                       |
//+------------------------------------------------------------------+
void CalculatePortfolioMetrics()
{
   double equity = account.Equity();
   double totalExposure = 0;
   
   // Reset group risks
   double groupRisks[6] = {0, 0, 0, 0, 0, 0};
   
   // Scan all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         long magic = position.Magic();
         
         // Check if it's our trade
         if(magic >= InpMagicBase && magic <= InpMagicBase + InpMagicRange)
         {
            string sym = position.Symbol();
            double openPrice = position.PriceOpen();
            double sl = position.StopLoss();
            double volume = position.Volume();
            
            // Calculate risk for this position
            double riskPoints = MathAbs(openPrice - sl);
            double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
            
            double riskMoney = 0;
            if(tickSize > 0)
               riskMoney = (riskPoints / tickSize) * tickValue * volume;
            
            double riskPercent = (equity > 0) ? (riskMoney / equity) * 100.0 : 0;
            
            totalExposure += riskPercent;
            
            // Add to correlation group
            ENUM_CORR_GROUP group = GetCorrelationGroup(sym);
            groupRisks[(int)group] += riskPercent;
         }
      }
   }
   
   // Update GlobalVariables
   GlobalVariableSet(GV_TOTAL_EXPOSURE, totalExposure);
   GlobalVariableSet(GV_GROUP_USD_RISK, groupRisks[0]);
   GlobalVariableSet(GV_GROUP_JPY_RISK, groupRisks[1]);
   GlobalVariableSet(GV_GROUP_GBP_RISK, groupRisks[2]);
   GlobalVariableSet(GV_GROUP_METALS_RISK, groupRisks[3]);
   GlobalVariableSet(GV_GROUP_INDICES_RISK, groupRisks[4]);
   
   // Calculate drawdown
   if(equity > g_peakEquity)
   {
      g_peakEquity = equity;
      GlobalVariableSet(GV_PEAK_EQUITY, g_peakEquity);
   }
   
   double dd = (g_peakEquity > 0) ? ((g_peakEquity - equity) / g_peakEquity) * 100.0 : 0;
   GlobalVariableSet(GV_CURRENT_DD, dd);
}

//+------------------------------------------------------------------+
//| Update risk multiplier based on DD and PF                         |
//+------------------------------------------------------------------+
void UpdateRiskMultiplier()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);
   
   double mult = 1.0;
   
   // DD-based reduction
   if(dd >= InpDD_Reduced)
      mult = MathMin(mult, InpDD_ReducedMult);
   else if(dd >= InpDD_Normal)
      mult = MathMin(mult, 0.75);
   
   // PF-based reduction
   if(pf < InpPF_Normal && pf >= InpPF_Reduced)
      mult = MathMin(mult, InpPF_ReducedMult);
   else if(pf < InpPF_Reduced && pf >= InpPF_Pause)
      mult = MathMin(mult, 0.4);
   
   GlobalVariableSet(GV_RISK_MULTIPLIER, mult);
}

//+------------------------------------------------------------------+
//| Update trading enabled status                                     |
//+------------------------------------------------------------------+
void UpdateTradingStatus()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);

   bool enabled = true;
   string reason = "";

   // Pause on extreme DD
   if(dd >= InpDD_Pause)
   {
      enabled = false;
      reason = "Portfolio DD >= " + DoubleToString(InpDD_Pause, 1) + "%";
   }

   // Pause on very bad PF
   if(pf < InpPF_Pause && g_tradeCount >= 20)
   {
      enabled = false;
      reason = "PF < " + DoubleToString(InpPF_Pause, 2);
   }

   // Pause on daily DD limit
   if(g_dailyLimitHit)
   {
      enabled = false;
      reason = "Daily DD limit hit";
   }

   // Pause on weekly DD limit
   if(g_weeklyLimitHit)
   {
      enabled = false;
      reason = "Weekly DD limit hit";
   }

   // Pause on monthly DD limit
   if(g_monthlyLimitHit)
   {
      enabled = false;
      reason = "Monthly DD limit hit";
   }

   if(!enabled && reason != "")
      Print("Trading PAUSED: ", reason);

   GlobalVariableSet(GV_TRADING_ENABLED, enabled ? 1 : 0);
}

//+------------------------------------------------------------------+
//| Check if trade request is allowed                                 |
//+------------------------------------------------------------------+
bool CanOpenTrade(string symbol, double requestedRisk, double &approvedRisk)
{
   // Check if trading enabled
   if(GlobalVariableGet(GV_TRADING_ENABLED) != 1)
   {
      approvedRisk = 0;
      return false;
   }

   double totalExposure = GlobalVariableGet(GV_TOTAL_EXPOSURE);
   double riskMult = GlobalVariableGet(GV_RISK_MULTIPLIER);

   // Apply risk multiplier
   double scaledRisk = requestedRisk * riskMult;

   // Apply correlation guard adjustment
   scaledRisk = GetCorrelationAdjustedRisk(symbol, scaledRisk);

   // Check portfolio limit
   if(totalExposure + scaledRisk > InpMaxPortfolioRisk)
   {
      scaledRisk = MathMax(0, InpMaxPortfolioRisk - totalExposure);
   }

   // Check symbol limit
   scaledRisk = MathMin(scaledRisk, InpMaxSymbolRisk);

   // Check group limit
   ENUM_CORR_GROUP group = GetCorrelationGroup(symbol);
   string gvKey = GetGroupGVKey(group);
   if(gvKey != "")
   {
      double groupRisk = GlobalVariableGet(gvKey);
      if(groupRisk + scaledRisk > InpMaxGroupRisk)
      {
         scaledRisk = MathMax(0, InpMaxGroupRisk - groupRisk);
      }
   }

   approvedRisk = scaledRisk;
   return (scaledRisk > 0.05); // Minimum viable risk
}

struct SymbolRank {
   string symbol;
   double score;
   double volScore;
   double liqScore;
   double regimeScore;
};

//+------------------------------------------------------------------+
//| Check if Symbol is Tradable                                       |
//+------------------------------------------------------------------+
bool IsSymbolTradableNow(string sym)
{
   if(!SymbolInfoInteger(sym, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL) return false;
   
   double spread = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   // Hard limit? Let's say 50 points (5 pips) for majors, maybe dynamic later
   if(spread > 50 && StringFind(sym, "JPY") < 0) return false; 
   
   if(iVolume(sym, PERIOD_M1, 0) == 0) return false; // No data
   
   return true;
}

//+------------------------------------------------------------------+
//| Helper: Get ATR Value (MQL5-safe)                                 |
//+------------------------------------------------------------------+
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE) return 0;
   
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1)
   {
      IndicatorRelease(handle);
      return 0;
   }
   IndicatorRelease(handle);
   return buf[0];
}

//+------------------------------------------------------------------+
//| Helper: Get MA Value (MQL5-safe)                                  |
//+------------------------------------------------------------------+
double GetMA(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int handle = iMA(symbol, tf, period, 0, MODE_SMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 0;
   
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1)
   {
      IndicatorRelease(handle);
      return 0;
   }
   IndicatorRelease(handle);
   return buf[0];
}

//+------------------------------------------------------------------+
//| Calculate Opportunity Score                                       |
//+------------------------------------------------------------------+
double CalculateOpportunityScore(string sym)
{
   // 1. Volatility Score (Normalized ATR)
   // We want pairs that are moving, but not exploding
   double atr = GetATR(sym, PERIOD_D1, 14, 0);
   double close = iClose(sym, PERIOD_D1, 0);
   if(close == 0) return 0;
   
   double normVol = (atr / close) * 100.0; // Daily range %
   double volScore = 0;
   
   // Ideal volatility window: 0.5% to 2.0% daily
   if(normVol >= 0.5 && normVol <= 2.0) volScore = 100;
   else if(normVol < 0.5) volScore = (normVol / 0.5) * 60; // Too quiet
   else volScore = MathMax(0, 100 - (normVol - 2.0) * 50); // Too crazy
   
   // 2. Liquidity Score (Volume / Spread)
   double vol = (double)iVolume(sym, PERIOD_H1, 0);
   double spread = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   double liqRatio = (spread > 0) ? vol / spread : 0;
   double liqScore = MathMin(100, liqRatio / 10.0); // Rough normalization
   
   // 3. Regime Fit
   MARKET_REGIME globalRegime = (MARKET_REGIME)GlobalVariableGet(GV_MARKET_REGIME);
   double regimeScore = 50;
   
   double ma50 = GetMA(sym, PERIOD_D1, 50, 0);
   double ma200 = GetMA(sym, PERIOD_D1, 200, 0);
   bool trending = (MathAbs(ma50 - ma200) > atr * 2);
   
   if(globalRegime == REGIME_TREND && trending) regimeScore = 100;
   else if(globalRegime == REGIME_RANGE && !trending) regimeScore = 100;
   else if(globalRegime == REGIME_VOLATILE) regimeScore = 30; // Penalize all in chaos
   
   // Weighted Sum
   return (volScore * 0.4) + (liqScore * 0.3) + (regimeScore * 0.3);
}

//+------------------------------------------------------------------+
//| Update Active Universe (The Brain)                                |
//+------------------------------------------------------------------+
void UpdateActiveUniverse()
{
   Print("🌌 Updating Dynamic Universe...");
   
   SymbolRank ranks[];
   ArrayResize(ranks, 0);
   
   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++)
   {
      string sym = SymbolName(i, true);
      
      if(!IsSymbolTradableNow(sym)) continue;
      
      double score = CalculateOpportunityScore(sym);
      
      int s = ArraySize(ranks);
      ArrayResize(ranks, s + 1);
      ranks[s].symbol = sym;
      ranks[s].score = score;
   }
   
   // Sort Ranks (Bubble sort for simplicity with small lists)
   int count = ArraySize(ranks);
   for(int i = 0; i < count - 1; i++) {
      for(int j = 0; j < count - i - 1; j++) {
         if(ranks[j].score < ranks[j+1].score) { // Descending
            SymbolRank temp = ranks[j];
            ranks[j] = ranks[j+1];
            ranks[j+1] = temp;
         }
      }
   }
   
   // Select Top N Uncorrelated
   ArrayResize(g_activeSymbols, 0);
   int maxSlots = 6; // Default to 6 pairs as requested
   
   // High VaR? Reduce slots by half
   double currentVaR = GlobalVariableGet(GV_PORTFOLIO_VAR);
   if(currentVaR > InpMaxVaR * 0.8) maxSlots = 3;
   
   for(int i = 0; i < count; i++)
   {
      if(ArraySize(g_activeSymbols) >= maxSlots) break;
      
      string candidate = ranks[i].symbol;
      bool correlated = false;
      
      // Check against already selected
      for(int a = 0; a < ArraySize(g_activeSymbols); a++) {
         double corr = GetSymbolCorrelation(candidate, g_activeSymbols[a]); // Uses live matrix
         if(corr > 0.70) {
            correlated = true;
            Print("   Skipping ", candidate, " (Correlated with ", g_activeSymbols[a], ")");
            break;
         }
      }
      
      if(!correlated) {
         int s = ArraySize(g_activeSymbols);
         ArrayResize(g_activeSymbols, s + 1);
         g_activeSymbols[s] = candidate;
         Print("   ✅ Selected: ", candidate, " (Score: ", DoubleToString(ranks[i].score, 1), ")");
      }
   }
   
   // Sync HeatMap
   ArrayResize(g_heatMap, ArraySize(g_activeSymbols));
   for(int i = 0; i < ArraySize(g_activeSymbols); i++) {
        g_heatMap[i].symbol = g_activeSymbols[i];
   }
}

//+------------------------------------------------------------------+
//| Calculate Live Correlation Matrix                                 |
//+------------------------------------------------------------------+
void CalculateLiveCorrelations()
{
   Print("... Calculating Live Correlations (this may take a moment) ...");
   
   int activeCount = ArraySize(g_activeSymbols);
   // Reset matrix
   ArrayResize(g_liveCorrelations, 0);
   
   int lookback = InpCorrLookback;
   
   for(int i = 0; i < activeCount; i++)
   {
      for(int j = i + 1; j < activeCount; j++)
      {
         string sym1 = g_activeSymbols[i];
         string sym2 = g_activeSymbols[j];
         
         double returns1[], returns2[];
         ArrayResize(returns1, lookback);
         ArrayResize(returns2, lookback);
         
         // Get Returns
         bool dataOK = true;
         for(int k = 0; k < lookback; k++)
         {
            // Use M1 or H1 ? H1 is safer for stability
            double c1_now = iClose(sym1, PERIOD_H1, k);
            double c1_prev = iClose(sym1, PERIOD_H1, k+1);
            
            double c2_now = iClose(sym2, PERIOD_H1, k);
            double c2_prev = iClose(sym2, PERIOD_H1, k+1);
            
            if(c1_prev == 0 || c2_prev == 0) { dataOK = false; break; }
            
            returns1[k] = (c1_prev != 0) ? (c1_now - c1_prev)/c1_prev : 0;
            returns2[k] = (c2_prev != 0) ? (c2_now - c2_prev)/c2_prev : 0;
         }
         
         if(dataOK)
         {
            double corr = CalculatePearson(returns1, returns2);
            
            // Store High Correlations Only (> 0.5 or < -0.5) to save memory?
            // Or store all? Let's store significant ones.
            if(MathAbs(corr) > 0.3) 
            {
               int s = ArraySize(g_liveCorrelations);
               ArrayResize(g_liveCorrelations, s + 1);
               g_liveCorrelations[s].symbol1 = sym1;
               g_liveCorrelations[s].symbol2 = sym2;
               g_liveCorrelations[s].correlation = corr;
               g_liveCorrelations[s].lastUpdate = TimeCurrent();
               
               // Update GV for key pairs
               if(sym1 == "EURUSD" && sym2 == "GBPUSD") GlobalVariableSet(GV_CORR_EUR_GBP, corr);
               if(sym1 == "USDJPY" && sym2 == "XAUUSD") GlobalVariableSet(GV_CORR_GOLD_USD, corr);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get Dominant Portfolio Regime                                     |
//+------------------------------------------------------------------+
MARKET_REGIME GetDominantPortfolioRegime()
{
   int trendCount = 0;
   int rangeCount = 0;
   int volCount = 0;
   int total = 0;
   
   for(int i = 0; i < ArraySize(g_activeSymbols); i++)
   {
      string sym = g_activeSymbols[i];
      double close = iClose(sym, PERIOD_D1, 0);
      double ma200 = GetMA(sym, PERIOD_D1, 200, 0);
      double atr = GetATR(sym, PERIOD_D1, 14, 0);
      double atrAvg = GetATR(sym, PERIOD_D1, 14, 10); // simplified avg
      
      if(close == 0 || ma200 == 0) continue;
      
      total++;
      if(atr > atrAvg * 1.5) volCount++;
      else if(MathAbs(close - ma200) > atr * 5) trendCount++; // Far from MA
      else rangeCount++;
   }
   
   if(total == 0) return REGIME_RANGE;
   
   if( (double)volCount/total > 0.3 ) return REGIME_VOLATILE;
   if( (double)trendCount/total > 0.5 ) return REGIME_TREND;
   
   return REGIME_RANGE;
}

//+------------------------------------------------------------------+
//| Update Risk Limits Based on Regime                                |
//+------------------------------------------------------------------+
void UpdateRiskLimitsByRegime()
{
   if(!InpUseRegimeSwitch) return;
   
   MARKET_REGIME regime = GetDominantPortfolioRegime();
   GlobalVariableSet(GV_MARKET_REGIME, (double)regime);
   
   for(int i = 0; i < ArraySize(g_regimeProfiles); i++)
   {
      if(g_regimeProfiles[i].regime == regime)
      {
         GlobalVariableSet(GV_MAX_PORTFOLIO_RISK, g_regimeProfiles[i].maxPortfolioRisk);
         GlobalVariableSet(GV_MAX_SYMBOL_RISK, g_regimeProfiles[i].maxSymbolRisk);
         GlobalVariableSet(GV_MAX_GROUP_RISK, g_regimeProfiles[i].maxGroupRisk);
         
         Print("📊 Regime Changed to: ", EnumToString(regime));
         Print("   Max Risk: ", g_regimeProfiles[i].maxPortfolioRisk, "%");
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Portfolio Value at Risk (VaR)                           |
//+------------------------------------------------------------------+
void CalculatePortfolioVaR()
{
   double returns[];
   int lookback = InpVaRLookback;
   ArrayResize(returns, lookback);
   ArrayInitialize(returns, 0);
   
   int activeCount = ArraySize(g_activeSymbols);
   
   // 1. Calculate historical daily portfolio returns (Simulated)
   // This assumes constant position sizes equal to current exposure, which is an approximation
   for(int i = 0; i < lookback; i++)
   {
      double dayReturnSum = 0;
      double totalWeight = 0;
      
      for(int s = 0; s < activeCount; s++)
      {
         string sym = g_activeSymbols[s];
         // Get current exposure for this symbol
         // Optimally we should map this properly, for now scan positions
         double weight = GetSymbolExposure(sym); 
         if(weight <= 0) continue;
         
         double c_today = iClose(sym, PERIOD_D1, i);
         double c_yest = iClose(sym, PERIOD_D1, i+1);
         
         if(c_today > 0 && c_yest > 0) {
             double r = (c_today - c_yest) / c_yest;
             dayReturnSum += weight * r;
             totalWeight += weight;
         }
      }
      returns[i] = dayReturnSum;
   }
   
   // 2. Calculate VaR (95%)
   double var = MathAbs(CalculatePercentile(returns, 0.05)); // 5th percentile worst loss
   GlobalVariableSet(GV_PORTFOLIO_VAR, var);
   
   if(var > InpMaxVaR) {
      Print("⛔ VaR BREACH: ", var, "% > ", InpMaxVaR, "%");
      // Could trigger pause here or in UpdateTradingStatus
   }
}

//+------------------------------------------------------------------+
//| Update Risk Heat Map                                              |
//+------------------------------------------------------------------+
void UpdateRiskHeatMap()
{
   for(int i = 0; i < ArraySize(g_heatMap); i++)
   {
      string sym = g_heatMap[i].symbol;
      double risk = GetSymbolExposure(sym);
      g_heatMap[i].currentRisk = risk;
      
      // Update Heat Source
      // 1. Exposure Heat
      double score = (risk / InpMaxSymbolRisk) * 50.0;
      
      // 2. Volatility Heat (ATR proximity)
      double atr = GetATR(sym, PERIOD_D1, 14, 0);
      double range = iHigh(sym, PERIOD_D1, 0) - iLow(sym, PERIOD_D1, 0);
      if(atr > 0 && range > atr * 1.5) score += 30; // High daily range
      
      g_heatMap[i].heatScore = MathMin(100, score);
      
      // Apply reduction if too hot
      double reduction = 1.0;
      if(score > 80) reduction = 0.5;
      else if(score > 60) reduction = 0.8;
      
      GlobalVariableSet(GV_HEAT_MULT_PREFIX + sym, reduction);
   }
}

//+------------------------------------------------------------------+
//| Helper: Get Symbol Exposure %                                     |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Get exact risk % for a specific symbol                            |
//+------------------------------------------------------------------+
double GetSymbolExposure(string symbol)
{
   double totalRisk = 0;
   double equity = account.Equity();
   if(equity <= 0) return 0;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(position.SelectByIndex(i)) {
         if(position.Symbol() == symbol && position.Magic() == InpMagicBase) {
             double sl = position.StopLoss();
             double open = position.PriceOpen();
             
             // If no SL, assume catastrophic risk? Or 0? 
             // Production rule: Every trade MUST have SL. If not, penalize heavily.
             if(sl == 0) {
                totalRisk += 0.5; // Fallback penalty
                continue;
             }
             
             double riskPoints = MathAbs(open - sl);
             double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
             double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
             double volume = position.Volume();
             
             if(tickSize > 0) {
                 double riskMoney = (riskPoints / tickSize) * tickValue * volume;
                 totalRisk += (riskMoney / equity) * 100.0;
             }
         }
      }
   }
   return totalRisk;
}

//+------------------------------------------------------------------+
//| Check Tail Risk (Net Delta)                                       |
//+------------------------------------------------------------------+
void CheckTailRiskHedge()
{
   double netDelta = 0;
   int count = 0;
   
   for(int i = PositionsTotal()-1; i >= 0; i--) {
       if(position.SelectByIndex(i)) {
          double vol = position.Volume();
          if(position.PositionType() == POSITION_TYPE_SELL) vol = -vol;
          netDelta += vol;
          count++;
       }
   }
   
   // If highly directional (net delta > 5 lots or equivalent)
   // This is raw lots, ideally should be dollar-delta or beta-weighted delta
   double mult = 1.0;
   if(MathAbs(netDelta) > 5.0 && count > 3) {
      mult = 0.5; // Restrict new directional trades
      Print("🛡️ Tail Risk Active: Net Delta ", netDelta);
   }
   GlobalVariableSet(GV_TAIL_RISK_MULT, mult);
}



//+------------------------------------------------------------------+
//| Manage Open Trades (Trailing, BE, Partials)                       |
//+------------------------------------------------------------------+
/*
void ManageOpenTrades()
{
   // Legacy: Managed by SymbolEngine
}
*/

//+------------------------------------------------------------------+
//| Check Trading Hours                                               |
//+------------------------------------------------------------------+
bool CheckTime(string start, string end)
{
   datetime dt = TimeCurrent();
    string current = TimeToString(dt, TIME_MINUTES);
   
   if(start < end)
   {
      return (current >= start && current <= end);
   }
   else
   {
      return (current >= start || current <= end);
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);
   double exposure = GlobalVariableGet(GV_TOTAL_EXPOSURE);
   double riskMult = GlobalVariableGet(GV_RISK_MULTIPLIER);
   double var = GlobalVariableGet(GV_PORTFOLIO_VAR);
   double regime = GlobalVariableGet(GV_MARKET_REGIME);
   
   bool enabled = GlobalVariableGet(GV_TRADING_ENABLED) == 1;

   string status = enabled ? "ACTIVE" : "PAUSED";
   if(g_dailyLimitHit) status = "DAILY LIMIT";

   string regimeStr = EnumToString((MARKET_REGIME)regime);
   StringReplace(regimeStr, "REGIME_", "");

   string text = "═══════════════════════════════════════════════\n";
   text += "  🧠 PORTFOLIO GOVERNOR v2.1 (GOD MODE)\n";
   text += "═══════════════════════════════════════════════\n";
   text += "Status: " + status + "  |  Regime: " + regimeStr + "\n";
   text += "-----------------------------------------------\n";
   text += "Equity: $" + DoubleToString(account.Equity(), 2) + "\n";
   text += "DD: " + DoubleToString(dd, 2) + "% (Limit: " + DoubleToString(InpDD_Pause, 1) + "%)\n";
   text += "VaR (95%): " + DoubleToString(var, 2) + "% (Limit: " + DoubleToString(InpMaxVaR, 2) + "%)\n";
   text += "-----------------------------------------------\n";
   text += "Exposure: " + DoubleToString(exposure, 2) + "%\n";
   text += "Risk Mult: " + DoubleToString(riskMult * 100, 0) + "%\n";
   text += "Tail Risk Mult: " + DoubleToString(GlobalVariableGet(GV_TAIL_RISK_MULT), 2) + "\n";
   text += "-----------------------------------------------\n";
   text += "Daily DD: " + DoubleToString(GlobalVariableGet(GV_DAILY_DD), 2) + "%\n";
   text += "Weekly DD: " + DoubleToString(GlobalVariableGet(GV_WEEKLY_DD), 2) + "%\n";
   text += "═══════════════════════════════════════════════\n";
   
   Comment(text);
}
//+------------------------------------------------------------------+
