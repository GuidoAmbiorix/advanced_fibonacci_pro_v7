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
      m_consistencyFloor   = 0.02;   // 2% of balance as minimum reference ($100 on $5k)
      m_fridayCloseUTC     = 21;
      m_magicNumber        = 0;
      m_brokerUTCOffset    = 2;
   }

   // consistencyFloor: balance fraction used as minimum denominator (default 0.02 = 2%)
   void Init(bool enabled, double floatLossLimit, double consistencyPct,
             int fridayCloseUTC, int magicNumber, int brokerUTCOffset,
             double consistencyFloor = 0.02)
   {
      m_enabled            = enabled;
      m_floatLossLimit     = floatLossLimit;
      m_consistencyPct     = consistencyPct;
      m_consistencyFloor   = consistencyFloor;
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
   //| 3. Friday UTC force close.                                     |
   //|    Returns true → close all positions immediately.             |
   //+----------------------------------------------------------------+
   bool IsFridayCloseTime()
   {
      if(!m_enabled || m_fridayCloseUTC <= 0) return false;

      MqlDateTime dt; TimeCurrent(dt);
      if(dt.day_of_week != 5) return false; // Not Friday

      // Convert broker time → UTC
      int utcHour = dt.hour - m_brokerUTCOffset;
      if(utcHour < 0)  utcHour += 24;
      if(utcHour > 23) utcHour -= 24;

      return (utcHour >= m_fridayCloseUTC);
   }
};

#endif
