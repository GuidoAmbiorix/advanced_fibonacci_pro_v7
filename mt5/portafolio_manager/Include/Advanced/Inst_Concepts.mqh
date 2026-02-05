//+------------------------------------------------------------------+
//|                                                Inst_Concepts.mqh |
//|          Institutional Concepts (Breakers, Macro, AMD, Wyckoff)   |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef INST_CONCEPTS_MQH
#define INST_CONCEPTS_MQH

#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Breaker Blocks                                                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Breaker Blocks (Simplified: Structure Retest)                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Breaker Blocks (Simplified: Structure Retest)                    |
//+------------------------------------------------------------------+
class CBreakerBlocks
{
public:
   double GetBreakerScore(int direction, double atr)
   {
      // LOGIC: Did we break a swing, then return to it?
      // Use iHighest/iLowest to find recent structure
      int swingLookback = 20;
      int highest = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, swingLookback, 5);
      int lowest = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, swingLookback, 5);
      
      if(highest < 0 || lowest < 0) return 0.0;
      
      double highVal = iHigh(_Symbol, PERIOD_CURRENT, highest);
      double lowVal = iLow(_Symbol, PERIOD_CURRENT, lowest);
      double currPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
      
      // Bearish Breaker: Price broke BELOW a Low, then returned UP to it?
      // Proxy: Price is near recent High (Support turned Res) or Low (Res turned Support)
      
      double tolerance = atr * 0.5;
      
      if(direction == 1) // Buy: Retesting old High (Bullish Breaker)
      {
         // Check if we are near the recent high
         if(MathAbs(currPrice - highVal) < tolerance) return 0.5;
      }
      else // Sell: Retesting old Low (Bearish Breaker)
      {
         // Check if we are near the recent low
         if(MathAbs(currPrice - lowVal) < tolerance) return 0.5;
      }

      return 0.0; 
   }
};

//+------------------------------------------------------------------+
//| Macro Windows                                                    |
//+------------------------------------------------------------------+
class CMacroWindows
{
public:
   double GetMacroScore()
   {
      // Silver Bullet Windows (NY Time)
      // 10:00 - 11:00 AM (London Close/NY AM)
      // 03:00 - 04:00 PM (NY PM)
      
      MqlDateTime dt;
      TimeCurrent(dt);
      
      // Assuming Server Time is UTC+2 or similar (offset required)
      // Lets check generic "Volatile Hours": 8-11 and 13-16 Server time roughly
      if((dt.hour >= 9 && dt.hour <= 11) || (dt.hour >= 15 && dt.hour <= 17))
      {
         return 0.5; // Active window bonus
      }
      return 0.0;
   }
};

//+------------------------------------------------------------------+
//| Power Of 3 (Accumulation-Manipulation-Distribution)              |
//+------------------------------------------------------------------+
class CPowerOf3
{
public:
   double GetPhaseScore(double atr)
   {
      // Logic: Low Volatility (Accumulation) -> Impulse (Manipulation/Exp)
      // AMD Proxy: High relative volume + Large range bar = Expansion/Manipulation phase
      
      // Simple Proxy: Do we have a breakout bar?
      double open = iOpen(_Symbol, PERIOD_CURRENT, 0);
      double close = iClose(_Symbol, PERIOD_CURRENT, 0);
      double body = MathAbs(close - open);
      
      if(body > atr * 0.8) // Large body
      {
         return 0.5; 
      }
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
