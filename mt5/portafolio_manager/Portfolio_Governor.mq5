//+------------------------------------------------------------------+
//|                                          Portfolio_Governor.mq5  |
//|          🧠 CENTRAL BRAIN - Multi-Symbol Risk Controller         |
//|             Manages: DD, Exposure, PF, Correlation Groups        |
//|             GOD MODE v2.1 - CRITICAL HARDENING                   |
//+------------------------------------------------------------------+
#property copyright "Portfolio Governor"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "2.10"
#property strict

// --- INCLUDES ---
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Include\PortfolioGlobals.mqh"
#include "Include\GovernorAllocator.mqh"
#include "Include\PortfolioMath.mqh"
#include "Include\Engines\SymbolEngineWrapper.mqh"
#include "Include\SymbolDatabase.mqh"
#include "Include\KillzoneDatabase.mqh"

// --- GOD MODE MODULES ---
#include "Include\KillSwitch.mqh"
#include "Include\LiquidityGuard.mqh"
#include "Include\SmartExecution.mqh"
#include "Include\MLRegimeDetector.mqh"
#include "Include\PortfolioOptimizer.mqh"
#include "Include\Dashboard.mqh"
#include "Include\DrawdownRecovery.mqh"
#include "Include\Lib\DatabaseManager.mqh"


// Note: NewsFilter and Kelly are handled at engine level (SymbolEngineWrapper), not portfolio level

// --- GLOBAL OBJECTS ---
CGovernorAllocator   allocator;
CTrade               g_trade;
CPositionInfo        position;
CAccountInfo         account;

// Advanced Modules
CKillSwitch          g_killSwitch;
CLiquidityGuard      g_liquidityGuard;
CSmartExecution      g_smartExec;
CMLRegimeDetector    g_mlRegime;
CPortfolioOptimizer  g_optimizer;
CDashboard          g_dashboard;
CDrawdownRecovery    g_recovery;
CDatabaseManager     g_db;


// --- INPUTS (Simplified for View) ---
input double InpMaxDrawdownPercent = 10.0;
input double InpMaxDailyLoss = 5.0;

// --- POSITION MANAGEMENT ---
input group "=== POSITION LIMITS (ICT SNIPER MODE - M15) ==="
input int    InpMaxGlobalPositions = 1;  // Max positions across ALL pairs (1=Sniper, 2-3=Balanced)
input bool   InpCountOnlyGovernorPositions = true;  // Count only Governor trades (ignore manual/other EAs)
input string InpPositionNote = "1 = Best for M15 | 2-3 = Experienced only | M15 = ICT sweet spot"; // Info

// --- ADAPTIVE CONFLUENCE RANKING ---
input group "=== ADAPTIVE CONFLUENCE (Percentile Ranking) ==="
input int    InpTopSymbolsToTrade = 1;   // Trade only top N ranked symbols per cycle (1=Best only, 2=Top 2)
input double InpMinScoreFloor = 10.0;     // GOD LEVEL: Min 10/30 (33%) - ELITE≥18, STRONG≥14, GOOD≥10
input string InpRankingNote = "GOD LEVEL 30-point confluence: Elite ≥18 | Strong ≥14 | Good ≥10"; // Info

// --- PERFORMANCE ---
input group "=== PERFORMANCE (VPS Optimization) ==="
input bool   InpEnableDashboard = false;  // Enable visual dashboard (disable for VPS/Wine performance)

// --- NOTIFICATIONS ---
input group "=== NOTIFICATIONS ==="
input bool   InpEnablePushNotifications = true; // Send mobile push notifications on trade entry

// --- STATE ---
string g_activeSymbols[];
CSymbolEngineWrapper *g_engines[];      // The Engine Room
MARKET_REGIME g_currentRegime = REGIME_RANGE;
ENUM_CURRENT_SESSION g_lastSession = SESSION_DEAD_ZONE; // Track session changes

// --- PERFORMANCE TRACKING ---
datetime g_initTime = 0;                // EA start time (for uptime)
double   g_dailyStartBalance = 0;       // Balance at start of day
datetime g_lastDayCheck = 0;            // Last day checked
int      g_totalWins = 0;               // Total winning trades
int      g_totalLosses = 0;             // Total losing trades
double   g_totalWinAmount = 0;          // Sum of all winning trades
double   g_totalLossAmount = 0;         // Sum of all losing trades (absolute)
double   g_totalProfitGross = 0;        // Gross profit
double   g_totalLossGross = 0;          // Gross loss (absolute)
datetime g_lastHeartbeat = 0;           // Last heartbeat log (10min periodic)
datetime g_lastDealProcessTime = 0;     // Last processed deal time (persistent tracking)
datetime g_lastEngineInitTime = 0;      // Last engine init (stagger to prevent CPU spikes)

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("🧠 INITIALIZING PORTFOLIO GOVERNOR (GOD MODE v2.1)...");

   // Init Modules
   g_killSwitch.Init(InpMaxDrawdownPercent, InpMaxDailyLoss, 100, 5);
   g_liquidityGuard.Init(50, 0.3);
   g_smartExec.Init(&g_liquidityGuard, 10);
   // Initialize dashboard only if enabled
   if(InpEnableDashboard)
      g_dashboard.Init();

   // Initialize Database
   if(!g_db.Init())
   {
      Print("⚠️ WARNING: Database initialization failed. Falling back to CSV/GlobalVars.");
   }


   // Recovery Init - FORCE RESET in Backtesting to prevent stale data
   if(MQLInfoInteger(MQL_TESTER))
   {
      // Backtest: Always reset peak equity to starting balance
      GlobalVariableSet(GV_PEAK_EQUITY, account.Equity());
      Print("📊 BACKTEST MODE: Reset Peak Equity to $", DoubleToString(account.Equity(), 2));
   }
   else if(GlobalVariableCheck(GV_PEAK_EQUITY) == false)
   {
      // Live: Only set if doesn't exist
      GlobalVariableSet(GV_PEAK_EQUITY, account.Equity());
   }

   g_recovery.Update(); // Set initial scaler

   // Performance Tracking Init
   g_initTime = TimeCurrent();
   g_dailyStartBalance = account.Balance();
   g_lastDayCheck = TimeCurrent();

   // Load historical stats from global variables (persist across restarts)
   if(MQLInfoInteger(MQL_TESTER))
   {
      // Backtest: Reset all stats to zero
      g_totalWins = 0;
      g_totalLosses = 0;
      g_totalWinAmount = 0;
      g_totalLossAmount = 0;
      g_totalProfitGross = 0;
      g_totalLossGross = 0;
      Print("📊 BACKTEST MODE: Reset all performance stats");
   }
    else
    {
       // Live: Load from global variables if they exist
       if(GlobalVariableCheck("GOV_TotalWins"))
          g_totalWins = (int)GlobalVariableGet("GOV_TotalWins");
       if(GlobalVariableCheck("GOV_TotalLosses"))
          g_totalLosses = (int)GlobalVariableGet("GOV_TotalLosses");
       if(GlobalVariableCheck("GOV_TotalWinAmount"))
          g_totalWinAmount = GlobalVariableGet("GOV_TotalWinAmount");
       if(GlobalVariableCheck("GOV_TotalLossAmount"))
          g_totalLossAmount = GlobalVariableGet("GOV_TotalLossAmount");
       if(GlobalVariableCheck("GOV_TotalProfitGross"))
          g_totalProfitGross = GlobalVariableGet("GOV_TotalProfitGross");
       if(GlobalVariableCheck("GOV_TotalLossGross"))
          g_totalLossGross = GlobalVariableGet("GOV_TotalLossGross");
       if(GlobalVariableCheck("GOV_LastDealTime"))
          g_lastDealProcessTime = (datetime)GlobalVariableGet("GOV_LastDealTime");
    }

   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 1);
   EventSetTimer(1);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_dashboard.Destroy();
   g_db.Close();


   // Save performance stats to global variables (ONLY in live mode, not backtesting)
   if(!MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariableSet("GOV_TotalWins", g_totalWins);
      GlobalVariableSet("GOV_TotalLosses", g_totalLosses);
      GlobalVariableSet("GOV_TotalWinAmount", g_totalWinAmount);
      GlobalVariableSet("GOV_TotalLossAmount", g_totalLossAmount);
      GlobalVariableSet("GOV_TotalProfitGross", g_totalProfitGross);
      GlobalVariableSet("GOV_TotalLossGross", g_totalLossGross);
      Print("💾 Stats saved to global variables");
   }

   // Clean up Engines
   for(int i=0; i<ArraySize(g_engines); i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC) delete g_engines[i];
   }
   ArrayResize(g_engines, 0);

   Print("🧠 Portfolio Governor shutdown - Stats saved");
}

//+------------------------------------------------------------------+
//| TICK (Safety)                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   g_killSwitch.OnTick(); // Update Monitors

   if(!g_killSwitch.CheckSafety())
   {
      string killReason = "SAFETY_TRIGGER"; // Simplify for now
      if(InpEnableDashboard)
         g_dashboard.Update("💀 KILLED", EnumToString(g_currentRegime), account.Equity(), 0, 0, "EMERGENCY", "DISCONNECTED", 999);
      return;
   }
}

//+------------------------------------------------------------------+
//| TRADE EVENT HANDLER (Performance Tracking)                        |
//| FIX: Persistent deal tracking to prevent double counting          |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Select only NEW deals since last checkpoint (incremental selection)
   if(!HistorySelect(g_lastDealProcessTime, TimeCurrent()))
      return;
   
   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0) return;
   
   datetime latestDealTime = g_lastDealProcessTime;
   
   // Process ALL new deals (not just last 10)
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      // Only count OUT deals (position closures)
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      
      // MAGIC FILTER: Only count our Governor trades (magic 1000-1999)
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic < 1000 || magic >= 2000)
         continue;
      
      // Calculate net profit
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double netProfit = profit + commission + swap;
      
      // Track latest deal time for checkpoint
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dealTime > latestDealTime)
         latestDealTime = dealTime;
      
      // Update statistics
      if(netProfit > 0)
      {
         g_totalWins++;
         g_totalWinAmount += netProfit;
         g_totalProfitGross += netProfit;
      }
      else if(netProfit < 0)
      {
         g_totalLosses++;
         g_totalLossAmount += MathAbs(netProfit);
         g_totalLossGross += MathAbs(netProfit);
      }
   }
   
   // Update checkpoint if any new deals were processed
   if(latestDealTime > g_lastDealProcessTime)
   {
      g_lastDealProcessTime = latestDealTime;
      
      // Save checkpoint and totals to Global Variables (live mode only)
      if(!MQLInfoInteger(MQL_TESTER))
      {
         GlobalVariableSet("GOV_LastDealTime", (double)g_lastDealProcessTime);
         GlobalVariableSet("GOV_TotalWins", g_totalWins);
         GlobalVariableSet("GOV_TotalLosses", g_totalLosses);
         GlobalVariableSet("GOV_TotalWinAmount", g_totalWinAmount);
         GlobalVariableSet("GOV_TotalLossAmount", g_totalLossAmount);
         GlobalVariableSet("GOV_TotalProfitGross", g_totalProfitGross);
         GlobalVariableSet("GOV_TotalLossGross", g_totalLossGross);
      }
   }
}

//+------------------------------------------------------------------+
//| TIMER (Logic)                                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_killSwitch.IsEnabled()) return;

   // 0. Check for new day (reset daily balance tracking)
   MqlDateTime dtCurrent;
   TimeCurrent(dtCurrent);
   MqlDateTime dtLastCheck;
   TimeToStruct(g_lastDayCheck, dtLastCheck);

   if(dtCurrent.day != dtLastCheck.day || dtCurrent.mon != dtLastCheck.mon || dtCurrent.year != dtLastCheck.year)
   {
      g_dailyStartBalance = account.Balance();
      g_lastDayCheck = TimeCurrent();
      Print("📅 New trading day - Daily balance reset to ", g_dailyStartBalance);
   }

   // 1. Update Universe & Engines
   UpdateUniverse();

   // 1.5. Heartbeat Log (every 10 minutes)
   if(TimeCurrent() - g_lastHeartbeat >= 600) // 600 sec = 10 min
   {
      PrintHeartbeat();
      g_lastHeartbeat = TimeCurrent();
   }

   // 2. Regime Detection with Confidence
   string leader = (ArraySize(g_activeSymbols) > 0) ? g_activeSymbols[0] : "EURUSD";
   RegimePrediction pred = g_mlRegime.DetectRegime(leader);
   if(pred.confidence > 0.6)
      g_currentRegime = pred.regime;

   // 2.5 GLOBAL POSITION LIMIT CHECK (ICT Sniper Mode)
   int globalPositions = GetGlobalPositionCount();  // FIX: Use magic-filtered count
   if(globalPositions >= InpMaxGlobalPositions)
   {
      // Already at max positions - skip execution loop
      // This enforces "one perfect trade" ICT methodology
      return;  // Don't scan for new entries
   }

   // 2.6 ADAPTIVE CONFLUENCE RANKING (Percentile System)
   // Collect all scores, rank them, allow only top N to trade
   int totalEngines = ArraySize(g_engines);

   // Health Monitor (Every 5 minutes)
   static datetime lastHealthMonitor = 0;
   if(TimeCurrent() - lastHealthMonitor > 300)
   {
       for(int i=0; i<totalEngines; i++)
       {
           if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
           {
               string health = g_engines[i].GetHealthStatus();
               if(health != "HEALTHY")
               {
                   Print("⚠️ ENGINE HEALTH | ", g_engines[i].m_symbol, 
                         " | Status: ", health, 
                         " | Recovery attempts: ", g_engines[i].m_recoveryAttempts);
                         
                   // Debug detail if critical
                   if(g_engines[i].m_recoveryAttempts >= 3)
                       g_engines[i].DebugIndicatorStatus();
               }
           }
       }
       lastHealthMonitor = TimeCurrent();
   }

   // Step 0: Pre-calculate scores for ranking (CRITICAL - must happen before ranking)
   for(int i=0; i<totalEngines; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         g_engines[i].UpdateScoresForRanking();
      }
   }

   // Step 1: Collect all scores
   struct SymbolRank {
      int engineIndex;
      double score;
   };
   SymbolRank rankings[];
   ArrayResize(rankings, totalEngines);

   for(int i=0; i<totalEngines; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         rankings[i].engineIndex = i;
         rankings[i].score = g_engines[i].GetBestConfluenceScore();
      }
   }

   // Step 2: Sort by score (descending - highest first)
   for(int i=0; i<totalEngines-1; i++)
   {
      for(int j=i+1; j<totalEngines; j++)
      {
         if(rankings[j].score > rankings[i].score)
         {
            // Swap
            SymbolRank temp = rankings[i];
            rankings[i] = rankings[j];
            rankings[j] = temp;
         }
      }
   }

   // Step 3: Set trading permissions - only top N can trade
   static datetime lastRankLog = 0;
   bool shouldLog = (TimeCurrent() - lastRankLog >= 10);
   
   if(shouldLog) lastRankLog = TimeCurrent();

   for(int i=0; i<totalEngines; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         // Find this engine's rank
         int rank = -1;
         for(int r=0; r<totalEngines; r++)
         {
            if(rankings[r].engineIndex == i)
            {
               rank = r;
               break;
            }
         }

         // Allow trading if:
         // 1. Ranked in top N positions
         // 2. Score meets minimum safety floor
         bool isTopRanked = (rank >= 0 && rank < InpTopSymbolsToTrade);
         bool meetsMinimum = (g_engines[i].GetBestConfluenceScore() >= InpMinScoreFloor);
         bool allowed = isTopRanked && meetsMinimum;

         g_engines[i].SetTradingPermission(allowed);

         // VERBOSE DEBUG: Log ALL ranking decisions (Throttled)
         if(shouldLog)
         {
             if(allowed)
             {
                Print("✅ RANK #", rank+1, ": ", g_engines[i].m_symbol,
                      " | Score: ", DoubleToString(g_engines[i].GetBestConfluenceScore(), 2),
                      " | STATUS: ALLOWED TO TRADE");
             }
             else if(rank >= 0 && rank < 8)  // Log top 8 (even if blocked)
             {
                Print("⏸️ RANK #", rank+1, ": ", g_engines[i].m_symbol,
                      " | Score: ", DoubleToString(g_engines[i].GetBestConfluenceScore(), 2),
                      " | BLOCKED (isTop=", (isTopRanked ? "YES" : "NO"),
                      ", meetsMin=", (meetsMinimum ? "YES" : "NO"), ")");
             }
         }
      }
   }

   // 2.9 DEBUG: Confirm top-ranked engines before execution
   if(shouldLog)
   {
       Print("📊 PRE-EXECUTION RANKING CONFIRMATION:");
       for(int i=0; i<MathMin(3, totalEngines); i++)  // Show top 3
       {
          int idx = rankings[i].engineIndex;
          if(CheckPointer(g_engines[idx]) == POINTER_DYNAMIC)
          {
             Print("  #", i+1, ": ", g_engines[idx].m_symbol,
                   " | Score: ", DoubleToString(rankings[i].score, 2),
                   " | AllowedFlag: ", (g_engines[idx].IsAllowedToTrade() ? "TRUE" : "FALSE"));
          }
       }
   }

   // 3. EXECUTION LOOP (The Heartbeat)
   // DEBUG: Count initialized engines
   int validEngines = 0;
   for(int i=0; i<totalEngines; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
         validEngines++;
   }
   static datetime lastEngineLog = 0;
   if(TimeCurrent() - lastEngineLog >= 60)  // Log once per minute
   {
      Print("🔧 ENGINE STATUS: ", validEngines, "/", totalEngines, " initialized");
      lastEngineLog = TimeCurrent();
   }
   
   for(int i=0; i<totalEngines; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         g_engines[i].OnTick(); // Triggers Scan -> Signal -> Trade (if allowed by ranking)
      }
   }

   // 4. Risk Parity Optimization
   g_optimizer.BalanceRiskContributions(g_activeSymbols);

   // 5. Recovery Scaling
   g_recovery.Update();

   // 6. Calculate Performance Metrics
   double todayPnL = account.Equity() - g_dailyStartBalance;
   int totalTrades = g_totalWins + g_totalLosses;
   double winRate = (totalTrades > 0) ? (g_totalWins / (double)totalTrades) * 100.0 : 0.0;
   double profitFactor = (g_totalLossGross > 0) ? (g_totalProfitGross / g_totalLossGross) : 0.0;
   double avgWin = (g_totalWins > 0) ? (g_totalWinAmount / g_totalWins) : 0.0;
   double avgLoss = (g_totalLosses > 0) ? (g_totalLossAmount / g_totalLosses) : 0.0;
   int uptimeMinutes = (int)((TimeCurrent() - g_initTime) / 60);

   // 7. Dashboard Updates (skip if disabled for performance)
   if(InpEnableDashboard)
   {
      int ping = (int)(TerminalInfoInteger(TERMINAL_PING_LAST) / 1000);
      string connReason;
      string connStatusStr = g_killSwitch.IsConnStable(connReason) ? "Stable" : "Unstable";

      // Update Main Status Panel
      g_dashboard.Update(g_killSwitch.GetStatus(), EnumToString(g_currentRegime),
                      account.Equity(), 0, 0,
                      "REC FACTOR: " + DoubleToString(g_recovery.GetMultiplier(), 2) + "x",
                      connStatusStr, ping);

   // Update Performance Panel (NEW)
   g_dashboard.UpdatePerformance(todayPnL, winRate, profitFactor, totalTrades,
                                  g_totalWins, g_totalLosses, avgWin, avgLoss);

   // Update Intel Panel (NEW)
   double regimeConfidence = pred.confidence; // Already 0-1 range
   int universeSize = ArraySize(g_activeSymbols);
   string regimeName = EnumToString(g_currentRegime); // Show actual regime
   g_dashboard.UpdateIntel(regimeConfidence, universeSize, regimeName);

   // Update Footer (NEW)
   string footerMsg = "Uptime: " + IntegerToString(uptimeMinutes) + "m | Portfolio Governor v2.1 | GOD MODE";
   g_dashboard.UpdateFooter(footerMsg);

   // Update Symbol Confluence Table (NEW) - SORTED BY BEST SCORE
   CDashboard::SymbolConfluenceRow symbolRows[];
   int engineCount = ArraySize(g_engines);
   int validEngines = 0;

   // Count valid engines first
   for(int i=0; i<engineCount; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
         validEngines++;
   }

   ArrayResize(symbolRows, MathMin(validEngines, 8)); // Max 8 symbols
   int rowIndex = 0;

   // Collect all symbol data WITH RANK AND PERMISSION
   for(int i=0; i<engineCount && rowIndex < 8; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         symbolRows[rowIndex].symbol = g_engines[i].m_symbol;  // Safer: get from engine directly
         symbolRows[rowIndex].buyScore = g_engines[i].GetBuyConfluence();
         symbolRows[rowIndex].sellScore = g_engines[i].GetSellConfluence();
         symbolRows[rowIndex].status = g_engines[i].GetStatus();
         symbolRows[rowIndex].rank = i + 1;  // Temp rank, will fix after sorting
         symbolRows[rowIndex].allowedToTrade = g_engines[i].IsAllowedToTrade();
         rowIndex++;
      }
   }

   // Sort by highest score (BUY or SELL) - Bubble Sort
   for(int i=0; i<ArraySize(symbolRows)-1; i++)
   {
      for(int j=0; j<ArraySize(symbolRows)-i-1; j++)
      {
         double score1 = MathMax(symbolRows[j].buyScore, symbolRows[j].sellScore);
         double score2 = MathMax(symbolRows[j+1].buyScore, symbolRows[j+1].sellScore);

         if(score2 > score1) // Descending order (highest first)
         {
            // Swap
            CDashboard::SymbolConfluenceRow temp = symbolRows[j];
            symbolRows[j] = symbolRows[j+1];
            symbolRows[j+1] = temp;
         }
      }
   }

   // Assign final ranks after sorting (1=best, 2=second, etc.)
   for(int i=0; i<ArraySize(symbolRows); i++)
   {
      symbolRows[i].rank = i + 1;
   }

   g_dashboard.UpdateSymbolTable(symbolRows);

   // Update Active Trades List
   string activeTrades[];
   int totalPos = PositionsTotal();
   int listSize = MathMin(totalPos, 12); // Max 12 on dash
   ArrayResize(activeTrades, listSize);

   for(int i=0; i<listSize; i++)
   {
      if(position.SelectByIndex(totalPos - 1 - i)) // Show newest first
      {
         string type = (position.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         double profit = position.Profit();
         string sym = position.Symbol();

         // Format: "EURUSD BUY | $ 25.50"
         string pnlStr = (profit >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(profit), 2);
         activeTrades[i] = sym + " " + type + " | " + pnlStr;
      }
   }
      g_dashboard.UpdateTradesList(activeTrades);
   } // End if(InpEnableDashboard)
}

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
void AddToArray(string &arr[], string value)
{
   int size = ArraySize(arr);
   ArrayResize(arr, size+1);
   arr[size] = value;
}

//+------------------------------------------------------------------+
//| Get Global Position Count (with optional magic filtering)        |
//| FIX: Prevents manual trades/other EAs from blocking Governor     |
//+------------------------------------------------------------------+
int GetGlobalPositionCount()
{
   if(!InpCountOnlyGovernorPositions)
      return PositionsTotal();  // Original behavior: count all positions
   
   // Count only Governor trades (magic 1000-1999)
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      long magic = PositionGetInteger(POSITION_MAGIC);
      
      // Our Governor magic range
      if(magic >= 1000 && magic < 2000)
         count++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Configure Symbol-Specific Risk Parameters                        |
//| Uses tuned parameters from .set files instead of defaults        |
//+------------------------------------------------------------------+
void ConfigureRiskForSymbol(string symbol, SymbolEngineParams &params)
{
   string sym = symbol;
   StringToUpper(sym);
   
   // Remove broker suffixes for matching
   StringReplace(sym, ".PRO", "");
   StringReplace(sym, ".M", "");
   StringReplace(sym, "+", "");
   StringReplace(sym, ".A", "");
   StringReplace(sym, "_OPT", "");
   
   // ===== EURUSD - King of Forex =====
   if(StringFind(sym, "EURUSD") >= 0)
   {
      // RISK (Conservative Profile)
      params.RiskBase = 0.4;
      params.RiskAddOn1 = 0.2;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.8;
      params.MaxLotsPerTrade = 1.0;
      
      // KELLY
      params.KellyFraction = 0.35;
      params.DailyMaxDD = 4.0;
      params.WeeklyMaxDD = 8.0;
      
      // TP/SL (Tight for EUR precision)
      params.FixedTP_R = 2.0;
      params.MinTP_R = 1.2;
      params.MaxTP_R = 3.0;
      params.PartialTP_R = 1.2;
      params.TrailStart_R = 1.6;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 5;
      params.MaxProfitPerSession_R = 10.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 6.0;
      params.TradeCooldownMinutes = 5;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== GBPUSD - Cable (HIGH PRIORITY FIX) =====
   else if(StringFind(sym, "GBPUSD") >= 0)
   {
      // RISK (Conservative - volatile pair)
      params.RiskBase = 0.3;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.6;
      params.MaxLotsPerTrade = 0.8;
      
      // KELLY
      params.KellyFraction = 0.30;
      params.DailyMaxDD = 3.5;
      params.WeeklyMaxDD = 7.0;
      
      // TP/SL (Wide for Cable's volatility)
      params.FixedTP_R = 2.2;
      params.MinTP_R = 1.3;
      params.MaxTP_R = 4.0;
      params.PartialTP_R = 1.3;
      params.TrailStart_R = 1.8;
      
      // SESSION LIMITS (Growth)
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.0;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== XAUUSD - Gold =====
   else if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      // RISK (Very Conservative - volatile)
      params.RiskBase = 0.07;
      params.RiskAddOn1 = 0.04;
      params.RiskAddOn2 = 0.02;
      params.MaxRisk = 0.15;
      params.MaxLotsPerTrade = 0.2;
      
      // KELLY (Quarter Kelly for gold)
      params.KellyFraction = 0.20;
      params.DailyMaxDD = 1.5;
      params.WeeklyMaxDD = 3.0;
      
      // TP/SL (Wider - gold trends)
      params.FixedTP_R = 2.5;
      params.MinTP_R = 1.5;
      params.MaxTP_R = 5.0;
      params.PartialTP_R = 1.5;
      params.PartialClosePercent = 35.0;
      params.TrailStart_R = 2.0;
      params.TrailATR_Mult = 1.5;
      
      // SESSION LIMITS (Stricter for gold)
      params.MaxTradesPerSession = 2;
      params.MaxProfitPerSession_R = 6.0;
      params.MaxLossPerSession_R = 2.0;
      params.DailyMaxLoss_R = 2.5;
      params.TradeCooldownMinutes = 15;
      params.LossCooldownMinutes = 60;
      
      // NEWS (Gold very sensitive)
      params.NewsMinutesBefore = 60;
      params.NewsMinutesAfter = 60;
   }
   
   // ===== GBPJPY - Volatile Cross =====
   else if(StringFind(sym, "GBPJPY") >= 0)
   {
      // RISK (Conservative)
      params.RiskBase = 0.08;
      params.RiskAddOn1 = 0.05;
      params.RiskAddOn2 = 0.03;
      params.MaxRisk = 0.2;
      params.MaxLotsPerTrade = 0.2;
      
      // KELLY
      params.KellyFraction = 0.22;
      params.DailyMaxDD = 1.8;
      params.WeeklyMaxDD = 3.5;
      
      // TP/SL (Wider for volatility)
      params.FixedTP_R = 2.2;
      params.MinTP_R = 1.3;
      params.MaxTP_R = 4.0;
      params.PartialTP_R = 1.3;
      params.TrailStart_R = 1.8;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 2;
      params.MaxProfitPerSession_R = 5.0;
      params.MaxLossPerSession_R = 1.8;
      params.DailyMaxLoss_R = 2.8;
      params.TradeCooldownMinutes = 12;
      params.LossCooldownMinutes = 50;
   }
   
   // ===== USDCAD - Loonie =====
   else if(StringFind(sym, "USDCAD") >= 0)
   {
      // RISK (Conservative)
      params.RiskBase = 0.35;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.7;
      params.MaxLotsPerTrade = 1.0;
      
      // KELLY
      params.KellyFraction = 0.32;
      params.DailyMaxDD = 3.8;
      params.WeeklyMaxDD = 7.5;
      
      // TP/SL (Standard)
      params.FixedTP_R = 2.1;
      params.MinTP_R = 1.2;
      params.MaxTP_R = 3.5;
      params.PartialTP_R = 1.2;
      params.TrailStart_R = 1.7;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.5;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== USDCHF - Swissy =====
   else if(StringFind(sym, "USDCHF") >= 0)
   {
      // RISK (Conservative - stable pair)
      params.RiskBase = 0.35;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.7;
      params.MaxLotsPerTrade = 1.0;
      
      // KELLY
      params.KellyFraction = 0.32;
      params.DailyMaxDD = 3.8;
      params.WeeklyMaxDD = 7.5;
      
      // TP/SL (Tight - stable moves)
      params.FixedTP_R = 2.0;
      params.MinTP_R = 1.2;
      params.MaxTP_R = 3.2;
      params.PartialTP_R = 1.2;
      params.TrailStart_R = 1.6;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.5;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== AUDUSD - Aussie =====
   else if(StringFind(sym, "AUDUSD") >= 0)
   {
      // RISK (Conservative)
      params.RiskBase = 0.35;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.7;
      params.MaxLotsPerTrade = 1.0;
      
      // KELLY
      params.KellyFraction = 0.32;
      params.DailyMaxDD = 3.8;
      params.WeeklyMaxDD = 7.5;
      
      // TP/SL (Standard)
      params.FixedTP_R = 2.1;
      params.MinTP_R = 1.2;
      params.MaxTP_R = 3.3;
      params.PartialTP_R = 1.2;
      params.TrailStart_R = 1.6;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.5;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== USDJPY - Yen King =====
   else if(StringFind(sym, "USDJPY") >= 0)
   {
      // RISK (Conservative - safe haven)
      params.RiskBase = 0.25;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.5;
      params.MaxLotsPerTrade = 0.8;
      
      // KELLY
      params.KellyFraction = 0.30;
      params.DailyMaxDD = 3.5;
      params.WeeklyMaxDD = 7.0;
      
      // TP/SL (Standard)
      params.FixedTP_R = 2.0;
      params.MinTP_R = 1.2;
      params.MaxTP_R = 3.2;
      params.PartialTP_R = 1.2;
      params.TrailStart_R = 1.6;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.0;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== EURJPY - EUR/JPY Cross =====
   else if(StringFind(sym, "EURJPY") >= 0)
   {
      // RISK (Conservative - volatile cross)
      params.RiskBase = 0.25;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.5;
      params.MaxLotsPerTrade = 0.8;
      
      // KELLY
      params.KellyFraction = 0.30;
      params.DailyMaxDD = 3.5;
      params.WeeklyMaxDD = 7.0;
      
      // TP/SL (Wider for volatility)
      params.FixedTP_R = 2.2;
      params.MinTP_R = 1.3;
      params.MaxTP_R = 4.0;
      params.PartialTP_R = 1.3;
      params.TrailStart_R = 1.8;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.0;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== NZDUSD - Kiwi =====
   else if(StringFind(sym, "NZDUSD") >= 0)
   {
      // RISK (Conservative)
      params.RiskBase = 0.35;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.7;
      params.MaxLotsPerTrade = 1.0;
      
      // KELLY
      params.KellyFraction = 0.32;
      params.DailyMaxDD = 3.8;
      params.WeeklyMaxDD = 7.5;
      
      // TP/SL (Standard)
      params.FixedTP_R = 2.0;
      params.MinTP_R = 1.2;
      params.MaxTP_R = 3.3;
      params.PartialTP_R = 1.2;
      params.TrailStart_R = 1.6;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.5;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // ===== AUDJPY - AUD/JPY Cross =====
   else if(StringFind(sym, "AUDJPY") >= 0)
   {
      // RISK (Conservative - commodity cross)
      params.RiskBase = 0.25;
      params.RiskAddOn1 = 0.15;
      params.RiskAddOn2 = 0.1;
      params.MaxRisk = 0.5;
      params.MaxLotsPerTrade = 0.8;
      
      // KELLY
      params.KellyFraction = 0.30;
      params.DailyMaxDD = 3.5;
      params.WeeklyMaxDD = 7.0;
      
      // TP/SL (Standard)
      params.FixedTP_R = 2.1;
      params.MinTP_R = 1.2;
      params.MaxTP_R = 3.5;
      params.PartialTP_R = 1.2;
      params.TrailStart_R = 1.7;
      
      // SESSION LIMITS
      params.MaxTradesPerSession = 4;
      params.MaxProfitPerSession_R = 8.0;
      params.MaxLossPerSession_R = 3.0;
      params.DailyMaxLoss_R = 5.0;
      params.TradeCooldownMinutes = 8;
      params.LossCooldownMinutes = 30;
   }
   
   // If symbol not matched, defaults remain (already set by GetDefaults())
}

void UpdateUniverse()
{
   // ==================================================================
   // 24/7 MODE: PERSISTENT 10-PAIR UNIVERSE (NO KILLZONE ROTATION)
   // Confluence system handles quality filtering, not killzones
   // ==================================================================
   
   static bool initialized = false;
   
   // 1. Initialize universe ONCE at startup (persistent engines)
   if(!initialized || ArraySize(g_activeSymbols) == 0)
   {
      Print("🌍 GOVERNOR: Initializing 8-pair GROWTH PORTFOLIO (24/7 MODE)...");
      
      // OPTIMIZED 8-PAIR SELECTION (Best Liquidity + Correlation Balance)
      // Based on professional trader research: 3-15 pairs max, 8 = conservative sweet spot
      string allPairs[] = {
         "EURUSD",    // 1. King - 28% daily volume (London/NY)
         "USDJPY",    // 2. Yen - 13% daily volume (Asian/London/NY)
         "GBPUSD",    // 3. Cable - 11% volume (London/NY volatility)
         "XAUUSD",    // 4. Gold - Trending asset (London/NY)
         "AUDUSD",    // 5. Aussie - 5% volume (Asian/London)
         "USDCAD",    // 6. Loonie - 4% volume (NY oil correlation)
         "EURJPY",    // 7. Cross - Asian/London/NY coverage
         "USDCHF"     // 8. Swissy - EUR/USD hedge (-85% correlation)
      };
      
      Print("📊 Portfolio Strategy: GROWTH (8 pairs)");
      Print("📊 Focus: Highest liquidity + Optimal correlation balance + Growth Risk");
      Print("📊 Coverage: 24/7 (Asian: 3 pairs | London: 8 pairs | NY: 6 pairs)");
      
      string verified[];
      
      // Verify each symbol exists in broker's market watch
      for(int i=0; i<ArraySize(allPairs); i++)
      {
         string sym = allPairs[i];
         
         // Check if exists (Standard)
         if(SymbolSelect(sym, true))
         {
            AddToArray(verified, sym);
            continue;
         }
         
         // Try common broker suffixes
         bool found = false;
         string suffixes[] = {".m", ".pro", "+", "c", ".a", "_opt"};
         for(int s=0; s<ArraySize(suffixes); s++)
         {
            string trySym = sym + suffixes[s];
            if(SymbolSelect(trySym, true))
            {
               AddToArray(verified, trySym);
               found = true;
               break;
            }
         }
         
         if(!found)
         {
            Print("⚠️ SYMBOL NOT FOUND: ", sym, " - Check Market Watch or broker symbol list");
         }
      }
      
      // Apply verified list
      ArrayResize(g_activeSymbols, ArraySize(verified));
      for(int i=0; i<ArraySize(verified); i++) 
         g_activeSymbols[i] = verified[i];
      
      Print("✅ GOVERNOR: ", ArraySize(g_activeSymbols), " pairs loaded (8-PAIR GROWTH MODE)");
      
      // List all loaded symbols
      string symbolList = "";
      for(int i=0; i<ArraySize(g_activeSymbols); i++)
      {
         symbolList += g_activeSymbols[i];
         if(i < ArraySize(g_activeSymbols) - 1) symbolList += ", ";
      }
      Print("📊 Active Universe: ", symbolList);
      
      initialized = true;
   }
   
   // 2. Sync Engines
   if(ArraySize(g_engines) != ArraySize(g_activeSymbols))
   {
      ArrayResize(g_engines, ArraySize(g_activeSymbols));
   }
   
   for(int i=0; i<ArraySize(g_activeSymbols); i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_INVALID)
      {
         // FIX: Stagger engine initialization (max 1 per second)
         // Prevents CPU spike on session change when 6+ engines init simultaneously
         if(TimeCurrent() - g_lastEngineInitTime < 1)
            break;  // Resume on next timer tick (1 second)
         
         string sym = g_activeSymbols[i];
         
         // Double Check Selection
         if(!SymbolSelect(sym, true)) continue;
         
         g_engines[i] = new CSymbolEngineWrapper();

         // Configure Params
         SymbolEngineParams params = CSymbolEngineWrapper::GetDefaults();
         // 🔥 APPLY SYMBOL-SPECIFIC RISK MAP
ConfigureRiskForSymbol(sym, params);
         params.MagicNumber = 1000 + i;
         params.TradeComment = "GodMode_" + sym;
         
         // NOTIFICATIONS
         params.EnablePushNotifications = InpEnablePushNotifications;

         // 24/7 MODE: DISABLE KILLZONE FILTER
         // Confluence system (30-point scoring) handles quality control
         params.UseKillzoneFilter = false;  // ← DISABLED for 24/7
         params.UseSymbolDefaults = false;
         params.EnableAsianKZ = false;      // Not used when filter disabled
         params.EnableLondonOpenKZ = false;
         params.EnableNYKZ = false;
         params.EnableLondonCloseKZ = false;

         // Volatility Spike Protection
         params.UseNewsFilter = true;
         params.NewsMinutesBefore = 30;
         params.NewsMinutesAfter = 30;

         if(g_engines[i].Init(sym, params, &g_db))

         {
            Print("🚀 Engine Ignited: ", sym, " | Mode: 24/7 (Killzones: DISABLED)");
         }
         else
         {
            Print("❌ Engine Failed: ", sym);
            delete g_engines[i];
            g_engines[i] = NULL;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Convert string array to comma-separated string           |
//+------------------------------------------------------------------+
string ArrayToString(const string &arr[])
{
   string result = "";
   for(int i=0; i<ArraySize(arr); i++)
   {
      result += arr[i];
      if(i < ArraySize(arr) - 1) result += ", ";
   }
   return result;
}

//+------------------------------------------------------------------+
//| Helper: Get minutes until next killzone starts                   |
//+------------------------------------------------------------------+
int GetMinutesToNextKillzone(ENUM_CURRENT_SESSION current)
{
   if(current != SESSION_DEAD_ZONE)
      return 0; // Already in killzone
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // Killzones in server time (GMT+2)
   int londonStart = 9 * 60;      // 09:00
   int nyStart = 15 * 60 + 30;    // 15:30
   
   int nextKZ = 0;
   
   if(currentMinutes < londonStart)
      nextKZ = londonStart;
   else if(currentMinutes < nyStart)
      nextKZ = nyStart;
   else
      nextKZ = londonStart + (24 * 60); // Tomorrow
   
   int diff = nextKZ - currentMinutes;
   if(diff < 0) diff += (24 * 60);
   
   return diff;
}

//+------------------------------------------------------------------+
//| Heartbeat: Periodic status log every 10 minutes                  |
//+------------------------------------------------------------------+
void PrintHeartbeat()
{
   // 1. Calculate uptime
   int uptimeMin = (int)((TimeCurrent() - g_initTime) / 60);
   int hours = uptimeMin / 60;
   int mins = uptimeMin % 60;
   
   // 2. Balance and Equity
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double floatingPL = equity - balance;
   
   // 3. Current session
   ENUM_CURRENT_SESSION session = GetCurrentSession(2, true);
   string sessionName = GetSessionName(session);
   
   // 4. Minutes to next killzone
   int minsToNext = GetMinutesToNextKillzone(session);
   
   // 5. Open trades
   int openTrades = PositionsTotal();
   
   // 6. Daily stats
   double winRate = 0;
   if(g_totalWins + g_totalLosses > 0)
      winRate = (double)g_totalWins / (g_totalWins + g_totalLosses) * 100.0;
   
   double dailyPL = balance - g_dailyStartBalance;
   double dailyPct = (g_dailyStartBalance > 0) ? (dailyPL / g_dailyStartBalance) * 100.0 : 0;
   
   // Print consolidated heartbeat
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("🧠 HEARTBEAT [", TimeToString(TimeCurrent(), TIME_MINUTES), 
         "] | Uptime: ", hours, "h ", mins, "m | Balance: $", 
         DoubleToString(balance, 2), " | Equity: $", DoubleToString(equity, 2));
   
   // Session info
   if(session == SESSION_DEAD_ZONE && minsToNext > 0)
      Print("🌍 Session: ", sessionName, " | Next: in ", minsToNext/60, "h ", minsToNext%60, "m");
   else
      Print("🌍 Session: ", sessionName, (session != SESSION_DEAD_ZONE ? " (Active)" : ""));
   
   // Active symbols
   if(ArraySize(g_activeSymbols) > 0)
      Print("📈 Active Universe: ", ArrayToString(g_activeSymbols), " (", ArraySize(g_activeSymbols), " symbols)");
   else
      Print("📈 Active Universe: None (waiting for killzone)");
   
   // Open trades
   if(openTrades > 0)
      Print("💰 Open Trades: ", openTrades, " | Floating: ", 
            (floatingPL >= 0 ? "+" : ""), DoubleToString(floatingPL, 2), 
            " (", (floatingPL >= 0 ? "+" : ""), DoubleToString((floatingPL/balance)*100, 2), "%)");
   else
      Print("💰 Open Trades: 0 | Ready for entries");
   
   // Daily stats (only if there were trades today)
   if(g_totalWins + g_totalLosses > 0)
      Print("📊 Today: Wins: ", g_totalWins, " | Losses: ", g_totalLosses, 
            " | P/L: ", (dailyPL >= 0 ? "+" : ""), DoubleToString(dailyPL, 2),
            " (", (dailyPct >= 0 ? "+" : ""), DoubleToString(dailyPct, 2), "%) | Win Rate: ", 
            DoubleToString(winRate, 1), "%");
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}
//+------------------------------------------------------------------+
