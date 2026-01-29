//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh  |
//|          High-Impact News Event Filter                            |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef NEWS_FILTER_MQH
#define NEWS_FILTER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| NEWS IMPACT LEVELS                                                |
//+------------------------------------------------------------------+
enum ENUM_NEWS_IMPACT
{
   NEWS_NONE = 0,
   NEWS_LOW = 1,
   NEWS_MEDIUM = 2,
   NEWS_HIGH = 3
};

//+------------------------------------------------------------------+
//| NEWS EVENT STRUCTURE                                              |
//+------------------------------------------------------------------+
struct NewsEvent
{
   datetime        time;
   string          currency;
   string          name;
   ENUM_NEWS_IMPACT impact;
   bool            isUpcoming;      // Within filter window
};

//+------------------------------------------------------------------+
//| NEWS FILTER MODULE                                                |
//| Responsibility: Pause trading around high-impact news             |
//+------------------------------------------------------------------+
class CNewsFilter
{
private:
   string          m_symbol;
   string          m_baseCurrency;
   string          m_quoteCurrency;

   int             m_minutesBefore;  // Minutes to pause before news
   int             m_minutesAfter;   // Minutes to pause after news
   bool            m_filterEnabled;

   NewsEvent       m_upcomingEvents[];
   datetime        m_lastCalendarCheck;
   int             m_checkIntervalMinutes;

   bool            m_inNewsWindow;
   datetime        m_windowStart;
   datetime        m_windowEnd;
   string          m_currentEventName;

   // FLASH CRASH / VOLATILITY SPIKE DETECTION
   bool            m_enableVolatilityFilter;
   double          m_volatilityThreshold;      // ATR multiplier for spike detection
   bool            m_inVolatilitySpike;
   datetime        m_spikeStartTime;
   int             m_spikeCooldownMinutes;
   int             m_hATR_M1;                   // 1-minute ATR for spike detection
   int             m_hATR_H1;                   // 1-hour ATR for baseline
   datetime        m_lastVolatilityCheck;

public:
   CNewsFilter() : m_minutesBefore(30), m_minutesAfter(30),
                   m_filterEnabled(true), m_checkIntervalMinutes(15),
                   m_inNewsWindow(false),
                   m_enableVolatilityFilter(true), m_volatilityThreshold(3.0),
                   m_inVolatilitySpike(false), m_spikeCooldownMinutes(15),
                   m_hATR_M1(INVALID_HANDLE), m_hATR_H1(INVALID_HANDLE),
                   m_lastVolatilityCheck(0) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, int minutesBefore = 30, int minutesAfter = 30,
             bool enabled = true)
   {
      m_symbol = symbol;
      m_minutesBefore = minutesBefore;
      m_minutesAfter = minutesAfter;
      m_filterEnabled = enabled;

      // Extract currencies from symbol
      ExtractCurrencies();

      // Initial calendar check
      m_lastCalendarCheck = 0;
      UpdateCalendar();

      // Initialize volatility spike detection
      if(m_enableVolatilityFilter)
      {
         m_hATR_M1 = iATR(m_symbol, PERIOD_M1, 14);
         m_hATR_H1 = iATR(m_symbol, PERIOD_H1, 14);

         if(m_hATR_M1 == INVALID_HANDLE || m_hATR_H1 == INVALID_HANDLE)
         {
            Print("⚠️ NEWS FILTER: Failed to create volatility indicators - Spike detection disabled");
            m_enableVolatilityFilter = false;
         }
         else
         {
            Print("✅ NEWS FILTER: Volatility spike detection enabled (Threshold: ", m_volatilityThreshold, "x)");
         }
      }

      return true;
   }

   ~CNewsFilter()
   {
      if(m_hATR_M1 != INVALID_HANDLE) IndicatorRelease(m_hATR_M1);
      if(m_hATR_H1 != INVALID_HANDLE) IndicatorRelease(m_hATR_H1);
   }

   //+------------------------------------------------------------------+
   //| Extract base and quote currencies from symbol                     |
   //+------------------------------------------------------------------+
   void ExtractCurrencies()
   {
      string sym = m_symbol;
      StringToUpper(sym);

      // Handle common symbol formats
      // Standard forex: EURUSD, EUR/USD
      // Metals: XAUUSD, GOLD
      // Indices: NAS100, US30

      // Remove common suffixes
      StringReplace(sym, ".PRO", "");
      StringReplace(sym, ".STD", "");
      StringReplace(sym, "_SB", "");
      StringReplace(sym, "/", "");

      // Standard 6-char forex pairs
      if(StringLen(sym) >= 6)
      {
         m_baseCurrency = StringSubstr(sym, 0, 3);
         m_quoteCurrency = StringSubstr(sym, 3, 3);
      }

      // Handle metals
      if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
      {
         m_baseCurrency = "XAU";
         m_quoteCurrency = "USD";
      }
      if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
      {
         m_baseCurrency = "XAG";
         m_quoteCurrency = "USD";
      }

      // Handle indices - focus on USD news
      if(StringFind(sym, "NAS") >= 0 || StringFind(sym, "US30") >= 0 ||
         StringFind(sym, "SP500") >= 0 || StringFind(sym, "US500") >= 0 ||
         StringFind(sym, "USTEC") >= 0)
      {
         m_baseCurrency = "USD";
         m_quoteCurrency = "USD";
      }
   }

   //+------------------------------------------------------------------+
   //| Update - Call periodically                                        |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(!m_filterEnabled) return;

      // Check if we need to refresh calendar (every 5 min instead of 15)
      if(TimeCurrent() - m_lastCalendarCheck >= 300) // 5 minutes
      {
         UpdateCalendar();
         m_lastCalendarCheck = TimeCurrent();
      }

      // Check if currently in news window
      CheckNewsWindow();

      // Check for volatility spikes (every 10 seconds)
      if(m_enableVolatilityFilter && TimeCurrent() - m_lastVolatilityCheck >= 10)
      {
         CheckVolatilitySpike();
         m_lastVolatilityCheck = TimeCurrent();
      }
   }

   //+------------------------------------------------------------------+
   //| Update calendar from MT5 Economic Calendar                        |
   //+------------------------------------------------------------------+
   void UpdateCalendar()
   {
      ArrayResize(m_upcomingEvents, 0);

      datetime now = TimeCurrent();
      datetime lookAhead = now + 86400;  // Look 24 hours ahead

      // Get calendar values from MT5
      MqlCalendarValue values[];
      int count = CalendarValueHistory(values, now - 3600, lookAhead);

      if(count <= 0) return;

      for(int i = 0; i < count; i++)
      {
         // Get event details
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event)) continue;

         // Get country info
         MqlCalendarCountry country;
         if(!CalendarCountryById(event.country_id, country)) continue;

         string currency = country.currency;
         StringToUpper(currency);

         // Check if this currency affects our symbol
         if(currency != m_baseCurrency && currency != m_quoteCurrency) continue;

         // Check impact level
         ENUM_NEWS_IMPACT impact = NEWS_NONE;
         if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            impact = NEWS_HIGH;
         else if(event.importance == CALENDAR_IMPORTANCE_MODERATE)
            impact = NEWS_MEDIUM;
         else if(event.importance == CALENDAR_IMPORTANCE_LOW)
            impact = NEWS_LOW;

         // Only track medium and high impact
         if(impact < NEWS_MEDIUM) continue;

         // Add to upcoming events
         int size = ArraySize(m_upcomingEvents);
         ArrayResize(m_upcomingEvents, size + 1);

         m_upcomingEvents[size].time = values[i].time;
         m_upcomingEvents[size].currency = currency;
         m_upcomingEvents[size].name = event.name;
         m_upcomingEvents[size].impact = impact;
         m_upcomingEvents[size].isUpcoming = true;
      }
   }

   //+------------------------------------------------------------------+
   //| Check if currently in news window                                 |
   //+------------------------------------------------------------------+
   void CheckNewsWindow()
   {
      m_inNewsWindow = false;
      datetime now = TimeCurrent();

      for(int i = 0; i < ArraySize(m_upcomingEvents); i++)
      {
         datetime eventTime = m_upcomingEvents[i].time;
         datetime windowStart = eventTime - m_minutesBefore * 60;
         datetime windowEnd = eventTime + m_minutesAfter * 60;

         if(now >= windowStart && now <= windowEnd)
         {
            m_inNewsWindow = true;
            m_windowStart = windowStart;
            m_windowEnd = windowEnd;
            m_currentEventName = m_upcomingEvents[i].currency + ": " +
                                 m_upcomingEvents[i].name;

            // High impact gets priority
            if(m_upcomingEvents[i].impact == NEWS_HIGH)
               break;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check for sudden volatility spikes (Flash Crash Detection)        |
   //+------------------------------------------------------------------+
   void CheckVolatilitySpike()
   {
      if(m_hATR_M1 == INVALID_HANDLE || m_hATR_H1 == INVALID_HANDLE)
      {
         m_inVolatilitySpike = false;
         return;
      }

      // Get current M1 ATR (short-term volatility)
      double atrM1Buffer[1];
      if(CopyBuffer(m_hATR_M1, 0, 0, 1, atrM1Buffer) != 1)
      {
         m_inVolatilitySpike = false;
         return;
      }

      // Get H1 ATR (baseline/normal volatility)
      double atrH1Buffer[1];
      if(CopyBuffer(m_hATR_H1, 0, 0, 1, atrH1Buffer) != 1)
      {
         m_inVolatilitySpike = false;
         return;
      }

      double currentVolatility = atrM1Buffer[0];
      double normalVolatility = atrH1Buffer[0];

      // Prevent division by zero
      if(normalVolatility <= 0)
      {
         m_inVolatilitySpike = false;
         return;
      }

      // Calculate volatility ratio
      double volatilityRatio = currentVolatility / normalVolatility;

      // SPIKE DETECTED: M1 ATR is X times higher than H1 ATR
      if(volatilityRatio >= m_volatilityThreshold)
      {
         if(!m_inVolatilitySpike)
         {
            m_inVolatilitySpike = true;
            m_spikeStartTime = TimeCurrent();

            Print("🚨 VOLATILITY SPIKE DETECTED: ", m_symbol,
                  " | M1 ATR: ", DoubleToString(currentVolatility, 5),
                  " | H1 ATR: ", DoubleToString(normalVolatility, 5),
                  " | Ratio: ", DoubleToString(volatilityRatio, 2), "x",
                  " | Trading BLOCKED for ", m_spikeCooldownMinutes, " minutes");
         }
      }
      // SPIKE ENDED: Check cooldown period
      else if(m_inVolatilitySpike)
      {
         int minutesSinceSpike = (int)((TimeCurrent() - m_spikeStartTime) / 60);

         if(minutesSinceSpike >= m_spikeCooldownMinutes)
         {
            m_inVolatilitySpike = false;
            Print("✅ VOLATILITY NORMALIZED: ", m_symbol, " | Trading resumed");
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check if trading is allowed (no news window or volatility spike)  |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      if(!m_filterEnabled) return true;

      // Block if in scheduled news window
      if(m_inNewsWindow) return false;

      // Block if in volatility spike
      if(m_enableVolatilityFilter && m_inVolatilitySpike) return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get time until next news event                                    |
   //+------------------------------------------------------------------+
   int GetMinutesToNextNews()
   {
      datetime now = TimeCurrent();
      int minMinutes = 999999;

      for(int i = 0; i < ArraySize(m_upcomingEvents); i++)
      {
         if(m_upcomingEvents[i].time > now)
         {
            int minutes = (int)((m_upcomingEvents[i].time - now) / 60);
            if(minutes < minMinutes) minMinutes = minutes;
         }
      }

      return minMinutes;
   }

   //+------------------------------------------------------------------+
   //| Get next news event info                                          |
   //+------------------------------------------------------------------+
   bool GetNextNewsEvent(datetime &eventTime, string &eventName, ENUM_NEWS_IMPACT &impact)
   {
      datetime now = TimeCurrent();
      datetime nearestTime = D'2100.01.01';
      int nearestIdx = -1;

      for(int i = 0; i < ArraySize(m_upcomingEvents); i++)
      {
         if(m_upcomingEvents[i].time > now && m_upcomingEvents[i].time < nearestTime)
         {
            nearestTime = m_upcomingEvents[i].time;
            nearestIdx = i;
         }
      }

      if(nearestIdx >= 0)
      {
         eventTime = m_upcomingEvents[nearestIdx].time;
         eventName = m_upcomingEvents[nearestIdx].currency + ": " +
                     m_upcomingEvents[nearestIdx].name;
         impact = m_upcomingEvents[nearestIdx].impact;
         return true;
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get risk multiplier based on news proximity and volatility        |
   //+------------------------------------------------------------------+
   double GetNewsRiskMultiplier()
   {
      if(!m_filterEnabled) return 1.0;

      // If in news window, should not trade (return 0)
      if(m_inNewsWindow) return 0.0;

      // If in volatility spike, should not trade (return 0)
      if(m_enableVolatilityFilter && m_inVolatilitySpike) return 0.0;

      // Reduce risk as news approaches
      int minutesToNews = GetMinutesToNextNews();

      if(minutesToNews <= m_minutesBefore) return 0.0;       // In buffer zone
      if(minutesToNews <= m_minutesBefore * 2) return 0.5;   // Approaching news
      if(minutesToNews <= m_minutesBefore * 3) return 0.75;  // News nearby

      return 1.0;  // Safe distance from news
   }

   //+------------------------------------------------------------------+
   //| Check for high-impact news specifically                           |
   //+------------------------------------------------------------------+
   bool IsHighImpactNewsNear(int minutesAhead = 60)
   {
      datetime now = TimeCurrent();
      datetime threshold = now + minutesAhead * 60;

      for(int i = 0; i < ArraySize(m_upcomingEvents); i++)
      {
         if(m_upcomingEvents[i].impact == NEWS_HIGH &&
            m_upcomingEvents[i].time <= threshold &&
            m_upcomingEvents[i].time > now)
         {
            return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Enable/Disable filter                                             |
   //+------------------------------------------------------------------+
   void SetEnabled(bool enabled) { m_filterEnabled = enabled; }
   bool IsEnabled() { return m_filterEnabled; }

   //+------------------------------------------------------------------+
   //| Get current status                                                |
   //+------------------------------------------------------------------+
   bool IsInNewsWindow() { return m_inNewsWindow; }
   string GetCurrentEventName() { return m_currentEventName; }

   //+------------------------------------------------------------------+
   //| Get string representation                                         |
   //+------------------------------------------------------------------+
   string ToString()
   {
      if(!m_filterEnabled) return "NEWS: OFF";

      // Priority 1: Volatility spike (most critical)
      if(m_enableVolatilityFilter && m_inVolatilitySpike)
      {
         int minutesSinceSpike = (int)((TimeCurrent() - m_spikeStartTime) / 60);
         int remaining = m_spikeCooldownMinutes - minutesSinceSpike;
         return "🚨 VOLATILITY SPIKE! BLOCKED (" + IntegerToString(remaining) + "m cooldown)";
      }

      // Priority 2: Scheduled news
      if(m_inNewsWindow)
         return "NEWS: BLOCKED (" + m_currentEventName + ")";

      // Priority 3: Upcoming news
      int minToNews = GetMinutesToNextNews();
      if(minToNews < 999999)
         return "NEWS: OK (Next: " + IntegerToString(minToNews) + "m)";

      return "NEWS: CLEAR";
   }

   //+------------------------------------------------------------------+
   //| Get upcoming events count                                         |
   //+------------------------------------------------------------------+
   int GetUpcomingEventsCount() { return ArraySize(m_upcomingEvents); }

   //+------------------------------------------------------------------+
   //| Volatility Spike Getters/Setters                                  |
   //+------------------------------------------------------------------+
   bool IsInVolatilitySpike() { return m_inVolatilitySpike; }

   void SetVolatilityThreshold(double threshold)
   {
      if(threshold > 0)
      {
         m_volatilityThreshold = threshold;
         Print("📊 NEWS FILTER: Volatility threshold set to ", threshold, "x");
      }
   }

   double GetVolatilityThreshold() { return m_volatilityThreshold; }

   void SetVolatilityCooldown(int minutes)
   {
      if(minutes > 0)
      {
         m_spikeCooldownMinutes = minutes;
         Print("⏱️ NEWS FILTER: Spike cooldown set to ", minutes, " minutes");
      }
   }

   void EnableVolatilityFilter(bool enable)
   {
      m_enableVolatilityFilter = enable;
      Print(enable ? "✅ Volatility spike detection enabled" : "❌ Volatility spike detection disabled");
   }

   bool IsVolatilityFilterEnabled() { return m_enableVolatilityFilter; }
};

#endif
