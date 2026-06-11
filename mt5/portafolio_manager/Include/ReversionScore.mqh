//+------------------------------------------------------------------+
//|                                              ReversionScore.mqh  |
//|                         APEX Reversal — Mean Reversion Engine    |
//|                                                                  |
//|  Strategy: Catch price exhaustion after impulse moves on Gold.   |
//|  Entry: M30  |  Context: H1 + H4                                 |
//|                                                                  |
//|  6 Pillars (2pts each = 12 max):                                 |
//|  P1 — MACD H1 peak/trough turning                                |
//|  P2 — RSI H1 divergence (price vs RSI)                          |
//|  P3 — ADR exhaustion (today > 80% of avg daily range)           |
//|  P4 — Liquidity sweep trap (wick beyond level + rejection)       |
//|  P5 — Bollinger Band H1 extreme + close-back rejection          |
//|  P6 — H4 MACD context alignment                                  |
//|                                                                  |
//|  Min score for valid signal: 6/12 (3+ pillars)                  |
//+------------------------------------------------------------------+
#ifndef REVERSION_SCORE_MQH
#define REVERSION_SCORE_MQH

struct ReversionSignal
{
   bool   valid;
   int    direction;    // 1=BUY reversion, -1=SELL reversion
   int    score;        // 0-12
   double sweepLevel;   // price of the liquidity sweep (SL anchor)
   double tp1;          // VWAP — first target
   double tp2;          // BB midline H1 — second target
   double adrPct;       // % of ADR consumed today (e.g. 0.87 = 87%)
   string reason;       // human-readable pillar breakdown
};

class CReversionScore
{
private:
   string            m_symbol;

   // H1 indicators
   int               m_macdH1;   // MACD 12,26,9
   int               m_rsiH1;    // RSI 14
   int               m_bbH1;     // Bollinger Bands 20,2
   int               m_atrH1;    // ATR 14

   // H4 indicators
   int               m_macdH4;   // MACD 12,26,9
   int               m_rsiH4;    // RSI 14

   // ADR
   int               m_adrPeriod;

   // Internal VWAP (lightweight — uses daily open + current price)
   double            m_vwap;

public:
   CReversionScore()
   {
      m_symbol    = "";
      m_macdH1    = INVALID_HANDLE;
      m_rsiH1     = INVALID_HANDLE;
      m_bbH1      = INVALID_HANDLE;
      m_atrH1     = INVALID_HANDLE;
      m_macdH4    = INVALID_HANDLE;
      m_rsiH4     = INVALID_HANDLE;
      m_adrPeriod = 20;
      m_vwap      = 0;
   }

   //+----------------------------------------------------------------+
   bool Init(string symbol)
   {
      m_symbol = symbol;

      m_macdH1 = iMACD(symbol, PERIOD_H1, 12, 26, 9, PRICE_CLOSE);
      m_rsiH1  = iRSI (symbol, PERIOD_H1, 14, PRICE_CLOSE);
      m_bbH1   = iBands(symbol, PERIOD_H1, 20, 0, 2.0, PRICE_CLOSE);
      m_atrH1  = iATR (symbol, PERIOD_H1, 14);
      m_macdH4 = iMACD(symbol, PERIOD_H4, 12, 26, 9, PRICE_CLOSE);
      m_rsiH4  = iRSI (symbol, PERIOD_H4, 14, PRICE_CLOSE);

      bool ok = (m_macdH1 != INVALID_HANDLE && m_rsiH1 != INVALID_HANDLE &&
                 m_bbH1   != INVALID_HANDLE && m_atrH1 != INVALID_HANDLE &&
                 m_macdH4 != INVALID_HANDLE && m_rsiH4 != INVALID_HANDLE);

      if(ok) Print("[APEX] ReversionScore initialized on ", symbol);
      else   Print("[APEX] ERROR: failed to create indicator handles on ", symbol);
      return ok;
   }

   void Deinit()
   {
      if(m_macdH1 != INVALID_HANDLE) { IndicatorRelease(m_macdH1); m_macdH1 = INVALID_HANDLE; }
      if(m_rsiH1  != INVALID_HANDLE) { IndicatorRelease(m_rsiH1);  m_rsiH1  = INVALID_HANDLE; }
      if(m_bbH1   != INVALID_HANDLE) { IndicatorRelease(m_bbH1);   m_bbH1   = INVALID_HANDLE; }
      if(m_atrH1  != INVALID_HANDLE) { IndicatorRelease(m_atrH1);  m_atrH1  = INVALID_HANDLE; }
      if(m_macdH4 != INVALID_HANDLE) { IndicatorRelease(m_macdH4); m_macdH4 = INVALID_HANDLE; }
      if(m_rsiH4  != INVALID_HANDLE) { IndicatorRelease(m_rsiH4);  m_rsiH4  = INVALID_HANDLE; }
   }

   //+----------------------------------------------------------------+
   //| Main entry point — evaluates both directions, returns best     |
   //+----------------------------------------------------------------+
   ReversionSignal Calculate()
   {
      _UpdateVWAP();

      ReversionSignal sell = Evaluate(-1);
      ReversionSignal buy  = Evaluate( 1);

      if(!sell.valid && !buy.valid) { ReversionSignal empty; empty.valid=false; empty.score=0; empty.direction=0; empty.reason="NO_SIGNAL"; return empty; }
      if(sell.valid && !buy.valid)  return sell;
      if(buy.valid  && !sell.valid) return buy;
      return (sell.score >= buy.score) ? sell : buy;
   }

   //+----------------------------------------------------------------+
   //| Evaluate one direction (-1=SELL reversion, 1=BUY reversion)   |
   //+----------------------------------------------------------------+
   ReversionSignal Evaluate(int dir)
   {
      ReversionSignal sig;
      sig.valid     = false;
      sig.direction = dir;
      sig.score     = 0;
      sig.reason    = "";
      sig.sweepLevel = 0;
      sig.tp1        = m_vwap;
      sig.tp2        = GetBBMidline();
      sig.adrPct     = GetADRConsumed();

      if(m_macdH1 == INVALID_HANDLE) return sig;

      // ── P1: MACD H1 peak/trough turning (2 pts) ──────────────────
      int p1 = ScoreMACD_H1(dir);
      sig.score += p1;
      if(p1 > 0) sig.reason += "MACD_H1(" + IntegerToString(p1) + ") ";

      // ── P2: RSI H1 divergence (2 pts) ────────────────────────────
      int p2 = ScoreRSI_Divergence(dir);
      sig.score += p2;
      if(p2 > 0) sig.reason += "RSI_DIV(" + IntegerToString(p2) + ") ";

      // ── P3: ADR exhaustion (2 pts) ────────────────────────────────
      int p3 = ScoreADR(dir);
      sig.score += p3;
      if(p3 > 0) sig.reason += "ADR(" + IntegerToString(p3) + "%) ";

      // ── P4: Liquidity sweep trap (2 pts) ─────────────────────────
      double sweepPrice = 0;
      int p4 = ScoreLiquiditySweep(dir, sweepPrice);
      sig.score      += p4;
      sig.sweepLevel  = sweepPrice;
      if(p4 > 0) sig.reason += "SWEEP(" + IntegerToString(p4) + ") ";

      // ── P5: BB H1 extreme + rejection (2 pts) ────────────────────
      int p5 = ScoreBBExtreme(dir);
      sig.score += p5;
      if(p5 > 0) sig.reason += "BB_EXT(" + IntegerToString(p5) + ") ";

      // ── P6: H4 MACD context (2 pts) ──────────────────────────────
      int p6 = ScoreMACD_H4(dir);
      sig.score += p6;
      if(p6 > 0) sig.reason += "H4_CTX(" + IntegerToString(p6) + ") ";

      // ── Valid when >= 6/12 ────────────────────────────────────────
      sig.valid = (sig.score >= 6);

      return sig;
   }

   double GetVWAP()        { return m_vwap; }
   double GetADRConsumed() { return CalcADRConsumed(); }
   void   UpdateVWAP()     { _UpdateVWAP(); }  // public hook for OnTick pre-score update

private:

   //+----------------------------------------------------------------+
   // P1 — MACD H1: histogram peaked and now reversing (2 pts)
   //   SELL: hist was positive, now declining 2+ bars from peak
   //   BUY:  hist was negative, now rising 2+ bars from trough
   //+----------------------------------------------------------------+
   int ScoreMACD_H1(int dir)
   {
      double main[5], sig[5];
      if(CopyBuffer(m_macdH1, 0, 0, 5, main) < 5) return 0;
      if(CopyBuffer(m_macdH1, 1, 0, 5, sig)  < 5) return 0;

      double h[5];
      for(int i=0; i<5; i++) h[i] = main[i] - sig[i];
      // h[0]=current, h[1]=prev, h[2]=2 bars ago

      if(dir == -1) // SELL: histogram was positive and is turning down
      {
         if(h[2] > 0 && h[1] > 0 && h[0] < h[1]) // peaked, now declining
         {
            if(h[0] < h[1] && h[1] < h[2]) return 2; // 2 bars of decline
            return 1; // 1 bar of decline
         }
      }
      else // BUY: histogram was negative and is turning up
      {
         if(h[2] < 0 && h[1] < 0 && h[0] > h[1]) // troughed, now rising
         {
            if(h[0] > h[1] && h[1] > h[2]) return 2; // 2 bars of rise
            return 1;
         }
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P2 — RSI H1 divergence (2 pts)
   //   Uses lookback of 20 H1 bars to find swing + compare to price
   //+----------------------------------------------------------------+
   int ScoreRSI_Divergence(int dir)
   {
      double rsi[25];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(m_rsiH1, 0, 0, 25, rsi) < 25) return 0;

      double rsiNow = rsi[0];

      if(dir == -1) // SELL: RSI overbought + making lower high while price makes higher high
      {
         if(rsiNow < 60) return 0; // not overbought enough
         // Find highest RSI in lookback (bars 3-20)
         int peak = 3;
         for(int i=4; i<=20; i++) if(rsi[i] > rsi[peak]) peak = i;
         double priceNow = iHigh(m_symbol, PERIOD_H1, 0);
         double pricePeak= iHigh(m_symbol, PERIOD_H1, peak);
         bool priceHH = (priceNow >= pricePeak);
         bool rsiLH   = (rsiNow   <  rsi[peak]);
         if(priceHH && rsiLH) return 2; // classic bearish divergence
         if(rsiNow > 70)      return 1; // just overbought, no full divergence
      }
      else // BUY: RSI oversold + making higher low while price makes lower low
      {
         if(rsiNow > 40) return 0;
         int trough = 3;
         for(int i=4; i<=20; i++) if(rsi[i] < rsi[trough]) trough = i;
         double priceNow  = iLow(m_symbol, PERIOD_H1, 0);
         double priceTrough = iLow(m_symbol, PERIOD_H1, trough);
         bool priceLL = (priceNow <= priceTrough);
         bool rsiHL   = (rsiNow   >  rsi[trough]);
         if(priceLL && rsiHL) return 2;
         if(rsiNow < 30)      return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P3 — ADR exhaustion (2 pts)
   //   >80% of ADR20 consumed today = potential reversal zone
   //+----------------------------------------------------------------+
   int ScoreADR(int dir)
   {
      double pct = CalcADRConsumed();
      if(pct <= 0) return 0;

      // Extra validation: price needs to be at the extreme side
      double todayH = iHigh(m_symbol, PERIOD_D1, 0);
      double todayL = iLow (m_symbol, PERIOD_D1, 0);
      double price  = (dir == -1) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                  : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      // SELL: price near today's high. BUY: price near today's low
      double rangePos = (todayH > todayL) ? (price - todayL) / (todayH - todayL) : 0.5;
      bool atExtreme = (dir == -1) ? (rangePos > 0.75) : (rangePos < 0.25);

      if(!atExtreme) return 0;
      if(pct >= 0.95) return 2;
      if(pct >= 0.80) return 1;
      return 0;
   }

   //+----------------------------------------------------------------+
   // P4 — Liquidity sweep trap (2 pts)
   //   Wick swept beyond swing high/low + candle rejected back (trap)
   //   sweepPrice output = level that was swept (for SL placement)
   //+----------------------------------------------------------------+
   int ScoreLiquiditySweep(int dir, double &sweepPrice)
   {
      // Use M30 bars for entry-level sweep detection
      // Look at current + previous 3 bars for sweep signature
      double highs[5], lows[5], opens[5], closes[5];
      ArraySetAsSeries(highs,  true);
      ArraySetAsSeries(lows,   true);
      ArraySetAsSeries(opens,  true);
      ArraySetAsSeries(closes, true);

      if(CopyHigh (m_symbol, PERIOD_M30, 0, 5, highs)  < 5) return 0;
      if(CopyLow  (m_symbol, PERIOD_M30, 0, 5, lows)   < 5) return 0;
      if(CopyOpen (m_symbol, PERIOD_M30, 0, 5, opens)  < 5) return 0;
      if(CopyClose(m_symbol, PERIOD_M30, 0, 5, closes) < 5) return 0;

      // Reference level: highest high / lowest low in bars 2-4 (recent swing)
      double swingH = highs[2];
      double swingL = lows[2];
      for(int i=3; i<=4; i++)
      {
         if(highs[i] > swingH) swingH = highs[i];
         if(lows[i]  < swingL) swingL = lows[i];
      }

      double atr = GetATR_H1();

      if(dir == -1) // SELL: wick swept above swingH + closed below it (trap)
      {
         // Bar 1 (previous completed bar): wick above swing, body closed below
         bool wickAbove   = (highs[1]  > swingH);
         bool closedBelow = (closes[1] < swingH);
         bool bearCandle  = (closes[1] < opens[1]);
         if(wickAbove && closedBelow && bearCandle)
         {
            sweepPrice = highs[1] + atr * 0.3; // SL above the sweep wick
            return 2;
         }
         // Partial: bar 0 (current forming) sweeping
         if(highs[0] > swingH && closes[0] < swingH)
         {
            sweepPrice = highs[0] + atr * 0.3;
            return 1;
         }
      }
      else // BUY: wick swept below swingL + closed above it (trap)
      {
         bool wickBelow   = (lows[1]   < swingL);
         bool closedAbove = (closes[1] > swingL);
         bool bullCandle  = (closes[1] > opens[1]);
         if(wickBelow && closedAbove && bullCandle)
         {
            sweepPrice = lows[1] - atr * 0.3; // SL below the sweep wick
            return 2;
         }
         if(lows[0] < swingL && closes[0] > swingL)
         {
            sweepPrice = lows[0] - atr * 0.3;
            return 1;
         }
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P5 — BB H1 extreme + close-back rejection (2 pts)
   //   Price spiked outside 2σ band AND closed back inside = rejection
   //+----------------------------------------------------------------+
   int ScoreBBExtreme(int dir)
   {
      double bbUpper[3], bbLower[3], bbMid[3];
      ArraySetAsSeries(bbUpper, true);
      ArraySetAsSeries(bbLower, true);
      ArraySetAsSeries(bbMid,   true);
      if(CopyBuffer(m_bbH1, 1, 0, 3, bbUpper) < 3) return 0; // upper
      if(CopyBuffer(m_bbH1, 2, 0, 3, bbLower) < 3) return 0; // lower
      if(CopyBuffer(m_bbH1, 0, 0, 3, bbMid)   < 3) return 0; // middle

      double highH1[3], lowH1[3], closeH1[3];
      ArraySetAsSeries(highH1,  true);
      ArraySetAsSeries(lowH1,   true);
      ArraySetAsSeries(closeH1, true);
      if(CopyHigh (m_symbol, PERIOD_H1, 0, 3, highH1)  < 3) return 0;
      if(CopyLow  (m_symbol, PERIOD_H1, 0, 3, lowH1)   < 3) return 0;
      if(CopyClose(m_symbol, PERIOD_H1, 0, 3, closeH1) < 3) return 0;

      if(dir == -1) // SELL: price spiked above upper band + closed back inside
      {
         bool spikedAbove  = (highH1[1]  > bbUpper[1]);
         bool closedInside = (closeH1[1] < bbUpper[1]);
         bool currentBelow = (closeH1[0] < bbUpper[0]);
         if(spikedAbove && closedInside) return currentBelow ? 2 : 1;
         if(closeH1[0] > bbUpper[0])    return 1; // currently at extreme
      }
      else // BUY: price spiked below lower band + closed back inside
      {
         bool spikedBelow  = (lowH1[1]   < bbLower[1]);
         bool closedInside = (closeH1[1] > bbLower[1]);
         bool currentAbove = (closeH1[0] > bbLower[0]);
         if(spikedBelow && closedInside) return currentAbove ? 2 : 1;
         if(closeH1[0] < bbLower[0])    return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // P6 — H4 MACD context (2 pts)
   //   H4 histogram confirming the same reversal direction
   //+----------------------------------------------------------------+
   int ScoreMACD_H4(int dir)
   {
      double main[4], sig[4];
      if(CopyBuffer(m_macdH4, 0, 0, 4, main) < 4) return 0;
      if(CopyBuffer(m_macdH4, 1, 0, 4, sig)  < 4) return 0;

      double h[4];
      for(int i=0; i<4; i++) h[i] = main[i] - sig[i];

      if(dir == -1) // SELL reversion: H4 histogram positive but declining
      {
         bool wasPositive = (h[2] > 0 || h[3] > 0);
         bool declining   = (h[0] < h[1] && h[1] <= h[2]);
         bool nearZero    = (MathAbs(h[0]) < MathAbs(h[2]) * 0.5); // lost momentum
         if(wasPositive && declining && nearZero) return 2;
         if(wasPositive && declining)             return 1;
      }
      else // BUY reversion: H4 histogram negative but rising
      {
         bool wasNegative = (h[2] < 0 || h[3] < 0);
         bool rising      = (h[0] > h[1] && h[1] >= h[2]);
         bool nearZero    = (MathAbs(h[0]) < MathAbs(h[2]) * 0.5);
         if(wasNegative && rising && nearZero) return 2;
         if(wasNegative && rising)             return 1;
      }
      return 0;
   }

   //+----------------------------------------------------------------+
   // Helpers
   //+----------------------------------------------------------------+
   double CalcADRConsumed()
   {
      double adrSum = 0;
      for(int i=1; i<=m_adrPeriod; i++)
         adrSum += iHigh(m_symbol, PERIOD_D1, i) - iLow(m_symbol, PERIOD_D1, i);
      double adr = adrSum / m_adrPeriod;
      if(adr <= 0) return 0;
      double todayRng = iHigh(m_symbol, PERIOD_D1, 0) - iLow(m_symbol, PERIOD_D1, 0);
      return todayRng / adr;
   }

   double GetBBMidline()
   {
      double mid[1];
      if(CopyBuffer(m_bbH1, 0, 0, 1, mid) == 1) return mid[0];
      return 0;
   }

   double GetATR_H1()
   {
      double atr[1];
      if(m_atrH1 != INVALID_HANDLE && CopyBuffer(m_atrH1, 0, 0, 1, atr) == 1) return atr[0];
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 150; // fallback
   }

   void _UpdateVWAP()
   {
      // Lightweight VWAP from M5 today
      datetime sessionStart = iTime(m_symbol, PERIOD_D1, 0);
      if(sessionStart <= 0) return;

      double cumTP=0, cumVol=0;
      for(int i=0; i<200; i++)
      {
         datetime t = iTime(m_symbol, PERIOD_M5, i);
         if(t < sessionStart) break;
         double h = iHigh (m_symbol, PERIOD_M5, i);
         double l = iLow  (m_symbol, PERIOD_M5, i);
         double c = iClose(m_symbol, PERIOD_M5, i);
         double v = (double)iVolume(m_symbol, PERIOD_M5, i);
         if(v <= 0) v = 1;
         cumTP  += ((h+l+c)/3.0) * v;
         cumVol += v;
      }
      if(cumVol > 0) m_vwap = cumTP / cumVol;
   }
};

#endif
