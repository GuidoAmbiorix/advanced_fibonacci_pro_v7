//+------------------------------------------------------------------+
//|                                                Inst_Concepts.mqh |
//|          Institutional Concepts (Breakers, Macro, AMD, Wyckoff)   |
//|                                  Copyright 2026, Infernal Portfolio Governor   |
//+------------------------------------------------------------------+
#ifndef INST_CONCEPTS_MQH
#define INST_CONCEPTS_MQH

#property copyright "Infernal Portfolio Governor"
#property strict

//+------------------------------------------------------------------+
//| CHoCH — Change of Character (replaces simplified Breaker Blocks) |
//| Detects confirmed structural break: a bar that CLOSES beyond     |
//| the last validated swing point, or a retest of the broken level. |
//+------------------------------------------------------------------+
class CBreakerBlocks
{
public:
   double GetBreakerScore(int direction, double atr)
   {
      int lookback = 20;

      if(direction == 1) // Bullish CHoCH: last closed bar closed ABOVE recent swing high
      {
         // Skip bar 0 (forming) and bar 1 (the closed trigger bar); look for swing from bar 2+
         int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 2);
         if(highestBar < 0) return 0.0;
         double swingHigh  = iHigh(_Symbol, PERIOD_CURRENT, highestBar);
         double lastClose  = iClose(_Symbol, PERIOD_CURRENT, 1); // last confirmed closed bar

         // Confirmed CHoCH: closed above the swing high
         if(lastClose > swingHigh) return 1.0;

         // Retest: price is testing the broken level from above (second-chance entry)
         double currPrice  = iClose(_Symbol, PERIOD_CURRENT, 0);
         double tolerance  = atr * 0.30;
         if(currPrice >= swingHigh - tolerance && currPrice <= swingHigh + tolerance &&
            lastClose > swingHigh)
            return 0.7;
      }
      else // Bearish CHoCH: last closed bar closed BELOW recent swing low
      {
         int lowestBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 2);
         if(lowestBar < 0) return 0.0;
         double swingLow   = iLow(_Symbol, PERIOD_CURRENT, lowestBar);
         double lastClose  = iClose(_Symbol, PERIOD_CURRENT, 1);

         if(lastClose < swingLow) return 1.0;

         double currPrice  = iClose(_Symbol, PERIOD_CURRENT, 0);
         double tolerance  = atr * 0.30;
         if(currPrice >= swingLow - tolerance && currPrice <= swingLow + tolerance &&
            lastClose < swingLow)
            return 0.7;
      }

      return 0.0;
   }
};

//+------------------------------------------------------------------+
//| Macro Windows — uses live killzone state instead of hardcoded    |
//| UTC hours. If an active killzone is open we are inside a         |
//| high-probability institutional time window.                      |
//+------------------------------------------------------------------+
class CMacroWindows
{
public:
   double GetMacroScore(bool kzActive = false)
   {
      return kzActive ? 0.5 : 0.0;
   }
};

//+------------------------------------------------------------------+
//| Session Phase Score (AMD — replaces stub Power of 3)             |
//| Detects ICT Accumulation → Manipulation → Distribution pattern:  |
//|  Accumulation: 3+ small-body bars (range compression)            |
//|  Manipulation: impulse bar (displacement) after compression      |
//| Only meaningful inside an active killzone session.               |
//+------------------------------------------------------------------+
class CPowerOf3
{
public:
   double GetPhaseScore(double atr, bool kzActive = false)
   {
      if(!kzActive) return 0.0; // AMD only meaningful in active session window

      if(atr <= 0) return 0.0;

      // Step 1: Confirm accumulation phase — 3 prior closed bars all small-body
      bool accumulated = true;
      for(int i = 2; i <= 4; i++) // bars 2,3,4 (all fully closed)
      {
         double o = iOpen(_Symbol,  PERIOD_CURRENT, i);
         double c = iClose(_Symbol, PERIOD_CURRENT, i);
         if(MathAbs(c - o) > atr * 0.45) { accumulated = false; break; }
      }
      if(!accumulated) return 0.0;

      // Step 2: Confirm displacement on last closed bar (manipulation/distribution)
      double lastO = iOpen(_Symbol,  PERIOD_CURRENT, 1);
      double lastC = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(MathAbs(lastC - lastO) >= atr * 0.90)
         return 0.8; // AMD in-session confirmed

      return 0.0;
   }
};

//+------------------------------------------------------------------+
//| Wyckoff Analysis (Springs/Upthrusts)                             |
//+------------------------------------------------------------------+
class CWyckoff
{
public:
   double GetWyckoffScore(int direction, double atr)
   {
      // Spring: Price dips below support (swing low) and closes back above (Pinbar/Hammer)
      
      int swingBars = 30;
      
      if(direction == 1) // Check for Spring (Buy)
      {
         int lowest = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, swingBars, 1);
         if(lowest < 0) return 0.0;
         double swingLow = iLow(_Symbol, PERIOD_CURRENT, lowest);
         
         double currLow = iLow(_Symbol, PERIOD_CURRENT, 0);
         double currClose = iClose(_Symbol, PERIOD_CURRENT, 0);
         
         // Pinbar check: Long lower wick
         double bodyHigh = MathMax(iOpen(_Symbol, PERIOD_CURRENT, 0), iClose(_Symbol, PERIOD_CURRENT, 0));
         double lowerWick = bodyHigh - currLow;
         
         // Did we sweep the low?
         bool sweep = (currLow < swingLow - (atr * 0.1)); 
         // Did we close back up?
         bool rejection = (currClose > swingLow) && (lowerWick > atr * 0.5);
         
         if(sweep && rejection) return 0.5;
      }
      else // Check for Upthrust (Sell)
      {
         int highest = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, swingBars, 1);
         if(highest < 0) return 0.0;
         double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, highest);
         
         double currHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
         double currClose = iClose(_Symbol, PERIOD_CURRENT, 0);
         
         // Pinbar check: Long upper wick
         double bodyLow = MathMin(iOpen(_Symbol, PERIOD_CURRENT, 0), iClose(_Symbol, PERIOD_CURRENT, 0));
         double upperWick = currHigh - bodyLow;
         
         // Did we sweep the high?
         bool sweep = (currHigh > swingHigh + (atr * 0.1));
         // Did we close back down?
         bool rejection = (currClose < swingHigh) && (upperWick > atr * 0.5);
         
         if(sweep && rejection) return 0.5;
      }

      return 0.0;
   }
};

//+------------------------------------------------------------------+
//| Currency Strength                                                |
//+------------------------------------------------------------------+
class CCurrencyStrength
{
public:
   double GetConfluenceScore(string symbol, int direction)
   {
      return 0.0; // Still hard without multicurrency driver
   }
};

#endif
