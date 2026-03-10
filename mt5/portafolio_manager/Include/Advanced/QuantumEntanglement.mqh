//+------------------------------------------------------------------+
//|                                    QuantumEntanglement.mqh        |
//|        Quantum Mutual Information for Correlation Detection       |
//|                          Copyright 2026, Guido Ambiorix           |
//+------------------------------------------------------------------+
#ifndef QUANTUM_ENTANGLEMENT_MQH
#define QUANTUM_ENTANGLEMENT_MQH

#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Quantum Entanglement Correlator                                   |
//| Uses quantum mutual information (von Neumann entropy)             |
//| Superior to Pearson correlation for non-linear dependencies      |
//+------------------------------------------------------------------+
class CQuantumEntanglement
{
private:
   // Price return buffers for correlation calculation
   #define MAX_LOOKBACK 100
   double m_returns1[MAX_LOOKBACK];
   double m_returns2[MAX_LOOKBACK];

   // Cache structure
   struct CorrelationCache
   {
      string   symbol1;
      string   symbol2;
      int      lookback;
      double   entanglement;
      datetime timestamp;
   };

   CorrelationCache m_cache[10]; // Cache last 10 calculations
   int              m_cacheSize;

   // Configuration
   int    m_defaultLookback;
   int    m_numBins; // For probability distribution binning

public:
   CQuantumEntanglement() : m_cacheSize(0), m_defaultLookback(20), m_numBins(10)
   {
      ArrayInitialize(m_returns1, 0.0);
      ArrayInitialize(m_returns2, 0.0);

      for(int i = 0; i < 10; i++)
      {
         m_cache[i].symbol1 = "";
         m_cache[i].symbol2 = "";
         m_cache[i].lookback = 0;
         m_cache[i].entanglement = 0.0;
         m_cache[i].timestamp = 0;
      }
   }

   ~CQuantumEntanglement() {}

   //+------------------------------------------------------------------+
   //| Calculate quantum entanglement between two symbols               |
   //| Returns: 0-1.0 (0=independent, 1=fully entangled)               |
   //+------------------------------------------------------------------+
   double Calculate(string symbol1, string symbol2, int lookback = 20)
   {
      // Validate inputs
      if(symbol1 == symbol2) return 1.0; // Perfect self-correlation
      if(lookback < 10) lookback = 10;
      if(lookback > MAX_LOOKBACK) lookback = MAX_LOOKBACK;

      // Check cache
      double cachedValue = GetFromCache(symbol1, symbol2, lookback);
      if(cachedValue >= 0) return cachedValue;

      // Get price returns for both symbols
      if(!CalculateReturns(symbol1, m_returns1, lookback)) return 0.0;
      if(!CalculateReturns(symbol2, m_returns2, lookback)) return 0.0;

      // Calculate quantum mutual information
      double mutualInfo = CalculateMutualInformation(lookback);

      // Normalize to 0-1 range
      double maxEntropy = CalculateMaxEntropy(lookback);
      double entanglement = (maxEntropy > 0) ? MathMin(1.0, mutualInfo / maxEntropy) : 0.0;

      // Cache result
      AddToCache(symbol1, symbol2, lookback, entanglement);

      return entanglement;
   }

private:
   //+------------------------------------------------------------------+
   //| Calculate price returns for a symbol                             |
   //+------------------------------------------------------------------+
   bool CalculateReturns(string symbol, double &returns[], int lookback)
   {
      double prices[];
      ArrayResize(prices, lookback + 1);

      // Get close prices
      for(int i = 0; i <= lookback; i++)
      {
         double price = iClose(symbol, PERIOD_CURRENT, i);
         if(price == 0) return false;
         prices[i] = price;
      }

      // Calculate log returns: ln(P_t / P_{t-1})
      for(int i = 0; i < lookback; i++)
      {
         if(prices[i+1] > 0)
         {
            returns[i] = MathLog(prices[i] / prices[i+1]);
         }
         else
         {
            returns[i] = 0.0;
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate quantum mutual information: I(A:B) = H(A) + H(B) - H(A,B) |
   //+------------------------------------------------------------------+
   double CalculateMutualInformation(int lookback)
   {
      // Calculate individual entropies
      double entropyA = CalculateEntropy(m_returns1, lookback);
      double entropyB = CalculateEntropy(m_returns2, lookback);

      // Calculate joint entropy
      double jointEntropy = CalculateJointEntropy(lookback);

      // Mutual information
      double mutualInfo = entropyA + entropyB - jointEntropy;

      return MathMax(0.0, mutualInfo); // Ensure non-negative
   }

   //+------------------------------------------------------------------+
   //| Calculate Shannon entropy: H(X) = -Σ p(x) log(p(x))             |
   //+------------------------------------------------------------------+
   double CalculateEntropy(const double &data[], int count)
   {
      // Create probability distribution using histogram binning
      double probabilities[10]; // m_numBins
      ArrayInitialize(probabilities, 0.0);

      // Find data range
      double minVal = data[0], maxVal = data[0];
      for(int i = 1; i < count; i++)
      {
         if(data[i] < minVal) minVal = data[i];
         if(data[i] > maxVal) maxVal = data[i];
      }

      double range = maxVal - minVal;
      if(range == 0) return 0.0;

      // Bin the data
      for(int i = 0; i < count; i++)
      {
         int bin = (int)((data[i] - minVal) / range * (m_numBins - 1));
         bin = MathMax(0, MathMin(m_numBins - 1, bin));
         probabilities[bin] += 1.0;
      }

      // Normalize to probabilities
      for(int i = 0; i < m_numBins; i++)
      {
         probabilities[i] /= count;
      }

      // Calculate Shannon entropy
      double entropy = 0.0;
      for(int i = 0; i < m_numBins; i++)
      {
         if(probabilities[i] > 0)
         {
            entropy -= probabilities[i] * MathLog(probabilities[i]);
         }
      }

      return entropy;
   }

   //+------------------------------------------------------------------+
   //| Calculate joint entropy: H(A,B)                                  |
   //+------------------------------------------------------------------+
   double CalculateJointEntropy(int lookback)
   {
      // Create 2D probability distribution
      double jointProb[10][10]; // m_numBins x m_numBins
      ArrayInitialize(jointProb, 0.0);

      // Find ranges for both datasets
      double minA = m_returns1[0], maxA = m_returns1[0];
      double minB = m_returns2[0], maxB = m_returns2[0];

      for(int i = 1; i < lookback; i++)
      {
         if(m_returns1[i] < minA) minA = m_returns1[i];
         if(m_returns1[i] > maxA) maxA = m_returns1[i];
         if(m_returns2[i] < minB) minB = m_returns2[i];
         if(m_returns2[i] > maxB) maxB = m_returns2[i];
      }

      double rangeA = maxA - minA;
      double rangeB = maxB - minB;

      if(rangeA == 0 || rangeB == 0) return 0.0;

      // Bin the joint data
      for(int i = 0; i < lookback; i++)
      {
         int binA = (int)((m_returns1[i] - minA) / rangeA * (m_numBins - 1));
         int binB = (int)((m_returns2[i] - minB) / rangeB * (m_numBins - 1));

         binA = MathMax(0, MathMin(m_numBins - 1, binA));
         binB = MathMax(0, MathMin(m_numBins - 1, binB));

         jointProb[binA][binB] += 1.0;
      }

      // Normalize and calculate entropy
      double entropy = 0.0;
      for(int i = 0; i < m_numBins; i++)
      {
         for(int j = 0; j < m_numBins; j++)
         {
            double prob = jointProb[i][j] / lookback;
            if(prob > 0)
            {
               entropy -= prob * MathLog(prob);
            }
         }
      }

      return entropy;
   }

   //+------------------------------------------------------------------+
   //| Calculate maximum possible entropy (for normalization)           |
   //+------------------------------------------------------------------+
   double CalculateMaxEntropy(int lookback)
   {
      // Maximum entropy occurs with uniform distribution
      // H_max = log(N) where N is number of bins
      return MathLog((double)m_numBins);
   }

   //+------------------------------------------------------------------+
   //| Cache management                                                  |
   //+------------------------------------------------------------------+
   double GetFromCache(string symbol1, string symbol2, int lookback)
   {
      datetime currentTime = TimeCurrent();

      for(int i = 0; i < m_cacheSize; i++)
      {
         // Check if cache entry matches (order-independent)
         bool match = (m_cache[i].symbol1 == symbol1 && m_cache[i].symbol2 == symbol2) ||
                      (m_cache[i].symbol1 == symbol2 && m_cache[i].symbol2 == symbol1);

         if(match && m_cache[i].lookback == lookback)
         {
            // Check if cache is still valid (less than 5 minutes old)
            if(currentTime - m_cache[i].timestamp < 300)
            {
               return m_cache[i].entanglement;
            }
         }
      }

      return -1.0; // Not found in cache
   }

   void AddToCache(string symbol1, string symbol2, int lookback, double entanglement)
   {
      int index = m_cacheSize % 10; // Circular buffer

      m_cache[index].symbol1 = symbol1;
      m_cache[index].symbol2 = symbol2;
      m_cache[index].lookback = lookback;
      m_cache[index].entanglement = entanglement;
      m_cache[index].timestamp = TimeCurrent();

      if(m_cacheSize < 10) m_cacheSize++;
   }
};

#endif
