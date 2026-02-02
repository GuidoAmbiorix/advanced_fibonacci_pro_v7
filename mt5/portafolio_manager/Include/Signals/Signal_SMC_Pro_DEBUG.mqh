//+------------------------------------------------------------------+
//|                                      Signal_SMC_Pro_DEBUG.mqh    |
//|          EMERGENCY DEBUG VERSION - Comprehensive Logging         |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

#include "..\SignalInterface.mqh"
// SMC Modules
#include "..\SMC_StructureBreak.mqh"
#include "..\SMC_OrderBlocks.mqh"
#include "..\SMC_FairValueGap.mqh"
#include "..\SMC_LiquiditySweep.mqh"
#include "..\NewsFilter.mqh"

// Phase 2 Enhancement Modules
#include "..\VolumeAnalysis.mqh"
#include "..\CurrencyStrength.mqh"
#include "..\CorrelationMatrix.mqh"
#include "..\SMC_BreakerBlocks.mqh"
#include "..\ICT_MacroWindows.mqh"
#include "..\ICT_PowerOf3.mqh"

//+------------------------------------------------------------------+
//| DEBUG SETTINGS                                                   |
//+------------------------------------------------------------------+
#define DEBUG_SCORING true
#define DEBUG_MODULES true
#define DEBUG_EXITS true
#define LOG_TO_FILE true

class CSignal_SMC_Pro_DEBUG : public CSignalStrategy
{
private:
   // Module Objects (Core SMC)
   CSMCStructureBreak  m_structure;
   CSMCOrderBlocks     m_orderBlocks;
   CSMCFairValueGap    m_fvg;
   CSMCLiquiditySweep  m_liquidity;
   CMTFConfluence      m_mtf;
   CKillzoneOptimizer  m_killzone;
   CNewsFilter         m_news;

   // Phase 2 Enhancement Modules
   CVolumeAnalysis     m_volume;
   CCurrencyStrength   m_currencyStrength;
   CCorrelationMatrix  m_correlation;
   CBreakerBlocks      m_breakers;
   CICTMacroWindows    m_macros;
   CICTPowerOf3        m_powerOf3;

   // Indicators
   int m_hRSI, m_hATR, m_hEMA;

   // Parameters
   int m_rsiPeriod;
   int m_emaPeriod;
   int m_smcLookback;
   double m_smcImpulse;
   bool m_useKillzones;

   // Debug counters
   int m_signalCount;
   int m_tradeCount;

public:
   CSignal_SMC_Pro_DEBUG()
   {
      m_rsiPeriod = 14;
      m_emaPeriod = 200;
      m_smcLookback = 45;  // H1 optimized
      m_smcImpulse = 2.5;   // H1 optimized
      m_useKillzones = true;

      m_hRSI = INVALID_HANDLE;
      m_hATR = INVALID_HANDLE;
      m_hEMA = INVALID_HANDLE;

      m_signalCount = 0;
      m_tradeCount = 0;
   }

   ~CSignal_SMC_Pro_DEBUG()
   {
      ReleaseIndicators();
      WriteDebugSummary();
   }

   bool InitIndicators(string symbol, ENUM_TIMEFRAMES timeframe) override
   {
      Print("=== INITIALIZING DEBUG VERSION ===");
      Print("Symbol: ", symbol, " | Timeframe: H1");

      if(symbol == "" || timeframe == PERIOD_CURRENT)
      {
         Print("ERROR: Invalid symbol or timeframe");
         return false;
      }

      m_hRSI = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
      m_hATR = iATR(symbol, timeframe, 14);
      m_hEMA = iMA(symbol, timeframe, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(m_hRSI == INVALID_HANDLE || m_hATR == INVALID_HANDLE || m_hEMA == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create indicators");
         return false;
      }

      // Init SMC Modules
      Print("Initializing Core SMC Modules...");
      m_structure.Init(symbol, timeframe, m_smcLookback);
      m_orderBlocks.Init(symbol, timeframe, 90, 5, m_smcImpulse);
      m_fvg.Init(symbol, timeframe, 80, 10, 0.8);
      m_liquidity.Init(symbol, timeframe, m_smcLookback);
      m_mtf.Init(symbol, PERIOD_D1, PERIOD_H4, PERIOD_H1, 50);
      m_killzone.Init(symbol, 2, true, true, false);
      m_news.Init(symbol, 30, 30, true);

      // Initialize Phase 2 Modules
      Print("Initializing Phase 2 Enhancement Modules...");
      m_volume.Init(symbol, timeframe, 100, 100);
      m_currencyStrength.Init(timeframe, 24);
      m_correlation.Init(timeframe, 50, 0.7);
      m_breakers.Init(symbol, timeframe, 50, 2.5);
      m_macros.Init(symbol, true);
      m_powerOf3.Init(symbol, timeframe, 30);

      Print("=== INITIALIZATION COMPLETE ===");
      TestModules(symbol, timeframe);

      return true;
   }

   void ReleaseIndicators()
   {
      if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
      if(m_hEMA != INVALID_HANDLE) IndicatorRelease(m_hEMA);
   }

   //+------------------------------------------------------------------+
   //| TEST MODULES ON INITIALIZATION                                  |
   //+------------------------------------------------------------------+
   void TestModules(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      Print("\n=== MODULE FUNCTIONALITY TEST ===");

      // Test Volume Analysis
      Print("\n--- Volume Analysis ---");
      double poc = m_volume.GetPOC();
      double vwap = m_volume.GetVWAP();
      double volScore = m_volume.GetConfluenceScore(1);
      Print("POC: ", poc, " | VWAP: ", vwap, " | Score: ", volScore);
      if(poc == 0 && vwap == 0) Print("⚠️ WARNING: Volume module returning zeros!");

      // Test Currency Strength
      Print("\n--- Currency Strength ---");
      double eurStr = m_currencyStrength.GetCurrencyStrength("EUR");
      double usdStr = m_currencyStrength.GetCurrencyStrength("USD");
      double pairStr = m_currencyStrength.GetPairStrength(symbol);
      Print("EUR: ", eurStr, " | USD: ", usdStr, " | Pair: ", pairStr);
      if(eurStr == 0 && usdStr == 0) Print("⚠️ WARNING: Currency Strength returning zeros!");

      // Test Power of 3
      Print("\n--- Power of 3 ---");
      string phase = m_powerOf3.GetPhaseName();
      double po3Score = m_powerOf3.GetPhaseScore();
      Print("Phase: ", phase, " | Score: ", po3Score);
      if(phase == "Unknown Phase") Print("⚠️ WARNING: Power of 3 always unknown!");

      // Test Macro Windows
      Print("\n--- Macro Windows ---");
      string window = m_macros.GetMacroWindowName();
      double macroScore = m_macros.GetMacroScore();
      Print("Window: ", window, " | Score: ", macroScore);

      // Test Breaker Blocks
      Print("\n--- Breaker Blocks ---");
      double breakerScore = m_breakers.GetBreakerScore(1);
      int breakerCount = m_breakers.GetActiveBreakerCount();
      Print("Score: ", breakerScore, " | Active Breakers: ", breakerCount);

      Print("\n=== MODULE TEST COMPLETE ===\n");
   }

   //+------------------------------------------------------------------+
   //| GET SIGNAL WITH COMPREHENSIVE LOGGING                           |
   //+------------------------------------------------------------------+
   int GetSignal(string symbol, ENUM_TIMEFRAMES timeframe) override
   {
      m_signalCount++;

      // Re-bind to current symbol
      m_structure.Init(symbol, timeframe, m_smcLookback);
      m_orderBlocks.Init(symbol, timeframe, 90, 5, m_smcImpulse);
      m_fvg.Init(symbol, timeframe, 80, 10, 0.8);
      m_liquidity.Init(symbol, timeframe, m_smcLookback);
      m_mtf.Init(symbol, PERIOD_D1, PERIOD_H4, PERIOD_H1, 50);
      m_news.Init(symbol, 30, 30, true);

      // Re-bind Phase 2 modules
      m_volume.Init(symbol, timeframe, 100, 100);
      m_currencyStrength.Init(timeframe, 24);
      m_breakers.Init(symbol, timeframe, 50, 2.5);
      m_macros.Init(symbol, true);
      m_powerOf3.Init(symbol, timeframe, 30);

      // Update Data
      m_structure.Update();
      m_orderBlocks.Update();
      m_fvg.Update();
      m_liquidity.Update();
      m_mtf.Update();
      m_news.Update();

      // News Filter Check
      if(!m_news.IsTradingAllowed())
      {
         if(DEBUG_SCORING) Print("Signal blocked: News filter");
         return 0;
      }

      // Killzone Check
      if(m_useKillzones)
      {
         m_killzone.Update();
         if(!m_killzone.IsTradingAllowed())
         {
            if(DEBUG_SCORING) Print("Signal blocked: Killzone");
            return 0;
         }
      }

      // Calculate Scores
      double buyScore = CalculateScoreDebug(symbol, 1);
      double sellScore = CalculateScoreDebug(symbol, -1);

      // Thresholds
      double strongThreshold = 12.0;

      if(DEBUG_SCORING && (buyScore >= 8.0 || sellScore >= 8.0))
      {
         Print("\n╔════════════════════════════════════════╗");
         Print("║        SIGNAL EVALUATION #", m_signalCount, "        ║");
         Print("╚════════════════════════════════════════╝");
         Print("Symbol: ", symbol, " | Time: ", TimeToString(TimeCurrent()));
         Print("BUY Score:  ", DoubleToString(buyScore, 2), " / 22.0");
         Print("SELL Score: ", DoubleToString(sellScore, 2), " / 22.0");
         Print("Threshold:  ", strongThreshold);
         Print("─────────────────────────────────────────");
      }

      if(buyScore >= strongThreshold)
      {
         m_tradeCount++;
         if(DEBUG_SCORING)
         {
            Print("✅ BUY SIGNAL GENERATED (Trade #", m_tradeCount, ")");
            Print("════════════════════════════════════════\n");
         }
         LogTradeToFile(symbol, 1, buyScore);
         return 1;
      }

      if(sellScore >= strongThreshold)
      {
         m_tradeCount++;
         if(DEBUG_SCORING)
         {
            Print("✅ SELL SIGNAL GENERATED (Trade #", m_tradeCount, ")");
            Print("════════════════════════════════════════\n");
         }
         LogTradeToFile(symbol, -1, sellScore);
         return -1;
      }

      return 0;
   }

   //+------------------------------------------------------------------+
   //| CALCULATE SCORE WITH DEBUG LOGGING                              |
   //+------------------------------------------------------------------+
   double CalculateScoreDebug(string symbol, int direction)
   {
      double score = 0;

      if(DEBUG_SCORING)
      {
         Print("\n┌─ Score Calculation (", (direction == 1 ? "BUY" : "SELL"), ") ─┐");
      }

      // 1. Core SMC (5.0 points max)
      double smcStructure = (m_structure.GetConfluenceScore(direction) > 0) ? 1.0 : 0;
      double smcOB = (m_orderBlocks.GetConfluenceScore(direction) > 0) ? 1.5 : 0;
      double smcFVG = (m_fvg.GetConfluenceScore(direction) > 0) ? 1.0 : 0;
      double smcLiq = (m_liquidity.GetConfluenceScore(direction) > 0) ? 1.5 : 0;
      double smcTotal = smcStructure + smcOB + smcFVG + smcLiq;
      score += smcTotal;

      if(DEBUG_SCORING)
      {
         Print("│ Core SMC: ", DoubleToString(smcTotal, 1), " / 5.0");
         Print("│   Structure: ", smcStructure, " | OB: ", smcOB);
         Print("│   FVG: ", smcFVG, " | Liquidity: ", smcLiq);
      }

      // 2. Advanced ICT (5.5 points max)
      double breakerScore = m_breakers.GetBreakerScore(direction);
      double macroScore = m_macros.GetMacroScore();
      double po3Score = m_powerOf3.GetPhaseScore();
      double ictTotal = breakerScore + macroScore + po3Score;
      score += ictTotal;

      if(DEBUG_SCORING)
      {
         Print("│ Advanced ICT: ", DoubleToString(ictTotal, 1), " / 5.5");
         Print("│   Breakers: ", breakerScore, " / 2.0");
         Print("│   Macros: ", macroScore, " / 1.5 (", m_macros.GetMacroWindowName(), ")");
         Print("│   Power of 3: ", po3Score, " / 2.0 (", m_powerOf3.GetPhaseName(), ")");
         if(po3Score < 0) Print("│   ⚠️ NEGATIVE PO3 - Manipulation phase detected!");
      }

      // 3. Volume Analysis (2.5 points max)
      double volScore = m_volume.GetConfluenceScore(direction);
      score += volScore;

      if(DEBUG_SCORING)
      {
         Print("│ Volume: ", DoubleToString(volScore, 1), " / 2.5");
         Print("│   POC: ", m_volume.GetPOC());
         Print("│   VWAP: ", m_volume.GetVWAP());
      }

      // 4. Multi-Timeframe (2.0 points max)
      double mtfScore = (m_mtf.GetConfluenceScore(direction) > 0) ? 2.0 : 0;
      score += mtfScore;

      if(DEBUG_SCORING)
      {
         Print("│ MTF Alignment: ", DoubleToString(mtfScore, 1), " / 2.0");
      }

      // 5. Currency Strength (1.5 points max)
      double csScore = m_currencyStrength.GetConfluenceScore(symbol, direction);
      double pairStrength = m_currencyStrength.GetPairStrength(symbol);
      score += csScore;

      if(DEBUG_SCORING)
      {
         Print("│ Currency Strength: ", DoubleToString(csScore, 1), " / 1.5");
         Print("│   Pair Strength: ", DoubleToString(pairStrength, 1));
      }

      if(DEBUG_SCORING)
      {
         Print("├────────────────────────────┤");
         Print("│ TOTAL SCORE: ", DoubleToString(score, 2), " / 22.0");
         Print("│ Percentage: ", DoubleToString((score/22.0)*100, 1), "%");
         Print("└────────────────────────────┘");
      }

      return score;
   }

   //+------------------------------------------------------------------+
   //| LOG TRADE TO CSV FILE                                           |
   //+------------------------------------------------------------------+
   void LogTradeToFile(string symbol, int direction, double score)
   {
      if(!LOG_TO_FILE) return;

      string filename = "trade_log_debug.csv";
      int handle = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON);

      if(handle == INVALID_HANDLE)
      {
         Print("ERROR: Cannot open log file");
         return;
      }

      FileSeek(handle, 0, SEEK_END);

      // Write header if file is empty
      if(FileSize(handle) == 0)
      {
         FileWrite(handle, "Time", "Symbol", "Direction", "TotalScore",
                   "CoreSMC", "AdvancedICT", "Volume", "MTF", "Currency",
                   "BreakerScore", "MacroScore", "PO3Score", "MacroWindow", "PO3Phase");
      }

      // Get component scores
      double smcTotal = 0;
      if(m_structure.GetConfluenceScore(direction) > 0) smcTotal += 1.0;
      if(m_orderBlocks.GetConfluenceScore(direction) > 0) smcTotal += 1.5;
      if(m_fvg.GetConfluenceScore(direction) > 0) smcTotal += 1.0;
      if(m_liquidity.GetConfluenceScore(direction) > 0) smcTotal += 1.5;

      double breakerScore = m_breakers.GetBreakerScore(direction);
      double macroScore = m_macros.GetMacroScore();
      double po3Score = m_powerOf3.GetPhaseScore();
      double ictTotal = breakerScore + macroScore + po3Score;

      double volScore = m_volume.GetConfluenceScore(direction);
      double mtfScore = (m_mtf.GetConfluenceScore(direction) > 0) ? 2.0 : 0;
      double csScore = m_currencyStrength.GetConfluenceScore(symbol, direction);

      // Write data
      FileWrite(handle,
         TimeToString(TimeCurrent()),
         symbol,
         (direction == 1 ? "BUY" : "SELL"),
         DoubleToString(score, 2),
         DoubleToString(smcTotal, 2),
         DoubleToString(ictTotal, 2),
         DoubleToString(volScore, 2),
         DoubleToString(mtfScore, 2),
         DoubleToString(csScore, 2),
         DoubleToString(breakerScore, 2),
         DoubleToString(macroScore, 2),
         DoubleToString(po3Score, 2),
         m_macros.GetMacroWindowName(),
         m_powerOf3.GetPhaseName()
      );

      FileClose(handle);
   }

   //+------------------------------------------------------------------+
   //| STOP LOSS WITH DEBUG                                            |
   //+------------------------------------------------------------------+
   double GetStopLoss(string symbol, int signalDir, double entryPrice) override
   {
      double atr[];
      ArraySetAsSeries(atr, true);

      if(CopyBuffer(m_hATR, 0, 0, 1, atr) <= 0)
      {
         Print("ERROR: Cannot get ATR");
         atr[0] = SymbolInfoDouble(symbol, SYMBOL_POINT) * 100;
      }

      double slDist = atr[0] * 2.2; // H1 Optimized
      double slPrice = (signalDir == 1) ? entryPrice - slDist : entryPrice + slDist;

      if(DEBUG_EXITS)
      {
         Print("\n=== STOP LOSS DEBUG ===");
         Print("Entry: ", entryPrice);
         Print("ATR: ", atr[0]);
         Print("SL Distance: ", slDist, " (", DoubleToString(slDist/atr[0], 2), " ATR)");
         Print("SL Price: ", slPrice);
         Print("Risk Points: ", DoubleToString(MathAbs(entryPrice - slPrice)/SymbolInfoDouble(symbol, SYMBOL_POINT), 0));
      }

      return slPrice;
   }

   //+------------------------------------------------------------------+
   //| TAKE PROFIT WITH DEBUG                                          |
   //+------------------------------------------------------------------+
   double GetTakeProfit(string symbol, int signalDir, double entryPrice) override
   {
       double sl = GetStopLoss(symbol, signalDir, entryPrice);
       double risk = MathAbs(entryPrice - sl);
       double tpDist = risk * 3.5; // H1 Optimized: 3.5R Target
       double tpPrice = (signalDir == 1) ? entryPrice + tpDist : entryPrice - tpDist;

       if(DEBUG_EXITS)
       {
          Print("\n=== TAKE PROFIT DEBUG ===");
          Print("Risk: ", risk);
          Print("TP Distance: ", tpDist, " (3.5R)");
          Print("TP Price: ", tpPrice);
          Print("R-Multiple: 3.5R");
          Print("Reward:Risk = ", DoubleToString(tpDist/risk, 2), ":1");
       }

       return tpPrice;
   }

   //+------------------------------------------------------------------+
   //| WRITE DEBUG SUMMARY ON DEINIT                                   |
   //+------------------------------------------------------------------+
   void WriteDebugSummary()
   {
      Print("\n╔════════════════════════════════════════╗");
      Print("║       DEBUG SESSION SUMMARY            ║");
      Print("╚════════════════════════════════════════╝");
      Print("Total Signals Evaluated: ", m_signalCount);
      Print("Total Trades Generated: ", m_tradeCount);
      if(m_signalCount > 0)
         Print("Signal to Trade Ratio: ", DoubleToString((double)m_tradeCount/m_signalCount*100, 2), "%");
      Print("════════════════════════════════════════\n");

      Print("📊 Check Files:");
      Print("  - Common Files/trade_log_debug.csv");
      Print("  - Experts tab for detailed logs");
   }
};
