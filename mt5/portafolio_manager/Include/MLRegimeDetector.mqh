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
//| ML REGIME DETECTOR (k-Means Enhanced)                            |
//| Responsibility: Predict market state using k-Means clustering   |
//+------------------------------------------------------------------+
class CMLRegimeDetector
{
private:
   double m_transMatrix[4][4];

   // k-Means Clustering Parameters
   struct ClusterCenter
   {
      double adx;
      double atrRatio;
      double volumeRatio;
      MARKET_REGIME regime;
   };

   ClusterCenter m_clusterCenters[4];
   bool          m_isTrained;
   int           m_trainingWindow;

public:
   CMLRegimeDetector()
   {
      InitModel();
      m_isTrained = false;
      m_trainingWindow = 500;
   }

   void InitModel()
   {
      // Initialize cluster centers with reasonable starting points
      // Cluster 0: Trending Up (High ADX, positive ATR ratio, high volume)
      m_clusterCenters[0].adx = 35.0;
      m_clusterCenters[0].atrRatio = 1.2;
      m_clusterCenters[0].volumeRatio = 1.3;
      m_clusterCenters[0].regime = MR_TRENDING_HIGH_VOL;

      // Cluster 1: Trending Down (High ADX, positive ATR ratio, high volume)
      m_clusterCenters[1].adx = 35.0;
      m_clusterCenters[1].atrRatio = 1.2;
      m_clusterCenters[1].volumeRatio = 1.3;
      m_clusterCenters[1].regime = MR_TRENDING_LOW_VOL;

      // Cluster 2: Ranging High Vol (Low ADX, high ATR ratio, high volume)
      m_clusterCenters[2].adx = 15.0;
      m_clusterCenters[2].atrRatio = 1.3;
      m_clusterCenters[2].volumeRatio = 1.4;
      m_clusterCenters[2].regime = MR_RANGING_HIGH_VOL;

      // Cluster 3: Ranging Low Vol (Low ADX, low ATR ratio, low volume)
      m_clusterCenters[3].adx = 15.0;
      m_clusterCenters[3].atrRatio = 0.8;
      m_clusterCenters[3].volumeRatio = 0.9;
      m_clusterCenters[3].regime = MR_RANGING_LOW_VOL;
   }

   //+------------------------------------------------------------------+
   //| Train k-Means on Historical Data                                |
   //+------------------------------------------------------------------+
   bool TrainOnHistoricalData(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      // Extract features from historical data
      double features[][3]; // [adx, atrRatio, volumeRatio]

      if(!ExtractFeatures(symbol, timeframe, features))
         return false;

      int numSamples = ArrayRange(features, 0);
      if(numSamples < 100) return false; // Need minimum data

      // k-Means iterations
      int maxIterations = 20;
      double tolerance = 0.001;

      for(int iter = 0; iter < maxIterations; iter++)
      {
         // Step 1: Assign each point to nearest cluster
         int assignments[];
         ArrayResize(assignments, numSamples);

         for(int i = 0; i < numSamples; i++)
         {
            assignments[i] = FindNearestCluster(features[i][0], features[i][1], features[i][2]);
         }

         // Step 2: Update cluster centers
         ClusterCenter newCenters[4];
         int counts[4] = {0, 0, 0, 0};

         // Initialize
         for(int k = 0; k < 4; k++)
         {
            newCenters[k].adx = 0;
            newCenters[k].atrRatio = 0;
            newCenters[k].volumeRatio = 0;
            newCenters[k].regime = m_clusterCenters[k].regime;
         }

         // Accumulate
         for(int i = 0; i < numSamples; i++)
         {
            int cluster = assignments[i];
            newCenters[cluster].adx += features[i][0];
            newCenters[cluster].atrRatio += features[i][1];
            newCenters[cluster].volumeRatio += features[i][2];
            counts[cluster]++;
         }

         // Average
         double maxChange = 0;
         for(int k = 0; k < 4; k++)
         {
            if(counts[k] > 0)
            {
               newCenters[k].adx /= counts[k];
               newCenters[k].atrRatio /= counts[k];
               newCenters[k].volumeRatio /= counts[k];

               // Calculate change
               double change = MathAbs(newCenters[k].adx - m_clusterCenters[k].adx) +
                              MathAbs(newCenters[k].atrRatio - m_clusterCenters[k].atrRatio) +
                              MathAbs(newCenters[k].volumeRatio - m_clusterCenters[k].volumeRatio);

               if(change > maxChange) maxChange = change;

               // Update centers
               m_clusterCenters[k] = newCenters[k];
            }
         }

         // Check convergence
         if(maxChange < tolerance)
            break;
      }

      m_isTrained = true;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Extract Features from Historical Data                           |
   //+------------------------------------------------------------------+
   bool ExtractFeatures(string symbol, ENUM_TIMEFRAMES timeframe, double &features[][3])
   {
      int bars = MathMin(m_trainingWindow, Bars(symbol, timeframe));
      if(bars < 100) return false;

      ArrayResize(features, bars);

      // Get ADX
      int hADX = iADX(symbol, timeframe, 14);
      double adxBuf[];
      ArraySetAsSeries(adxBuf, true);

      // Get ATR
      int hATR = iATR(symbol, timeframe, 14);
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);

      // Get Volume
      long volume[];
      ArraySetAsSeries(volume, true);

      if(hADX == INVALID_HANDLE || hATR == INVALID_HANDLE) return false;

      if(CopyBuffer(hADX, 0, 0, bars, adxBuf) < bars) return false;
      if(CopyBuffer(hATR, 0, 0, bars, atrBuf) < bars) return false;
      if(CopyTickVolume(symbol, timeframe, 0, bars, volume) < bars) return false;

      // Calculate features
      for(int i = 0; i < bars; i++)
      {
         // Feature 1: ADX (0-100)
         features[i][0] = adxBuf[i];

         // Feature 2: ATR Ratio (current / 20-bar avg)
         double avgATR = 0;
         for(int j = i; j < MathMin(i + 20, bars); j++)
            avgATR += atrBuf[j];
         avgATR /= 20;
         features[i][1] = (avgATR > 0) ? atrBuf[i] / avgATR : 1.0;

         // Feature 3: Volume Ratio (current / 20-bar avg)
         double avgVol = 0;
         for(int j = i; j < MathMin(i + 20, bars); j++)
            avgVol += (double)volume[j];  // Explicit cast to avoid warning
         avgVol /= 20;
         features[i][2] = (avgVol > 0) ? (double)volume[i] / avgVol : 1.0;
      }

      IndicatorRelease(hADX);
      IndicatorRelease(hATR);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Find Nearest Cluster                                            |
   //+------------------------------------------------------------------+
   int FindNearestCluster(double adx, double atrRatio, double volumeRatio)
   {
      double minDistance = DBL_MAX;
      int nearestCluster = 0;

      for(int k = 0; k < 4; k++)
      {
         double distance = EuclideanDistance(adx, atrRatio, volumeRatio,
                                            m_clusterCenters[k].adx,
                                            m_clusterCenters[k].atrRatio,
                                            m_clusterCenters[k].volumeRatio);

         if(distance < minDistance)
         {
            minDistance = distance;
            nearestCluster = k;
         }
      }

      return nearestCluster;
   }

   //+------------------------------------------------------------------+
   //| Calculate Euclidean Distance                                    |
   //+------------------------------------------------------------------+
   double EuclideanDistance(double x1, double y1, double z1,
                           double x2, double y2, double z2)
   {
      return MathSqrt(MathPow(x1 - x2, 2) + MathPow(y1 - y2, 2) + MathPow(z1 - z2, 2));
   }

   //+------------------------------------------------------------------+
   //| Detect Regime With k-Means                                      |
   //+------------------------------------------------------------------+
   RegimePrediction DetectRegime(string symbol)
   {
      RegimePrediction pred;

      // Extract current features
      int hADX = iADX(symbol, PERIOD_CURRENT, 14);
      int hATR = iATR(symbol, PERIOD_CURRENT, 14);

      double adxBuf[], atrBuf[];
      ArraySetAsSeries(adxBuf, true);
      ArraySetAsSeries(atrBuf, true);

      if(hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
      {
         pred.regime = MR_TRENDING_HIGH_VOL;
         pred.confidence = 0.5;
         return pred;
      }

      if(CopyBuffer(hADX, 0, 0, 20, adxBuf) < 20 || CopyBuffer(hATR, 0, 0, 20, atrBuf) < 20)
      {
         IndicatorRelease(hADX);
         IndicatorRelease(hATR);
         pred.regime = MR_TRENDING_HIGH_VOL;
         pred.confidence = 0.5;
         return pred;
      }

      // Calculate ATR ratio
      double avgATR = 0;
      for(int i = 0; i < 20; i++)
         avgATR += atrBuf[i];
      avgATR /= 20;
      double atrRatio = (avgATR > 0) ? atrBuf[0] / avgATR : 1.0;

      // Calculate Volume ratio
      long volume[];
      ArraySetAsSeries(volume, true);
      CopyTickVolume(symbol, PERIOD_CURRENT, 0, 20, volume);

      double avgVol = 0;
      for(int i = 0; i < 20; i++)
         avgVol += (double)volume[i];  // Explicit cast to avoid warning
      avgVol /= 20;
      double volumeRatio = (avgVol > 0) ? (double)volume[0] / avgVol : 1.0;

      // Find nearest cluster
      int nearestCluster = FindNearestCluster(adxBuf[0], atrRatio, volumeRatio);

      // Calculate confidence based on distance
      double distance = EuclideanDistance(adxBuf[0], atrRatio, volumeRatio,
                                         m_clusterCenters[nearestCluster].adx,
                                         m_clusterCenters[nearestCluster].atrRatio,
                                         m_clusterCenters[nearestCluster].volumeRatio);

      // Normalize confidence (inverse of distance, scaled)
      pred.confidence = 1.0 / (1.0 + distance);
      pred.regime = m_clusterCenters[nearestCluster].regime;

      IndicatorRelease(hADX);
      IndicatorRelease(hATR);

      return pred;
   }

   void Init() {} // Interface compatibility

   bool IsTrained() { return m_isTrained; }
};

#endif
