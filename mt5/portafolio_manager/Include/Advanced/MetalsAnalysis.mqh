//+------------------------------------------------------------------+
//|                                              MetalsAnalysis.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                              https://github.com/GuidoAmbiorix    |
//+------------------------------------------------------------------+
#ifndef METALS_ANALYSIS_MQH
#define METALS_ANALYSIS_MQH

//+------------------------------------------------------------------+
//| METALS ANALYSIS MODULE                                           |
//| Purpose: Specialized analysis for precious metals (XAUUSD)      |
//| Focus: DXY correlation, safe-haven flows, volatility regimes     |
//| Conservative Approach: Quality over quantity, strict filters     |
//+------------------------------------------------------------------+
class CMetalsAnalysis
{
private:
   datetime m_lastUpdate;
   double   m_dxyTrend;            // DXY direction cache (-1 to +1)
   int      m_volatilityRegime;    // 0=low, 1=normal, 2=high, 3=spike
   int      m_riskSentiment;       // 0=risk-off, 1=neutral, 2=risk-on
   int      m_monthBias;           // Seasonal bias for current month (-1, 0, +1)

   int      m_hATR_EURUSD;         // ATR for USD strength proxy
   int      m_hATR_GBPUSD;
   int      m_hATR_USDJPY;
   int      m_hATR_Gold;           // ATR for gold volatility

   double   m_goldATR;             // Current gold ATR
   double   m_avgGoldATR;          // 20-period average gold ATR

   string   m_symbol;

public:
   CMetalsAnalysis() : m_lastUpdate(0), m_dxyTrend(0), m_volatilityRegime(1),
                       m_riskSentiment(1), m_monthBias(0),
                       m_hATR_EURUSD(INVALID_HANDLE), m_hATR_GBPUSD(INVALID_HANDLE),
                       m_hATR_USDJPY(INVALID_HANDLE), m_hATR_Gold(INVALID_HANDLE),
                       m_goldATR(0), m_avgGoldATR(0) {}

   ~CMetalsAnalysis()
   {
      if(m_hATR_EURUSD != INVALID_HANDLE) IndicatorRelease(m_hATR_EURUSD);
      if(m_hATR_GBPUSD != INVALID_HANDLE) IndicatorRelease(m_hATR_GBPUSD);
      if(m_hATR_USDJPY != INVALID_HANDLE) IndicatorRelease(m_hATR_USDJPY);
      if(m_hATR_Gold != INVALID_HANDLE) IndicatorRelease(m_hATR_Gold);
   }

   //+------------------------------------------------------------------+
   //| Initialize metals analysis module                                |
   //+------------------------------------------------------------------+
   bool Init(string symbol)
   {
      m_symbol = symbol;

      // Initialize ATR indicators for DXY proxy (major USD pairs)
      m_hATR_EURUSD = iATR(BrokerSymbol("EURUSD"), PERIOD_CURRENT, 14);
      m_hATR_GBPUSD = iATR(BrokerSymbol("GBPUSD"), PERIOD_CURRENT, 14);
      m_hATR_USDJPY = iATR(BrokerSymbol("USDJPY"), PERIOD_CURRENT, 14);

      // Initialize Gold ATR for volatility regime detection
      m_hATR_Gold = iATR(symbol, PERIOD_CURRENT, 14);

      if(m_hATR_EURUSD == INVALID_HANDLE || m_hATR_GBPUSD == INVALID_HANDLE ||
         m_hATR_USDJPY == INVALID_HANDLE || m_hATR_Gold == INVALID_HANDLE)
      {
         Print("MetalsAnalysis ERROR: Failed to initialize ATR indicators");
         return false;
      }

      Print("[OK] MetalsAnalysis initialized for ", symbol);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get confluence score for metals (conservative bias)             |
   //| Range: -5 to +6 points                                          |
   //| Typical: -2 to +3 points (net filtering effect)                 |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      UpdateCache();

      double score = 0.0;

      // 1. DXY Correlation Analysis (±2 points)
      score += GetDXYCorrelationScore(direction);

      // 2. Safe-Haven Flow Detection (±2 points)
      score += GetSafeHavenScore(direction);

      // 3. Volatility Regime Filter (-2 to +1 points)
      score += GetVolatilityRegimeScore();

      // 4. Seasonal Bias (0 to +1 points)
      score += GetSeasonalScore();

      return score;
   }

private:
   //+------------------------------------------------------------------+
   //| Update cached values (once per bar)                             |
   //+------------------------------------------------------------------+
   void UpdateCache()
   {
      datetime currentBarTime = iTime(m_symbol, PERIOD_CURRENT, 0);
      if(m_lastUpdate == currentBarTime) return;

      m_lastUpdate = currentBarTime;
      m_dxyTrend = CalculateDXYTrend();
      m_volatilityRegime = DetectVolatilityRegime();
      m_riskSentiment = DetectRiskSentiment();
      m_monthBias = GetSeasonalBias();
   }

   //+------------------------------------------------------------------+
   //| Calculate DXY trend using major USD pairs as proxy              |
   //| Returns: -1 (falling) to +1 (rising)                            |
   //+------------------------------------------------------------------+
   double CalculateDXYTrend()
   {
      double eurusd_close[], gbpusd_close[], usdjpy_close[];
      double eurusd_ema[], gbpusd_ema[], usdjpy_ema[];

      ArraySetAsSeries(eurusd_close, true);
      ArraySetAsSeries(gbpusd_close, true);
      ArraySetAsSeries(usdjpy_close, true);

      // Get recent close prices
      if(CopyClose(BrokerSymbol("EURUSD"), PERIOD_CURRENT, 0, 10, eurusd_close) <= 0) return 0;
      if(CopyClose(BrokerSymbol("GBPUSD"), PERIOD_CURRENT, 0, 10, gbpusd_close) <= 0) return 0;
      if(CopyClose(BrokerSymbol("USDJPY"), PERIOD_CURRENT, 0, 10, usdjpy_close) <= 0) return 0;

      // Calculate simple slope over 10 bars
      double eurusd_slope = (eurusd_close[0] - eurusd_close[9]) / eurusd_close[9];
      double gbpusd_slope = (gbpusd_close[0] - gbpusd_close[9]) / gbpusd_close[9];
      double usdjpy_slope = (usdjpy_close[0] - usdjpy_close[9]) / usdjpy_close[9];

      // DXY rises when EURUSD/GBPUSD fall and USDJPY rises
      // Invert EUR/GBP slopes, keep USD/JPY slope
      double dxy_proxy = (-eurusd_slope - gbpusd_slope + usdjpy_slope) / 3.0;

      return MathMax(-1.0, MathMin(1.0, dxy_proxy * 100.0)); // Normalize to -1 to +1
   }

   //+------------------------------------------------------------------+
   //| Detect volatility regime                                        |
   //| Returns: 0=low, 1=normal, 2=high, 3=spike                       |
   //+------------------------------------------------------------------+
   int DetectVolatilityRegime()
   {
      double atr[];
      ArraySetAsSeries(atr, true);

      if(CopyBuffer(m_hATR_Gold, 0, 0, 20, atr) <= 0) return 1; // Default: normal

      m_goldATR = atr[0];

      // Calculate 20-period average ATR
      double sum = 0;
      for(int i = 0; i < 20; i++)
         sum += atr[i];
      m_avgGoldATR = sum / 20.0;

      // Classify regime
      double ratio = m_goldATR / m_avgGoldATR;

      if(ratio > 2.0) return 3;      // Spike/chaos (avoid)
      else if(ratio > 1.5) return 2; // High volatility
      else if(ratio < 0.7) return 0; // Low volatility grind
      else return 1;                  // Normal expansion
   }

   //+------------------------------------------------------------------+
   //| Detect risk sentiment (risk-on vs risk-off)                     |
   //| Returns: 0=risk-off, 1=neutral, 2=risk-on                       |
   //+------------------------------------------------------------------+
   int DetectRiskSentiment()
   {
      double eurusd_atr[], gbpusd_atr[];
      ArraySetAsSeries(eurusd_atr, true);
      ArraySetAsSeries(gbpusd_atr, true);

      if(CopyBuffer(m_hATR_EURUSD, 0, 0, 5, eurusd_atr) <= 0) return 1;
      if(CopyBuffer(m_hATR_GBPUSD, 0, 0, 5, gbpusd_atr) <= 0) return 1;

      // Risk-off: ATR spikes in forex pairs (fear/flight to safety)
      double eurusd_spike = eurusd_atr[0] / eurusd_atr[4];
      double gbpusd_spike = gbpusd_atr[0] / gbpusd_atr[4];

      double avg_spike = (eurusd_spike + gbpusd_spike) / 2.0;

      if(avg_spike > 1.3) return 0;      // Risk-off (ATR spiking)
      else if(avg_spike < 0.8) return 2; // Risk-on (ATR contracting)
      else return 1;                      // Neutral
   }

   //+------------------------------------------------------------------+
   //| Get seasonal bias for current month                             |
   //| Returns: -1 (weak), 0 (neutral), +1 (strong)                    |
   //+------------------------------------------------------------------+
   int GetSeasonalBias()
   {
      MqlDateTime dt;
      TimeCurrent(dt);

      // Gold seasonality (historical patterns):
      // Strong months: Jan, Mar, Sep, Oct, Nov
      // Weak months: May, Jun, Jul

      switch(dt.mon)
      {
         case 1:  return 1;  // January - strong
         case 3:  return 1;  // March - strong
         case 5:  return -1; // May - weak
         case 6:  return -1; // June - weak
         case 7:  return -1; // July - weak
         case 9:  return 1;  // September - strong
         case 10: return 1;  // October - strong
         case 11: return 1;  // November - strong
         default: return 0;  // Neutral
      }
   }

   //+------------------------------------------------------------------+
   //| DXY Correlation Score                                           |
   //| Gold typically inverse to DXY                                   |
   //| Returns: -2 to +2 points                                        |
   //+------------------------------------------------------------------+
   double GetDXYCorrelationScore(int direction)
   {
      // BUY gold when DXY falling (negative trend)
      // SELL gold when DXY rising (positive trend)

      if(direction == 1) // BUY signal
      {
         if(m_dxyTrend < -0.3) return 2.0;      // Strong DXY fall: +2
         else if(m_dxyTrend < 0) return 1.0;    // Weak DXY fall: +1
         else if(m_dxyTrend > 0.3) return -2.0; // Strong DXY rise: -2 (penalty)
         else return -0.5;                       // Weak DXY rise: -0.5
      }
      else // SELL signal
      {
         if(m_dxyTrend > 0.3) return 2.0;       // Strong DXY rise: +2
         else if(m_dxyTrend > 0) return 1.0;    // Weak DXY rise: +1
         else if(m_dxyTrend < -0.3) return -2.0; // Strong DXY fall: -2 (penalty)
         else return -0.5;                       // Weak DXY fall: -0.5
      }
   }

   //+------------------------------------------------------------------+
   //| Safe-Haven Flow Score                                           |
   //| Gold rallies in risk-off environments                           |
   //| Returns: -1 to +2 points                                        |
   //+------------------------------------------------------------------+
   double GetSafeHavenScore(int direction)
   {
      if(direction == 1) // BUY signal
      {
         if(m_riskSentiment == 0) return 2.0;      // Risk-off: +2
         else if(m_riskSentiment == 1) return 0;   // Neutral: 0
         else return -1.0;                          // Risk-on: -1 (penalty)
      }
      else // SELL signal
      {
         if(m_riskSentiment == 2) return 1.0;      // Risk-on (gold weakens): +1
         else if(m_riskSentiment == 1) return 0;   // Neutral: 0
         else return -1.0;                          // Risk-off (gold strengthens): -1
      }
   }

   //+------------------------------------------------------------------+
   //| Volatility Regime Score                                         |
   //| Avoid spikes, favor normal expansion                            |
   //| Returns: -2 to +1 points                                        |
   //+------------------------------------------------------------------+
   double GetVolatilityRegimeScore()
   {
      switch(m_volatilityRegime)
      {
         case 0: return 0;    // Low volatility grind: neutral
         case 1: return 1.0;  // Normal expansion: favorable (+1)
         case 2: return 0;    // High volatility: neutral (caution)
         case 3: return -2.0; // Spike/chaos: penalty (avoid whipsaws)
         default: return 0;
      }
   }

   //+------------------------------------------------------------------+
   //| Seasonal Score                                                   |
   //| Slight boost during historically strong months                  |
   //| Returns: 0 to +1 points                                         |
   //+------------------------------------------------------------------+
   double GetSeasonalScore()
   {
      if(m_monthBias == 1) return 1.0;      // Strong month: +1
      else if(m_monthBias == -1) return 0;  // Weak month: 0 (neutral, no penalty)
      else return 0;                         // Neutral month: 0
   }
};

#endif
