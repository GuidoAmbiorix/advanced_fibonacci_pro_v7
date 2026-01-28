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
// --- STATE ---
string g_activeSymbols[];
CSymbolEngineWrapper *g_engines[];      // The Engine Room
MARKET_REGIME g_currentRegime = REGIME_RANGE;

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
   
   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 1);
   EventSetTimer(1);
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_dashboard.Destroy();
   
   // Clean up Engines
   for(int i=0; i<ArraySize(g_engines); i++)
   {
      if(CheckPointer(g_engines[i]) == POINTER_DYNAMIC) delete g_engines[i];
   }
   ArrayResize(g_engines, 0);
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
//| TIMER (Logic)                                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_killSwitch.IsEnabled()) return;
   
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
   
   // 4. Recovery Scaling
   g_recovery.Update();
   
   // 5. Dashboard Update
   int ping = (int)(TerminalInfoInteger(TERMINAL_PING_LAST) / 1000);
   string connReason;
   string connStatusStr = g_killSwitch.IsConnStable(connReason) ? "Stable" : "Unstable";
   
   // Update Main Metrics
   g_dashboard.Update(g_killSwitch.GetStatus(), EnumToString(g_currentRegime), 
                      account.Equity(), 0, 0, 
                      "REC FACTOR: " + DoubleToString(g_recovery.GetMultiplier(), 2) + "x",
                      connStatusStr, ping);
                      
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
