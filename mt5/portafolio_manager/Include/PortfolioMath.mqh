//+------------------------------------------------------------------+
//|                                                PortfolioMath.mqh |
//|          Mathematical Library for Portfolio Governor             |
//|               Pearson, VaR, Volatility, Statistics               |
//+------------------------------------------------------------------+
#property copyright "Portfolio Governor Math"
#property strict

//+------------------------------------------------------------------+
//| Calculate Pearson Correlation Coefficient                        |
//| Returns: Value between -1.0 and 1.0 (or 0 on error)              |
//+------------------------------------------------------------------+
double CalculatePearson(double &x[], double &y[])
{
   int n = ArraySize(x);
   if(n != ArraySize(y) || n < 2) return 0;
   
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
   
   for(int i = 0; i < n; i++)
   {
      sumX += x[i];
      sumY += y[i];
      sumXY += x[i] * y[i];
      sumX2 += x[i] * x[i];
      sumY2 += y[i] * y[i];
   }
   
   double numerator = n * sumXY - sumX * sumY;
   double denominator = MathSqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY));
   
   return (denominator != 0) ? numerator / denominator : 0;
}

//+------------------------------------------------------------------+
//| Calculate Population Standard Deviation (Volatility)             |
//+------------------------------------------------------------------+
double CalculateVolatility(double &data[])
{
   int n = ArraySize(data);
   if(n < 2) return 0;
   
   double sum = 0;
   for(int i = 0; i < n; i++) sum += data[i];
   
   double mean = sum / n;
   double sumSqDiff = 0;
   
   for(int i = 0; i < n; i++)
   {
      double diff = data[i] - mean;
      sumSqDiff += diff * diff;
   }
   
   return MathSqrt(sumSqDiff / n);
}

//+------------------------------------------------------------------+
//| Calculate Simple Moving Average of Array                         |
//+------------------------------------------------------------------+
double CalculateMean(double &data[])
{
   int n = ArraySize(data);
   if(n == 0) return 0;
   
   double sum = 0;
   for(int i = 0; i < n; i++) sum += data[i];
   return sum / n;
}

//+------------------------------------------------------------------+
//| Calculate Percentile (for VaR)                                   |
//| Assumes data is NOT sorted, will create copy and sort            |
//| Percentile 0.05 = 5th percentile                                 |
//+------------------------------------------------------------------+
double CalculatePercentile(const double &data[], double percentile)
{
   int n = ArraySize(data);
   if(n == 0) return 0;
   
   double sorted[];
   ArrayResize(sorted, n);
   ArrayCopy(sorted, data);
   ArraySort(sorted);
   
   double index = (n - 1) * percentile;
   int lower = (int)MathFloor(index);
   int upper = (int)MathCeil(index);
   double weight = index - lower;
   
   if(upper >= n) return sorted[n-1];
   if(lower < 0) return sorted[0];
   
   return sorted[lower] * (1.0 - weight) + sorted[upper] * weight;
}
