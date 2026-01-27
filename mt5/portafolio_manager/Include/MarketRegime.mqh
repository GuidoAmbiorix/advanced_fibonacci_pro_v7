//+------------------------------------------------------------------+
//|                                                MarketRegime.mqh  |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef MARKET_REGIME_MQH
#define MARKET_REGIME_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "PortfolioGlobals.mqh"

//+------------------------------------------------------------------+
//| MARKET REGIME MODULE                                              |
//| Responsibility: "What is the current market environment?"        |
//+------------------------------------------------------------------+
class CMarketRegime
{
public:
   MARKET_REGIME Detect(double currentATR, double avgATR, double currentEMA, double prevEMA)
   {
      // 1. Check for Chaos (High Volatility Expansion)
      if(currentATR > avgATR * 1.5)
         return REGIME_CHAOS;

      // 2. Check for Trend (EMA Slope)
      double emaSlope = MathAbs(currentEMA - prevEMA);
      if(emaSlope > 0.1 * avgATR) // Significant slope
         return REGIME_TREND;

      // 3. RANGE DETECTION
      // Compressed volatility or flat slope
      double atrRatio = (avgATR > 0) ? currentATR / avgATR : 1.0;
      if(atrRatio < 0.9 || emaSlope < (currentATR * 0.05))
         return REGIME_RANGE;

      return REGIME_RANGE; // Default
   }
   
   string RegimeToString(MARKET_REGIME r)
   {
      switch(r)
      {
         case REGIME_TREND:    return "TRENDING";
         case REGIME_RANGE:    return "RANGING";
         case REGIME_VOLATILE: return "VOLATILE";
         case REGIME_CHAOS:    return "CHAOS";
         default:              return "UNKNOWN";
      }
   }
};

#endif
