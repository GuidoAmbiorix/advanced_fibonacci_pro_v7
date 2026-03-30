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
#include "Include\RankManager.mqh"
// #include "Include\DashboardCanvas.mqh" // DISABLED FOR LITE MODE

CGovernorAllocator allocator;
CRankManager       rankManager;
// CDashboardCanvas   dashboardCanvas; // DISABLED FOR LITE MODE

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "═══════ PORTFOLIO LIMITS ═══════"
input double InpMaxPortfolioRisk = 3.0;        // Max Total Portfolio Risk (%)
input double InpMaxSymbolRisk = 0.6;           // Max Risk Per Symbol (%)
input double InpMaxGroupRisk = 2.0;            // Max Risk Per Correlation Group (%)

input group "═══════ DRAWDOWN GOVERNOR ═══════"
input double InpDD_Normal = 1.5;               // DD Level: Normal Trading (%)
input double InpDD_Reduced = 2.5;              // DD Level: Reduced Risk (%)
input double InpDD_Pause = 3.5;                // DD Level: Pause Trading (%) [GOAT: Max 4%]
input double InpDD_ReducedMult = 0.5;          // Risk Multiplier when DD > Normal

input group "═══════ ROLLING PF GOVERNOR ═══════"
input int    InpRollingTrades = 30;            // Rolling Window (trades)
input double InpPF_Normal = 1.8;               // PF Level: Normal Trading
input double InpPF_Reduced = 1.2;              // PF Level: Reduced Risk
input double InpPF_Pause = 1.0;                // PF Level: Pause Trading
input double InpPF_ReducedMult = 0.7;          // Risk Mult when PF < Normal

input group "═══════ DAILY/WEEKLY LIMITS ═══════"
input double InpDailyMaxDD = 2.5;              // Daily Max Drawdown (%) [GOAT: No daily limit, but be safe]
input double InpWeeklyMaxDD = 3.5;             // Weekly Max Drawdown (%) [GOAT: 4% trailing total]
input double InpMonthlyMaxDD = 4.0;            // Monthly Max Drawdown (%) [GOAT: 4% trailing max]
input double InpDailyTarget = 0.0;             // Daily Profit Target (%, 0=disabled)
input double InpDailyTargetUSD = 10.0;         // Daily Profit Target ($, 0=disabled) [GOAT: $10]

input group "═══════ CORRELATION GUARD ═══════"
input bool   InpUseCorrelationGuard = true;    // Enable Correlation Guard
input double InpHighCorrelation = 0.70;        // High Correlation Threshold
input double InpCorrelationReduction = 0.50;   // Size Reduction Factor


input group "═══════ MAGIC NUMBER RANGE ═══════"
input int    InpMagicBase = 100000;            // Magic Number Base
input int    InpMagicRange = 999;              // Magic Number Range (Base to Base+Range)

input group "═══════ FRIDAY CLOSE ═══════"
input int    InpFridayCloseHour = 22;          // Friday close hour (broker time, 0=disabled)

input group "═══════ UPDATE FREQUENCY ═══════"
input int    InpUpdateSeconds = 5;             // Update Interval (seconds)


//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CPositionInfo position;
CAccountInfo  account;

double g_peakEquity = 0;
datetime g_lastUpdate = 0;
bool g_fridayCloseExecuted = false;

// FIX: Transaction logging (Phase 4 - Race condition prevention)
int g_transactionLogHandle = INVALID_HANDLE;
string g_transactionLogFile = "";

// Dashboard performance cache
struct DashboardCache
{
   double lastDD;
   double lastPF;
   double lastExposure;
   double lastRiskMult;
   bool lastTradingEnabled;
   double lastDailyProfit;
   bool lastDailyTarget;
   datetime lastUpdateTime;
   int positionsCount;
   bool forceUpdate;
};
DashboardCache g_dashCache;

// Consistency tracking - Last 5 days history
struct DailyPnL
{
   datetime date;
   double profit;
};
DailyPnL g_last5Days[5];

// Market status tracking
datetime g_lastTickReceived = 0;

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
bool g_dailyTargetHit = false;
bool g_dailyTargetPositionsClosed = false;


// Correlation matrix (pre-defined known correlations)
struct SymbolCorrelation
{
   string symbol1;
   string symbol2;
   double correlation;
};

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
   // Detect broker suffix (e.g. "c" for Exness cent accounts)
   DetectBrokerSuffix();

   // Initialize GlobalVariables
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
   
   // Restore peak equity from persistent GV on restart; only initialize from current equity if no prior peak recorded
   double savedPeak = GlobalVariableGet(GV_PEAK_EQUITY);
   g_peakEquity = (savedPeak > 0) ? savedPeak : account.Equity();
   ArrayResize(g_tradeResults, InpRollingTrades);
   ArrayInitialize(g_tradeResults, 0);

   // Initialize daily/weekly/monthly tracking
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
   GlobalVariableSet(GV_DAILY_PROFIT, 0);
   GlobalVariableSet(GV_DAILY_TARGET_HIT, 0);


   // Initialize Dashboard Cache
   ZeroMemory(g_dashCache);
   g_dashCache.forceUpdate = true;

   // Set up timer for updates even when market is closed (every 5 seconds)
   EventSetTimer(InpUpdateSeconds);

   Print("===============================================================");
   // Initialize Rank Manager: Auto-Discovery is now active (no manual AddSymbol needed)


   // Initialize Dashboard Canvas
   // if(!dashboardCanvas.Init("GovDashboard", 20, 20, 550, 400))
   //    Print("Failed to create dashboard canvas");

   Print("  PORTFOLIO GOVERNOR v2.0 ENHANCED DASHBOARD READY");
   Print("===============================================================");
   Print("  Max Portfolio Risk: ", InpMaxPortfolioRisk, "%");
   Print("  Max Symbol Risk: ", InpMaxSymbolRisk, "%");
   Print("  Max Group Risk: ", InpMaxGroupRisk, "%");
   Print("  DD Pause Level: ", InpDD_Pause, "%");
   Print("  PF Pause Level: < ", InpPF_Pause);
   Print("  Daily Max DD: ", InpDailyMaxDD, "%");
   Print("  Weekly Max DD: ", InpWeeklyMaxDD, "%");
   Print("  Correlation Guard: ", InpUseCorrelationGuard ? "ON" : "OFF");
   Print("  Timer Update: Every ", InpUpdateSeconds, " seconds (works when market closed)");
   Print("===============================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Kill timer
   EventKillTimer();

   // Mark governor as inactive
   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 0);

   // FIX: Close transaction log file (Phase 4)
   if(g_transactionLogHandle != INVALID_HANDLE)
   {
      FileClose(g_transactionLogHandle);
      g_transactionLogHandle = INVALID_HANDLE;
      Print("Transaction log closed: ", g_transactionLogFile);
   }

   // Clean up dashboard visual objects
   DeleteDashboard();

   Comment("");
   Print("🧠 Portfolio Governor DEACTIVATED");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Register tick received (for market status detection)
   g_lastTickReceived = TimeCurrent();

   ProcessGovernorUpdate();
}

//+------------------------------------------------------------------+
//| Timer function (works even when market is closed)                |
//+------------------------------------------------------------------+
void OnTimer()
{
   ProcessGovernorUpdate();
}

//+------------------------------------------------------------------+
//| Main Governor Update Logic (shared by OnTick and OnTimer)        |
//+------------------------------------------------------------------+
void ProcessGovernorUpdate()
{
   // Throttle updates
   if(TimeCurrent() - g_lastUpdate < InpUpdateSeconds) return;
   g_lastUpdate = TimeCurrent();

   // 0. Check period resets (daily/weekly/monthly)
   CheckPeriodReset();

   // 0.5 Friday Pre-Weekend Close
   if(InpFridayCloseHour > 0)
   {
      MqlDateTime dtFri;
      TimeCurrent(dtFri);
      if(dtFri.day_of_week == 5 && dtFri.hour >= InpFridayCloseHour)
      {
         if(!g_fridayCloseExecuted)
         {
            CloseAllPositions("Friday Pre-Weekend Close");
            g_fridayCloseExecuted = true;
            Print("[GOVERNOR] Friday close executed at hour ", dtFri.hour);
         }
      }
      else
      {
         g_fridayCloseExecuted = false; // Reset on non-Friday or before close hour
      }
   }

   // 1. Calculate portfolio metrics
   CalculatePortfolioMetrics();

   // 2. Calculate daily/weekly drawdowns
   CalculatePeriodDrawdowns();

   // 3. Update risk multiplier
   UpdateRiskMultiplier();

   // 4. Update trading enabled status
   UpdateTradingStatus();

   // 5. Update dashboard
   UpdateDashboard();

   // 8. Update Ranks (Ranking System)
   rankManager.UpdateRanks();

   // 9. Publish update timestamp
   GlobalVariableSet(GV_LAST_UPDATE, (double)TimeCurrent());
}

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
      g_dailyTargetHit = false;
      g_dailyTargetPositionsClosed = false;
      GlobalVariableSet(GV_DAILY_TARGET_HIT, 0);
      GlobalVariableSet(GV_DAILY_PROFIT, 0);
      g_lastDayCheck = TimeCurrent();
      GlobalVariableSet(GV_DAILY_START_EQUITY, g_dailyStartEquity);
      Print("New trading day - Daily reset. Start Equity: ", g_dailyStartEquity);
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

      double dailyProfitUSD = currentEquity - g_dailyStartEquity;
      double dailyProfit = (g_dailyStartEquity > 0) ? (dailyProfitUSD / g_dailyStartEquity) * 100.0 : 0;
      GlobalVariableSet(GV_DAILY_PROFIT, dailyProfit);

      bool targetUSDHit = (InpDailyTargetUSD > 0 && dailyProfitUSD >= InpDailyTargetUSD);
      bool targetPctHit = (InpDailyTarget > 0 && dailyProfit >= InpDailyTarget);

      if((targetUSDHit || targetPctHit) && !g_dailyTargetHit)
      {
         g_dailyTargetHit = true;
         GlobalVariableSet(GV_DAILY_TARGET_HIT, 1);
         
         string targetMsg = targetUSDHit ? StringFormat("$%.2f", InpDailyTargetUSD) : StringFormat("%.2f%%", InpDailyTarget);
         Print("DAILY TARGET HIT: ", targetMsg, " - Trading paused for today!");
               
         if(!g_dailyTargetPositionsClosed)
         {
            CloseAllPositions("Daily Profit Target Reached!");
            g_dailyTargetPositionsClosed = true;
         }
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
//| Emergency Close All Positions                                     |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   CTrade trade;
   int total = PositionsTotal();
   int closedCount = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         long magic = position.Magic();
         if(magic >= InpMagicBase && magic <= InpMagicBase + InpMagicRange)
         {
            if(trade.PositionClose(position.Ticket()))
            {
               closedCount++;
            }
            else
            {
               Print("Failed to close position ", position.Ticket(), " Error: ", GetLastError());
            }
         }
      }
   }
   Print("EMERGENCY CLOSE ALL EXECUTED. Reason: ", reason, " | Closed: ", closedCount, " positions.");
}

//+------------------------------------------------------------------+
//| Get correlation between two symbols                               |
//+------------------------------------------------------------------+
double GetSymbolCorrelation(string sym1, string sym2)
{
   // Normalize symbols (strip broker suffix like "c" for cent accounts)
   string s1 = StripBrokerSuffix(sym1), s2 = StripBrokerSuffix(sym2);
   StringToUpper(s1);
   StringToUpper(s2);

   // Remove common suffixes
   StringReplace(s1, ".PRO", "");
   StringReplace(s2, ".PRO", "");

   // Check predefined correlations
   for(int i = 0; i < ArraySize(g_correlations); i++)
   {
      if((g_correlations[i].symbol1 == s1 && g_correlations[i].symbol2 == s2) ||
         (g_correlations[i].symbol1 == s2 && g_correlations[i].symbol2 == s1))
      {
         return g_correlations[i].correlation;
      }
   }

   // Check if same correlation group
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
   int highCorrPositions = 0;  // FIX: Count correlated positions (Phase 4)

   // Scan existing positions for correlated pairs
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         string existingSym = position.Symbol();
         if(existingSym == symbol) continue;  // Skip same symbol

         double corr = MathAbs(GetSymbolCorrelation(symbol, existingSym));
         if(corr > maxCorrelation) maxCorrelation = corr;

         // FIX: Count positions with correlation > 0.75
         if(corr >= 0.75) highCorrPositions++;
      }
   }

   // FIX: Block 3rd correlated position (Phase 4 enhancement)
   if(highCorrPositions >= 2 && maxCorrelation >= 0.75)
   {
      Print("⛔ CORRELATION GUARD: ", symbol, " BLOCKED - Already holding ", highCorrPositions,
            " positions with correlation >= 0.75");
      LogTransaction(symbol, "CORR_BLOCK", GlobalVariableGet(GV_TOTAL_EXPOSURE), GlobalVariableGet(GV_TOTAL_EXPOSURE));
      return 0;  // Block entry completely
   }

   // Apply reduction if high correlation exists (but < 2 positions)
   if(maxCorrelation >= InpHighCorrelation)
   {
      adjustedRisk *= InpCorrelationReduction;
      Print("⚠ Correlation guard: ", symbol, " reduced to ", DoubleToString(adjustedRisk, 2),
            "% (corr=", DoubleToString(maxCorrelation, 2), ", positions=", highCorrPositions, ")");
   }

   return adjustedRisk;
}

//+------------------------------------------------------------------+
//| Trade event - capture closed trades for PF calculation            |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Check for newly closed trades
   // Use GlobalVariable to persist count across EA restarts, preventing history re-processing
   string gvHistoryKey = "PG_LastHistoryCount";
   int lastHistoryCount = (int)GlobalVariableGet(gvHistoryKey);
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
            
            // Check if it's our trade and an exit for Portfolio metrics
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
      GlobalVariableSet(gvHistoryKey, currentCount);
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
   
   // FIX: Update GlobalVariables with transaction logging (Phase 4)
   double oldExposure = GlobalVariableGet(GV_TOTAL_EXPOSURE);

   GlobalVariableSet(GV_TOTAL_EXPOSURE, totalExposure);
   GlobalVariableSet(GV_GROUP_USD_RISK, groupRisks[0]);
   GlobalVariableSet(GV_GROUP_JPY_RISK, groupRisks[1]);
   GlobalVariableSet(GV_GROUP_GBP_RISK, groupRisks[2]);
   GlobalVariableSet(GV_GROUP_METALS_RISK, groupRisks[3]);
   GlobalVariableSet(GV_GROUP_INDICES_RISK, groupRisks[4]);

   // Log significant changes (> 0.1% delta)
   if(MathAbs(totalExposure - oldExposure) > 0.1)
   {
      LogTransaction("PORTFOLIO", "UPDATE", oldExposure, totalExposure);
   }
   
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

   // Pause when daily profit target is hit (lock in gains)
   if(g_dailyTargetHit)
   {
      enabled = false;
      reason = "Daily profit target hit (gains locked)";
   }

   // Only log on state change to avoid spam every timer tick
   static bool lastEnabled = true;
   if(enabled != lastEnabled)
   {
      if(!enabled)
         Print("Trading PAUSED: ", reason);
      else
         Print("Trading RESUMED");
      lastEnabled = enabled;
   }

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

   // Check portfolio limit (micro-account aware)
   double effectivePortfolioCap = InpMaxPortfolioRisk;
   if(account.Equity() <= 500)       effectivePortfolioCap = MathMax(InpMaxPortfolioRisk, 25.0);
   else if(account.Equity() <= 2000) effectivePortfolioCap = MathMax(InpMaxPortfolioRisk, 20.0);
   else if(account.Equity() <= 10000) effectivePortfolioCap = MathMax(InpMaxPortfolioRisk, 10.0);

   if(totalExposure + scaledRisk > effectivePortfolioCap)
   {
      scaledRisk = MathMax(0, effectivePortfolioCap - totalExposure);
   }

   // Check symbol limit (micro-account aware)
   // Micro accounts need higher % per symbol to open min lots
   double effectiveSymbolCap = InpMaxSymbolRisk;
   double equity = account.Equity();
   if(equity <= 100)        effectiveSymbolCap = MathMax(InpMaxSymbolRisk, 15.0);
   else if(equity <= 500)   effectiveSymbolCap = MathMax(InpMaxSymbolRisk, 12.0);
   else if(equity <= 2000)  effectiveSymbolCap = MathMax(InpMaxSymbolRisk, 10.0);
   else if(equity <= 10000) effectiveSymbolCap = MathMax(InpMaxSymbolRisk, 5.0);

   scaledRisk = MathMin(scaledRisk, effectiveSymbolCap);

   // Check group limit (also micro-aware)
   double effectiveGroupCap = InpMaxGroupRisk;
   if(equity <= 200) effectiveGroupCap = MathMax(InpMaxGroupRisk, effectiveSymbolCap * 2.0);

   ENUM_CORR_GROUP group = GetCorrelationGroup(symbol);
   string gvKey = GetGroupGVKey(group);
   if(gvKey != "")
   {
      double groupRisk = GlobalVariableGet(gvKey);
      if(groupRisk + scaledRisk > effectiveGroupCap)
      {
         scaledRisk = MathMax(0, effectiveGroupCap - groupRisk);
      }
   }

   approvedRisk = scaledRisk;
   return (scaledRisk > 0.05); // Minimum viable risk
}

//+------------------------------------------------------------------+
//| FIX: Transaction Logger (Phase 4 - Debug race conditions)         |
//+------------------------------------------------------------------+
void LogTransaction(string symbol, string action, double exposureBefore, double exposureAfter)
{
   // Create file on first call
   if(g_transactionLogHandle == INVALID_HANDLE)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      g_transactionLogFile = StringFormat("Governor_Transactions_%04d%02d%02d.csv",
                                          dt.year, dt.mon, dt.day);

      g_transactionLogHandle = FileOpen(g_transactionLogFile,
                                       FILE_WRITE|FILE_CSV|FILE_COMMON,
                                       ",");

      if(g_transactionLogHandle != INVALID_HANDLE)
      {
         // Write header
         FileWrite(g_transactionLogHandle,
                  "Timestamp", "Symbol", "Action", "ExposureBefore",
                  "ExposureAfter", "Delta", "TotalPositions");
      }
   }

   if(g_transactionLogHandle != INVALID_HANDLE)
   {
      double delta = exposureAfter - exposureBefore;
      int totalPositions = PositionsTotal();

      FileWrite(g_transactionLogHandle,
               TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
               symbol,
               action,
               DoubleToString(exposureBefore, 3),
               DoubleToString(exposureAfter, 3),
               DoubleToString(delta, 3),
               IntegerToString(totalPositions));

      FileFlush(g_transactionLogHandle);
   }
}

//+------------------------------------------------------------------+
//| Helper: Check if Market is Open (Reliable Tick Detection)        |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   datetime currentTime = TimeCurrent();

   // Method 1: Check if we received ticks recently (< 2 minutes)
   if(g_lastTickReceived > 0)
   {
      long secondsSinceLastTick = currentTime - g_lastTickReceived;

      if(secondsSinceLastTick < 120) // Ticks within last 2 minutes
         return true;
      else if(secondsSinceLastTick < 300) // 2-5 minutes: uncertain, check day
      {
         MqlDateTime dt;
         TimeToStruct(currentTime, dt);

         // Saturday = definitely closed
         if(dt.day_of_week == 6) return false;

         // Benefit of doubt during week
         if(dt.day_of_week >= 1 && dt.day_of_week <= 5) return true;

         return false;
      }
      else // > 5 minutes without ticks = closed
      {
         return false;
      }
   }

   // Method 2: Fallback - check symbol quote time
   string symbol = Symbol();
   datetime symbolTime = (datetime)SymbolInfoInteger(symbol, SYMBOL_TIME);

   if(symbolTime > 0 && (currentTime - symbolTime) < 120)
      return true;

   // Method 3: Last resort - day check
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);

   if(dt.day_of_week == 6) return false; // Saturday
   if(dt.day_of_week == 0) return false; // Sunday (unless late)

   return false; // Default to closed if uncertain
}

//+------------------------------------------------------------------+
//| Helper: Count Trading Days (with 0.5%+ profit each)              |
//+------------------------------------------------------------------+
int CountTradingDays()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d", now.year, now.mon, now.day));
   datetime twoWeeksAgo = todayStart - 14 * 24 * 3600;

   HistorySelect(twoWeeksAgo, TimeCurrent());
   int total = HistoryDealsTotal();

   // Track profit per day
   double dayProfits[14];
   ArrayInitialize(dayProfits, 0);

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);

      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      // Calculate day index (0-13)
      int dayIndex = (int)((dealTime - twoWeeksAgo) / (24 * 3600));
      if(dayIndex >= 0 && dayIndex < 14)
         dayProfits[dayIndex] += profit;
   }

   // Count days with 0.5%+ profit
   int count = 0;
   double threshold = account.Balance() * 0.005; // 0.5%

   for(int i = 0; i < 14; i++)
   {
      if(dayProfits[i] >= threshold)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Helper: Get Today's Win Rate                                     |
//+------------------------------------------------------------------+
void GetTodayWinRate(int &wins, int &losses)
{
   wins = 0;
   losses = 0;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d", now.year, now.mon, now.day));

   HistorySelect(todayStart, TimeCurrent());
   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);

      // Filter by magic number range
      if(magic < InpMagicBase || magic > InpMagicBase + InpMagicRange) continue;

      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

      if(profit > 0)
         wins++;
      else if(profit < 0)
         losses++;
   }
}

//+------------------------------------------------------------------+
//| Dashboard - Enhanced Visual & Performance Optimized              |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   // Performance: Get all values once
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);
   double exposure = GlobalVariableGet(GV_TOTAL_EXPOSURE);
   double riskMult = GlobalVariableGet(GV_RISK_MULTIPLIER);
   bool tradingEnabled = (GlobalVariableGet(GV_TRADING_ENABLED) == 1);
   int currentPositions = PositionsTotal();

   double dailyProfit = GlobalVariableGet(GV_DAILY_PROFIT);

   // Performance: Check if FULL update needed (dirty flag system)
   bool needsFullUpdate = g_dashCache.forceUpdate ||
                          MathAbs(g_dashCache.lastDD - dd) > 0.01 ||
                          MathAbs(g_dashCache.lastPF - pf) > 0.01 ||
                          MathAbs(g_dashCache.lastExposure - exposure) > 0.01 ||
                          MathAbs(g_dashCache.lastRiskMult - riskMult) > 0.001 ||
                          g_dashCache.lastTradingEnabled != tradingEnabled ||
                          MathAbs(g_dashCache.lastDailyProfit - dailyProfit) > 0.01 ||
                          g_dashCache.lastDailyTarget != g_dailyTargetHit ||
                          g_dashCache.positionsCount != currentPositions;

   // Always update time/status at minimum every update interval (no caching for header)
   bool timeUpdate = (TimeCurrent() - g_dashCache.lastUpdateTime) >= InpUpdateSeconds;

   if(!needsFullUpdate && !timeUpdate) return; // Skip if nothing changed

   // If only time update, just refresh header (performance optimization)
   if(timeUpdate && !needsFullUpdate)
   {
      UpdateDashboardHeader(tradingEnabled);
      g_dashCache.lastUpdateTime = TimeCurrent();
      return;
   }

   // Update cache for full update
   g_dashCache.lastDD = dd;
   g_dashCache.lastPF = pf;
   g_dashCache.lastExposure = exposure;
   g_dashCache.lastRiskMult = riskMult;
   g_dashCache.lastTradingEnabled = tradingEnabled;
   g_dashCache.lastDailyProfit = dailyProfit;
   g_dashCache.lastDailyTarget = g_dailyTargetHit;
   g_dashCache.lastUpdateTime = TimeCurrent();
   g_dashCache.positionsCount = currentPositions;
   g_dashCache.forceUpdate = false;

   // Create visual dashboard with graphical objects (full redraw)
   CreateVisualDashboard(dd, pf, exposure, riskMult, tradingEnabled, dailyProfit);
}

//+------------------------------------------------------------------+
//| Update Only Dashboard Header (Time/Status) - Fast Update         |
//+------------------------------------------------------------------+
void UpdateDashboardHeader(bool tradingEnabled)
{
   int x = 15, y = 35;
   color textColor = clrWhiteSmoke;

   // Update status
   color statusColor = tradingEnabled ? clrLimeGreen : clrOrangeRed;
   string statusText = tradingEnabled ? "● ONLINE" : "● PAUSED";
   CreateLabel("GovStatus", x+320, y, statusText, statusColor, 10, true);

   // Update market status
   bool isMarketOpen = IsMarketOpen();
   color marketColor = isMarketOpen ? clrLimeGreen : clrGray;
   string marketText = isMarketOpen ? "📈 OPEN" : "🔒 CLOSED";
   CreateLabel("GovMarket", x+430, y, marketText, marketColor, 9, false);

   // Update time (this is what makes the clock tick!)
   CreateLabel("GovTime", x+520, y, TimeToString(TimeCurrent(), TIME_SECONDS), textColor, 8, false);

   ChartRedraw();
}

void CreateVisualDashboard(double dd, double pf, double exposure, double riskMult,
                          bool tradingEnabled, double dailyProfit)
{
   int x = 15, y = 25;
   int lineHeight = 18;
   int sectionGap = 8;
   color bgColor = C'20,20,30';
   color textColor = clrWhiteSmoke;

   // Main Panel Background
   CreateRectLabel("GovBG", x, y, 620, 430, bgColor, clrNONE, 1, 0);

   // Header Section
   y += 10;
   color statusColor = tradingEnabled ? clrLimeGreen : clrOrangeRed;
   string statusText = tradingEnabled ? "● ONLINE" : "● PAUSED";
   CreateLabel("GovHeader", x+10, y, "🧠 GOAT INSTANT PRO $2500", clrGold, 11, true);
   CreateLabel("GovStatus", x+320, y, statusText, statusColor, 10, true);

   // Market status indicator
   bool isMarketOpen = IsMarketOpen();
   color marketColor = isMarketOpen ? clrLimeGreen : clrGray;
   string marketText = isMarketOpen ? "📈 OPEN" : "🔒 CLOSED";
   CreateLabel("GovMarket", x+430, y, marketText, marketColor, 9, false);

   CreateLabel("GovTime", x+520, y, TimeToString(TimeCurrent(), TIME_SECONDS), textColor, 8, false);

   y += lineHeight + sectionGap;
   CreateSeparator("GovSep1", x+10, y, 600, clrDimGray);

   // ═══════════════════════════════════════════════════════════════
   // SECTION 1: DAILY PERFORMANCE
   // ═══════════════════════════════════════════════════════════════
   y += sectionGap + 5;
   CreateLabel("GovDailyTitle", x+10, y, "📅 TODAY'S PERFORMANCE", clrCornflowerBlue, 10, true);


   y += lineHeight;
   double dailyProfitUSD = account.Balance() * (dailyProfit / 100.0);
   color dailyColor = dailyProfit > 0 ? clrLimeGreen : dailyProfit < 0 ? clrRed : clrGray;
   CreateLabel("GovDailyLabel", x+20, y, "P&L Today:", textColor, 9, false);
   CreateLabel("GovDailyValueUSD", x+110, y, "$" + DoubleToString(dailyProfitUSD, 2), dailyColor, 11, true);
   CreateLabel("GovDailyValuePct", x+200, y, "(" + DoubleToString(dailyProfit, 2) + "%)", dailyColor, 9, false);

   if(InpDailyTarget > 0)
   {
      double targetPct = (dailyProfit / InpDailyTarget) * 100;
      targetPct = MathMax(0, MathMin(targetPct, 100));

      // Use USD target for progress if available
      if(InpDailyTargetUSD > 0)
      {
         double profitUSD = account.Balance() * (dailyProfit / 100.0);
         targetPct = (profitUSD / InpDailyTargetUSD) * 100.0;
         targetPct = MathMax(0, MathMin(targetPct, 100));
      }

      color targetColor = g_dailyTargetHit ? clrLimeGreen : clrCornflowerBlue;
      CreateProgressBar("GovTargetBar", x+320, y-2, 150, 14, targetPct, 100, targetColor, bgColor);
      
      string targetLabel = "";
      if(InpDailyTargetUSD > 0) targetLabel = "$" + DoubleToString(InpDailyTargetUSD, 0) + " goal";
      else targetLabel = DoubleToString(InpDailyTarget, 1) + "% goal";
      
      string targetStatus = g_dailyTargetHit ? "✅ TARGET HIT" : targetLabel;
      CreateLabel("GovTargetStatus", x+480, y, targetStatus, targetColor, 8, true);
   }

   // Live Win Rate Today
   y += lineHeight;
   int todayWins = 0, todayLosses = 0;
   GetTodayWinRate(todayWins, todayLosses);
   int totalToday = todayWins + todayLosses;
   double winRateToday = totalToday > 0 ? (double)todayWins / totalToday * 100.0 : 0;
   color wrColor = winRateToday >= 60 ? clrLimeGreen :
                  winRateToday >= 45 ? clrYellow : clrOrange;
   CreateLabel("GovWinRateLabel", x+20, y, "Win Rate:", textColor, 8, false);
   CreateLabel("GovWinRateValue", x+110, y, DoubleToString(winRateToday, 0) + "%", wrColor, 9, true);
   CreateLabel("GovWinRateBreakdown", x+180, y, "(" + IntegerToString(todayWins) + "W / " + IntegerToString(todayLosses) + "L)", clrGray, 8, false);

   // Drawdown monitoring
   y += lineHeight;
   color ddColor = dd < InpDD_Normal ? clrLimeGreen :
                   dd < InpDD_Reduced ? clrYellow :
                   dd < InpDD_Pause ? clrOrange : clrRed;
   CreateLabel("GovDDLabel", x+20, y, "Drawdown:", textColor, 8, false);
   CreateLabel("GovDDValue", x+110, y, DoubleToString(dd, 2) + "%", ddColor, 9, true);
   CreateProgressBar("GovDDBar", x+180, y-2, 150, 14, dd, InpDD_Pause, ddColor, bgColor);
   CreateLabel("GovDDLimit", x+340, y, "Max: " + DoubleToString(InpDD_Pause, 1) + "% (GOAT: 4%)", clrGray, 7, false);

   y += lineHeight + sectionGap;
   CreateSeparator("GovSep3", x+10, y, 600, clrDimGray);

   // ═══════════════════════════════════════════════════════════════
   // SECTION 3: ACTIVE TRADINGS - PRIORITY #3
   // ═══════════════════════════════════════════════════════════════
   y += sectionGap + 5;
   int activePositions = PositionsTotal();
   CreateLabel("GovActiveTitle", x+10, y, "📈 ACTIVE POSITIONS (" + IntegerToString(activePositions) + ")", clrCornflowerBlue, 10, true);

   if(activePositions == 0)
   {
      y += lineHeight;
      CreateLabel("GovNoPositions", x+20, y, "No open positions", clrGray, 9, false);
   }
   else
   {
      // Show up to 5 positions
      int displayCount = MathMin(activePositions, 5);
      double totalFloating = 0;

      for(int i = 0; i < displayCount; i++)
      {
         if(position.SelectByIndex(i))
         {
            y += lineHeight;
            string symbol = position.Symbol();
            string direction = position.Type() == POSITION_TYPE_BUY ? "BUY" : "SELL";
            double floating = position.Profit() + position.Swap();
            totalFloating += floating;
            color floatColor = floating > 0 ? clrLimeGreen : floating < 0 ? clrRed : clrGray;

            // Clean symbol name
            string cleanSym = symbol;
            StringReplace(cleanSym, ".pro", "");
            StringReplace(cleanSym, ".PRO", "");
            StringReplace(cleanSym, ".x", "");
            StringReplace(cleanSym, ".X", "");

            CreateLabel("GovPos" + IntegerToString(i) + "Sym", x+20, y, cleanSym, textColor, 8, false);
            CreateLabel("GovPos" + IntegerToString(i) + "Dir", x+110, y, direction,
                       direction == "BUY" ? clrDodgerBlue : clrOrange, 8, true);
            CreateLabel("GovPos" + IntegerToString(i) + "Float", x+170, y,
                       DoubleToString(floating, 2), floatColor, 9, true);

            // Duration
            datetime openTime = position.Time();
            int durationMinutes = (int)((TimeCurrent() - openTime) / 60);
            int hours = durationMinutes / 60;
            int mins = durationMinutes % 60;
            string duration = IntegerToString(hours) + "h " + IntegerToString(mins) + "m";
            CreateLabel("GovPos" + IntegerToString(i) + "Dur", x+260, y, duration, clrGray, 7, false);

            // Volume
            CreateLabel("GovPos" + IntegerToString(i) + "Vol", x+340, y,
                       DoubleToString(position.Volume(), 2) + " lot", clrGray, 7, false);
         }
      }

      if(activePositions > 5)
      {
         y += lineHeight;
         CreateLabel("GovPosMore", x+20, y, "... +" + IntegerToString(activePositions - 5) + " more positions", clrGray, 7, false);
      }

      // Total Floating Summary
      y += lineHeight + 3;
      CreateSeparator("GovPosSep", x+20, y, 560, clrDimGray);
      y += 8;
      color totalFloatColor = totalFloating > 0 ? clrLimeGreen : totalFloating < 0 ? clrRed : clrGray;
      CreateLabel("GovFloatTotalLabel", x+20, y, "Total Floating P&L:", textColor, 9, true);
      CreateLabel("GovFloatTotalValue", x+170, y, "$" + DoubleToString(totalFloating, 2), totalFloatColor, 10, true);

      // Exposure
      CreateLabel("GovExpLabel", x+320, y, "Risk Exposure:", textColor, 8, false);
      CreateLabel("GovExpValue", x+420, y, DoubleToString(exposure, 2) + "%", clrCornflowerBlue, 9, true);
   }

   y += lineHeight + sectionGap;
   CreateSeparator("GovSep4", x+10, y, 600, clrDimGray);

   // ═══════════════════════════════════════════════════════════════
   // SECTION 4: LIVE SIGNALS RANKING - PRIORITY #4
   // ═══════════════════════════════════════════════════════════════
   y += sectionGap + 5;
   CreateLabel("GovRankTitle", x+10, y, "🏆 LIVE SIGNALS RANKING", clrCornflowerBlue, 10, true);

   SymbolRank ranks[];
   int count = rankManager.GetRanks(ranks);

   if(count == 0)
   {
      y += lineHeight;
      CreateLabel("GovNoRanks", x+20, y, "Scanning markets...", clrGray, 9, false);
   }
   else
   {
      string medals[3] = {"🥇", "🥈", "🥉"};
      color rankColors[3] = {clrGold, clrSilver, C'205,127,50'};

      y += lineHeight - 2;
      CreateLabel("GovRankHeader1", x+20, y, "SYMBOL", clrGray, 7, false);
      CreateLabel("GovRankHeader2", x+110, y, "SCORE/REQ", clrGray, 7, false);
      CreateLabel("GovRankHeader3", x+200, y, "DIR", clrGray, 7, false);
      CreateLabel("GovRankHeader4", x+250, y, "KILLZONE", clrGray, 7, false);
      CreateLabel("GovRankHeader5", x+320, y, "STATUS", clrGray, 7, false);

      int displayCount = MathMin(count, 5); // Show top 5
      for(int i = 0; i < displayCount; i++)
      {
         y += lineHeight;

         string sym = ranks[i].symbol;
         double score = ranks[i].score;
         double req = ranks[i].reqScore;
         string dir = ranks[i].direction > 0 ? "BUY" : (ranks[i].direction < 0 ? "SELL" : "WAIT");
         bool kz = ranks[i].isKZOpen;
         int rankNum = ranks[i].rank;
         
         // Clean symbol name
         string cleanSym = sym;
         StringReplace(cleanSym, ".pro", "");
         StringReplace(cleanSym, ".PRO", "");
         StringReplace(cleanSym, ".x", "");
         StringReplace(cleanSym, ".X", "");

         color scoreColor = score >= req ? clrLimeGreen : score >= 10 ? clrYellow : clrOrange;
         color dirColor = dir == "BUY" ? clrDodgerBlue : (dir == "SELL" ? clrOrangeRed : clrGray);
         color kzColor = kz ? clrLimeGreen : clrGray;
         string kzText = kz ? "ACTIVE" : "CLOSED";
         
         string statusText = (rankNum <= 3 && kz && score >= req) ? "ELIGIBLE" : "WAITING";
         color statusColor = (statusText == "ELIGIBLE") ? clrLimeGreen : clrGray;

         string rLabel = (i < 3) ? medals[i] : "#" + IntegerToString(rankNum);
         color rColor = (i < 3) ? rankColors[i] : clrWhiteSmoke;

         CreateLabel("GovLiveRank" + IntegerToString(i) + "Medal", x+20, y, rLabel, rColor, 10, false);
         CreateLabel("GovLiveRank" + IntegerToString(i) + "Sym", x+45, y, cleanSym, textColor, 9, true);
         
         string scoreTxt = DoubleToString(score, 1) + " / " + DoubleToString(req, 1);
         CreateLabel("GovLiveRank" + IntegerToString(i) + "Score", x+110, y, scoreTxt, scoreColor, 9, true);
         
         CreateLabel("GovLiveRank" + IntegerToString(i) + "Dir", x+200, y, dir, dirColor, 8, true);
         CreateLabel("GovLiveRank" + IntegerToString(i) + "KZ", x+250, y, kzText, kzColor, 8, false);
         CreateLabel("GovLiveRank" + IntegerToString(i) + "Status", x+320, y, statusText, statusColor, 8, true);
      }
   }

   // Portfolio-level stats
   y += lineHeight + sectionGap;
   CreateSeparator("GovSep5", x+10, y, 600, clrDimGray);

   y += sectionGap + 5;
   CreateLabel("GovPortfolioTitle", x+10, y, "📊 PORTFOLIO HEALTH", clrCornflowerBlue, 10, true);

   y += lineHeight;
   color pfColor = pf >= InpPF_Normal ? clrLimeGreen :
                   pf >= InpPF_Reduced ? clrYellow : clrOrange;
   CreateLabel("GovPFLabel", x+20, y, "Profit Factor:", textColor, 8, false);
   CreateLabel("GovPFValue", x+130, y, DoubleToString(pf, 2), pfColor, 9, true);
   CreateLabel("GovPFTrades", x+200, y, "(" + IntegerToString(g_tradeCount) + " trades)", clrGray, 7, false);

   color multColor = riskMult >= 1.0 ? clrLimeGreen :
                    riskMult >= 0.7 ? clrYellow : clrOrange;
   CreateLabel("GovMultLabel", x+320, y, "Risk Mult:", textColor, 8, false);
   CreateLabel("GovMultValue", x+420, y, DoubleToString(riskMult, 2) + "x", multColor, 9, true);

   // Correlation Groups Summary
   y += lineHeight;
   double usdRisk = GlobalVariableGet(GV_GROUP_USD_RISK);
   double jpyRisk = GlobalVariableGet(GV_GROUP_JPY_RISK);
   double gbpRisk = GlobalVariableGet(GV_GROUP_GBP_RISK);
   double metalsRisk = GlobalVariableGet(GV_GROUP_METALS_RISK);

   CreateLabel("GovGroupLabel", x+20, y, "Groups:", textColor, 8, false);
   CreateLabel("GovGroupUSD", x+90, y, "USD:" + DoubleToString(usdRisk, 1) + "%", clrGray, 7, false);
   CreateLabel("GovGroupJPY", x+170, y, "JPY:" + DoubleToString(jpyRisk, 1) + "%", clrGray, 7, false);
   CreateLabel("GovGroupGBP", x+250, y, "GBP:" + DoubleToString(gbpRisk, 1) + "%", clrGray, 7, false);
   CreateLabel("GovGroupXAU", x+330, y, "XAU:" + DoubleToString(metalsRisk, 1) + "%", clrGray, 7, false);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper: Create Label Object                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold)
{
   string objName = "Gov_" + name;

   if(ObjectFind(0, objName) < 0)
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetString(0, objName, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
}

//+------------------------------------------------------------------+
//| Helper: Create Rectangle Label (Background/Bar)                  |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int width, int height,
                    color bgColor, color borderColor, int borderWidth, int corner)
{
   string objName = "Gov_" + name;

   if(ObjectFind(0, objName) < 0)
      ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, borderColor);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, borderWidth);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper: Create Progress Bar                                      |
//+------------------------------------------------------------------+
void CreateProgressBar(string name, int x, int y, int maxWidth, int height,
                      double value, double maxValue, color barColor, color bgColor)
{
   string bgName = "Gov_" + name + "_BG";
   string barName = "Gov_" + name + "_Bar";

   // Background
   CreateRectLabel(name + "_BG", x, y, maxWidth, height, C'40,40,50', clrDimGray, 1, CORNER_LEFT_UPPER);

   // Progress bar (foreground)
   double pct = MathMin(value / maxValue, 1.0);
   int barWidth = (int)(maxWidth * pct);
   if(barWidth > 0)
      CreateRectLabel(name + "_Bar", x, y, barWidth, height, barColor, clrNONE, 0, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Helper: Create Separator Line                                    |
//+------------------------------------------------------------------+
void CreateSeparator(string name, int x, int y, int width, color clr)
{
   CreateRectLabel(name, x, y, width, 1, clr, clrNONE, 0, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Helper: Create Group Risk Display Line                           |
//+------------------------------------------------------------------+
void CreateGroupRiskLine(string groupName, int x, int y, double risk, double maxRisk,
                        color textColor, color bgColor)
{
   color riskColor = risk < maxRisk*0.6 ? clrLimeGreen :
                    risk < maxRisk*0.85 ? clrYellow : clrOrange;

   CreateLabel("GovGroup" + groupName + "Label", x, y, groupName + ":", textColor, 9, false);
   CreateLabel("GovGroup" + groupName + "Value", x+60, y, DoubleToString(risk, 2) + "%", riskColor, 9, true);
   CreateProgressBar("GovGroup" + groupName + "Bar", x+140, y-2, 120, 14, risk, maxRisk, riskColor, bgColor);
   CreateLabel("GovGroup" + groupName + "Limit", x+270, y, "/" + DoubleToString(maxRisk, 1) + "%", clrGray, 8, false);
}

//+------------------------------------------------------------------+
//| Helper: Delete All Dashboard Objects (Cleanup)                   |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
   int total = ObjectsTotal(0, 0, OBJ_LABEL);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_LABEL);
      if(StringFind(name, "Gov_") == 0)
         ObjectDelete(0, name);
   }

   total = ObjectsTotal(0, 0, OBJ_RECTANGLE_LABEL);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_RECTANGLE_LABEL);
      if(StringFind(name, "Gov_") == 0)
         ObjectDelete(0, name);
   }

   ChartRedraw();
   Comment("");
}
//+------------------------------------------------------------------+
