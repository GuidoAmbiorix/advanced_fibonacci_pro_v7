//+------------------------------------------------------------------+
//|                                                          HMM.mqh |
//| 2-state Hidden Markov Model overlay for volatility regime        |
//| States: LOW_VOL (0) and HIGH_VOL (1)                             |
//+------------------------------------------------------------------+
#ifndef HMM_MQH
#define HMM_MQH

enum HMM_STATE { HMM_LOW_VOL = 0, HMM_HIGH_VOL = 1 };

class CHMM
{
private:
   // Transition matrix A[from][to]
   double m_A[2][2];
   // Emission matrix B[state][obs] (obs: 0=low_vol, 1=high_vol)
   double m_B[2][2];
   // Current state probabilities (forward vars)
   double m_alpha[2];

   // Soft counts for online re-estimation
   double m_emitCount[2][2];
   double m_transCount[2][2];
   int    m_updateCount;
   int    m_updateInterval;

   // Rolling vol buffer for averaging
   double m_volBuffer[50];
   int    m_volHead;
   int    m_volFilled;

   // Output
   HMM_STATE m_state;
   double    m_confidence;

   bool m_initialized;

   double _VolAverage()
   {
      if(m_volFilled == 0) return 1.0;
      double s = 0;
      for(int i = 0; i < m_volFilled; i++) s += m_volBuffer[i];
      return s / m_volFilled;
   }

   void _Reestimate()
   {
      for(int s = 0; s < 2; s++)
      {
         double total = m_emitCount[s][0] + m_emitCount[s][1] + 1e-6;
         m_B[s][0] = MathMax(0.05, MathMin(0.95, m_emitCount[s][0] / total));
         m_B[s][1] = 1.0 - m_B[s][0];
      }
   }

public:
   CHMM()
   {
      // Informative priors: vol regimes are persistent
      m_A[0][0] = 0.85; m_A[0][1] = 0.15;
      m_A[1][0] = 0.20; m_A[1][1] = 0.80;

      m_B[0][0] = 0.80; m_B[0][1] = 0.20; // LOW_VOL state: mostly low-vol obs
      m_B[1][0] = 0.25; m_B[1][1] = 0.75; // HIGH_VOL state: mostly high-vol obs

      m_alpha[0] = 0.65; m_alpha[1] = 0.35;

      ArrayInitialize(m_emitCount, 0.5); // Laplace prior
      ArrayInitialize(m_transCount, 0.5);
      ArrayInitialize(m_volBuffer, 0);

      m_updateCount    = 0;
      m_updateInterval = 20;
      m_volHead        = 0;
      m_volFilled      = 0;
      m_state          = HMM_LOW_VOL;
      m_confidence     = 0.65;
      m_initialized    = false;
   }

   void Init(int updateInterval = 20)
   {
      m_updateInterval = updateInterval;
      m_initialized    = true;
   }

   void UpdateObservation(double realizedVol)
   {
      if(!m_initialized) return;

      // Store vol in buffer
      m_volBuffer[m_volHead] = realizedVol;
      m_volHead = (m_volHead + 1) % 50;
      if(m_volFilled < 50) m_volFilled++;

      // Discretize: 1 = high vol if above rolling average
      double avgVol = _VolAverage();
      int obs = (realizedVol > avgVol * 1.2) ? 1 : 0;

      // Forward step: alpha_new[s] = B[s][obs] * sum_s'(alpha[s'] * A[s'][s])
      double newAlpha[2];
      for(int s = 0; s < 2; s++)
         newAlpha[s] = m_B[s][obs] * (m_alpha[0] * m_A[0][s] + m_alpha[1] * m_A[1][s]);

      // Normalize
      double norm = newAlpha[0] + newAlpha[1];
      if(norm > 1e-10) { newAlpha[0] /= norm; newAlpha[1] /= norm; }
      else             { newAlpha[0] = 0.5; newAlpha[1] = 0.5; }

      m_alpha[0] = newAlpha[0];
      m_alpha[1] = newAlpha[1];

      // Update state
      m_state = (m_alpha[1] > m_alpha[0]) ? HMM_HIGH_VOL : HMM_LOW_VOL;
      m_confidence = MathMax(m_alpha[0], m_alpha[1]);

      // Accumulate soft counts for re-estimation
      int prevState = (int)m_state;
      m_emitCount[prevState][obs] += 1.0;

      // Re-estimate emissions periodically
      m_updateCount++;
      if(m_updateCount >= m_updateInterval)
      {
         _Reestimate();
         m_updateCount = 0;
      }
   }

   HMM_STATE GetState()      { return m_state; }
   double    GetConfidence() { return m_confidence; }
};
#endif
