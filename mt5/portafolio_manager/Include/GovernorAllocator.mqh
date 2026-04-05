//+------------------------------------------------------------------+
//|                                           GovernorAllocator.mqh |
//|                                  Copyright 2026, Infernal Portfolio Governor  |
//|                                     https://www.mql5.com |
//+------------------------------------------------------------------+
#ifndef GOVERNOR_ALLOCATOR_MQH
#define GOVERNOR_ALLOCATOR_MQH

#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

#include "PortfolioGlobals.mqh" // Access to GV keys

//+------------------------------------------------------------------+
//| SHARED DATA STRUCTURES                                            |
//+------------------------------------------------------------------+
struct GovernorRequest
{
   string symbol;
   double baseRisk;
   double winRate;
   double rollingR;
   int    regime; // 0=Trend, 1=Range, 2=Chaos
};

//+------------------------------------------------------------------+
//| GOVERNOR ALLOCATOR MODULE                                         |
//| Responsibility: "The Language of Capital Allocation"             |
//|                 + Calculating Portfolio-Aware Risk               |
//+------------------------------------------------------------------+
class CGovernorAllocator
{
public:
   // 1. Calculate Score (Shared Logic for transparency)
   double CalculateSymbolScore(GovernorRequest &req)
   {
      double score = 1.0;
      
      // Win Rate Weight
      if(req.winRate > 0.6) score += 0.5;
      if(req.winRate < 0.4) score -= 0.3;
      
      // Rolling R Weight
      if(req.rollingR > 2.0) score += 0.5;
      if(req.rollingR < -1.0) score -= 0.5;
      
      // Regime Penalty
      if(req.regime == 2) score = 0; // Chaos = Zero Allocation
      
      return MathMax(0, score);
   }
   
   // 2. Client Side: Builder
   GovernorRequest BuildRequest(string sym, double risk, double wr, double rr, int reg)
   {
      GovernorRequest req;
      req.symbol = sym;
      req.baseRisk = risk;
      req.winRate = wr;
      req.rollingR = rr;
      req.regime = reg;
      return req;
   }
   
   // 3. Request Risk (The Contract Implementation)
   double RequestRisk(GovernorRequest &req)
   {
      // Micro account detection: raise hard cap for small accounts
      // $10-$100 accounts need higher risk % to even open 0.01 lots
      double hardCap = GetHardCapForAccount();

      if(!IsGovernorActive())
      {
         // Standalone mode: simulate Governor score scaling so backtest is representative
         double score = CalculateSymbolScore(req);
         double scaledRisk = req.baseRisk * score;
         // Apply account-aware hard cap
         if(scaledRisk > hardCap) scaledRisk = hardCap;
         return scaledRisk;
      }

      double requestedWithScore = req.baseRisk * CalculateSymbolScore(req);

      // 2. Apply Portfolio Multiplier
      double mult = 1.0;
      if(GlobalVariableCheck(GV_RISK_MULTIPLIER))
         mult = GlobalVariableGet(GV_RISK_MULTIPLIER);

      double finalRisk = requestedWithScore * mult;

      // 3. Exposure Check (account-aware hard cap)
      double totalExp = 0;
      if(GlobalVariableCheck(GV_TOTAL_EXPOSURE)) totalExp = GlobalVariableGet(GV_TOTAL_EXPOSURE);

      if(totalExp + finalRisk > hardCap)
         finalRisk = MathMax(0, hardCap - totalExp);

      return finalRisk;
   }

   // Account-size-aware hard cap
   // Micro accounts ($10-$100) need higher risk % to trade 0.01 lots
   double GetHardCapForAccount()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) equity = AccountInfoDouble(ACCOUNT_BALANCE);

      if(equity <= 100)       return 15.0;  // Nano: allow up to 15%
      else if(equity <= 500)  return 12.0;  // Micro: allow up to 12%
      else if(equity <= 2000) return 10.0;  // Cent $10-$20: allow up to 10% (full escalator)
      else if(equity <= 10000) return 5.0;  // Small: allow up to 5%
      else                    return 2.0;   // Standard: 2% cap
   }
   
   // Helper to check governor status
   bool IsGovernorActive()
   {
      return (GlobalVariableCheck(GV_GOVERNOR_ACTIVE) && GlobalVariableGet(GV_GOVERNOR_ACTIVE) == 1);
   }
};

#endif
