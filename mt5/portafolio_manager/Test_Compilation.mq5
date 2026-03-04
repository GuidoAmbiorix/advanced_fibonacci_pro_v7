//+------------------------------------------------------------------+
//|                                          Test_Compilation.mq5    |
//|                                  Test Multi-Symbol Engine Fixes  |
//+------------------------------------------------------------------+
#property copyright "Test"
#property version   "1.00"
#property strict

#include "Include\MultiSymbol\SymbolScanner.mqh"
#include "Include\MultiSymbol\SymbolContext.mqh"
#include "Include\MultiSymbol\IndicatorCache.mqh"

CSymbolContextManager g_contextManager;

int OnInit() {
   Print("Testing compilation...");

   // Test adding a symbol
   g_contextManager.AddSymbol("EURUSD");

   // Test getting context
   int idx = g_contextManager.GetContextIndex("EURUSD");
   if(idx >= 0) {
      SymbolContext* ctx = g_contextManager.GetContext(idx);
      if(ctx != NULL) {
         ctx.symbol = "EURUSD";
         ctx.symbolType = SYMBOL_TYPE_FOREX;
         Print("Context accessed successfully: ", ctx.symbol);
      }
   }

   // Test indicator cache
   CIndicatorCache cache;
   if(idx >= 0) {
      cache.Init(GetPointer(g_contextManager), idx);
   }

   Print("Compilation test successful!");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   g_contextManager.Clear();
}

void OnTick() {
   // Empty
}
//+------------------------------------------------------------------+
