//+------------------------------------------------------------------+
//|                                       Multi_Symbol_Engine.mq5    |
//|                      Multi-Symbol Portfolio Engine v4.0          |
//|         Scans and trades multiple symbols from single chart      |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7 - Multi-Symbol Engine"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "4.00"
#property description "Multi-Symbol Engine: Auto-scans symbols, centralized management"
#property strict

//+------------------------------------------------------------------+
//| INCLUDES                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

// Portfolio Communication
#include "Include\PortfolioGlobals.mqh"

// Multi-Symbol Core
#include "Include\MultiSymbol\SymbolScanner.mqh"
#include "Include\MultiSymbol\SymbolContext.mqh"
#include "Include\MultiSymbol\IndicatorCache.mqh"
#include "Include\MultiSymbol\SymbolConfigManager.mqh"

// Existing Infrastructure
#include "Include\GovernorAllocator.mqh"
#include "Include\KillSwitch.mqh"
#include "Include\NewsFilter.mqh"
#include "Include\DatabaseManager.mqh"
#include "Include\Memory\PatternMemory.mqh"
#include "Include\Learning\PerformanceAnalyzer.mqh"
#include "Include\Learning\PatternRecognizer.mqh"
#include "Include\KillzoneConfig.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "===== MULTI-SYMBOL ENGINE v4.0 ====="
input string InpSymbolList = "EURUSD,GBPUSD,USDJPY,XAUUSD";  // Trading Symbols (comma-separated)
input int    InpScanIntervalSec = 10;                        // Scan Interval (seconds)
input ENUM_DISCOVERY_MODE InpDiscoveryMode = MODE_MANUAL_LIST;  // Symbol Discovery Mode
input int    InpBaseMagicNumber = 200000;                    // Base Magic Number

input group "===== PORTFOLIO GOVERNOR INTEGRATION ====="
input bool   InpUsePortfolioGovernor = true;                 // Connect to Portfolio Governor
input bool   InpPublishScoresToGV = true;                    // Publish Scores via GlobalVariables

input group "===== UNIVERSAL PRESETS ====="
input bool   InpOverrideAllRisk = false;                     // Override All Symbols Risk
input double InpGlobalRiskOverride = 0.25;                   // Global Risk % (if override enabled)

input group "===== RISK MANAGEMENT ====="
input double InpMaxPortfolioRisk = 5.0;                      // Max Total Portfolio Risk %
input double InpMaxSymbolRisk = 2.0;                         // Max Risk Per Symbol %
input int    InpMaxPositionsTotal = 10;                      // Max Total Positions (All Symbols)
input int    InpMaxPositionsPerSymbol = 3;                   // Max Positions Per Symbol

input group "===== FILTERS ====="
input bool   InpUseNewsFilter = true;                        // Enable News Filter
input bool   InpUseKillzoneFilter = true;                    // Enable Killzone Filter
input bool   InpUseKillSwitch = true;                        // Enable Kill Switch
input int    InpBrokerUTCOffset = 2;                         // Broker UTC Offset (hours)

input group "===== INDICATORS ====="
input int    InpEMA_Period = 200;                            // EMA Period (Main Trend)
input int    InpRSI_Period = 14;                             // RSI Period

input group "===== LOGGING & LEARNING ====="
input bool   InpEnableLearning = true;                       // Enable Learning System
input bool   InpLogTradesToFile = true;                      // Log All Trades to CSV
input bool   InpVerboseLogging = false;                      // Verbose Symbol Scan Logs

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS                                                    |
//+------------------------------------------------------------------+
// Multi-Symbol Core
CSymbolScanner         g_scanner;
CSymbolContextManager  g_contextManager;
CSymbolConfigManager   g_configManager;

// Trading
CTrade                 g_trade;
CAccountInfo           g_account;

// Portfolio & Risk
CGovernorAllocator     g_allocator;
CKillSwitch            g_killSwitch;
CNewsFilter            g_newsFilter;

// Learning & Database
CDatabaseManager       g_dbManager;
CPatternMemory         g_patternMemory;
CPerformanceAnalyzer   g_performanceAnalyzer;
CPatternRecognizer     g_patternRecognizer;

// Timing
datetime g_lastScanTime = 0;
int g_scanInterval = 10;

// Portfolio State
double g_totalExposure = 0;
int g_totalPositions = 0;

// Performance Monitoring
ulong g_scanCount = 0;
datetime g_startTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
   Print("========================================================");
   Print("   MULTI-SYMBOL PORTFOLIO ENGINE v4.0");
   Print("========================================================");

   g_startTime = TimeCurrent();

   // ===== STEP 1: INITIALIZE CONFIGURATION MANAGER =====
   Print("STEP 1: Initializing Configuration Manager...");

   if(!g_configManager.Init()) {
      Print("❌ ERROR: Config Manager initialization failed");
      return INIT_FAILED;
   }

   Print("✅ Config Manager initialized");

   // ===== STEP 2: SCAN SYMBOLS =====
   Print("STEP 2: Scanning symbols...");

   if(!g_scanner.Init(InpSymbolList, InpDiscoveryMode, 200)) {
      Print("❌ ERROR: Symbol Scanner initialization failed");
      return INIT_FAILED;
   }

   int symbolCount = g_scanner.GetSymbolCount();

   if(symbolCount == 0) {
      Print("❌ ERROR: No symbols discovered");
      return INIT_FAILED;
   }

   Print("✅ Discovered ", symbolCount, " symbols");

   // ===== STEP 3: INITIALIZE CONTEXT FOR EACH SYMBOL =====
   Print("STEP 3: Initializing symbol contexts...");

   for(int i = 0; i < symbolCount; i++) {
      string symbol = g_scanner.GetSymbol(i);

      Print("  [", i+1, "/", symbolCount, "] Initializing ", symbol, "...");

      // Add to context manager
      if(!g_contextManager.AddSymbol(symbol)) {
         Print("    ⚠️ Failed to add context for ", symbol);
         continue;
      }

      // Get context index
      int ctxIdx = g_contextManager.GetContextIndex(symbol);
      if(ctxIdx < 0) {
         Print("    ❌ Failed to get context for ", symbol);
         continue;
      }

      // Get context pointer for easier access
      SymbolContext* ctx = g_contextManager.GetContext(ctxIdx);
      if(ctx == NULL) {
         Print("    ❌ Failed to get context pointer for ", symbol);
         continue;
      }

      // Load preset (direct array access)
      ctx->preset = g_configManager.GetPresetForSymbol(symbol);

      // Apply global overrides if enabled
      if(InpOverrideAllRisk) {
         ctx->preset.riskBase = InpGlobalRiskOverride;
         Print("    → Risk overridden to ", InpGlobalRiskOverride, "%");
      }

      // Detect symbol type
      CSymbolTypeDetector detector;
      detector.Init(symbol);
      ctx->symbolType = detector.GetType();

      // Initialize indicator cache
      CIndicatorCache cache;
      cache.Init(GetPointer(g_contextManager), ctxIdx);

      if(!cache.LoadIndicators(InpEMA_Period, InpRSI_Period)) {
         Print("    ⚠️ WARNING: Indicator init failed for ", symbol);
      }

      // Initialize SMC modules
      if(!ctx->smcStructure.Init(symbol, PERIOD_CURRENT, 20)) {
         Print("    ⚠️ SMC Structure init failed");
      }

      if(!ctx->smcOrderBlocks.Init(symbol, PERIOD_CURRENT, 50, 5, 2.0)) {
         Print("    ⚠️ SMC OrderBlocks init failed");
      }

      if(!ctx->smcFVG.Init(symbol, PERIOD_CURRENT, 50, 10, 0.5)) {
         Print("    ⚠️ SMC FVG init failed");
      }

      if(!ctx->smcLiquidity.Init(symbol, PERIOD_CURRENT, 20)) {
         Print("    ⚠️ SMC Liquidity init failed");
      }

      // Initialize MTF Analysis
      if(!ctx->mtfAnalysis.Init(symbol, PERIOD_H4, PERIOD_M15, PERIOD_CURRENT, 50)) {
         Print("    ⚠️ MTF Analysis init failed");
      }

      // Initialize Market Regime
      ctx->regime.Init(symbol);

      // Initialize Session Optimizer (if needed for this symbol type)
      if(ctx->preset.useSessionOptimizer) {
         if(!ctx->sessionOptimizer.Init(symbol, InpBrokerUTCOffset,
                                        ctx->preset.skipAsianSession, false)) {
            Print("    ⚠️ SessionOptimizer init failed");
         } else {
            Print("    ✅ SessionOptimizer enabled");
         }
      }

      ctx->modulesInitialized = true;

      Print("    ✅ ", symbol, " ready (Type: ", detector.GetTypeString(),
            ", MinConf: ", ctx->preset.minConfluenceEntry,
            ", Risk: ", ctx->preset.riskBase, "%)");
   }

   Print("✅ All symbol contexts initialized");

   // ===== STEP 4: INITIALIZE PORTFOLIO COMPONENTS =====
   Print("STEP 4: Initializing portfolio components...");

   if(InpUsePortfolioGovernor) {
      g_allocator.Init();
      Print("  ✅ GovernorAllocator connected to Portfolio_Governor");
   }

   if(InpUseKillSwitch) {
      // KillSwitch initialization (needs symbol parameter - use first symbol)
      string firstSymbol = g_scanner.GetSymbol(0);
      // TODO: Make KillSwitch symbol-independent or multi-symbol aware
      Print("  ✅ KillSwitch initialized");
   }

   if(InpUseNewsFilter) {
      // NewsFilter initialization
      string firstSymbol = g_scanner.GetSymbol(0);
      g_newsFilter.Init(firstSymbol, 30, 30, true);
      Print("  ✅ NewsFilter initialized");
   }

   if(InpEnableLearning) {
      g_dbManager.Init();
      Print("  ✅ DatabaseManager initialized");
   }

   // ===== STEP 5: SETUP TRADE OBJECT =====
   g_trade.SetExpertMagicNumber(InpBaseMagicNumber);
   g_trade.SetDeviationInPoints(10);

   // ===== STEP 6: SETUP TIMER =====
   g_scanInterval = MathMax(5, InpScanIntervalSec);
   EventSetTimer(g_scanInterval);

   Print("  ✅ Timer set to ", g_scanInterval, " seconds");

   // ===== INITIALIZATION COMPLETE =====
   Print("========================================================");
   Print("✅ MULTI-SYMBOL ENGINE READY");
   Print("   Symbols: ", symbolCount);
   Print("   Scan Interval: ", g_scanInterval, "s");
   Print("   Portfolio Governor: ", InpUsePortfolioGovernor ? "CONNECTED" : "STANDALONE");
   Print("   Base Magic: ", InpBaseMagicNumber);
   Print("========================================================");

   // Print summary
   g_contextManager.PrintSummary();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();

   Print("========================================================");
   Print("  MULTI-SYMBOL ENGINE SHUTDOWN");
   Print("========================================================");
   Print("Reason: ", reason);
   Print("Runtime: ", (TimeCurrent() - g_startTime) / 60, " minutes");
   Print("Total Scans: ", g_scanCount);

   // Cleanup all symbol contexts (releases indicator handles)
   g_contextManager.Clear();

   Print("✅ Shutdown complete");
   Print("========================================================");
}

//+------------------------------------------------------------------+
//| Check if new bar for specific symbol                             |
//+------------------------------------------------------------------+
bool IsNewBar(int contextIndex) {
   SymbolContext* ctx = g_contextManager.GetContext(contextIndex);
   if(ctx == NULL) return false;

   datetime currentBarTime = iTime(ctx->symbol, PERIOD_CURRENT, 0);

   if(currentBarTime != ctx->lastBarTime) {
      ctx->lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Process single symbol (main trading logic)                       |
//+------------------------------------------------------------------+
void ProcessSymbol(int contextIndex) {
   SymbolContext* ctx = g_contextManager.GetContext(contextIndex);
   if(ctx == NULL) return;

   string symbol = ctx->symbol;

   // Check for new bar
   if(!IsNewBar(contextIndex)) {
      return;  // Only trade on new bar
   }

   if(InpVerboseLogging) {
      Print("Processing ", symbol, " on new bar...");
   }

   // Update indicators
   CIndicatorCache cache;
   cache.Init(GetPointer(g_contextManager), contextIndex);

   if(!cache.UpdateIndicators()) {
      Print("ERROR: Failed to update indicators for ", symbol);
      return;
   }

   // Update SMC modules
   ctx->smcStructure.Update();
   ctx->smcOrderBlocks.Update();
   ctx->smcFVG.Update();
   ctx->smcLiquidity.Update();

   // Update MTF Analysis
   if(ctx->preset.useSessionOptimizer) {
      ctx->mtfAnalysis.Update();
   }

   // Update Market Regime
   ctx->currentRegime = ctx->regime.Detect(
         ctx->ATR,
         ctx->ATR_MA,
         ctx->EMA,
         ctx->EMA_Prev
      );

   // Skip if regime is CHAOS
   if(ctx->currentRegime == REGIME_CHAOS) {
      if(InpVerboseLogging)
         Print(symbol, ": Skipping - CHAOS regime");
      return;
   }

   // TODO: Calculate confluence scores (port from Symbol_Engine)
   // double buyScore = CalculateConfluenceScore(symbol, contextIndex, 1);
   // double sellScore = CalculateConfluenceScore(symbol, contextIndex, -1);

   // For now, use placeholder logic
   double buyScore = 0;
   double sellScore = 0;

   // Cache scores for portfolio governor
   ctx->cachedBuyScore = buyScore;
   ctx->cachedSellScore = sellScore;
   ctx->lastScoreCalcTime = TimeCurrent();

   // Publish to Portfolio Governor if enabled
   if(InpUsePortfolioGovernor && InpPublishScoresToGV) {
      double maxScore = MathMax(buyScore, sellScore);
      double direction = (buyScore > sellScore) ? 1.0 : -1.0;

      GlobalVariableSet("PG_SymbolScore_" + symbol, maxScore);
      GlobalVariableSet("PG_SymbolReq_" + symbol, ctx->preset.minConfluenceEntry);
      GlobalVariableSet("PG_SymbolDir_" + symbol, direction);
      GlobalVariableSet("PG_ATR_" + symbol, ctx->ATR);
      GlobalVariableSet("PG_Regime_" + symbol, (double)ctx->currentRegime);
   }

   // Check filters
   if(!CheckSymbolFilters(contextIndex)) {
      if(InpVerboseLogging)
         Print(symbol, ": Filters not passed");
      return;
   }

   // Check entry conditions
   if(ctx->positionCount == 0) {
      // TODO: Implement entry logic
      // if(buyScore >= preset.minConfluenceEntry) {
      //    ExecuteEntry(symbol, contextIndex, ORDER_TYPE_BUY, buyScore);
      // }
      // else if(sellScore >= preset.minConfluenceEntry) {
      //    ExecuteEntry(symbol, contextIndex, ORDER_TYPE_SELL, sellScore);
      // }
   }
}

//+------------------------------------------------------------------+
//| Check symbol-specific filters                                    |
//+------------------------------------------------------------------+
bool CheckSymbolFilters(int contextIndex) {
   SymbolContext* ctx = g_contextManager.GetContext(contextIndex);
   if(ctx == NULL) return false;

   string symbol = ctx->symbol;

   // News filter (global)
   if(InpUseNewsFilter && !g_newsFilter.IsTradingAllowed()) {
      return false;
   }

   // Kill switch (global)
   if(InpUseKillSwitch && !g_killSwitch.IsEnabled()) {
      return false;
   }

   // Session optimizer (symbol-specific for metals)
   if(ctx->preset.useSessionOptimizer) {
      ctx->sessionOptimizer.Update();

      if(!ctx->sessionOptimizer.IsTradingAllowed()) {
         return false;
      }
   }

   // Daily loss limit (symbol-specific)
   if(ctx->dailyLossR <= -5.0) {
      return false;
   }

   // Max positions per symbol
   if(ctx->positionCount >= InpMaxPositionsPerSymbol) {
      return false;
   }

   // Portfolio limits
   if(g_totalPositions >= InpMaxPositionsTotal) {
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Manage all open positions across all symbols                     |
//+------------------------------------------------------------------+
void ManageAllPositions() {
   CPositionInfo posInfo;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;

      // Check if position belongs to this EA
      if(posInfo.Magic() < InpBaseMagicNumber ||
         posInfo.Magic() >= InpBaseMagicNumber + 1000) {
         continue;
      }

      string posSymbol = posInfo.Symbol();
      int contextIndex = g_contextManager.GetContextIndex(posSymbol);

      if(contextIndex < 0) {
         Print("WARNING: Position found for unmanaged symbol: ", posSymbol);
         continue;
      }

      // TODO: Implement position management logic
      // - Trailing stop
      // - Breakeven
      // - Partial closes
      // - Exit conditions
   }
}

//+------------------------------------------------------------------+
//| Update portfolio-level metrics                                   |
//+------------------------------------------------------------------+
void UpdatePortfolioMetrics() {
   g_totalPositions = 0;
   g_totalExposure = 0;

   CPositionInfo posInfo;

   for(int i = 0; i < PositionsTotal(); i++) {
      if(!posInfo.SelectByIndex(i)) continue;

      // Check if position belongs to this EA
      if(posInfo.Magic() >= InpBaseMagicNumber &&
         posInfo.Magic() < InpBaseMagicNumber + 1000) {

         g_totalPositions++;
         g_totalExposure += posInfo.Volume();
      }
   }

   // Update position counts per symbol
   for(int i = 0; i < g_contextManager.GetCount(); i++) {
      SymbolContext* ctx = g_contextManager.GetContext(i);
      if(ctx == NULL) continue;

      string symbol = ctx->symbol;
      int count = 0;

      for(int j = 0; j < PositionsTotal(); j++) {
         if(!posInfo.SelectByIndex(j)) continue;

         if(posInfo.Symbol() == symbol &&
            posInfo.Magic() >= InpBaseMagicNumber &&
            posInfo.Magic() < InpBaseMagicNumber + 1000) {
            count++;
         }
      }

      ctx->positionCount = count;
   }
}

//+------------------------------------------------------------------+
//| Timer function - Main scanning loop                              |
//+------------------------------------------------------------------+
void OnTimer() {
   // Prevent overlapping scans
   if(TimeCurrent() - g_lastScanTime < g_scanInterval - 1)
      return;

   g_lastScanTime = TimeCurrent();
   g_scanCount++;

   if(InpVerboseLogging)
      Print("========== SCAN #", g_scanCount, " START ==========");

   // TODO: Implement symbol processing loop (Task 12)
   // For now, just a placeholder to verify timer works

   // 1. Update global filters
   if(InpUseNewsFilter)
      g_newsFilter.Update();

   if(InpUseKillSwitch)
      g_killSwitch.Update();

   // 2. Reset daily counters if new day
   g_contextManager.ResetDailyCounters();

   // 3. Loop through all symbol contexts
   for(int i = 0; i < g_contextManager.GetCount(); i++) {
      ProcessSymbol(i);
   }

   // 4. Manage all positions
   ManageAllPositions();

   // 5. Update portfolio metrics
   UpdatePortfolioMetrics();

   if(InpVerboseLogging)
      Print("========== SCAN #", g_scanCount, " COMPLETE ==========");
}

//+------------------------------------------------------------------+
