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

input group "═══════ UPDATE FREQUENCY ═══════"
input int    InpUpdateSeconds = 5;             // Update Interval (seconds)

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
   
   g_peakEquity = account.Equity();
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

   Print("===============================================================");
   // Initialize Rank Manager: Auto-Discovery is now active (no manual AddSymbol needed)
   
   // Initialize Dashboard Canvas
   // if(!dashboardCanvas.Init("GovDashboard", 20, 20, 550, 400))
   //    Print("Failed to create dashboard canvas");
      
   Print("  PORTFOLIO GOVERNOR v2.0 V2 DASHBOARD (LITE MODE) READY");
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

   // 3. Update risk multiplier
   UpdateRiskMultiplier();

   // 4. Update trading enabled status
   UpdateTradingStatus();

   // 5. Update dashboard
   UpdateDashboard();

   // 6. Update Ranks (Ranking System)
   rankManager.UpdateRanks();

   // 7. Publish update timestamp
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
   static int lastHistoryCount = 0;
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
//| Dashboard                                                         |
void UpdateDashboard()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);

   // --- CHAMELEON MULTI-STRATEGY DASHBOARD ---
   string text = "🧠 GOVERNOR + CHAMELEON | " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n";
   text += "DD: " + DoubleToString(dd, 2) + "% | PF: " + DoubleToString(pf, 2) + "\n";
   text += "===============================================\n";

   // Get ranking data
   text += rankManager.GetRankingTable(5); // Show Top 5

   // Add Chameleon system status
   text += "===============================================\n";
   text += " CHAMELEON STATUS\n";
   text += "===============================================\n";
   text += GetChameleonStatus();

   Comment(text);
}

//+------------------------------------------------------------------+
//| Get Chameleon System Status                                       |
//+------------------------------------------------------------------+
string GetChameleonStatus()
{
   string text = "";

   // Get all symbols from ranking
   SymbolRank ranks[];
   int symbolCount = rankManager.GetRanks(ranks);

   if(symbolCount == 0) {
      return " No active symbols\n";
   }

   // Header
   text += " Symbol    | Phase     | Strategy  | Stats\n";
   text += "-----------------------------------------------\n";

   // Show status for each symbol
   for(int i = 0; i < MathMin(symbolCount, 8); i++) {
      string symbol = ranks[i].symbol;

      // Check if Chameleon is enabled for this symbol
      if(!IsChameleonEnabled(symbol)) {
         text += StringFormat(" %-9s | LEGACY MODE (Chameleon disabled)\n", symbol);
         continue;
      }

      // Get market phase and active strategy
      int phase = GetSymbolPhase(symbol);
      int strategy = GetSymbolStrategy(symbol);

      string phaseStr = PhaseToString(phase);
      string stratStr = StrategyToString(strategy);

      // Get strategy performance (for active strategy)
      string stats = "N/A";
      if(strategy > 0) {
         int trades = GetStrategyTrades(symbol, strategy);
         if(trades > 0) {
            double wr = GetStrategyWinRate(symbol, strategy);
            double pfactor = GetStrategyProfitFactor(symbol, strategy);
            stats = StringFormat("%dT %.0f%% PF%.1f", trades, wr, pfactor);
         } else {
            stats = "No trades";
         }
      }

      text += StringFormat(" %-9s | %-9s | %-8s | %s\n",
                          symbol, phaseStr, stratStr, stats);
   }

   return text;
}

//+------------------------------------------------------------------+
//| Check if Chameleon is Enabled for Symbol                         |
//+------------------------------------------------------------------+
bool IsChameleonEnabled(string symbol)
{
   string gvName = "GV_CHAMELEON_ACTIVE_" + symbol;
   if(!GlobalVariableCheck(gvName))
      return false;

   return (GlobalVariableGet(gvName) > 0.5);
}

//+------------------------------------------------------------------+
//| Get Symbol Market Phase                                           |
//+------------------------------------------------------------------+
int GetSymbolPhase(string symbol)
{
   // Try to get phase from Market_Phase_Analyzer indicator
   int hPhase = iCustom(symbol, PERIOD_CURRENT, "Market_Phase_Analyzer");
   if(hPhase == INVALID_HANDLE)
      return 4;  // PHASE_UNDEFINED

   double phaseBuf[1];
   if(CopyBuffer(hPhase, 0, 0, 1, phaseBuf) <= 0) {
      IndicatorRelease(hPhase);
      return 4;  // PHASE_UNDEFINED
   }

   IndicatorRelease(hPhase);
   return (int)phaseBuf[0];
}

//+------------------------------------------------------------------+
//| Get Symbol Active Strategy                                        |
//+------------------------------------------------------------------+
int GetSymbolStrategy(string symbol)
{
   string gvName = "GV_CHAMELEON_STRATEGY_" + symbol;
   if(!GlobalVariableCheck(gvName))
      return 0;  // Legacy

   return (int)GlobalVariableGet(gvName);
}

//+------------------------------------------------------------------+
//| Convert Phase to String                                           |
//+------------------------------------------------------------------+
string PhaseToString(int phase)
{
   switch(phase) {
      case 0: return "Dormant";
      case 1: return "Trending";
      case 2: return "Ranging";
      case 3: return "Volatile";
      case 4: return "Undefined";
      default: return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Convert Strategy to String                                        |
//+------------------------------------------------------------------+
string StrategyToString(int strategy)
{
   switch(strategy) {
      case 0: return "Legacy";
      case 1: return "Sniper";
      case 2: return "RubberBd";
      case 3: return "Breakout";
      default: return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Get Strategy Trade Count                                          |
//+------------------------------------------------------------------+
int GetStrategyTrades(string symbol, int strategy)
{
   string gvName = StringFormat("GV_STRAT_%s_%d_TRADES", symbol, strategy);
   if(!GlobalVariableCheck(gvName))
      return 0;

   return (int)GlobalVariableGet(gvName);
}

//+------------------------------------------------------------------+
//| Get Strategy Win Rate                                             |
//+------------------------------------------------------------------+
double GetStrategyWinRate(string symbol, int strategy)
{
   string gvName = StringFormat("GV_STRAT_%s_%d_WR", symbol, strategy);
   if(!GlobalVariableCheck(gvName))
      return 0.0;

   return GlobalVariableGet(gvName) * 100.0;  // Convert to percentage
}

//+------------------------------------------------------------------+
//| Get Strategy Profit Factor                                        |
//+------------------------------------------------------------------+
double GetStrategyProfitFactor(string symbol, int strategy)
{
   string gvName = StringFormat("GV_STRAT_%s_%d_PF", symbol, strategy);
   if(!GlobalVariableCheck(gvName))
      return 0.0;

   return GlobalVariableGet(gvName);
}
//+------------------------------------------------------------------+
