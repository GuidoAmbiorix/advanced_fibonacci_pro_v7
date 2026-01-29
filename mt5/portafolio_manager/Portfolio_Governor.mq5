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

// --- GOD MODE MODULES ---
#include "Include\KillSwitch.mqh"
#include "Include\LiquidityGuard.mqh"
#include "Include\SmartExecution.mqh"
#include "Include\MLRegimeDetector.mqh"
#include "Include\PortfolioOptimizer.mqh"
#include "Include\Dashboard.mqh"
#include "Include\NewsFilter.mqh"
#include "Include\KellyPositionSizer.mqh"
#include "Include\DrawdownRecovery.mqh"

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
CNewsFilter          g_newsFilter;
CKellyPositionSizer  g_kelly;
CDrawdownRecovery    g_recovery;

// --- INPUTS (Simplified for View) ---
input double InpMaxDrawdownPercent = 10.0;
input double InpMaxDailyLoss = 5.0;

// --- STATE ---
string g_activeSymbols[];
CSymbolEngineWrapper *g_engines[];      // The Engine Room
MARKET_REGIME g_currentRegime = REGIME_RANGE;

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
   g_dashboard.Init();

   // Recovery Init
   if(GlobalVariableCheck(GV_PEAK_EQUITY) == false)
      GlobalVariableSet(GV_PEAK_EQUITY, account.Equity());

   g_recovery.Update(); // Set initial scaler

   // Performance Tracking Init
   g_initTime = TimeCurrent();
   g_dailyStartBalance = account.Balance();
   g_lastDayCheck = TimeCurrent();

   // Load historical stats from global variables (persist across restarts)
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

   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 1);
   EventSetTimer(1);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_dashboard.Destroy();

   // Save performance stats to global variables (persist across restarts)
   GlobalVariableSet("GOV_TotalWins", g_totalWins);
   GlobalVariableSet("GOV_TotalLosses", g_totalLosses);
   GlobalVariableSet("GOV_TotalWinAmount", g_totalWinAmount);
   GlobalVariableSet("GOV_TotalLossAmount", g_totalLossAmount);
   GlobalVariableSet("GOV_TotalProfitGross", g_totalProfitGross);
   GlobalVariableSet("GOV_TotalLossGross", g_totalLossGross);

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
      g_dashboard.Update("💀 KILLED", EnumToString(g_currentRegime), account.Equity(), 0, 0, "EMERGENCY", "DISCONNECTED", 999);
      return;
   }
}

//+------------------------------------------------------------------+
//| TRADE EVENT HANDLER (Performance Tracking)                        |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Track closed positions for statistics
   if(HistorySelect(0, TimeCurrent()))
   {
      int totalDeals = HistoryDealsTotal();

      for(int i = totalDeals - 1; i >= MathMax(0, totalDeals - 10); i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         // Only count OUT deals (position closures)
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;

         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double netProfit = profit + commission + swap;

         // Check if this deal was already counted (simple cache)
         static ulong lastProcessedTicket = 0;
         if(ticket == lastProcessedTicket) break;
         lastProcessedTicket = ticket;

         // Update statistics
         if(netProfit > 0)
         {
            g_totalWins++;
            g_totalWinAmount += netProfit;
            g_totalProfitGross += netProfit;
            GlobalVariableSet("GOV_TotalWins", g_totalWins);
            GlobalVariableSet("GOV_TotalWinAmount", g_totalWinAmount);
            GlobalVariableSet("GOV_TotalProfitGross", g_totalProfitGross);
         }
         else if(netProfit < 0)
         {
            g_totalLosses++;
            g_totalLossAmount += MathAbs(netProfit);
            g_totalLossGross += MathAbs(netProfit);
            GlobalVariableSet("GOV_TotalLosses", g_totalLosses);
            GlobalVariableSet("GOV_TotalLossAmount", g_totalLossAmount);
            GlobalVariableSet("GOV_TotalLossGross", g_totalLossGross);
         }

         break; // Only process most recent unprocessed deal
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

   // 2. Regime Detection with Confidence
   string leader = (ArraySize(g_activeSymbols) > 0) ? g_activeSymbols[0] : "EURUSD";
   RegimePrediction pred = g_mlRegime.DetectRegime(leader);
   if(pred.confidence > 0.6)
      g_currentRegime = pred.regime;

   // 3. EXECUTION LOOP (The Heartbeat)
   int totalEngines = ArraySize(g_engines);
   for(int i=0; i<totalEngines; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         g_engines[i].OnTick(); // Triggers Scan -> Signal -> Trade
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

   // 7. Dashboard Updates
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
   g_dashboard.UpdateIntel(regimeConfidence, universeSize, "Risk Parity");

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

   // Collect all symbol data
   for(int i=0; i<engineCount && rowIndex < 8; i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC)
      {
         symbolRows[rowIndex].symbol = g_activeSymbols[i];
         symbolRows[rowIndex].buyScore = g_engines[i].GetBuyConfluence();
         symbolRows[rowIndex].sellScore = g_engines[i].GetSellConfluence();
         symbolRows[rowIndex].status = g_engines[i].GetStatus();
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
}

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
// Helper to append to array
void AddToArray(string &arr[], string value)
{
   int size = ArraySize(arr);
   ArrayResize(arr, size+1);
   arr[size] = value;
}

void UpdateUniverse()
{
   // 1. Initial Universe Setup (Run once or if empty)
   if(ArraySize(g_activeSymbols) == 0)
   {
      string candidates[] = {"EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "BTCUSD", "US30", "DE30"};
      string verified[];
      
      // Always add current symbol first (it's guaranteed to exist)
      AddToArray(verified, _Symbol);
      
      // Try to add candidates
      for(int i=0; i<ArraySize(candidates); i++)
      {
         string sym = candidates[i];
         if(sym == _Symbol) continue; // Already added
         
         // Check if exists (Standard)
         if(SymbolSelect(sym, true)) 
         {
            AddToArray(verified, sym);
            continue;
         }
         
         // Try Suffixes if standard failed (Simple auto-discovery)
         // Common suffixes: .m, .pro, +, c, .a
         string suffixes[] = {".m", ".pro", "+", "c", ".a", "_opt"};
         for(int s=0; s<ArraySize(suffixes); s++)
         {
            string trySym = sym + suffixes[s];
            if(SymbolSelect(trySym, true))
            {
               AddToArray(verified, trySym);
               break; 
            }
         }
      }
      
      // Apply Verified List
      ArrayResize(g_activeSymbols, ArraySize(verified));
      for(int i=0; i<ArraySize(verified); i++) g_activeSymbols[i] = verified[i];
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
         string sym = g_activeSymbols[i];
         
         // Double Check Selection
         if(!SymbolSelect(sym, true)) continue;
         
         g_engines[i] = new CSymbolEngineWrapper();
         
         // Configure Params
         SymbolEngineParams params = CSymbolEngineWrapper::GetDefaults();
         params.MagicNumber = 1000 + i; 
         params.TradeComment = "GodMode_" + sym;
         
         if(g_engines[i].Init(sym, params))
         {
            Print("🚀 Engine Ignited: ", sym);
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
