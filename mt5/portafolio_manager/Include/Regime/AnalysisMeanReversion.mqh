//+------------------------------------------------------------------+
//|                                    AnalysisMeanReversion.mqh    |
//|  Strategy module: RANGING markets                                |
//|  Logic: Buy near BB lower + RSI oversold, Sell near BB upper     |
//|         TP = BB midline. SL = beyond outer band.                 |
//|         No runner. Quick escalator. Works 35% of the time.       |
//+------------------------------------------------------------------+
#ifndef ANALYSIS_MEAN_REVERSION_MQH_INCLUDED
#define ANALYSIS_MEAN_REVERSION_MQH_INCLUDED

struct MRSignal
{
   bool   valid;
   int    direction;    // ORDER_TYPE_BUY=0, ORDER_TYPE_SELL=1
   double entryPrice;
   double slPrice;
   double tpPrice;
   double slPips;
   double tpPips;
   int    score;        // confluence score
   string reason;
};

class CAnalysisMeanReversion
{
private:
   int    m_hBB;
   int    m_hRSI;
   int    m_hATR;
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;

   // BB params
   int    m_bbPeriod;
   double m_bbDeviation;
   // RSI params
   int    m_rsiPeriod;
   double m_rsiOversold;
   double m_rsiOverbought;
   // ATR
   int    m_atrPeriod;
   // SL buffer beyond band (ATR multiples)
   double m_slATR_Mult;

public:
   CAnalysisMeanReversion()
   {
      m_hBB         = INVALID_HANDLE;
      m_hRSI        = INVALID_HANDLE;
      m_hATR        = INVALID_HANDLE;
      m_bbPeriod    = 20;
      m_bbDeviation = 2.0;
      m_rsiPeriod   = 14;
      m_rsiOversold = 35.0;
      m_rsiOverbought = 65.0;
      m_atrPeriod   = 14;
      m_slATR_Mult  = 0.5;
   }

   bool Init(string symbol, ENUM_TIMEFRAMES tf,
             int bbPeriod = 20, double bbDev = 2.0,
             int rsiPeriod = 14, double rsiOS = 35.0, double rsiOB = 65.0,
             int atrPeriod = 14, double slATR = 0.5)
   {
      m_symbol      = symbol;
      m_tf          = tf;
      m_bbPeriod    = bbPeriod;
      m_bbDeviation = bbDev;
      m_rsiPeriod   = rsiPeriod;
      m_rsiOversold = rsiOS;
      m_rsiOverbought = rsiOB;
      m_atrPeriod   = atrPeriod;
      m_slATR_Mult  = slATR;

      m_hBB  = iBands(symbol, tf, bbPeriod, 0, bbDev, PRICE_CLOSE);
      m_hRSI = iRSI(symbol, tf, rsiPeriod, PRICE_CLOSE);
      m_hATR = iATR(symbol, tf, atrPeriod);

      return (m_hBB != INVALID_HANDLE && m_hRSI != INVALID_HANDLE && m_hATR != INVALID_HANDLE);
   }

   void Deinit()
   {
      if(m_hBB  != INVALID_HANDLE) { IndicatorRelease(m_hBB);  m_hBB  = INVALID_HANDLE; }
      if(m_hRSI != INVALID_HANDLE) { IndicatorRelease(m_hRSI); m_hRSI = INVALID_HANDLE; }
      if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
   }

   //+------------------------------------------------------------------+
   //| Analyze current bar and return signal                             |
   //+------------------------------------------------------------------+
   MRSignal Analyze()
   {
      MRSignal sig;
      sig.valid     = false;
      sig.direction = -1;
      sig.score     = 0;
      sig.reason    = "";

      if(m_hBB == INVALID_HANDLE || m_hRSI == INVALID_HANDLE || m_hATR == INVALID_HANDLE)
         return sig;

      // Read Bollinger Bands (buffer 0=mid, 1=upper, 2=lower)
      double bbMid[], bbUp[], bbLow[];
      ArraySetAsSeries(bbMid,  true);
      ArraySetAsSeries(bbUp,   true);
      ArraySetAsSeries(bbLow,  true);
      if(CopyBuffer(m_hBB, 0, 1, 3, bbMid) < 3) return sig;
      if(CopyBuffer(m_hBB, 1, 1, 3, bbUp)  < 3) return sig;
      if(CopyBuffer(m_hBB, 2, 1, 3, bbLow) < 3) return sig;

      // Read RSI
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(m_hRSI, 0, 1, 3, rsi) < 3) return sig;

      // Read ATR
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_hATR, 0, 1, 2, atr) < 2) return sig;

      // Read closes (last 3 bars)
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, m_tf, 1, 3, closes) < 3) return sig;

      double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double bbWidth = bbUp[0] - bbLow[0];
      double atrNow  = atr[0];

      // ── BUY signal: price pierced below BB lower, RSI oversold ─────
      bool priceBelowLower = (closes[1] < bbLow[1]);  // prev bar below band
      bool rsiOversold     = (rsi[0] < m_rsiOversold);
      bool rsiRecovering   = (rsi[0] > rsi[1]);         // RSI turning up
      bool priceRecovering = (closes[0] > closes[1]);   // price turning up

      if(priceBelowLower && rsiOversold)
      {
         sig.valid     = true;
         sig.direction = ORDER_TYPE_BUY;
         sig.entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         sig.slPrice    = bbLow[0] - (atrNow * m_slATR_Mult);
         sig.tpPrice    = bbMid[0];
         sig.slPips     = (sig.entryPrice - sig.slPrice) / point;
         sig.tpPips     = (sig.tpPrice - sig.entryPrice) / point;

         // Build score
         sig.score += 10;  // base: price below BB
         if(rsiOversold)   sig.score += 8;
         if(rsiRecovering) sig.score += 6;
         if(priceRecovering) sig.score += 6;
         // Pin bar / wick rejection bonus
         double lastLow  = 0, lastHigh = 0, lastClose = 0, lastOpen = 0;
         double tmpLow[], tmpHigh[], tmpOpen[];
         ArraySetAsSeries(tmpLow,  true);
         ArraySetAsSeries(tmpHigh, true);
         ArraySetAsSeries(tmpOpen, true);
         if(CopyLow(m_symbol,  m_tf, 1, 2, tmpLow)  >= 2 &&
            CopyHigh(m_symbol, m_tf, 1, 2, tmpHigh) >= 2 &&
            CopyOpen(m_symbol, m_tf, 1, 2, tmpOpen) >= 2)
         {
            double lowerWick = MathMin(tmpOpen[1], closes[1]) - tmpLow[1];
            double body      = MathAbs(tmpOpen[1] - closes[1]);
            if(lowerWick > body * 1.5) sig.score += 8;  // bullish pin bar
         }

         sig.reason = StringFormat("MR BUY: BB_pierce+RSI%.0f score=%d", rsi[0], sig.score);
      }

      // ── SELL signal: price pierced above BB upper, RSI overbought ──
      bool priceAboveUpper = (closes[1] > bbUp[1]);
      bool rsiOverbought   = (rsi[0] > m_rsiOverbought);
      bool rsiFalling      = (rsi[0] < rsi[1]);
      bool priceFalling    = (closes[0] < closes[1]);

      if(!sig.valid && priceAboveUpper && rsiOverbought)
      {
         sig.valid     = true;
         sig.direction = ORDER_TYPE_SELL;
         sig.entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         sig.slPrice    = bbUp[0] + (atrNow * m_slATR_Mult);
         sig.tpPrice    = bbMid[0];
         sig.slPips     = (sig.slPrice - sig.entryPrice) / point;
         sig.tpPips     = (sig.entryPrice - sig.tpPrice) / point;

         sig.score += 10;
         if(rsiOverbought) sig.score += 8;
         if(rsiFalling)    sig.score += 6;
         if(priceFalling)  sig.score += 6;

         sig.reason = StringFormat("MR SELL: BB_pierce+RSI%.0f score=%d", rsi[0], sig.score);
      }

      // Validate: TP must have at least 1:1 R:R (no point in worse)
      if(sig.valid && sig.tpPips < sig.slPips * 1.0)
      {
         sig.valid  = false;
         sig.reason = "MR: R:R too low";
      }

      return sig;
   }

   // BB width as % of price — useful for ranging confirmation
   double GetBBWidthPct()
   {
      double bbUp[], bbLow[], mid[];
      ArraySetAsSeries(bbUp,  true);
      ArraySetAsSeries(bbLow, true);
      ArraySetAsSeries(mid,   true);
      if(CopyBuffer(m_hBB, 0, 1, 1, mid)   < 1) return 0;
      if(CopyBuffer(m_hBB, 1, 1, 1, bbUp)  < 1) return 0;
      if(CopyBuffer(m_hBB, 2, 1, 1, bbLow) < 1) return 0;
      return (mid[0] > 0) ? ((bbUp[0] - bbLow[0]) / mid[0]) * 100.0 : 0;
   }
};

#endif
