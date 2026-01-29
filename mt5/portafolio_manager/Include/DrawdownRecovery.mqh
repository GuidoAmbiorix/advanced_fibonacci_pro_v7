//+------------------------------------------------------------------+
//|                                           DrawdownRecovery.mqh   |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef DRAWDOWN_RECOVERY_MQH
#define DRAWDOWN_RECOVERY_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "PortfolioGlobals.mqh"

//+------------------------------------------------------------------+
//| DRAWDOWN RECOVERY MODULE                                          |
//| Responsibility: Intelligently scale risk during DD and Recovery  |
//+------------------------------------------------------------------+
class CDrawdownRecovery
{
private:
   double   m_recoveryFactor;
   
public:
   CDrawdownRecovery() : m_recoveryFactor(1.0) {}

   //+------------------------------------------------------------------+
   //| Update Recovery Factor                                            |
   //+------------------------------------------------------------------+
   void Update()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double peakEquity = GlobalVariableGet(GV_PEAK_EQUITY);
      
      if(peakEquity == 0) peakEquity = currentEquity;
      
      // Update Peak High Water Mark
      if(currentEquity > peakEquity)
      {
         GlobalVariableSet(GV_PEAK_EQUITY, currentEquity);
         m_recoveryFactor = 1.0;
         return;
      }
      
      // Calculate Drawdown %
      double dd = (peakEquity - currentEquity) / peakEquity;
      
      // Scale Risk: Cut risk as DD deepens
      if(dd < 0.02) // < 2% DD: Normal
      {
         m_recoveryFactor = 1.0;
      }
      else if(dd < 0.05) // 2-5% DD: Moderate Cut
      {
         m_recoveryFactor = 0.8; 
      }
      else if(dd < 0.08) // 5-8% DD: Serious Cut
      {
         m_recoveryFactor = 0.5;
      }
      else // > 8% DD: Survival Mode
      {
         m_recoveryFactor = 0.25;
      }
      
      // Store in Global Variable for all strategies to see
      GlobalVariableSet(GV_RISK_MULTIPLIER, m_recoveryFactor);
   }
   
   double GetMultiplier() { return m_recoveryFactor; }
};

#endif
