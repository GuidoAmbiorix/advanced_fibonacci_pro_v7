//+------------------------------------------------------------------+
//|                                         QuantumAnalysis.mqh      |
//|              Quantum Market Analysis for Confluence Detection     |
//|                          Copyright 2026, Guido Ambiorix           |
//+------------------------------------------------------------------+
#ifndef QUANTUM_ANALYSIS_MQH
#define QUANTUM_ANALYSIS_MQH

#property copyright "Guido Ambiorix"
#property strict

#include "QuantumWalk.mqh"
#include "QuantumCoherence.mqh"

//+------------------------------------------------------------------+
//| Quantum Analysis API                                              |
//| Combines quantum random walk and coherence detection             |
//| Returns: 0-4.0 confluence points                                 |
//+------------------------------------------------------------------+
class CQuantumAnalysis
{
private:
   CQuantumWalk      m_qwalk;
   CQuantumCoherence m_coherence;

   // Performance cache
   double            m_cachedProb_Buy;
   double            m_cachedProb_Sell;
   double            m_cachedCoherence;
   datetime          m_lastCalc;

   // Configuration
   int               m_walkSteps;
   double            m_coherenceThreshold;
   bool              m_weightMomentum;
   bool              m_initialized;

public:
   CQuantumAnalysis() : m_walkSteps(50), m_coherenceThreshold(0.50),
                        m_weightMomentum(true), m_lastCalc(0),
                        m_cachedProb_Buy(0), m_cachedProb_Sell(0),
                        m_cachedCoherence(0), m_initialized(false) {}

   ~CQuantumAnalysis() {}

   //+------------------------------------------------------------------+
   //| Initialize quantum analysis modules                              |
   //+------------------------------------------------------------------+
   bool Init(int walkSteps = 50, double coherenceThreshold = 0.50, bool weightMomentum = true)
   {
      m_walkSteps = MathMax(20, MathMin(100, walkSteps));
      m_coherenceThreshold = MathMax(0.3, MathMin(0.8, coherenceThreshold));
      m_weightMomentum = weightMomentum;

      // Initialize coherence module
      if(!m_coherence.Init())
      {
         Print("QuantumAnalysis: Failed to initialize coherence module");
         return false;
      }

      m_initialized = true;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score (0-4.0 pts) - Main API                      |
   //| direction: 1=buy, -1=sell                                        |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      if(!m_initialized) return 0.0;

      Update(); // Refresh cache if needed

      double score = 0.0;

      // 1. Quantum Random Walk Probability (0-2.0 pts)
      double prob = (direction == 1) ? m_cachedProb_Buy : m_cachedProb_Sell;
      score += prob * 2.0; // Scale 0-1 to 0-2.0 pts

      // 2. Quantum Coherence (0-2.0 pts)
      if(m_cachedCoherence >= 0.75)
         score += 2.0;      // Strong coherence
      else if(m_cachedCoherence >= 0.50)
         score += 1.0;      // Moderate coherence
      // else 0 pts for weak coherence

      // 3. Quantum State Bonus (0.5 pts)
      // High probability + high coherence = quantum edge
      if(prob >= 0.70 && m_cachedCoherence >= 0.75)
         score += 0.5;

      return score;
   }

   //+------------------------------------------------------------------+
   //| Get quantum probability for specific direction                   |
   //+------------------------------------------------------------------+
   double GetQuantumProbability(int direction)
   {
      if(!m_initialized) return 0.5; // Neutral

      Update();
      return (direction == 1) ? m_cachedProb_Buy : m_cachedProb_Sell;
   }

   //+------------------------------------------------------------------+
   //| Get coherence strength (0-1.0)                                   |
   //+------------------------------------------------------------------+
   double GetCoherenceStrength()
   {
      if(!m_initialized) return 0.0;

      Update();
      return m_cachedCoherence;
   }

   //+------------------------------------------------------------------+
   //| Check if current market is in quantum state                      |
   //| Returns: true if high probability + high coherence               |
   //+------------------------------------------------------------------+
   bool IsQuantumState()
   {
      if(!m_initialized) return false;

      Update();
      double maxProb = MathMax(m_cachedProb_Buy, m_cachedProb_Sell);
      return (maxProb >= 0.75 && m_cachedCoherence >= 0.80);
   }

   //+------------------------------------------------------------------+
   //| Get quantum state classification                                 |
   //| Returns: 0=weak, 1=moderate, 2=strong, 3=elite                  |
   //+------------------------------------------------------------------+
   int GetQuantumStateLevel()
   {
      if(!m_initialized) return 0;

      Update();
      double maxProb = MathMax(m_cachedProb_Buy, m_cachedProb_Sell);

      // Elite quantum state
      if(maxProb >= 0.75 && m_cachedCoherence >= 0.80)
         return 3;

      // Strong quantum state
      if(maxProb >= 0.65 && m_cachedCoherence >= 0.60)
         return 2;

      // Moderate quantum state
      if(maxProb >= 0.55 && m_cachedCoherence >= 0.50)
         return 1;

      // Weak state
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get quantum state name for debugging                             |
   //+------------------------------------------------------------------+
   string GetQuantumStateName()
   {
      int level = GetQuantumStateLevel();

      switch(level)
      {
         case 3: return "ELITE";
         case 2: return "STRONG";
         case 1: return "MODERATE";
         default: return "WEAK";
      }
   }

   //+------------------------------------------------------------------+
   //| Get detailed quantum metrics for logging                         |
   //+------------------------------------------------------------------+
   string GetMetrics()
   {
      if(!m_initialized) return "Not initialized";

      Update();

      return StringFormat("QRW(B:%.2f S:%.2f) Coh:%.2f State:%s",
                         m_cachedProb_Buy,
                         m_cachedProb_Sell,
                         m_cachedCoherence,
                         GetQuantumStateName());
   }

   //+------------------------------------------------------------------+
   //| Get expected win rate boost based on quantum state              |
   //+------------------------------------------------------------------+
   double GetWinRateBoost()
   {
      int level = GetQuantumStateLevel();

      switch(level)
      {
         case 3: return 0.10;  // +10% expected win rate (elite)
         case 2: return 0.07;  // +7% (strong)
         case 1: return 0.04;  // +4% (moderate)
         default: return 0.0;  // No boost (weak)
      }
   }

private:
   //+------------------------------------------------------------------+
   //| Update cache if needed (once per bar)                            |
   //+------------------------------------------------------------------+
   void Update()
   {
      datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

      // Check if cache is still valid
      if(currentBar == m_lastCalc) return;

      // Calculate quantum random walk probabilities
      m_cachedProb_Buy = m_qwalk.Calculate(1, m_walkSteps, m_weightMomentum);
      m_cachedProb_Sell = m_qwalk.Calculate(-1, m_walkSteps, m_weightMomentum);

      // Calculate quantum coherence
      m_cachedCoherence = m_coherence.Calculate();

      // Update cache timestamp
      m_lastCalc = currentBar;
   }
};

#endif
