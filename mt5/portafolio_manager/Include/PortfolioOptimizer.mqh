//+------------------------------------------------------------------+
//|                                         PortfolioOptimizer.mqh   |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef PORTFOLIO_OPTIMIZER_MQH
#define PORTFOLIO_OPTIMIZER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| PORTFOLIO OPTIMIZER                                               |
//| Responsibility: Dynamic Weight Allocation (Risk Parity)          |
//+------------------------------------------------------------------+
class CPortfolioOptimizer
{
private:
   
public:
   CPortfolioOptimizer() {}

   //+------------------------------------------------------------------+
   //| Calculate Risk Parity Weights                                     |
   //| Logic: Equal Risk Contribution (Inv Vol)                         |
   //+------------------------------------------------------------------+
   void BalanceRiskContributions(string &symbols[])
   {
      int count = ArraySize(symbols);
      if(count == 0) return;
      
      double totalInvVol = 0;
      double invVols[];
      ArrayResize(invVols, count);
      
      // 1. Calculate Inverse Volatility for each
      for(int i = 0; i < count; i++)
      {
         double atr = GetATR(symbols[i]);
         double price = SymbolInfoDouble(symbols[i], SYMBOL_BID);
         
         if(price > 0 && atr > 0)
         {
            double dailyVol = atr / price; // % Volatility
            if(dailyVol > 0)
            {
               invVols[i] = 1.0 / dailyVol;
               totalInvVol += invVols[i];
            }
         }
      }
      
      // 2. Normalize and Set Global Weights
      if(totalInvVol > 0)
      {
         for(int i = 0; i < count; i++)
         {
            // Weight = (InvVol / Total) * Count
            // e.g. if 2 assets, 1 is 2x vol of 2.
            // 1 has w=0.33, 2 has w=0.66.
            // Normalize so avg multiplier is 1.0
            
            double rawWeight = invVols[i] / totalInvVol;
            double multiplier = rawWeight * count; 
            
            // Clamp (0.5x to 2.0x)
            multiplier = MathMax(0.5, MathMin(2.0, multiplier));
            
            GlobalVariableSet("OPT_RISK_" + symbols[i], multiplier);
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Helper: Get ATR (Simplified)                                      |
   //+------------------------------------------------------------------+
   double GetATR(string symbol)
   {
      int handle = iATR(symbol, PERIOD_D1, 14);
      if(handle == INVALID_HANDLE) return 0;
      
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, 0, 0, 1, buf) > 0)
      {
         IndicatorRelease(handle);
         return buf[0];
      }
      IndicatorRelease(handle);
      return 0;
   }
   
   //+------------------------------------------------------------------+
   //| Init (Optional)                                                   |
   //+------------------------------------------------------------------+
   void Init() {}
   
   bool NeedsRebalance() { return true; } // Rebalance on every cycle
};

#endif
