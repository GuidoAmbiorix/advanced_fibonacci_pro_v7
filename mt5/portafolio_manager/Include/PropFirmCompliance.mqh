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
   double   m_floatLossLimit;   // Hard stop on total floating loss (absolute $, e.g. 42.0)
   double   m_consistencyPct;   // Max today's profit / month profit (e.g. 0.15 = 15%)
   int      m_fridayCloseUTC;   // UTC hour for Friday force close (e.g. 21, 0=disabled)
   int      m_magicNumber;
   int      m_brokerUTCOffset;  // Broker time offset from UTC (e.g. 2 for UTC+2)

public:
   CPropFirmCompliance()
   {
      m_enabled         = false;
      m_floatLossLimit  = 42.0;
      m_consistencyPct  = 0.15;
      m_fridayCloseUTC  = 21;
      m_magicNumber     = 0;
      m_brokerUTCOffset = 2;
   }

   void Init(bool enabled, double floatLossLimit, double consistencyPct,
             int fridayCloseUTC, int magicNumber, int brokerUTCOffset)
   {
      m_enabled         = enabled;
      m_floatLossLimit  = floatLossLimit;
      m_consistencyPct  = consistencyPct;
      m_fridayCloseUTC  = fridayCloseUTC;
      m_magicNumber     = magicNumber;
      m_brokerUTCOffset = brokerUTCOffset;
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
         if(!PositionSelectByIndex(i)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         totalFloat += PositionGetDouble(POSITION_PROFIT)
                     + PositionGetDouble(POSITION_SWAP);
      }
      return (totalFloat <= -m_floatLossLimit);
   }

   //+----------------------------------------------------------------+
   //| 2. Consistency rule monitor.                                   |
   //|    Block entries if today's closed profit ≥ X% of month total. |
   //|    Only triggers when month has positive profit to protect.    |
   //|    Returns true → block new entries.                           |
   //+----------------------------------------------------------------+
   bool IsConsistencyViolated(string &reason)
   {
      if(!m_enabled || m_consistencyPct <= 0) return false;

      // Month start: first day of current month at 00:00 broker time
      MqlDateTime now; TimeCurrent(now);
      MqlDateTime mStart; mStart.year = now.year; mStart.mon = now.mon;
      mStart.day = 1; mStart.hour = 0; mStart.min = 0; mStart.sec = 0;
      datetime monthStart = StructToTime(mStart);

      // Today start
      MqlDateTime tStart; tStart.year = now.year; tStart.mon = now.mon;
      tStart.day = now.day; tStart.hour = 0; tStart.min = 0; tStart.sec = 0;
      datetime todayStart = StructToTime(tStart);

      if(!HistorySelect(monthStart, TimeCurrent())) return false;

      double monthProfit = 0.0;
      double todayProfit = 0.0;
      int total = HistoryDealsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magicNumber) continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         if(profit <= 0) continue; // Only count winning periods

         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         monthProfit += profit;
         if(dealTime >= todayStart) todayProfit += profit;
      }

      if(monthProfit <= 0 || todayProfit <= 0) return false;

      double pct = todayProfit / monthProfit;
      if(pct >= m_consistencyPct)
      {
         reason = StringFormat(
            "[PF_COMPLIANCE] Consistency rule: today=+$%.2f is %.1f%% of month=+$%.2f (limit %.0f%%). Pausing entries.",
            todayProfit, pct * 100.0, monthProfit, m_consistencyPct * 100.0);
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
