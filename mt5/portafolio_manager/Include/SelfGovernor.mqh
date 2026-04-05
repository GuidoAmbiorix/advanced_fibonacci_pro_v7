//+------------------------------------------------------------------+
//|                                              SelfGovernor.mqh    |
//|                          Copyright 2026, Infernal Portfolio Governor |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
// Self-contained per-symbol risk governor.
// Replaces the external Portfolio_Governor dependency.
// Each Symbol_Engine instance manages its own drawdown independently.
//+------------------------------------------------------------------+
#ifndef SELF_GOVERNOR_MQH
#define SELF_GOVERNOR_MQH
#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

class CSelfGovernor
{
private:
   bool     m_enabled;
   double   m_ddReduce;    // % total DD to start reducing risk
   double   m_ddPause;     // % total DD to pause trading entirely
   double   m_reducedMult; // risk multiplier when in reduce zone
   double   m_dailyMaxDD;  // % daily DD to stop for the day

   double   m_peakEquity;
   double   m_dailyStart;
   datetime m_dayStart;

   void LogThrottled(string msg, datetime &lastLog)
   {
      if(TimeCurrent() - lastLog > 300)
      {
         Print("[GOVERNOR] ", msg);
         lastLog = TimeCurrent();
      }
   }

public:
   void Init(bool enabled, double ddReduce, double ddPause, double reducedMult, double dailyMaxDD)
   {
      m_enabled      = enabled;
      m_ddReduce     = ddReduce;
      m_ddPause      = ddPause;
      m_reducedMult  = reducedMult;
      m_dailyMaxDD   = dailyMaxDD;
      m_peakEquity   = 0;
      m_dailyStart   = 0;
      m_dayStart     = 0;
   }

   // Account-size-aware hard cap on risk %
   double GetHardCap()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) equity = AccountInfoDouble(ACCOUNT_BALANCE);
      if(equity <= 100)        return 15.0;
      else if(equity <= 500)   return 12.0;
      else if(equity <= 2000)  return 10.0;
      else if(equity <= 10000) return  5.0;
      else                     return  2.0;
   }

   // Returns risk multiplier: 1.0 = normal, <1.0 = reduced, 0.0 = paused
   double GetMultiplier()
   {
      if(!m_enabled) return 1.0;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return 1.0;

      if(m_peakEquity <= 0) m_peakEquity = equity;
      if(m_dailyStart <= 0) { m_dailyStart = equity; m_dayStart = TimeCurrent(); }

      if(equity > m_peakEquity) m_peakEquity = equity;

      // Daily reset
      MqlDateTime now, dayStart;
      TimeToStruct(TimeCurrent(), now);
      TimeToStruct(m_dayStart, dayStart);
      if(now.day != dayStart.day || now.mon != dayStart.mon)
      {
         m_dailyStart = equity;
         m_dayStart   = TimeCurrent();
      }

      double totalDD = (m_peakEquity - equity) / m_peakEquity * 100.0;
      double dailyDD = (m_dailyStart  - equity) / m_dailyStart  * 100.0;

      static datetime lastLog1 = 0, lastLog2 = 0, lastLog3 = 0;

      if(dailyDD >= m_dailyMaxDD)
      {
         LogThrottled("Daily DD " + DoubleToString(dailyDD,2) + "% >= " + DoubleToString(m_dailyMaxDD,1) + "% — PAUSED for today", lastLog1);
         return 0.0;
      }
      if(totalDD >= m_ddPause)
      {
         LogThrottled("Total DD " + DoubleToString(totalDD,2) + "% >= " + DoubleToString(m_ddPause,1) + "% — TRADING HALTED", lastLog2);
         return 0.0;
      }
      if(totalDD >= m_ddReduce)
      {
         LogThrottled("Total DD " + DoubleToString(totalDD,2) + "% — risk reduced to " + DoubleToString(m_reducedMult*100,0) + "%", lastLog3);
         return m_reducedMult;
      }

      return 1.0;
   }

   // Apply multiplier and hard cap to a base risk value
   double ApproveRisk(double baseRisk)
   {
      double approved = baseRisk * GetMultiplier();
      double cap = GetHardCap();
      if(approved > cap) approved = cap;
      return approved;
   }

   bool IsTradingEnabled()
   {
      return GetMultiplier() > 0.0;
   }

   double GetCurrentTotalDD()
   {
      if(m_peakEquity <= 0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_peakEquity - equity) / m_peakEquity * 100.0;
   }

   double GetCurrentDailyDD()
   {
      if(m_dailyStart <= 0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_dailyStart - equity) / m_dailyStart * 100.0;
   }

   string GetStatus()
   {
      if(!m_enabled) return "OFF";
      double mult = GetMultiplier();
      if(mult <= 0.0) return "PAUSED";
      if(mult < 1.0)  return "REDUCED(" + DoubleToString(mult*100,0) + "%)";
      return "ACTIVE DD:" + DoubleToString(GetCurrentTotalDD(),1) + "%";
   }
};

#endif
