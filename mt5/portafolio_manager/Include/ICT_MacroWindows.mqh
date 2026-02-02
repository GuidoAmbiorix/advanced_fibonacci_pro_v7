//+------------------------------------------------------------------+
//|                                       ICT_MacroWindows.mqh       |
//|                    ICT Macro Time Windows Module                  |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Macro Window Types                                               |
//+------------------------------------------------------------------+
enum ENUM_MACRO_WINDOW
{
   MACRO_NONE = 0,          // Outside macro windows
   MACRO_LONDON = 1,        // London Macro (02:00-05:00 EST)
   MACRO_NY_AM = 2,         // NY AM Macro (08:00-11:00 EST)
   MACRO_SILVER_BULLET = 3  // Silver Bullet (13:30-16:00 EST) - PRIME
};

//+------------------------------------------------------------------+
//| ICT Macro Windows Class                                          |
//+------------------------------------------------------------------+
class CICTMacroWindows
{
private:
   string            m_symbol;
   bool              m_useDST;              // Daylight Saving Time adjustment

   // Macro windows in broker time (will be adjusted)
   int               m_londonStart;         // London Macro start hour
   int               m_londonEnd;           // London Macro end hour
   int               m_nyAmStart;           // NY AM start hour
   int               m_nyAmEnd;             // NY AM end hour
   int               m_silverStart;         // Silver Bullet start hour
   int               m_silverStartMin;      // Silver Bullet start minute
   int               m_silverEnd;           // Silver Bullet end hour

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CICTMacroWindows()
   {
      m_useDST = true;
      InitializeMacroTimes();
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, bool useDST = true)
   {
      m_symbol = symbol;
      m_useDST = useDST;
      InitializeMacroTimes();
   }

   //+------------------------------------------------------------------+
   //| Initialize Macro Time Windows (EST to Broker Time)              |
   //+------------------------------------------------------------------+
   void InitializeMacroTimes()
   {
      // Get broker's GMT offset
      int brokerGMT = (int)(TimeGMTOffset() / 3600);

      // EST is GMT-5 (or GMT-4 during DST)
      int estOffset = m_useDST ? -4 : -5;
      int adjustment = brokerGMT - estOffset;

      // London Macro: 02:00-05:00 EST
      m_londonStart = 2 + adjustment;
      m_londonEnd = 5 + adjustment;

      // NY AM Macro: 08:00-11:00 EST
      m_nyAmStart = 8 + adjustment;
      m_nyAmEnd = 11 + adjustment;

      // Silver Bullet: 13:30-16:00 EST
      m_silverStart = 13 + adjustment;
      m_silverStartMin = 30;
      m_silverEnd = 16 + adjustment;

      // Handle wraparound (24-hour clock)
      if(m_londonStart < 0) m_londonStart += 24;
      if(m_londonEnd < 0) m_londonEnd += 24;
      if(m_nyAmStart < 0) m_nyAmStart += 24;
      if(m_nyAmEnd < 0) m_nyAmEnd += 24;
      if(m_silverStart < 0) m_silverStart += 24;
      if(m_silverEnd < 0) m_silverEnd += 24;

      if(m_londonStart >= 24) m_londonStart -= 24;
      if(m_londonEnd >= 24) m_londonEnd -= 24;
      if(m_nyAmStart >= 24) m_nyAmStart -= 24;
      if(m_nyAmEnd >= 24) m_nyAmEnd -= 24;
      if(m_silverStart >= 24) m_silverStart -= 24;
      if(m_silverEnd >= 24) m_silverEnd -= 24;
   }

   //+------------------------------------------------------------------+
   //| Get Current Macro Window                                        |
   //+------------------------------------------------------------------+
   ENUM_MACRO_WINDOW GetCurrentMacroWindow()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      int hour = dt.hour;
      int minute = dt.min;

      // Check Silver Bullet (highest priority)
      if(IsInTimeRange(hour, minute, m_silverStart, m_silverStartMin, m_silverEnd, 0))
         return MACRO_SILVER_BULLET;

      // Check NY AM
      if(IsInTimeRange(hour, minute, m_nyAmStart, 0, m_nyAmEnd, 0))
         return MACRO_NY_AM;

      // Check London
      if(IsInTimeRange(hour, minute, m_londonStart, 0, m_londonEnd, 0))
         return MACRO_LONDON;

      return MACRO_NONE;
   }

   //+------------------------------------------------------------------+
   //| Helper: Check if current time is in range                       |
   //+------------------------------------------------------------------+
   bool IsInTimeRange(int hour, int minute, int startHour, int startMin, int endHour, int endMin)
   {
      int currentMinutes = hour * 60 + minute;
      int startMinutes = startHour * 60 + startMin;
      int endMinutes = endHour * 60 + endMin;

      // Handle wraparound (e.g., 23:00 to 02:00)
      if(endMinutes < startMinutes)
      {
         return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
      }
      else
      {
         return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
      }
   }

   //+------------------------------------------------------------------+
   //| Get Macro Score (0-1.5 points)                                  |
   //+------------------------------------------------------------------+
   double GetMacroScore()
   {
      ENUM_MACRO_WINDOW window = GetCurrentMacroWindow();

      switch(window)
      {
         case MACRO_SILVER_BULLET:
            return 1.5;  // PRIME window

         case MACRO_NY_AM:
            return 1.0;  // Strong window

         case MACRO_LONDON:
            return 0.8;  // Good window

         case MACRO_NONE:
         default:
            return 0;    // Outside macro windows
      }
   }

   //+------------------------------------------------------------------+
   //| Check if in Silver Bullet window                                |
   //+------------------------------------------------------------------+
   bool IsInSilverBullet()
   {
      return (GetCurrentMacroWindow() == MACRO_SILVER_BULLET);
   }

   //+------------------------------------------------------------------+
   //| Check if in any Macro window                                    |
   //+------------------------------------------------------------------+
   bool IsInMacroWindow()
   {
      return (GetCurrentMacroWindow() != MACRO_NONE);
   }

   //+------------------------------------------------------------------+
   //| Get Macro Window Name                                           |
   //+------------------------------------------------------------------+
   string GetMacroWindowName()
   {
      ENUM_MACRO_WINDOW window = GetCurrentMacroWindow();

      switch(window)
      {
         case MACRO_SILVER_BULLET:
            return "Silver Bullet (13:30-16:00 EST)";

         case MACRO_NY_AM:
            return "NY AM Macro (08:00-11:00 EST)";

         case MACRO_LONDON:
            return "London Macro (02:00-05:00 EST)";

         case MACRO_NONE:
         default:
            return "Outside Macro Windows";
      }
   }

   //+------------------------------------------------------------------+
   //| Get Next Macro Window                                           |
   //+------------------------------------------------------------------+
   string GetNextMacroWindow()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      int hour = dt.hour;
      int minute = dt.min;
      int currentMinutes = hour * 60 + minute;

      // Calculate minutes for each window start
      int londonMinutes = m_londonStart * 60;
      int nyAmMinutes = m_nyAmStart * 60;
      int silverMinutes = m_silverStart * 60 + m_silverStartMin;

      // Find next window
      if(currentMinutes < londonMinutes)
         return StringFormat("London Macro in %d min", londonMinutes - currentMinutes);
      else if(currentMinutes < nyAmMinutes)
         return StringFormat("NY AM Macro in %d min", nyAmMinutes - currentMinutes);
      else if(currentMinutes < silverMinutes)
         return StringFormat("Silver Bullet in %d min", silverMinutes - currentMinutes);
      else
         return "London Macro tomorrow";
   }

   //+------------------------------------------------------------------+
   //| Get Macro Info for Dashboard                                    |
   //+------------------------------------------------------------------+
   string GetMacroInfo()
   {
      string info = "=== ICT MACRO WINDOWS ===\n";

      ENUM_MACRO_WINDOW current = GetCurrentMacroWindow();

      if(current != MACRO_NONE)
      {
         info += "ACTIVE: " + GetMacroWindowName() + "\n";
         info += StringFormat("Score: +%.1f points\n", GetMacroScore());
      }
      else
      {
         info += "Status: Outside macro windows\n";
         info += "Next: " + GetNextMacroWindow() + "\n";
      }

      return info;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   int GetLondonStart() { return m_londonStart; }
   int GetLondonEnd() { return m_londonEnd; }
   int GetNYAmStart() { return m_nyAmStart; }
   int GetNYAmEnd() { return m_nyAmEnd; }
   int GetSilverStart() { return m_silverStart; }
   int GetSilverEnd() { return m_silverEnd; }
};
