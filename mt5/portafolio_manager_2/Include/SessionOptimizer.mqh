//+------------------------------------------------------------------+
//|                                            SessionOptimizer.mqh  |
//|          Trading Session Optimization                             |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef SESSION_OPTIMIZER_MQH
#define SESSION_OPTIMIZER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| TRADING SESSIONS                                                  |
//+------------------------------------------------------------------+
enum ENUM_TRADING_SESSION
{
   SESSION_NONE = 0,
   SESSION_ASIAN = 1,
   SESSION_LONDON = 2,
   SESSION_NEW_YORK = 3,
   SESSION_LONDON_NY_OVERLAP = 4,  // Prime time
   SESSION_ASIAN_LONDON_OVERLAP = 5
};

//+------------------------------------------------------------------+
//| SESSION QUALITY                                                   |
//+------------------------------------------------------------------+
enum ENUM_SESSION_QUALITY
{
   SQ_POOR = 0,       // Asian only, low volume
   SQ_FAIR = 1,       // Single session
   SQ_GOOD = 2,       // Active session
   SQ_PRIME = 3       // Overlap periods
};

//+------------------------------------------------------------------+
//| SESSION OPTIMIZER MODULE                                          |
//| Responsibility: Optimize trading for best session times           |
//+------------------------------------------------------------------+
class CSessionOptimizer
{
private:
   string          m_symbol;
   int             m_brokerUTCOffset;

   // Session times in UTC
   int             m_asianStart;      // Default: 00:00
   int             m_asianEnd;        // Default: 09:00
   int             m_londonStart;     // Default: 07:00
   int             m_londonEnd;       // Default: 16:00
   int             m_nyStart;         // Default: 12:00
   int             m_nyEnd;           // Default: 21:00

   ENUM_TRADING_SESSION m_currentSession;
   ENUM_SESSION_QUALITY m_currentQuality;
   double          m_riskMultiplier;  // Session-based risk adjustment

   bool            m_skipAsian;       // Skip Asian session entirely
   bool            m_focusOverlap;    // Only trade overlaps

public:
   CSessionOptimizer() : m_brokerUTCOffset(0), m_asianStart(0), m_asianEnd(9),
                         m_londonStart(7), m_londonEnd(16), m_nyStart(12), m_nyEnd(21),
                         m_skipAsian(false), m_focusOverlap(false) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, int brokerUTCOffset = 0, bool skipAsian = false,
             bool focusOverlap = false)
   {
      m_symbol = symbol;
      m_brokerUTCOffset = brokerUTCOffset;
      m_skipAsian = skipAsian;
      m_focusOverlap = focusOverlap;

      // Adjust for symbol type
      AdjustSessionsForSymbol();

      return true;
   }

   //+------------------------------------------------------------------+
   //| Adjust session times based on symbol                              |
   //+------------------------------------------------------------------+
   void AdjustSessionsForSymbol()
   {
      string sym = m_symbol;
      StringToUpper(sym);

      // Metals (XAUUSD, XAGUSD) - most active during NY/London overlap
      if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "XAG") >= 0 ||
         StringFind(sym, "GOLD") >= 0 || StringFind(sym, "SILVER") >= 0)
      {
         // Gold trades 23 hours, but most volume in NY session
         m_asianStart = 0;
         m_asianEnd = 7;
         m_londonStart = 7;
         m_londonEnd = 16;
         m_nyStart = 12;
         m_nyEnd = 21;
      }

      // JPY pairs - more active in Asian session
      if(StringFind(sym, "JPY") >= 0)
      {
         m_asianStart = 0;
         m_asianEnd = 9;
         // Tokyo-London overlap is also good
      }

      // US indices - focus on NY session
      if(StringFind(sym, "NAS") >= 0 || StringFind(sym, "US30") >= 0 ||
         StringFind(sym, "SP500") >= 0 || StringFind(sym, "USTEC") >= 0)
      {
         m_nyStart = 13;  // After US market open
         m_nyEnd = 20;    // Before close
      }
   }

   //+------------------------------------------------------------------+
   //| Update - Call to refresh current session                          |
   //+------------------------------------------------------------------+
   void Update()
   {
      DetermineCurrentSession();
      CalculateQuality();
      CalculateRiskMultiplier();
   }

   //+------------------------------------------------------------------+
   //| Determine current trading session                                 |
   //+------------------------------------------------------------------+
   void DetermineCurrentSession()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Convert to UTC
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;

      // Check for overlaps first (highest priority)
      bool inLondon = (utcHour >= m_londonStart && utcHour < m_londonEnd);
      bool inNY = (utcHour >= m_nyStart && utcHour < m_nyEnd);
      bool inAsian = (utcHour >= m_asianStart && utcHour < m_asianEnd);

      // London-NY overlap (13:00-16:00 UTC typically)
      if(inLondon && inNY)
      {
         m_currentSession = SESSION_LONDON_NY_OVERLAP;
         return;
      }

      // Asian-London overlap (07:00-09:00 UTC)
      if(inAsian && inLondon)
      {
         m_currentSession = SESSION_ASIAN_LONDON_OVERLAP;
         return;
      }

      // Single sessions
      if(inLondon)
      {
         m_currentSession = SESSION_LONDON;
         return;
      }

      if(inNY)
      {
         m_currentSession = SESSION_NEW_YORK;
         return;
      }

      if(inAsian)
      {
         m_currentSession = SESSION_ASIAN;
         return;
      }

      m_currentSession = SESSION_NONE;
   }

   //+------------------------------------------------------------------+
   //| Calculate session quality                                         |
   //+------------------------------------------------------------------+
   void CalculateQuality()
   {
      switch(m_currentSession)
      {
         case SESSION_LONDON_NY_OVERLAP:
            m_currentQuality = SQ_PRIME;
            break;

         case SESSION_ASIAN_LONDON_OVERLAP:
            m_currentQuality = SQ_GOOD;
            break;

         case SESSION_LONDON:
         case SESSION_NEW_YORK:
            m_currentQuality = SQ_GOOD;
            break;

         case SESSION_ASIAN:
            m_currentQuality = SQ_FAIR;
            break;

         default:
            m_currentQuality = SQ_POOR;
            break;
      }

      // Check day of week
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Friday afternoon - reduce quality
      if(dt.day_of_week == 5 && dt.hour >= 18)
         m_currentQuality = (ENUM_SESSION_QUALITY)MathMax((int)m_currentQuality - 1, 0);

      // Sunday/Monday early - reduce quality
      if(dt.day_of_week == 0 || (dt.day_of_week == 1 && dt.hour < 7))
         m_currentQuality = SQ_POOR;
   }

   //+------------------------------------------------------------------+
   //| Calculate risk multiplier based on session                        |
   //+------------------------------------------------------------------+
   void CalculateRiskMultiplier()
   {
      switch(m_currentQuality)
      {
         case SQ_PRIME:
            m_riskMultiplier = 1.0;
            break;

         case SQ_GOOD:
            m_riskMultiplier = 0.9;
            break;

         case SQ_FAIR:
            m_riskMultiplier = 0.7;
            break;

         case SQ_POOR:
         default:
            m_riskMultiplier = 0.5;
            break;
      }

      // Additional adjustments
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // First hour of major session - slightly reduced (wait for direction)
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;
      if(utcHour == m_londonStart || utcHour == m_nyStart)
         m_riskMultiplier *= 0.9;

      // Peak overlap hours - boost
      if(m_currentSession == SESSION_LONDON_NY_OVERLAP)
      {
         if(utcHour >= 13 && utcHour <= 15)  // Prime overlap time
            m_riskMultiplier = 1.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Check if trading is allowed                                       |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      if(m_currentSession == SESSION_NONE)
         return false;

      if(m_skipAsian && m_currentSession == SESSION_ASIAN)
         return false;

      if(m_focusOverlap && m_currentSession != SESSION_LONDON_NY_OVERLAP &&
         m_currentSession != SESSION_ASIAN_LONDON_OVERLAP)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if in prime trading time                                    |
   //+------------------------------------------------------------------+
   bool IsPrimeTime()
   {
      return (m_currentSession == SESSION_LONDON_NY_OVERLAP);
   }

   //+------------------------------------------------------------------+
   //| Get hours until next prime time                                   |
   //+------------------------------------------------------------------+
   int GetHoursUntilPrimeTime()
   {
      if(IsPrimeTime()) return 0;

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;

      // Prime time starts at ~13:00 UTC
      int primeStart = 13;

      if(utcHour < primeStart)
         return primeStart - utcHour;
      else
         return (24 - utcHour) + primeStart;  // Next day
   }

   //+------------------------------------------------------------------+
   //| Get confluence score contribution (0-0.5)                         |
   //+------------------------------------------------------------------+
   double GetConfluenceScore()
   {
      switch(m_currentQuality)
      {
         case SQ_PRIME:  return 0.5;
         case SQ_GOOD:   return 0.3;
         case SQ_FAIR:   return 0.1;
         default:        return 0.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Getters                                                           |
   //+------------------------------------------------------------------+
   ENUM_TRADING_SESSION GetCurrentSession() { return m_currentSession; }
   ENUM_SESSION_QUALITY GetCurrentQuality() { return m_currentQuality; }
   double GetRiskMultiplier() { return m_riskMultiplier; }

   //+------------------------------------------------------------------+
   //| Set broker UTC offset                                             |
   //+------------------------------------------------------------------+
   void SetBrokerOffset(int offset) { m_brokerUTCOffset = offset; }

   //+------------------------------------------------------------------+
   //| Get session name                                                  |
   //+------------------------------------------------------------------+
   string GetSessionName()
   {
      switch(m_currentSession)
      {
         case SESSION_ASIAN:              return "ASIAN";
         case SESSION_LONDON:             return "LONDON";
         case SESSION_NEW_YORK:           return "NEW YORK";
         case SESSION_LONDON_NY_OVERLAP:  return "LDN/NY OVERLAP";
         case SESSION_ASIAN_LONDON_OVERLAP: return "ASIA/LDN OVERLAP";
         default:                         return "OFF HOURS";
      }
   }

   //+------------------------------------------------------------------+
   //| Get quality name                                                  |
   //+------------------------------------------------------------------+
   string GetQualityName()
   {
      switch(m_currentQuality)
      {
         case SQ_PRIME:  return "PRIME";
         case SQ_GOOD:   return "GOOD";
         case SQ_FAIR:   return "FAIR";
         default:        return "POOR";
      }
   }

   //+------------------------------------------------------------------+
   //| Get string representation                                         |
   //+------------------------------------------------------------------+
   string ToString()
   {
      return "SESSION: " + GetSessionName() + " (" + GetQualityName() + ") " +
             DoubleToString(m_riskMultiplier * 100, 0) + "%";
   }

   //+------------------------------------------------------------------+
   //| Get estimated spread multiplier based on session                  |
   //+------------------------------------------------------------------+
   double GetExpectedSpreadMultiplier()
   {
      switch(m_currentSession)
      {
         case SESSION_LONDON_NY_OVERLAP:  return 1.0;  // Tightest spreads
         case SESSION_LONDON:             return 1.1;
         case SESSION_NEW_YORK:           return 1.1;
         case SESSION_ASIAN_LONDON_OVERLAP: return 1.2;
         case SESSION_ASIAN:              return 1.5;  // Wider spreads
         default:                         return 2.0;  // Widest spreads
      }
   }

   //+------------------------------------------------------------------+
   //| Check if approaching session close                                |
   //+------------------------------------------------------------------+
   bool IsNearSessionClose()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;

      // Within 1 hour of session end
      if(m_currentSession == SESSION_LONDON && utcHour >= m_londonEnd - 1)
         return true;
      if(m_currentSession == SESSION_NEW_YORK && utcHour >= m_nyEnd - 1)
         return true;
      if(m_currentSession == SESSION_ASIAN && utcHour >= m_asianEnd - 1)
         return true;

      return false;
   }
};

#endif
