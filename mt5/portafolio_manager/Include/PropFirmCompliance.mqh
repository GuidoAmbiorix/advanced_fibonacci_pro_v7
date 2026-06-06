//+------------------------------------------------------------------+
//|                                          PropFirmCompliance.mqh  |
//|  Prop Firm Compliance Layer — FundingPips Zero $5k rules.        |
//|  Three hard protections:                                         |
//|    1. Floating loss emergency close (1% floating rule = $50,     |
//|       using $42 as conservative limit with buffer)               |
//|    2. Consistency rule: today's profit ≤ 15% of month total      |
//|    3. Friday UTC force close (no weekend holding)                |
//+------------------------------------------------------------------+
#ifndef PROP_FIRM_COMPLIANCE_MQH
#define PROP_FIRM_COMPLIANCE_MQH

class CPropFirmCompliance
{
private:
   bool     m_enabled;
   double   m_floatLossLimit;      // Hard stop on total floating loss (absolute $, e.g. 42.0)
   double   m_consistencyPct;      // Max best-day / total-profit ratio (e.g. 0.15 = 15%)
   double   m_consistencyFloor;    // Min reference = balance * floor (avoids false blocks at start)
   double   m_dailyLossMaxPct;     // Max daily loss % combining closed + floating (e.g. 3.0)
   int      m_fridayCloseUTC;      // UTC hour for Friday force close (e.g. 21, 0=disabled)
   int      m_magicNumber;
   int      m_brokerUTCOffset;     // Broker time offset from UTC (e.g. 2 for UTC+2)

   //+----------------------------------------------------------------+
   //| Compute net P&L per calendar day from history.                 |
   //| Fills dailyPnl[] sorted by date asc. Returns number of days.  |
   //+----------------------------------------------------------------+
   struct DayPnL { datetime date; double pnl; };

   int BuildDailyPnL(datetime fromTime, DayPnL &days[], datetime &todayStart)
   {
      if(!HistorySelect(fromTime, TimeCurrent())) return 0;

      // Collect net P&L per deal, grouped by calendar day
      // Use a simple flat array — max 31 days per month, up to 90 for challenge
      ArrayResize(days, 0);
      int count = 0;

      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magicNumber) continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

         // Truncate to calendar day (broker time)
         MqlDateTime dt; TimeToStruct(dealTime, dt);
         dt.hour = 0; dt.min = 0; dt.sec = 0;
         datetime dayKey = StructToTime(dt);

         // Find or add this day in the array
         bool found = false;
         for(int d = 0; d < count; d++)
         {
            if(days[d].date == dayKey) { days[d].pnl += pnl; found = true; break; }
         }
         if(!found)
         {
            count++;
            ArrayResize(days, count);
            days[count - 1].date = dayKey;
            days[count - 1].pnl  = pnl;
         }
      }

      // Mark today's start for the caller
      MqlDateTime now; TimeCurrent(now);
      now.hour = 0; now.min = 0; now.sec = 0;
      todayStart = StructToTime(now);

      return count;
   }

public:
   CPropFirmCompliance()
   {
      m_enabled            = false;
      m_floatLossLimit     = 42.0;
      m_consistencyPct     = 0.15;
      m_consistencyFloor   = 0.02;
      m_dailyLossMaxPct    = 3.0;
      m_fridayCloseUTC     = 21;
      m_magicNumber        = 0;
      m_brokerUTCOffset    = 2;
   }

   void Init(bool enabled, double floatLossLimit, double consistencyPct,
             int fridayCloseUTC, int magicNumber, int brokerUTCOffset,
             double consistencyFloor = 0.02, double dailyLossMaxPct = 3.0)
   {
      m_enabled            = enabled;
      m_floatLossLimit     = floatLossLimit;
      m_consistencyPct     = consistencyPct;
      m_consistencyFloor   = consistencyFloor;
      m_dailyLossMaxPct    = dailyLossMaxPct;
      m_fridayCloseUTC     = fridayCloseUTC;
      m_magicNumber        = magicNumber;
      m_brokerUTCOffset    = brokerUTCOffset;
   }

   bool IsEnabled() { return m_enabled; }

   //+----------------------------------------------------------------+
   //| 1. Floating loss hard stop.                                    |
   //|    Returns true → emergency close all positions immediately.   |
   //|    totalFloat is filled with the current sum.                  |
   //+----------------------------------------------------------------+
   bool CheckFloatingLoss(double &totalFloat)
   {
      if(!m_enabled || m_floatLossLimit <= 0) { totalFloat = 0; return false; }

      totalFloat = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == "") continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         totalFloat += PositionGetDouble(POSITION_PROFIT)
                     + PositionGetDouble(POSITION_SWAP);
      }
      return (totalFloat <= -m_floatLossLimit);
   }

   //+----------------------------------------------------------------+
   //| 2. Consistency rule — aligned with FundingPips Zero.          |
   //|                                                                |
   //|  Rule: best single trading day (net P&L) must NOT exceed       |
   //|  X% of total net accumulated profit for the period.            |
   //|                                                                |
   //|  Implementation:                                               |
   //|  a) Build net daily P&L from month start (all deals, net)     |
   //|  b) totalNet  = sum of all daily P&L                           |
   //|  c) bestDay   = highest net P&L of any single day              |
   //|  d) todayNet  = today's net P&L (partial — still trading)     |
   //|  e) reference = MathMax(totalNet, balance * floor)             |
   //|     → floor prevents false blocks when period just started     |
   //|  f) Block entries if todayNet / reference >= consistencyPct   |
   //|  g) Warn (no block) if a past day already exceeds the limit   |
   //|                                                                |
   //|  Returns true → block new entries.                            |
   //+----------------------------------------------------------------+
   bool IsConsistencyViolated(string &reason)
   {
      if(!m_enabled || m_consistencyPct <= 0) return false;

      // Use month start as the lookback period
      MqlDateTime now; TimeCurrent(now);
      MqlDateTime mStart;
      mStart.year = now.year; mStart.mon = now.mon;
      mStart.day  = 1; mStart.hour = 0; mStart.min = 0; mStart.sec = 0;
      datetime monthStart = StructToTime(mStart);

      DayPnL days[];
      datetime todayStart = 0;
      int dayCount = BuildDailyPnL(monthStart, days, todayStart);
      if(dayCount == 0) return false;

      // Aggregate: total net profit, best past day, today's net
      double totalNet  = 0.0;
      double bestPast  = 0.0;   // best day EXCLUDING today
      double todayNet  = 0.0;

      for(int d = 0; d < dayCount; d++)
      {
         totalNet += days[d].pnl;
         if(days[d].date == todayStart)
            todayNet = days[d].pnl;
         else if(days[d].pnl > bestPast)
            bestPast = days[d].pnl;
      }

      // Nothing positive yet → no consistency risk
      if(totalNet <= 0 || todayNet <= 0) return false;

      // Floor reference: avoid false blocks when period total is tiny
      // (e.g., $5 total at start of month → $1 today = 20% false positive)
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double floorAmt  = balance * m_consistencyFloor;
      double reference = MathMax(totalNet, floorAmt);

      double todayPct = todayNet / reference;

      // ── Warning: a past day already exceeds the limit ─────────────
      if(bestPast > 0 && reference > 0)
      {
         double pastPct = bestPast / reference;
         if(pastPct >= m_consistencyPct)
         {
            static datetime lastPastWarn = 0;
            if(TimeCurrent() - lastPastWarn > 3600)
            {
               PrintFormat("[PF_COMPLIANCE] WARNING: A previous day earned $%.2f = %.1f%% of $%.2f total "
                           "(limit %.0f%%). Consistency at risk on evaluation.",
                           bestPast, pastPct * 100.0, reference, m_consistencyPct * 100.0);
               lastPastWarn = TimeCurrent();
            }
         }
      }

      // ── Early warning at 85% of limit ──────────────────────────────
      double warnThreshold = m_consistencyPct * 0.85;
      if(todayPct >= warnThreshold && todayPct < m_consistencyPct)
      {
         static datetime lastWarn = 0;
         if(TimeCurrent() - lastWarn > 900)
         {
            PrintFormat("[PF_COMPLIANCE] APPROACHING limit: today=$%.2f = %.1f%% of $%.2f (limit %.0f%%). "
                        "%.1f%% remaining.",
                        todayNet, todayPct * 100.0, reference, m_consistencyPct * 100.0,
                        (m_consistencyPct - todayPct) * 100.0);
            lastWarn = TimeCurrent();
         }
      }

      // ── Hard block at limit ─────────────────────────────────────────
      if(todayPct >= m_consistencyPct)
      {
         reason = StringFormat(
            "[PF_COMPLIANCE] Consistency limit reached: today=$%.2f = %.1f%% of $%.2f net total "
            "(limit %.0f%%, floor=$%.2f). No new entries.",
            todayNet, todayPct * 100.0, reference, m_consistencyPct * 100.0, floorAmt);
         return true;
      }

      return false;
   }

   //+----------------------------------------------------------------+
   //| 3. Daily loss limit — combines CLOSED + FLOATING P&L.         |
   //|    FundingPips: "floating and closed losses must not exceed    |
   //|    3% of the account balance."                                 |
   //|    dayStartBal: balance at start of today (from EquityGuard)  |
   //|    Returns true → close all positions + block entries.         |
   //+----------------------------------------------------------------+
   bool IsDailyLossBreached(double dayStartBal, string &reason)
   {
      if(!m_enabled || m_dailyLossMaxPct <= 0 || dayStartBal <= 0) return false;

      double curBal    = AccountInfoDouble(ACCOUNT_BALANCE);
      double curEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      double closedToday = curBal    - dayStartBal;   // negative = closed loss today
      double floatingNow = curEquity - curBal;         // negative = open floating loss
      double combined    = closedToday + floatingNow;
      double limit       = dayStartBal * (m_dailyLossMaxPct / 100.0);

      // Early warning at 80% of limit
      if(combined < 0 && MathAbs(combined) >= limit * 0.80)
      {
         static datetime lastWarn = 0;
         if(TimeCurrent() - lastWarn > 300)
         {
            PrintFormat("[PF_COMPLIANCE] DAILY LOSS WARNING: closed=%.2f + float=%.2f = %.2f | limit=-%.2f (%.0f%% used)",
                        closedToday, floatingNow, combined, limit,
                        MathAbs(combined) / limit * 100.0);
            lastWarn = TimeCurrent();
         }
      }

      if(combined <= -limit)
      {
         reason = StringFormat(
            "[PF_COMPLIANCE] DAILY LOSS BREACH: closed=%.2f + float=%.2f = %.2f >= -%.2f (%.1f%% of %.2f). CLOSING ALL.",
            closedToday, floatingNow, combined, limit, m_dailyLossMaxPct, dayStartBal);
         return true;
      }
      return false;
   }

   //+----------------------------------------------------------------+
   //| 4. Trailing drawdown from all-time equity peak.               |
   //|    FundingPips: equity must not drop 5% below highest equity   |
   //|    point ever recorded (not weekly — all-time).                |
   //|    allTimePeak: from EquityGuard.GetAllTimePeak()              |
   //|    Returns true → close all positions + block entries.         |
   //+----------------------------------------------------------------+
   bool CheckTrailingDD(double allTimePeak, string &reason)
   {
      if(!m_enabled || allTimePeak <= 0) return false;

      double curEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double trailLimit = allTimePeak * 0.05;      // 5% of peak
      double drawdown   = allTimePeak - curEquity;  // positive = loss from peak

      // Early warning at 80% of limit
      if(drawdown > 0 && drawdown >= trailLimit * 0.80)
      {
         static datetime lastWarn = 0;
         if(TimeCurrent() - lastWarn > 300)
         {
            PrintFormat("[PF_COMPLIANCE] TRAIL DD WARNING: peak=%.2f equity=%.2f drawdown=%.2f (%.1f%% of 5%% = $%.2f limit)",
                        allTimePeak, curEquity, drawdown, drawdown / trailLimit * 100.0, trailLimit);
            lastWarn = TimeCurrent();
         }
      }

      if(drawdown >= trailLimit)
      {
         reason = StringFormat(
            "[PF_COMPLIANCE] TRAIL DD BREACH: peak=%.2f equity=%.2f drawdown=%.2f >= 5%% ($%.2f). CLOSING ALL.",
            allTimePeak, curEquity, drawdown, trailLimit);
         return true;
      }
      return false;
   }

   //+----------------------------------------------------------------+
   //| 5. Trade activity warning.                                     |
   //|    FundingPips: must complete at least 1 trade every 30 days.  |
   //|    Warn at warnDays (default 25) to give time to act.          |
   //+----------------------------------------------------------------+
   void CheckActivityWarning(int warnDays = 25)
   {
      if(!m_enabled) return;

      // Look back 60 days for last closed trade
      datetime from = TimeCurrent() - (datetime)(60 * 86400);
      if(!HistorySelect(from, TimeCurrent())) return;

      datetime lastTrade = 0;
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magicNumber) continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(t > lastTrade) lastTrade = t;
      }

      int daysAgo = (lastTrade > 0) ? (int)((TimeCurrent() - lastTrade) / 86400) : 61;

      if(daysAgo >= warnDays)
      {
         static datetime lastActivityLog = 0;
         if(TimeCurrent() - lastActivityLog > 3600)
         {
            PrintFormat("[PF_COMPLIANCE] ACTIVITY WARNING: last completed trade was %d days ago. "
                        "Account BREACHES if no trade within %d days. TRADE IMMEDIATELY.",
                        daysAgo, 30);
            lastActivityLog = TimeCurrent();
         }
      }
   }

   //+----------------------------------------------------------------+
   //| 6. Payout eligibility warning.                                 |
   //|    FundingPips: need ≥7 active trading days per 30-day cycle.  |
   //|    activeDays30: count of distinct trading days with trades     |
   //|    in the last 30 days (passed in from DB query).              |
   //|    Warns daily when approaching the minimum.                   |
   //+----------------------------------------------------------------+
   void CheckPayoutEligibility(int activeDays30, int warnBelow = 7)
   {
      if(!m_enabled) return;

      if(activeDays30 < warnBelow)
      {
         static datetime lastEligLog = 0;
         if(TimeCurrent() - lastEligLog > 3600)
         {
            PrintFormat("[PF_COMPLIANCE] PAYOUT WARNING: only %d active trading day(s) in the last 30 days "
                        "(need %d for payout eligibility). Trade more days.",
                        activeDays30, warnBelow);
            lastEligLog = TimeCurrent();
         }
      }
   }

   //+----------------------------------------------------------------+
   //| 7. Friday UTC force close.                                     |
   //|    Returns true → close all positions immediately.             |
   //|                                                                |
   //|  IMPORTANT: Uses pure UTC calculation to avoid broker TZ bugs.|
   //|  Bug case: broker UTC+3 → Friday 21:00 UTC = Sat 00:00 broker |
   //|  → day_of_week = 6 → old check would MISS the close entirely. |
   //|  Also triggers all day Saturday: handles EA restarts with      |
   //|  residual open positions after the weekend gap.                |
   //+----------------------------------------------------------------+
   bool IsFridayCloseTime()
   {
      if(!m_enabled || m_fridayCloseUTC <= 0) return false;

      // Convert broker time to UTC by subtracting the broker offset
      // (broker_time = UTC + offset → UTC = broker_time - offset)
      datetime utcNow = TimeCurrent() - (datetime)(m_brokerUTCOffset * 3600);
      MqlDateTime utc;
      TimeToStruct(utcNow, utc);

      // Friday after target UTC hour — standard case
      bool fridayAfterClose = (utc.day_of_week == 5 && utc.hour >= m_fridayCloseUTC);

      // All day Saturday UTC — catches EA restarts with residual positions
      // (market opens Sunday ~21:00 UTC; before that we should be flat)
      bool saturdayClosed   = (utc.day_of_week == 6);

      return (fridayAfterClose || saturdayClosed);
   }
};

#endif
