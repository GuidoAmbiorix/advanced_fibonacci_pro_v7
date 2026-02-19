//+------------------------------------------------------------------+
//|                                       BreakoutStrategy.mqh        |
//|                 "The Breakout" - Volatility Expansion Strategy    |
//|              When the rubber band snaps, ride the momentum        |
//+------------------------------------------------------------------+
#property copyright "Chameleon Multi-Strategy System"
#property version   "1.00"
#property strict

#include "BaseStrategy.mqh"

//+------------------------------------------------------------------+
//| Breakout Strategy Class                                           |
//| Active Phase: PHASE_VOLATILE                                      |
//| Philosophy: "When the rubber band snaps, ride the momentum"      |
//+------------------------------------------------------------------+
class CBreakoutStrategy : public CBaseStrategy {
public:
   //--- Constructor
   CBreakoutStrategy() {
      m_strategyName = "Breakout";
      m_activePhase = PHASE_VOLATILE;
      m_minConfluence = 14.0; // Higher threshold - breakouts need strong confirmation
   }

   //--- Destructor
   ~CBreakoutStrategy() {}

   //--- Check entry conditions
   virtual bool CheckEntry(int direction) override {
      // 1. Market Phase Check - MUST be VOLATILE
      if(!IsPhaseActive()) {
         return false;
      }

      // 2. Candle Close Beyond Fib Extremes
      double fib0Buf[1], fib100Buf[1];
      if(CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) <= 0) {
         return false;
      }

      double close = iClose(_Symbol, PERIOD_CURRENT, 1);

      bool bullishBreakout = (direction == 1 && close > fib0Buf[0]);
      bool bearishBreakout = (direction == -1 && close < fib100Buf[0]);

      if(!bullishBreakout && !bearishBreakout) {
         return false;
      }

      // 3. Volume Surge (minimum 2x normal)
      double rvol = GetRVOL();
      if(rvol < 2.0) {
         return false; // Need strong volume for valid breakout
      }

      // 4. Momentum Confirmation (Strong directional candle)
      double range = iHigh(_Symbol, PERIOD_CURRENT, 1) - iLow(_Symbol, PERIOD_CURRENT, 1);
      double body = MathAbs(iClose(_Symbol, PERIOD_CURRENT, 1) - iOpen(_Symbol, PERIOD_CURRENT, 1));

      if(range == 0) return false;

      double bodyRatio = body / range;
      if(bodyRatio < 0.6) {
         return false; // Need strong directional candle (60%+ body)
      }

      // 5. No Major Resistance Ahead (check SMC liquidity)
      if(m_handleSMC != INVALID_HANDLE) {
         double smcLiqBuf[1];
         // Buffer 3: Liquidity sweep score
         if(CopyBuffer(m_handleSMC, 3, 0, 1, smcLiqBuf) > 0) {
            if(smcLiqBuf[0] > 0.5) {
               return false; // Potential liquidity grab ahead
            }
         }
      }

      // 6. Clean breakout check
      if(!IsCleanBreakout(direction, fib0Buf[0], fib100Buf[0])) {
         return false;
      }

      // All conditions met
      return true;
   }

   //--- Calculate confluence score
   virtual double GetConfluenceScore(int direction) override {
      double score = 0.0;

      // 1. Clean Breakout = +6.0 pts
      double fib0Buf[1], fib100Buf[1];
      if(CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) > 0 &&
         CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) > 0) {
         if(IsCleanBreakout(direction, fib0Buf[0], fib100Buf[0])) {
            score += 6.0;
         }
      }

      // 2. High Volume = +4.0 pts
      double rvol = GetRVOL();
      score += MathMin(4.0, (rvol - 1.0) * 2.0); // Max 4.0 at RVOL 3.0+

      // 3. Strong Momentum = +3.0 pts
      double momentumScore = GetMomentumScore();
      score += momentumScore * 3.0; // 0-1.0 normalized

      // 4. Volatility Expansion = +3.0 pts
      double volStateBuf[1];
      if(CopyBuffer(m_handleMarketPhase, 2, 0, 1, volStateBuf) > 0) {
         // Buffer 2: Volatility state (0-100%)
         score += (volStateBuf[0] / 100.0) * 3.0;
      }

      // 5. Structure Alignment = +2.0 pts
      if(m_handleSMC != INVALID_HANDLE) {
         double smcStructBuf[1];
         if(CopyBuffer(m_handleSMC, 0, 0, 1, smcStructBuf) > 0) {
            score += MathMin(2.0, smcStructBuf[0] / 2.0); // Max 2.0 pts
         }
      }

      // Max possible score: 18.0 pts
      return score;
   }

   //--- Get Take Profit levels
   virtual void GetTPLevels(double &tp1, double &tp2, double &tp3) override {
      // Target Fibonacci extensions (aggressive)
      double fib0Buf[1], fib100Buf[1], swingDirBuf[1];
      if(CopyBuffer(m_handleFibGolden, 3, 0, 1, fib0Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 9, 0, 1, fib100Buf) <= 0 ||
         CopyBuffer(m_handleFibGolden, 2, 0, 1, swingDirBuf) <= 0) {
         tp1 = 0; tp2 = 0; tp3 = 0;
         return;
      }

      int swingDirection = (int)swingDirBuf[0];
      double swingRange = MathAbs(fib0Buf[0] - fib100Buf[0]);

      if(swingDirection == 1) {
         // Bullish breakout - targets above
         tp1 = fib0Buf[0] + swingRange * 0.618;  // 161.8% extension (R:R ~1:1.5)
         tp2 = fib0Buf[0] + swingRange * 1.000;  // 200% extension (R:R ~1:2.5)
         tp3 = fib0Buf[0] + swingRange * 1.618;  // 261.8% extension (R:R ~1:4)
      } else {
         // Bearish breakout - targets below
         tp1 = fib100Buf[0] - swingRange * 0.618;
         tp2 = fib100Buf[0] - swingRange * 1.000;
         tp3 = fib100Buf[0] - swingRange * 1.618;
      }
   }

   //--- Get Stop Loss level
   virtual double GetStopLoss(int direction) override {
      // Stop loss: Inside the previous range (behind breakout point)
      double fib50Buf[1];
      if(CopyBuffer(m_handleFibGolden, 6, 0, 1, fib50Buf) <= 0) {
         return 0.0;
      }

      double atr = GetATR();
      double buffer = atr * 0.5; // 50% ATR buffer

      if(direction == 1) {
         // Buy: SL at 50% level (middle of range) minus buffer
         return fib50Buf[0] - buffer;
      } else {
         // Sell: SL at 50% level plus buffer
         return fib50Buf[0] + buffer;
      }
   }

private:
   //--- Check for clean breakout
   bool IsCleanBreakout(int direction, double fib0, double fib100) {
      // Get last 3 candles
      double closes[3];
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 3, closes) != 3) {
         return false;
      }

      if(direction == 1) {
         // Bullish breakout: Check if price decisively broke above fib0
         // At least 2 of last 3 closes should be above fib0
         int closesAbove = 0;
         for(int i = 0; i < 3; i++) {
            if(closes[i] > fib0) closesAbove++;
         }
         return (closesAbove >= 2);
      } else {
         // Bearish breakout: Check if price decisively broke below fib100
         int closesBelow = 0;
         for(int i = 0; i < 3; i++) {
            if(closes[i] < fib100) closesBelow++;
         }
         return (closesBelow >= 2);
      }
   }

   //--- Get momentum score (0-1.0 normalized)
   double GetMomentumScore() {
      double range = iHigh(_Symbol, PERIOD_CURRENT, 1) - iLow(_Symbol, PERIOD_CURRENT, 1);
      double body = MathAbs(iClose(_Symbol, PERIOD_CURRENT, 1) - iOpen(_Symbol, PERIOD_CURRENT, 1));

      if(range == 0) return 0.0;

      double bodyRatio = body / range;

      // Normalize to 0-1.0 (0.6 = threshold, 1.0 = perfect)
      if(bodyRatio < 0.6) return 0.0;
      if(bodyRatio >= 1.0) return 1.0;

      return (bodyRatio - 0.6) / 0.4; // Scale 0.6-1.0 to 0-1.0
   }
};
