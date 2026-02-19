//+------------------------------------------------------------------+
//|                                           SniperStrategy.mqh      |
//|                         "The Sniper" - Trend Following Strategy  |
//|          Waits for pullback to golden pocket in strong trends    |
//+------------------------------------------------------------------+
#property copyright "Chameleon Multi-Strategy System"
#property version   "1.00"
#property strict

#include "BaseStrategy.mqh"

//+------------------------------------------------------------------+
//| Sniper Strategy Class                                             |
//| Active Phase: PHASE_TRENDING                                      |
//| Philosophy: "Wait for the pullback to the golden pocket"         |
//+------------------------------------------------------------------+
class CSniperStrategy : public CBaseStrategy {
public:
   //--- Constructor
   CSniperStrategy() {
      m_strategyName = "Sniper";
      m_activePhase = PHASE_TRENDING;
      m_minConfluence = 12.0; // Lower threshold - trends are forgiving
   }

   //--- Destructor
   ~CSniperStrategy() {}

   //--- Check entry conditions
   virtual bool CheckEntry(int direction) override {
      // 1. Market Phase Check - MUST be TRENDING
      if(!IsPhaseActive()) {
         return false;
      }

      // 2. Golden Pocket Check
      double inPocketBuf[1], swingDirBuf[1], strengthBuf[1];
      if(CopyBuffer(m_handleFibGolden, 11, 0, 1, inPocketBuf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 2, 0, 1, swingDirBuf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 15, 0, 1, strengthBuf) <= 0) {
         return false;
      }

      // Must be in golden pocket
      if(inPocketBuf[0] != 1.0) {
         return false;
      }

      // Swing direction must match trade direction
      if((int)swingDirBuf[0] != direction) {
         return false;
      }

      // Swing strength should be at least 50%
      if(strengthBuf[0] < 50.0) {
         return false;
      }

      // 3. EMA Alignment (MANDATORY)
      if(!IsEMAAligned(direction)) {
         return false;
      }

      // 4. Structure Break Check (if SMC available)
      if(m_handleSMC != INVALID_HANDLE) {
         double smcStructBuf[1];
         if(CopyBuffer(m_handleSMC, 0, 0, 1, smcStructBuf) > 0) {
            // Buffer 0: Structure break score (0-4 pts)
            if(smcStructBuf[0] < 1.0) {
               return false; // No structure break detected
            }
         }
      }

      // 5. Volume Confirmation (if Volume indicator available)
      if(m_handleVolume != INVALID_HANDLE) {
         double volumeBuf[1];
         // Buffer 2: Buy volume score, Buffer 3: Sell volume score
         int bufferIndex = (direction == 1) ? 2 : 3;
         if(CopyBuffer(m_handleVolume, bufferIndex, 0, 1, volumeBuf) > 0) {
            if(volumeBuf[0] < 2.0) {
               return false; // Weak volume confirmation
            }
         }
      }

      // All conditions met
      return true;
   }

   //--- Calculate confluence score
   virtual double GetConfluenceScore(int direction) override {
      double score = 0.0;

      // 1. Golden Pocket Touch = +5.0 pts
      double inPocketBuf[1];
      if(CopyBuffer(m_handleFibGolden, 11, 0, 1, inPocketBuf) > 0) {
         if(inPocketBuf[0] == 1.0) {
            score += 5.0;
         }
      }

      // 2. Strong Trend Strength = +3.0 pts
      double trendBuf[1];
      if(CopyBuffer(m_handleMarketPhase, 1, 0, 1, trendBuf) > 0) {
         // Buffer 1: Trend strength (0-100%)
         score += (trendBuf[0] / 100.0) * 3.0;
      }

      // 3. Structure Break = +4.0 pts
      if(m_handleSMC != INVALID_HANDLE) {
         double smcBuf[1];
         if(CopyBuffer(m_handleSMC, 0, 0, 1, smcBuf) > 0) {
            score += smcBuf[0]; // Already 0-4 pts
         }
      }

      // 4. Volume Confirmation = +4.0 pts
      if(m_handleVolume != INVALID_HANDLE) {
         double volBuf[1];
         int bufferIndex = (direction == 1) ? 2 : 3;
         if(CopyBuffer(m_handleVolume, bufferIndex, 0, 1, volBuf) > 0) {
            score += volBuf[0]; // Already 0-4 pts
         }
      }

      // 5. Swing Strength Bonus = +2.0 pts
      double strengthBuf[1];
      if(CopyBuffer(m_handleFibGolden, 15, 0, 1, strengthBuf) > 0) {
         score += (strengthBuf[0] / 100.0) * 2.0;
      }

      // Max possible score: 18.0 pts
      return score;
   }

   //--- Get Take Profit levels
   virtual void GetTPLevels(double &tp1, double &tp2, double &tp3) override {
      // Get Fibonacci levels
      double fib100Buf[1], fib618Buf[1], swingDirBuf[1];
      if(CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 7, 0, 1, fib618Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 2, 0, 1, swingDirBuf) <= 0) {
         tp1 = 0; tp2 = 0; tp3 = 0;
         return;
      }

      int swingDirection = (int)swingDirBuf[0];
      double swingRange = MathAbs(fib100Buf[0] - fib618Buf[0]) * (100.0 / 16.8); // Extrapolate full range

      if(swingDirection == 1) {
         // Bullish swing - targets above
         tp1 = fib100Buf[0];                      // 100% level (R:R ~1:1)
         tp2 = fib100Buf[0] + swingRange * 0.618; // 161.8% extension (R:R ~1:2)
         tp3 = fib100Buf[0] + swingRange * 1.618; // 261.8% extension (R:R ~1:4)
      } else {
         // Bearish swing - targets below
         tp1 = fib100Buf[0];                      // 100% level
         tp2 = fib100Buf[0] - swingRange * 0.618; // 161.8% extension
         tp3 = fib100Buf[0] - swingRange * 1.618; // 261.8% extension
      }
   }

   //--- Get Stop Loss level
   virtual double GetStopLoss(int direction) override {
      // Stop loss: Just below golden pocket (78.6% level + buffer)
      double fib786Buf[1];
      if(CopyBuffer(m_handleFibGolden, 8, 0, 1, fib786Buf) <= 0) {
         return 0.0;
      }

      double atr = GetATR();
      double buffer = atr * 0.3; // 30% ATR buffer

      if(direction == 1) {
         // Buy: SL below 78.6% level
         return fib786Buf[0] - buffer;
      } else {
         // Sell: SL above 78.6% level
         return fib786Buf[0] + buffer;
      }
   }
};
