//+------------------------------------------------------------------+
//|                                             MLRegimeDetector.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef ML_REGIME_DETECTOR_MQH
#define ML_REGIME_DETECTOR_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "PortfolioGlobals.mqh"

struct RegimePrediction
{
   MARKET_REGIME regime;
   double        confidence;
   MARKET_REGIME alternative;
};

//+------------------------------------------------------------------+
//| ML REGIME DETECTOR                                                |
//| Responsibility: Predict market state using probabilistic models  |
//+------------------------------------------------------------------+
class CMLRegimeDetector
{
private:
   double m_transMatrix[4][4];
   
public:
   CMLRegimeDetector() { InitModel(); }
   
   void InitModel()
   {
      // ... same init as before ...
   }

   //+------------------------------------------------------------------+
   //| Detect Regime With Confidence                                     |
   //+------------------------------------------------------------------+
   RegimePrediction DetectRegime(string symbol)
   {
      RegimePrediction pred;
      
      // 1. Feature Extraction
      // Use MQL5 standard CopyBuffer approach
      int atrHandle = iATR(symbol, PERIOD_D1, 14);
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      double atr = 0;
      
      if(atrHandle != INVALID_HANDLE)
      {
         if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0)
            atr = atrBuf[0];
         IndicatorRelease(atrHandle); 
      }
      
      double adx = 30; // Mock ADX
      
      // Calculate Probabilities
      double pTrend = (adx > 25) ? 0.8 : 0.2;
      double pRange = (adx < 20) ? 0.8 : 0.2;
      double pVol = (atr > 0.0050) ? 0.7 : 0.1; // Placeholder threshold
      
      // Normalize
      double sum = pTrend + pRange + pVol;
      pTrend /= sum;
      pRange /= sum;
      pVol /= sum;
      
      // Find Max
      if(pTrend > pRange && pTrend > pVol)
      {
         pred.regime = REGIME_TREND;
         pred.confidence = pTrend;
         pred.alternative = (pRange > pVol) ? REGIME_RANGE : REGIME_VOLATILE;
      }
      else if(pRange > pTrend && pRange > pVol)
      {
         pred.regime = REGIME_RANGE;
         pred.confidence = pRange;
      }
      else
      {
         pred.regime = REGIME_VOLATILE;
         pred.confidence = pVol;
      }
      
      return pred;
   }
   
   void Init() {} // Interface compatibility
};

#endif
