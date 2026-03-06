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
input double InpDailyTarget = 1.0;             // Daily Profit Target (%, 0=disabled)

input group "═══════ CORRELATION GUARD ═══════"
input bool   InpUseCorrelationGuard = true;    // Enable Correlation Guard
input double InpHighCorrelation = 0.70;        // High Correlation Threshold
input double InpCorrelationReduction = 0.50;   // Size Reduction Factor

input group "═══════ MAGIC NUMBER RANGE ═══════"
input int    InpMagicBase = 100000;            // Magic Number Base
input int    InpMagicRange = 999;              // Magic Number Range (Base to Base+Range)

input group "═══════ UPDATE FREQUENCY ═══════"
input int    InpUpdateSeconds = 5;             // Update Interval (seconds)

input group "═══════ CONSISTENCY RULE ═══════"
input bool   InpEnableConsistencyRule = true;  // Enable prop-firm Consistency Rule
input double InpConsistencyMaxPct    = 20.0;   // Max Best-Day % of Total Profit
input double InpConsistencyWarnPct   = 85.0;   // Warning threshold (% of max, default 85)
input double InpConsistencyMinUSD    = 150.0;  // Min total profit ($) before rule activates
input bool   InpConsistencyClose     = true;   // Proactively close positions when limit approached

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CPositionInfo position;
CAccountInfo  account;

double g_peakEquity = 0;
datetime g_lastUpdate = 0;

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
   double lastConsistencyRatio;
   bool lastConsistencyBlocked;
   double lastDailyProfit;
   bool lastDailyTarget;
   datetime lastUpdateTime;
   int positionsCount;
   bool forceUpdate;
};
DashboardCache g_dashCache;

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

// Consistency Rule tracking
double   g_consistencyBestDay   = 0;   // Best single-day realized profit ($)
double   g_consistencyTotal     = 0;   // Sum of all positive closed-day profits ($)
double   g_consistencyTodayReal = 0;   // Today's realized (closed) profit ($)
bool     g_consistencyBlocked   = false;
bool     g_consistencyScanned   = false; // True once the full history scan ran today
datetime g_consistencyScanDate  = 0;

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

   // Consistency Rule GVs
   GlobalVariableSet(GV_CONSISTENCY_BEST_DAY, 0);
   GlobalVariableSet(GV_CONSISTENCY_TOTAL,    0);
   GlobalVariableSet(GV_CONSISTENCY_RATIO,    0);
   GlobalVariableSet(GV_CONSISTENCY_BLOCKED,  0);

   // Initialize Dashboard Cache
   ZeroMemory(g_dashCache);
   g_dashCache.forceUpdate = true;

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
   Print("===============================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
   // Throttle updates
   if(TimeCurrent() - g_lastUpdate < InpUpdateSeconds) return;
   g_lastUpdate = TimeCurrent();

   // 0. Check period resets (daily/weekly/monthly)
   CheckPeriodReset();

   // 1. Calculate portfolio metrics
   CalculatePortfolioMetrics();

   // 2. Calculate daily/weekly drawdowns
   CalculatePeriodDrawdowns();

   // 3. Consistency Rule metrics
   if(InpEnableConsistencyRule)
      CalculateConsistencyMetrics();

   // 4. Update risk multiplier
   UpdateRiskMultiplier();

   // 5. Update trading enabled status
   UpdateTradingStatus();

   // 6. Proactive close if trade is rushing toward best-day cap
   if(InpEnableConsistencyRule && InpConsistencyClose)
      CheckConsistencyProactiveClose();

   // 7. Update dashboard
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
      // Consistency Rule: reset today's realized profit and force full re-scan
      g_consistencyTodayReal = 0;
      g_consistencyScanned   = false;
      g_consistencyBlocked   = false;
      GlobalVariableSet(GV_CONSISTENCY_BLOCKED, 0);
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

      // Daily profit tracking and target check
      double dailyProfit = ((currentEquity - g_dailyStartEquity) / g_dailyStartEquity) * 100.0;
      GlobalVariableSet(GV_DAILY_PROFIT, dailyProfit);

      if(InpDailyTarget > 0 && dailyProfit >= InpDailyTarget && !g_dailyTargetHit)
      {
         g_dailyTargetHit = true;
         GlobalVariableSet(GV_DAILY_TARGET_HIT, 1);
         Print("DAILY TARGET HIT: +", DoubleToString(dailyProfit, 2), "% >= ", InpDailyTarget,
               "% - Trading paused for today!");
               
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
   // Normalize symbols
   string s1 = sym1, s2 = sym2;
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

            // --- Consistency Rule: incremental update ---
            // Consistency rule applies to the ENTIRE ACCOUNT (all magic numbers)
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
            {
               long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
               if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
               {
                  // Check if this deal closed TODAY
                  datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                  MqlDateTime dealDT, nowDT;
                  TimeToStruct(dealTime, dealDT);
                  TimeToStruct(TimeCurrent(), nowDT);

                  if(dealDT.year == nowDT.year && dealDT.mon == nowDT.mon && dealDT.day == nowDT.day)
                  {
                     // Full P&L = profit + swap + commission
                     double fullPnL = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                     g_consistencyTodayReal += fullPnL;

                     // Invalidate cache so next Governor tick re-runs CalculateConsistencyMetrics
                     g_consistencyScanned = false;

                     Print("[CONSISTENCY] Trade closed today. TodayReal updated: $",
                           DoubleToString(g_consistencyTodayReal, 2),
                           " | PnL: $", DoubleToString(fullPnL, 2));
                  }
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

//+------------------------------------------------------------------+
//| Update trading enabled status                                     |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Sum floating P&L of all managed open positions                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Sum floating P&L of ALL open positions in the account             |
//+------------------------------------------------------------------+
double GetTotalOpenFloating()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         // For Prop Firm consistency rules, ALL floating profit counts
         // regardless of the strategy or manual entry
         total += position.Profit() + position.Swap();
      }
   }
   return total;
}

//+------------------------------------------------------------------+
//| Scan deal history to compute consistency metrics                  |
//+------------------------------------------------------------------+
void CalculateConsistencyMetrics()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d", now.year, now.mon, now.day));

   // Full history scan: once per day (or on first run)
   if(!g_consistencyScanned || g_consistencyScanDate != todayStart)
   {
      g_consistencyScanned   = true;
      g_consistencyScanDate  = todayStart;
      g_consistencyBestDay   = 0;
      g_consistencyTotal     = 0;
      g_consistencyTodayReal = 0;

      // Scan entire history grouped by calendar day
      HistorySelect(0, TimeCurrent());
      int total = HistoryDealsTotal();

      // Map day -> profit using a simple two-pass approach
      // Pass 1: collect all exit deals
      datetime dayBucket  = 0;
      double   dayProfit  = 0;
      double   prevDay    = 0;

      // We need per-day sums; iterate chrono order (history is chronological)
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
         
         // Consistency rule: must include ALL trades in the account (prop firm view)
         // Exclude balance operations (deposits/withdrawals)
         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double   profit   = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                           + HistoryDealGetDouble(ticket, DEAL_SWAP)
                           + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         // Determine day bucket for this deal
         MqlDateTime dt;
         TimeToStruct(dealTime, dt);
         datetime thisDayStart = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

         if(thisDayStart != dayBucket)
         {
            // Flush previous day
            if(dayBucket > 0 && dayBucket < todayStart)
            {
               if(dayProfit > g_consistencyBestDay) g_consistencyBestDay = dayProfit;
               if(dayProfit > 0)                    g_consistencyTotal  += dayProfit;
            }
            dayBucket = thisDayStart;
            dayProfit = 0;
         }

         if(thisDayStart == todayStart)
            g_consistencyTodayReal += profit;   // Today's realized
         else
            dayProfit += profit;
      }

      // Flush the last historical day (not today)
      if(dayBucket > 0 && dayBucket < todayStart)
      {
         if(dayProfit > g_consistencyBestDay) g_consistencyBestDay = dayProfit;
         if(dayProfit > 0)                    g_consistencyTotal  += dayProfit;
      }
   }
   else
   {
      // Lightweight update: just recalculate today's realized from last known trade count
      // (OnTrade already updates g_consistencyTodayReal via AddTradeResult flow,
      //  but we re-scan today only to be safe when a new deal comes in)
      // Nothing extra needed here — OnTrade handles incremental updates.
   }

   // Compute ratio (skip if not enough total profit — new account)
   double ratio = 0;
   if(g_consistencyTotal >= InpConsistencyMinUSD && g_consistencyTotal > 0)
   {
      // Best day for ratio purposes: max(historical best, today's realized)
      double effectiveBest = MathMax(g_consistencyBestDay, g_consistencyTodayReal);
      double effectiveTotal = g_consistencyTotal + MathMax(g_consistencyTodayReal, 0);
      if(effectiveTotal > 0)
         ratio = effectiveBest / effectiveTotal;
   }

   // Block flag
   double limitRatio = InpConsistencyMaxPct / 100.0;
   g_consistencyBlocked = (ratio >= limitRatio && g_consistencyTotal >= InpConsistencyMinUSD);

   // Publish to GlobalVariables
   GlobalVariableSet(GV_CONSISTENCY_BEST_DAY, MathMax(g_consistencyBestDay, g_consistencyTodayReal));
   GlobalVariableSet(GV_CONSISTENCY_TOTAL,    g_consistencyTotal + MathMax(g_consistencyTodayReal, 0));
   GlobalVariableSet(GV_CONSISTENCY_RATIO,    ratio);
   GlobalVariableSet(GV_CONSISTENCY_BLOCKED,  g_consistencyBlocked ? 1 : 0);

   static bool s_skippedLogged = false;
   if(g_consistencyTotal < InpConsistencyMinUSD)
   {
      if(!s_skippedLogged)
      {
         Print("[CONSISTENCY] Skipped: Total profit below minimum ($",
               DoubleToString(g_consistencyTotal, 2), " < $", DoubleToString(InpConsistencyMinUSD, 2), ")");
         s_skippedLogged = true;
      }
   }
   else
   {
      s_skippedLogged = false; // Reset if we pass the minimum
   }
}

//+------------------------------------------------------------------+
//| Proactive close: shut positions before they push today over cap   |
//+------------------------------------------------------------------+
void CheckConsistencyProactiveClose()
{
   // Skip if not enough accumulated profit (new account)
   if(g_consistencyTotal < InpConsistencyMinUSD) return;

   double limitRatio       = InpConsistencyMaxPct / 100.0;
   double openFloat        = GetTotalOpenFloating();

   // Only consider closing when floating profit is POSITIVE (don't close losers for this reason)
   if(openFloat <= 0) return;

   double projectedToday   = g_consistencyTodayReal + openFloat;
   double projectedBest    = MathMax(g_consistencyBestDay, projectedToday);
   double projectedTotal   = g_consistencyTotal + MathMax(projectedToday, 0);
   double projectedRatio   = (projectedTotal > 0) ? projectedBest / projectedTotal : 0;

   if(projectedRatio >= limitRatio)
   {
      Print("[CONSISTENCY] BREACH IMMINENT: Projected ratio ",
            DoubleToString(projectedRatio * 100, 1), "% >= ",
            DoubleToString(InpConsistencyMaxPct, 1), "%");
      Print("[CONSISTENCY] TodayReal=$", DoubleToString(g_consistencyTodayReal, 2),
            " | OpenFloat=$", DoubleToString(openFloat, 2),
            " | Projected=$", DoubleToString(projectedToday, 2));
      Print("[CONSISTENCY] BestDay(proj)=$", DoubleToString(projectedBest, 2),
            " | Total(proj)=$", DoubleToString(projectedTotal, 2));
      CloseAllPositions("Consistency Rule: Best day limit approaching " +
                        DoubleToString(projectedRatio * 100, 1) + "%");
      // Force a metric refresh after the close
      g_consistencyScanned = false;
   }
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

   // Pause / reduce risk when Consistency Rule is breached
   if(InpEnableConsistencyRule && g_consistencyTotal >= InpConsistencyMinUSD)
   {
      double ratio        = GlobalVariableGet(GV_CONSISTENCY_RATIO);
      double limitRatio   = InpConsistencyMaxPct / 100.0;
      double warnRatio    = limitRatio * (InpConsistencyWarnPct / 100.0);

      if(g_consistencyBlocked)
      {
         enabled = false;
         reason  = "Consistency Rule: Best day = " +
                   DoubleToString(ratio * 100.0, 1) + "% >= " +
                   DoubleToString(InpConsistencyMaxPct, 1) + "% limit";
      }
      else if(ratio >= warnRatio)
      {
         // Warning zone: reduce multiplier to 50% to slow further gains
         double currentMult = GlobalVariableGet(GV_RISK_MULTIPLIER);
         GlobalVariableSet(GV_RISK_MULTIPLIER, MathMin(currentMult, 0.5));
         static bool warnLogged = false;
         if(!warnLogged)
         {
            Print("[CONSISTENCY] WARNING: Ratio ", DoubleToString(ratio * 100.0, 1),
                  "% approaching limit. Risk multiplier capped at 0.50.");
            warnLogged = true;
         }
      }
      else
      {
         static bool warnLogged = false;
         warnLogged = false; // reset so warning prints again if ratio climbs back
      }
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

   double cRatio = 0, cBestDay = 0, cTotal = 0;
   bool cBlocked = false;
   if(InpEnableConsistencyRule)
   {
      cRatio = GlobalVariableGet(GV_CONSISTENCY_RATIO) * 100.0;
      cBestDay = GlobalVariableGet(GV_CONSISTENCY_BEST_DAY);
      cTotal = GlobalVariableGet(GV_CONSISTENCY_TOTAL);
      cBlocked = (GlobalVariableGet(GV_CONSISTENCY_BLOCKED) == 1);
   }

   double dailyProfit = GlobalVariableGet(GV_DAILY_PROFIT);

   // Performance: Check if update needed (dirty flag system)
   bool needsUpdate = g_dashCache.forceUpdate ||
                      MathAbs(g_dashCache.lastDD - dd) > 0.01 ||
                      MathAbs(g_dashCache.lastPF - pf) > 0.01 ||
                      MathAbs(g_dashCache.lastExposure - exposure) > 0.01 ||
                      MathAbs(g_dashCache.lastRiskMult - riskMult) > 0.001 ||
                      g_dashCache.lastTradingEnabled != tradingEnabled ||
                      MathAbs(g_dashCache.lastConsistencyRatio - cRatio) > 0.1 ||
                      g_dashCache.lastConsistencyBlocked != cBlocked ||
                      MathAbs(g_dashCache.lastDailyProfit - dailyProfit) > 0.01 ||
                      g_dashCache.lastDailyTarget != g_dailyTargetHit ||
                      g_dashCache.positionsCount != currentPositions ||
                      (TimeCurrent() - g_dashCache.lastUpdateTime) > 10;

   if(!needsUpdate) return; // Skip rendering if nothing changed

   // Update cache
   g_dashCache.lastDD = dd;
   g_dashCache.lastPF = pf;
   g_dashCache.lastExposure = exposure;
   g_dashCache.lastRiskMult = riskMult;
   g_dashCache.lastTradingEnabled = tradingEnabled;
   g_dashCache.lastConsistencyRatio = cRatio;
   g_dashCache.lastConsistencyBlocked = cBlocked;
   g_dashCache.lastDailyProfit = dailyProfit;
   g_dashCache.lastDailyTarget = g_dailyTargetHit;
   g_dashCache.lastUpdateTime = TimeCurrent();
   g_dashCache.positionsCount = currentPositions;
   g_dashCache.forceUpdate = false;

   // Create visual dashboard with graphical objects
   CreateVisualDashboard(dd, pf, exposure, riskMult, tradingEnabled,
                         cRatio, cBestDay, cTotal, cBlocked, dailyProfit);
}

//+------------------------------------------------------------------+
//| Create Visual Dashboard with Graphics Objects                    |
//+------------------------------------------------------------------+
void CreateVisualDashboard(double dd, double pf, double exposure, double riskMult,
                          bool tradingEnabled, double cRatio, double cBestDay,
                          double cTotal, bool cBlocked, double dailyProfit)
{
   int x = 15, y = 25;
   int lineHeight = 20;
   int sectionGap = 10;
   color bgColor = C'20,20,30';
   color textColor = clrWhiteSmoke;

   // Main Panel Background
   CreateRectLabel("GovBG", x, y, 600, 480, bgColor, clrNONE, 1, 0);

   // Header Section
   y += 10;
   color statusColor = tradingEnabled ? clrLimeGreen : clrOrangeRed;
   string statusText = tradingEnabled ? "● ONLINE" : "● PAUSED";
   CreateLabel("GovHeader", x+10, y, "🧠 PORTFOLIO GOVERNOR v2.0", clrGold, 12, true);
   CreateLabel("GovStatus", x+380, y, statusText, statusColor, 11, true);
   CreateLabel("GovTime", x+490, y, TimeToString(TimeCurrent(), TIME_SECONDS), textColor, 9, false);

   y += lineHeight + sectionGap;
   CreateSeparator("GovSep1", x+10, y, 580, clrDimGray);

   // Main Metrics Section
   y += sectionGap + 5;
   CreateLabel("GovMetricsTitle", x+10, y, "📊 CORE METRICS", clrCornflowerBlue, 10, true);

   y += lineHeight;
   // Drawdown with color coding
   color ddColor = dd < InpDD_Normal ? clrLimeGreen :
                   dd < InpDD_Reduced ? clrYellow :
                   dd < InpDD_Pause ? clrOrange : clrRed;
   CreateLabel("GovDDLabel", x+20, y, "Drawdown:", textColor, 9, false);
   CreateLabel("GovDDValue", x+150, y, DoubleToString(dd, 2) + "%", ddColor, 10, true);
   CreateProgressBar("GovDDBar", x+250, y-2, 150, 14, dd, InpDD_Pause, ddColor, bgColor);
   CreateLabel("GovDDLimit", x+410, y, "Limit: " + DoubleToString(InpDD_Pause, 1) + "%", clrGray, 8, false);

   y += lineHeight;
   // Profit Factor with color coding
   color pfColor = pf >= InpPF_Normal ? clrLimeGreen :
                   pf >= InpPF_Reduced ? clrYellow :
                   pf >= InpPF_Pause ? clrOrange : clrRed;
   CreateLabel("GovPFLabel", x+20, y, "Profit Factor:", textColor, 9, false);
   CreateLabel("GovPFValue", x+150, y, DoubleToString(pf, 2), pfColor, 10, true);
   string pfTarget = "Target: >" + DoubleToString(InpPF_Normal, 1);
   CreateLabel("GovPFTarget", x+250, y, pfTarget, clrGray, 8, false);
   CreateLabel("GovPFTrades", x+410, y, "Trades: " + IntegerToString(g_tradeCount), clrGray, 8, false);

   y += lineHeight;
   // Portfolio Exposure with progress bar
   color exposureColor = exposure < InpMaxPortfolioRisk*0.6 ? clrLimeGreen :
                        exposure < InpMaxPortfolioRisk*0.85 ? clrYellow : clrOrange;
   CreateLabel("GovExpLabel", x+20, y, "Portfolio Risk:", textColor, 9, false);
   CreateLabel("GovExpValue", x+150, y, DoubleToString(exposure, 2) + "%", exposureColor, 10, true);
   CreateProgressBar("GovExpBar", x+250, y-2, 150, 14, exposure, InpMaxPortfolioRisk, exposureColor, bgColor);
   CreateLabel("GovExpLimit", x+410, y, "Max: " + DoubleToString(InpMaxPortfolioRisk, 1) + "%", clrGray, 8, false);

   y += lineHeight;
   // Risk Multiplier
   color multColor = riskMult >= 1.0 ? clrLimeGreen :
                    riskMult >= 0.7 ? clrYellow : clrOrange;
   CreateLabel("GovMultLabel", x+20, y, "Risk Multiplier:", textColor, 9, false);
   CreateLabel("GovMultValue", x+150, y, DoubleToString(riskMult, 2) + "x", multColor, 10, true);
   int multPct = (int)(riskMult * 100);
   CreateProgressBar("GovMultBar", x+250, y-2, 150, 14, multPct, 100, multColor, bgColor);
   CreateLabel("GovMultInfo", x+410, y, "Positions: " + IntegerToString(PositionsTotal()), clrGray, 8, false);

   y += lineHeight + sectionGap;
   CreateSeparator("GovSep2", x+10, y, 580, clrDimGray);

   // Daily Performance Section
   y += sectionGap + 5;
   CreateLabel("GovDailyTitle", x+10, y, "📅 DAILY PERFORMANCE", clrCornflowerBlue, 10, true);

   y += lineHeight;
   color dailyColor = dailyProfit > 0 ? clrLimeGreen : dailyProfit < 0 ? clrRed : clrGray;
   CreateLabel("GovDailyLabel", x+20, y, "Daily P&L:", textColor, 9, false);
   CreateLabel("GovDailyValue", x+150, y, DoubleToString(dailyProfit, 2) + "%", dailyColor, 10, true);

   if(InpDailyTarget > 0)
   {
      double targetPct = (dailyProfit / InpDailyTarget) * 100;
      targetPct = MathMax(0, MathMin(targetPct, 100));
      color targetColor = g_dailyTargetHit ? clrLimeGreen : clrCornflowerBlue;
      CreateProgressBar("GovTargetBar", x+250, y-2, 150, 14, targetPct, 100, targetColor, bgColor);
      string targetStatus = g_dailyTargetHit ? "✅ ACHIEVED" : DoubleToString(InpDailyTarget, 1) + "% Goal";
      CreateLabel("GovTargetStatus", x+410, y, targetStatus, targetColor, 8, true);
   }

   y += lineHeight;
   double dailyDD = GlobalVariableGet(GV_DAILY_DD);
   color dailyDDColor = dailyDD < InpDailyMaxDD*0.5 ? clrLimeGreen :
                       dailyDD < InpDailyMaxDD*0.8 ? clrYellow : clrOrange;
   CreateLabel("GovDailyDDLabel", x+20, y, "Daily DD:", textColor, 9, false);
   CreateLabel("GovDailyDDValue", x+150, y, DoubleToString(dailyDD, 2) + "%", dailyDDColor, 10, true);
   CreateProgressBar("GovDailyDDBar", x+250, y-2, 150, 14, dailyDD, InpDailyMaxDD, dailyDDColor, bgColor);
   CreateLabel("GovDailyDDLimit", x+410, y, "Limit: " + DoubleToString(InpDailyMaxDD, 1) + "%", clrGray, 8, false);

   y += lineHeight;
   double weeklyDD = GlobalVariableGet(GV_WEEKLY_DD);
   color weeklyDDColor = weeklyDD < InpWeeklyMaxDD*0.5 ? clrLimeGreen :
                        weeklyDD < InpWeeklyMaxDD*0.8 ? clrYellow : clrOrange;
   CreateLabel("GovWeeklyDDLabel", x+20, y, "Weekly DD:", textColor, 9, false);
   CreateLabel("GovWeeklyDDValue", x+150, y, DoubleToString(weeklyDD, 2) + "%", weeklyDDColor, 10, true);
   CreateProgressBar("GovWeeklyDDBar", x+250, y-2, 150, 14, weeklyDD, InpWeeklyMaxDD, weeklyDDColor, bgColor);
   CreateLabel("GovWeeklyDDLimit", x+410, y, "Limit: " + DoubleToString(InpWeeklyMaxDD, 1) + "%", clrGray, 8, false);

   // Consistency Rule Section
   if(InpEnableConsistencyRule)
   {
      y += lineHeight + sectionGap;
      CreateSeparator("GovSep3", x+10, y, 580, clrDimGray);

      y += sectionGap + 5;
      CreateLabel("GovConsistTitle", x+10, y, "⚖️ CONSISTENCY RULE (Prop Firm)", clrCornflowerBlue, 10, true);

      y += lineHeight;
      string cStatus = "";
      color cStatusColor = clrGray;

      if(g_consistencyTotal < InpConsistencyMinUSD)
      {
         cStatus = "⏳ INACTIVE (Below $" + DoubleToString(InpConsistencyMinUSD, 0) + ")";
         cStatusColor = clrGray;
      }
      else if(cBlocked)
      {
         cStatus = "🔴 BLOCKED";
         cStatusColor = clrRed;
      }
      else if(cRatio >= InpConsistencyMaxPct * InpConsistencyWarnPct / 100.0)
      {
         cStatus = "⚠️ WARNING";
         cStatusColor = clrOrange;
      }
      else
      {
         cStatus = "✅ HEALTHY";
         cStatusColor = clrLimeGreen;
      }

      CreateLabel("GovConsistStatus", x+350, y, cStatus, cStatusColor, 10, true);

      y += lineHeight;
      CreateLabel("GovConsistBestLabel", x+20, y, "Best Day:", textColor, 9, false);
      CreateLabel("GovConsistBestValue", x+150, y, "$" + DoubleToString(cBestDay, 2), clrGold, 9, true);
      CreateLabel("GovConsistTotalLabel", x+310, y, "Total:", textColor, 9, false);
      CreateLabel("GovConsistTotalValue", x+400, y, "$" + DoubleToString(cTotal, 2), clrCornflowerBlue, 9, true);

      y += lineHeight;
      CreateLabel("GovConsistRatioLabel", x+20, y, "Best/Total Ratio:", textColor, 9, false);
      color ratioColor = cRatio < InpConsistencyMaxPct*0.5 ? clrLimeGreen :
                        cRatio < InpConsistencyMaxPct*0.85 ? clrYellow : clrOrange;
      CreateLabel("GovConsistRatioValue", x+150, y, DoubleToString(cRatio, 1) + "%", ratioColor, 10, true);
      CreateProgressBar("GovConsistBar", x+250, y-2, 150, 14, cRatio, InpConsistencyMaxPct, ratioColor, bgColor);
      CreateLabel("GovConsistLimit", x+410, y, "Max: " + DoubleToString(InpConsistencyMaxPct, 1) + "%", clrGray, 8, false);

      // Missing profit calculation
      double targetRatio = (InpConsistencyMaxPct - 0.1) / 100.0;
      if(cRatio > targetRatio * 100.0 && cBestDay > 0 && g_consistencyTotal >= InpConsistencyMinUSD)
      {
         double requiredTotal = cBestDay / targetRatio;
         double missing = requiredTotal - cTotal;
         if(missing > 0)
         {
            y += lineHeight;
            CreateLabel("GovConsistMissingLabel", x+20, y, "💰 Missing for Payout:", clrYellow, 9, true);
            CreateLabel("GovConsistMissingValue", x+200, y, "$" + DoubleToString(missing, 2), clrYellow, 10, true);
            CreateLabel("GovConsistGoal", x+350, y, "Goal: $" + DoubleToString(requiredTotal, 2), clrGray, 8, false);
         }
      }
   }

   // Group Risk Section
   y += lineHeight + sectionGap;
   CreateSeparator("GovSep4", x+10, y, 580, clrDimGray);

   y += sectionGap + 5;
   CreateLabel("GovGroupTitle", x+10, y, "🌍 CORRELATION GROUPS", clrCornflowerBlue, 10, true);

   y += lineHeight;
   double usdRisk = GlobalVariableGet(GV_GROUP_USD_RISK);
   CreateGroupRiskLine("USD", x+20, y, usdRisk, InpMaxGroupRisk, textColor, bgColor);

   y += lineHeight;
   double jpyRisk = GlobalVariableGet(GV_GROUP_JPY_RISK);
   CreateGroupRiskLine("JPY", x+20, y, jpyRisk, InpMaxGroupRisk, textColor, bgColor);

   y += lineHeight;
   double gbpRisk = GlobalVariableGet(GV_GROUP_GBP_RISK);
   CreateGroupRiskLine("GBP", x+20, y, gbpRisk, InpMaxGroupRisk, textColor, bgColor);

   y += lineHeight;
   double metalsRisk = GlobalVariableGet(GV_GROUP_METALS_RISK);
   CreateGroupRiskLine("XAU", x+20, y, metalsRisk, InpMaxGroupRisk, textColor, bgColor);

   // Footer - Top 5 Rankings
   y += lineHeight + sectionGap;
   CreateSeparator("GovSep5", x+10, y, 580, clrDimGray);

   y += sectionGap + 5;
   CreateLabel("GovRankTitle", x+10, y, "🏆 TOP SYMBOLS", clrCornflowerBlue, 10, true);

   y += lineHeight - 5;
   string rankTable = rankManager.GetRankingTable(5);
   CreateLabel("GovRankTable", x+20, y, rankTable, textColor, 8, false);

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
