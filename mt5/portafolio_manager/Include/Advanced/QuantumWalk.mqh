//+------------------------------------------------------------------+
//|                                             QuantumWalk.mqh      |
//|               Quantum Random Walk for Price Probability           |
//|                          Copyright 2026, Guido Ambiorix           |
//+------------------------------------------------------------------+
#ifndef QUANTUM_WALK_MQH
#define QUANTUM_WALK_MQH

#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Quantum Random Walk Engine                                        |
//| Simulates quantum walk on price lattice using Hadamard coin      |
//+------------------------------------------------------------------+
class CQuantumWalk
{
private:
   // Amplitude grid for quantum walk simulation
   #define MAX_POSITIONS 201  // -100 to +100 positions
   #define HADAMARD_COEFF 0.7071067811865476  // 1/√2

   double m_amplitudes[MAX_POSITIONS];

   // Price data for momentum weighting
   double m_priceBuffer[100];
   int    m_priceCount;

   // Performance cache
   datetime m_lastUpdate;
   double   m_cachedBuyProb;
   double   m_cachedSellProb;
   int      m_lastSteps;

public:
   CQuantumWalk() : m_priceCount(0), m_lastUpdate(0),
                    m_cachedBuyProb(0), m_cachedSellProb(0),
                    m_lastSteps(0)
   {
      ArrayInitialize(m_amplitudes, 0.0);
      ArrayInitialize(m_priceBuffer, 0.0);
   }

   ~CQuantumWalk() {}

   //+------------------------------------------------------------------+
   //| Calculate quantum walk probability for direction                 |
   //| direction: 1=buy, -1=sell                                        |
   //| steps: number of quantum walk iterations (20-100)               |
   //| weightMomentum: bias probability by price momentum              |
   //+------------------------------------------------------------------+
   double Calculate(int direction, int steps = 50, bool weightMomentum = true)
   {
      // Validate inputs
      if(steps < 10) steps = 10;
      if(steps > 100) steps = 100;

      // Update price data
      UpdatePriceData();

      // Check cache validity
      datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(currentBar == m_lastUpdate && steps == m_lastSteps)
      {
         return (direction == 1) ? m_cachedBuyProb : m_cachedSellProb;
      }

      // Run quantum walk simulation
      SimulateQuantumWalk(steps);

      // Calculate probabilities using Born rule
      double buyProb = CalculateProbability(1);
      double sellProb = CalculateProbability(-1);

      // Apply momentum weighting if enabled
      if(weightMomentum)
      {
         double momentumBias = GetMomentumBias();

         if(momentumBias > 0) // Bullish momentum
         {
            buyProb = buyProb * 0.7 + (buyProb * momentumBias * 0.3);
            sellProb = sellProb * 0.7 + (sellProb * (1.0 - momentumBias) * 0.3);
         }
         else if(momentumBias < 0) // Bearish momentum
         {
            double absMomentum = MathAbs(momentumBias);
            sellProb = sellProb * 0.7 + (sellProb * absMomentum * 0.3);
            buyProb = buyProb * 0.7 + (buyProb * (1.0 - absMomentum) * 0.3);
         }
      }

      // Normalize probabilities
      double total = buyProb + sellProb;
      if(total > 0)
      {
         buyProb /= total;
         sellProb /= total;
      }

      // Cache results
      m_cachedBuyProb = buyProb;
      m_cachedSellProb = sellProb;
      m_lastUpdate = currentBar;
      m_lastSteps = steps;

      return (direction == 1) ? buyProb : sellProb;
   }

private:
   //+------------------------------------------------------------------+
   //| Update price buffer for momentum calculation                     |
   //+------------------------------------------------------------------+
   void UpdatePriceData()
   {
      m_priceCount = MathMin(50, Bars(_Symbol, PERIOD_CURRENT));

      for(int i = 0; i < m_priceCount; i++)
      {
         m_priceBuffer[i] = iClose(_Symbol, PERIOD_CURRENT, i);
      }
   }

   //+------------------------------------------------------------------+
   //| Simulate quantum random walk                                     |
   //+------------------------------------------------------------------+
   void SimulateQuantumWalk(int steps)
   {
      // Initialize: particle at center with amplitude = 1.0
      ArrayInitialize(m_amplitudes, 0.0);
      int centerPos = MAX_POSITIONS / 2; // Position 100
      m_amplitudes[centerPos] = 1.0;

      // Temporary amplitude array for next state
      double nextAmplitudes[MAX_POSITIONS];

      // Quantum walk evolution
      for(int step = 0; step < steps; step++)
      {
         ArrayInitialize(nextAmplitudes, 0.0);

         // Apply Hadamard coin + shift operator
         for(int pos = 1; pos < MAX_POSITIONS - 1; pos++)
         {
            if(MathAbs(m_amplitudes[pos]) < 1e-10) continue; // Skip negligible amplitudes

            double amplitude = m_amplitudes[pos];

            // Hadamard transformation: superposition of left/right
            // |0⟩ → (|0⟩ + |1⟩)/√2, |1⟩ → (|0⟩ - |1⟩)/√2
            double leftAmp = amplitude * HADAMARD_COEFF;
            double rightAmp = amplitude * HADAMARD_COEFF;

            // Quantum shift: move based on coin state
            nextAmplitudes[pos - 1] += leftAmp;  // Move left
            nextAmplitudes[pos + 1] += rightAmp; // Move right
         }

         // Update amplitude array
         ArrayCopy(m_amplitudes, nextAmplitudes);

         // Normalize to prevent amplitude overflow
         if(step % 10 == 0)
         {
            NormalizeAmplitudes();
         }
      }

      // Final normalization
      NormalizeAmplitudes();
   }

   //+------------------------------------------------------------------+
   //| Calculate probability using Born rule: P = |ψ|²                  |
   //+------------------------------------------------------------------+
   double CalculateProbability(int direction)
   {
      int centerPos = MAX_POSITIONS / 2;
      double probability = 0.0;

      if(direction == 1) // Buy probability (right side)
      {
         for(int pos = centerPos + 1; pos < MAX_POSITIONS; pos++)
         {
            probability += m_amplitudes[pos] * m_amplitudes[pos]; // |ψ|²
         }
      }
      else // Sell probability (left side)
      {
         for(int pos = 0; pos < centerPos; pos++)
         {
            probability += m_amplitudes[pos] * m_amplitudes[pos]; // |ψ|²
         }
      }

      return MathMax(0.0, MathMin(1.0, probability));
   }

   //+------------------------------------------------------------------+
   //| Normalize amplitude array (quantum state normalization)          |
   //+------------------------------------------------------------------+
   void NormalizeAmplitudes()
   {
      double sumSquared = 0.0;

      for(int i = 0; i < MAX_POSITIONS; i++)
      {
         sumSquared += m_amplitudes[i] * m_amplitudes[i];
      }

      if(sumSquared > 0)
      {
         double norm = MathSqrt(sumSquared);
         for(int i = 0; i < MAX_POSITIONS; i++)
         {
            m_amplitudes[i] /= norm;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate price momentum bias (-1 to +1)                         |
   //+------------------------------------------------------------------+
   double GetMomentumBias()
   {
      if(m_priceCount < 10) return 0.0;

      // Calculate short-term vs long-term momentum
      double shortMA = 0.0, longMA = 0.0;
      int shortPeriod = MathMin(5, m_priceCount);
      int longPeriod = MathMin(20, m_priceCount);

      for(int i = 0; i < shortPeriod; i++)
         shortMA += m_priceBuffer[i];
      shortMA /= shortPeriod;

      for(int i = 0; i < longPeriod; i++)
         longMA += m_priceBuffer[i];
      longMA /= longPeriod;

      // Momentum strength
      double currentPrice = m_priceBuffer[0];
      double priceRange = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 20, 0)) -
                          iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 20, 0));

      if(priceRange == 0) return 0.0;

      // Normalize momentum to -1...+1 range
      double momentum = (shortMA - longMA) / priceRange;
      return MathMax(-1.0, MathMin(1.0, momentum * 5.0)); // Scale factor 5.0
   }
};

#endif
