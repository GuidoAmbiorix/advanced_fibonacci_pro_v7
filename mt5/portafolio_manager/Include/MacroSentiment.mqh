//+------------------------------------------------------------------+
//|                                              MacroSentiment.mqh  |
//|  Macro Sentiment Proxy — DXY + VIX + Safe Haven                  |
//|                                                                  |
//|  DXY Proxy  : Weighted EMA slope of 5 USD crosses               |
//|  VIX Proxy  : ATR(14)/ATR(50) ratio across 4 pairs              |
//|  Safe Haven : XAUUSD momentum + USDJPY inverse momentum         |
//|                                                                  |
//|  Output: GetRiskMultiplier() → 0.25–1.00                        |
//|          IsConflicting(sym, dir) → block counter-DXY entries    |
//+------------------------------------------------------------------+
#ifndef MACRO_SENTIMENT_MQH
#define MACRO_SENTIMENT_MQH

#define MS_DXY_PAIRS 5
#define MS_VIX_PAIRS 4

//+------------------------------------------------------------------+
//| DXY component weights (sum = 1.0)                                |
//+------------------------------------------------------------------+
struct DXYComponent
{
   string symbol;
   double weight;
   bool   usdIsBase; // true = USD/xxx (USDJPY, USDCAD, USDCHF)
                     // false = xxx/USD (EURUSD, GBPUSD)
};

class CMacroSentiment
{
private:
   DXYComponent     m_dxy[MS_DXY_PAIRS];

   string           m_vixSymbols[MS_VIX_PAIRS];
   int              m_hATRFast[MS_VIX_PAIRS];   // ATR(14)
   int              m_hATRSlow[MS_VIX_PAIRS];   // ATR(50)

   // EMA handles for DXY slope
   int              m_hEMA_DXY[MS_DXY_PAIRS];   // EMA(20) on each DXY pair

   // Safe haven
   int              m_hATR_Gold;
   int              m_hEMA_Gold;    // EMA(20) XAUUSD
   int              m_hEMA_USDJPY; // EMA(20) USDJPY

   // State
   bool   m_initialized;
   double m_lastDXY;       // +1 = strong USD, -1 = weak USD
   double m_lastVIX;       // ratio: >1.0 = elevated vol
   double m_lastSafeHaven; // +1 = risk-off, -1 = risk-on
   double m_lastMultiplier;
   datetime m_lastUpdate;
   int    m_emaPeriod;

public:
   CMacroSentiment()
   {
      m_initialized  = false;
      m_lastDXY      = 0;
      m_lastVIX      = 1.0;
      m_lastSafeHaven = 0;
      m_lastMultiplier = 1.0;
      m_lastUpdate   = 0;
      m_emaPeriod    = 20;
      m_hATR_Gold    = INVALID_HANDLE;
      m_hEMA_Gold    = INVALID_HANDLE;
      m_hEMA_USDJPY  = INVALID_HANDLE;
            for(int i=0;i<MS_VIX_PAIRS;i++){m_hATRFast[i]=INVALID_HANDLE;m_hATRSlow[i]=INVALID_HANDLE;}
      for(int i=0;i<MS_DXY_PAIRS;i++) m_hEMA_DXY[i]=INVALID_HANDLE;
   }

   bool Init(ENUM_TIMEFRAMES tf = PERIOD_H4)
   {
      // ── DXY components ──────────────────────────────────────────
      // EURUSD  57.6% (USD is quote — invert)
      m_dxy[0].symbol = "EURUSD"; m_dxy[0].weight = 0.576; m_dxy[0].usdIsBase = false;
      // USDJPY  13.6%
      m_dxy[1].symbol = "USDJPY"; m_dxy[1].weight = 0.136; m_dxy[1].usdIsBase = true;
      // GBPUSD  11.9% (invert)
      m_dxy[2].symbol = "GBPUSD"; m_dxy[2].weight = 0.119; m_dxy[2].usdIsBase = false;
      // USDCAD   9.1%
      m_dxy[3].symbol = "USDCAD"; m_dxy[3].weight = 0.091; m_dxy[3].usdIsBase = true;
      // USDCHF   3.6%  (EUR+JPY+GBP+CAD = 93.6%, remaining ~3.6% CHF, ignoring SEK/NOK)
      m_dxy[4].symbol = "USDCHF"; m_dxy[4].weight = 0.036; m_dxy[4].usdIsBase = true;

      // ── VIX pairs ───────────────────────────────────────────────
      m_vixSymbols[0] = "EURUSD";
      m_vixSymbols[1] = "GBPUSD";
      m_vixSymbols[2] = "USDJPY";
      m_vixSymbols[3] = "XAUUSD";

      // Create indicator handles — skip pairs not available in this broker
      for(int i = 0; i < MS_DXY_PAIRS; i++)
      {
         if(!_SymbolExists(m_dxy[i].symbol)) { m_hEMA_DXY[i] = INVALID_HANDLE; continue; }
         m_hEMA_DXY[i] = iMA(m_dxy[i].symbol, tf, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
         if(m_hEMA_DXY[i] == INVALID_HANDLE)
            Print("[MacroSentiment] Warning: EMA handle failed for ", m_dxy[i].symbol);
      }

      for(int i = 0; i < MS_VIX_PAIRS; i++)
      {
         if(!_SymbolExists(m_vixSymbols[i])) { m_hATRFast[i] = m_hATRSlow[i] = INVALID_HANDLE; continue; }
         m_hATRFast[i] = iATR(m_vixSymbols[i], tf, 14);
         m_hATRSlow[i] = iATR(m_vixSymbols[i], tf, 50);
      }

      if(_SymbolExists("XAUUSD"))
      {
         m_hATR_Gold  = iATR("XAUUSD", tf, 14);
         m_hEMA_Gold  = iMA("XAUUSD", tf, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      }
      if(_SymbolExists("USDJPY"))
         m_hEMA_USDJPY = iMA("USDJPY", tf, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

      m_initialized = true; // soft init — missing handles degrade gracefully
      return true;
   }

   void Deinit()
   {
      for(int i = 0; i < MS_DXY_PAIRS; i++)
         if(m_hEMA_DXY[i] != INVALID_HANDLE) { IndicatorRelease(m_hEMA_DXY[i]); m_hEMA_DXY[i] = INVALID_HANDLE; }
      for(int i = 0; i < MS_VIX_PAIRS; i++)
      {
         if(m_hATRFast[i] != INVALID_HANDLE) { IndicatorRelease(m_hATRFast[i]); m_hATRFast[i] = INVALID_HANDLE; }
         if(m_hATRSlow[i] != INVALID_HANDLE) { IndicatorRelease(m_hATRSlow[i]); m_hATRSlow[i] = INVALID_HANDLE; }
      }
      if(m_hATR_Gold   != INVALID_HANDLE) { IndicatorRelease(m_hATR_Gold);  m_hATR_Gold  = INVALID_HANDLE; }
      if(m_hEMA_Gold   != INVALID_HANDLE) { IndicatorRelease(m_hEMA_Gold);  m_hEMA_Gold  = INVALID_HANDLE; }
      if(m_hEMA_USDJPY != INVALID_HANDLE) { IndicatorRelease(m_hEMA_USDJPY); m_hEMA_USDJPY = INVALID_HANDLE; }
      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   //| Call once per bar                                                  |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(!m_initialized) return;
      datetime barTime = iTime(_Symbol, PERIOD_H4, 0);
      if(barTime == m_lastUpdate) return;
      m_lastUpdate = barTime;

      m_lastDXY      = _ComputeDXY();
      m_lastVIX      = _ComputeVIX();
      m_lastSafeHaven = _ComputeSafeHaven();
      m_lastMultiplier = _ComputeMultiplier();
   }

   //+------------------------------------------------------------------+
   //| Risk multiplier: 0.25 (risk-off, high vol) → 1.00 (normal)       |
   //+------------------------------------------------------------------+
   double GetRiskMultiplier() { return m_lastMultiplier; }

   //+------------------------------------------------------------------+
   //| Returns true if trading this symbol/direction conflicts with DXY  |
   //| Only blocks when DXY signal is strong (|dxy| > 0.5)              |
   //+------------------------------------------------------------------+
   bool IsConflicting(string symbol, int orderType)
   {
      if(MathAbs(m_lastDXY) < 0.5) return false; // DXY signal too weak — no filter

      bool dxyBullishUSD = (m_lastDXY > 0);

      // Determine if this trade direction is USD-bullish or USD-bearish
      // USD base pairs: USDJPY, USDCAD, USDCHF — BUY = USD bullish
      // USD quote pairs: EURUSD, GBPUSD, AUDUSD, NZDUSD — BUY = USD bearish
      bool usdIsBase = (StringFind(symbol, "USD") == 0);
      bool symIsUSDPair = (StringFind(symbol, "USD") >= 0);
      if(!symIsUSDPair) return false; // not a USD pair — no DXY filter

      bool tradeUSDLong;
      if(usdIsBase)
         tradeUSDLong = (orderType == ORDER_TYPE_BUY);
      else
         tradeUSDLong = (orderType == ORDER_TYPE_SELL);

      // Conflict: DXY trending strongly one way but trade goes opposite
      return (dxyBullishUSD && !tradeUSDLong) || (!dxyBullishUSD && tradeUSDLong);
   }

   // Dashboard status line
   string GetStatus()
   {
      return StringFormat("Macro: DXY=%+.2f VIX=%.2f SH=%+.2f Mult=%.2f",
                          m_lastDXY, m_lastVIX, m_lastSafeHaven, m_lastMultiplier);
   }

   double GetDXY()       { return m_lastDXY; }
   double GetVIX()       { return m_lastVIX; }
   double GetSafeHaven() { return m_lastSafeHaven; }

private:
   //+------------------------------------------------------------------+
   //| DXY Proxy: weighted EMA slope, normalized to -1..+1              |
   //+------------------------------------------------------------------+
   double _ComputeDXY()
   {
      double dxy = 0;
      double totalWeight = 0;

      for(int i = 0; i < MS_DXY_PAIRS; i++)
      {
         if(m_hEMA_DXY[i] == INVALID_HANDLE) continue;

         double ema[];
         ArraySetAsSeries(ema, true);
         if(CopyBuffer(m_hEMA_DXY[i], 0, 1, 5, ema) < 5) continue;

         // Slope = (EMA[0] - EMA[4]) / EMA[4] normalized as % change
         double slope = (ema[0] > 0) ? (ema[0] - ema[4]) / ema[4] * 100.0 : 0;

         // If USD is quote (EURUSD, GBPUSD) invert — rising EUR/GBP = weak USD
         if(!m_dxy[i].usdIsBase) slope = -slope;

         dxy += slope * m_dxy[i].weight;
         totalWeight += m_dxy[i].weight;
      }

      if(totalWeight < 0.01) return 0;
      dxy /= totalWeight;

      // Normalize: cap at ±0.15% EMA move = ±1.0 score
      return MathMax(-1.0, MathMin(1.0, dxy / 0.15));
   }

   //+------------------------------------------------------------------+
   //| VIX Proxy: ATR(14)/ATR(50) average across 4 pairs                |
   //| >1.0 = elevated volatility                                       |
   //+------------------------------------------------------------------+
   double _ComputeVIX()
   {
      double total = 0;
      int count = 0;

      for(int i = 0; i < MS_VIX_PAIRS; i++)
      {
         if(m_hATRFast[i] == INVALID_HANDLE || m_hATRSlow[i] == INVALID_HANDLE) continue;

         double atrFast[], atrSlow[];
         ArraySetAsSeries(atrFast, true);
         ArraySetAsSeries(atrSlow, true);
         if(CopyBuffer(m_hATRFast[i], 0, 1, 1, atrFast) < 1) continue;
         if(CopyBuffer(m_hATRSlow[i], 0, 1, 1, atrSlow) < 1) continue;
         if(atrSlow[0] <= 0) continue;

         total += atrFast[0] / atrSlow[0];
         count++;
      }

      return (count > 0) ? total / count : 1.0;
   }

   //+------------------------------------------------------------------+
   //| Safe Haven: gold up + USDJPY down = risk-off (+1)               |
   //+------------------------------------------------------------------+
   double _ComputeSafeHaven()
   {
      double score = 0;
      int components = 0;

      // Gold momentum: EMA slope = risk-off signal
      if(m_hEMA_Gold != INVALID_HANDLE)
      {
         double ema2[];
         ArraySetAsSeries(ema2, true);
         if(CopyBuffer(m_hEMA_Gold, 0, 1, 5, ema2) >= 5)
         {
            double goldSlope = (ema2[0] > 0) ? (ema2[0] - ema2[4]) / ema2[4] * 100 : 0;
            score += MathMax(-1.0, MathMin(1.0, goldSlope / 0.30)); // gold moves more
            components++;
         }
      }

      // USDJPY: falling = JPY strengthening = risk-off
      if(m_hEMA_USDJPY != INVALID_HANDLE)
      {
         double ema[];
         ArraySetAsSeries(ema, true);
         if(CopyBuffer(m_hEMA_USDJPY, 0, 1, 5, ema) >= 5)
         {
            double jpySlope = (ema[0] > 0) ? (ema[0] - ema[4]) / ema[4] * 100 : 0;
            score -= MathMax(-1.0, MathMin(1.0, jpySlope / 0.15)); // invert: USDJPY down = risk-off
            components++;
         }
      }

      return (components > 0) ? score / components : 0;
   }

   //+------------------------------------------------------------------+
   //| Combined multiplier: 0.25–1.00                                   |
   //| High VIX + strong safe haven signal = lower multiplier           |
   //+------------------------------------------------------------------+
   double _ComputeMultiplier()
   {
      double mult = 1.0;

      // VIX penalty: ratio > 1.5 starts reducing size
      if(m_lastVIX > 1.5)
      {
         double excess = MathMin(m_lastVIX - 1.5, 1.5); // cap at 3.0
         mult *= MathMax(0.40, 1.0 - excess * 0.40);    // 1.5 → 1.0x, 3.0 → 0.4x
      }

      // Safe haven penalty: strong risk-off reduces position size
      if(m_lastSafeHaven > 0.5)
      {
         double shPenalty = (m_lastSafeHaven - 0.5) / 0.5;
         mult *= MathMax(0.50, 1.0 - shPenalty * 0.30); // max -30% from safe haven
      }

      // DXY extreme: very strong trend → we allow it (no penalty),
      // but trade direction filter (IsConflicting) handles the directional risk

      return MathMax(0.25, MathMin(1.0, mult));
   }

   bool _SymbolExists(string sym)
   {
      return (SymbolInfoDouble(sym, SYMBOL_BID) > 0);
   }
};

#endif
