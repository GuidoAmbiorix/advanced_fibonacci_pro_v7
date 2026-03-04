//+------------------------------------------------------------------+
//|                                             SymbolContext.mqh    |
//|                    Multi-Symbol Engine - Per-Symbol State        |
//|           Container for all symbol-specific data and modules     |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7 - Multi-Symbol Engine"
#property version   "1.00"
#property strict

#include "..\Core\SymbolTypeDetector.mqh"
#include "..\Config\UniversalConfig.mqh"
#include "..\Learning_MFE_MAE.mqh"
#include "..\Memory\PatternMemory.mqh"
#include "..\MarketRegime.mqh"
#include "..\SMC_StructureBreak.mqh"
#include "..\SMC_OrderBlocks.mqh"
#include "..\SMC_FairValueGap.mqh"
#include "..\SMC_LiquiditySweep.mqh"
#include "..\MTF_Confluence.mqh"
#include "..\SessionOptimizer.mqh"

//+------------------------------------------------------------------+
//| Symbol Context Class                                             |
//| Holds ALL state for one symbol (previously global in Symbol_Engine) |
//+------------------------------------------------------------------+
class SymbolContext {
public:
   // ===== IDENTITY =====
   string symbol;
   ENUM_SYMBOL_TYPE symbolType;
   SymbolPreset preset;

   // ===== INDICATOR HANDLES =====
   int hRSI;
   int hATR;
   int hEMA;
   int hEMA50;
   int hEMA100;

   // ===== INDICATOR VALUES =====
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

   // ===== SMC MODULE OBJECTS =====
   CSMCStructureBreak smcStructure;
   CSMCOrderBlocks smcOrderBlocks;
   CSMCFairValueGap smcFVG;
   CSMCLiquiditySweep smcLiquidity;

   // ===== ANALYSIS MODULES =====
   CMTFConfluence mtfAnalysis;
   CMarketRegime regime;
   CSessionOptimizer sessionOptimizer;

   // ===== TRADING STATE =====
   datetime lastBarTime;
   int positionCount;
   bool addOn1Triggered;
   bool addOn2Triggered;
   datetime lastTradeTime;

   // ===== CONFLUENCE SCORES (CACHED) =====
   double cachedBuyScore;
   double cachedSellScore;
   datetime lastScoreCalcTime;
   ConfluenceFactors lastBuyFactors;
   ConfluenceFactors lastSellFactors;

   // ===== PORTFOLIO COMMUNICATION =====
   double publishedScore;        // Last score published to GlobalVariables
   double publishedReq;          // Required threshold
   double publishedDir;          // Direction (1.0=Buy, -1.0=Sell)
   double assignedRank;          // Rank assigned by Portfolio Governor

   // ===== MARKET REGIME =====
   MARKET_REGIME currentRegime;

   // ===== RISK & PROTECTION STATE =====
   double dailyLossR;
   int consecutiveLosses;
   datetime lastLossTime;
   int dailyTradesCount;
   datetime lastResetDate;

   // ===== INITIALIZATION FLAGS =====
   bool indicatorsLoaded;
   bool modulesInitialized;

   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   SymbolContext() :
      symbol(""),
      symbolType(SYMBOL_TYPE_UNKNOWN),
      hRSI(INVALID_HANDLE),
      hATR(INVALID_HANDLE),
      hEMA(INVALID_HANDLE),
      hEMA50(INVALID_HANDLE),
      hEMA100(INVALID_HANDLE),
      RSI(0), RSI_Prev(0),
      ATR(0), EMA(0), EMA_Prev(0),
      ATR_MA(0),
      EMA50(0), EMA50_Prev(0),
      EMA100(0), EMA100_Prev(0),
      lastBarTime(0),
      positionCount(0),
      addOn1Triggered(false),
      addOn2Triggered(false),
      lastTradeTime(0),
      cachedBuyScore(0),
      cachedSellScore(0),
      lastScoreCalcTime(0),
      publishedScore(0),
      publishedReq(0),
      publishedDir(0),
      assignedRank(999),
      currentRegime(REGIME_UNKNOWN),
      dailyLossR(0),
      consecutiveLosses(0),
      lastLossTime(0),
      dailyTradesCount(0),
      lastResetDate(0),
      indicatorsLoaded(false),
      modulesInitialized(false)
   {
      // Initialize preset to defaults
      preset.minConfluenceEntry = 0;
      preset.riskBase = 0;
      preset.maxRisk = 0;
   }
};

//+------------------------------------------------------------------+
//| Symbol Context Manager Class                                     |
//| Manages array of SymbolContext objects                          |
//+------------------------------------------------------------------+
class CSymbolContextManager {
private:
   SymbolContext m_contexts[];

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSymbolContextManager() {
      ArrayResize(m_contexts, 0);
   }

   //+------------------------------------------------------------------+
   //| Add new symbol context                                           |
   //+------------------------------------------------------------------+
   bool AddSymbol(string symbol) {
      // Check if already exists
      if(FindIndex(symbol) >= 0) {
         Print("WARNING: Symbol ", symbol, " already exists in context manager");
         return false;
      }

      int sz = ArraySize(m_contexts);
      ArrayResize(m_contexts, sz + 1);

      m_contexts[sz].symbol = symbol;

      Print("SymbolContext added: ", symbol, " (index ", sz, ")");

      return true;
   }

   //+------------------------------------------------------------------+
   //| Find symbol index                                                |
   //+------------------------------------------------------------------+
   int FindIndex(string symbol) {
      for(int i = 0; i < ArraySize(m_contexts); i++)
         if(m_contexts[i].symbol == symbol)
            return i;
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Get context by symbol name (returns index)                       |
   //+------------------------------------------------------------------+
   int GetContextIndex(string symbol) {
      return FindIndex(symbol);
   }

   //+------------------------------------------------------------------+
   //| Get context reference by index (for modification)                |
   //| Usage: contextManager.GetContext(idx).symbol = "EURUSD"         |
   //+------------------------------------------------------------------+
   SymbolContext* GetContext(int index) {
      if(index < 0 || index >= ArraySize(m_contexts))
         return NULL;
      return GetPointer(m_contexts[index]);
   }

   //+------------------------------------------------------------------+
   //| Get const context reference by index (for read-only access)     |
   //+------------------------------------------------------------------+
   const SymbolContext* GetContextConst(int index) const {
      if(index < 0 || index >= ArraySize(m_contexts))
         return NULL;
      return GetPointer(m_contexts[index]);
   }

   //+------------------------------------------------------------------+
   //| Get count of managed symbols                                     |
   //+------------------------------------------------------------------+
   int GetCount() const {
      return ArraySize(m_contexts);
   }

   //+------------------------------------------------------------------+
   //| Remove symbol context                                            |
   //+------------------------------------------------------------------+
   bool RemoveSymbol(string symbol) {
      int idx = FindIndex(symbol);
      if(idx < 0) {
         Print("WARNING: Symbol ", symbol, " not found for removal");
         return false;
      }

      // Cleanup indicator handles before removal
      if(m_contexts[idx].hRSI != INVALID_HANDLE)
         IndicatorRelease(m_contexts[idx].hRSI);
      if(m_contexts[idx].hATR != INVALID_HANDLE)
         IndicatorRelease(m_contexts[idx].hATR);
      if(m_contexts[idx].hEMA != INVALID_HANDLE)
         IndicatorRelease(m_contexts[idx].hEMA);
      if(m_contexts[idx].hEMA50 != INVALID_HANDLE)
         IndicatorRelease(m_contexts[idx].hEMA50);
      if(m_contexts[idx].hEMA100 != INVALID_HANDLE)
         IndicatorRelease(m_contexts[idx].hEMA100);

      // Shift array elements
      for(int i = idx; i < ArraySize(m_contexts) - 1; i++)
         m_contexts[i] = m_contexts[i + 1];

      ArrayResize(m_contexts, ArraySize(m_contexts) - 1);

      Print("SymbolContext removed: ", symbol);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Clear all contexts (cleanup on deinit)                           |
   //+------------------------------------------------------------------+
   void Clear() {
      Print("Clearing ", ArraySize(m_contexts), " symbol contexts...");

      for(int i = 0; i < ArraySize(m_contexts); i++) {
         // Release indicator handles
         if(m_contexts[i].hRSI != INVALID_HANDLE)
            IndicatorRelease(m_contexts[i].hRSI);
         if(m_contexts[i].hATR != INVALID_HANDLE)
            IndicatorRelease(m_contexts[i].hATR);
         if(m_contexts[i].hEMA != INVALID_HANDLE)
            IndicatorRelease(m_contexts[i].hEMA);
         if(m_contexts[i].hEMA50 != INVALID_HANDLE)
            IndicatorRelease(m_contexts[i].hEMA50);
         if(m_contexts[i].hEMA100 != INVALID_HANDLE)
            IndicatorRelease(m_contexts[i].hEMA100);
      }

      ArrayFree(m_contexts);

      Print("SymbolContextManager cleared");
   }

   //+------------------------------------------------------------------+
   //| Print summary of all contexts                                    |
   //+------------------------------------------------------------------+
   void PrintSummary() const {
      Print("====== SYMBOL CONTEXT SUMMARY ======");
      Print("Total Symbols: ", ArraySize(m_contexts));

      for(int i = 0; i < ArraySize(m_contexts); i++) {
         Print("  [", i, "] ", m_contexts[i].symbol,
               " Type=", EnumToString(m_contexts[i].symbolType),
               " Indicators=", m_contexts[i].indicatorsLoaded ? "Loaded" : "NOT Loaded",
               " Rank=", (int)m_contexts[i].assignedRank);
      }

      Print("====================================");
   }

   //+------------------------------------------------------------------+
   //| Reset daily counters for all symbols                             |
   //+------------------------------------------------------------------+
   void ResetDailyCounters() {
      datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

      for(int i = 0; i < ArraySize(m_contexts); i++) {
         if(m_contexts[i].lastResetDate != today) {
            m_contexts[i].dailyTradesCount = 0;
            m_contexts[i].dailyLossR = 0;
            m_contexts[i].consecutiveLosses = 0;
            m_contexts[i].lastResetDate = today;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get total positions across all symbols                           |
   //+------------------------------------------------------------------+
   int GetTotalPositions() const {
      int total = 0;
      for(int i = 0; i < ArraySize(m_contexts); i++)
         total += m_contexts[i].positionCount;
      return total;
   }
};
//+------------------------------------------------------------------+
