//+------------------------------------------------------------------+
//|                                                MomentumScore.mqh |
//|                         APEX Momentum — H1 Momentum Burst Entry  |
//|                                                                  |
//|  Strategy: Catch momentum ignition after squeeze/consolidation.  |
//|  Entry: H1  |  Context: H4                                       |
//|                                                                  |
//|  6 Pillars (2pts each = 12 max):                                 |
//|  P1 — RSI H1: crossing 50 with force (2 bars of acceleration)   |
//|  P2 — MACD H1: signal line cross + histogram growing            |
//|  P3 — H4 trend alignment: EMA 200 H4 on same side               |
//|  P4 — Volume spike H1: tick volume > 1.5x 20-bar average        |
//|  P5 — ATR expansion H1: current > 1.2x ATR average              |
//|  P6 — H1 structure: recent HH/HL or LL/LH confirms direction    |
//|                                                                  |
//|  Min score: 6/12                                                 |
//+------------------------------------------------------------------+
#ifndef MOMENTUM_SCORE_MQH
#define MOMENTUM_SCORE_MQH

struct MomentumSignal
{
   bool   valid;
   int    direction;
   int    score;
   double entryPrice;
   double tp1;        // 1:1 fast target
   double tp2;        // 1:2 momentum extension
   string reason;
};

class CMomentumScore
{
private:
   string   m_symbol;
   int      m_rsiH1;
   int      m_macdH1;
   int      m_emaH4;
   int      m_atrH1;

public:
   CMomentumScore()
   {
      m_symbol = "";
      m_rsiH1  = INVALID_HANDLE;
      m_macdH1 = INVALID_HANDLE;
      m_emaH4  = INVALID_HANDLE;
      m_atrH1  = INVALID_HANDLE;
   }

   bool Init(string symbol)
   {
      m_symbol = symbol;
      m_rsiH1  = iRSI  (symbol, PERIOD_H1, 14, PRICE_CLOSE);
      m_macdH1 = iMACD (symbol, PERIOD_H1, 12, 26, 9, PRICE_CLOSE);
      m_emaH4  = iMA   (symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      m_atrH1  = iATR  (symbol, PERIOD_H1, 14);

      bool ok = (m_rsiH1 != INVALID_HANDLE && m_macdH1 != INVALID_HANDLE &&
                 m_emaH4 != INVALID_HANDLE && m_atrH1  != INVALID_HANDLE);
      if(ok) Print("[APEX MOMENTUM] MomentumScore initialized on ", symbol);
      else   Print("[APEX MOMENTUM] ERROR: failed to create handles on ", symbol);
      return ok;
   }

   void Deinit()
   {
      if(m_rsiH1  != INVALID_HANDLE) { IndicatorRelease(m_rsiH1);  m_rsiH1  = INVALID_HANDLE; }
      if(m_macdH1 != INVALID_HANDLE) { IndicatorRelease(m_macdH1); m_macdH1 = INVALID_HANDLE; }
      if(m_emaH4  != INVALID_HANDLE) { IndicatorRelease(m_emaH4);  m_emaH4  = INVALID_HANDLE; }
      if(m_atrH1  != INVALID_HANDLE) { IndicatorRelease(m_atrH1);  m_atrH1  = INVALID_HANDLE; }
   }

   void Update() { /* no per-bar state */ }

   MomentumSignal Calculate()
   {
      MomentumSignal sell = Evaluate(-1);
      MomentumSignal buy  = Evaluate( 1);
      if(!sell.valid && !buy.valid) { MomentumSignal e; e.valid=false; e.score=0; e.direction=0; e.reason="NO_SIGNAL"; return e; }
      if(sell.valid && !buy.valid)  return sell;
      if(buy.valid  && !sell.valid) return buy;
      return (sell.score >= buy.score) ? sell : buy;
   }

   MomentumSignal Evaluate(int dir)
   {
      MomentumSignal sig;
      sig.valid      = false;
      sig.direction  = dir;
      sig.score      = 0;
      sig.reason     = "";
      sig.entryPrice = SymbolInfoDouble(m_symbol, dir == 1 ? SYMBOL_ASK : SYMBOL_BID);

      if(m_rsiH1 == INVALID_HANDLE) return sig;

      // P1 — RSI H1 crossing 50 with acceleration (2pts)
      int p1 = ScoreRSICross(dir);
      sig.score += p1;
      if(p1 > 0) sig.reason += "RSI_CROSS(" + IntegerToString(p1) + ") ";

      // P2 — MACD H1 signal cross + growing histogram (2pts)
      int p2 = ScoreMACDCross(dir);
      sig.score += p2;
      if(p2 > 0) sig.reason += "MACD_CROSS(" + IntegerToString(p2) + ") ";

      // P3 — H4 EMA 200 alignment (2pts)
      int p3 = ScoreH4Alignment(dir);
      sig.score += p3;
      if(p3 > 0) sig.reason += "H4_ALIGN(" + IntegerToString(p3) + ") ";

      // P4 — Volume spike H1 (2pts)
      int p4 = ScoreVolume();
      sig.score += p4;
      if(p4 > 0) sig.reason += "VOL_SPIKE(" + IntegerToString(p4) + ") ";

      // P5 — ATR expansion H1 (2pts)
      int p5 = ScoreATR();
      sig.score += p5;
      if(p5 > 0) sig.reason += "ATR_EXP(" + IntegerToString(p5) + ") ";

      // P6 — H1 structure break (2pts)
      int p6 = ScoreStructure(dir);
      sig.score += p6;
      if(p6 > 0) sig.reason += "STRUCT(" + IntegerToString(p6) + ") ";

      sig.valid = (sig.score >= 6);

      double atr = GetATR_H1();
      sig.tp1 = (dir == 1) ? sig.entryPrice + atr * 2.0 : sig.entryPrice - atr * 2.0;
      sig.tp2 = (dir == 1) ? sig.entryPrice + atr * 4.0 : sig.entryPrice - atr * 4.0;

      return sig;
   }

private:

   //+----------------------------------------------------------------+
   // P1 — RSI H1: crossed 50 in last 2 bars + accelerating (2pts)
   //+----------------------------------------------------------------+
   int ScoreRSICross(int dir)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(m_rsiH1, 0, 0, 4, rsi) < 4) return 0;

      if(dir == 1)  // BUY: RSI crossed above 50 and rising
      {
         bool crossed = (rsi[1] < 50 && rsi[0] >= 50);  // just crossed
         bool rising2 = (rsi[2] < 50 && rsi[0] >= 50);   // crossing confirmed 2nd bar
         bool accel   = (rsi[0] > rsi[1]);
         if(crossed && accel)  return 2;
         if(rising2 && accel)  return 1;
         if(rsi[0] > 55)       return 1;  // already above with momentum
      }
      else  // SELL: RSI crossed below 50
      {
         bool crossed = (rsi[1] > 50 && rsi[0] <= 50);
         bool falling2= (rsi[2] > 50 && rsi[0] <= 50);
         bool accel   = (rsi[0] < rsi[1]);
         if(crossed && accel)  return 2;
         if(falling2 && accel) return 1;
         if(rsi[0] < 45)       return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P2 — MACD H1: signal line crossed + histogram growing (2pts)
   //+----------------------------------------------------------------+
   int ScoreMACDCross(int dir)
   {
      double main[4], sig[4];
      if(CopyBuffer(m_macdH1, 0, 0, 4, main) < 4) return 0;
      if(CopyBuffer(m_macdH1, 1, 0, 4, sig)  < 4) return 0;
      double h[4];
      for(int i=0; i<4; i++) h[i] = main[i] - sig[i];

      if(dir == 1)
      {
         bool recentCross = (h[1] < 0 && h[0] >= 0) || (h[2] < 0 && h[1] >= 0);
         bool growing     = (h[0] > 0 && h[0] > h[1]);
         if(recentCross && growing) return 2;
         if(growing && h[0] > 0)   return 1;
      }
      else
      {
         bool recentCross = (h[1] > 0 && h[0] <= 0) || (h[2] > 0 && h[1] <= 0);
         bool declining   = (h[0] < 0 && h[0] < h[1]);
         if(recentCross && declining) return 2;
         if(declining && h[0] < 0)   return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P3 — H4 EMA 200: price on correct side + slope aligned (2pts)
   //+----------------------------------------------------------------+
   int ScoreH4Alignment(int dir)
   {
      double ema[];
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
   // P4 — Volume spike: tick volume > 1.5x 20-bar average (2pts)
   //+----------------------------------------------------------------+
   int ScoreVolume()
   {
      long vol[];
      ArraySetAsSeries(vol, true);
      if(CopyTickVolume(m_symbol, PERIOD_H1, 0, 21, vol) < 21) return 0;

      double avg = 0;
      for(int i=1; i<=20; i++) avg += (double)vol[i];
      avg /= 20.0;
      if(avg <= 0) return 0;

      double ratio = (double)vol[0] / avg;
      if(ratio >= 2.0) return 2;
      if(ratio >= 1.5) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P5 — ATR expansion H1: current > 1.2x average (2pts)
   //+----------------------------------------------------------------+
   int ScoreATR()
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_atrH1, 0, 0, 21, atr) < 21) return 0;

      double avg = 0;
      for(int i=1; i<=20; i++) avg += atr[i];
      avg /= 20.0;
      if(avg <= 0) return 0;

      double ratio = atr[0] / avg;
      if(ratio >= 1.5) return 2;
      if(ratio >= 1.2) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P6 — H1 structure: HH+HL (buy) or LL+LH (sell) in last 6 bars
   //+----------------------------------------------------------------+
   int ScoreStructure(int dir)
   {
      double h[], l[];
      ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
      if(CopyHigh(m_symbol, PERIOD_H1, 1, 6, h) < 6) return 0;
      if(CopyLow (m_symbol, PERIOD_H1, 1, 6, l) < 6) return 0;

      bool hhhl = (h[0] > h[2] && l[0] > l[2]);  // higher high + higher low
      bool lllh = (l[0] < l[2] && h[0] < h[2]);  // lower low  + lower high

      if(dir == 1  && hhhl) return 2;
      if(dir == -1 && lllh) return 2;

      // Partial
      if(dir == 1  && h[0] > h[2]) return 1;
      if(dir == -1 && l[0] < l[2]) return 1;
      return 0;
   }

   double GetATR_H1()
   {
      double atr[1];
      if(m_atrH1 != INVALID_HANDLE && CopyBuffer(m_atrH1, 0, 0, 1, atr) == 1) return atr[0];
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 150;
   }
};

#endif
