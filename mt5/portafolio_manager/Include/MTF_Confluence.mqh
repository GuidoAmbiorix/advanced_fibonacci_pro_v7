//+------------------------------------------------------------------+
//|                                              MTF_Confluence.mqh  |
//|          Multi-Timeframe Confluence Analysis                      |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef MTF_CONFLUENCE_MQH
#define MTF_CONFLUENCE_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| HTF BIAS                                                          |
//+------------------------------------------------------------------+
enum ENUM_HTF_BIAS
{
   BIAS_NEUTRAL = 0,
   BIAS_BULLISH = 1,
   BIAS_BEARISH = 2,
   BIAS_STRONG_BULLISH = 3,
   BIAS_STRONG_BEARISH = 4
};

//+------------------------------------------------------------------+
//| TIMEFRAME ANALYSIS STRUCTURE                                      |
//+------------------------------------------------------------------+
struct TimeframeAnalysis
{
   ENUM_TIMEFRAMES tf;
   double          emaValue;
   double          emaSlope;        // Slope direction
   bool            priceAboveEMA;
   double          rsiValue;
   bool            isTrending;      // Based on ATR expansion
   int             swingBias;       // 1 = HH/HL, -1 = LH/LL, 0 = mixed
   double          atr;
};

//+------------------------------------------------------------------+
//| MTF CONFLUENCE MODULE                                             |
//| Responsibility: HTF direction + LTF entry timing                  |
//+------------------------------------------------------------------+
class CMTFConfluence
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_htf;           // Higher Timeframe (H4/Daily)
   ENUM_TIMEFRAMES m_mtf;           // Medium Timeframe (H1)
   ENUM_TIMEFRAMES m_ltf;           // Lower Timeframe (M15/M5)

   TimeframeAnalysis m_htfAnalysis;
   TimeframeAnalysis m_mtfAnalysis;
   TimeframeAnalysis m_ltfAnalysis;

   ENUM_HTF_BIAS   m_currentBias;
   double          m_alignmentScore; // 0-100%

   // Indicator handles
   int             m_hEMA_HTF, m_hEMA_MTF, m_hEMA_LTF;
   int             m_hRSI_HTF, m_hRSI_MTF, m_hRSI_LTF;
   int             m_hATR_HTF, m_hATR_MTF, m_hATR_LTF;

   int             m_emaPeriod;
   int             m_rsiPeriod;

public:
   CMTFConfluence() : m_emaPeriod(50), m_rsiPeriod(14), m_currentBias(BIAS_NEUTRAL) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES htf = PERIOD_H4,
             ENUM_TIMEFRAMES mtf = PERIOD_H1, ENUM_TIMEFRAMES ltf = PERIOD_M15,
             int emaPeriod = 50, int rsiPeriod = 14)
   {
      m_symbol = symbol;
      m_htf = htf;
      m_mtf = mtf;
      m_ltf = ltf;
      m_emaPeriod = emaPeriod;
      m_rsiPeriod = rsiPeriod;

      // Create indicator handles for each timeframe
      m_hEMA_HTF = iMA(m_symbol, m_htf, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_hEMA_MTF = iMA(m_symbol, m_mtf, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_hEMA_LTF = iMA(m_symbol, m_ltf, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

      m_hRSI_HTF = iRSI(m_symbol, m_htf, m_rsiPeriod, PRICE_CLOSE);
      m_hRSI_MTF = iRSI(m_symbol, m_mtf, m_rsiPeriod, PRICE_CLOSE);
      m_hRSI_LTF = iRSI(m_symbol, m_ltf, m_rsiPeriod, PRICE_CLOSE);

      m_hATR_HTF = iATR(m_symbol, m_htf, 14);
      m_hATR_MTF = iATR(m_symbol, m_mtf, 14);
      m_hATR_LTF = iATR(m_symbol, m_ltf, 14);

      if(m_hEMA_HTF == INVALID_HANDLE || m_hEMA_MTF == INVALID_HANDLE ||
         m_hEMA_LTF == INVALID_HANDLE) return false;

      if(m_hRSI_HTF == INVALID_HANDLE || m_hRSI_MTF == INVALID_HANDLE ||
         m_hRSI_LTF == INVALID_HANDLE) return false;

      if(m_hATR_HTF == INVALID_HANDLE || m_hATR_MTF == INVALID_HANDLE ||
         m_hATR_LTF == INVALID_HANDLE) return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Deinitialize                                                      |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      if(m_hEMA_HTF != INVALID_HANDLE) IndicatorRelease(m_hEMA_HTF);
      if(m_hEMA_MTF != INVALID_HANDLE) IndicatorRelease(m_hEMA_MTF);
      if(m_hEMA_LTF != INVALID_HANDLE) IndicatorRelease(m_hEMA_LTF);
      if(m_hRSI_HTF != INVALID_HANDLE) IndicatorRelease(m_hRSI_HTF);
      if(m_hRSI_MTF != INVALID_HANDLE) IndicatorRelease(m_hRSI_MTF);
      if(m_hRSI_LTF != INVALID_HANDLE) IndicatorRelease(m_hRSI_LTF);
      if(m_hATR_HTF != INVALID_HANDLE) IndicatorRelease(m_hATR_HTF);
      if(m_hATR_MTF != INVALID_HANDLE) IndicatorRelease(m_hATR_MTF);
      if(m_hATR_LTF != INVALID_HANDLE) IndicatorRelease(m_hATR_LTF);
   }

   //+------------------------------------------------------------------+
   //| Update - Call on each new bar                                     |
   //+------------------------------------------------------------------+
   void Update()
   {
      // Analyze each timeframe
      AnalyzeTimeframe(m_htf, m_hEMA_HTF, m_hRSI_HTF, m_hATR_HTF, m_htfAnalysis);
      AnalyzeTimeframe(m_mtf, m_hEMA_MTF, m_hRSI_MTF, m_hATR_MTF, m_mtfAnalysis);
      AnalyzeTimeframe(m_ltf, m_hEMA_LTF, m_hRSI_LTF, m_hATR_LTF, m_ltfAnalysis);

      // Determine overall bias
      DetermineBias();

      // Calculate alignment score
      CalculateAlignmentScore();
   }

   //+------------------------------------------------------------------+
   //| Analyze single timeframe                                          |
   //+------------------------------------------------------------------+
   void AnalyzeTimeframe(ENUM_TIMEFRAMES tf, int handleEMA, int handleRSI, int handleATR,
                         TimeframeAnalysis &analysis)
   {
      analysis.tf = tf;

      // Get EMA values
      double emaBuf[2];
      if(CopyBuffer(handleEMA, 0, 1, 2, emaBuf) == 2)
      {
         analysis.emaValue = emaBuf[1];
         analysis.emaSlope = emaBuf[1] - emaBuf[0];
      }
      else
      {
         // FIX: Initialize to safe defaults if CopyBuffer fails
         analysis.emaValue = 0;
         analysis.emaSlope = 0;
      }

      // Get current price
      double currentPrice = iClose(m_symbol, tf, 0);
      analysis.priceAboveEMA = (analysis.emaValue > 0) ? (currentPrice > analysis.emaValue) : false;

      // Get RSI
      double rsiBuf[1];
      if(CopyBuffer(handleRSI, 0, 1, 1, rsiBuf) == 1)
         analysis.rsiValue = rsiBuf[0];

      // Get ATR for trend detection
      double atrBuf[1], atrMaBuf[20];
      if(CopyBuffer(handleATR, 0, 1, 1, atrBuf) == 1)
         analysis.atr = atrBuf[0];

      // Calculate ATR MA for trend detection
      // FIX: Track successful reads to avoid division by zero
      double atrSum = 0;
      int successfulReads = 0;
      for(int i = 1; i <= 20; i++)
      {
         double ab[1];
         if(CopyBuffer(handleATR, 0, i, 1, ab) == 1)
         {
            atrSum += ab[0];
            successfulReads++;
         }
      }
      // FIX: Only calculate if we have enough data, otherwise use fallback
      double atrMa = (successfulReads >= 10) ? (atrSum / successfulReads) : analysis.atr;
      analysis.isTrending = (atrMa > 0) ? (analysis.atr > atrMa * 1.1) : false;

      // Determine swing bias (HH/HL vs LH/LL)
      analysis.swingBias = CalculateSwingBias(tf);
   }

   //+------------------------------------------------------------------+
   //| Calculate swing bias for a timeframe                              |
   //+------------------------------------------------------------------+
   int CalculateSwingBias(ENUM_TIMEFRAMES tf)
   {
      // Find recent swing highs and lows
      int lookback = 20;

      double recentHighs[3], recentLows[3];
      int highCount = 0, lowCount = 0;

      for(int i = 2; i < lookback && (highCount < 3 || lowCount < 3); i++)
      {
         double high = iHigh(m_symbol, tf, i);
         double low = iLow(m_symbol, tf, i);

         bool isSwingHigh = true;
         bool isSwingLow = true;

         // Check if swing point
         for(int j = 1; j <= 2; j++)
         {
            if(i - j >= 0 && iHigh(m_symbol, tf, i - j) >= high) isSwingHigh = false;
            if(i + j < lookback && iHigh(m_symbol, tf, i + j) >= high) isSwingHigh = false;
            if(i - j >= 0 && iLow(m_symbol, tf, i - j) <= low) isSwingLow = false;
            if(i + j < lookback && iLow(m_symbol, tf, i + j) <= low) isSwingLow = false;
         }

         if(isSwingHigh && highCount < 3)
         {
            recentHighs[highCount] = high;
            highCount++;
         }
         if(isSwingLow && lowCount < 3)
         {
            recentLows[lowCount] = low;
            lowCount++;
         }
      }

      if(highCount < 2 || lowCount < 2) return 0;

      // Check pattern
      bool makingHH = recentHighs[0] > recentHighs[1];
      bool makingHL = recentLows[0] > recentLows[1];
      bool makingLL = recentLows[0] < recentLows[1];
      bool makingLH = recentHighs[0] < recentHighs[1];

      if(makingHH && makingHL) return 1;   // Bullish structure
      if(makingLL && makingLH) return -1;  // Bearish structure

      return 0;  // Mixed/unclear
   }

   //+------------------------------------------------------------------+
   //| Determine overall bias                                            |
   //+------------------------------------------------------------------+
   void DetermineBias()
   {
      int bullishPoints = 0;
      int bearishPoints = 0;

      // HTF analysis (highest weight)
      if(m_htfAnalysis.priceAboveEMA && m_htfAnalysis.emaSlope > 0)
         bullishPoints += 3;
      else if(!m_htfAnalysis.priceAboveEMA && m_htfAnalysis.emaSlope < 0)
         bearishPoints += 3;

      if(m_htfAnalysis.swingBias == 1) bullishPoints += 2;
      else if(m_htfAnalysis.swingBias == -1) bearishPoints += 2;

      // MTF analysis (medium weight)
      if(m_mtfAnalysis.priceAboveEMA && m_mtfAnalysis.emaSlope > 0)
         bullishPoints += 2;
      else if(!m_mtfAnalysis.priceAboveEMA && m_mtfAnalysis.emaSlope < 0)
         bearishPoints += 2;

      if(m_mtfAnalysis.swingBias == 1) bullishPoints += 1;
      else if(m_mtfAnalysis.swingBias == -1) bearishPoints += 1;

      // RSI confirmation
      if(m_htfAnalysis.rsiValue > 50) bullishPoints += 1;
      else if(m_htfAnalysis.rsiValue < 50) bearishPoints += 1;

      // Determine final bias
      int diff = bullishPoints - bearishPoints;

      if(diff >= 6) m_currentBias = BIAS_STRONG_BULLISH;
      else if(diff >= 3) m_currentBias = BIAS_BULLISH;
      else if(diff <= -6) m_currentBias = BIAS_STRONG_BEARISH;
      else if(diff <= -3) m_currentBias = BIAS_BEARISH;
      else m_currentBias = BIAS_NEUTRAL;
   }

   //+------------------------------------------------------------------+
   //| Calculate alignment score (0-100)                                 |
   //+------------------------------------------------------------------+
   void CalculateAlignmentScore()
   {
      double score = 0;

      // All TFs above EMA = 30 points
      if(m_htfAnalysis.priceAboveEMA && m_mtfAnalysis.priceAboveEMA && m_ltfAnalysis.priceAboveEMA)
         score += 30;
      else if(!m_htfAnalysis.priceAboveEMA && !m_mtfAnalysis.priceAboveEMA && !m_ltfAnalysis.priceAboveEMA)
         score += 30;

      // All EMA slopes aligned = 25 points
      bool allSlopesUp = m_htfAnalysis.emaSlope > 0 && m_mtfAnalysis.emaSlope > 0 && m_ltfAnalysis.emaSlope > 0;
      bool allSlopesDown = m_htfAnalysis.emaSlope < 0 && m_mtfAnalysis.emaSlope < 0 && m_ltfAnalysis.emaSlope < 0;
      if(allSlopesUp || allSlopesDown) score += 25;

      // Swing bias alignment = 25 points
      if(m_htfAnalysis.swingBias != 0 && m_htfAnalysis.swingBias == m_mtfAnalysis.swingBias)
         score += 25;

      // RSI alignment = 20 points
      bool allRsiBullish = m_htfAnalysis.rsiValue > 50 && m_mtfAnalysis.rsiValue > 50;
      bool allRsiBearish = m_htfAnalysis.rsiValue < 50 && m_mtfAnalysis.rsiValue < 50;
      if(allRsiBullish || allRsiBearish) score += 20;

      m_alignmentScore = score;
   }

   //+------------------------------------------------------------------+
   //| Check if direction aligns with HTF bias                           |
   //+------------------------------------------------------------------+
   bool IsDirectionAligned(int direction)
   {
      if(direction == 1)
         return (m_currentBias == BIAS_BULLISH || m_currentBias == BIAS_STRONG_BULLISH);
      else if(direction == -1)
         return (m_currentBias == BIAS_BEARISH || m_currentBias == BIAS_STRONG_BEARISH);

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get confluence score contribution (0-2.0)                         |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;

      // Base score for alignment
      if(IsDirectionAligned(direction))
      {
         score = 1.0;

         // Bonus for strong bias
         if((direction == 1 && m_currentBias == BIAS_STRONG_BULLISH) ||
            (direction == -1 && m_currentBias == BIAS_STRONG_BEARISH))
            score += 0.5;

         // Bonus for high alignment score
         if(m_alignmentScore >= 80) score += 0.5;
         else if(m_alignmentScore >= 60) score += 0.25;
      }
      else if(m_currentBias == BIAS_NEUTRAL)
      {
         // Neutral bias - partial score based on LTF
         if((direction == 1 && m_ltfAnalysis.priceAboveEMA && m_ltfAnalysis.emaSlope > 0) ||
            (direction == -1 && !m_ltfAnalysis.priceAboveEMA && m_ltfAnalysis.emaSlope < 0))
            score = 0.5;
      }
      else
      {
         // Trading against HTF bias - penalize
         score = -0.5;
      }

      return MathMin(MathMax(score, -0.5), 2.0);
   }

   //+------------------------------------------------------------------+
   //| Check if LTF gives entry signal in direction of HTF               |
   //+------------------------------------------------------------------+
   bool IsLTFEntrySignal(int direction)
   {
      if(!IsDirectionAligned(direction)) return false;

      // LTF should show momentum in direction
      if(direction == 1)
      {
         // Price crossing above LTF EMA with RSI momentum
         return (m_ltfAnalysis.priceAboveEMA &&
                 m_ltfAnalysis.emaSlope > 0 &&
                 m_ltfAnalysis.rsiValue > 45 && m_ltfAnalysis.rsiValue < 70);
      }
      else
      {
         return (!m_ltfAnalysis.priceAboveEMA &&
                 m_ltfAnalysis.emaSlope < 0 &&
                 m_ltfAnalysis.rsiValue < 55 && m_ltfAnalysis.rsiValue > 30);
      }
   }

   //+------------------------------------------------------------------+
   //| Check if in pullback zone on HTF                                  |
   //+------------------------------------------------------------------+
   bool IsInHTFPullback(int direction)
   {
      double currentPrice = iClose(m_symbol, m_htf, 0);
      double pullbackZone = m_htfAnalysis.atr * 1.5;

      if(direction == 1 && m_currentBias == BIAS_BULLISH)
      {
         // Price pulled back close to HTF EMA
         return (currentPrice > m_htfAnalysis.emaValue &&
                 currentPrice < m_htfAnalysis.emaValue + pullbackZone);
      }
      else if(direction == -1 && m_currentBias == BIAS_BEARISH)
      {
         return (currentPrice < m_htfAnalysis.emaValue &&
                 currentPrice > m_htfAnalysis.emaValue - pullbackZone);
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                           |
   //+------------------------------------------------------------------+
   ENUM_HTF_BIAS GetBias() { return m_currentBias; }
   double GetAlignmentScore() { return m_alignmentScore; }

   TimeframeAnalysis GetHTFAnalysis() { return m_htfAnalysis; }
   TimeframeAnalysis GetMTFAnalysis() { return m_mtfAnalysis; }
   TimeframeAnalysis GetLTFAnalysis() { return m_ltfAnalysis; }

   //+------------------------------------------------------------------+
   //| Get string representation                                         |
   //+------------------------------------------------------------------+
   string ToString()
   {
      string biasStr;
      switch(m_currentBias)
      {
         case BIAS_STRONG_BULLISH: biasStr = "STRONG BULL"; break;
         case BIAS_BULLISH: biasStr = "BULLISH"; break;
         case BIAS_STRONG_BEARISH: biasStr = "STRONG BEAR"; break;
         case BIAS_BEARISH: biasStr = "BEARISH"; break;
         default: biasStr = "NEUTRAL"; break;
      }

      return "MTF: " + biasStr + " (" + DoubleToString(m_alignmentScore, 0) + "%)";
   }
};

#endif
