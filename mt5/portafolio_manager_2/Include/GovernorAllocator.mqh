//+------------------------------------------------------------------+
//|                                           GovernorAllocator.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef GOVERNOR_ALLOCATOR_MQH
#define GOVERNOR_ALLOCATOR_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
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
      if(!IsGovernorActive()) return req.baseRisk; // Standalone mode
      
      // 1. Calculate Score first? Or assume req.baseRisk IS the requested score-adjusted risk?
      // Architecture says: Symbol calculates score, then asks.
      // But user said: "Governor decides 'how much'".
      // So Symbol should ask with RAW risk? 
      // User said: "double approvedRisk = RequestRiskFromGovernor(InpRiskBase * score);" in previous violation note.
      // Ideally this function takes the final asked risk.
      
      double requestedWithScore = req.baseRisk * CalculateSymbolScore(req);
      
      // 2. Apply Portfolio Multiplier
      double mult = 1.0;
      if(GlobalVariableCheck(GV_RISK_MULTIPLIER))
         mult = GlobalVariableGet(GV_RISK_MULTIPLIER);
         
      double finalRisk = requestedWithScore * mult;
      
      // 3. Exposure Check (Simple client-side guard, Governor does real check)
      double totalExp = 0; 
      if(GlobalVariableCheck(GV_TOTAL_EXPOSURE)) totalExp = GlobalVariableGet(GV_TOTAL_EXPOSURE);
      
      if(totalExp + finalRisk > 2.0) // Hard cap fail-safe
         finalRisk = MathMax(0, 2.0 - totalExp);
         
      return finalRisk;
   }
   
   // Helper to check governor status
   bool IsGovernorActive()
   {
      return (GlobalVariableCheck(GV_GOVERNOR_ACTIVE) && GlobalVariableGet(GV_GOVERNOR_ACTIVE) == 1);
   }
};

#endif
