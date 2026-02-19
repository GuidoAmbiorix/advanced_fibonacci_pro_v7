//+------------------------------------------------------------------+
//|                                                     FailSafe.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef FAILSAFE_MQH
#define FAILSAFE_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
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
   
   bool IsExecutionSafe()
   {
      // 1. Spread Check
      m_symbol.RefreshRates();
      if(m_symbol.Spread() > m_maxSpread) return false;
      
      // 2. Circuit Breaker (if too many failures recently)
      if(m_consecutiveFailures >= 3)
      {
         if(TimeCurrent() - m_lastFailureTime < 300) return false; // Cool down 5 mins
         m_consecutiveFailures = 0; // Reset after cooldown
      }
      
      return true;
   }
   
   void ReportFailure()
   {
      m_consecutiveFailures++;
      m_lastFailureTime = TimeCurrent();
      Print("⚠️ FAILSAFE: Execution reported failure. Count: ", m_consecutiveFailures);
   }
   
   void ReportSuccess()
   {
      m_consecutiveFailures = 0;
   }
};

#endif
