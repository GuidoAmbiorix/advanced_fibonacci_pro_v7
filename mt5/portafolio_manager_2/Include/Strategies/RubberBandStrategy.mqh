//+------------------------------------------------------------------+
//|                                      RubberBandStrategy.mqh       |
//|                  "The Rubber Band" - Mean Reversion Strategy      |
//|        Price snaps back to center when stretched to extremes      |
//+------------------------------------------------------------------+
#property copyright "Chameleon Multi-Strategy System"
#property version   "1.00"
#property strict

#include "BaseStrategy.mqh"

//+------------------------------------------------------------------+
//| Rubber Band Strategy Class                                        |
//| Active Phase: PHASE_RANGING                                       |
//| Philosophy: "Rubber band snaps back when stretched too far"      |
//+------------------------------------------------------------------+
class CRubberBandStrategy : public CBaseStrategy {
public:
   //--- Constructor
   CRubberBandStrategy() {
      m_strategyName = "RubberBand";
      m_activePhase = PHASE_RANGING;
      m_minConfluence = 10.0; // Lower threshold - ranges have less confirmation
   }

   //--- Destructor
   ~CRubberBandStrategy() {}

   //--- Check entry conditions
   virtual bool CheckEntry(int direction) override {
      // 1. Market Phase Check - MUST be RANGING
      if(!IsPhaseActive()) {
         return false;
      }

      // 2. Price at Range Extremes
      double fib0Buf[1], fib100Buf[1], nearestLevelBuf[1];
      if(CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 12, 0, 1, nearestLevelBuf) <= 0) {
         return false;
      }

      int nearestLevel = (int)nearestLevelBuf[0];

      // Buy: Price near 100% level (swing low / bottom of range)
      if(direction == 1 && nearestLevel != 9) {
         return false;
      }

      // Sell: Price near 0% level (swing high / top of range)
      if(direction == -1 && nearestLevel != 3) {
         return false;
      }

      // 3. RSI INVERTED Logic (mean reversion specific)
      if(m_handleRSI != INVALID_HANDLE) {
         double rsiBuf[1];
         if(CopyBuffer(m_handleRSI, 0, 1, 1, rsiBuf) > 0) {
            // Buy only at oversold (RSI < 30)
            if(direction == 1 && rsiBuf[0] > 30) {
               return false;
            }
            // Sell only at overbought (RSI > 70)
            if(direction == -1 && rsiBuf[0] < 70) {
               return false;
            }
         }
      }

      // 4. Volume Confirmation (LOW volume preferred in ranges)
      double rvol = GetRVOL();
      if(rvol > 1.2) {
         return false; // Too much volume = potential breakout, not reversal
      }

      // 5. Check for fake-out (price briefly went beyond range)
      if(!CheckFakeout(direction, fib0Buf[0], fib100Buf[0])) {
         // Fake-out not required, but adds confluence if present
      }

      // All conditions met
      return true;
   }

   //--- Calculate confluence score
   virtual double GetConfluenceScore(int direction) override {
      double score = 0.0;

      // 1. At Range Extreme = +4.0 pts
      double nearestLevelBuf[1];
      if(CopyBuffer(m_handleFibGolden, 12, 0, 1, nearestLevelBuf) > 0) {
         int nearestLevel = (int)nearestLevelBuf[0];
         if((direction == 1 && nearestLevel == 9) ||  // Buy at bottom
            (direction == -1 && nearestLevel == 3)) { // Sell at top
            score += 4.0;
         }
      }

      // 2. RSI Extreme = +3.0 pts
      if(m_handleRSI != INVALID_HANDLE) {
         double rsiBuf[1];
         if(CopyBuffer(m_handleRSI, 0, 1, 1, rsiBuf) > 0) {
            if(direction == 1) {
               // More extreme oversold = higher score (max 3.0 at RSI 0)
               score += MathMax(0, (30.0 - rsiBuf[0]) / 10.0);
            } else {
               // More extreme overbought = higher score (max 3.0 at RSI 100)
               score += MathMax(0, (rsiBuf[0] - 70.0) / 10.0);
            }
         }
      }

      // 3. Fake-out Bonus = +5.0 pts
      double fib0Buf[1], fib100Buf[1];
      if(CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) > 0 &&
         CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) > 0) {
         if(CheckFakeout(direction, fib0Buf[0], fib100Buf[0])) {
            score += 5.0;
         }
      }

      // 4. Low Volatility = +2.0 pts (ranges need calm)
      double volStateBuf[1];
      if(CopyBuffer(m_handleMarketPhase, 2, 0, 1, volStateBuf) > 0) {
         // Buffer 2: Volatility state (0-100%)
         if(volStateBuf[0] < 30.0) {
            score += 2.0;
         } else if(volStateBuf[0] < 50.0) {
            score += 1.0;
         }
      }

      // 5. Distance from center = +2.0 pts
      double fib50Buf[1];
      if(CopyBuffer(m_handleFibGolden, 6, 0, 1, fib50Buf) > 0 &&
         CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) > 0 &&
         CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) > 0) {
         double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double rangeSize = MathAbs(fib0Buf[0] - fib100Buf[0]);
         double distanceFromCenter = MathAbs(currentPrice - fib50Buf[0]);
         double distanceRatio = distanceFromCenter / (rangeSize / 2.0);
         score += MathMin(2.0, distanceRatio * 2.0); // Max 2.0 pts at extreme
      }

      // Max possible score: 16.0 pts
      return score;
   }

   //--- Get Take Profit levels
   virtual void GetTPLevels(double &tp1, double &tp2, double &tp3) override {
      // Target: Center of range (50% Fib level)
      double fib50Buf[1], fib0Buf[1], fib100Buf[1], swingDirBuf[1];
      if(CopyBuffer(m_handleFibGolden, 6, 0, 1, fib50Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 2, 0, 1, swingDirBuf) <= 0) {
         tp1 = 0; tp2 = 0; tp3 = 0;
         return;
      }

      int swingDirection = (int)swingDirBuf[0];

      // TP1: 50% level (center of range) - R:R ~1:1
      tp1 = fib50Buf[0];

      // TP2: Opposite extreme (R:R ~1:2)
      if(swingDirection == 1) {
         tp2 = fib0Buf[0];  // Buy from bottom, target top
      } else {
         tp2 = fib100Buf[0]; // Sell from top, target bottom
      }

      // TP3: No extension in ranges (same as TP2)
      tp3 = tp2;
   }

   //--- Get Stop Loss level
   virtual double GetStopLoss(int direction) override {
      // Stop loss: Beyond 127.2% extension (outside range + buffer)
      double fib1272Buf[1];
      if(CopyBuffer(m_handleFibGolden, 10, 0, 1, fib1272Buf) <= 0) {
         return 0.0;
      }

      double atr = GetATR();
      double buffer = atr * 0.5; // 50% ATR buffer

      if(direction == 1) {
         // Buy: SL below 127.2% extension (below range)
         return fib1272Buf[0] - buffer;
      } else {
         // Sell: SL above inverse 127.2% extension (above range)
         // Note: For bearish swings, 127.2% is above 0% level
         double fib0Buf[1];
         if(CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) > 0) {
            double range = MathAbs(fib1272Buf[0] - fib0Buf[0]);
            return fib0Buf[0] + range + buffer;
         }
         return fib1272Buf[0] + buffer;
      }
   }

private:
   //--- Check for fake-out (price briefly broke outside range)
   bool CheckFakeout(int direction, double fib0, double fib100) {
      double fib1272Buf[1];
      if(CopyBuffer(m_handleFibGolden, 10, 0, 1, fib1272Buf) <= 0) {
         return false;
      }

      double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Check recent price action (last 3 bars)
      double highs[3], lows[3];
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, 3, highs) != 3 ||
         CopyLow(_Symbol, PERIOD_CURRENT, 1, 3, lows) != 3) {
         return false;
      }

      if(direction == 1) {
         // Buy: Check if price went below 100% level but came back
         for(int i = 0; i < 3; i++) {
            if(lows[i] < fib100 && currentPrice > fib100) {
               return true; // Fake breakdown detected
            }
         }
      } else {
         // Sell: Check if price went above 0% level but came back
         for(int i = 0; i < 3; i++) {
            if(highs[i] > fib0 && currentPrice < fib0) {
               return true; // Fake breakout detected
            }
         }
      }

      return false;
   }
};
