//+------------------------------------------------------------------+
//|                                           IndicatorCache.mqh     |
//|                Multi-Symbol Engine - Indicator Management        |
//|          Lazy-loads and caches indicators per symbol             |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7 - Multi-Symbol Engine"
#property version   "1.00"
#property strict

#include "SymbolContext.mqh"

//+------------------------------------------------------------------+
//| Indicator Cache Class                                            |
//| Manages indicator creation, caching, and buffer updates          |
//+------------------------------------------------------------------+
class CIndicatorCache {
private:
   int m_contextIndex;
   CSymbolContextManager* m_manager;
   string m_symbol;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CIndicatorCache() : m_contextIndex(-1), m_manager(NULL), m_symbol("") {}

   //+------------------------------------------------------------------+
   //| Initialize with context manager and index                        |
   //+------------------------------------------------------------------+
   bool Init(CSymbolContextManager* manager, int contextIndex) {
      if(manager == NULL) {
         Print("ERROR: IndicatorCache Init - NULL manager");
         return false;
      }

      if(contextIndex < 0 || contextIndex >= manager.GetCount()) {
         Print("ERROR: IndicatorCache Init - invalid context index");
         return false;
      }

      m_manager = manager;
      m_contextIndex = contextIndex;
      m_symbol = manager.GetContext(contextIndex).symbol;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Load all required indicators for symbol                          |
   //+------------------------------------------------------------------+
   bool LoadIndicators(int emaPeriod = 200, int rsiPeriod = 14) {
      if(m_manager == NULL || m_contextIndex < 0) {
         Print("ERROR: IndicatorCache not initialized");
         return false;
      }

      Print("Loading indicators for ", m_symbol, "...");

      SymbolContext* ctx = m_manager.GetContext(m_contextIndex);
      if(ctx == NULL) {
         Print("ERROR: Failed to get context");
         return false;
      }

      bool success = true;

      // RSI Indicator
      if(ctx->hRSI == INVALID_HANDLE) {
         ctx->hRSI = iRSI(m_symbol, PERIOD_CURRENT, rsiPeriod, PRICE_CLOSE);

         if(ctx->hRSI == INVALID_HANDLE) {
            Print("  ❌ RSI init failed for ", m_symbol, " - Error: ", GetLastError());
            success = false;
         } else {
            Print("  ✅ RSI loaded (period ", rsiPeriod, ")");
         }
      }

      // ATR Indicator
      if(ctx->hATR == INVALID_HANDLE) {
         ctx->hATR = iATR(m_symbol, PERIOD_CURRENT, 14);

         if(ctx->hATR == INVALID_HANDLE) {
            Print("  ❌ ATR init failed for ", m_symbol, " - Error: ", GetLastError());
            success = false;
         } else {
            Print("  ✅ ATR loaded (period 14)");
         }
      }

      // EMA Indicator (Main Trend)
      if(ctx->hEMA == INVALID_HANDLE) {
         ctx->hEMA = iMA(m_symbol, PERIOD_CURRENT, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

         if(ctx->hEMA == INVALID_HANDLE) {
            Print("  ❌ EMA init failed for ", m_symbol, " - Error: ", GetLastError());
            success = false;
         } else {
            Print("  ✅ EMA loaded (period ", emaPeriod, ")");
         }
      }

      // EMA50 (Reversal Filter)
      if(ctx->hEMA50 == INVALID_HANDLE) {
         ctx->hEMA50 = iMA(m_symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);

         if(ctx->hEMA50 == INVALID_HANDLE) {
            Print("  ⚠️ EMA50 init failed for ", m_symbol, " (non-critical)");
         } else {
            Print("  ✅ EMA50 loaded");
         }
      }

      // EMA100 (Reversal Filter)
      if(ctx->hEMA100 == INVALID_HANDLE) {
         ctx->hEMA100 = iMA(m_symbol, PERIOD_CURRENT, 100, 0, MODE_EMA, PRICE_CLOSE);

         if(ctx->hEMA100 == INVALID_HANDLE) {
            Print("  ⚠️ EMA100 init failed for ", m_symbol, " (non-critical)");
         } else {
            Print("  ✅ EMA100 loaded");
         }
      }

      ctx->indicatorsLoaded = success;

      if(success) {
         Print("✅ All indicators loaded for ", m_symbol);
      } else {
         Print("❌ Some indicators failed for ", m_symbol);
      }

      return success;
   }

   //+------------------------------------------------------------------+
   //| Update indicator buffers (call on each new bar)                  |
   //+------------------------------------------------------------------+
   bool UpdateIndicators() {
      if(m_manager == NULL || m_contextIndex < 0) {
         Print("ERROR: IndicatorCache not initialized");
         return false;
      }

      SymbolContext* ctx = m_manager.GetContext(m_contextIndex);
      if(ctx == NULL) {
         Print("ERROR: Failed to get context");
         return false;
      }

      if(!ctx->indicatorsLoaded) {
         Print("WARNING: Indicators not loaded for ", m_symbol);
         return false;
      }

      // Buffers for indicator data
      double rsi[], atr[], ema[], ema50[], ema100[];

      // RSI
      if(ctx->hRSI != INVALID_HANDLE) {
         if(CopyBuffer(ctx->hRSI, 0, 0, 2, rsi) != 2) {
            Print("ERROR: Failed to copy RSI buffer for ", m_symbol);
            return false;
         }

         ctx->RSI_Prev = ctx->RSI;
         ctx->RSI = rsi[0];
      }

      // ATR
      if(ctx->hATR != INVALID_HANDLE) {
         if(CopyBuffer(ctx->hATR, 0, 0, 2, atr) != 2) {
            Print("ERROR: Failed to copy ATR buffer for ", m_symbol);
            return false;
         }

         ctx->ATR = atr[0];

         // Calculate ATR MA (simple moving average of last 20 ATRs)
         double atrArray[];
         if(CopyBuffer(ctx->hATR, 0, 0, 20, atrArray) == 20) {
            ctx->ATR_MA = 0;
            for(int i = 0; i < 20; i++)
               ctx->ATR_MA += atrArray[i];
            ctx->ATR_MA /= 20.0;
         }
      }

      // EMA
      if(ctx->hEMA != INVALID_HANDLE) {
         if(CopyBuffer(ctx->hEMA, 0, 0, 2, ema) != 2) {
            Print("ERROR: Failed to copy EMA buffer for ", m_symbol);
            return false;
         }

         ctx->EMA_Prev = ctx->EMA;
         ctx->EMA = ema[0];
      }

      // EMA50
      if(ctx->hEMA50 != INVALID_HANDLE) {
         if(CopyBuffer(ctx->hEMA50, 0, 0, 2, ema50) == 2) {
            ctx->EMA50_Prev = ctx->EMA50;
            ctx->EMA50 = ema50[0];
         }
      }

      // EMA100
      if(ctx->hEMA100 != INVALID_HANDLE) {
         if(CopyBuffer(ctx->hEMA100, 0, 0, 2, ema100) == 2) {
            ctx->EMA100_Prev = ctx->EMA100;
            ctx->EMA100 = ema100[0];
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Cleanup indicator handles                                        |
   //+------------------------------------------------------------------+
   void Cleanup() {
      SymbolContext* ctx = m_manager.GetContext(m_contextIndex);
      if(ctx == NULL) return;

      Print("Cleaning up indicators for ", m_symbol, "...");

      if(ctx->hRSI != INVALID_HANDLE) {
         IndicatorRelease(ctx->hRSI);
         ctx->hRSI = INVALID_HANDLE;
         Print("  Released RSI");
      }

      if(ctx->hATR != INVALID_HANDLE) {
         IndicatorRelease(ctx->hATR);
         ctx->hATR = INVALID_HANDLE;
         Print("  Released ATR");
      }

      if(ctx->hEMA != INVALID_HANDLE) {
         IndicatorRelease(ctx->hEMA);
         ctx->hEMA = INVALID_HANDLE;
         Print("  Released EMA");
      }

      if(ctx->hEMA50 != INVALID_HANDLE) {
         IndicatorRelease(ctx->hEMA50);
         ctx->hEMA50 = INVALID_HANDLE;
         Print("  Released EMA50");
      }

      if(ctx->hEMA100 != INVALID_HANDLE) {
         IndicatorRelease(ctx->hEMA100);
         ctx->hEMA100 = INVALID_HANDLE;
         Print("  Released EMA100");
      }

      ctx->indicatorsLoaded = false;

      Print("✅ Indicators cleaned up for ", m_symbol);
   }

   //+------------------------------------------------------------------+
   //| Get indicator values summary for logging                         |
   //+------------------------------------------------------------------+
   string GetIndicatorSummary() const {
      const SymbolContext* ctx = m_manager.GetContextConst(m_contextIndex);
      if(ctx == NULL) return "NULL";

      return StringFormat("%s: RSI=%.1f ATR=%.5f EMA=%.5f Regime=%s",
                         m_symbol,
                         ctx->RSI,
                         ctx->ATR,
                         ctx->EMA,
                         EnumToString(ctx->currentRegime));
   }

   //+------------------------------------------------------------------+
   //| Verify all indicators are ready                                  |
   //+------------------------------------------------------------------+
   bool VerifyIndicatorsReady() const {
      const SymbolContext* ctx = m_manager.GetContextConst(m_contextIndex);
      if(ctx == NULL) return false;

      bool ready = true;

      if(ctx->hRSI == INVALID_HANDLE) {
         Print(m_symbol, ": RSI handle invalid");
         ready = false;
      }

      if(ctx->hATR == INVALID_HANDLE) {
         Print(m_symbol, ": ATR handle invalid");
         ready = false;
      }

      if(ctx->hEMA == INVALID_HANDLE) {
         Print(m_symbol, ": EMA handle invalid");
         ready = false;
      }

      // EMA50/100 are optional, don't fail if missing

      return ready;
   }
};
//+------------------------------------------------------------------+
