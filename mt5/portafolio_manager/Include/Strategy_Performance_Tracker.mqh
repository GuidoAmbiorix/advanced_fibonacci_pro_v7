//+------------------------------------------------------------------+
//|                              Strategy_Performance_Tracker.mqh     |
//|                   Track Performance Metrics Per Strategy          |
//|           Auto-disable underperforming strategies + Dashboard     |
//+------------------------------------------------------------------+
#property copyright "Chameleon Multi-Strategy System"
#property version   "1.00"
#property strict

#include "Strategies\BaseStrategy.mqh"

//+------------------------------------------------------------------+
//| Performance Structure for Each Strategy                          |
//+------------------------------------------------------------------+
struct StrategyPerformance {
   string strategyName;
   MARKET_PHASE activePhase;

   // Trade statistics
   int totalTrades;
   int winningTrades;
   int losingTrades;

   // Profit metrics
   double totalProfit;
   double totalLoss;
   double biggestWin;
   double biggestLoss;
   double netProfit;

   // Calculated metrics
   double winRate;           // Percentage
   double profitFactor;      // Ratio
   double avgWin;
   double avgLoss;
   double avgRR;             // Average Risk:Reward

   // Timestamps
   datetime lastTradeTime;
   datetime lastUpdateTime;

   // Status
   bool isEnabled;
   string disabledReason;
};

//+------------------------------------------------------------------+
//| Strategy Performance Tracker Class                               |
//+------------------------------------------------------------------+
class CStrategyTracker {
private:
   StrategyPerformance m_sniper;
   StrategyPerformance m_rubberBand;
   StrategyPerformance m_breakout;

   string m_dbFile;
   bool m_initialized;

public:
   //--- Constructor
   CStrategyTracker() {
      m_initialized = false;
      m_dbFile = "";
   }

   //--- Initialize tracker
   bool Init(string symbol = "") {
      // Initialize Sniper strategy metrics
      m_sniper.strategyName = "Sniper";
      m_sniper.activePhase = PHASE_TRENDING;
      ResetMetrics(m_sniper);

      // Initialize Rubber Band strategy metrics
      m_rubberBand.strategyName = "RubberBand";
      m_rubberBand.activePhase = PHASE_RANGING;
      ResetMetrics(m_rubberBand);

      // Initialize Breakout strategy metrics
      m_breakout.strategyName = "Breakout";
      m_breakout.activePhase = PHASE_VOLATILE;
      ResetMetrics(m_breakout);

      // Set database file path
      if(symbol == "") symbol = _Symbol;
      m_dbFile = "strategy_performance_" + symbol + ".csv";

      // Load historical data from file
      LoadFromDatabase();

      m_initialized = true;
      return true;
   }

   //--- Record trade closure
   void OnTradeClose(int strategy, double profit, double riskAmount, double rewardAmount) {
      // Work with the appropriate strategy struct
      switch(strategy) {
         case 1: ProcessTradeClose(m_sniper, profit); break;
         case 2: ProcessTradeClose(m_rubberBand, profit); break;
         case 3: ProcessTradeClose(m_breakout, profit); break;
         default: return;
      }

      // Save to database
      SaveToDatabase();
   }

   //--- Get strategy report
   string GetReport() {
      if(!m_initialized) return "Strategy tracker not initialized";

      string report = "\n========== STRATEGY PERFORMANCE ==========\n";
      report += FormatStrategyReport(m_sniper);
      report += FormatStrategyReport(m_rubberBand);
      report += FormatStrategyReport(m_breakout);
      report += "==========================================\n";

      return report;
   }

   //--- Get compact dashboard text
   string GetDashboardText() {
      if(!m_initialized) return "";

      string txt = "";
      txt += StringFormat("Sniper: %d trades | %.1f%% WR | PF %.2f | %s\n",
                         m_sniper.totalTrades,
                         m_sniper.winRate,
                         m_sniper.profitFactor,
                         m_sniper.isEnabled ? "ON" : "OFF");

      txt += StringFormat("RubberBand: %d trades | %.1f%% WR | PF %.2f | %s\n",
                         m_rubberBand.totalTrades,
                         m_rubberBand.winRate,
                         m_rubberBand.profitFactor,
                         m_rubberBand.isEnabled ? "ON" : "OFF");

      txt += StringFormat("Breakout: %d trades | %.1f%% WR | PF %.2f | %s\n",
                         m_breakout.totalTrades,
                         m_breakout.winRate,
                         m_breakout.profitFactor,
                         m_breakout.isEnabled ? "ON" : "OFF");

      return txt;
   }

   //--- Check if strategy should be disabled
   bool ShouldDisableStrategy(int strategy) {
      switch(strategy) {
         case 1: return !m_sniper.isEnabled;
         case 2: return !m_rubberBand.isEnabled;
         case 3: return !m_breakout.isEnabled;
         default: return false;
      }
   }

   //--- Manually enable/disable strategy
   void SetStrategyEnabled(int strategy, bool enabled, string reason = "") {
      switch(strategy) {
         case 1:
            m_sniper.isEnabled = enabled;
            if(!enabled && reason != "") m_sniper.disabledReason = reason;
            break;
         case 2:
            m_rubberBand.isEnabled = enabled;
            if(!enabled && reason != "") m_rubberBand.disabledReason = reason;
            break;
         case 3:
            m_breakout.isEnabled = enabled;
            if(!enabled && reason != "") m_breakout.disabledReason = reason;
            break;
      }
   }

   //--- Get strategy metrics
   double GetWinRate(int strategy) {
      switch(strategy) {
         case 1: return m_sniper.winRate;
         case 2: return m_rubberBand.winRate;
         case 3: return m_breakout.winRate;
         default: return 0.0;
      }
   }

   double GetProfitFactor(int strategy) {
      switch(strategy) {
         case 1: return m_sniper.profitFactor;
         case 2: return m_rubberBand.profitFactor;
         case 3: return m_breakout.profitFactor;
         default: return 0.0;
      }
   }

   int GetTotalTrades(int strategy) {
      switch(strategy) {
         case 1: return m_sniper.totalTrades;
         case 2: return m_rubberBand.totalTrades;
         case 3: return m_breakout.totalTrades;
         default: return 0;
      }
   }

private:
   //--- Process a trade close for a specific strategy
   void ProcessTradeClose(StrategyPerformance &perf, double profit) {
      perf.totalTrades++;
      perf.lastTradeTime = TimeCurrent();

      if(profit > 0) {
         // Winning trade
         perf.winningTrades++;
         perf.totalProfit += profit;
         if(profit > perf.biggestWin) perf.biggestWin = profit;
      } else {
         // Losing trade
         perf.losingTrades++;
         perf.totalLoss += MathAbs(profit);
         if(profit < perf.biggestLoss) perf.biggestLoss = profit;
      }

      // Calculate net profit
      perf.netProfit = perf.totalProfit - perf.totalLoss;

      // Recalculate metrics
      RecalculateMetrics(perf);

      // Update timestamp
      perf.lastUpdateTime = TimeCurrent();

      // Check if strategy should be disabled
      CheckAutoDisable(perf);
   }

   //--- Reset metrics for a strategy
   void ResetMetrics(StrategyPerformance &perf) {
      perf.totalTrades = 0;
      perf.winningTrades = 0;
      perf.losingTrades = 0;
      perf.totalProfit = 0.0;
      perf.totalLoss = 0.0;
      perf.biggestWin = 0.0;
      perf.biggestLoss = 0.0;
      perf.netProfit = 0.0;
      perf.winRate = 0.0;
      perf.profitFactor = 0.0;
      perf.avgWin = 0.0;
      perf.avgLoss = 0.0;
      perf.avgRR = 0.0;
      perf.lastTradeTime = 0;
      perf.lastUpdateTime = 0;
      perf.isEnabled = true;
      perf.disabledReason = "";
   }

   //--- Recalculate all metrics
   void RecalculateMetrics(StrategyPerformance &perf) {
      // Win rate
      perf.winRate = (perf.totalTrades > 0) ?
                     (double)perf.winningTrades / perf.totalTrades * 100.0 : 0.0;

      // Profit factor
      perf.profitFactor = (perf.totalLoss > 0) ?
                          perf.totalProfit / perf.totalLoss : 0.0;

      // Average win/loss
      perf.avgWin = (perf.winningTrades > 0) ?
                    perf.totalProfit / perf.winningTrades : 0.0;
      perf.avgLoss = (perf.losingTrades > 0) ?
                     perf.totalLoss / perf.losingTrades : 0.0;

      // Average R:R (simplified)
      perf.avgRR = (perf.avgLoss > 0) ? perf.avgWin / perf.avgLoss : 0.0;
   }

   //--- Check if strategy should be auto-disabled
   void CheckAutoDisable(StrategyPerformance &perf) {
      if(!perf.isEnabled) return; // Already disabled

      // Rule 1: Win rate < 40% after 20+ trades
      if(perf.totalTrades >= 20 && perf.winRate < 40.0) {
         perf.isEnabled = false;
         perf.disabledReason = "Win rate below 40% after 20+ trades";
         Print("[STRATEGY TRACKER] ", perf.strategyName, " disabled: ", perf.disabledReason);
         return;
      }

      // Rule 2: Profit factor < 1.0 after 30+ trades
      if(perf.totalTrades >= 30 && perf.profitFactor < 1.0) {
         perf.isEnabled = false;
         perf.disabledReason = "Profit factor below 1.0 after 30+ trades";
         Print("[STRATEGY TRACKER] ", perf.strategyName, " disabled: ", perf.disabledReason);
         return;
      }

      // Rule 3: Net profit deeply negative after 25+ trades
      if(perf.totalTrades >= 25 && perf.netProfit < -500.0) {
         perf.isEnabled = false;
         perf.disabledReason = "Net profit below -$500 after 25+ trades";
         Print("[STRATEGY TRACKER] ", perf.strategyName, " disabled: ", perf.disabledReason);
         return;
      }
   }

   //--- Format strategy report
   string FormatStrategyReport(StrategyPerformance &perf) {
      string report = StringFormat("\n%s Strategy (%s):\n",
                                   perf.strategyName,
                                   PhaseToString(perf.activePhase));

      report += StringFormat("  Status: %s", perf.isEnabled ? "ENABLED" : "DISABLED");
      if(!perf.isEnabled && perf.disabledReason != "") {
         report += " (" + perf.disabledReason + ")";
      }
      report += "\n";

      report += StringFormat("  Total Trades: %d (W:%d / L:%d)\n",
                            perf.totalTrades, perf.winningTrades, perf.losingTrades);

      report += StringFormat("  Win Rate: %.1f%%\n", perf.winRate);
      report += StringFormat("  Profit Factor: %.2f\n", perf.profitFactor);
      report += StringFormat("  Net Profit: $%.2f\n", perf.netProfit);
      report += StringFormat("  Avg R:R: %.2f\n", perf.avgRR);

      if(perf.lastTradeTime > 0) {
         report += StringFormat("  Last Trade: %s\n", TimeToString(perf.lastTradeTime));
      }

      return report;
   }

   //--- Convert phase to string
   string PhaseToString(MARKET_PHASE phase) {
      switch(phase) {
         case PHASE_TRENDING: return "Trending";
         case PHASE_RANGING: return "Ranging";
         case PHASE_VOLATILE: return "Volatile";
         case PHASE_DORMANT: return "Dormant";
         default: return "Undefined";
      }
   }

   //--- Save performance data to CSV
   bool SaveToDatabase() {
      int fileHandle = FileOpen(m_dbFile, FILE_WRITE | FILE_CSV | FILE_COMMON);
      if(fileHandle == INVALID_HANDLE) {
         Print("[STRATEGY TRACKER] Failed to open file for writing: ", m_dbFile);
         return false;
      }

      // Write header
      FileWrite(fileHandle, "Strategy,Phase,TotalTrades,WinningTrades,LosingTrades,TotalProfit,TotalLoss,NetProfit,WinRate,ProfitFactor,IsEnabled,DisabledReason");

      // Write Sniper data
      WriteStrategyRow(fileHandle, m_sniper);

      // Write Rubber Band data
      WriteStrategyRow(fileHandle, m_rubberBand);

      // Write Breakout data
      WriteStrategyRow(fileHandle, m_breakout);

      FileClose(fileHandle);
      return true;
   }

   //--- Write strategy row to CSV
   void WriteStrategyRow(int fileHandle, StrategyPerformance &perf) {
      FileWrite(fileHandle,
               perf.strategyName,
               (int)perf.activePhase,
               perf.totalTrades,
               perf.winningTrades,
               perf.losingTrades,
               perf.totalProfit,
               perf.totalLoss,
               perf.netProfit,
               perf.winRate,
               perf.profitFactor,
               perf.isEnabled ? 1 : 0,
               perf.disabledReason);
   }

   //--- Load performance data from CSV
   bool LoadFromDatabase() {
      if(!FileIsExist(m_dbFile, FILE_COMMON)) {
         Print("[STRATEGY TRACKER] No existing database file found. Starting fresh.");
         return false;
      }

      int fileHandle = FileOpen(m_dbFile, FILE_READ | FILE_CSV | FILE_COMMON);
      if(fileHandle == INVALID_HANDLE) {
         Print("[STRATEGY TRACKER] Failed to open file for reading: ", m_dbFile);
         return false;
      }

      // Skip header
      string header = FileReadString(fileHandle);

      // Read strategies
      while(!FileIsEnding(fileHandle)) {
         string strategyName = FileReadString(fileHandle);
         if(strategyName == "") break;

         if(strategyName == "Sniper") {
            ReadStrategyRow(fileHandle, m_sniper);
         } else if(strategyName == "RubberBand") {
            ReadStrategyRow(fileHandle, m_rubberBand);
         } else if(strategyName == "Breakout") {
            ReadStrategyRow(fileHandle, m_breakout);
         }
      }

      FileClose(fileHandle);
      Print("[STRATEGY TRACKER] Loaded performance data from ", m_dbFile);
      return true;
   }

   //--- Read strategy row from CSV
   void ReadStrategyRow(int fileHandle, StrategyPerformance &perf) {
      perf.activePhase = (MARKET_PHASE)FileReadNumber(fileHandle);
      perf.totalTrades = (int)FileReadNumber(fileHandle);
      perf.winningTrades = (int)FileReadNumber(fileHandle);
      perf.losingTrades = (int)FileReadNumber(fileHandle);
      perf.totalProfit = FileReadNumber(fileHandle);
      perf.totalLoss = FileReadNumber(fileHandle);
      perf.netProfit = FileReadNumber(fileHandle);
      perf.winRate = FileReadNumber(fileHandle);
      perf.profitFactor = FileReadNumber(fileHandle);
      perf.isEnabled = ((int)FileReadNumber(fileHandle) == 1);
      perf.disabledReason = FileReadString(fileHandle);
   }
};
