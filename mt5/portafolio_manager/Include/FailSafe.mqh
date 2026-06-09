//+------------------------------------------------------------------+
//|                                                     FailSafe.mqh |
//|                                  Copyright 2026, Infernal Portfolio Governor  |
//|                                     https://www.mql5.com |
//+------------------------------------------------------------------+
#ifndef FAILSAFE_MQH
#define FAILSAFE_MQH

#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| FAIL SAFE MODULE                                                  |
//| Responsibility: "Is it technically safe to execute?"             |
//+------------------------------------------------------------------+
class CFailSafe
{
private:
   CSymbolInfo m_symbol;
   int         m_maxSpread;
   int         m_consecutiveFailures;
   datetime    m_lastFailureTime;
   
public:
   CFailSafe() : m_maxSpread(50), m_consecutiveFailures(0), m_lastFailureTime(0) {}
   
   void Init(int maxSpread)
   {
      m_maxSpread = maxSpread;
      m_symbol.Name(_Symbol);
   }
   
   bool IsExecutionSafe(bool isNewTrade = true, string &reason = "")
   {
      m_symbol.RefreshRates();

      // 1. Spread Check — skipped entirely if m_maxSpread >= 9999 (disabled)
      if(m_maxSpread < 9999)
      {
         double currentATR = iATR(_Symbol, _Period, 14);
         double dynamicLimit = currentATR * 0.30;
         if(dynamicLimit < 20) dynamicLimit = 20;
         double limit = isNewTrade ? dynamicLimit : dynamicLimit * 1.5;
         // Honor the parameter: use whichever is tighter
         if(m_maxSpread < (int)limit) limit = (double)m_maxSpread;

         if(m_symbol.Spread() > limit)
         {
            reason = StringFormat("spread=%d > limit=%.0f (ATR_dynamic=%.0f param=%d)",
                                  m_symbol.Spread(), limit, dynamicLimit, m_maxSpread);
            return false;
         }
      }

      // 2. Circuit Breaker — 3 consecutive failures → 5 min cooldown
      if(m_consecutiveFailures >= 3)
      {
         int remaining = 300 - (int)(TimeCurrent() - m_lastFailureTime);
         if(remaining > 0)
         {
            reason = StringFormat("circuit_breaker: %d failures, %ds cooldown left",
                                  m_consecutiveFailures, remaining);
            return false;
         }
         m_consecutiveFailures = 0;
      }

      return true;
   }
   
   void ReportFailure()
   {
      m_consecutiveFailures++;
      m_lastFailureTime = TimeCurrent();
      Print("R FAILSAFE: Execution reported failure. Count: ", m_consecutiveFailures);
   }
   
   void ReportSuccess()
   {
      m_consecutiveFailures = 0;
   }
};

#endif
