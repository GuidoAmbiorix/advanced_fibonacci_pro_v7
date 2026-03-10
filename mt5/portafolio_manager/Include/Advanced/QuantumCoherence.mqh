//+------------------------------------------------------------------+
//|                                        QuantumCoherence.mqh      |
//|            Kuramoto Order Parameter for Indicator Alignment       |
//|                          Copyright 2026, Guido Ambiorix           |
//+------------------------------------------------------------------+
#ifndef QUANTUM_COHERENCE_MQH
#define QUANTUM_COHERENCE_MQH

#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Quantum Coherence Detector                                        |
//| Measures phase alignment across multiple technical indicators    |
//| Uses Kuramoto synchronization model                              |
//+------------------------------------------------------------------+
class CQuantumCoherence
{
private:
   // Indicator handles
   int m_rsiHandle;
   int m_emaFastHandle;
   int m_emaSlowHandle;
   int m_atrHandle;

   // Indicator buffers
   double m_rsiBuffer[10];
   double m_emaFastBuffer[10];
   double m_emaSlowBuffer[10];
   double m_atrBuffer[10];
   double m_volumeBuffer[10];

   // Performance cache
   datetime m_lastUpdate;
   double   m_cachedCoherence;
   double   m_smoothedCoherence;

   // Configuration
   int    m_rsiPeriod;
   int    m_emaFastPeriod;
   int    m_emaSlowPeriod;
   int    m_atrPeriod;
   double m_smoothingAlpha;

public:
   CQuantumCoherence() : m_lastUpdate(0), m_cachedCoherence(0), m_smoothedCoherence(0),
                         m_rsiPeriod(14), m_emaFastPeriod(8), m_emaSlowPeriod(21),
                         m_atrPeriod(14), m_smoothingAlpha(0.3)
   {
      ArrayInitialize(m_rsiBuffer, 0.0);
      ArrayInitialize(m_emaFastBuffer, 0.0);
      ArrayInitialize(m_emaSlowBuffer, 0.0);
      ArrayInitialize(m_atrBuffer, 0.0);
      ArrayInitialize(m_volumeBuffer, 0.0);

      m_rsiHandle = INVALID_HANDLE;
      m_emaFastHandle = INVALID_HANDLE;
      m_emaSlowHandle = INVALID_HANDLE;
      m_atrHandle = INVALID_HANDLE;
   }

   ~CQuantumCoherence()
   {
      ReleaseIndicators();
   }

   //+------------------------------------------------------------------+
   //| Initialize indicators                                            |
   //+------------------------------------------------------------------+
   bool Init()
   {
      // Create indicator handles
      m_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, m_rsiPeriod, PRICE_CLOSE);
      m_emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_atrHandle = iATR(_Symbol, PERIOD_CURRENT, m_atrPeriod);

      if(m_rsiHandle == INVALID_HANDLE || m_emaFastHandle == INVALID_HANDLE ||
         m_emaSlowHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
      {
         Print("QuantumCoherence: Failed to create indicators");
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate quantum coherence (0-1.0)                              |
   //| Returns Kuramoto order parameter measuring phase synchronization |
   //+------------------------------------------------------------------+
   double Calculate()
   {
      // Check cache validity
      datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(currentBar == m_lastUpdate)
      {
         return m_smoothedCoherence;
      }

      // Update indicator data
      if(!UpdateIndicatorData())
      {
         return m_smoothedCoherence; // Return last valid value
      }

      // Convert indicators to phases (0 to 2π)
      double phases[4];
      phases[0] = CalculateRSIPhase();
      phases[1] = CalculateEMAPhase();
      phases[2] = CalculateATRPhase();
      phases[3] = CalculateVolumePhase();

      // Calculate Kuramoto order parameter
      // R = |Σ e^(iθ)| / N = √[(Σcos(θ))² + (Σsin(θ))²] / N
      double sumCos = 0.0, sumSin = 0.0;
      int validPhases = 0;

      for(int i = 0; i < 4; i++)
      {
         if(phases[i] >= 0) // Valid phase
         {
            sumCos += MathCos(phases[i]);
            sumSin += MathSin(phases[i]);
            validPhases++;
         }
      }

      double coherence = 0.0;
      if(validPhases > 0)
      {
         double magnitude = MathSqrt(sumCos * sumCos + sumSin * sumSin);
         coherence = magnitude / validPhases;
      }

      // Apply exponential smoothing to reduce noise
      if(m_lastUpdate == 0) // First calculation
      {
         m_smoothedCoherence = coherence;
      }
      else
      {
         m_smoothedCoherence = m_smoothedCoherence * (1.0 - m_smoothingAlpha) +
                               coherence * m_smoothingAlpha;
      }

      // Cache results
      m_cachedCoherence = coherence;
      m_lastUpdate = currentBar;

      return m_smoothedCoherence;
   }

   //+------------------------------------------------------------------+
   //| Get individual indicator phases for debugging                    |
   //+------------------------------------------------------------------+
   void GetPhaseBreakdown(double &rsiPhase, double &emaPhase, double &atrPhase, double &volPhase)
   {
      rsiPhase = CalculateRSIPhase();
      emaPhase = CalculateEMAPhase();
      atrPhase = CalculateATRPhase();
      volPhase = CalculateVolumePhase();
   }

private:
   //+------------------------------------------------------------------+
   //| Update indicator buffers                                         |
   //+------------------------------------------------------------------+
   bool UpdateIndicatorData()
   {
      // Copy indicator data
      if(CopyBuffer(m_rsiHandle, 0, 0, 10, m_rsiBuffer) <= 0) return false;
      if(CopyBuffer(m_emaFastHandle, 0, 0, 10, m_emaFastBuffer) <= 0) return false;
      if(CopyBuffer(m_emaSlowHandle, 0, 0, 10, m_emaSlowBuffer) <= 0) return false;
      if(CopyBuffer(m_atrHandle, 0, 0, 10, m_atrBuffer) <= 0) return false;

      // Copy volume data
      long volumeData[10];
      if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, 10, volumeData) <= 0) return false;

      for(int i = 0; i < 10; i++)
      {
         m_volumeBuffer[i] = (double)volumeData[i];
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate RSI phase (0 to 2π)                                    |
   //| RSI < 30 = bearish phase, RSI > 70 = bullish phase              |
   //+------------------------------------------------------------------+
   double CalculateRSIPhase()
   {
      if(ArraySize(m_rsiBuffer) == 0) return -1.0;

      double rsi = m_rsiBuffer[0];

      // Map RSI (0-100) to phase (0-2π)
      // RSI 0 → 0°, RSI 50 → 180°, RSI 100 → 360°
      return (rsi / 100.0) * 2.0 * M_PI;
   }

   //+------------------------------------------------------------------+
   //| Calculate EMA phase based on slope                               |
   //+------------------------------------------------------------------+
   double CalculateEMAPhase()
   {
      if(ArraySize(m_emaFastBuffer) < 3 || ArraySize(m_emaSlowBuffer) < 3) return -1.0;

      // Calculate EMA slope (fast - slow)
      double currentDiff = m_emaFastBuffer[0] - m_emaSlowBuffer[0];
      double previousDiff = m_emaFastBuffer[1] - m_emaSlowBuffer[1];

      double slope = currentDiff - previousDiff;

      // Normalize slope to phase
      double priceRange = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 20, 0)) -
                          iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 20, 0));

      if(priceRange == 0) return M_PI; // Neutral phase

      double normalizedSlope = (slope / priceRange) * 10.0; // Scale factor

      // Map to phase: positive slope → 0°, neutral → 180°, negative slope → 360°
      return M_PI + MathArctan(normalizedSlope);
   }

   //+------------------------------------------------------------------+
   //| Calculate ATR phase (volatility expansion/contraction)           |
   //+------------------------------------------------------------------+
   double CalculateATRPhase()
   {
      if(ArraySize(m_atrBuffer) < 10) return -1.0;

      // Calculate ATR ratio (current / moving average)
      double currentATR = m_atrBuffer[0];
      double avgATR = 0.0;

      for(int i = 0; i < 10; i++)
      {
         avgATR += m_atrBuffer[i];
      }
      avgATR /= 10.0;

      if(avgATR == 0) return M_PI;

      double atrRatio = currentATR / avgATR;

      // Map ATR ratio to phase
      // High volatility (ratio > 1.5) → 0° (strong phase)
      // Normal volatility (ratio ~ 1.0) → 180° (neutral)
      // Low volatility (ratio < 0.5) → 360° (weak phase)

      double phase = M_PI * (2.0 - atrRatio); // Inverse relationship
      return MathMax(0, MathMin(2.0 * M_PI, phase));
   }

   //+------------------------------------------------------------------+
   //| Calculate Volume phase (relative volume)                         |
   //+------------------------------------------------------------------+
   double CalculateVolumePhase()
   {
      if(ArraySize(m_volumeBuffer) < 10) return -1.0;

      // Calculate RVOL (relative volume)
      double currentVol = m_volumeBuffer[0];
      double avgVol = 0.0;

      for(int i = 1; i < 10; i++) // Skip current bar
      {
         avgVol += m_volumeBuffer[i];
      }
      avgVol /= 9.0;

      if(avgVol == 0) return M_PI;

      double rvol = currentVol / avgVol;

      // Map RVOL to phase
      // High volume (RVOL > 2.0) → 0° (strong conviction)
      // Normal volume (RVOL ~ 1.0) → 180° (neutral)
      // Low volume (RVOL < 0.5) → 360° (low conviction)

      double phase = M_PI * (2.0 - rvol);
      return MathMax(0, MathMin(2.0 * M_PI, phase));
   }

   //+------------------------------------------------------------------+
   //| Release indicator handles                                        |
   //+------------------------------------------------------------------+
   void ReleaseIndicators()
   {
      if(m_rsiHandle != INVALID_HANDLE) IndicatorRelease(m_rsiHandle);
      if(m_emaFastHandle != INVALID_HANDLE) IndicatorRelease(m_emaFastHandle);
      if(m_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(m_emaSlowHandle);
      if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);

      m_rsiHandle = INVALID_HANDLE;
      m_emaFastHandle = INVALID_HANDLE;
      m_emaSlowHandle = INVALID_HANDLE;
      m_atrHandle = INVALID_HANDLE;
   }
};

#endif
