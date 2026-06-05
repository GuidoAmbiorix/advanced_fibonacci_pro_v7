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
   
   bool IsExecutionSafe(bool isNewTrade = true)
   {
      // 1. Spread Check (Adaptive ATR-Relative)
      m_symbol.RefreshRates();
      
      // Calculate dynamic spread limit (30% of current ATR)
      double currentATR = iATR(_Symbol, _Period, 14);
      double dynamicMaxSpread = currentATR * 0.30;
      
      // Safety floor: 20 points (to handle ECN/raw spreads)
      if(dynamicMaxSpread < 20) dynamicMaxSpread = 20;

      // Tighten for new trades, allow 50% extra for existing trades to avoid "Quick Closes"
      double limit = isNewTrade ? dynamicMaxSpread : (dynamicMaxSpread * 1.5);

      if(m_symbol.Spread() > limit) return false;
      
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
      Print("R FAILSAFE: Execution reported failure. Count: ", m_consecutiveFailures);
   }
   
   void ReportSuccess()
   {
      m_consecutiveFailures = 0;
   }
};

#endif
