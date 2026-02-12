//+------------------------------------------------------------------+
//|                                          KellyPositionSizer.mqh  |
//|          Adaptive Position Sizing using Kelly Criterion           |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef KELLY_POSITION_SIZER_MQH
#define KELLY_POSITION_SIZER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "Learning_MFE_MAE.mqh"  // For ENTRY_QUALITY enum

//+------------------------------------------------------------------+
//| TRADE RESULT STRUCTURE                                            |
//+------------------------------------------------------------------+
struct TradeResult
{
   datetime time;
   double   rOutcome;      // Risk-adjusted outcome (R-multiple)
   bool     isWin;
   ENTRY_QUALITY quality;
};

//+------------------------------------------------------------------+
//| KELLY POSITION SIZER MODULE                                       |
//| Responsibility: Adaptive position sizing using Kelly Criterion    |
//+------------------------------------------------------------------+
class CKellyPositionSizer
{
private:
   int             m_rollingWindow;     // Number of trades for calculation
   TradeResult     m_tradeHistory[];    // Rolling trade history
   int             m_tradeCount;

   // Calculated metrics
   double          m_winRate;
   double          m_avgWin;            // Average win in R
   double          m_avgLoss;           // Average loss in R
   double          m_rewardRiskRatio;   // Avg Win / Avg Loss
   double          m_kellyPercent;      // Full Kelly percentage
   double          m_optimalRisk;       // Half Kelly (recommended)

   // Constraints
   double          m_baseRisk;          // Base risk percentage
   double          m_minRisk;           // Minimum risk percentage
   double          m_maxRisk;           // Maximum risk percentage
   double          m_kellyFraction;     // Fraction of Kelly to use (0.5 = Half Kelly)

   // Daily limits
   double          m_dailyStartEquity;
   double          m_dailyMaxDD;        // Max daily drawdown %
   double          m_weeklyMaxDD;       // Max weekly drawdown %
   double          m_weeklyStartEquity;
   datetime        m_lastDayCheck;
   datetime        m_lastWeekCheck;
   bool            m_dailyLimitHit;
   bool            m_weeklyLimitHit;

public:
   CKellyPositionSizer() : m_rollingWindow(30), m_tradeCount(0),
                           m_baseRisk(0.5), m_minRisk(0.25), m_maxRisk(1.0),
                           m_kellyFraction(0.5), m_dailyMaxDD(3.0), m_weeklyMaxDD(6.0),
                           m_dailyLimitHit(false), m_weeklyLimitHit(false) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(double baseRisk = 0.5, double minRisk = 0.25, double maxRisk = 1.0,
             double kellyFraction = 0.5, int rollingWindow = 30,
             double dailyMaxDD = 3.0, double weeklyMaxDD = 6.0)
   {
      m_baseRisk = baseRisk;
      m_minRisk = minRisk;
      m_maxRisk = maxRisk;
      m_kellyFraction = kellyFraction;
      m_rollingWindow = rollingWindow;
      m_dailyMaxDD = dailyMaxDD;
      m_weeklyMaxDD = weeklyMaxDD;

      ArrayResize(m_tradeHistory, 0);
      m_tradeCount = 0;

      // Initialize daily/weekly tracking
      m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_weeklyStartEquity = m_dailyStartEquity;
      m_lastDayCheck = TimeCurrent();
      m_lastWeekCheck = TimeCurrent();

      return true;
   }

   //+------------------------------------------------------------------+
   //| Update - Call periodically                                        |
   //+------------------------------------------------------------------+
   void Update()
   {
      CheckPeriodReset();
      CheckDrawdownLimits();
      CalculateMetrics();
      CalculateKelly();
   }

   //+------------------------------------------------------------------+
   //| Add trade result                                                  |
   //+------------------------------------------------------------------+
   void AddTradeResult(double rOutcome, ENTRY_QUALITY quality)
   {
      TradeResult result;
      result.time = TimeCurrent();
      result.rOutcome = rOutcome;
      result.isWin = (rOutcome > 0);
      result.quality = quality;

      // Add to rolling window
      int size = ArraySize(m_tradeHistory);
      if(size >= m_rollingWindow)
      {
         // Shift and add
         for(int i = 0; i < m_rollingWindow - 1; i++)
            m_tradeHistory[i] = m_tradeHistory[i + 1];
         m_tradeHistory[m_rollingWindow - 1] = result;
      }
      else
      {
         ArrayResize(m_tradeHistory, size + 1);
         m_tradeHistory[size] = result;
      }

      m_tradeCount++;

      // Recalculate metrics
      CalculateMetrics();
      CalculateKelly();
   }

   //+------------------------------------------------------------------+
   //| Calculate trading metrics from history                            |
   //+------------------------------------------------------------------+
   void CalculateMetrics()
   {
      int count = ArraySize(m_tradeHistory);
      if(count == 0)
      {
         m_winRate = 0.55;  // Default assumption
         m_avgWin = 1.5;
         m_avgLoss = 1.0;
         return;
      }

      int wins = 0;
      double totalWin = 0;
      double totalLoss = 0;
      int winCount = 0;
      int lossCount = 0;

      for(int i = 0; i < count; i++)
      {
         if(m_tradeHistory[i].isWin)
         {
            wins++;
            totalWin += m_tradeHistory[i].rOutcome;
            winCount++;
         }
         else
         {
            totalLoss += MathAbs(m_tradeHistory[i].rOutcome);
            lossCount++;
         }
      }

      m_winRate = (count > 0) ? (double)wins / count : 0.55;
      m_avgWin = (winCount > 0) ? totalWin / winCount : 1.5;
      m_avgLoss = (lossCount > 0) ? totalLoss / lossCount : 1.0;
      m_rewardRiskRatio = (m_avgLoss > 0) ? m_avgWin / m_avgLoss : 1.5;
   }

   //+------------------------------------------------------------------+
   //| Calculate Kelly Criterion                                         |
   //+------------------------------------------------------------------+
   void CalculateKelly()
   {
      // Kelly Formula: K% = W - [(1-W) / R]
      // Where:
      //   W = Win Rate
      //   R = Reward/Risk Ratio (Avg Win / Avg Loss)

      if(m_rewardRiskRatio <= 0)
      {
         m_kellyPercent = 0;
         m_optimalRisk = m_baseRisk;
         return;
      }

      double kelly = m_winRate - ((1.0 - m_winRate) / m_rewardRiskRatio);

      // Kelly can be negative (don't trade) or very high (too risky)
      m_kellyPercent = MathMax(0, kelly) * 100.0;  // Convert to percentage

      // Apply Kelly fraction (Half Kelly is common for safety)
      m_optimalRisk = m_kellyPercent * m_kellyFraction;

      // Apply constraints
      m_optimalRisk = MathMax(m_minRisk, MathMin(m_maxRisk, m_optimalRisk));
   }

   //+------------------------------------------------------------------+
   //| Get position size risk % for a specific quality                   |
   //+------------------------------------------------------------------+
   double GetRiskForQuality(ENTRY_QUALITY quality)
   {
      // Check if limits hit
      if(m_dailyLimitHit || m_weeklyLimitHit)
         return 0;

      double baseOptimal = m_optimalRisk;

      // Adjust based on entry quality
      switch(quality)
      {
         case EQ_ELITE:
            return MathMin(baseOptimal * 1.2, m_maxRisk);

         case EQ_STRONG:
            return baseOptimal;

         case EQ_GOOD:
            return baseOptimal * 0.8;

         case EQ_WEAK:
            return 0;  // Don't trade weak setups

         default:
            return m_baseRisk;
      }
   }

   //+------------------------------------------------------------------+
   //| Get position size with all factors                                |
   //+------------------------------------------------------------------+
   double GetAdjustedRisk(ENTRY_QUALITY quality, double newsMultiplier = 1.0,
                          double sessionMultiplier = 1.0, double regimeMultiplier = 1.0)
   {
      double baseRisk = GetRiskForQuality(quality);

      // Apply all multipliers
      double adjustedRisk = baseRisk * newsMultiplier * sessionMultiplier * regimeMultiplier;

      // Final constraints
      return MathMax(m_minRisk, MathMin(m_maxRisk, adjustedRisk));
   }

   //+------------------------------------------------------------------+
   //| Check for period reset (daily/weekly)                             |
   //+------------------------------------------------------------------+
   void CheckPeriodReset()
   {
      MqlDateTime current, lastDay, lastWeek;
      TimeToStruct(TimeCurrent(), current);
      TimeToStruct(m_lastDayCheck, lastDay);
      TimeToStruct(m_lastWeekCheck, lastWeek);

      // New day
      if(current.day != lastDay.day)
      {
         m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_dailyLimitHit = false;
         m_lastDayCheck = TimeCurrent();
      }

      // New week (Monday)
      if(current.day_of_week == 1 && lastWeek.day_of_week != 1)
      {
         m_weeklyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_weeklyLimitHit = false;
         m_lastWeekCheck = TimeCurrent();
      }
   }

   //+------------------------------------------------------------------+
   //| Check drawdown limits                                             |
   //+------------------------------------------------------------------+
   void CheckDrawdownLimits()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Daily DD check
      if(m_dailyStartEquity > 0)
      {
         double dailyDD = ((m_dailyStartEquity - currentEquity) / m_dailyStartEquity) * 100.0;
         if(dailyDD >= m_dailyMaxDD)
            m_dailyLimitHit = true;
      }

      // Weekly DD check
      if(m_weeklyStartEquity > 0)
      {
         double weeklyDD = ((m_weeklyStartEquity - currentEquity) / m_weeklyStartEquity) * 100.0;
         if(weeklyDD >= m_weeklyMaxDD)
            m_weeklyLimitHit = true;
      }
   }

   //+------------------------------------------------------------------+
   //| Check if trading allowed based on DD limits                       |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      return (!m_dailyLimitHit && !m_weeklyLimitHit);
   }

   //+------------------------------------------------------------------+
   //| Get current daily DD %                                            |
   //+------------------------------------------------------------------+
   double GetDailyDD()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_dailyStartEquity <= 0) return 0;
      return ((m_dailyStartEquity - currentEquity) / m_dailyStartEquity) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Get current weekly DD %                                           |
   //+------------------------------------------------------------------+
   double GetWeeklyDD()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_weeklyStartEquity <= 0) return 0;
      return ((m_weeklyStartEquity - currentEquity) / m_weeklyStartEquity) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Get expectancy (expected R per trade)                             |
   //+------------------------------------------------------------------+
   double GetExpectancy()
   {
      // Expectancy = (Win% * Avg Win) - (Loss% * Avg Loss)
      return (m_winRate * m_avgWin) - ((1.0 - m_winRate) * m_avgLoss);
   }

   //+------------------------------------------------------------------+
   //| Getters                                                           |
   //+------------------------------------------------------------------+
   double GetWinRate() { return m_winRate; }
   double GetAvgWin() { return m_avgWin; }
   double GetAvgLoss() { return m_avgLoss; }
   double GetRewardRiskRatio() { return m_rewardRiskRatio; }
   double GetKellyPercent() { return m_kellyPercent; }
   double GetOptimalRisk() { return m_optimalRisk; }
   int GetTradeCount() { return m_tradeCount; }
   bool IsDailyLimitHit() { return m_dailyLimitHit; }
   bool IsWeeklyLimitHit() { return m_weeklyLimitHit; }

   //+------------------------------------------------------------------+
   //| Get string representation                                         |
   //+------------------------------------------------------------------+
   string ToString()
   {
      string limitStr = "";
      if(m_dailyLimitHit) limitStr = " [DAILY LIMIT]";
      else if(m_weeklyLimitHit) limitStr = " [WEEKLY LIMIT]";

      return "KELLY: WR=" + DoubleToString(m_winRate * 100, 1) + "% " +
             "R:R=" + DoubleToString(m_rewardRiskRatio, 2) + " " +
             "Opt=" + DoubleToString(m_optimalRisk, 2) + "%" + limitStr;
   }

   //+------------------------------------------------------------------+
   //| Get detailed stats string                                         |
   //+------------------------------------------------------------------+
   string GetDetailedStats()
   {
      string stats = "=== Kelly Position Sizer ===\n";
      stats += "Trades: " + IntegerToString(ArraySize(m_tradeHistory)) + "/" + IntegerToString(m_rollingWindow) + "\n";
      stats += "Win Rate: " + DoubleToString(m_winRate * 100, 1) + "%\n";
      stats += "Avg Win: " + DoubleToString(m_avgWin, 2) + "R\n";
      stats += "Avg Loss: " + DoubleToString(m_avgLoss, 2) + "R\n";
      stats += "R:R Ratio: " + DoubleToString(m_rewardRiskRatio, 2) + "\n";
      stats += "Expectancy: " + DoubleToString(GetExpectancy(), 3) + "R\n";
      stats += "Full Kelly: " + DoubleToString(m_kellyPercent, 2) + "%\n";
      stats += "Half Kelly: " + DoubleToString(m_optimalRisk, 2) + "%\n";
      stats += "Daily DD: " + DoubleToString(GetDailyDD(), 2) + "/" + DoubleToString(m_dailyMaxDD, 1) + "%\n";
      stats += "Weekly DD: " + DoubleToString(GetWeeklyDD(), 2) + "/" + DoubleToString(m_weeklyMaxDD, 1) + "%\n";

      return stats;
   }

   //+------------------------------------------------------------------+
   //| Reset statistics                                                  |
   //+------------------------------------------------------------------+
   void Reset()
   {
      ArrayResize(m_tradeHistory, 0);
      m_tradeCount = 0;
      m_dailyLimitHit = false;
      m_weeklyLimitHit = false;
      m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_weeklyStartEquity = m_dailyStartEquity;
   }
};

#endif
