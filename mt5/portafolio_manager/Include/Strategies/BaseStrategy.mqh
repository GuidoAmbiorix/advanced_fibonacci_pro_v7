//+------------------------------------------------------------------+
//|                                              BaseStrategy.mqh     |
//|                        Base Class for All Trading Strategies     |
//|                   Part of Chameleon Multi-Strategy System        |
//+------------------------------------------------------------------+
#property copyright "Chameleon Multi-Strategy System"
#property version   "1.00"
#property strict

//--- Include necessary files
#include <Trade\Trade.mqh>

//--- Market phase enumeration (matches Market_Phase_Analyzer)
enum MARKET_PHASE {
   PHASE_DORMANT = 0,       // Volume < MinVolume, skip trading
   PHASE_TRENDING = 1,      // ADX > 25 + Positive Autocorrelation
   PHASE_RANGING = 2,       // ADX < 20 + Price in Fib 0-100% box
   PHASE_VOLATILE = 3,      // BBW expansion + Price breaking Fib levels
   PHASE_UNDEFINED = 4      // Transition state
};

//+------------------------------------------------------------------+
//| Base Strategy Class                                               |
//+------------------------------------------------------------------+
class CBaseStrategy {
protected:
   //--- Indicator handles
   int m_handleMarketPhase;
   int m_handleFibGolden;
   int m_handleSMC;
   int m_handleVolume;
   int m_handleMTF;
   int m_handleRSI;

   //--- Strategy properties
   string m_strategyName;
   MARKET_PHASE m_activePhase;
   int m_magicNumber;
   double m_minConfluence;

   //--- Trade object
   CTrade m_trade;

   //--- Performance tracking
   int m_totalTrades;
   int m_winningTrades;
   int m_losingTrades;
   double m_totalProfit;
   double m_totalLoss;

public:
   //--- Constructor
   CBaseStrategy() {
      m_strategyName = "BaseStrategy";
      m_activePhase = PHASE_UNDEFINED;
      m_magicNumber = 0;
      m_minConfluence = 10.0;
      m_totalTrades = 0;
      m_winningTrades = 0;
      m_losingTrades = 0;
      m_totalProfit = 0.0;
      m_totalLoss = 0.0;
   }

   //--- Destructor
   virtual ~CBaseStrategy() {}

   //--- Initialization
   virtual bool Init(int marketPhaseHandle, int fibGoldenHandle, int smcHandle, int volumeHandle, int mtfHandle, int rsiHandle) {
      m_handleMarketPhase = marketPhaseHandle;
      m_handleFibGolden = fibGoldenHandle;
      m_handleSMC = smcHandle;
      m_handleVolume = volumeHandle;
      m_handleMTF = mtfHandle;
      m_handleRSI = rsiHandle;

      if(m_handleMarketPhase == INVALID_HANDLE || m_handleFibGolden == INVALID_HANDLE) {
         Print("[", m_strategyName, "] ERROR: Invalid indicator handles");
         return false;
      }

      return true;
   }

   //--- Set strategy properties
   void SetMagicNumber(int magic) { m_magicNumber = magic; }
   void SetMinConfluence(double confluence) { m_minConfluence = confluence; }

   //--- Get strategy info
   string GetName() { return m_strategyName; }
   MARKET_PHASE GetActivePhase() { return m_activePhase; }

   //--- Virtual methods (to be implemented by derived classes)
   virtual bool CheckEntry(int direction) { return false; }
   virtual double GetConfluenceScore(int direction) { return 0.0; }
   virtual void GetTPLevels(double &tp1, double &tp2, double &tp3) { tp1 = 0; tp2 = 0; tp3 = 0; }
   virtual double GetStopLoss(int direction) { return 0.0; }

   //--- Check if current market phase matches strategy
   bool IsPhaseActive() {
      double phaseBuf[1];
      if(CopyBuffer(m_handleMarketPhase, 0, 0, 1, phaseBuf) <= 0) {
         return false;
      }

      MARKET_PHASE currentPhase = (MARKET_PHASE)phaseBuf[0];
      return (currentPhase == m_activePhase);
   }

   //--- Helper: Get RVOL (Relative Volume)
   double GetRVOL() {
      long volumes[20];
      if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, 20, volumes) != 20) {
         return 1.0;
      }

      long currentVol = volumes[0];
      double avgVol = 0;
      for(int i = 1; i < 20; i++) {
         avgVol += (double)volumes[i];  // Cast to double
      }
      avgVol /= 19.0;

      if(avgVol == 0) return 1.0;
      return (double)currentVol / avgVol;
   }

   //--- Helper: Check EMA alignment
   bool IsEMAAligned(int direction) {
      // Get EMA from MTF indicator buffer 0
      if(m_handleMTF == INVALID_HANDLE) return true; // Skip if not available

      double emaBuf[1];
      if(CopyBuffer(m_handleMTF, 0, 0, 1, emaBuf) <= 0) {
         return true; // Don't block on error
      }

      double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(direction == 1) {
         return currentPrice > emaBuf[0]; // Buy: price above EMA
      } else {
         return currentPrice < emaBuf[0]; // Sell: price below EMA
      }
   }

   //--- Helper: Get ATR value
   double GetATR() {
      int atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
      if(atrHandle == INVALID_HANDLE) return 0.0;

      double atrBuf[1];
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) <= 0) {
         IndicatorRelease(atrHandle);
         return 0.0;
      }

      double atr = atrBuf[0];
      IndicatorRelease(atrHandle);
      return atr;
   }

   //--- Helper: Convert pips to price
   double PipsToPrice(double pips) {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
      return pips * pipSize;
   }

   //--- Update performance metrics
   void OnTradeClose(double profit) {
      m_totalTrades++;
      if(profit > 0) {
         m_winningTrades++;
         m_totalProfit += profit;
      } else {
         m_losingTrades++;
         m_totalLoss += MathAbs(profit);
      }
   }

   //--- Get performance metrics
   double GetWinRate() {
      return (m_totalTrades > 0) ? (double)m_winningTrades / m_totalTrades * 100.0 : 0.0;
   }

   double GetProfitFactor() {
      return (m_totalLoss > 0) ? m_totalProfit / m_totalLoss : 0.0;
   }

   int GetTotalTrades() { return m_totalTrades; }
};
