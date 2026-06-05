//+------------------------------------------------------------------+
//|                                       AnalysisVolatility.mqh    |
//|  Strategy module: VOLATILE markets (ATR compression + breakout)  |
//|  Logic: Wait for ATR squeeze, then trade the breakout direction  |
//|         Small size, immediate harvest, tight runner.              |
//|  Works during: news releases, Asian→London open, key levels.     |
//+------------------------------------------------------------------+
#ifndef ANALYSIS_VOLATILITY_MQH_INCLUDED
#define ANALYSIS_VOLATILITY_MQH_INCLUDED

struct VolSignal
{
   bool   valid;
   int    direction;
   double entryPrice;
   double slPrice;
   double tpPrice;
   double slPips;
   double tpPips;
   int    score;
   string reason;
   bool   isBreakout;   // true = compression breakout, false = spike fade
};

class CAnalysisVolatility
{
private:
   int    m_hATR;
   int    m_hATR_Fast;   // fast ATR for compression detection
   int    m_hADX;
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;

   int    m_atrSlow;       // slow ATR period (baseline)
   int    m_atrFast;       // fast ATR (current compression measure)
   int    m_adxPeriod;
   double m_squeezeRatio;  // ATR fast/slow < this = compression
   double m_breakoutRatio; // ATR fast/slow > this = breakout confirmed
   int    m_compressionBars; // min bars in compression before trade
   double m_slATR_Mult;
   double m_tpATR_Mult;

   // State
   int    m_barsInCompression;
   bool   m_compressionActive;

public:
   CAnalysisVolatility()
   {
      m_hATR            = INVALID_HANDLE;
      m_hATR_Fast       = INVALID_HANDLE;
      m_hADX            = INVALID_HANDLE;
      m_atrSlow         = 50;
      m_atrFast         = 5;
      m_adxPeriod       = 14;
      m_squeezeRatio    = 0.70;   // ATR(5)/ATR(50) < 0.70 = squeeze
      m_breakoutRatio   = 1.30;   // ATR(5)/ATR(50) > 1.30 = breakout
      m_compressionBars = 3;
      m_slATR_Mult      = 1.2;    // SL = 1.2x ATR beyond entry
      m_tpATR_Mult      = 2.0;    // TP = 2x ATR from entry
      m_barsInCompression = 0;
      m_compressionActive = false;
   }

   bool Init(string symbol, ENUM_TIMEFRAMES tf,
             int atrSlow = 50, int atrFast = 5, int adxPeriod = 14,
             double squeezeRatio = 0.70, double breakoutRatio = 1.30,
             int compressionBars = 3, double slMult = 1.2, double tpMult = 2.0)
   {
      m_symbol          = symbol;
      m_tf              = tf;
      m_atrSlow         = atrSlow;
      m_atrFast         = atrFast;
      m_adxPeriod       = adxPeriod;
      m_squeezeRatio    = squeezeRatio;
      m_breakoutRatio   = breakoutRatio;
      m_compressionBars = compressionBars;
      m_slATR_Mult      = slMult;
      m_tpATR_Mult      = tpMult;

      m_hATR      = iATR(symbol, tf, atrSlow);
      m_hATR_Fast = iATR(symbol, tf, atrFast);
      m_hADX      = iADX(symbol, tf, adxPeriod);

      return (m_hATR != INVALID_HANDLE && m_hATR_Fast != INVALID_HANDLE && m_hADX != INVALID_HANDLE);
   }

   void Deinit()
   {
      if(m_hATR      != INVALID_HANDLE) { IndicatorRelease(m_hATR);      m_hATR      = INVALID_HANDLE; }
      if(m_hATR_Fast != INVALID_HANDLE) { IndicatorRelease(m_hATR_Fast); m_hATR_Fast = INVALID_HANDLE; }
      if(m_hADX      != INVALID_HANDLE) { IndicatorRelease(m_hADX);      m_hADX      = INVALID_HANDLE; }
   }

   //+------------------------------------------------------------------+
   //| Call on each new bar. Returns signal if breakout detected.        |
   //+------------------------------------------------------------------+
   VolSignal Analyze()
   {
      VolSignal sig;
      sig.valid       = false;
      sig.direction   = -1;
      sig.score       = 0;
      sig.reason      = "";
      sig.isBreakout  = false;

      if(m_hATR == INVALID_HANDLE || m_hATR_Fast == INVALID_HANDLE) return sig;

      // Read ATRs
      double atrSlow[], atrFast[];
      ArraySetAsSeries(atrSlow, true);
      ArraySetAsSeries(atrFast, true);
      if(CopyBuffer(m_hATR,      0, 1, 5, atrSlow) < 5) return sig;
      if(CopyBuffer(m_hATR_Fast, 0, 1, 5, atrFast) < 5) return sig;

      double slowNow  = atrSlow[0];
      double fastNow  = atrFast[0];
      double fastPrev = atrFast[1];
      if(slowNow <= 0) return sig;

      double ratio     = fastNow / slowNow;
      double ratioPrev = fastPrev / slowNow;

      // Read ADX
      double adxBuf[], diPlus[], diMinus[];
      ArraySetAsSeries(adxBuf,  true);
      ArraySetAsSeries(diPlus,  true);
      ArraySetAsSeries(diMinus, true);
      if(CopyBuffer(m_hADX, 0, 1, 2, adxBuf)  < 2) return sig;
      if(CopyBuffer(m_hADX, 1, 1, 2, diPlus)  < 2) return sig;
      if(CopyBuffer(m_hADX, 2, 1, 2, diMinus) < 2) return sig;

      // Read OHLC
      double closes[], highs[], lows[], opens[];
      ArraySetAsSeries(closes, true);
      ArraySetAsSeries(highs,  true);
      ArraySetAsSeries(lows,   true);
      ArraySetAsSeries(opens,  true);
      if(CopyClose(m_symbol, m_tf, 1, 5, closes) < 5) return sig;
      if(CopyHigh(m_symbol,  m_tf, 1, 5, highs)  < 5) return sig;
      if(CopyLow(m_symbol,   m_tf, 1, 5, lows)   < 5) return sig;
      if(CopyOpen(m_symbol,  m_tf, 1, 5, opens)  < 5) return sig;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      // ── PHASE 1: Detect compression ────────────────────────────────
      if(ratio < m_squeezeRatio)
      {
         m_barsInCompression++;
         m_compressionActive = true;
      }
      else if(ratio >= m_squeezeRatio)
      {
         if(ratio < m_breakoutRatio)
            m_barsInCompression = 0; // not breaking out yet, reset
      }

      // ── PHASE 2: Detect breakout from compression ──────────────────
      bool breakout = (m_compressionActive &&
                       m_barsInCompression >= m_compressionBars &&
                       ratio >= m_breakoutRatio &&
                       ratioPrev < m_breakoutRatio);

      if(!breakout) return sig;

      // ── PHASE 3: Direction of breakout ────────────────────────────
      // Use: last bar direction + DI± comparison
      bool bullBar    = (closes[0] > opens[0]);
      bool diPlusDom  = (diPlus[0] > diMinus[0]);
      bool adxRising  = (adxBuf[0] > adxBuf[1]);

      int dir = -1;
      if(bullBar && diPlusDom)   dir = ORDER_TYPE_BUY;
      if(!bullBar && !diPlusDom) dir = ORDER_TYPE_SELL;
      if(dir == -1) return sig; // no clean direction

      // Compression range high/low (for SL reference)
      double comprHigh = highs[ArrayMaximum(highs, 0, (int)MathMin(m_barsInCompression, 5))];
      double comprLow  = lows[ArrayMinimum(lows,   0, (int)MathMin(m_barsInCompression, 5))];

      sig.valid       = true;
      sig.direction   = dir;
      sig.isBreakout  = true;

      if(dir == ORDER_TYPE_BUY)
      {
         sig.entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         sig.slPrice    = comprLow - (slowNow * 0.3);
         sig.tpPrice    = sig.entryPrice + (fastNow * m_tpATR_Mult);
         sig.slPips     = (sig.entryPrice - sig.slPrice) / point;
         sig.tpPips     = (sig.tpPrice - sig.entryPrice) / point;
      }
      else
      {
         sig.entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         sig.slPrice    = comprHigh + (slowNow * 0.3);
         sig.tpPrice    = sig.entryPrice - (fastNow * m_tpATR_Mult);
         sig.slPips     = (sig.slPrice - sig.entryPrice) / point;
         sig.tpPips     = (sig.entryPrice - sig.tpPrice) / point;
      }

      // Score
      sig.score += 15;  // base: confirmed breakout from compression
      if(adxRising)  sig.score += 10;
      if(ratio > m_breakoutRatio * 1.3) sig.score += 8;  // strong breakout
      if(m_barsInCompression >= m_compressionBars * 2) sig.score += 7; // long squeeze

      sig.reason = StringFormat("VOL BREAKOUT %s: squeeze=%dbars ratio=%.2f score=%d",
                                 (dir == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                                 m_barsInCompression, ratio, sig.score);

      // Reset compression state after breakout
      m_barsInCompression = 0;
      m_compressionActive = false;

      return sig;
   }

   bool IsInCompression() { return m_compressionActive && m_barsInCompression >= m_compressionBars; }
   int  GetCompressionBars() { return m_barsInCompression; }
};

#endif
