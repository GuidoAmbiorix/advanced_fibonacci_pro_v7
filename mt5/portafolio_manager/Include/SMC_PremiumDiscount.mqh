//+------------------------------------------------------------------+
//|                                      SMC_PremiumDiscount.mqh      |
//|          Premium/Discount Zone Classification                     |
//|                                  Copyright 2026, Guido Ambiorix  |
//+------------------------------------------------------------------+
#ifndef SMC_PREMIUM_DISCOUNT_MQH
#define SMC_PREMIUM_DISCOUNT_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| ZONE TYPE                                                         |
//+------------------------------------------------------------------+
enum ENUM_PRICE_ZONE
{
   ZONE_UNKNOWN = 0,
   ZONE_DEEP_DISCOUNT = 1,    // 0-25% (extreme buy zone)
   ZONE_DISCOUNT = 2,         // 25-50% (buy zone)
   ZONE_EQUILIBRIUM = 3,      // 45-55% (neutral zone)
   ZONE_PREMIUM = 4,          // 50-75% (sell zone)
   ZONE_DEEP_PREMIUM = 5      // 75-100% (extreme sell zone)
};

//+------------------------------------------------------------------+
//| PREMIUM/DISCOUNT ANALYZER                                         |
//+------------------------------------------------------------------+
class CSMCPremiumDiscount
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_swingLookback;
   
   double            m_swingHigh;
   double            m_swingLow;
   double            m_equilibrium;
   double            m_currentZonePct;  // 0-100
   ENUM_PRICE_ZONE   m_currentZone;

public:
   CSMCPremiumDiscount() : m_swingLookback(50), m_swingHigh(0),
                           m_swingLow(0), m_equilibrium(0),
                           m_currentZonePct(50), m_currentZone(ZONE_EQUILIBRIUM) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int swingLookback = 50)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_swingLookback = swingLookback;
      
      Update();
      
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update - Call on new bar                                         |
   //+------------------------------------------------------------------+
   void Update()
   {
      // Find recent swing high/low
      int highBar = iHighest(m_symbol, m_timeframe, MODE_HIGH, m_swingLookback, 1);
      int lowBar = iLowest(m_symbol, m_timeframe, MODE_LOW, m_swingLookback, 1);
      
      if(highBar >= 0 && lowBar >= 0)
      {
         m_swingHigh = iHigh(m_symbol, m_timeframe, highBar);
         m_swingLow = iLow(m_symbol, m_timeframe, lowBar);
         m_equilibrium = (m_swingHigh + m_swingLow) / 2.0;
         
         // Calculate current price position
         double currentPrice = iClose(m_symbol, m_timeframe, 0);
         double range = m_swingHigh - m_swingLow;
         
         if(range > 0)
         {
            m_currentZonePct = ((currentPrice - m_swingLow) / range) * 100.0;
            
            // Classify zone
            if(m_currentZonePct < 25)
               m_currentZone = ZONE_DEEP_DISCOUNT;
            else if(m_currentZonePct < 45)
               m_currentZone = ZONE_DISCOUNT;
            else if(m_currentZonePct <= 55)
               m_currentZone = ZONE_EQUILIBRIUM;
            else if(m_currentZonePct <= 75)
               m_currentZone = ZONE_PREMIUM;
            else
               m_currentZone = ZONE_DEEP_PREMIUM;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score                                             |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;
      
      // BUY signals should be in DISCOUNT zones
      if(direction == 1)
      {
         if(m_currentZone == ZONE_DEEP_DISCOUNT)
            score = 1.0;  // Ideal buy zone
         else if(m_currentZone == ZONE_DISCOUNT)
            score = 0.7;  // Good buy zone
         else if(m_currentZone == ZONE_EQUILIBRIUM)
            score= 0.3;   // Neutral
         // Premium zones = 0 for buys
      }
      // SELL signals should be in PREMIUM zones
      else if(direction == -1)
      {
         if(m_currentZone == ZONE_DEEP_PREMIUM)
            score = 1.0;  // Ideal sell zone
         else if(m_currentZone == ZONE_PREMIUM)
            score = 0.7;  // Good sell zone
         else if(m_currentZone == ZONE_EQUILIBRIUM)
            score = 0.3;  // Neutral
         // Discount zones = 0 for sells
      }
      
      return score;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                           |
   //+------------------------------------------------------------------+
   ENUM_PRICE_ZONE GetCurrentZone() { return m_currentZone; }
   double GetZonePercentage() { return m_currentZonePct; }
   double GetEquilibrium() { return m_equilibrium; }
   
   //+------------------------------------------------------------------+
   //| Is Price in Discount                                             |
   //+------------------------------------------------------------------+
   bool IsInDiscount()
   {
      return (m_currentZone == ZONE_DISCOUNT || m_currentZone == ZONE_DEEP_DISCOUNT);
   }
   
   //+------------------------------------------------------------------+
   //| Is Price in Premium                                              |
   //+------------------------------------------------------------------+
   bool IsInPremium()
   {
      return (m_currentZone == ZONE_PREMIUM || m_currentZone == ZONE_DEEP_PREMIUM);
   }

   //+------------------------------------------------------------------+
   //| String Representation                                            |
   //+------------------------------------------------------------------+
   string ToString()
   {
      string zone = "UNKNOWN";
      switch(m_currentZone)
      {
         case ZONE_DEEP_DISCOUNT: zone = "DEEP DISCOUNT"; break;
         case ZONE_DISCOUNT: zone = "DISCOUNT"; break;
         case ZONE_EQUILIBRIUM: zone = "EQUILIBRIUM"; break;
         case ZONE_PREMIUM: zone = "PREMIUM"; break;
         case ZONE_DEEP_PREMIUM: zone = "DEEP PREMIUM"; break;
      }
      
      return zone + " (" + DoubleToString(m_currentZonePct, 0) + "%)";
   }
};

#endif
