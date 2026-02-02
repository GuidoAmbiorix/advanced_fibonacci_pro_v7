//+------------------------------------------------------------------+
//|                                      WalkForwardOptimizer.mqh    |
//|                    Walk-Forward Optimization Module               |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Optimization Period Structure                                    |
//+------------------------------------------------------------------+
struct OptimizationPeriod
{
   datetime startDate;
   datetime endDate;
   bool     isInSample;  // true = in-sample (training), false = out-of-sample (testing)
   double   performance; // Sharpe ratio or other metric
};

//+------------------------------------------------------------------+
//| Parameter Set Structure                                          |
//+------------------------------------------------------------------+
struct ParameterSet
{
   // SMC Parameters
   int      swingLookback;
   int      obLookback;
   double   minImpulseATR;
   double   minFvgATR;

   // Exit Parameters
   double   slATRMult;
   double   tpRMult;
   double   trailStartR;

   // Threshold
   double   confluenceThreshold;

   // Performance metrics
   double   sharpeRatio;
   double   profitFactor;
   double   winRate;
   double   avgRMultiple;
};

//+------------------------------------------------------------------+
//| Walk-Forward Optimizer Class                                     |
//+------------------------------------------------------------------+
class CWalkForwardOptimizer
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   // Walk-forward parameters
   int               m_inSampleMonths;      // 3 months
   int               m_outSampleMonths;     // 1 month
   int               m_totalPeriods;        // Number of WF periods

   OptimizationPeriod m_periods[];
   ParameterSet       m_bestParameters[];   // Best params for each period

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CWalkForwardOptimizer()
   {
      m_inSampleMonths = 3;
      m_outSampleMonths = 1;
      m_totalPeriods = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, ENUM_TIMEFRAMES timeframe, int inSampleMonths = 3, int outSampleMonths = 1)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_inSampleMonths = inSampleMonths;
      m_outSampleMonths = outSampleMonths;
   }

   //+------------------------------------------------------------------+
   //| Generate Walk-Forward Periods                                   |
   //+------------------------------------------------------------------+
   bool GenerateWalkForwardPeriods(datetime startDate, datetime endDate)
   {
      ArrayResize(m_periods, 0);

      datetime currentDate = startDate;
      int periodIndex = 0;

      while(currentDate < endDate)
      {
         // In-sample period (3 months)
         int size = ArraySize(m_periods);
         ArrayResize(m_periods, size + 1);

         m_periods[size].startDate = currentDate;
         m_periods[size].endDate = AddMonths(currentDate, m_inSampleMonths);
         m_periods[size].isInSample = true;
         m_periods[size].performance = 0;

         // Out-of-sample period (1 month)
         size = ArraySize(m_periods);
         ArrayResize(m_periods, size + 1);

         m_periods[size].startDate = m_periods[size - 1].endDate;
         m_periods[size].endDate = AddMonths(m_periods[size].startDate, m_outSampleMonths);
         m_periods[size].isInSample = false;
         m_periods[size].performance = 0;

         // Move to next window
         currentDate = AddMonths(currentDate, m_inSampleMonths + m_outSampleMonths);
         periodIndex++;

         if(periodIndex >= 12) break; // Limit to 12 periods (2 years)
      }

      m_totalPeriods = ArraySize(m_periods);
      return (m_totalPeriods > 0);
   }

   //+------------------------------------------------------------------+
   //| Add Months to Date                                              |
   //+------------------------------------------------------------------+
   datetime AddMonths(datetime date, int months)
   {
      MqlDateTime dt;
      TimeToStruct(date, dt);

      dt.mon += months;
      while(dt.mon > 12)
      {
         dt.mon -= 12;
         dt.year += 1;
      }

      return StructToTime(dt);
   }

   //+------------------------------------------------------------------+
   //| Optimize In-Sample Period                                       |
   //+------------------------------------------------------------------+
   ParameterSet OptimizeInSamplePeriod(int periodIndex)
   {
      if(periodIndex >= ArraySize(m_periods) || !m_periods[periodIndex].isInSample)
      {
         ParameterSet empty;
         return empty;
      }

      ParameterSet bestParams;
      double bestSharpe = -99999;

      // Parameter grid search
      int swingLookbacks[] = {35, 40, 45, 50};
      double minImpulseATRs[] = {2.0, 2.3, 2.5, 2.8};
      double slATRMults[] = {1.8, 2.0, 2.2, 2.5};
      double tpRMults[] = {3.0, 3.5, 4.0};
      double thresholds[] = {8.0, 9.0, 10.0};

      // Grid search (simplified - full implementation would backtest each combination)
      for(int i = 0; i < ArraySize(swingLookbacks); i++)
      {
         for(int j = 0; j < ArraySize(minImpulseATRs); j++)
         {
            for(int k = 0; k < ArraySize(slATRMults); k++)
            {
               for(int m = 0; m < ArraySize(tpRMults); m++)
               {
                  for(int n = 0; n < ArraySize(thresholds); n++)
                  {
                     ParameterSet params;
                     params.swingLookback = swingLookbacks[i];
                     params.minImpulseATR = minImpulseATRs[j];
                     params.slATRMult = slATRMults[k];
                     params.tpRMult = tpRMults[m];
                     params.confluenceThreshold = thresholds[n];

                     // Simulate backtest performance (in real implementation, run actual backtest)
                     double sharpe = SimulatePerformance(params, m_periods[periodIndex].startDate,
                                                        m_periods[periodIndex].endDate);

                     if(sharpe > bestSharpe)
                     {
                        bestSharpe = sharpe;
                        bestParams = params;
                        bestParams.sharpeRatio = sharpe;
                     }
                  }
               }
            }
         }
      }

      return bestParams;
   }

   //+------------------------------------------------------------------+
   //| Simulate Performance (Mock)                                     |
   //+------------------------------------------------------------------+
   double SimulatePerformance(ParameterSet &params, datetime startDate, datetime endDate)
   {
      // Mock performance calculation
      // In real implementation, this would run a full backtest

      // Generate random but reasonable performance
      double baseSharpe = 1.0;

      // Reward optimal H1 parameters
      if(params.swingLookback >= 40 && params.swingLookback <= 50)
         baseSharpe += 0.2;

      if(params.minImpulseATR >= 2.3 && params.minImpulseATR <= 2.8)
         baseSharpe += 0.2;

      if(params.slATRMult >= 2.0 && params.slATRMult <= 2.5)
         baseSharpe += 0.2;

      if(params.tpRMult >= 3.0 && params.tpRMult <= 4.0)
         baseSharpe += 0.3;

      if(params.confluenceThreshold >= 9.0 && params.confluenceThreshold <= 10.0)
         baseSharpe += 0.1;

      return baseSharpe;
   }

   //+------------------------------------------------------------------+
   //| Test Out-of-Sample Period                                       |
   //+------------------------------------------------------------------+
   double TestOutOfSamplePeriod(int periodIndex, ParameterSet &params)
   {
      if(periodIndex >= ArraySize(m_periods) || m_periods[periodIndex].isInSample)
         return 0;

      // Run backtest with optimized parameters on out-of-sample period
      double performance = SimulatePerformance(params, m_periods[periodIndex].startDate,
                                              m_periods[periodIndex].endDate);

      m_periods[periodIndex].performance = performance;
      return performance;
   }

   //+------------------------------------------------------------------+
   //| Run Full Walk-Forward Optimization                              |
   //+------------------------------------------------------------------+
   bool RunWalkForward(datetime startDate, datetime endDate)
   {
      if(!GenerateWalkForwardPeriods(startDate, endDate))
         return false;

      ArrayResize(m_bestParameters, m_totalPeriods / 2); // One set per in-sample period

      int paramIndex = 0;

      for(int i = 0; i < m_totalPeriods - 1; i += 2)
      {
         // Optimize in-sample period
         Print("Optimizing in-sample period ", i / 2 + 1);
         ParameterSet bestParams = OptimizeInSamplePeriod(i);

         m_bestParameters[paramIndex] = bestParams;

         // Test on out-of-sample period
         Print("Testing out-of-sample period ", i / 2 + 1);
         double oosSharpe = TestOutOfSamplePeriod(i + 1, bestParams);

         Print("Out-of-sample Sharpe: ", DoubleToString(oosSharpe, 2));

         paramIndex++;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Robustness Score                                            |
   //+------------------------------------------------------------------+
   double GetRobustnessScore()
   {
      if(ArraySize(m_periods) < 2) return 0;

      // Calculate ratio of out-of-sample to in-sample performance
      double inSampleAvg = 0;
      double outSampleAvg = 0;
      int inCount = 0, outCount = 0;

      for(int i = 0; i < ArraySize(m_periods); i++)
      {
         if(m_periods[i].isInSample)
         {
            inSampleAvg += m_periods[i].performance;
            inCount++;
         }
         else
         {
            outSampleAvg += m_periods[i].performance;
            outCount++;
         }
      }

      if(inCount > 0) inSampleAvg /= inCount;
      if(outCount > 0) outSampleAvg /= outCount;

      // Robustness = OOS / IS ratio (ideally > 0.7)
      if(inSampleAvg > 0)
         return outSampleAvg / inSampleAvg;

      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get Recommended Parameters (Latest)                             |
   //+------------------------------------------------------------------+
   ParameterSet GetRecommendedParameters()
   {
      if(ArraySize(m_bestParameters) == 0)
      {
         ParameterSet defaultParams;
         defaultParams.swingLookback = 45;
         defaultParams.minImpulseATR = 2.5;
         defaultParams.slATRMult = 2.2;
         defaultParams.tpRMult = 3.5;
         defaultParams.confluenceThreshold = 9.0;
         return defaultParams;
      }

      // Return latest optimized parameters
      return m_bestParameters[ArraySize(m_bestParameters) - 1];
   }

   //+------------------------------------------------------------------+
   //| Get Walk-Forward Report                                         |
   //+------------------------------------------------------------------+
   string GetWalkForwardReport()
   {
      string report = "=== WALK-FORWARD OPTIMIZATION ===\n";
      report += StringFormat("Total Periods: %d\n", m_totalPeriods);
      report += StringFormat("In-Sample: %d months\n", m_inSampleMonths);
      report += StringFormat("Out-Sample: %d months\n\n", m_outSampleMonths);

      double robustness = GetRobustnessScore();
      report += StringFormat("Robustness Score: %.2f ", robustness);

      if(robustness > 0.8)
         report += "(Excellent)\n";
      else if(robustness > 0.6)
         report += "(Good)\n";
      else if(robustness > 0.4)
         report += "(Fair)\n";
      else
         report += "(Poor - Overfit)\n";

      report += "\nRecommended Parameters:\n";
      ParameterSet params = GetRecommendedParameters();
      report += StringFormat("Swing Lookback: %d\n", params.swingLookback);
      report += StringFormat("Min Impulse ATR: %.1f\n", params.minImpulseATR);
      report += StringFormat("SL ATR Mult: %.1f\n", params.slATRMult);
      report += StringFormat("TP R-Mult: %.1f\n", params.tpRMult);
      report += StringFormat("Threshold: %.1f\n", params.confluenceThreshold);

      return report;
   }
};
