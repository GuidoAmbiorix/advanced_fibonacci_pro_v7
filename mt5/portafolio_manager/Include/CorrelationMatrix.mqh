//+------------------------------------------------------------------+
//|                                        CorrelationMatrix.mqh     |
//|                    Portfolio Correlation Analysis Module          |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Correlation Matrix Class                                         |
//+------------------------------------------------------------------+
class CCorrelationMatrix
{
private:
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_period;              // Lookback period for correlation
   double            m_correlationThreshold; // Threshold for high correlation

   struct SymbolPair
   {
      string symbol1;
      string symbol2;
      double correlation;
   };

   SymbolPair        m_correlations[];     // Correlation cache

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CCorrelationMatrix()
   {
      m_period = 50;                        // 50 bars for correlation
      m_timeframe = PERIOD_H1;
      m_correlationThreshold = 0.7;         // 70% correlation threshold
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(ENUM_TIMEFRAMES timeframe, int period = 50, double threshold = 0.7)
   {
      m_timeframe = timeframe;
      m_period = period;
      m_correlationThreshold = threshold;
   }

   //+------------------------------------------------------------------+
   //| Calculate Pearson Correlation between two symbols               |
   //+------------------------------------------------------------------+
   double CalculatePearsonCorrelation(string symbol1, string symbol2)
   {
      if(symbol1 == symbol2) return 1.0;

      // Get price data for both symbols
      double prices1[];
      double prices2[];

      ArraySetAsSeries(prices1, true);
      ArraySetAsSeries(prices2, true);

      ArrayResize(prices1, m_period);
      ArrayResize(prices2, m_period);

      // Copy close prices
      if(CopyClose(symbol1, m_timeframe, 0, m_period, prices1) < m_period)
         return 0;

      if(CopyClose(symbol2, m_timeframe, 0, m_period, prices2) < m_period)
         return 0;

      // Calculate returns (percentage change)
      double returns1[];
      double returns2[];

      ArrayResize(returns1, m_period - 1);
      ArrayResize(returns2, m_period - 1);

      for(int i = 0; i < m_period - 1; i++)
      {
         if(prices1[i + 1] != 0 && prices2[i + 1] != 0)
         {
            returns1[i] = (prices1[i] - prices1[i + 1]) / prices1[i + 1];
            returns2[i] = (prices2[i] - prices2[i + 1]) / prices2[i + 1];
         }
         else
         {
            returns1[i] = 0;
            returns2[i] = 0;
         }
      }

      // Calculate means
      double mean1 = 0, mean2 = 0;
      for(int i = 0; i < m_period - 1; i++)
      {
         mean1 += returns1[i];
         mean2 += returns2[i];
      }
      mean1 /= (m_period - 1);
      mean2 /= (m_period - 1);

      // Calculate Pearson correlation
      double numerator = 0;
      double sumSq1 = 0;
      double sumSq2 = 0;

      for(int i = 0; i < m_period - 1; i++)
      {
         double dev1 = returns1[i] - mean1;
         double dev2 = returns2[i] - mean2;

         numerator += dev1 * dev2;
         sumSq1 += dev1 * dev1;
         sumSq2 += dev2 * dev2;
      }

      double denominator = MathSqrt(sumSq1 * sumSq2);

      if(denominator == 0) return 0;

      return numerator / denominator;
   }

   //+------------------------------------------------------------------+
   //| Check if two symbols are highly correlated                      |
   //+------------------------------------------------------------------+
   bool IsHighlyCorrelated(string symbol1, string symbol2)
   {
      double correlation = CalculatePearsonCorrelation(symbol1, symbol2);
      return MathAbs(correlation) > m_correlationThreshold;
   }

   //+------------------------------------------------------------------+
   //| Get correlation coefficient                                      |
   //+------------------------------------------------------------------+
   double GetCorrelation(string symbol1, string symbol2)
   {
      // Check cache first
      for(int i = 0; i < ArraySize(m_correlations); i++)
      {
         if((m_correlations[i].symbol1 == symbol1 && m_correlations[i].symbol2 == symbol2) ||
            (m_correlations[i].symbol1 == symbol2 && m_correlations[i].symbol2 == symbol1))
         {
            return m_correlations[i].correlation;
         }
      }

      // Calculate and cache
      double correlation = CalculatePearsonCorrelation(symbol1, symbol2);

      int size = ArraySize(m_correlations);
      ArrayResize(m_correlations, size + 1);

      m_correlations[size].symbol1 = symbol1;
      m_correlations[size].symbol2 = symbol2;
      m_correlations[size].correlation = correlation;

      return correlation;
   }

   //+------------------------------------------------------------------+
   //| Calculate portfolio concentration risk                          |
   //+------------------------------------------------------------------+
   double GetPortfolioConcentration(const string& symbols[])
   {
      int numSymbols = ArraySize(symbols);
      if(numSymbols <= 1) return 0;

      double totalCorrelation = 0;
      int pairCount = 0;

      // Calculate average correlation across all pairs
      for(int i = 0; i < numSymbols; i++)
      {
         for(int j = i + 1; j < numSymbols; j++)
         {
            double corr = GetCorrelation(symbols[i], symbols[j]);
            totalCorrelation += MathAbs(corr);
            pairCount++;
         }
      }

      if(pairCount == 0) return 0;

      return totalCorrelation / pairCount;
   }

   //+------------------------------------------------------------------+
   //| Get correlation-adjusted position size                          |
   //+------------------------------------------------------------------+
   double GetCorrelationAdjustedSize(string newSymbol, const string& existingSymbols[], double baseSize)
   {
      int numExisting = ArraySize(existingSymbols);
      if(numExisting == 0) return baseSize;

      double maxCorrelation = 0;

      // Find maximum correlation with existing positions
      for(int i = 0; i < numExisting; i++)
      {
         double corr = MathAbs(GetCorrelation(newSymbol, existingSymbols[i]));
         if(corr > maxCorrelation)
            maxCorrelation = corr;
      }

      // Reduce size based on correlation
      // 0% correlation = 100% size
      // 50% correlation = 75% size
      // 70% correlation = 50% size
      // 90% correlation = 25% size

      if(maxCorrelation >= 0.9)
         return baseSize * 0.25;
      else if(maxCorrelation >= 0.7)
         return baseSize * 0.5;
      else if(maxCorrelation >= 0.5)
         return baseSize * 0.75;
      else
         return baseSize;
   }

   //+------------------------------------------------------------------+
   //| Should block trade due to high correlation                      |
   //+------------------------------------------------------------------+
   bool ShouldBlockTrade(string newSymbol, const string& existingSymbols[])
   {
      int numExisting = ArraySize(existingSymbols);
      if(numExisting == 0) return false;

      // Block if highly correlated (>0.7) with any existing position
      for(int i = 0; i < numExisting; i++)
      {
         if(IsHighlyCorrelated(newSymbol, existingSymbols[i]))
            return true;
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Clear correlation cache                                         |
   //+------------------------------------------------------------------+
   void ClearCache()
   {
      ArrayResize(m_correlations, 0);
   }

   //+------------------------------------------------------------------+
   //| Get correlation matrix for dashboard                            |
   //+------------------------------------------------------------------+
   string GetCorrelationReport(const string& symbols[])
   {
      string report = "=== CORRELATION MATRIX ===\n";
      int numSymbols = ArraySize(symbols);

      for(int i = 0; i < numSymbols; i++)
      {
         for(int j = i + 1; j < numSymbols; j++)
         {
            double corr = GetCorrelation(symbols[i], symbols[j]);
            string status = (MathAbs(corr) > m_correlationThreshold) ? "[HIGH]" : "[OK]";

            report += StringFormat("%s vs %s: %.2f %s\n",
                                   symbols[i], symbols[j], corr, status);
         }
      }

      double concentration = GetPortfolioConcentration(symbols);
      report += StringFormat("\nPortfolio Concentration: %.2f%%\n", concentration * 100);

      return report;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   double GetThreshold() { return m_correlationThreshold; }
   void SetThreshold(double threshold) { m_correlationThreshold = threshold; }
};
