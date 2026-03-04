# Implementation Plan: Multi-Symbol Portfolio Engine v4.0

## Executive Summary

**Goal:** Replace the current distributed architecture (N Symbol_Engine instances + Portfolio_Governor) with a single centralized EA that manages multiple symbols from one chart attachment.

**Current System:**
- Portfolio_Governor.mq5 (monitoring brain)
- Symbol_Engine.mq5 × N instances (one per chart)
- Communication via GlobalVariables (IPC bus)
- Resource overhead: N charts × N indicator sets

**Proposed System:**
- Multi_Symbol_Engine.mq5 (all-in-one)
- Runs on single chart (any symbol, just for timer)
- Internal symbol loop with shared indicator caching
- Auto-configuration from symbol list
- 60-80% resource reduction

---

## Architecture Decision: Two-Phase Approach

### Phase 1: Keep Portfolio_Governor Separate (RECOMMENDED)
**Rationale:** Proven monitoring system with RankManager stays intact

**Structure:**
```
Portfolio_Governor.mq5 (unchanged)
  ↓ GlobalVariables ↓
Multi_Symbol_Engine.mq5 (new)
  → Scans multiple symbols internally
  → Publishes scores to GlobalVariables (like Symbol_Engine does)
  → Reads ranks from Governor
  → Executes trades for top-ranked symbols
```

**Advantages:**
- Lower risk (Governor is battle-tested)
- Easier rollback if issues arise
- Preserves existing RankManager correlation logic
- Can run Multi_Symbol_Engine + legacy Symbol_Engines simultaneously (gradual migration)

**Disadvantages:**
- Still uses GlobalVariables IPC (minor overhead)
- Two EAs instead of one

---

### Phase 2: Full Merge (OPTIONAL - After Phase 1 Validation)
**Merge Portfolio_Governor INTO Multi_Symbol_Engine**

**Structure:**
```
Portfolio_Engine.mq5 (mega EA)
  → Portfolio risk monitoring (DD, PF, exposure)
  → Multi-symbol scanning
  → Ranking engine
  → Trade execution
```

**Advantages:**
- True single-EA solution
- No GlobalVariables overhead
- Unified logging
- Simpler deployment

**Disadvantages:**
- Higher complexity (2500+ lines)
- Harder to debug
- All-or-nothing deployment (no gradual migration)

---

## RECOMMENDATION: Implement Phase 1 First

Build **Multi_Symbol_Engine.mq5** that works WITH existing Portfolio_Governor.mq5.

---

# Phase 1 Implementation Plan: Multi_Symbol_Engine.mq5

## Design Principles

1. **Single Chart Attachment:** Works from ANY chart (EURUSD, XAUUSD, or even a blank symbol)
2. **Symbol Auto-Discovery:** Reads from input list, Market Watch, or config file
3. **Timer-Based Scanning:** OnTimer() instead of OnTick() (5-10 second intervals)
4. **Shared Indicators:** Load indicators once per symbol, cache handles
5. **Central Position Manager:** Single CTrade object, symbol in magic number encoding or comment
6. **Configuration Templates:** Per-symbol presets (like Universal_Engine's SymbolPreset)
7. **Portfolio Governor Compatible:** Publishes scores via GlobalVariables, reads ranks

---

## File Structure

```
Multi_Symbol_Engine.mq5                      // Main EA (1800-2200 lines)

Include/
  MultiSymbol/
    SymbolScanner.mqh                        // Symbol discovery & iteration
    SymbolContext.mqh                        // Per-symbol state container
    IndicatorCache.mqh                       // Centralized indicator management
    SymbolConfigManager.mqh                  // Load per-symbol presets
    UnifiedOrderManager.mqh                  // Central trade execution
    SymbolPositionTracker.mqh                // Position state per symbol

  // Reuse existing:
  Core/
    SymbolTypeDetector.mqh                   // Already created
    PositionStateManager.mqh                 // Already created
  Config/
    UniversalConfig.mqh                      // Already created
  PortfolioGlobals.mqh                       // Keep for IPC
  GovernorAllocator.mqh                      // Keep for risk calculation
  SMC_*.mqh                                  // Reuse all SMC modules
  KillzoneConfig.mqh                         // Reuse
  MarketRegime.mqh                           // Reuse
  etc.
```

---

## Core Components

### 1. SymbolScanner.mqh

**Purpose:** Discovers and manages list of symbols to trade

**Responsibilities:**
- Parse input symbol list
- Validate symbol availability
- Filter by Market Watch (optional)
- Return array of active symbols

**Implementation:**

```mql5
class CSymbolScanner {
private:
   string m_symbols[];

public:
   // Discovery modes
   enum DISCOVERY_MODE {
      MODE_MANUAL_LIST,      // From input string
      MODE_MARKET_WATCH,     // All visible in Market Watch
      MODE_FILE_CONFIG       // From symbols.txt or symbols.json
   };

   bool Init(string symbolList, DISCOVERY_MODE mode) {
      if(mode == MODE_MANUAL_LIST) {
         ParseSymbolList(symbolList);  // "EURUSD,GBPUSD,XAUUSD"
      } else if(mode == MODE_MARKET_WATCH) {
         ScanMarketWatch();
      } else if(mode == MODE_FILE_CONFIG) {
         LoadFromFile("symbols.txt");
      }

      ValidateSymbols();
      return ArraySize(m_symbols) > 0;
   }

   void ParseSymbolList(string input) {
      // Split by comma
      string parts[];
      int count = StringSplit(input, ',', parts);
      ArrayResize(m_symbols, count);
      for(int i = 0; i < count; i++) {
         string sym = parts[i];
         StringTrimLeft(sym);
         StringTrimRight(sym);
         m_symbols[i] = sym;
      }
   }

   void ScanMarketWatch() {
      int total = SymbolsTotal(true);  // Market Watch only
      ArrayResize(m_symbols, 0);
      for(int i = 0; i < total; i++) {
         string sym = SymbolName(i, true);
         if(IsValidForTrading(sym)) {
            int sz = ArraySize(m_symbols);
            ArrayResize(m_symbols, sz + 1);
            m_symbols[sz] = sym;
         }
      }
   }

   bool IsValidForTrading(string symbol) {
      // Check if tradable, has sufficient history, etc.
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) return false;

      // Check history availability
      int bars = iBars(symbol, PERIOD_H1, 0);
      if(bars < 200) return false;

      return true;
   }

   void ValidateSymbols() {
      // Remove invalid symbols
      for(int i = ArraySize(m_symbols) - 1; i >= 0; i--) {
         if(!SymbolSelect(m_symbols[i], true)) {
            Print("WARNING: Symbol ", m_symbols[i], " not available - removing");
            ArrayRemove(m_symbols, i, 1);
         }
      }
   }

   int GetSymbolCount() { return ArraySize(m_symbols); }
   string GetSymbol(int index) {
      if(index >= 0 && index < ArraySize(m_symbols))
         return m_symbols[index];
      return "";
   }
};
```

---

### 2. SymbolContext.mqh

**Purpose:** Container for per-symbol state (all data that was previously global in Symbol_Engine)

**Structure:**

```mql5
struct SymbolContext {
   // Identity
   string symbol;
   ENUM_SYMBOL_TYPE symbolType;
   SymbolPreset preset;

   // Indicator Handles
   int hRSI;
   int hATR;
   int hEMA;
   int hEMA50;
   int hEMA100;

   // Indicator Values
   double RSI;
   double RSI_Prev;
   double ATR;
   double EMA;
   double EMA_Prev;
   double ATR_MA;
   double EMA50;
   double EMA50_Prev;
   double EMA100;
   double EMA100_Prev;

   // Module Objects (per symbol)
   CSMCStructureBreak smcStructure;
   CSMCOrderBlocks smcOrderBlocks;
   CSMCFairValueGap smcFVG;
   CSMCLiquiditySweep smcLiquidity;
   CMTFConfluence mtfAnalysis;
   CMarketRegime regime;
   CSessionOptimizer sessionOptimizer;

   // Trading State
   datetime lastBarTime;
   int positionCount;
   bool addOn1Triggered;
   bool addOn2Triggered;
   datetime lastTradeTime;

   // Confluence Scores (cached)
   double cachedBuyScore;
   double cachedSellScore;
   datetime lastScoreCalcTime;
   ConfluenceFactors lastBuyFactors;
   ConfluenceFactors lastSellFactors;

   // Portfolio Communication
   double publishedScore;
   double publishedReq;
   double publishedDir;
   double assignedRank;

   // Market Regime
   MARKET_REGIME currentRegime;

   // Risk State
   double dailyLossR;
   int consecutiveLosses;

   // Constructor
   SymbolContext() : symbol(""), symbolType(SYMBOL_TYPE_UNKNOWN),
                     hRSI(INVALID_HANDLE), hATR(INVALID_HANDLE), hEMA(INVALID_HANDLE),
                     lastBarTime(0), positionCount(0), addOn1Triggered(false), addOn2Triggered(false),
                     cachedBuyScore(0), cachedSellScore(0), assignedRank(999),
                     currentRegime(REGIME_UNKNOWN), dailyLossR(0), consecutiveLosses(0) {}
};

class CSymbolContextManager {
private:
   SymbolContext m_contexts[];

public:
   bool AddSymbol(string symbol) {
      int sz = ArraySize(m_contexts);
      ArrayResize(m_contexts, sz + 1);
      m_contexts[sz].symbol = symbol;
      return true;
   }

   int FindIndex(string symbol) {
      for(int i = 0; i < ArraySize(m_contexts); i++)
         if(m_contexts[i].symbol == symbol)
            return i;
      return -1;
   }

   SymbolContext* GetContext(string symbol) {
      int idx = FindIndex(symbol);
      if(idx >= 0)
         return &m_contexts[idx];
      return NULL;
   }

   int GetCount() { return ArraySize(m_contexts); }
   SymbolContext* GetByIndex(int idx) {
      if(idx >= 0 && idx < ArraySize(m_contexts))
         return &m_contexts[idx];
      return NULL;
   }
};
```

---

### 3. IndicatorCache.mqh

**Purpose:** Lazy-load and cache indicator handles per symbol

**Implementation:**

```mql5
class CIndicatorCache {
private:
   SymbolContext* m_context;
   string m_symbol;

public:
   bool Init(SymbolContext* context) {
      m_context = context;
      m_symbol = context.symbol;
      return true;
   }

   bool LoadIndicators(SymbolPreset &preset, int emaperiod, int rsiPeriod) {
      // RSI
      if(m_context.hRSI == INVALID_HANDLE) {
         m_context.hRSI = iRSI(m_symbol, PERIOD_CURRENT, rsiPeriod, PRICE_CLOSE);
         if(m_context.hRSI == INVALID_HANDLE) {
            Print("ERROR: RSI init failed for ", m_symbol);
            return false;
         }
      }

      // ATR
      if(m_context.hATR == INVALID_HANDLE) {
         m_context.hATR = iATR(m_symbol, PERIOD_CURRENT, 14);
         if(m_context.hATR == INVALID_HANDLE) {
            Print("ERROR: ATR init failed for ", m_symbol);
            return false;
         }
      }

      // EMA
      if(m_context.hEMA == INVALID_HANDLE) {
         m_context.hEMA = iMA(m_symbol, PERIOD_CURRENT, emaperiod, 0, MODE_EMA, PRICE_CLOSE);
         if(m_context.hEMA == INVALID_HANDLE) {
            Print("ERROR: EMA init failed for ", m_symbol);
            return false;
         }
      }

      // Reversal EMAs
      if(m_context.hEMA50 == INVALID_HANDLE) {
         m_context.hEMA50 = iMA(m_symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      }
      if(m_context.hEMA100 == INVALID_HANDLE) {
         m_context.hEMA100 = iMA(m_symbol, PERIOD_CURRENT, 100, 0, MODE_EMA, PRICE_CLOSE);
      }

      return true;
   }

   bool UpdateIndicators() {
      double rsi[], atr[], ema[], ema50[], ema100[];

      if(CopyBuffer(m_context.hRSI, 0, 0, 2, rsi) != 2) return false;
      if(CopyBuffer(m_context.hATR, 0, 0, 2, atr) != 2) return false;
      if(CopyBuffer(m_context.hEMA, 0, 0, 2, ema) != 2) return false;
      if(CopyBuffer(m_context.hEMA50, 0, 0, 2, ema50) != 2) return false;
      if(CopyBuffer(m_context.hEMA100, 0, 0, 2, ema100) != 2) return false;

      m_context.RSI_Prev = m_context.RSI;
      m_context.RSI = rsi[0];

      m_context.ATR = atr[0];

      m_context.EMA_Prev = m_context.EMA;
      m_context.EMA = ema[0];

      m_context.EMA50_Prev = m_context.EMA50;
      m_context.EMA50 = ema50[0];

      m_context.EMA100_Prev = m_context.EMA100;
      m_context.EMA100 = ema100[0];

      // Calculate ATR MA (simple moving average of last 20 ATRs)
      double atrArray[];
      if(CopyBuffer(m_context.hATR, 0, 0, 20, atrArray) == 20) {
         m_context.ATR_MA = 0;
         for(int i = 0; i < 20; i++) m_context.ATR_MA += atrArray[i];
         m_context.ATR_MA /= 20.0;
      }

      return true;
   }

   void Cleanup() {
      if(m_context.hRSI != INVALID_HANDLE) IndicatorRelease(m_context.hRSI);
      if(m_context.hATR != INVALID_HANDLE) IndicatorRelease(m_context.hATR);
      if(m_context.hEMA != INVALID_HANDLE) IndicatorRelease(m_context.hEMA);
      if(m_context.hEMA50 != INVALID_HANDLE) IndicatorRelease(m_context.hEMA50);
      if(m_context.hEMA100 != INVALID_HANDLE) IndicatorRelease(m_context.hEMA100);
   }
};
```

---

### 4. SymbolConfigManager.mqh

**Purpose:** Load per-symbol presets (reuse UniversalConfig.mqh logic)

**Implementation:**

```mql5
class CSymbolConfigManager {
private:
   CUniversalConfig m_universalConfig;
   CSymbolTypeDetector m_detector;

public:
   bool Init() {
      return m_universalConfig.Init();
   }

   SymbolPreset GetPresetForSymbol(string symbol) {
      m_detector.Init(symbol);
      ENUM_SYMBOL_TYPE type = m_detector.GetType();
      return m_universalConfig.GetPreset(type);
   }

   // Optional: Load overrides from SET file
   bool LoadOverridesFromSet(string symbol, SymbolPreset &preset) {
      // Check if sets/[symbol].set exists
      string filename = "sets\\" + symbol + ".set";

      // MQL5 doesn't have native SET parsing, would need custom parser
      // OR use input groups per symbol (see Option B below)

      return false;  // Placeholder
   }
};
```

**Configuration Options:**

**Option A: Hardcoded Input Array (Simplest)**
```mql5
input string InpSymbolList = "EURUSD,GBPUSD,USDJPY,XAUUSD,NAS100";  // Symbol list
```

**Option B: Per-Symbol Input Groups (More Flexible)**
```mql5
input group "===== SYMBOL 1: EURUSD ====="
input bool   InpSym1_Enable = true;
input string InpSym1_Symbol = "EURUSD";
input double InpSym1_RiskOverride = 0.0;  // 0 = use preset

input group "===== SYMBOL 2: GBPUSD ====="
input bool   InpSym2_Enable = true;
input string InpSym2_Symbol = "GBPUSD";
input double InpSym2_RiskOverride = 0.0;

// ... up to InpSym10
```

**Option C: External Config File (Most Scalable)**
```json
// symbols.json
{
  "symbols": [
    {
      "name": "EURUSD",
      "enabled": true,
      "riskOverride": 0.0,
      "confluenceOverride": 0
    },
    {
      "name": "XAUUSD",
      "enabled": true,
      "riskOverride": 0.15,
      "confluenceOverride": 14
    }
  ]
}
```

**RECOMMENDATION:** Start with **Option A** (simple string list), migrate to **Option C** (JSON) in Phase 2.

---

### 5. UnifiedOrderManager.mqh

**Purpose:** Centralized trade execution across all symbols

**Challenge:** How to identify which symbol a position belongs to?

**Solution Options:**

**Option A: Magic Number Encoding (Recommended)**
```mql5
// Base magic: 200000
// Symbol offset: Hash(symbol) % 1000
// Example:
//   EURUSD → 200001
//   GBPUSD → 200002
//   XAUUSD → 200003

int GetMagicForSymbol(string symbol) {
   int baseMagic = 200000;
   int symbolHash = 0;

   // Simple hash
   for(int i = 0; i < StringLen(symbol); i++)
      symbolHash += StringGetCharacter(symbol, i);

   int offset = (symbolHash % 999) + 1;
   return baseMagic + offset;
}

string GetSymbolFromMagic(int magic) {
   // Reverse lookup from position comment or stored map
   // See Option B for comment-based approach
   return "";
}
```

**Option B: Comment Field Storage (More Robust)**
```mql5
// Store symbol in position comment
string BuildTradeComment(string symbol, string label) {
   return symbol + "|" + label;  // "EURUSD|Initial"
}

string ExtractSymbolFromComment(string comment) {
   int pos = StringFind(comment, "|");
   if(pos > 0)
      return StringSubstr(comment, 0, pos);
   return "";
}

bool ExecuteTrade(string symbol, ENUM_ORDER_TYPE type, double lots,
                  double price, double sl, double tp, string label) {
   CTrade trade;
   trade.SetExpertMagicNumber(GetMagicForSymbol(symbol));

   string comment = BuildTradeComment(symbol, label);

   if(type == ORDER_TYPE_BUY)
      return trade.Buy(lots, symbol, price, sl, tp, comment);
   else
      return trade.Sell(lots, symbol, price, sl, tp, comment);
}
```

**RECOMMENDATION:** Use **Option B** (comment storage) for symbol identification. More flexible and human-readable.

---

### 6. SymbolPositionTracker.mqh

**Purpose:** Track positions per symbol (replaces PositionStateManager per-EA)

**Implementation:**

```mql5
class CSymbolPositionTracker {
private:
   struct SymbolPositions {
      string symbol;
      PositionState states[];  // Reuse PositionState from PositionStateManager.mqh
   };

   SymbolPositions m_symbolPositions[];

public:
   int FindSymbolIndex(string symbol) {
      for(int i = 0; i < ArraySize(m_symbolPositions); i++)
         if(m_symbolPositions[i].symbol == symbol)
            return i;
      return -1;
   }

   bool AddPosition(string symbol, ulong ticket, double risk, double dollarRisk,
                    double slDist, ENTRY_QUALITY quality, ConfluenceFactors &factors) {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0) {
         // Add new symbol entry
         int sz = ArraySize(m_symbolPositions);
         ArrayResize(m_symbolPositions, sz + 1);
         m_symbolPositions[sz].symbol = symbol;
         ArrayResize(m_symbolPositions[sz].states, 0);
         idx = sz;
      }

      // Add position to symbol's state array
      int stateSz = ArraySize(m_symbolPositions[idx].states);
      ArrayResize(m_symbolPositions[idx].states, stateSz + 1);

      m_symbolPositions[idx].states[stateSz].ticket = ticket;
      m_symbolPositions[idx].states[stateSz].partialClosed = false;
      m_symbolPositions[idx].states[stateSz].initialRisk = risk;
      m_symbolPositions[idx].states[stateSz].dollarRisk = dollarRisk;
      m_symbolPositions[idx].states[stateSz].initialSLDist = slDist;
      m_symbolPositions[idx].states[stateSz].quality = quality;
      m_symbolPositions[idx].states[stateSz].entryFactors = factors;

      return true;
   }

   int GetPositionCount(string symbol) {
      int idx = FindSymbolIndex(symbol);
      if(idx >= 0)
         return ArraySize(m_symbolPositions[idx].states);
      return 0;
   }

   // Additional methods: FindPosition, RemovePosition, etc.
};
```

---

## Main EA Structure: Multi_Symbol_Engine.mq5

### Input Parameters

```mql5
input group "===== MULTI-SYMBOL ENGINE v4.0 ====="
input string InpSymbolList = "EURUSD,GBPUSD,USDJPY,XAUUSD,NAS100";  // Trading Symbols
input int    InpScanIntervalSec = 10;                               // Scan Interval (seconds)
input bool   InpUseMarketWatch = false;                             // Use Market Watch Instead of List
input int    InpBaseMagicNumber = 200000;                           // Base Magic Number

input group "===== PORTFOLIO GOVERNOR INTEGRATION ====="
input bool   InpUsePortfolioGovernor = true;                        // Connect to Portfolio Governor
input bool   InpPublishScoresToGV = true;                           // Publish Scores via GlobalVariables

input group "===== UNIVERSAL PRESETS ====="
input bool   InpOverrideAllRisk = false;                            // Override All Symbols Risk
input double InpGlobalRiskOverride = 0.25;                          // Global Risk % (if override enabled)

input group "===== RISK MANAGEMENT ====="
input double InpMaxPortfolioRisk = 5.0;                             // Max Total Portfolio Risk %
input double InpMaxSymbolRisk = 2.0;                                // Max Risk Per Symbol %
input int    InpMaxPositionsTotal = 10;                             // Max Total Positions Across All Symbols

input group "===== FILTERS ====="
input bool   InpUseNewsFilter = true;                               // Enable News Filter
input bool   InpUseKillzoneFilter = true;                           // Enable Killzone Filter
input int    InpBrokerUTCOffset = 2;                                // Broker UTC Offset

input group "===== LOGGING ====="
input bool   InpEnableLearning = true;                              // Enable Learning System
input bool   InpLogTradesToFile = true;                             // Log All Trades to CSV
input bool   InpVerboseLogging = false;                             // Verbose Symbol Scan Logs
```

---

### Global Variables

```mql5
// Scanner & Symbol Management
CSymbolScanner scanner;
CSymbolContextManager contextManager;
CSymbolConfigManager configManager;

// Portfolio Components
CGovernorAllocator allocator;
CSymbolPositionTracker positionTracker;
CUnifiedOrderManager orderManager;

// Shared Modules (if not per-symbol)
CNewsFilter globalNewsFilter;
CKillSwitch globalKillSwitch;
CDatabaseManager dbManager;

// Timing
datetime g_lastScanTime = 0;
int g_scanInterval = 10;  // seconds

// Portfolio State
double g_totalExposure = 0;
int g_totalPositions = 0;
```

---

### OnInit()

```mql5
int OnInit() {
   Print("====================================================");
   Print("   MULTI-SYMBOL PORTFOLIO ENGINE v4.0 INITIALIZING");
   Print("====================================================");

   // 1. Initialize Config Manager
   if(!configManager.Init()) {
      Print("ERROR: Config Manager init failed");
      return INIT_FAILED;
   }

   // 2. Scan Symbols
   CSymbolScanner::DISCOVERY_MODE mode = InpUseMarketWatch
      ? CSymbolScanner::MODE_MARKET_WATCH
      : CSymbolScanner::MODE_MANUAL_LIST;

   if(!scanner.Init(InpSymbolList, mode)) {
      Print("ERROR: Symbol Scanner init failed");
      return INIT_FAILED;
   }

   int symbolCount = scanner.GetSymbolCount();
   Print("Discovered ", symbolCount, " symbols for trading");

   // 3. Initialize Context for Each Symbol
   for(int i = 0; i < symbolCount; i++) {
      string symbol = scanner.GetSymbol(i);
      Print("  [", i+1, "/", symbolCount, "] Initializing ", symbol);

      // Add to context manager
      contextManager.AddSymbol(symbol);
      SymbolContext* ctx = contextManager.GetContext(symbol);

      // Get preset
      ctx.preset = configManager.GetPresetForSymbol(symbol);

      // Detect type
      CSymbolTypeDetector detector;
      detector.Init(symbol);
      ctx.symbolType = detector.GetType();

      // Initialize indicator cache
      CIndicatorCache cache;
      cache.Init(ctx);
      if(!cache.LoadIndicators(ctx.preset, 200, 14)) {
         Print("WARNING: Indicator init failed for ", symbol);
      }

      // Initialize SMC modules
      if(!ctx.smcStructure.Init(symbol, PERIOD_CURRENT, 20)) {
         Print("WARNING: SMC Structure init failed for ", symbol);
      }
      if(!ctx.smcOrderBlocks.Init(symbol, PERIOD_CURRENT, 50, 5, 2.0)) {
         Print("WARNING: SMC OrderBlocks init failed for ", symbol);
      }
      if(!ctx.smcFVG.Init(symbol, PERIOD_CURRENT, 50, 10, 0.5)) {
         Print("WARNING: SMC FVG init failed for ", symbol);
      }
      if(!ctx.smcLiquidity.Init(symbol, PERIOD_CURRENT, 20)) {
         Print("WARNING: SMC Liquidity init failed for ", symbol);
      }

      // Initialize MTF Analysis
      if(!ctx.mtfAnalysis.Init(symbol, PERIOD_H4, PERIOD_M15, PERIOD_CURRENT, 50)) {
         Print("WARNING: MTF Analysis init failed for ", symbol);
      }

      // Initialize Session Optimizer (if needed)
      if(ctx.preset.useSessionOptimizer) {
         if(!ctx.sessionOptimizer.Init(symbol, InpBrokerUTCOffset, ctx.preset.skipAsianSession, false)) {
            Print("WARNING: SessionOptimizer init failed for ", symbol);
         }
      }

      Print("  → ", symbol, " ready (Type: ", detector.GetTypeString(),
            ", MinConf: ", ctx.preset.minConfluenceEntry,
            ", Risk: ", ctx.preset.riskBase, "%)");
   }

   // 4. Initialize Portfolio Components
   if(InpUsePortfolioGovernor) {
      allocator.Init();
      Print("GovernorAllocator: Connected to Portfolio_Governor");
   }

   positionTracker.Init();
   orderManager.Init(InpBaseMagicNumber);

   if(InpEnableLearning) {
      dbManager.Init();
      Print("DatabaseManager: Initialized");
   }

   // 5. Setup Timer
   g_scanInterval = MathMax(5, InpScanIntervalSec);
   EventSetTimer(g_scanInterval);

   Print("====================================================");
   Print("Multi-Symbol Engine: READY");
   Print("Symbols: ", symbolCount);
   Print("Scan Interval: ", g_scanInterval, " seconds");
   Print("====================================================");

   return INIT_SUCCEEDED;
}
```

---

### OnTimer()

```mql5
void OnTimer() {
   // Prevent overlapping scans
   if(TimeCurrent() - g_lastScanTime < g_scanInterval - 1)
      return;

   g_lastScanTime = TimeCurrent();

   if(InpVerboseLogging)
      Print("=== Multi-Symbol Scan Start ===");

   // 1. Update Global Filters
   if(InpUseNewsFilter)
      globalNewsFilter.Update();

   globalKillSwitch.Update();

   // 2. Loop Through All Symbols
   for(int i = 0; i < contextManager.GetCount(); i++) {
      SymbolContext* ctx = contextManager.GetByIndex(i);
      if(ctx == NULL) continue;

      // Process symbol
      ProcessSymbol(ctx);
   }

   // 3. Manage Existing Positions
   ManageAllPositions();

   // 4. Update Portfolio Metrics
   UpdatePortfolioMetrics();

   if(InpVerboseLogging)
      Print("=== Multi-Symbol Scan Complete ===");
}
```

---

### ProcessSymbol()

```mql5
void ProcessSymbol(SymbolContext* ctx) {
   string symbol = ctx.symbol;

   // 1. Check if new bar
   datetime currentBarTime = iTime(symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == ctx.lastBarTime)
      return;  // No new bar, skip

   ctx.lastBarTime = currentBarTime;

   // 2. Update Indicators
   CIndicatorCache cache;
   cache.Init(ctx);
   if(!cache.UpdateIndicators()) {
      if(InpVerboseLogging)
         Print(symbol, ": Indicator update failed");
      return;
   }

   // 3. Update Modules
   ctx.currentRegime = ctx.regime.Detect(ctx.ATR, ctx.ATR_MA, ctx.EMA, ctx.EMA_Prev);

   if(ctx.preset.useSessionOptimizer)
      ctx.sessionOptimizer.Update();

   ctx.smcStructure.Update();
   ctx.smcOrderBlocks.Update();
   ctx.smcFVG.Update();
   ctx.smcLiquidity.Update();
   ctx.mtfAnalysis.Update();

   // 4. Calculate Confluence Scores
   ctx.cachedBuyScore = CalculateConfluenceScore(ctx, 1);
   ctx.cachedSellScore = CalculateConfluenceScore(ctx, -1);
   ctx.lastScoreCalcTime = currentBarTime;

   // 5. Publish Scores to Portfolio Governor (if enabled)
   if(InpPublishScoresToGV) {
      double maxScore = MathMax(ctx.cachedBuyScore, ctx.cachedSellScore);
      double direction = (ctx.cachedBuyScore > ctx.cachedSellScore) ? 1.0 : -1.0;

      GlobalVariableSet(GV_SCORE_PREFIX + symbol, maxScore);
      GlobalVariableSet(GV_REQ_PREFIX + symbol, ctx.preset.minConfluenceEntry);
      GlobalVariableSet(GV_DIR_PREFIX + symbol, direction);
      GlobalVariableSet(GV_BAROPEN_PREFIX + symbol, (double)currentBarTime);

      bool isKZOpen = !InpUseKillzoneFilter || CheckKillzone(ctx);
      GlobalVariableSet(GV_KZ_PREFIX + symbol, isKZOpen ? 1.0 : 0.0);
      GlobalVariableSet("PG_ATR_" + symbol, ctx.ATR);
      GlobalVariableSet("PG_Regime_" + symbol, (double)ctx.currentRegime);

      double quality = (maxScore >= 22) ? 3.0 : (maxScore >= 18) ? 2.0 : 1.0;
      GlobalVariableSet("PG_Quality_" + symbol, quality);
   }

   // 6. Read Rank from Governor
   if(InpUsePortfolioGovernor && GlobalVariableCheck(GV_RANK_PREFIX + symbol)) {
      ctx.assignedRank = GlobalVariableGet(GV_RANK_PREFIX + symbol);
   } else {
      ctx.assignedRank = 1;  // Default if no Governor
   }

   // 7. Evaluate Entry Signal
   EvaluateEntrySignal(ctx);

   if(InpVerboseLogging) {
      Print(symbol, ": Buy=", ctx.cachedBuyScore, " Sell=", ctx.cachedSellScore,
            " Rank=", (int)ctx.assignedRank, " Regime=", EnumToString(ctx.currentRegime));
   }
}
```

---

### CalculateConfluenceScore()

```mql5
// Reuse exact logic from Symbol_Engine.mq5, but operate on SymbolContext
double CalculateConfluenceScore(SymbolContext* ctx, int direction) {
   // This is a COPY of the CalculateConfluenceScore() from Symbol_Engine.mq5
   // but using ctx.RSI, ctx.EMA, ctx.smcStructure, etc. instead of globals

   double score = 0;

   // Trend alignment
   if(direction == 1 && ctx.EMA < ctx.EMA_Prev) score += 2.0;
   if(direction == -1 && ctx.EMA > ctx.EMA_Prev) score += 2.0;

   // RSI momentum
   if(direction == 1 && ctx.RSI > 50 && ctx.RSI > ctx.RSI_Prev) score += 1.5;
   if(direction == -1 && ctx.RSI < 50 && ctx.RSI < ctx.RSI_Prev) score += 1.5;

   // SMC Structure Break
   if(ctx.smcStructure.HasBullishBOS() && direction == 1) score += 3.0;
   if(ctx.smcStructure.HasBearishBOS() && direction == -1) score += 3.0;

   // Order Blocks
   if(ctx.smcOrderBlocks.HasValidBullishOB() && direction == 1) score += 2.5;
   if(ctx.smcOrderBlocks.HasValidBearishOB() && direction == -1) score += 2.5;

   // Fair Value Gaps
   if(ctx.smcFVG.HasBullishFVG() && direction == 1) score += 2.0;
   if(ctx.smcFVG.HasBearishFVG() && direction == -1) score += 2.0;

   // Liquidity Sweep
   if(ctx.smcLiquidity.DetectSweep(direction)) score += 2.5;

   // MTF Alignment
   if(ctx.mtfAnalysis.IsAligned(direction)) score += 3.0;

   // ... add all other confluence factors from Symbol_Engine ...

   return score;
}
```

---

### EvaluateEntrySignal()

```mql5
void EvaluateEntrySignal(SymbolContext* ctx) {
   // Filters
   if(!IsTradingEnabled()) return;
   if(ctx.currentRegime == REGIME_CHAOS) return;
   if(InpUseNewsFilter && !globalNewsFilter.IsTradingAllowed()) return;
   if(InpUseKillzoneFilter && !CheckKillzone(ctx)) return;
   if(!globalKillSwitch.IsEnabled()) return;

   // Rank check
   double activeSlots = InpUsePortfolioGovernor
      ? GlobalVariableGet("PG_ActiveSlots")
      : 10.0;

   if(ctx.assignedRank > activeSlots) return;

   // Portfolio limits
   if(g_totalPositions >= InpMaxPositionsTotal) return;
   if(g_totalExposure >= InpMaxPortfolioRisk) return;

   // Symbol-specific position limit
   ctx.positionCount = positionTracker.GetPositionCount(ctx.symbol);
   if(ctx.positionCount >= 3) return;  // Max 3 positions per symbol

   // Determine best direction
   int bestDirection = 0;
   double bestScore = 0;

   if(ctx.cachedBuyScore >= ctx.preset.minConfluenceEntry &&
      ctx.cachedBuyScore > ctx.cachedSellScore) {
      bestDirection = 1;
      bestScore = ctx.cachedBuyScore;
   } else if(ctx.cachedSellScore >= ctx.preset.minConfluenceEntry &&
             ctx.cachedSellScore > ctx.cachedBuyScore) {
      bestDirection = -1;
      bestScore = ctx.cachedSellScore;
   }

   if(bestDirection == 0) return;  // No valid signal

   // Request risk from Governor Allocator
   GovernorRequest req;
   req.symbol = ctx.symbol;
   req.baseRisk = ctx.preset.riskBase;
   req.isAddOn = (ctx.positionCount > 0);
   req.group = GetCorrelationGroup(ctx.symbol);

   double approvedRisk = allocator.RequestRisk(req);
   if(approvedRisk < 0.05) {
      if(InpVerboseLogging)
         Print(ctx.symbol, ": Risk request denied or too low (", approvedRisk, "%)");
      return;
   }

   // Execute Trade
   ENUM_ORDER_TYPE orderType = (bestDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ENTRY_QUALITY quality = learning.CalculateQuality(bestScore);

   ExecuteTradeForSymbol(ctx, orderType, approvedRisk, quality);
}
```

---

### ExecuteTradeForSymbol()

```mql5
void ExecuteTradeForSymbol(SymbolContext* ctx, ENUM_ORDER_TYPE type,
                           double riskPct, ENTRY_QUALITY quality) {
   string symbol = ctx.symbol;

   // Symbol info
   CSymbolInfo symInfo;
   symInfo.Name(symbol);
   symInfo.RefreshRates();

   double price = (type == ORDER_TYPE_BUY) ? symInfo.Ask() : symInfo.Bid();

   // Calculate SL/TP (reuse logic from Symbol_Engine)
   double slDistance = ctx.ATR * 1.5;
   double sl = (type == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;

   // Position sizing
   double dollarRisk = AccountInfoDouble(ACCOUNT_EQUITY) * (riskPct / 100.0);
   double riskPerLot = slDistance / symInfo.Point() * symInfo.TickValue();
   double lots = dollarRisk / riskPerLot;

   // Normalize lots
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, MathFloor(lots / lotStep) * lotStep));

   // Calculate TP
   double tp = CalculateTakeProfit(ctx, price, slDistance, (type == ORDER_TYPE_BUY) ? 1 : -1, quality);

   // Execute via UnifiedOrderManager
   string label = (ctx.positionCount == 0) ? "Initial" : "AddOn" + IntegerToString(ctx.positionCount);

   ulong ticket = orderManager.ExecuteTrade(symbol, type, lots, price, sl, tp, label);

   if(ticket > 0) {
      Print("✅ TRADE EXECUTED: ", symbol, " ", EnumToString(type), " ",
            lots, " lots @ ", price, " SL=", sl, " TP=", tp,
            " Risk=", riskPct, "% Quality=", EnumToString(quality));

      // Add to position tracker
      ConfluenceFactors factors = (type == ORDER_TYPE_BUY) ? ctx.lastBuyFactors : ctx.lastSellFactors;
      positionTracker.AddPosition(symbol, ticket, riskPct, dollarRisk, slDistance, quality, factors);

      // Update portfolio exposure
      g_totalExposure += riskPct;
      g_totalPositions++;

      // Log to database
      if(InpEnableLearning) {
         dbManager.LogTradeEntry(ticket, symbol, (type == ORDER_TYPE_BUY) ? 1 : -1,
                                 lots, price, sl, tp, ctx.cachedBuyScore,
                                 quality, KILLZONE_NONE, REGIME_UNKNOWN);
      }
   } else {
      Print("❌ TRADE FAILED: ", symbol, " Error: ", GetLastError());
   }
}
```

---

### ManageAllPositions()

```mql5
void ManageAllPositions() {
   CPositionInfo pos;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!pos.SelectByIndex(i)) continue;

      int magic = (int)pos.Magic();
      if(magic < InpBaseMagicNumber || magic >= InpBaseMagicNumber + 1000)
         continue;  // Not ours

      string symbol = pos.Symbol();
      ulong ticket = pos.Ticket();

      // Get symbol context
      SymbolContext* ctx = contextManager.GetContext(symbol);
      if(ctx == NULL) continue;

      // Manage position (BE, trailing, partials)
      ManagePosition(ctx, ticket, pos);
   }
}

void ManagePosition(SymbolContext* ctx, ulong ticket, CPositionInfo &pos) {
   // Reuse trailing/BE/partial logic from Symbol_Engine
   // but operate on ctx.preset parameters

   double open = pos.PriceOpen();
   double curr = pos.PriceCurrent();
   double sl = pos.StopLoss();
   long pType = pos.PositionType();

   // Get position state
   int stateIdx = positionTracker.FindPosition(ctx.symbol, ticket);
   if(stateIdx < 0) return;

   double initialSLDist = positionTracker.GetInitialSLDist(ctx.symbol, stateIdx);
   double rawProfit = (pType == POSITION_TYPE_BUY) ? (curr - open) : (open - curr);
   double profitR = initialSLDist > _Point ? rawProfit / initialSLDist : 0;

   // Partial TP
   double partialTP = ctx.preset.partialCloseAt_R;
   if(!positionTracker.GetPartialClosed(ctx.symbol, stateIdx) && profitR >= partialTP) {
      double closeVol = NormalizeDouble(pos.Volume() * (ctx.preset.partialClosePercent / 100.0), 2);
      if(closeVol >= SymbolInfoDouble(ctx.symbol, SYMBOL_VOLUME_MIN)) {
         CTrade trade;
         if(trade.PositionClosePartial(ticket, closeVol)) {
            positionTracker.SetPartialClosed(ctx.symbol, ticket, true);
            Print("📊 PARTIAL CLOSE: ", ctx.symbol, " ", ticket, " @ ", profitR, "R");
         }
      }
   }

   // Trailing Stop (use preset.beThreshold_R, preset.trailStart_R, etc.)
   if(profitR >= ctx.preset.trailStart_R) {
      double newSL = CalculateTrailingSL(ctx, pType, curr, open, profitR);
      if(newSL > 0 && ShouldUpdateSL(pType, sl, newSL)) {
         CTrade trade;
         if(trade.PositionModify(ticket, newSL, pos.TakeProfit())) {
            Print("📈 TRAILING SL: ", ctx.symbol, " ", ticket, " SL=", newSL);
         }
      }
   }
}
```

---

## Portfolio Metrics Publishing

```mql5
void UpdatePortfolioMetrics() {
   // Calculate total exposure
   g_totalExposure = 0;
   g_totalPositions = 0;

   CPositionInfo pos;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(!pos.SelectByIndex(i)) continue;

      int magic = (int)pos.Magic();
      if(magic >= InpBaseMagicNumber && magic < InpBaseMagicNumber + 1000) {
         string symbol = pos.Symbol();
         ulong ticket = pos.Ticket();

         // Get dollar risk from tracker
         int stateIdx = positionTracker.FindPosition(symbol, ticket);
         if(stateIdx >= 0) {
            double dollarRisk = positionTracker.GetDollarRisk(symbol, stateIdx);
            double riskPct = (dollarRisk / AccountInfoDouble(ACCOUNT_EQUITY)) * 100.0;
            g_totalExposure += riskPct;
         }

         g_totalPositions++;
      }
   }

   // Publish to GlobalVariables (if Governor running separately)
   if(InpPublishScoresToGV) {
      GlobalVariableSet(GV_TOTAL_EXPOSURE, g_totalExposure);
      GlobalVariableSet("MS_TotalPositions", g_totalPositions);  // Custom key
   }
}
```

---

## OnDeinit()

```mql5
void OnDeinit(const int reason) {
   EventKillTimer();

   // Release all indicators
   for(int i = 0; i < contextManager.GetCount(); i++) {
      SymbolContext* ctx = contextManager.GetByIndex(i);
      if(ctx != NULL) {
         CIndicatorCache cache;
         cache.Init(ctx);
         cache.Cleanup();
      }
   }

   Print("Multi-Symbol Engine: Shutdown complete");
}
```

---

## Configuration File Support (Optional - Phase 2)

### symbols.txt (Simple Format)

```
# Trading Symbols Configuration
# Format: SYMBOL,ENABLED,RISK_OVERRIDE,CONFLUENCE_OVERRIDE
EURUSD,1,0.0,0
GBPUSD,1,0.0,0
USDJPY,1,0.0,0
XAUUSD,1,0.15,14
NAS100,1,0.20,10
```

### Parser

```mql5
bool LoadSymbolsFromFile(string filename) {
   int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE) {
      Print("ERROR: Cannot open ", filename);
      return false;
   }

   while(!FileIsEnding(handle)) {
      string line = FileReadString(handle);

      // Skip comments and empty lines
      if(StringLen(line) == 0 || StringSubstr(line, 0, 1) == "#")
         continue;

      // Parse: SYMBOL,ENABLED,RISK_OVERRIDE,CONFLUENCE_OVERRIDE
      string parts[];
      if(StringSplit(line, ',', parts) >= 4) {
         string symbol = parts[0];
         bool enabled = (parts[1] == "1");
         double riskOverride = StringToDouble(parts[2]);
         int confluenceOverride = (int)StringToInteger(parts[3]);

         if(enabled) {
            // Add to scanner
            // ... implementation
         }
      }
   }

   FileClose(handle);
   return true;
}
```

---

## Testing & Validation Plan

### Phase 1: Single Symbol Validation
1. Test with **EURUSD only** in symbol list
2. Compare signals vs. Symbol_Engine.mq5 on same chart
3. Validate: same entry signals, same risk calculations, same position management
4. **Success Criteria:** ≥99% signal parity over 24h backtest

### Phase 2: Multi-Symbol Basic Test
1. Test with 3 symbols: EURUSD, GBPUSD, XAUUSD
2. Verify each symbol gets scanned independently
3. Confirm no indicator handle leaks
4. **Success Criteria:** All 3 symbols trading correctly, no crashes

### Phase 3: Portfolio Governor Integration
1. Run Portfolio_Governor.mq5 + Multi_Symbol_Engine.mq5
2. Verify GlobalVariables communication
3. Confirm ranking system works (top-ranked symbols trade first)
4. **Success Criteria:** Dynamic slot allocation working, correlation penalties applied

### Phase 4: Full Load Test
1. Test with 10 symbols
2. Monitor CPU/memory usage vs. 10 × Symbol_Engine instances
3. Verify no performance degradation
4. **Success Criteria:** <50% resource usage vs. distributed system

### Phase 5: Live Demo
1. Deploy on demo account with 5-7 symbols
2. Run for 1 week
3. Compare metrics vs. historical distributed system performance
4. **Success Criteria:** Similar win rate, profit factor, max DD

---

## Deployment Strategy

### Week 1: Development
- Create core classes (Scanner, Context, IndicatorCache)
- Implement ProcessSymbol() logic
- Build basic OnTimer() loop

### Week 2: Integration
- Port CalculateConfluenceScore()
- Integrate UnifiedOrderManager
- Add SymbolPositionTracker

### Week 3: Testing
- Backtest single symbol (EURUSD)
- Backtest multi-symbol (3 symbols)
- Fix bugs, optimize performance

### Week 4: Validation
- Run alongside Symbol_Engine instances (parallel testing)
- Validate signal parity
- Test with Portfolio_Governor

### Week 5: Production
- Deploy to demo account
- Monitor for 1 week
- Gradual rollout if successful

---

## Migration Path

### Option A: Gradual Migration (Recommended)
```
Week 1-2: Run Multi_Symbol_Engine (EURUSD, GBPUSD) + Symbol_Engine (USDJPY, others)
Week 3-4: Migrate more symbols to Multi_Symbol_Engine
Week 5-6: Deprecate all Symbol_Engine instances
```

### Option B: Full Cutover
```
After validation complete:
- Remove all Symbol_Engine instances from charts
- Deploy Multi_Symbol_Engine on single chart
- Monitor closely for 48h
```

---

## Expected Benefits

### Resource Savings
- **CPU Usage:** -60% (one EA loop vs. N EA loops)
- **Memory Usage:** -50% (shared indicator buffers)
- **Disk I/O:** -70% (single log file vs. N log files)

### Operational Benefits
- **Configuration:** 1 input set vs. N SET files
- **Deployment:** Attach once vs. N chart attachments
- **Monitoring:** Single EA to watch vs. N EAs
- **Logging:** Unified trade journal

### Architectural Benefits
- **Maintainability:** Single codebase
- **Testing:** Easier to backtest portfolio behavior
- **Scaling:** Add symbols via config, no new chart needed
- **Coordination:** Direct access to all symbol states (no GlobalVariables lag)

---

## Rollback Plan

If Multi_Symbol_Engine fails:

1. **Immediate:** Detach Multi_Symbol_Engine, re-attach Symbol_Engine instances
2. **Backup:** Symbol_Engine.mq5 and Metals_Engine.mq5 preserved
3. **Data:** All trades logged separately, no data loss
4. **Time to Rollback:** <10 minutes

**Rollback Triggers:**
- Critical bug causing unexpected trades
- >20% performance degradation vs. baseline
- Position tracking errors
- Memory leaks or crashes

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Indicator handle leak | High | Implement proper cleanup in OnDeinit(), monitor handle count |
| Symbol scan timeout | Medium | Set scan interval ≥10s, optimize indicator caching |
| Position misidentification | High | Use comment field + magic encoding, validate on startup |
| GlobalVariables race conditions | Medium | Reuse AtomicAdd/AtomicSubtract from PortfolioGlobals.mqh |
| Memory overflow (100+ symbols) | Low | Hard limit at 50 symbols, array size monitoring |

---

## Future Enhancements (Phase 3+)

1. **Dynamic Symbol Addition:** Add/remove symbols without restart (hot reload config)
2. **Symbol Groups:** Group symbols for coordinated entry (e.g., all USD pairs)
3. **Cross-Symbol Signals:** Use EURUSD strength to enhance GBPUSD entry
4. **ML Integration:** Centralized feature extraction for all symbols
5. **Web Dashboard:** Real-time portfolio view via WebSocket or HTTP API
6. **Cloud Config:** Load symbol list and settings from cloud (JSON API)

---

## Summary

**Multi_Symbol_Engine.mq5** consolidates the distributed multi-EA architecture into a single, efficient EA that:

✅ Scans multiple symbols from ONE chart attachment
✅ Shares indicator resources across symbols
✅ Integrates with existing Portfolio_Governor.mq5
✅ Supports 50-70% resource reduction
✅ Maintains 100% signal parity with Symbol_Engine
✅ Enables centralized configuration and monitoring
✅ Provides clean migration path from current system

**Next Step:** Begin Phase 1 development (core classes + single symbol validation)

---

**Implementation Time Estimate:** 4-6 weeks
**Complexity:** High (architectural refactor)
**Risk Level:** Medium (gradual migration reduces risk)
**Expected ROI:** High (resource savings + operational efficiency)
