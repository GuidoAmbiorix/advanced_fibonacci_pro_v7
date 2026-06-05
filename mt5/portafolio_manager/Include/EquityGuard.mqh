//+------------------------------------------------------------------+
//|                                                  EquityGuard.mqh |
//|  Greed circuit breaker: daily profit cap, equity trail,          |
//|  hot-streak filter. Prevents euforia from burning gains.         |
//+------------------------------------------------------------------+
#ifndef EQUITY_GUARD_MQH
#define EQUITY_GUARD_MQH

class CEquityGuard
{
private:
   double   m_dayStartBalance;    // Balance at start of trading day
   double   m_weekHighEquity;     // Highest equity seen this week
   double   m_initBalance;        // Balance at EA init (week anchor)
   int      m_consecutiveWins;    // Consecutive winning trades
   bool     m_initialized;

   // Config
   double   m_dailyProfitCapPct;  // e.g. 2.0 = pause if +2% today
   double   m_equityTrailPct;     // e.g. 0.40 = protect 60% of gains from weekHigh
   int      m_hotStreakBonus;     // extra confluence pts required after N wins

public:
   CEquityGuard()
   {
      m_dayStartBalance   = 0;
      m_weekHighEquity    = 0;
      m_initBalance       = 0;
      m_consecutiveWins   = 0;
      m_initialized       = false;
      m_dailyProfitCapPct = 2.0;
      m_equityTrailPct    = 0.40;
      m_hotStreakBonus    = 3;
   }

   void Init(double startBalance, double dailyProfitCapPct, double equityTrailPct, int hotStreakBonus)
   {
      m_initBalance       = startBalance;
      m_dayStartBalance   = startBalance;
      m_weekHighEquity    = startBalance;
      m_dailyProfitCapPct = dailyProfitCapPct;
      m_equityTrailPct    = equityTrailPct;
      m_hotStreakBonus    = hotStreakBonus;
      m_initialized       = true;
   }

   // Call at start of each new day (from ResetDailyLossIfNewDay)
   void OnDayStart(double balance)
   {
      m_dayStartBalance = balance;
   }

   // Call when a new trading week starts (Monday)
   void OnWeekStart(double balance)
   {
      m_initBalance    = balance;
      m_weekHighEquity = balance;
   }

   // Call every scan tick to keep weekHigh updated
   void UpdateWeekHigh(double equity)
   {
      if(equity > m_weekHighEquity) m_weekHighEquity = equity;
   }

   // Call after every trade closes
   void OnTradeClose(bool wasWin)
   {
      if(wasWin) m_consecutiveWins++;
      else       m_consecutiveWins = 0;
   }

   //+----------------------------------------------------------------+
   //| Main gate: can we open a new entry?                            |
   //| Returns true = OK, false = pause (fills reason string)         |
   //+----------------------------------------------------------------+
   bool CanEnterNewTrade(double currentBalance, double currentEquity, string &reason)
   {
      if(!m_initialized) return true;

      // --- 1. Daily Profit Cap ---
      if(m_dailyProfitCapPct > 0 && m_dayStartBalance > 0)
      {
         double dailyGainPct = (currentBalance - m_dayStartBalance) / m_dayStartBalance * 100.0;
         if(dailyGainPct >= m_dailyProfitCapPct)
         {
            reason = StringFormat("[EQUITY_GUARD] Daily cap reached: +%.2f%% (limit %.1f%%). No new entries today.",
                                  dailyGainPct, m_dailyProfitCapPct);
            return false;
         }
      }

      // --- 2. Equity Trail Stop (protect gains from weekly high) ---
      if(m_equityTrailPct > 0 && m_weekHighEquity > m_initBalance)
      {
         double weekGain   = m_weekHighEquity - m_initBalance;
         double floor      = m_initBalance + weekGain * (1.0 - m_equityTrailPct);
         if(currentEquity < floor)
         {
            reason = StringFormat("[EQUITY_GUARD] Equity trail: weekHigh=%.2f floor=%.2f current=%.2f. Pausing entries.",
                                  m_weekHighEquity, floor, currentEquity);
            return false;
         }
      }

      return true;
   }

   // Extra confluence points required when on a hot streak (>= 3 wins)
   int GetHotStreakBonus()
   {
      return (m_consecutiveWins >= 3) ? m_hotStreakBonus : 0;
   }

   int  GetConsecutiveWins()    { return m_consecutiveWins; }
   double GetDayStartBalance()  { return m_dayStartBalance; }
   double GetWeekHighEquity()   { return m_weekHighEquity; }
};

#endif
