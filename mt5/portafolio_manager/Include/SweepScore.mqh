//+------------------------------------------------------------------+
//|                                                   SweepScore.mqh |
//|                    APEX Sweep — Asian Liquidity Sweep Reversal   |
//|                                                                  |
//|  Strategy: Catch false London breakouts of Asian consolidation.  |
//|  Entry: M5 | Window: 07:00-09:30 UTC (London open sweep only)   |
//|                                                                  |
//|  6 Pillars (2pts each = 12 max):                                 |
//|  P1 — Asia range defined and clean (>= 1.5x ATR M5, 3+ bars)   |
//|  P2 — London sweep: M5 closed OUTSIDE Asia range + in window    |
//|  P3 — Reversal candle: body pointing back INTO the range        |
//|  P4 — RSI(8) M5 overextended at sweep, now turning back        |
//|  P5 — Price re-entering Asia range (M5 close back inside)      |
//|  P6 — Volume spike on sweep bar > 1.5x 20-bar average          |
//|                                                                  |
//|  Min score: 6/12 | TP = Asia midpoint | SL = sweep extreme+ATR |
//+------------------------------------------------------------------+
#ifndef SWEEP_SCORE_MQH
#define SWEEP_SCORE_MQH

struct SweepSignal
{
   bool   valid;
   int    direction;   // 1=BUY (swept low → up), -1=SELL (swept high → down)
   int    score;
   double sweepLevel;  // The Asia range level that was swept
   double tp;          // Asia midpoint — fast target
   double sl;          // Beyond sweep extreme + 0.5 ATR buffer
   string reason;
};

class CSweepScore
{
private:
   string   m_symbol;
   int      m_rsiM5;
   int      m_atrM5;
   int      m_brokerOffset;

   double   m_asiaHigh;
   double   m_asiaLow;
   double   m_asiaMid;
   datetime m_asiaDate;

public:
   CSweepScore()
   {
      m_symbol       = "";
      m_rsiM5        = INVALID_HANDLE;
      m_atrM5        = INVALID_HANDLE;
      m_brokerOffset = 3;
      m_asiaHigh     = 0;
      m_asiaLow      = 0;
      m_asiaMid      = 0;
      m_asiaDate     = 0;
   }

   bool Init(string symbol, int brokerUTCOffset = 3)
   {
      m_symbol       = symbol;
      m_brokerOffset = brokerUTCOffset;
      m_rsiM5        = iRSI(symbol, PERIOD_M5, 8, PRICE_CLOSE);
      m_atrM5        = iATR(symbol, PERIOD_M5, 14);

      bool ok = (m_rsiM5 != INVALID_HANDLE && m_atrM5 != INVALID_HANDLE);
      if(ok)  Print("[APEX SWEEP] SweepScore initialized on ", symbol, " UTC+", brokerUTCOffset);
      else    Print("[APEX SWEEP] ERROR: failed to create handles on ", symbol);
      return ok;
   }

   void Deinit()
   {
      if(m_rsiM5 != INVALID_HANDLE) { IndicatorRelease(m_rsiM5); m_rsiM5 = INVALID_HANDLE; }
      if(m_atrM5 != INVALID_HANDLE) { IndicatorRelease(m_atrM5); m_atrM5 = INVALID_HANDLE; }
   }

   void Update()
   {
      datetime today = iTime(m_symbol, PERIOD_D1, 0);
      if(today != m_asiaDate)
      {
         CalcAsiaRange();
         m_asiaDate = today;
      }
   }

   SweepSignal Calculate()
   {
      SweepSignal sell = Evaluate(-1);
      SweepSignal buy  = Evaluate( 1);
      if(!sell.valid && !buy.valid)
      {
         SweepSignal e; e.valid=false; e.score=0; e.direction=0; e.reason="NO_SIGNAL";
         e.sweepLevel=0; e.tp=0; e.sl=0;
         return e;
      }
      if(sell.valid && !buy.valid) return sell;
      if(buy.valid  && !sell.valid) return buy;
      return (sell.score >= buy.score) ? sell : buy;
   }

   SweepSignal Evaluate(int dir)
   {
      SweepSignal sig;
      sig.valid      = false;
      sig.direction  = dir;
      sig.score      = 0;
      sig.reason     = "";
      sig.sweepLevel = (dir == 1) ? m_asiaLow : m_asiaHigh;
      sig.tp         = m_asiaMid;
      sig.sl         = 0;

      if(m_atrM5 == INVALID_HANDLE) return sig;
      if(m_asiaHigh <= 0 || m_asiaLow <= 0) return sig;

      // GATE 1 HARD — must be inside sweep window before scoring anything
      if(!IsInSweepWindow())
      {
         sig.valid  = false;
         sig.score  = 0;
         sig.reason = "[G1:OUTSIDE_WINDOW] ";
         return sig;
      }

      // P1 — Asia range valid (2pts)
      int p1 = ScoreAsiaRange();
      sig.score += p1;
      if(p1 > 0) sig.reason += "ASIA(" + IntegerToString(p1) + ") ";

      // P2 — Sweep confirmed in window (2pts)
      int p2 = ScoreSweepConfirmed(dir);
      sig.score += p2;
      if(p2 > 0) sig.reason += "SWEEP(" + IntegerToString(p2) + ") ";

      // P3 — Reversal candle back toward range (2pts)
      int p3 = ScoreReversalCandle(dir);
      sig.score += p3;
      if(p3 > 0) sig.reason += "REV(" + IntegerToString(p3) + ") ";

      // P4 — RSI(8) overextended + turning (2pts)
      int p4 = ScoreRSI(dir);
      sig.score += p4;
      if(p4 > 0) sig.reason += "RSI(" + IntegerToString(p4) + ") ";

      // P5 — Price re-entering range (2pts)
      int p5 = ScoreReEntry(dir);
      sig.score += p5;
      if(p5 > 0) sig.reason += "REENTRY(" + IntegerToString(p5) + ") ";

      // P6 — Volume spike on sweep bar (2pts)
      int p6 = ScoreVolume();
      sig.score += p6;
      if(p6 > 0) sig.reason += "VOL(" + IntegerToString(p6) + ") ";

      sig.valid = (sig.score >= 6);

      // ── 90% WIN RATE GATES — hard blocks even if score passes ────────
      // Gate 1: window already enforced in ScoreSweepConfirmed (07:00-07:45 UTC)
      // Gate 2: reversal candle must close back INSIDE the Asia range
      if(sig.valid && !GateReversalInsideRange(dir))
      {
         sig.valid  = false;
         sig.reason += "[G2:CANDLE_OUTSIDE] ";
      }
      // Gate 3: spread must be <= 3 pips at entry moment
      if(sig.valid && !GateSpreadOK())
      {
         sig.valid  = false;
         sig.reason += "[G3:SPREAD_WIDE] ";
      }
      // ── END GATES ─────────────────────────────────────────────────────

      // SL: beyond sweep extreme + 0.5 ATR
      double atr = GetATR_M5();
      if(dir == 1)
      {
         double lows[];
         ArraySetAsSeries(lows, true);
         double sweepLow = m_asiaLow;
         if(CopyLow(m_symbol, PERIOD_M5, 0, 5, lows) >= 5)
            for(int i=1; i<=4; i++) sweepLow = MathMin(sweepLow, lows[i]);
         sig.sl = sweepLow - atr * 0.5;
      }
      else
      {
         double highs[];
         ArraySetAsSeries(highs, true);
         double sweepHigh = m_asiaHigh;
         if(CopyHigh(m_symbol, PERIOD_M5, 0, 5, highs) >= 5)
            for(int i=1; i<=4; i++) sweepHigh = MathMax(sweepHigh, highs[i]);
         sig.sl = sweepHigh + atr * 0.5;
      }

      return sig;
   }

   // Expose Asia range for display/TP calculation
   double GetAsiaHigh() { return m_asiaHigh; }
   double GetAsiaLow()  { return m_asiaLow;  }
   double GetAsiaMid()  { return m_asiaMid;  }
   bool   IsInWindow()  { return IsInSweepWindow(); }

private:

   //+----------------------------------------------------------------+
   // P1 — Asia range >= 1.5x ATR M5 (2pts)
   //+----------------------------------------------------------------+
   int ScoreAsiaRange()
   {
      if(m_asiaHigh <= m_asiaLow) return 0;
      double atr = GetATR_M5();
      if(atr <= 0) return 0;
      double ratio = (m_asiaHigh - m_asiaLow) / atr;
      if(ratio >= 4.0) return 2;
      if(ratio >= 1.5) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P2 — In 07:00-09:30 UTC window + M5 closed outside range (2pts)
   //+----------------------------------------------------------------+
   int ScoreSweepConfirmed(int dir)
   {
      if(!IsInSweepWindow()) return 0;

      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, PERIOD_M5, 0, 4, closes) < 4) return 0;

      if(dir == 1)  // BUY: swept below Asia low
      {
         bool bar1 = (closes[1] < m_asiaLow);
         bool bar2 = (closes[2] < m_asiaLow);
         if(bar1 && bar2) return 2;
         if(bar1)         return 1;
      }
      else  // SELL: swept above Asia high
      {
         bool bar1 = (closes[1] > m_asiaHigh);
         bool bar2 = (closes[2] > m_asiaHigh);
         if(bar1 && bar2) return 2;
         if(bar1)         return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P3 — Reversal candle: body pointing back into Asia range (2pts)
   //   Bar 1 = the reversal candle (last completed M5 bar)
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

      if(dir == 1)  // BUY: bullish bar or long lower wick
      {
         bool bullish       = (closes[1] > opens[1]);
         bool longLowerWick = (opens[1] - lows[1] > body * 1.5);
         if(bullish && bodyRatio >= 0.5) return 2;
         if(bullish || longLowerWick)    return 1;
      }
      else  // SELL: bearish bar or long upper wick
      {
         bool bearish       = (closes[1] < opens[1]);
         bool longUpperWick = (highs[1] - opens[1] > body * 1.5);
         if(bearish && bodyRatio >= 0.5) return 2;
         if(bearish || longUpperWick)    return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P4 — RSI(8) M5: extreme on sweep bar, recovering now (2pts)
   //+----------------------------------------------------------------+
   int ScoreRSI(int dir)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(m_rsiM5 == INVALID_HANDLE) return 0;
      if(CopyBuffer(m_rsiM5, 0, 0, 4, rsi) < 4) return 0;

      if(dir == 1)  // BUY: was oversold, now recovering
      {
         bool wasExtreme   = (rsi[2] < 30.0 || rsi[3] < 30.0);
         bool recovering   = (rsi[1] > rsi[2]);
         bool strongRecover= (rsi[1] > 35.0 && rsi[2] < 30.0);
         if(strongRecover)            return 2;
         if(wasExtreme && recovering) return 1;
      }
      else  // SELL: was overbought, now falling
      {
         bool wasExtreme   = (rsi[2] > 70.0 || rsi[3] > 70.0);
         bool falling      = (rsi[1] < rsi[2]);
         bool strongFall   = (rsi[1] < 65.0 && rsi[2] > 70.0);
         if(strongFall)             return 2;
         if(wasExtreme && falling)  return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P5 — Price re-entering Asia range (M5 close back inside) (2pts)
   //+----------------------------------------------------------------+
   int ScoreReEntry(int dir)
   {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, PERIOD_M5, 0, 3, closes) < 3) return 0;

      if(dir == 1)  // BUY: bar 0/1 now above Asia low
      {
         bool bar0In = (closes[0] > m_asiaLow);
         bool bar1In = (closes[1] > m_asiaLow);
         if(bar0In && bar1In) return 2;
         if(bar0In)           return 1;
      }
      else  // SELL: bar 0/1 now below Asia high
      {
         bool bar0In = (closes[0] < m_asiaHigh);
         bool bar1In = (closes[1] < m_asiaHigh);
         if(bar0In && bar1In) return 2;
         if(bar0In)           return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P6 — Volume spike on sweep bar (bar 1 or 2) > 1.5x average (2pts)
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
      // Check bars 1 and 2 (sweep + confirmation)
      double r1 = (double)vol[1] / avg;
      double r2 = (double)vol[2] / avg;
      double best = MathMax(r1, r2);
      if(best >= 2.5) return 2;
      if(best >= 1.5) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // Window check: 07:00 to 09:30 UTC
   //+----------------------------------------------------------------+
   bool IsInSweepWindow()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      // Convert broker time to UTC
      int utcMinutes = dt.hour * 60 + dt.min - m_brokerOffset * 60;
      if(utcMinutes < 0) utcMinutes += 24 * 60;
      // Gate 1: ultra-precise window 07:00-07:45 UTC — strongest sweeps only
      return (utcMinutes >= 7*60 && utcMinutes <= 7*60+45);
   }

   //+----------------------------------------------------------------+
   // Gate 2 — Reversal candle (bar 1) closed INSIDE the Asia range
   //   BUY:  close > asiaLow  (not just a wick — real close back in)
   //   SELL: close < asiaHigh
   //+----------------------------------------------------------------+
   bool GateReversalInsideRange(int dir)
   {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, PERIOD_M5, 0, 3, closes) < 3) return false;
      if(dir == 1) return (closes[1] > m_asiaLow);
      else         return (closes[1] < m_asiaHigh);
   }

   //+----------------------------------------------------------------+
   // Gate 3 — Spread <= 3 pips at moment of entry
   //   For gold (5-digit broker): 30 points = 3.0 pips
   //+----------------------------------------------------------------+
   bool GateSpreadOK()
   {
      long spreadPts = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      // Gold: 1 pip = 10 points (5-digit). 3 pips = 30 points.
      return (spreadPts <= 30);
   }

   //+----------------------------------------------------------------+
   // Build Asia range: H1 bars from 00:00 to 07:00 UTC
   //+----------------------------------------------------------------+
   void CalcAsiaRange()
   {
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      // Asia start in broker time = 00:00 UTC = m_brokerOffset:00 broker
      dt.hour = m_brokerOffset; dt.min = 0; dt.sec = 0;
      datetime asiaStart = StructToTime(dt);
      // If current broker time is before asiaStart (early morning), go back one day
      if(TimeCurrent() < asiaStart) asiaStart -= 86400;
      datetime asiaEnd = asiaStart + 7 * 3600;

      double high = 0, low = DBL_MAX;
      bool found = false;
      for(int i = 0; i < 120; i++)
      {
         datetime t = iTime(m_symbol, PERIOD_H1, i);
         if(t <= 0) break;
         if(t < asiaStart) break;
         if(t >= asiaEnd)  continue;
         double h = iHigh(m_symbol, PERIOD_H1, i);
         double l = iLow (m_symbol, PERIOD_H1, i);
         if(h > high) high = h;
         if(l < low)  low  = l;
         found = true;
      }
      if(found && high > low)
      {
         m_asiaHigh = high;
         m_asiaLow  = low;
         m_asiaMid  = (high + low) * 0.5;
         Print("[APEX SWEEP] Asia range: H=", DoubleToString(high,2),
               " L=", DoubleToString(low,2),
               " Mid=", DoubleToString(m_asiaMid,2));
      }
   }

   double GetATR_M5()
   {
      double atr[1];
      if(m_atrM5 != INVALID_HANDLE && CopyBuffer(m_atrM5, 0, 0, 1, atr) == 1) return atr[0];
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 50;
   }
};

#endif
