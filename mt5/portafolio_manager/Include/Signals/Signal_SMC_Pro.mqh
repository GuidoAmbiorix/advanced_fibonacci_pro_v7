//+------------------------------------------------------------------+
//|                                              Signal_SMC_Pro.mqh  |
//|          Professional SMC Strategy Module (Ported from v2.0)     |
//|             Structure + Order Blocks + FVG + Liquidity           |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

#include "..\SignalInterface.mqh"
// SMC Modules (Paths relative to Include/)
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

class CSignal_SMC_Pro : public CSignalStrategy
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
   
public:
   CSignal_SMC_Pro()
   {
      m_rsiPeriod = 14;
      m_emaPeriod = 200;
      m_smcLookback = 20;
      m_smcImpulse = 2.0;
      m_useKillzones = true;
      
      m_hRSI = INVALID_HANDLE;
      m_hATR = INVALID_HANDLE;
      m_hEMA = INVALID_HANDLE;
      m_currentSymbol = "";
   }
   
   // Configure Strategy Parameters
   void Configure(int rsi, int ema, int smcLookback, double smcImpulse, bool useKZ)
   {
      m_rsiPeriod = rsi;
      m_emaPeriod = ema;
      m_smcLookback = smcLookback;
      m_smcImpulse = smcImpulse;
      m_useKillzones = useKZ;
   }
   
   ~CSignal_SMC_Pro()
   {
      ReleaseIndicators();
   }
   
   string GetName() override { return "SMC_Pro_v2"; }

   void InitSymbol(string symbol)
   {
       // If symbol changed, release old handles to prevent data contamination
       if(m_currentSymbol != "" && m_currentSymbol != symbol)
       {
           ReleaseIndicators();
       }
       m_currentSymbol = symbol;

       if(m_hRSI == INVALID_HANDLE) {
          m_hRSI = iRSI(symbol, PERIOD_CURRENT, m_rsiPeriod, PRICE_CLOSE);
          m_hATR = iATR(symbol, PERIOD_CURRENT, 14);
          m_hEMA = iMA(symbol, PERIOD_CURRENT, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
          
          // Init SMC Modules
          m_structure.Init(symbol, PERIOD_CURRENT, m_smcLookback);
          m_orderBlocks.Init(symbol, PERIOD_CURRENT, 50, 5, m_smcImpulse);
          m_fvg.Init(symbol, PERIOD_CURRENT, 50, 10, 0.5);
          m_liquidity.Init(symbol, PERIOD_CURRENT, m_smcLookback);

          // H1 Optimized MTF: D1 (macro) → H4 (structure) → H1 (execution)
          m_mtf.Init(symbol, PERIOD_D1, PERIOD_H4, PERIOD_H1, 50);
          m_killzone.Init(symbol, 2, true, true, false);
          m_news.Init(symbol, 30, 30, true);

          // Initialize Phase 2 Modules
          m_volume.Init(symbol, PERIOD_CURRENT, 100, 100);
          m_currencyStrength.Init(PERIOD_CURRENT, 24);
          m_correlation.Init(PERIOD_CURRENT, 50, 0.7);
          m_breakers.Init(symbol, PERIOD_CURRENT, 50, 2.5);
          m_macros.Init(symbol, true);
          m_powerOf3.Init(symbol, PERIOD_CURRENT, 30);
       }
       }
   }
   
   void ReleaseIndicators()
   {
      if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
      if(m_hEMA != INVALID_HANDLE) IndicatorRelease(m_hEMA);
      m_hRSI = INVALID_HANDLE;
   }

   int GetSignal(string symbol, ENUM_TIMEFRAMES timeframe) override
   {
      // Re-bind to current symbol
      m_structure.Init(symbol, timeframe, m_smcLookback);
      m_orderBlocks.Init(symbol, timeframe, 50, 5, m_smcImpulse);
      m_fvg.Init(symbol, timeframe, 50, 10, 0.5);
      m_liquidity.Init(symbol, timeframe, m_smcLookback);
      // H1 Optimized MTF: D1 (macro) → H4 (structure) → H1 (execution)
      m_mtf.Init(symbol, PERIOD_D1, PERIOD_H4, PERIOD_H1, 50);
      m_news.Init(symbol, 30, 30, true);

      // Re-bind Phase 2 modules
      m_volume.Init(symbol, timeframe, 100, 100);
      m_currencyStrength.Init(timeframe, 24);
      m_correlation.Init(timeframe, 50, 0.7);
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
      
      // 1. News Filter Check (Hard Block)
      if(!m_news.IsTradingAllowed()) return 0;
      
      // 2. Killzone Check (using param) - if enabled and outside KZ, reduce score or block?
      // For now, let's keep killzone as a filter inside CalculateScore (bonus points) 
      // OR a hard filter. The user prefers strict logic.
      if(m_useKillzones)
      {
          m_killzone.Update();
          if(!m_killzone.IsTradingAllowed()) return 0; // Hard Block
      }
      
      // Calculate Scores with Enhanced System
      double buyScore = CalculateScore(symbol, 1);
      double sellScore = CalculateScore(symbol, -1);

      // New H1 Thresholds (22 points max):
      // Elite: ≥12 points (54% of max)
      // Strong: ≥9 points (41% of max)
      // Good: ≥7 points (32% of max)
      double eliteThreshold = 12.0;
      double strongThreshold = 9.0;

      if(buyScore >= strongThreshold) return 1;
      if(sellScore >= strongThreshold) return -1;

      return 0;
   }

   double CalculateScore(string symbol, int direction)
   {
      double score = 0;

      // === ENHANCED CONFLUENCE SYSTEM (22 points max) ===

      // 1. Core SMC (5.0 points max)
      if(m_structure.GetConfluenceScore(direction) > 0) score += 1.0;    // Structure break
      if(m_orderBlocks.GetConfluenceScore(direction) > 0) score += 1.5;  // Order blocks
      if(m_fvg.GetConfluenceScore(direction) > 0) score += 1.0;          // Fair Value Gap
      if(m_liquidity.GetConfluenceScore(direction) > 0) score += 1.5;    // Liquidity sweep

      // 2. Advanced ICT (5.5 points max)
      score += m_breakers.GetBreakerScore(direction);                     // 0-2.0 pts
      score += m_macros.GetMacroScore();                                  // 0-1.5 pts
      score += m_powerOf3.GetPhaseScore();                                // 0-2.0 pts (can be negative)

      // 3. Volume Analysis (2.5 points max)
      score += m_volume.GetConfluenceScore(direction);                    // 0-2.5 pts

      // 4. Multi-Timeframe (2.0 points max)
      if(m_mtf.GetConfluenceScore(direction) > 0) score += 2.0;

      // 5. Currency Strength (1.5 points max)
      score += m_currencyStrength.GetConfluenceScore(symbol, direction);  // 0-1.5 pts

      // 6. Fibonacci (1.5 points max) - if available
      // TODO: Add fibonacci module scoring when integrated

      // 7. Regime (1.0 point max) - if ML regime detector available
      // TODO: Add regime scoring when integrated

      // Note: Correlation check is done at portfolio level, not here

      return score;
   }
   
   //+------------------------------------------------------------------+
   //| Stop Loss: ATR Based                                              |
   //+------------------------------------------------------------------+
   double GetStopLoss(string symbol, int signalDir, double entryPrice) override
   {
      double atr = iATR(symbol, PERIOD_CURRENT, 14, 0); // Need handle
      // Fallback if handle issue
      if(atr == 0) atr = SymbolInfoDouble(symbol, SYMBOL_POINT) * 100;

      double slDist = atr * 2.2; // H1 Optimized (was 1.5, now 2.2 for wider stops)

      // Check for Order Block SL
      // Optimized: If we knew WHICH OB triggered, we'd put SL below it.
      // For now, ATR is robust.

      if(signalDir == 1) return entryPrice - slDist;
      else return entryPrice + slDist;
   }
   
   //+------------------------------------------------------------------+
   //| Take Profit: 2R fixed                                             |
   //+------------------------------------------------------------------+
   double GetTakeProfit(string symbol, int signalDir, double entryPrice) override
   {
       double sl = GetStopLoss(symbol, signalDir, entryPrice);
       double risk = MathAbs(entryPrice - sl);
       double tpDist = risk * 3.5; // H1 Optimized: 3.5R Target (was 2.5R)

       if(signalDir == 1) return entryPrice + tpDist;
       else return entryPrice - tpDist;
   }

   //+------------------------------------------------------------------+
   //| Get Detailed Scoring Breakdown (for Dashboard)                  |
   //+------------------------------------------------------------------+
   string GetScoreBreakdown(string symbol, int direction)
   {
      string breakdown = "=== CONFLUENCE BREAKDOWN ===\n";

      // Core SMC
      double smcScore = 0;
      if(m_structure.GetConfluenceScore(direction) > 0) smcScore += 1.0;
      if(m_orderBlocks.GetConfluenceScore(direction) > 0) smcScore += 1.5;
      if(m_fvg.GetConfluenceScore(direction) > 0) smcScore += 1.0;
      if(m_liquidity.GetConfluenceScore(direction) > 0) smcScore += 1.5;
      breakdown += StringFormat("Core SMC: %.1f/5.0\n", smcScore);

      // Advanced ICT
      double breakerScore = m_breakers.GetBreakerScore(direction);
      double macroScore = m_macros.GetMacroScore();
      double po3Score = m_powerOf3.GetPhaseScore();
      double ictScore = breakerScore + macroScore + po3Score;
      breakdown += StringFormat("Advanced ICT: %.1f/5.5\n", ictScore);
      breakdown += StringFormat("  - Breakers: %.1f\n", breakerScore);
      breakdown += StringFormat("  - Macros: %.1f (%s)\n", macroScore, m_macros.GetMacroWindowName());
      breakdown += StringFormat("  - Power of 3: %.1f (%s)\n", po3Score, m_powerOf3.GetPhaseName());

      // Volume
      double volScore = m_volume.GetConfluenceScore(direction);
      breakdown += StringFormat("Volume Analysis: %.1f/2.5\n", volScore);

      // MTF
      double mtfScore = (m_mtf.GetConfluenceScore(direction) > 0) ? 2.0 : 0;
      breakdown += StringFormat("Multi-Timeframe: %.1f/2.0\n", mtfScore);

      // Currency Strength
      double csScore = m_currencyStrength.GetConfluenceScore(symbol, direction);
      double pairStrength = m_currencyStrength.GetPairStrength(symbol);
      breakdown += StringFormat("Currency Strength: %.1f/1.5 (Pair: %.1f)\n", csScore, pairStrength);

      // Total
      double total = smcScore + ictScore + volScore + mtfScore + csScore;
      breakdown += StringFormat("\nTOTAL SCORE: %.1f/22.0\n", total);

      // Rating
      if(total >= 12.0)
         breakdown += "RATING: ELITE\n";
      else if(total >= 9.0)
         breakdown += "RATING: STRONG\n";
      else if(total >= 7.0)
         breakdown += "RATING: GOOD\n";
      else
         breakdown += "RATING: WEAK\n";

      return breakdown;
   }

   //+------------------------------------------------------------------+
   //| Check Correlation Before Entry (Portfolio Level)                |
   //+------------------------------------------------------------------+
   bool CheckCorrelationSafety(string newSymbol, string existingSymbols[])
   {
      return !m_correlation.ShouldBlockTrade(newSymbol, existingSymbols);
   }

   //+------------------------------------------------------------------+
   //| Get Correlation-Adjusted Position Size                          |
   //+------------------------------------------------------------------+
   double GetCorrelationAdjustedSize(string newSymbol, string existingSymbols[], double baseSize)
   {
      return m_correlation.GetCorrelationAdjustedSize(newSymbol, existingSymbols, baseSize);
   }
};
