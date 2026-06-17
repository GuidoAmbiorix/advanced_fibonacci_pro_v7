//+------------------------------------------------------------------+
//|                                           SweepScoreCrypto.mqh   |
//|              APEX Sweep CRYPTO — Sessionless Swing Sweep         |
//|                                                                  |
//|  Strategy: Detect wick traps on dynamic H1 swing highs/lows.    |
//|  No fixed time window — works 24/7 on BTC, ETH, XRP, SOL.       |
//|                                                                  |
//|  Range: highest high / lowest low of the last N H1 bars (def 20)|
//|  Refreshed every new H1 bar.                                     |
//|                                                                  |
//|  6 Pillars (2pts each = 12 max):                                 |
//|  P1 — Swing range is clean consolidation (>= 2x H1 ATR width)   |
//|  P2 — Sweep depth: wick extends >= 0.5x ATR beyond swing level   |
//|  P3 — Reversal candle body pointing back INTO swing range        |
//|  P4 — RSI(8) M5 overextended at sweep, now turning back         |
//|  P5 — Price re-entering swing range (M5 close back inside)      |
//|  P6 — Volume spike on sweep bar > 1.5x 20-bar M5 average        |
//|                                                                  |
//|  Hard gates:                                                     |
//|  G1 — Current M5 bar wicked BEYOND swing level AND closed INSIDE |
//|       (wick trap — the fundamental definition of a sweep)        |
//|  G2 — Reversal candle (bar 1) closed back inside swing range     |
//|  G3 — Spread <= 5% of H1 ATR (auto-calibrates: BTC/ETH/XRP/SOL) |
//|                                                                  |
//|  Min score: 6/12 | TP = swing midpoint | SL = sweep wick + ATR  |
//+------------------------------------------------------------------+
#ifndef SWEEP_SCORE_CRYPTO_MQH
#define SWEEP_SCORE_CRYPTO_MQH

struct SweepSignalCrypto
{
   bool   valid;
   int    direction;    // 1=BUY (swept low → up), -1=SELL (swept high → down)
   int    score;
   double sweepLevel;   // The swing level that was swept
   double tp;           // Swing midpoint — fast target
   double sl;           // Beyond sweep wick + ATR buffer
   string reason;
};

class CSweepScoreCrypto
{
private:
   string   m_symbol;
   int      m_rsiM5;
   int      m_atrM5;
   int      m_atrH1;
   int      m_lookback;      // H1 bars to scan for swing H/L (default 20)
   int      m_minRangeBars;  // Min bars price stayed inside range before sweep

   double   m_swingHigh;
   double   m_swingLow;
   double   m_swingMid;
   datetime m_lastH1Bar;     // Last H1 bar time when range was recalculated

public:
   CSweepScoreCrypto()
   {
      m_symbol       = "";
      m_rsiM5        = INVALID_HANDLE;
      m_atrM5        = INVALID_HANDLE;
      m_atrH1        = INVALID_HANDLE;
      m_lookback     = 20;
      m_minRangeBars = 5;
      m_swingHigh    = 0;
      m_swingLow     = 0;
      m_swingMid     = 0;
      m_lastH1Bar    = 0;
   }

   bool Init(string symbol, int lookback = 20, int minRangeBars = 5)
   {
      m_symbol       = symbol;
      m_lookback     = lookback;
      m_minRangeBars = minRangeBars;
      m_rsiM5        = iRSI(symbol, PERIOD_M5, 8, PRICE_CLOSE);
      m_atrM5        = iATR(symbol, PERIOD_M5, 14);
      m_atrH1        = iATR(symbol, PERIOD_H1, 14);

      bool ok = (m_rsiM5 != INVALID_HANDLE &&
                 m_atrM5 != INVALID_HANDLE &&
                 m_atrH1 != INVALID_HANDLE);
      if(ok)  Print("[APEX SWEEP CRYPTO] Initialized on ", symbol,
                    " | Lookback=", lookback, " H1 bars");
      else    Print("[APEX SWEEP CRYPTO] ERROR: failed to create handles on ", symbol);
      return ok;
   }

   void Deinit()
   {
      if(m_rsiM5 != INVALID_HANDLE) { IndicatorRelease(m_rsiM5); m_rsiM5 = INVALID_HANDLE; }
      if(m_atrM5 != INVALID_HANDLE) { IndicatorRelease(m_atrM5); m_atrM5 = INVALID_HANDLE; }
      if(m_atrH1 != INVALID_HANDLE) { IndicatorRelease(m_atrH1); m_atrH1 = INVALID_HANDLE; }
   }

   // Call on every tick — refreshes swing range on each new H1 bar
   void Update()
   {
      datetime curH1 = iTime(m_symbol, PERIOD_H1, 0);
      if(curH1 != m_lastH1Bar)
      {
         CalcSwingRange();
         m_lastH1Bar = curH1;
      }
   }

   SweepSignalCrypto Calculate()
   {
      SweepSignalCrypto sell = Evaluate(-1);
      SweepSignalCrypto buy  = Evaluate( 1);
      if(!sell.valid && !buy.valid)
      {
         SweepSignalCrypto e;
         e.valid = false; e.score = 0; e.direction = 0;
         e.reason = "NO_SIGNAL"; e.sweepLevel = 0; e.tp = 0; e.sl = 0;
         return e;
      }
      if(sell.valid && !buy.valid) return sell;
      if(buy.valid  && !sell.valid) return buy;
      return (sell.score >= buy.score) ? sell : buy;
   }

   SweepSignalCrypto Evaluate(int dir)
   {
      SweepSignalCrypto sig;
      sig.valid      = false;
      sig.direction  = dir;
      sig.score      = 0;
      sig.reason     = "";
      sig.sweepLevel = (dir == 1) ? m_swingLow : m_swingHigh;
      sig.tp         = m_swingMid;
      sig.sl         = 0;

      if(m_atrM5 == INVALID_HANDLE || m_atrH1 == INVALID_HANDLE) return sig;
      if(m_swingHigh <= 0 || m_swingLow <= 0) return sig;

      // GATE 1 HARD — current M5 bar must have WICKED beyond swing level
      //               AND CLOSED back inside (wick trap = true sweep)
      if(!GateWickTrap(dir))
      {
         sig.valid  = false;
         sig.score  = 0;
         sig.reason = "[G1:NO_WICK_TRAP] ";
         return sig;
      }

      // P1 — Swing range width is a clean consolidation (2pts)
      int p1 = ScoreSwingRange();
      sig.score += p1;
      if(p1 > 0) sig.reason += "RANGE(" + IntegerToString(p1) + ") ";

      // P2 — Sweep depth: wick extends meaningfully beyond swing level (2pts)
      int p2 = ScoreSweepDepth(dir);
      sig.score += p2;
      if(p2 > 0) sig.reason += "DEPTH(" + IntegerToString(p2) + ") ";

      // P3 — Reversal candle body pointing back into range (2pts)
      int p3 = ScoreReversalCandle(dir);
      sig.score += p3;
      if(p3 > 0) sig.reason += "REV(" + IntegerToString(p3) + ") ";

      // P4 — RSI(8) M5 overextended + turning back (2pts)
      int p4 = ScoreRSI(dir);
      sig.score += p4;
      if(p4 > 0) sig.reason += "RSI(" + IntegerToString(p4) + ") ";

      // P5 — Price re-entering swing range (2pts)
      int p5 = ScoreReEntry(dir);
      sig.score += p5;
      if(p5 > 0) sig.reason += "REENTRY(" + IntegerToString(p5) + ") ";

      // P6 — Volume spike on sweep bar (2pts)
      int p6 = ScoreVolume();
      sig.score += p6;
      if(p6 > 0) sig.reason += "VOL(" + IntegerToString(p6) + ") ";

      sig.valid = (sig.score >= 6);

      // GATE 2 — Reversal candle (bar 1) must have CLOSED back inside swing range
      if(sig.valid && !GateReversalInsideRange(dir))
      {
         sig.valid  = false;
         sig.reason += "[G2:CANDLE_OUTSIDE] ";
      }

      // GATE 3 — Spread <= 5% of H1 ATR (auto-calibrates for crypto)
      if(sig.valid && !GateSpreadOK())
      {
         sig.valid  = false;
         sig.reason += "[G3:SPREAD_WIDE] ";
      }

      // SL: beyond sweep wick extreme + 0.5x M5 ATR buffer
      double atrM5 = GetATR_M5();
      if(dir == 1)
      {
         double lows[];
         ArraySetAsSeries(lows, true);
         double wickLow = m_swingLow;
         if(CopyLow(m_symbol, PERIOD_M5, 0, 5, lows) >= 5)
            for(int i = 1; i <= 4; i++) wickLow = MathMin(wickLow, lows[i]);
         sig.sl = wickLow - atrM5 * 0.5;
      }
      else
      {
         double highs[];
         ArraySetAsSeries(highs, true);
         double wickHigh = m_swingHigh;
         if(CopyHigh(m_symbol, PERIOD_M5, 0, 5, highs) >= 5)
            for(int i = 1; i <= 4; i++) wickHigh = MathMax(wickHigh, highs[i]);
         sig.sl = wickHigh + atrM5 * 0.5;
      }

      return sig;
   }

   double GetSwingHigh() { return m_swingHigh; }
   double GetSwingLow()  { return m_swingLow;  }
   double GetSwingMid()  { return m_swingMid;  }

private:

   //+----------------------------------------------------------------+
   // GATE 1 — Wick trap: M5 bar wicked BEYOND swing level but        |
   //          CLOSED back INSIDE the swing range.                    |
   //          This is the literal definition of a sweep/stop-hunt.   |
   //+----------------------------------------------------------------+
   bool GateWickTrap(int dir)
   {
      double opens[], closes[], highs[], lows[];
      ArraySetAsSeries(opens,  true);
      ArraySetAsSeries(closes, true);
      ArraySetAsSeries(highs,  true);
      ArraySetAsSeries(lows,   true);
      if(CopyOpen (m_symbol, PERIOD_M5, 0, 4, opens)  < 4) return false;
      if(CopyClose(m_symbol, PERIOD_M5, 0, 4, closes) < 4) return false;
      if(CopyHigh (m_symbol, PERIOD_M5, 0, 4, highs)  < 4) return false;
      if(CopyLow  (m_symbol, PERIOD_M5, 0, 4, lows)   < 4) return false;

      if(dir == 1)  // BUY: wick below swingLow, close above swingLow
      {
         // Check bars 1 or 2 (sweep could be 1-2 bars ago)
         bool bar1 = (lows[1]  < m_swingLow && closes[1] > m_swingLow);
         bool bar2 = (lows[2]  < m_swingLow && closes[2] > m_swingLow);
         return (bar1 || bar2);
      }
      else  // SELL: wick above swingHigh, close below swingHigh
      {
         bool bar1 = (highs[1] > m_swingHigh && closes[1] < m_swingHigh);
         bool bar2 = (highs[2] > m_swingHigh && closes[2] < m_swingHigh);
         return (bar1 || bar2);
      }
   }

   //+----------------------------------------------------------------+
   // P1 — Swing range width >= 2x H1 ATR = clean consolidation      |
   //      Narrow ranges produce fake sweeps — require real width.    |
   //+----------------------------------------------------------------+
   int ScoreSwingRange()
   {
      if(m_swingHigh <= m_swingLow) return 0;
      double atrH1 = GetATR_H1();
      if(atrH1 <= 0) return 0;
      double ratio = (m_swingHigh - m_swingLow) / atrH1;
      if(ratio >= 3.0) return 2;   // wide clean range → premium
      if(ratio >= 2.0) return 1;   // minimum acceptable range
      return 0;
   }

   //+----------------------------------------------------------------+
   // P2 — Sweep depth: wick extends >= 0.5x M5 ATR beyond swing      |
   //      A tiny needle poke is noise — require meaningful extension. |
   //+----------------------------------------------------------------+
   int ScoreSweepDepth(int dir)
   {
      double atrM5 = GetATR_M5();
      if(atrM5 <= 0) return 0;

      double lows[], highs[];
      ArraySetAsSeries(lows,  true);
      ArraySetAsSeries(highs, true);

      if(dir == 1)
      {
         if(CopyLow(m_symbol, PERIOD_M5, 0, 4, lows) < 4) return 0;
         double wickLow = MathMin(lows[1], lows[2]);
         double depth   = m_swingLow - wickLow;          // how far below swingLow
         if(depth >= atrM5 * 1.0) return 2;              // deep sweep — strong
         if(depth >= atrM5 * 0.5) return 1;              // moderate sweep
      }
      else
      {
         if(CopyHigh(m_symbol, PERIOD_M5, 0, 4, highs) < 4) return 0;
         double wickHigh = MathMax(highs[1], highs[2]);
         double depth    = wickHigh - m_swingHigh;
         if(depth >= atrM5 * 1.0) return 2;
         if(depth >= atrM5 * 0.5) return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P3 — Reversal candle (bar 1): body pointing back into range     |
   //+----------------------------------------------------------------+
   int ScoreReversalCandle(int dir)
   {
      double opens[], closes[], highs[], lows[];
      ArraySetAsSeries(opens,  true);
      ArraySetAsSeries(closes, true);
      ArraySetAsSeries(highs,  true);
      ArraySetAsSeries(lows,   true);
      if(CopyOpen (m_symbol, PERIOD_M5, 0, 3, opens)  < 3) return 0;
      if(CopyClose(m_symbol, PERIOD_M5, 0, 3, closes) < 3) return 0;
      if(CopyHigh (m_symbol, PERIOD_M5, 0, 3, highs)  < 3) return 0;
      if(CopyLow  (m_symbol, PERIOD_M5, 0, 3, lows)   < 3) return 0;

      double body   = MathAbs(closes[1] - opens[1]);
      double candle = highs[1] - lows[1];
      if(candle <= 0) return 0;
      double bodyRatio = body / candle;

      if(dir == 1)
      {
         bool bullish       = (closes[1] > opens[1]);
         bool longLowerWick = (opens[1] - lows[1] > body * 1.5);
         if(bullish && bodyRatio >= 0.5) return 2;
         if(bullish || longLowerWick)    return 1;
      }
      else
      {
         bool bearish       = (closes[1] < opens[1]);
         bool longUpperWick = (highs[1] - opens[1] > body * 1.5);
         if(bearish && bodyRatio >= 0.5) return 2;
         if(bearish || longUpperWick)    return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P4 — RSI(8) M5 overextended at sweep, now recovering (2pts)     |
   //+----------------------------------------------------------------+
   int ScoreRSI(int dir)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(m_rsiM5 == INVALID_HANDLE) return 0;
      if(CopyBuffer(m_rsiM5, 0, 0, 4, rsi) < 4) return 0;

      if(dir == 1)
      {
         bool wasExtreme    = (rsi[2] < 30.0 || rsi[3] < 30.0);
         bool recovering    = (rsi[1] > rsi[2]);
         bool strongRecover = (rsi[1] > 35.0 && rsi[2] < 30.0);
         if(strongRecover)            return 2;
         if(wasExtreme && recovering) return 1;
      }
      else
      {
         bool wasExtreme  = (rsi[2] > 70.0 || rsi[3] > 70.0);
         bool falling     = (rsi[1] < rsi[2]);
         bool strongFall  = (rsi[1] < 65.0 && rsi[2] > 70.0);
         if(strongFall)            return 2;
         if(wasExtreme && falling) return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P5 — Price re-entering swing range (M5 close back inside) (2pts)|
   //+----------------------------------------------------------------+
   int ScoreReEntry(int dir)
   {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, PERIOD_M5, 0, 3, closes) < 3) return 0;

      if(dir == 1)
      {
         bool bar0In = (closes[0] > m_swingLow);
         bool bar1In = (closes[1] > m_swingLow);
         if(bar0In && bar1In) return 2;
         if(bar0In)           return 1;
      }
      else
      {
         bool bar0In = (closes[0] < m_swingHigh);
         bool bar1In = (closes[1] < m_swingHigh);
         if(bar0In && bar1In) return 2;
         if(bar0In)           return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P6 — Volume spike: sweep bar (bar 1 or 2) > 1.5x average (2pts) |
   //+----------------------------------------------------------------+
   int ScoreVolume()
   {
      long vol[];
      ArraySetAsSeries(vol, true);
      if(CopyTickVolume(m_symbol, PERIOD_M5, 0, 23, vol) < 23) return 0;
      double avg = 0;
      for(int i = 3; i <= 22; i++) avg += (double)vol[i];
      avg /= 20.0;
      if(avg <= 0) return 0;
      double r1   = (double)vol[1] / avg;
      double r2   = (double)vol[2] / avg;
      double best = MathMax(r1, r2);
      if(best >= 2.5) return 2;
      if(best >= 1.5) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // Gate 2 — Bar 1 closed INSIDE swing range                        |
   //+----------------------------------------------------------------+
   bool GateReversalInsideRange(int dir)
   {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, PERIOD_M5, 0, 3, closes) < 3) return false;
      if(dir == 1) return (closes[1] > m_swingLow);
      else         return (closes[1] < m_swingHigh);
   }

   //+----------------------------------------------------------------+
   // Gate 3 — Spread <= 5% of H1 ATR                                 |
   //   Auto-calibrates: BTC spread $20 vs ATR $500 = 4% → OK         |
   //                    ETH spread $5  vs ATR $80  = 6% → reject     |
   //   Works for all crypto pairs without hardcoded point values.     |
   //+----------------------------------------------------------------+
   bool GateSpreadOK()
   {
      double atrH1 = GetATR_H1();
      if(atrH1 <= 0) return true;  // can't check, don't block
      double spreadPrice = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD)
                           * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (spreadPrice / atrH1 <= 0.05);
   }

   //+----------------------------------------------------------------+
   // Build swing range: H/L of last m_lookback H1 bars (skip bar 0). |
   // Skipping bar 0 avoids a forming bar distorting the range.        |
   //+----------------------------------------------------------------+
   void CalcSwingRange()
   {
      double high = 0;
      double low  = DBL_MAX;
      bool   found = false;

      for(int i = 1; i <= m_lookback; i++)
      {
         double h = iHigh(m_symbol, PERIOD_H1, i);
         double l = iLow (m_symbol, PERIOD_H1, i);
         if(h <= 0 || l <= 0) continue;
         if(h > high) high = h;
         if(l < low)  low  = l;
         found = true;
      }

      if(found && high > low)
      {
         m_swingHigh = high;
         m_swingLow  = low;
         m_swingMid  = (high + low) * 0.5;
         PrintFormat("[APEX SWEEP CRYPTO] Swing range (%d H1 bars): H=%.5f L=%.5f Mid=%.5f",
                     m_lookback, high, low, m_swingMid);
      }
   }

   double GetATR_M5()
   {
      double atr[1];
      if(m_atrM5 != INVALID_HANDLE && CopyBuffer(m_atrM5, 0, 0, 1, atr) == 1) return atr[0];
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 50;
   }

   double GetATR_H1()
   {
      double atr[1];
      if(m_atrH1 != INVALID_HANDLE && CopyBuffer(m_atrH1, 0, 0, 1, atr) == 1) return atr[0];
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 200;
   }
};

#endif
