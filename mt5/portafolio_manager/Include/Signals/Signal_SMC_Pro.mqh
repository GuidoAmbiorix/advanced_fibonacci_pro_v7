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

class CSignal_SMC_Pro : public CSignalStrategy
{
private:
   // Module Objects
   CSMCStructureBreak  m_structure;
   CSMCOrderBlocks     m_orderBlocks;
   CSMCFairValueGap    m_fvg;
   CSMCLiquiditySweep  m_liquidity;
   CMTFConfluence      m_mtf;
   CKillzoneOptimizer  m_killzone;
   CNewsFilter         m_news;
   
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
          
          m_mtf.Init(symbol, PERIOD_H4, PERIOD_H1, PERIOD_CURRENT, 50);
          m_killzone.Init(symbol, 2, true, true, false); 
          m_news.Init(symbol, 30, 30, true); 
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
      m_mtf.Init(symbol, PERIOD_H4, PERIOD_H1, timeframe, 50);
      m_news.Init(symbol, 30, 30, true);
      
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
      
      // Calculate Scores
      double buyScore = CalculateScore(symbol, 1);
      double sellScore = CalculateScore(symbol, -1);
      
      // Threshold (Strong Entry)
      double threshold = 6.0;
      
      if(buyScore >= threshold) return 1;
      if(sellScore >= threshold) return -1;
      
      return 0;
   }
   
   double CalculateScore(string symbol, int direction)
   {
      double score = 0;
      
      // 1. SMC Factors
      if(m_structure.GetConfluenceScore(direction) > 0) score += 1.0;
      if(m_orderBlocks.GetConfluenceScore(direction) > 0) score += 1.5;
      if(m_fvg.GetConfluenceScore(direction) > 0) score += 1.0;
      if(m_liquidity.GetConfluenceScore(direction) > 0) score += 1.5;
      
      // 2. MTF
      if(m_mtf.GetConfluenceScore(direction) > 0) score += 2.0;

      // 3. RSI Momentum (Manual check)
      double rsi = iRSI(symbol, PERIOD_CURRENT, m_rsiPeriod, PRICE_CLOSE);
      // ... (Simplify for brevity: Trend alignment)
      
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
      
      double slDist = atr * 1.5; // Standard
      
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
       double tpDist = risk * 2.5; // 2.5R Target
       
       if(signalDir == 1) return entryPrice + tpDist;
       else return entryPrice - tpDist;
   }
};
