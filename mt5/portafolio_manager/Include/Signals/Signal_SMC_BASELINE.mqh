//+------------------------------------------------------------------+
//|                                      Signal_SMC_BASELINE.mqh     |
//|          BASELINE VERSION - Old System Only (No New Modules)     |
//|                       For A/B Testing Against Enhanced System    |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

#include "..\SignalInterface.mqh"
// ONLY Core SMC Modules (NO Phase 2 enhancements)
#include "..\SMC_StructureBreak.mqh"
#include "..\SMC_OrderBlocks.mqh"
#include "..\SMC_FairValueGap.mqh"
#include "..\SMC_LiquiditySweep.mqh"
#include "..\NewsFilter.mqh"

//+------------------------------------------------------------------+
//| BASELINE - Old System Before H1 Enhancement                     |
//+------------------------------------------------------------------+
class CSignal_SMC_BASELINE : public CSignalStrategy
{
private:
   // Module Objects (Core SMC ONLY)
   CSMCStructureBreak  m_structure;
   CSMCOrderBlocks     m_orderBlocks;
   CSMCFairValueGap    m_fvg;
   CSMCLiquiditySweep  m_liquidity;
   CMTFConfluence      m_mtf;
   CKillzoneOptimizer  m_killzone;
   CNewsFilter         m_news;

   // Indicators
   int m_hRSI, m_hATR, m_hEMA;

   // Parameters (OLD M15 VALUES)
   int m_rsiPeriod;
   int m_emaPeriod;
   int m_smcLookback;
   double m_smcImpulse;
   bool m_useKillzones;

public:
   CSignal_SMC_BASELINE()
   {
      m_rsiPeriod = 14;
      m_emaPeriod = 200;
      m_smcLookback = 20;    // OLD M15 value (not 45)
      m_smcImpulse = 2.0;    // OLD M15 value (not 2.5)
      m_useKillzones = true;

      m_hRSI = INVALID_HANDLE;
      m_hATR = INVALID_HANDLE;
      m_hEMA = INVALID_HANDLE;
   }

   ~CSignal_SMC_BASELINE()
   {
      ReleaseIndicators();
   }

   bool InitIndicators(string symbol, ENUM_TIMEFRAMES timeframe) override
   {
      Print("=== BASELINE VERSION (Old System) ===");

      m_hRSI = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
      m_hATR = iATR(symbol, timeframe, 14);
      m_hEMA = iMA(symbol, timeframe, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(m_hRSI == INVALID_HANDLE || m_hATR == INVALID_HANDLE || m_hEMA == INVALID_HANDLE)
         return false;

      // Init SMC Modules (OLD PARAMETERS)
      m_structure.Init(symbol, timeframe, 20);  // OLD: 20 (not 45)
      m_orderBlocks.Init(symbol, timeframe, 50, 5, 2.0);  // OLD: 50, 2.0 (not 90, 2.5)
      m_fvg.Init(symbol, timeframe, 50, 10, 0.5);  // OLD: 0.5 (not 0.8)
      m_liquidity.Init(symbol, timeframe, 20);  // OLD: 20 (not 35)

      // OLD MTF: H4 → H1 → Current (not D1 → H4 → H1)
      m_mtf.Init(symbol, PERIOD_H4, PERIOD_H1, timeframe, 50);

      m_killzone.Init(symbol, 2, true, true, false);
      m_news.Init(symbol, 30, 30, true);

      Print("Baseline initialized with OLD M15 parameters");
      return true;
   }

   void ReleaseIndicators()
   {
      if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
      if(m_hEMA != INVALID_HANDLE) IndicatorRelease(m_hEMA);
   }

   int GetSignal(string symbol, ENUM_TIMEFRAMES timeframe) override
   {
      // Re-bind with OLD parameters
      m_structure.Init(symbol, timeframe, 20);
      m_orderBlocks.Init(symbol, timeframe, 50, 5, 2.0);
      m_fvg.Init(symbol, timeframe, 50, 10, 0.5);
      m_liquidity.Init(symbol, timeframe, 20);
      m_mtf.Init(symbol, PERIOD_H4, PERIOD_H1, timeframe, 50);
      m_news.Init(symbol, 30, 30, true);

      // Update Data
      m_structure.Update();
      m_orderBlocks.Update();
      m_fvg.Update();
      m_liquidity.Update();
      m_mtf.Update();
      m_news.Update();

      // News Filter
      if(!m_news.IsTradingAllowed()) return 0;

      // Killzone Check
      if(m_useKillzones)
      {
         m_killzone.Update();
         if(!m_killzone.IsTradingAllowed()) return 0;
      }

      // Calculate Scores (OLD SYSTEM)
      double buyScore = CalculateScoreBaseline(symbol, 1);
      double sellScore = CalculateScoreBaseline(symbol, -1);

      // OLD THRESHOLD: 5.0 out of 7.0 max
      double threshold = 5.0;

      if(buyScore >= threshold) return 1;
      if(sellScore >= threshold) return -1;

      return 0;
   }

   //+------------------------------------------------------------------+
   //| OLD SCORING SYSTEM (7 points max)                               |
   //+------------------------------------------------------------------+
   double CalculateScoreBaseline(string symbol, int direction)
   {
      double score = 0;

      // OLD SYSTEM: Only 7 points max
      // Structure: 1.0, OB: 1.5, FVG: 1.0, Liquidity: 1.5, MTF: 2.0

      if(m_structure.GetConfluenceScore(direction) > 0) score += 1.0;
      if(m_orderBlocks.GetConfluenceScore(direction) > 0) score += 1.5;
      if(m_fvg.GetConfluenceScore(direction) > 0) score += 1.0;
      if(m_liquidity.GetConfluenceScore(direction) > 0) score += 1.5;
      if(m_mtf.GetConfluenceScore(direction) > 0) score += 2.0;

      // NO Volume, NO Currency Strength, NO ICT Advanced
      // NO Breakers, NO Macros, NO Power of 3

      return score;
   }

   //+------------------------------------------------------------------+
   //| OLD STOP LOSS (1.5 ATR, not 2.2)                                |
   //+------------------------------------------------------------------+
   double GetStopLoss(string symbol, int signalDir, double entryPrice) override
   {
      double atr[];
      ArraySetAsSeries(atr, true);

      if(CopyBuffer(m_hATR, 0, 0, 1, atr) <= 0)
         atr[0] = SymbolInfoDouble(symbol, SYMBOL_POINT) * 100;

      double slDist = atr[0] * 1.5; // OLD: 1.5 ATR (not 2.2)

      if(signalDir == 1) return entryPrice - slDist;
      else return entryPrice + slDist;
   }

   //+------------------------------------------------------------------+
   //| OLD TAKE PROFIT (2.5R, not 3.5R)                                |
   //+------------------------------------------------------------------+
   double GetTakeProfit(string symbol, int signalDir, double entryPrice) override
   {
       double sl = GetStopLoss(symbol, signalDir, entryPrice);
       double risk = MathAbs(entryPrice - sl);
       double tpDist = risk * 2.5; // OLD: 2.5R (not 3.5R)

       if(signalDir == 1) return entryPrice + tpDist;
       else return entryPrice - tpDist;
   }
};
