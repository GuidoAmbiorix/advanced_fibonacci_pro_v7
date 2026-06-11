//+------------------------------------------------------------------+
//|                                                BreakoutScore.mqh |
//|                          APEX Breakout — Asia Range / Level Break |
//|                                                                  |
//|  Strategy: Catch institutional breakouts from consolidation.    |
//|  Entry: M30/H1  |  Context: H4                                  |
//|                                                                  |
//|  6 Pillars (2pts each = 12 max):                                 |
//|  P1 — Asia range defined (00:00-07:00 UTC, min ATR*1.5 range)   |
//|  P2 — Price broke + CLOSED outside Asia range on M30            |
//|  P3 — ATR expansion post-breakout: > 1.5x ATR average           |
//|  P4 — BB squeeze pre-breakout: H1 BB width < 1.0 ATR (3+ bars) |
//|  P5 — Volume spike on breakout bar: > 1.8x 20-bar average       |
//|  P6 — H4 structure supports direction (no counter-HTF break)    |
//|                                                                  |
//|  Min score: 6/12                                                 |
//+------------------------------------------------------------------+
#ifndef BREAKOUT_SCORE_MQH
#define BREAKOUT_SCORE_MQH

struct BreakoutSignal
{
   bool   valid;
   int    direction;
   int    score;
   double breakLevel;  // Asia High or Asia Low that was broken
   double tp1;         // 1x ATR target (fast capture)
   double tp2;         // 2x ATR target (runner)
   string reason;
};

class CBreakoutScore
{
private:
   string   m_symbol;
   int      m_atrH1;
   int      m_bbH1;    // Bollinger Bands H1 for squeeze detection
   int      m_emaH4;   // EMA 200 H4 for context

   // Cached Asia range (updated once per day)
   double   m_asiaHigh;
   double   m_asiaLow;
   datetime m_asiaDate;

public:
   CBreakoutScore()
   {
      m_symbol   = "";
      m_atrH1    = INVALID_HANDLE;
      m_bbH1     = INVALID_HANDLE;
      m_emaH4    = INVALID_HANDLE;
      m_asiaHigh = 0;
      m_asiaLow  = 0;
      m_asiaDate = 0;
   }

   bool Init(string symbol)
   {
      m_symbol = symbol;
      m_atrH1  = iATR  (symbol, PERIOD_H1, 14);
      m_bbH1   = iBands(symbol, PERIOD_H1, 20, 0, 2.0, PRICE_CLOSE);
      m_emaH4  = iMA   (symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);

      bool ok = (m_atrH1 != INVALID_HANDLE && m_bbH1 != INVALID_HANDLE &&
                 m_emaH4 != INVALID_HANDLE);
      if(ok) Print("[APEX BREAKOUT] BreakoutScore initialized on ", symbol);
      else   Print("[APEX BREAKOUT] ERROR: failed to create handles on ", symbol);
      return ok;
   }

   void Deinit()
   {
      if(m_atrH1 != INVALID_HANDLE) { IndicatorRelease(m_atrH1); m_atrH1 = INVALID_HANDLE; }
      if(m_bbH1  != INVALID_HANDLE) { IndicatorRelease(m_bbH1);  m_bbH1  = INVALID_HANDLE; }
      if(m_emaH4 != INVALID_HANDLE) { IndicatorRelease(m_emaH4); m_emaH4 = INVALID_HANDLE; }
   }

   void Update()
   {
      // Refresh Asia range once per day
      datetime today = iTime(m_symbol, PERIOD_D1, 0);
      if(today != m_asiaDate)
      {
         CalcAsiaRange();
         m_asiaDate = today;
      }
   }

   BreakoutSignal Calculate()
   {
      BreakoutSignal sell = Evaluate(-1);
      BreakoutSignal buy  = Evaluate( 1);
      if(!sell.valid && !buy.valid) { BreakoutSignal e; e.valid=false; e.score=0; e.direction=0; e.reason="NO_SIGNAL"; return e; }
      if(sell.valid && !buy.valid)  return sell;
      if(buy.valid  && !sell.valid) return buy;
      return (sell.score >= buy.score) ? sell : buy;
   }

   BreakoutSignal Evaluate(int dir)
   {
      BreakoutSignal sig;
      sig.valid      = false;
      sig.direction  = dir;
      sig.score      = 0;
      sig.reason     = "";
      sig.breakLevel = (dir == 1) ? m_asiaHigh : m_asiaLow;

      if(m_atrH1 == INVALID_HANDLE) return sig;

      // P1 — Asia range defined and valid (2pts)
      int p1 = ScoreAsiaRange();
      sig.score += p1;
      if(p1 > 0) sig.reason += "ASIA_RANGE(" + IntegerToString(p1) + ") ";

      // P2 — Closed outside Asia range (2pts)
      int p2 = ScoreBreakClose(dir);
      sig.score += p2;
      if(p2 > 0) sig.reason += "BREAK_CLOSE(" + IntegerToString(p2) + ") ";

      // P3 — ATR expansion (2pts)
      int p3 = ScoreATRExpansion();
      sig.score += p3;
      if(p3 > 0) sig.reason += "ATR_EXP(" + IntegerToString(p3) + ") ";

      // P4 — BB squeeze before breakout (2pts)
      int p4 = ScoreBBSqueeze();
      sig.score += p4;
      if(p4 > 0) sig.reason += "BB_SQ(" + IntegerToString(p4) + ") ";

      // P5 — Volume spike on breakout (2pts)
      int p5 = ScoreVolume();
      sig.score += p5;
      if(p5 > 0) sig.reason += "VOL(" + IntegerToString(p5) + ") ";

      // P6 — H4 structure context supports direction (2pts)
      int p6 = ScoreH4Context(dir);
      sig.score += p6;
      if(p6 > 0) sig.reason += "H4_CTX(" + IntegerToString(p6) + ") ";

      sig.valid = (sig.score >= 6);

      double atr = GetATR_H1();
      double price = SymbolInfoDouble(m_symbol, dir == 1 ? SYMBOL_ASK : SYMBOL_BID);
      sig.tp1 = (dir == 1) ? price + atr * 2.0 : price - atr * 2.0;
      sig.tp2 = (dir == 1) ? price + atr * 4.0 : price - atr * 4.0;

      return sig;
   }

private:

   //+----------------------------------------------------------------+
   // P1 — Asia range exists and is at least 1.5x ATR in size (2pts)
   //+----------------------------------------------------------------+
   int ScoreAsiaRange()
   {
      if(m_asiaHigh <= 0 || m_asiaLow <= 0 || m_asiaHigh <= m_asiaLow) return 0;
      double rangeSize = m_asiaHigh - m_asiaLow;
      double atr = GetATR_H1();
      if(atr <= 0) return 0;
      double ratio = rangeSize / atr;
      if(ratio >= 2.0) return 2;
      if(ratio >= 1.5) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P2 — M30 closed outside Asia range (not just wick) (2pts)
   //   Also checks bar 1 (just completed) for a confirmed close
   //+----------------------------------------------------------------+
   int ScoreBreakClose(int dir)
   {
      if(m_asiaHigh <= 0) return 0;

      double closes[3];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, PERIOD_M30, 0, 3, closes) < 3) return 0;

      if(dir == 1)  // BUY: close above Asia High
      {
         if(closes[1] > m_asiaHigh && closes[0] > m_asiaHigh) return 2; // 2 bars above
         if(closes[1] > m_asiaHigh)                           return 1; // 1 bar above
      }
      else  // SELL: close below Asia Low
      {
         if(closes[1] < m_asiaLow && closes[0] < m_asiaLow) return 2;
         if(closes[1] < m_asiaLow)                          return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P3 — ATR expansion: H1 current > 1.5x average (breakout energy)
   //+----------------------------------------------------------------+
   int ScoreATRExpansion()
   {
      double atr[21];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_atrH1, 0, 0, 21, atr) < 21) return 0;
      double avg = 0;
      for(int i=1; i<=20; i++) avg += atr[i];
      avg /= 20.0;
      if(avg <= 0) return 0;
      double ratio = atr[0] / avg;
      if(ratio >= 2.0) return 2;
      if(ratio >= 1.5) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P4 — BB squeeze: H1 band width < 1.0 ATR for 3+ of last 5 bars
   //   Pre-breakout compression = energy build-up
   //+----------------------------------------------------------------+
   int ScoreBBSqueeze()
   {
      double upper[5], lower[5];
      ArraySetAsSeries(upper, true); ArraySetAsSeries(lower, true);
      if(CopyBuffer(m_bbH1, 1, 0, 5, upper) < 5) return 0;
      if(CopyBuffer(m_bbH1, 2, 0, 5, lower) < 5) return 0;

      double atr = GetATR_H1();
      if(atr <= 0) return 0;

      int squeezeCount = 0;
      for(int i=1; i<=4; i++)  // skip bar 0 (forming), check bars 1-4
         if((upper[i] - lower[i]) < atr * 1.0) squeezeCount++;

      if(squeezeCount >= 3) return 2;
      if(squeezeCount >= 2) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P5 — Volume spike on the breakout bar (H1 bar 1 or 0) (2pts)
   //+----------------------------------------------------------------+
   int ScoreVolume()
   {
      long vol[21];
      ArraySetAsSeries(vol, true);
      if(CopyTickVolume(m_symbol, PERIOD_H1, 0, 21, vol) < 21) return 0;

      double avg = 0;
      for(int i=2; i<=20; i++) avg += (double)vol[i];  // skip current + prev
      avg /= 19.0;
      if(avg <= 0) return 0;

      // Check breakout bar (bar 1 = last completed)
      double ratio = (double)vol[1] / avg;
      if(ratio >= 2.5) return 2;
      if(ratio >= 1.8) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P6 — H4 EMA 200: price on correct side (trend aligns breakout)
   //+----------------------------------------------------------------+
   int ScoreH4Context(int dir)
   {
      double ema[2];
      ArraySetAsSeries(ema, true);
      if(m_emaH4 == INVALID_HANDLE) return 0;
      if(CopyBuffer(m_emaH4, 0, 0, 2, ema) < 2) return 0;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      bool priceOK = (dir == 1) ? (price > ema[0]) : (price < ema[0]);
      bool slopeOK = (dir == 1) ? (ema[0] > ema[1]) : (ema[0] < ema[1]);
      if(priceOK && slopeOK) return 2;
      if(priceOK)            return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // Build Asia range: scan H1 bars from 00:00 to 07:00 UTC today
   //+----------------------------------------------------------------+
   void CalcAsiaRange()
   {
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime asiaStart = StructToTime(dt);
      datetime asiaEnd   = asiaStart + 7 * 3600;  // 07:00 UTC

      double high = 0, low = DBL_MAX;
      bool found = false;
      for(int i = 0; i < 50; i++)
      {
         datetime barTime = iTime(m_symbol, PERIOD_H1, i);
         if(barTime <= 0) break;
         if(barTime < asiaStart) break;
         if(barTime >= asiaEnd) continue;  // skip bars after 07:00
         double barH = iHigh(m_symbol, PERIOD_H1, i);
         double barL = iLow (m_symbol, PERIOD_H1, i);
         if(barH > high) high = barH;
         if(barL < low)  low  = barL;
         found = true;
      }
      if(found && high > low) { m_asiaHigh = high; m_asiaLow = low; }
   }

   double GetATR_H1()
   {
      double atr[1];
      if(m_atrH1 != INVALID_HANDLE && CopyBuffer(m_atrH1, 0, 0, 1, atr) == 1) return atr[0];
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 150;
   }
};

#endif
