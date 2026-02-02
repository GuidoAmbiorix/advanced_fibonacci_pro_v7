//+------------------------------------------------------------------+
//|                                    ExitStrategyAnalyzer.mqh      |
//|                  Analyze Actual R-Multiples Achieved             |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Trade Analysis Structure                                         |
//+------------------------------------------------------------------+
struct TradeAnalysis
{
   long     ticket;
   datetime entryTime;
   double   entryPrice;
   double   slPrice;
   double   tpPrice;
   double   exitPrice;
   double   risk;
   double   reward;
   double   rMultiple;
   double   mfe;          // Maximum Favorable Excursion
   double   mae;          // Maximum Adverse Excursion
   string   exitReason;
   int      barsHeld;
};

//+------------------------------------------------------------------+
//| Exit Strategy Analyzer Class                                    |
//+------------------------------------------------------------------+
class CExitStrategyAnalyzer
{
private:
   TradeAnalysis m_trades[];
   int           m_tradeCount;

   // Statistics
   double        m_avgRMultiple;
   double        m_avgMFE;
   double        m_avgMAE;
   double        m_winRate;
   int           m_prematureStops;
   int           m_reachedTP;

public:
   CExitStrategyAnalyzer()
   {
      ArrayResize(m_trades, 0);
      m_tradeCount = 0;
      m_prematureStops = 0;
      m_reachedTP = 0;
   }

   //+------------------------------------------------------------------+
   //| Record Trade Entry                                              |
   //+------------------------------------------------------------------+
   void RecordEntry(long ticket, double entry, double sl, double tp)
   {
      int size = ArraySize(m_trades);
      ArrayResize(m_trades, size + 1);

      m_trades[size].ticket = ticket;
      m_trades[size].entryTime = TimeCurrent();
      m_trades[size].entryPrice = entry;
      m_trades[size].slPrice = sl;
      m_trades[size].tpPrice = tp;
      m_trades[size].risk = MathAbs(entry - sl);
      m_trades[size].reward = MathAbs(tp - entry);
      m_trades[size].mfe = 0;
      m_trades[size].mae = 0;

      m_tradeCount++;
   }

   //+------------------------------------------------------------------+
   //| Update Trade Progress (Track MFE/MAE)                          |
   //+------------------------------------------------------------------+
   void UpdateTrade(long ticket, double currentPrice)
   {
      for(int i = 0; i < ArraySize(m_trades); i++)
      {
         if(m_trades[i].ticket == ticket)
         {
            double profit = currentPrice - m_trades[i].entryPrice;

            // Update MFE (Maximum Favorable Excursion)
            if(profit > m_trades[i].mfe)
               m_trades[i].mfe = profit;

            // Update MAE (Maximum Adverse Excursion)
            if(profit < 0 && MathAbs(profit) > m_trades[i].mae)
               m_trades[i].mae = MathAbs(profit);

            break;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Record Trade Exit                                              |
   //+------------------------------------------------------------------+
   void RecordExit(long ticket, double exitPrice, string reason)
   {
      for(int i = 0; i < ArraySize(m_trades); i++)
      {
         if(m_trades[i].ticket == ticket)
         {
            m_trades[i].exitPrice = exitPrice;
            m_trades[i].exitReason = reason;
            m_trades[i].barsHeld = (int)((TimeCurrent() - m_trades[i].entryTime) / PeriodSeconds(PERIOD_H1));

            // Calculate actual R-Multiple achieved
            double actualProfit = exitPrice - m_trades[i].entryPrice;
            m_trades[i].rMultiple = actualProfit / m_trades[i].risk;

            // Classify exit
            if(StringFind(reason, "TP") >= 0 || StringFind(reason, "Target") >= 0)
               m_reachedTP++;
            else if(StringFind(reason, "SL") >= 0 || StringFind(reason, "Stop") >= 0)
               m_prematureStops++;

            CalculateStatistics();
            break;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Statistics                                            |
   //+------------------------------------------------------------------+
   void CalculateStatistics()
   {
      if(m_tradeCount == 0) return;

      double totalR = 0;
      double totalMFE = 0;
      double totalMAE = 0;
      int winners = 0;

      for(int i = 0; i < ArraySize(m_trades); i++)
      {
         if(m_trades[i].exitPrice > 0)
         {
            totalR += m_trades[i].rMultiple;
            totalMFE += m_trades[i].mfe / m_trades[i].risk;
            totalMAE += m_trades[i].mae / m_trades[i].risk;

            if(m_trades[i].rMultiple > 0)
               winners++;
         }
      }

      int closedTrades = 0;
      for(int i = 0; i < ArraySize(m_trades); i++)
      {
         if(m_trades[i].exitPrice > 0)
            closedTrades++;
      }

      if(closedTrades > 0)
      {
         m_avgRMultiple = totalR / closedTrades;
         m_avgMFE = totalMFE / closedTrades;
         m_avgMAE = totalMAE / closedTrades;
         m_winRate = (double)winners / closedTrades * 100;
      }
   }

   //+------------------------------------------------------------------+
   //| Get Comprehensive Report                                        |
   //+------------------------------------------------------------------+
   string GetReport()
   {
      CalculateStatistics();

      string report = "\n╔══════════════════════════════════════════╗\n";
      report += "║     EXIT STRATEGY ANALYSIS REPORT        ║\n";
      report += "╚══════════════════════════════════════════╝\n\n";

      report += "OVERALL STATISTICS:\n";
      report += "─────────────────────────────────────────\n";
      report += StringFormat("Total Trades: %d\n", m_tradeCount);
      report += StringFormat("Win Rate: %.1f%%\n", m_winRate);
      report += StringFormat("Avg R-Multiple: %.2fR\n", m_avgRMultiple);
      report += StringFormat("Avg MFE: %.2fR\n", m_avgMFE);
      report += StringFormat("Avg MAE: %.2fR\n", m_avgMAE);
      report += "\n";

      report += "EXIT BREAKDOWN:\n";
      report += "─────────────────────────────────────────\n";
      report += StringFormat("Reached TP: %d (%.1f%%)\n", m_reachedTP,
                            (double)m_reachedTP/m_tradeCount*100);
      report += StringFormat("Hit SL: %d (%.1f%%)\n", m_prematureStops,
                            (double)m_prematureStops/m_tradeCount*100);
      report += "\n";

      // MFE/MAE Analysis
      report += "OPPORTUNITY ANALYSIS:\n";
      report += "─────────────────────────────────────────\n";

      double mfeCapture = (m_avgMFE > 0) ? (m_avgRMultiple / m_avgMFE * 100) : 0;
      report += StringFormat("MFE Capture Rate: %.1f%%\n", mfeCapture);

      if(mfeCapture < 50)
         report += "⚠️ LOW CAPTURE - Trades moving favorably but not closing well\n";
      else if(mfeCapture > 80)
         report += "✅ GOOD CAPTURE - Effectively capturing favorable moves\n";

      report += "\n";

      // Stop Loss Analysis
      double maeRatio = m_avgMAE / 1.0; // Compare to 1R SL
      if(maeRatio > 1.2)
         report += "⚠️ STOPS TOO TIGHT - MAE exceeds 1.2R regularly\n";
      else if(maeRatio < 0.5)
         report += "✅ GOOD STOP PLACEMENT - MAE well below SL\n";

      report += "\n";

      // Target Analysis
      report += "TARGET ACHIEVEMENT:\n";
      report += "─────────────────────────────────────────\n";

      if(m_avgRMultiple < 1.0 && m_avgMFE > 2.0)
         report += "🔴 CRITICAL: Avg R <1.0 but MFE >2.0\n";
         report += "    → Trades move 2R+ favorable but close <1R\n";
         report += "    → EXIT STRATEGY IS THE PROBLEM\n\n";

      if(m_avgRMultiple < 0.5)
         report += "🔴 CRITICAL: Avg R <0.5 - System is bleeding capital\n\n";

      if(m_avgRMultiple > 2.0)
         report += "✅ EXCELLENT: Avg R >2.0 - Strong exit execution\n\n";

      // Recommendations
      report += "RECOMMENDATIONS:\n";
      report += "─────────────────────────────────────────\n";

      if(m_avgRMultiple < 1.0)
      {
         report += "1. INCREASE STOP LOSS to 2.5-3.0 ATR\n";
         report += "2. WIDEN TRAILING STOP distance\n";
         report += "3. START TRAILING at 3.0R (not 2.5R)\n";
      }

      if(mfeCapture < 60)
      {
         report += "4. REVIEW TRAILING LOGIC - too aggressive\n";
         report += "5. Consider PARTIAL PROFITS at 2R\n";
         report += "6. Let RUNNERS develop longer\n";
      }

      if(m_prematureStops > m_reachedTP)
      {
         report += "7. STOPS HIT MORE THAN TPS\n";
         report += "   → SL too tight OR TP too far\n";
         report += "   → Test with 2.5 ATR SL, 3.0R TP\n";
      }

      report += "\n═══════════════════════════════════════════\n";

      return report;
   }

   //+------------------------------------------------------------------+
   //| Export to CSV                                                   |
   //+------------------------------------------------------------------+
   void ExportToCSV()
   {
      string filename = "exit_analysis.csv";
      int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_COMMON);

      if(handle == INVALID_HANDLE) return;

      // Header
      FileWrite(handle, "Ticket", "Entry", "SL", "TP", "Exit", "Risk",
                "R-Multiple", "MFE_R", "MAE_R", "BarsHeld", "ExitReason");

      // Data
      for(int i = 0; i < ArraySize(m_trades); i++)
      {
         if(m_trades[i].exitPrice > 0)
         {
            FileWrite(handle,
               IntegerToString(m_trades[i].ticket),
               DoubleToString(m_trades[i].entryPrice, 5),
               DoubleToString(m_trades[i].slPrice, 5),
               DoubleToString(m_trades[i].tpPrice, 5),
               DoubleToString(m_trades[i].exitPrice, 5),
               DoubleToString(m_trades[i].risk, 5),
               DoubleToString(m_trades[i].rMultiple, 2),
               DoubleToString(m_trades[i].mfe / m_trades[i].risk, 2),
               DoubleToString(m_trades[i].mae / m_trades[i].risk, 2),
               IntegerToString(m_trades[i].barsHeld),
               m_trades[i].exitReason
            );
         }
      }

      FileClose(handle);
      Print("Exit analysis exported to: ", filename);
   }

   //+------------------------------------------------------------------+
   //| Getters                                                         |
   //+------------------------------------------------------------------+
   double GetAvgRMultiple() { return m_avgRMultiple; }
   double GetAvgMFE() { return m_avgMFE; }
   double GetAvgMAE() { return m_avgMAE; }
   double GetWinRate() { return m_winRate; }
};
