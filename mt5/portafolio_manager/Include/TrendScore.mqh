//+------------------------------------------------------------------+
//|                                                   TrendScore.mqh |
//|                          APEX Trend — H4 Swing Trend Following   |
//|                                                                  |
//|  Strategy: Ride institutional trend moves on Gold.              |
//|  Entry: H4  |  Context: D1                                       |
//|                                                                  |
//|  6 Pillars (2pts each = 12 max):                                 |
//|  P1 — EMA 200 H4: price side + slope direction                  |
//|  P2 — D1 structure: HH+HL (buy) or LL+LH (sell) confirmed       |
//|  P3 — MACD H4: histogram same side + accelerating               |
//|  P4 — ATR expansion H4: above 20-bar average (momentum present) |
//|  P5 — RSI H4: momentum zone (50-70 buy / 30-50 sell)            |
//|  P6 — D1 VWAP: price in value zone                              |
//|                                                                  |
//|  Min score for valid signal: 6/12 (3+ pillars)                  |
//+------------------------------------------------------------------+
#ifndef TREND_SCORE_MQH
#define TREND_SCORE_MQH

struct TrendSignal
{
   bool   valid;
   int    direction;    // 1=BUY trend, -1=SELL trend
   int    score;        // 0-12
   double entryZone;    // pullback level (EMA or structure)
   double tp1;          // first target (swing high/low)
   double tp2;          // extended target (ATR projection)
   string reason;
};

class CTrendScore
{
private:
   string   m_symbol;
   int      m_emaH4;    // EMA 200 H4
   int      m_macdH4;   // MACD 12,26,9 H4
   int      m_rsiH4;    // RSI 14 H4
   int      m_atrH4;    // ATR 14 H4
   int      m_rsiD1;    // RSI 14 D1 (D1 structure proxy)

public:
   CTrendScore()
   {
      m_symbol = "";
      m_emaH4  = INVALID_HANDLE;
      m_macdH4 = INVALID_HANDLE;
      m_rsiH4  = INVALID_HANDLE;
      m_atrH4  = INVALID_HANDLE;
      m_rsiD1  = INVALID_HANDLE;
   }

   bool Init(string symbol)
   {
      m_symbol = symbol;
      m_emaH4  = iMA   (symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      m_macdH4 = iMACD (symbol, PERIOD_H4, 12, 26, 9, PRICE_CLOSE);
      m_rsiH4  = iRSI  (symbol, PERIOD_H4, 14, PRICE_CLOSE);
      m_atrH4  = iATR  (symbol, PERIOD_H4, 14);
      m_rsiD1  = iRSI  (symbol, PERIOD_D1, 14, PRICE_CLOSE);

      bool ok = (m_emaH4 != INVALID_HANDLE && m_macdH4 != INVALID_HANDLE &&
                 m_rsiH4 != INVALID_HANDLE && m_atrH4  != INVALID_HANDLE &&
                 m_rsiD1 != INVALID_HANDLE);
      if(ok) Print("[APEX TREND] TrendScore initialized on ", symbol);
      else   Print("[APEX TREND] ERROR: failed to create handles on ", symbol);
      return ok;
   }

   void Deinit()
   {
      if(m_emaH4  != INVALID_HANDLE) { IndicatorRelease(m_emaH4);  m_emaH4  = INVALID_HANDLE; }
      if(m_macdH4 != INVALID_HANDLE) { IndicatorRelease(m_macdH4); m_macdH4 = INVALID_HANDLE; }
      if(m_rsiH4  != INVALID_HANDLE) { IndicatorRelease(m_rsiH4);  m_rsiH4  = INVALID_HANDLE; }
      if(m_atrH4  != INVALID_HANDLE) { IndicatorRelease(m_atrH4);  m_atrH4  = INVALID_HANDLE; }
      if(m_rsiD1  != INVALID_HANDLE) { IndicatorRelease(m_rsiD1);  m_rsiD1  = INVALID_HANDLE; }
   }

   void Update() { /* no per-bar state needed */ }

   TrendSignal Calculate()
   {
      TrendSignal sell = Evaluate(-1);
      TrendSignal buy  = Evaluate( 1);
      if(!sell.valid && !buy.valid)  { TrendSignal e; e.valid=false; e.score=0; e.direction=0; e.reason="NO_SIGNAL"; return e; }
      if(sell.valid && !buy.valid)   return sell;
      if(buy.valid  && !sell.valid)  return buy;
      return (sell.score >= buy.score) ? sell : buy;
   }

   TrendSignal Evaluate(int dir)
   {
      TrendSignal sig;
      sig.valid      = false;
      sig.direction  = dir;
      sig.score      = 0;
      sig.reason     = "";
      sig.entryZone  = GetEMA200();
      sig.tp1        = 0;
      sig.tp2        = 0;

      if(m_emaH4 == INVALID_HANDLE) return sig;

      // P1 — EMA 200 H4: price side + slope (2pts)
      int p1 = ScoreEMA(dir);
      sig.score += p1;
      if(p1 > 0) sig.reason += "EMA200(" + IntegerToString(p1) + ") ";

      // P2 — D1 structure: HH+HL or LL+LH (2pts)
      int p2 = ScoreD1Structure(dir);
      sig.score += p2;
      if(p2 > 0) sig.reason += "D1_STRUCT(" + IntegerToString(p2) + ") ";

      // P3 — MACD H4: accelerating in trend direction (2pts)
      int p3 = ScoreMACD(dir);
      sig.score += p3;
      if(p3 > 0) sig.reason += "MACD_H4(" + IntegerToString(p3) + ") ";

      // P4 — ATR H4 expansion: above 20-bar average (2pts)
      int p4 = ScoreATRExpansion();
      sig.score += p4;
      if(p4 > 0) sig.reason += "ATR_EXP(" + IntegerToString(p4) + ") ";

      // P5 — RSI H4 momentum zone (2pts)
      int p5 = ScoreRSIMomentum(dir);
      sig.score += p5;
      if(p5 > 0) sig.reason += "RSI_MOM(" + IntegerToString(p5) + ") ";

      // P6 — D1 VWAP value zone (2pts)
      int p6 = ScoreVWAP(dir);
      sig.score += p6;
      if(p6 > 0) sig.reason += "VWAP(" + IntegerToString(p6) + ") ";

      sig.valid = (sig.score >= 6);

      // TP projections from ATR
      double atr = GetATR_H4();
      double price = SymbolInfoDouble(m_symbol, dir == 1 ? SYMBOL_ASK : SYMBOL_BID);
      sig.tp1 = (dir == 1) ? price + atr * 3.0 : price - atr * 3.0;
      sig.tp2 = (dir == 1) ? price + atr * 6.0 : price - atr * 6.0;

      return sig;
   }

private:

   //+----------------------------------------------------------------+
   // P1 — EMA 200 H4: price above/below + slope aligned (2pts)
   //+----------------------------------------------------------------+
   int ScoreEMA(int dir)
   {
      double ema[];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(m_emaH4, 0, 0, 3, ema) < 3) return 0;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      bool priceAligned = (dir == 1) ? (price > ema[0]) : (price < ema[0]);
      bool slopeAligned = (dir == 1) ? (ema[0] > ema[1] && ema[1] > ema[2])
                                     : (ema[0] < ema[1] && ema[1] < ema[2]);
      if(priceAligned && slopeAligned) return 2;
      if(priceAligned)                 return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P2 — D1 structure: 2 swings confirm trend direction (2pts)
   //   BUY:  last 2 D1 highs are HH AND last 2 D1 lows are HL
   //   SELL: last 2 D1 lows are LL AND last 2 D1 highs are LH
   //+----------------------------------------------------------------+
   int ScoreD1Structure(int dir)
   {
      // Use D1 bars 1-6 (confirmed, not current forming)
      double h[], l[];
      ArraySetAsSeries(h, true);
      ArraySetAsSeries(l, true);
      if(CopyHigh(m_symbol, PERIOD_D1, 1, 6, h) < 6) return 0;
      if(CopyLow (m_symbol, PERIOD_D1, 1, 6, l) < 6) return 0;

      // Find 2 most recent swing highs and lows in those 6 bars
      // Simple: compare bar 0 vs bar 2 vs bar 4 as swing reference
      bool hhhl = (h[0] > h[2] && l[0] > l[2] && h[2] > h[4] && l[2] > l[4]); // bullish
      bool lllh = (l[0] < l[2] && h[0] < h[2] && l[2] < l[4] && h[2] < h[4]); // bearish

      if(dir == 1 && hhhl) return 2;
      if(dir == -1 && lllh) return 2;

      // Partial: just one swing confirms
      bool partialBull = (h[0] > h[2] || l[0] > l[2]);
      bool partialBear = (l[0] < l[2] || h[0] < h[2]);
      if(dir == 1  && partialBull) return 1;
      if(dir == -1 && partialBear) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P3 — MACD H4: histogram same side as direction + growing (2pts)
   //+----------------------------------------------------------------+
   int ScoreMACD(int dir)
   {
      double main[4], sig[4];
      if(CopyBuffer(m_macdH4, 0, 0, 4, main) < 4) return 0;
      if(CopyBuffer(m_macdH4, 1, 0, 4, sig)  < 4) return 0;
      double h[4];
      for(int i=0; i<4; i++) h[i] = main[i] - sig[i];

      if(dir == 1)  // BUY: histogram positive and growing
      {
         bool positive = (h[0] > 0 && h[1] > 0);
         bool growing  = (h[0] > h[1]);
         if(positive && growing) return 2;
         if(positive)            return 1;
      }
      else  // SELL: histogram negative and declining
      {
         bool negative = (h[0] < 0 && h[1] < 0);
         bool declining= (h[0] < h[1]);
         if(negative && declining) return 2;
         if(negative)              return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P4 — ATR H4: current ATR > 1.2x 20-bar average (2pts)
   //   Pure momentum check — not direction-dependent
   //+----------------------------------------------------------------+
   int ScoreATRExpansion()
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_atrH4, 0, 0, 21, atr) < 21) return 0;

      double current = atr[0];
      double avg = 0;
      for(int i=1; i<=20; i++) avg += atr[i];
      avg /= 20.0;

      if(avg <= 0) return 0;
      double ratio = current / avg;
      if(ratio >= 1.4) return 2;
      if(ratio >= 1.2) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P5 — RSI H4 momentum zone: not OB/OS, riding the trend (2pts)
   //   BUY:  RSI 45-70 (momentum zone, not exhausted)
   //   SELL: RSI 30-55 (momentum zone, not exhausted)
   //+----------------------------------------------------------------+
   int ScoreRSIMomentum(int dir)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(m_rsiH4, 0, 0, 2, rsi) < 2) return 0;

      double r = rsi[0];
      if(dir == 1)
      {
         if(r >= 50 && r <= 65) return 2;  // core momentum zone
         if(r >= 45 && r <= 70) return 1;  // acceptable zone
      }
      else
      {
         if(r <= 50 && r >= 35) return 2;
         if(r <= 55 && r >= 30) return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P6 — D1 VWAP: price in value zone relative to VWAP (2pts)
   //+----------------------------------------------------------------+
   int ScoreVWAP(int dir)
   {
      // Approximate D1 VWAP from 5 recent D1 bars (simplified)
      double h[], l[], c[];
      long   v[];
      ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
      ArraySetAsSeries(c, true); ArraySetAsSeries(v, true);
      if(CopyHigh(m_symbol, PERIOD_D1, 0, 5, h)        < 5) return 0;
      if(CopyLow (m_symbol, PERIOD_D1, 0, 5, l)        < 5) return 0;
      if(CopyClose(m_symbol, PERIOD_D1, 0, 5, c)       < 5) return 0;
      if(CopyTickVolume(m_symbol, PERIOD_D1, 0, 5, v)  < 5) return 0;

      double cumTP=0, cumVol=0;
      for(int i=0; i<5; i++)
      {
         double tp = (h[i]+l[i]+c[i]) / 3.0;
         double vol = (double)v[i]; if(vol<=0) vol=1;
         cumTP  += tp * vol;
         cumVol += vol;
      }
      double vwap = (cumVol > 0) ? cumTP/cumVol : 0;
      if(vwap <= 0) return 0;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double atr   = GetATR_H4();
      double dist  = price - vwap;
      bool atVWAP  = (MathAbs(dist) <= atr * 0.5);

      if(atVWAP) return 2;
      if(dir == 1  && dist < 0) return 1;  // below VWAP = value area for buys
      if(dir == -1 && dist > 0) return 1;  // above VWAP = premium area for sells
      return 0;
   }

   double GetEMA200()
   {
      double ema[1];
      if(m_emaH4 != INVALID_HANDLE && CopyBuffer(m_emaH4, 0, 0, 1, ema) == 1) return ema[0];
      return 0;
   }

   double GetATR_H4()
   {
      double atr[1];
      if(m_atrH4 != INVALID_HANDLE && CopyBuffer(m_atrH4, 0, 0, 1, atr) == 1) return atr[0];
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 500;
   }
};

#endif
