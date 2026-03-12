//+------------------------------------------------------------------+
//|                                           PerformanceMetrics.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//+------------------------------------------------------------------+
#ifndef PERFORMANCE_METRICS_MQH
#define PERFORMANCE_METRICS_MQH

//+------------------------------------------------------------------+
//| Performance Metrics Structure                                     |
//+------------------------------------------------------------------+
struct PerformanceMetrics
{
   double kellyFraction;      // Kelly Criterion optimal fraction
   double expectancy;         // Expected value per trade (R)
   double profitFactor;       // Gross profit / gross loss
   double winRate;            // Win rate (0-1.0)
   double avgWin;             // Average winning trade
   double avgLoss;            // Average losing trade (absolute)
   int totalTrades;           // Total trades in sample
   double performanceMult;    // Final multiplier (0.7-1.3)
};

//+------------------------------------------------------------------+
//| Get Performance Data for Symbol                                  |
//+------------------------------------------------------------------+
PerformanceMetrics GetSymbolPerformance(string symbol, int lookbackTrades = 30)
{
   PerformanceMetrics metrics;
   ZeroMemory(metrics);

   double grossProfit = 0, grossLoss = 0;
   int wins = 0, losses = 0;
   double winSum = 0, lossSum = 0;

   // Scan last 30 days for this symbol
   datetime monthAgo = TimeCurrent() - 30 * 24 * 3600;
   HistorySelect(monthAgo, TimeCurrent());

   int total = HistoryDealsTotal();
   int counted = 0;

   for(int i = total - 1; i >= 0 && counted < lookbackTrades; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      string dealSym = HistoryDealGetString(ticket, DEAL_SYMBOL);

      // Normalize symbols for comparison
      string normDealSym = dealSym;
      StringReplace(normDealSym, ".pro", "");
      StringReplace(normDealSym, ".PRO", "");
      StringReplace(normDealSym, ".x", "");
      StringReplace(normDealSym, ".X", "");
      StringToUpper(normDealSym);

      string normSymbol = symbol;
      StringReplace(normSymbol, ".pro", "");
      StringReplace(normSymbol, ".PRO", "");
      StringReplace(normSymbol, ".x", "");
      StringReplace(normSymbol, ".X", "");
      StringToUpper(normSymbol);

      if(StringFind(normDealSym, normSymbol) < 0) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT);

      if(pnl > 0)
      {
         wins++;
         winSum += pnl;
         grossProfit += pnl;
      }
      else if(pnl < 0)
      {
         losses++;
         lossSum += MathAbs(pnl);
         grossLoss += MathAbs(pnl);
      }

      counted++;
   }

   metrics.totalTrades = wins + losses;
   metrics.winRate = (metrics.totalTrades > 0) ? (double)wins / metrics.totalTrades : 0;
   metrics.avgWin = (wins > 0) ? winSum / wins : 0;
   metrics.avgLoss = (losses > 0) ? lossSum / losses : 0;
   metrics.profitFactor = (grossLoss > 0) ? grossProfit / grossLoss :
                          (grossProfit > 0 ? 2.0 : 0);

   // Calculate Kelly Criterion (fractional)
   if(metrics.avgLoss > 0)
   {
      double winLossRatio = metrics.avgWin / metrics.avgLoss;
      double kelly = (metrics.winRate * winLossRatio - (1.0 - metrics.winRate)) / winLossRatio;
      metrics.kellyFraction = MathMax(0, MathMin(0.25, kelly * 0.25)); // Quarter Kelly
   }

   // Calculate Expectancy (R-multiple)
   metrics.expectancy = (metrics.winRate * metrics.avgWin) -
                        ((1.0 - metrics.winRate) * metrics.avgLoss);

   // Calculate performance multiplier (0.7x to 1.3x)
   if(metrics.totalTrades >= 10)
   {
      // HOT HAND: PF > 2.0 AND Win Rate > 55%
      if(metrics.profitFactor > 2.0 && metrics.winRate > 0.55)
         metrics.performanceMult = 1.30;

      // WARM HAND: PF > 1.5 AND Win Rate > 50%
      else if(metrics.profitFactor > 1.5 && metrics.winRate > 0.50)
         metrics.performanceMult = 1.15;

      // COLD HAND: PF < 1.0 OR Win Rate < 40%
      else if(metrics.profitFactor < 1.0 || metrics.winRate < 0.40)
         metrics.performanceMult = 0.70;

      // COOLING: PF < 1.2 OR Win Rate < 45%
      else if(metrics.profitFactor < 1.2 || metrics.winRate < 0.45)
         metrics.performanceMult = 0.85;

      else
         metrics.performanceMult = 1.0; // Neutral
   }
   else
   {
      metrics.performanceMult = 1.0; // Not enough data, neutral
   }

   return metrics;
}

#endif
