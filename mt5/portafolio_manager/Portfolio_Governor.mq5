//+------------------------------------------------------------------+
//|                                          Portfolio_Governor.mq5  |
//|          🧠 CENTRAL BRAIN V3.0 - Multi-Symbol Risk Controller    |
//|             Manages: Symbol Engines, DB, DD, Correlation         |
//+------------------------------------------------------------------+
#property copyright "Portfolio Governor"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "3.00"
#property description "🧠 Portfolio Governor: Central Risk Brain"
#property description "Run on ONE chart only. Controls all Symbol Engines."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Include\PortfolioGlobals.mqh"
#include "Include\GovernorAllocator.mqh"
#include "Include\DatabaseManager.mqh"
#include "Include\SymbolEngine.mqh"

CGovernorAllocator allocator;
CDatabaseManager   dbManager;

// Forward Declaration
void SeedDefaultConfigs();


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
input int    InpCorrelationLookback = 300;     // Bars for correlation (M15)

input group "═══════ MAGIC NUMBER RANGE ═══════"
input int    InpMagicBase = 100000;            // Magic Number Base
input int    InpMagicRange = 999;              // Magic Number Range (Base to Base+Range)

input group "═══════ UPDATE FREQUENCY ═══════"
input int    InpUpdateSeconds = 1;             // Interval (seconds) - Fast for scalping

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CPositionInfo position;
CAccountInfo  account;

// Managed Soldiers
CSymbolEngine *g_engines[];
int            g_engineCount = 0;

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

// Correlation Engine
struct DynamicCorrelation
{
   string symbol1;
   string symbol2;
   double correlation;
};

// Monitored symbols for dynamic correlation
string g_monitoredSymbols[]; // Updated from DB
DynamicCorrelation g_dynamicMatrix[];
datetime g_lastMatrixUpdate = 0;


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
   
   // Initialize database
   if(!dbManager.Init())
   {
       Print("❌ CRITICAL: Database init failed!");
       return INIT_FAILED;
   }
   
   // Load Configs
   SymbolConfig configs[];
   int totalConfigs = dbManager.LoadSymbolConfigs(configs);
   
   if(totalConfigs == 0)
   {
       Print("⚠️ No configs found in DB. Seeding Default Symbols...");
       SeedDefaultConfigs();
       // Reload after seeding
       totalConfigs = dbManager.LoadSymbolConfigs(configs);
   }
   
   if(totalConfigs > 0)
   {
       ArrayResize(g_engines, totalConfigs);
       g_engineCount = 0;
       
       for(int i=0; i<totalConfigs; i++)
       {
           // Check if symbol exists in Market Watch
           if(!SymbolSelect(configs[i].symbol, true))
           {
               Print("⚠️ Symbol ", configs[i].symbol, " unavailable. Skipping.");
               continue;
           }
           
           g_engines[g_engineCount] = new CSymbolEngine();
           if(g_engines[g_engineCount].Init(configs[i], &dbManager))
           {
               g_engineCount++;
           }
           else
           {
               Print("❌ Failed to init engine for ", configs[i].symbol);
               delete g_engines[g_engineCount];
           }
       }
       // Resize to actual successful inits
       ArrayResize(g_engines, g_engineCount);
       
       // Update Monitored Symbols from Configs
       ArrayResize(g_monitoredSymbols, g_engineCount);
       for(int i=0; i<g_engineCount; i++)
       {
           g_monitoredSymbols[i] = g_engines[i].GetSymbol();
       }
   }
   
   // Initialize Risk/Metrics
   g_peakEquity = account.Equity();
   ArrayResize(g_tradeResults, InpRollingTrades);
   ArrayInitialize(g_tradeResults, 0);

   g_dailyStartEquity = account.Equity();
   g_weeklyStartEquity = account.Equity();
   g_monthlyStartEquity = account.Equity();
   g_lastDayCheck = TimeCurrent();
   g_lastWeekCheck = TimeCurrent();
   g_lastMonthCheck = TimeCurrent();

   Print("===============================================================");
   Print("  PORTFOLIO GOVERNOR v3.0 (CENTRALIZED) ACTIVATED");
   Print("===============================================================");
   Print("  Active Engines: ", g_engineCount);
   Print("  Database: ENABLED");
   Print("===============================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Cleanup Engines
   for(int i=0; i<g_engineCount; i++)
   {
       if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
           delete g_engines[i];
   }
   ArrayResize(g_engines, 0);
   
   dbManager.Close();

   // Mark governor as inactive
   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 0);
   Comment("");
   Print("🧠 Portfolio Governor DEACTIVATED");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Run Governor Logic (Metrics, Risk, Correlation)
   // Throttle only the heavy metrics, but engines might needs faster ticks?
   // We'll throttle logic but run engines every tick or throttle them slightly less.
   
   static datetime lastGovUpdate = 0;
   
   if(TimeCurrent() - lastGovUpdate >= InpUpdateSeconds)
   {
       lastGovUpdate = TimeCurrent();
       
       CheckPeriodReset();
       UpdateCorrelationMatrix();
       CalculatePortfolioMetrics();
       CalculatePeriodDrawdowns();
       UpdateRiskMultiplier();
       UpdateTradingStatus();
       UpdateDashboard();
       GlobalVariableSet(GV_LAST_UPDATE, (double)TimeCurrent());
   }
   
   // 2. Run Symbol Engines (The Army)
   // We run them sequentially. Since MT5 is single-threaded per EA, this is standard.
   // Caution: If many symbols, this loop must be fast.
   
   for(int i=0; i<g_engineCount; i++)
   {
       if(CheckPointer(g_engines[i]) != POINTER_INVALID)
       {
           g_engines[i].OnTick();
       }
   }
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
//| Update Dynamic Correlation Matrix                                 |
//+------------------------------------------------------------------+
void UpdateCorrelationMatrix()
{
   // Update once per hour
   if(TimeCurrent() - g_lastMatrixUpdate < 3600 && ArraySize(g_dynamicMatrix) > 0) return;

   g_lastMatrixUpdate = TimeCurrent();
   int symCount = ArraySize(g_monitoredSymbols);
   
   // Calculate combinations (n * (n-1)) / 2
   int matrixSize = (symCount * (symCount - 1)) / 2;
   ArrayResize(g_dynamicMatrix, matrixSize);
   
   int idx = 0;
   // Print("🔄 DCE: Updating Matrix for ", symCount, " symbols..."); // Reduce noise

   for(int i = 0; i < symCount; i++)
   {
      for(int j = i + 1; j < symCount; j++)
      {
         double corr = CalculatePearsonCorrelation(g_monitoredSymbols[i], g_monitoredSymbols[j]);
         g_dynamicMatrix[idx].symbol1 = g_monitoredSymbols[i];
         g_dynamicMatrix[idx].symbol2 = g_monitoredSymbols[j];
         g_dynamicMatrix[idx].correlation = corr;
         idx++;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Pearson Correlation                                     |
//+------------------------------------------------------------------+
double CalculatePearsonCorrelation(string s1, string s2)
{
   int lookback = InpCorrelationLookback;
   double close1[], close2[];
   
   // Copy M15 closes
   if(CopyClose(s1, PERIOD_M15, 0, lookback, close1) != lookback) return 0;
   if(CopyClose(s2, PERIOD_M15, 0, lookback, close2) != lookback) return 0;
   
   double sum1 = 0, sum2 = 0;
   for(int i=0; i<lookback; i++) { sum1 += close1[i]; sum2 += close2[i]; }
   double mean1 = sum1 / lookback;
   double mean2 = sum2 / lookback;
   
   double num = 0, den1 = 0, den2 = 0;
   for(int i=0; i<lookback; i++)
   {
      double d1 = close1[i] - mean1;
      double d2 = close2[i] - mean2;
      num += d1 * d2;
      den1 += d1 * d1;
      den2 += d2 * d2;
   }
   
   if(den1 * den2 == 0) return 0;
   return num / MathSqrt(den1 * den2);
}

//+------------------------------------------------------------------+
//| Get correlation between two symbols                               |
//+------------------------------------------------------------------+
double GetSymbolCorrelation(string sym1, string sym2)
{
   string s1 = sym1;
   string s2 = sym2;
   StringToUpper(s1);
   StringToUpper(s2);

   // Check dynamic matrix
   for(int i = 0; i < ArraySize(g_dynamicMatrix); i++)
   {
      if((g_dynamicMatrix[i].symbol1 == s1 && g_dynamicMatrix[i].symbol2 == s2) ||
         (g_dynamicMatrix[i].symbol1 == s2 && g_dynamicMatrix[i].symbol2 == s1))
      {
         return g_dynamicMatrix[i].correlation;
      }
   }

   return 0.0; // Unknown
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
            
            // Allow any magic in our monitored range?
            // Actually, with centralized engine, we know the magics. 
            // Simplified check:
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
            {
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                AddTradeResult(profit);
                
                // Also trigger Engine OnTrade if needed?
                for(int j=0; j<g_engineCount; j++)
                {
                    if(g_engines[j].GetSymbol() == HistoryDealGetString(ticket, DEAL_SYMBOL))
                        g_engines[j].OnTrade();
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
         // We monitor ALL positions now, or just ours?
         // Safer to monitor everything for exposure calculation
         string sym = position.Symbol();
         double openPrice = position.PriceOpen();
         double sl = position.StopLoss();
         double volume = position.Volume();
         
         // Calculate risk for this position
         double riskPoints = MathAbs(openPrice - sl);
         if(sl == 0) riskPoints = 0; // No SL, hard to guess risk. Maybe use ATR?
         
         double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         
         double riskMoney = 0;
         if(tickSize > 0 && riskPoints > 0)
            riskMoney = (riskPoints / tickSize) * tickValue * volume;
         
         double riskPercent = (equity > 0) ? (riskMoney / equity) * 100.0 : 0;
         
         totalExposure += riskPercent;
         
         // Add to correlation group
         ENUM_CORR_GROUP group = GetCorrelationGroup(sym);
         groupRisks[(int)group] += riskPercent;
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
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);
   double exposure = GlobalVariableGet(GV_TOTAL_EXPOSURE);
   double riskMult = GlobalVariableGet(GV_RISK_MULTIPLIER);
   bool enabled = GlobalVariableGet(GV_TRADING_ENABLED) == 1;

   double dailyDD = GlobalVariableGet(GV_DAILY_DD);
   double weeklyDD = GlobalVariableGet(GV_WEEKLY_DD);

   string status = enabled ? "ACTIVE" : "PAUSED";
   if(g_dailyLimitHit) status = "DAILY LIMIT";
   else if(g_weeklyLimitHit) status = "WEEKLY LIMIT";
   else if(g_monthlyLimitHit) status = "MONTHLY LIMIT";

   string ddColor = (dd < InpDD_Normal) ? "[OK]" : ((dd < InpDD_Pause) ? "[WARN]" : "[CRIT]");
   string pfColor = (pf >= InpPF_Normal) ? "[OK]" : ((pf >= InpPF_Pause) ? "[WARN]" : "[CRIT]");
   string dailyColor = (dailyDD < InpDailyMaxDD * 0.5) ? "[OK]" : ((dailyDD < InpDailyMaxDD) ? "[WARN]" : "[CRIT]");
   string weeklyColor = (weeklyDD < InpWeeklyMaxDD * 0.5) ? "[OK]" : ((weeklyDD < InpWeeklyMaxDD) ? "[WARN]" : "[CRIT]");

   string text = "===============================================\n";
   text += "  🧠 BRAIN v3.0 (DCE + DB + CENTRALIZED)\n";
   text += "===============================================\n";
   text += "Status: " + status + "\n";
   text += "Engines: " + IntegerToString(g_engineCount) + " Active\n";
   text += "-----------------------------------------------\n";
   text += "Equity: $" + DoubleToString(account.Equity(), 2) + "\n";
   text += ddColor + " Portfolio DD: " + DoubleToString(dd, 2) + "% (Pause: " + DoubleToString(InpDD_Pause, 1) + "%)\n";
   text += pfColor + " Rolling PF: " + DoubleToString(pf, 2) + " (Last " + IntegerToString(MathMin(g_tradeCount, InpRollingTrades)) + " trades)\n";
   text += "-----------------------------------------------\n";
   text += "PERIOD DRAWDOWNS:\n";
   text += dailyColor + " Daily: " + DoubleToString(dailyDD, 2) + "% / " + DoubleToString(InpDailyMaxDD, 1) + "%\n";
   text += weeklyColor + " Weekly: " + DoubleToString(weeklyDD, 2) + "% / " + DoubleToString(InpWeeklyMaxDD, 1) + "%\n";
   text += "-----------------------------------------------\n";
   text += "Exposure: " + DoubleToString(exposure, 2) + "% / " + DoubleToString(InpMaxPortfolioRisk, 1) + "%\n";
   text += "Risk Mult: " + DoubleToString(riskMult * 100, 0) + "%\n";
   text += "Corr Guard: " + (InpUseCorrelationGuard ? "ON" : "OFF") + "\n";
   text += "-----------------------------------------------\n";
   text += "GROUP EXPOSURE:\n";
   text += "  USD: " + DoubleToString(GlobalVariableGet(GV_GROUP_USD_RISK), 2) + "%\n";
   text += "  JPY: " + DoubleToString(GlobalVariableGet(GV_GROUP_JPY_RISK), 2) + "%\n";
   text += "  GBP: " + DoubleToString(GlobalVariableGet(GV_GROUP_GBP_RISK), 2) + "%\n";
   text += "  Metals: " + DoubleToString(GlobalVariableGet(GV_GROUP_METALS_RISK), 2) + "%\n";
   text += "  Indices: " + DoubleToString(GlobalVariableGet(GV_GROUP_INDICES_RISK), 2) + "%\n";
   text += "===============================================\n";

   Comment(text);
}
