//+------------------------------------------------------------------+
//|                                         WyckoffAnalysis.mqh      |
//|                    Wyckoff Method Phase Detection Module          |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Wyckoff Phases                                                   |
//+------------------------------------------------------------------+
enum ENUM_WYCKOFF_PHASE
{
   WYCKOFF_UNKNOWN = 0,        // Unable to determine
   WYCKOFF_ACCUMULATION = 1,   // Sideways at lows (prepare for markup)
   WYCKOFF_MARKUP = 2,         // Strong uptrend
   WYCKOFF_DISTRIBUTION = 3,   // Sideways at highs (prepare for markdown)
   WYCKOFF_MARKDOWN = 4        // Strong downtrend
};

//+------------------------------------------------------------------+
//| Wyckoff Analysis Class                                           |
//+------------------------------------------------------------------+
class CWyckoffAnalysis
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_lookback;

   ENUM_WYCKOFF_PHASE m_currentPhase;

   // Volume Spread Analysis parameters
   double            m_avgVolume;
   double            m_avgSpread;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CWyckoffAnalysis()
   {
      m_lookback = 50;
      m_currentPhase = WYCKOFF_UNKNOWN;
      m_avgVolume = 0;
      m_avgSpread = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 50)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_lookback = lookback;
   }

   //+------------------------------------------------------------------+
   //| Detect Wyckoff Phase                                            |
   //+------------------------------------------------------------------+
   ENUM_WYCKOFF_PHASE DetectPhase()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookback, rates);
      if(copied < m_lookback) return WYCKOFF_UNKNOWN;

      // Need minimum 50 bars for Wyckoff analysis
      if(copied < 50) return WYCKOFF_UNKNOWN;

      // Calculate Volume Spread Analysis (VSA)
      CalculateVSA(rates);

      // Find recent price action characteristics
      int recentMaxIdx = ArrayMaximum(rates, 0, 20);
      int recentMinIdx = ArrayMinimum(rates, 0, 20);
      int olderMaxIdx = ArrayMaximum(rates, 20, 30);
      int olderMinIdx = ArrayMinimum(rates, 20, 30);

      if(recentMaxIdx < 0 || recentMinIdx < 0 || olderMaxIdx < 0 || olderMinIdx < 0)
         return WYCKOFF_UNKNOWN;

      double recentHigh = rates[recentMaxIdx].high;
      double recentLow = rates[recentMinIdx].low;
      double recentRange = recentHigh - recentLow;

      double olderHigh = rates[olderMaxIdx].high;
      double olderLow = rates[olderMinIdx].low;
      double olderRange = olderHigh - olderLow;

      // Current price position
      double currentPrice = rates[0].close;
      double midPoint = (recentHigh + recentLow) / 2;

      // Calculate trend strength
      double trendStrength = CalculateTrendStrength(rates);

      // Phase 1: ACCUMULATION
      // - Sideways at lows
      // - Decreasing volume
      // - Narrow spreads
      bool isAtLows = currentPrice < (recentLow + recentRange * 0.3);
      bool isSideways = recentRange < m_avgSpread * 1.5;
      bool lowVolume = rates[0].tick_volume < m_avgVolume * 0.8;

      if(isAtLows && isSideways && lowVolume)
      {
         m_currentPhase = WYCKOFF_ACCUMULATION;
         return WYCKOFF_ACCUMULATION;
      }

      // Phase 2: MARKUP
      // - Strong uptrend
      // - Increasing volume
      // - Wide spreads on up bars
      bool strongUptrend = trendStrength > 0.6;
      bool highVolume = rates[0].tick_volume > m_avgVolume * 1.2;
      bool wideSpread = (rates[0].high - rates[0].low) > m_avgSpread * 1.3;
      bool bullish = rates[0].close > rates[0].open;

      if(strongUptrend && highVolume && wideSpread && bullish)
      {
         m_currentPhase = WYCKOFF_MARKUP;
         return WYCKOFF_MARKUP;
      }

      // Phase 3: DISTRIBUTION
      // - Sideways at highs
      // - High volume but no progress
      // - Narrow spreads
      bool isAtHighs = currentPrice > (recentHigh - recentRange * 0.3);
      bool highVolButNoProgress = highVolume && isSideways;

      if(isAtHighs && highVolButNoProgress)
      {
         m_currentPhase = WYCKOFF_DISTRIBUTION;
         return WYCKOFF_DISTRIBUTION;
      }

      // Phase 4: MARKDOWN
      // - Strong downtrend
      // - Increasing volume
      // - Wide spreads on down bars
      bool strongDowntrend = trendStrength < -0.6;
      bool bearish = rates[0].close < rates[0].open;

      if(strongDowntrend && highVolume && wideSpread && bearish)
      {
         m_currentPhase = WYCKOFF_MARKDOWN;
         return WYCKOFF_MARKDOWN;
      }

      m_currentPhase = WYCKOFF_UNKNOWN;
      return WYCKOFF_UNKNOWN;
   }

   //+------------------------------------------------------------------+
   //| Calculate Volume Spread Analysis                                |
   //+------------------------------------------------------------------+
   void CalculateVSA(MqlRates &rates[])
   {
      double totalVolume = 0;
      double totalSpread = 0;

      for(int i = 0; i < MathMin(30, ArraySize(rates)); i++)
      {
         totalVolume += (double)rates[i].tick_volume;
         totalSpread += (rates[i].high - rates[i].low);
      }

      m_avgVolume = totalVolume / 30;
      m_avgSpread = totalSpread / 30;
   }

   //+------------------------------------------------------------------+
   //| Calculate Trend Strength (-1 to +1)                             |
   //+------------------------------------------------------------------+
   double CalculateTrendStrength(MqlRates &rates[])
   {
      // Simple trend strength based on price position
      double highest = rates[ArrayMaximum(rates, 0, 30)].high;
      double lowest = rates[ArrayMinimum(rates, 0, 30)].low;
      double range = highest - lowest;

      if(range == 0) return 0;

      double currentPrice = rates[0].close;
      double pricePosition = (currentPrice - lowest) / range;

      // Convert 0-1 to -1 to +1
      return (pricePosition - 0.5) * 2;
   }

   //+------------------------------------------------------------------+
   //| Check if Breakout from Accumulation/Distribution               |
   //+------------------------------------------------------------------+
   bool IsBreakoutFromAccumulation()
   {
      if(m_currentPhase != WYCKOFF_ACCUMULATION) return false;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, 10, rates);
      if(copied < 10) return false;

      // Check for volume surge and price breakout
      double recentHigh = rates[ArrayMaximum(rates, 1, 9)].high;
      bool priceBreakout = rates[0].close > recentHigh;
      bool volumeSurge = rates[0].tick_volume > m_avgVolume * 1.5;

      return priceBreakout && volumeSurge;
   }

   //+------------------------------------------------------------------+
   //| Check if Breakdown from Distribution                            |
   //+------------------------------------------------------------------+
   bool IsBreakdownFromDistribution()
   {
      if(m_currentPhase != WYCKOFF_DISTRIBUTION) return false;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, 10, rates);
      if(copied < 10) return false;

      // Check for volume surge and price breakdown
      double recentLow = rates[ArrayMinimum(rates, 1, 9)].low;
      bool priceBreakdown = rates[0].close < recentLow;
      bool volumeSurge = rates[0].tick_volume > m_avgVolume * 1.5;

      return priceBreakdown && volumeSurge;
   }

   //+------------------------------------------------------------------+
   //| Get Wyckoff Score (0-1.5 points)                                |
   //+------------------------------------------------------------------+
   double GetWyckoffScore(int signalDir)
   {
      ENUM_WYCKOFF_PHASE phase = DetectPhase();

      // Score for trading breakouts from accumulation/distribution
      if(signalDir == 1 && phase == WYCKOFF_ACCUMULATION && IsBreakoutFromAccumulation())
         return 1.5;  // Bullish breakout from accumulation

      if(signalDir == -1 && phase == WYCKOFF_DISTRIBUTION && IsBreakdownFromDistribution())
         return 1.5;  // Bearish breakdown from distribution

      // Continuation in markup/markdown
      if(signalDir == 1 && phase == WYCKOFF_MARKUP)
         return 1.0;  // Continuation in uptrend

      if(signalDir == -1 && phase == WYCKOFF_MARKDOWN)
         return 1.0;  // Continuation in downtrend

      return 0;
   }

   //+------------------------------------------------------------------+
   //| Should Trade (Filter)                                           |
   //+------------------------------------------------------------------+
   bool ShouldTrade(int signalDir)
   {
      ENUM_WYCKOFF_PHASE phase = DetectPhase();

      // Trade breakouts from accumulation (bullish)
      if(signalDir == 1 && phase == WYCKOFF_ACCUMULATION && IsBreakoutFromAccumulation())
         return true;

      // Trade breakdowns from distribution (bearish)
      if(signalDir == -1 && phase == WYCKOFF_DISTRIBUTION && IsBreakdownFromDistribution())
         return true;

      // Trade continuations in markup/markdown
      if(signalDir == 1 && phase == WYCKOFF_MARKUP)
         return true;

      if(signalDir == -1 && phase == WYCKOFF_MARKDOWN)
         return true;

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get Phase Name                                                   |
   //+------------------------------------------------------------------+
   string GetPhaseName()
   {
      ENUM_WYCKOFF_PHASE phase = DetectPhase();

      switch(phase)
      {
         case WYCKOFF_ACCUMULATION:
            return "Accumulation (Prepare for Markup)";
         case WYCKOFF_MARKUP:
            return "Markup (Uptrend)";
         case WYCKOFF_DISTRIBUTION:
            return "Distribution (Prepare for Markdown)";
         case WYCKOFF_MARKDOWN:
            return "Markdown (Downtrend)";
         default:
            return "Unknown Phase";
      }
   }

   //+------------------------------------------------------------------+
   //| Get Wyckoff Info for Dashboard                                  |
   //+------------------------------------------------------------------+
   string GetWyckoffInfo()
   {
      string info = "=== WYCKOFF ANALYSIS ===\n";

      ENUM_WYCKOFF_PHASE phase = DetectPhase();
      info += "Phase: " + GetPhaseName() + "\n";

      if(phase == WYCKOFF_ACCUMULATION)
      {
         info += StringFormat("Avg Volume: %.0f\n", m_avgVolume);
         if(IsBreakoutFromAccumulation())
            info += "BREAKOUT DETECTED! +1.5 pts\n";
      }
      else if(phase == WYCKOFF_DISTRIBUTION)
      {
         info += StringFormat("Avg Volume: %.0f\n", m_avgVolume);
         if(IsBreakdownFromDistribution())
            info += "BREAKDOWN DETECTED! +1.5 pts\n";
      }
      else if(phase == WYCKOFF_MARKUP)
      {
         info += "Trend: UP +1.0 pt\n";
      }
      else if(phase == WYCKOFF_MARKDOWN)
      {
         info += "Trend: DOWN +1.0 pt\n";
      }

      return info;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   ENUM_WYCKOFF_PHASE GetCurrentPhase() { return m_currentPhase; }
   double GetAvgVolume() { return m_avgVolume; }
   double GetAvgSpread() { return m_avgSpread; }
};
