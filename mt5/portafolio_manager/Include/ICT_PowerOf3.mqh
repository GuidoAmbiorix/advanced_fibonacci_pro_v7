//+------------------------------------------------------------------+
//|                                         ICT_PowerOf3.mqh         |
//|                    ICT Power of 3 Phase Detection                 |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Power of 3 Phases                                                |
//+------------------------------------------------------------------+
enum ENUM_PO3_PHASE
{
   PO3_UNKNOWN = 0,         // Unable to determine
   PO3_ACCUMULATION = 1,    // Sideways at lows (compression)
   PO3_MANIPULATION = 2,    // False move (liquidity grab)
   PO3_DISTRIBUTION = 3     // True move (expansion) - TRADE THIS
};

//+------------------------------------------------------------------+
//| ICT Power of 3 Class                                             |
//+------------------------------------------------------------------+
class CICTPowerOf3
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_lookback;

   ENUM_PO3_PHASE    m_currentPhase;
   int               m_phaseStartBar;

   // Phase detection parameters
   double            m_accumulationRange;   // Range threshold for accumulation
   double            m_manipulationRange;   // Range for manipulation
   int               m_minAccBars;          // Minimum bars for accumulation

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CICTPowerOf3()
   {
      m_lookback = 30;
      m_currentPhase = PO3_UNKNOWN;
      m_phaseStartBar = 0;
      m_minAccBars = 5;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 30)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_lookback = lookback;
   }

   //+------------------------------------------------------------------+
   //| Detect Current Power of 3 Phase                                 |
   //+------------------------------------------------------------------+
   ENUM_PO3_PHASE DetectPhase()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookback, rates);
      if(copied < m_lookback) return PO3_UNKNOWN;

      // Need minimum 20 bars for phase detection
      if(copied < 20) return PO3_UNKNOWN;

      double atr = GetATR();
      if(atr == 0) return PO3_UNKNOWN;

      // Calculate recent range and volume
      int maxIdx = ArrayMaximum(rates, 0, 10);
      int minIdx = ArrayMinimum(rates, 0, 10);

      if(maxIdx < 0 || minIdx < 0 || maxIdx >= copied || minIdx >= copied)
         return PO3_UNKNOWN;

      double recentHigh = rates[maxIdx].high;
      double recentLow = rates[minIdx].low;
      double recentRange = recentHigh - recentLow;

      // Calculate volume average
      double avgVolume = 0;
      for(int i = 0; i < 10; i++)
         avgVolume += (double)rates[i].tick_volume;
      avgVolume /= 10;

      double olderVolume = 0;
      for(int i = 10; i < 20; i++)
         olderVolume += (double)rates[i].tick_volume;
      olderVolume /= 10;

      // Phase 1: ACCUMULATION
      // - Tight range (< 1.5 ATR over 10 bars)
      // - Consolidation after decline
      // - Decreasing volume
      bool isAccumulation = (recentRange < atr * 1.5) &&
                           (avgVolume < olderVolume * 1.2);

      if(isAccumulation)
      {
         m_currentPhase = PO3_ACCUMULATION;
         return PO3_ACCUMULATION;
      }

      // Phase 2: MANIPULATION
      // - False breakout
      // - Quick reversal (liquidity grab)
      // - Wicks rejecting levels
      bool hasRecentReversal = false;

      for(int i = 1; i < 5; i++)
      {
         // Check for strong reversal candle
         double bodySize = MathAbs(rates[i].close - rates[i].open);
         double upperWick = rates[i].high - MathMax(rates[i].open, rates[i].close);
         double lowerWick = MathMin(rates[i].open, rates[i].close) - rates[i].low;

         // Manipulation: Large wick rejection (wick > 2x body)
         if(upperWick > bodySize * 2 || lowerWick > bodySize * 2)
         {
            hasRecentReversal = true;
            break;
         }
      }

      bool isManipulation = hasRecentReversal && (recentRange > atr * 1.0);

      if(isManipulation)
      {
         m_currentPhase = PO3_MANIPULATION;
         return PO3_MANIPULATION;
      }

      // Phase 3: DISTRIBUTION
      // - Strong directional move
      // - Expansion (> 2.0 ATR range)
      // - Increasing volume
      bool isDistribution = (recentRange > atr * 2.0) &&
                           (avgVolume > olderVolume * 1.3);

      if(isDistribution)
      {
         m_currentPhase = PO3_DISTRIBUTION;
         return PO3_DISTRIBUTION;
      }

      m_currentPhase = PO3_UNKNOWN;
      return PO3_UNKNOWN;
   }

   //+------------------------------------------------------------------+
   //| Get Phase Score (0-2.0 points)                                  |
   //+------------------------------------------------------------------+
   double GetPhaseScore()
   {
      ENUM_PO3_PHASE phase = DetectPhase();

      // Only trade Distribution phase
      if(phase == PO3_DISTRIBUTION)
         return 2.0;  // Strong score for trading the expansion

      // Filter out Manipulation (false moves)
      if(phase == PO3_MANIPULATION)
         return -1.0; // Negative score to discourage trading

      // Neutral for Accumulation and Unknown
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Should Trade (only in Distribution)                             |
   //+------------------------------------------------------------------+
   bool ShouldTrade()
   {
      return (DetectPhase() == PO3_DISTRIBUTION);
   }

   //+------------------------------------------------------------------+
   //| Is In Manipulation (avoid trading)                              |
   //+------------------------------------------------------------------+
   bool IsInManipulation()
   {
      return (DetectPhase() == PO3_MANIPULATION);
   }

   //+------------------------------------------------------------------+
   //| Get Phase Name                                                   |
   //+------------------------------------------------------------------+
   string GetPhaseName()
   {
      ENUM_PO3_PHASE phase = DetectPhase();

      switch(phase)
      {
         case PO3_ACCUMULATION:
            return "Accumulation (Consolidation)";

         case PO3_MANIPULATION:
            return "Manipulation (Liquidity Grab)";

         case PO3_DISTRIBUTION:
            return "Distribution (Expansion) - TRADE";

         case PO3_UNKNOWN:
         default:
            return "Unknown Phase";
      }
   }

   //+------------------------------------------------------------------+
   //| Get ATR Helper                                                   |
   //+------------------------------------------------------------------+
   double GetATR()
   {
      double atr[];
      ArraySetAsSeries(atr, true);

      int handle = iATR(m_symbol, m_timeframe, 14);
      if(handle == INVALID_HANDLE) return 0;

      if(CopyBuffer(handle, 0, 0, 1, atr) <= 0)
      {
         IndicatorRelease(handle);
         return 0;
      }

      IndicatorRelease(handle);
      return atr[0];
   }

   //+------------------------------------------------------------------+
   //| Get Phase Direction (for Distribution phase)                    |
   //+------------------------------------------------------------------+
   int GetPhaseDirection()
   {
      if(DetectPhase() != PO3_DISTRIBUTION)
         return 0; // No clear direction

      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, m_timeframe, 0, 10, rates);
      if(copied < 10) return 0;

      // Check overall direction in recent bars
      double startPrice = rates[9].close;
      double endPrice = rates[0].close;

      if(endPrice > startPrice)
         return 1;  // Bullish distribution
      else if(endPrice < startPrice)
         return -1; // Bearish distribution

      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get Power of 3 Info for Dashboard                               |
   //+------------------------------------------------------------------+
   string GetPowerOf3Info()
   {
      string info = "=== POWER OF 3 ===\n";

      ENUM_PO3_PHASE phase = DetectPhase();
      info += "Phase: " + GetPhaseName() + "\n";

      double score = GetPhaseScore();
      if(score > 0)
         info += StringFormat("Score: +%.1f points\n", score);
      else if(score < 0)
         info += "AVOID TRADING (Manipulation)\n";

      if(phase == PO3_DISTRIBUTION)
      {
         int dir = GetPhaseDirection();
         string dirStr = (dir == 1) ? "BULLISH" : (dir == -1) ? "BEARISH" : "NEUTRAL";
         info += "Direction: " + dirStr + "\n";
      }

      return info;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   ENUM_PO3_PHASE GetCurrentPhase() { return m_currentPhase; }
};
