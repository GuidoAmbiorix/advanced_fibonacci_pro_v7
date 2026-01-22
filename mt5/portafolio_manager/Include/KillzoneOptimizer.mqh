//+------------------------------------------------------------------+
//|                                           KillzoneOptimizer.mqh  |
//|                    ICT Killzone Trading Optimization              |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef KILLZONE_OPTIMIZER_MQH
#define KILLZONE_OPTIMIZER_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "KillzoneConfig.mqh"

//+------------------------------------------------------------------+
//| KILLZONE OPTIMIZER MODULE                                         |
//| Responsibility: Optimize trading for ICT killzone times           |
//+------------------------------------------------------------------+
class CKillzoneOptimizer
{
private:
   string               m_symbol;
   int                  m_brokerUTCOffset;
   bool                 m_autoDST;            // Auto-adjust for DST

   // Killzone enable/disable flags
   bool                 m_enableAsian;
   bool                 m_enableLondonOpen;
   bool                 m_enableNY;
   bool                 m_enableLondonClose;

   // Current state
   ENUM_KILLZONE        m_currentKillzone;
   ENUM_KILLZONE_QUALITY m_currentQuality;
   double               m_riskMultiplier;     // Killzone-based risk adjustment

   // Strategy settings
   bool                 m_focusPrimeOnly;     // Only trade prime killzones
   bool                 m_useSymbolDefaults;  // Use symbol-specific defaults

   // Symbol type detection
   ENUM_SYMBOL_TYPE     m_symbolType;
   bool                 m_isUSIndex;

public:
   CKillzoneOptimizer() : m_brokerUTCOffset(0), m_autoDST(true),
                          m_enableAsian(false), m_enableLondonOpen(true),
                          m_enableNY(true), m_enableLondonClose(false),
                          m_focusPrimeOnly(false), m_useSymbolDefaults(true) {}

   //+------------------------------------------------------------------+
   //| Initialize Killzone Optimizer                                    |
   //+------------------------------------------------------------------+
   bool Init(string symbol, int brokerUTCOffset = 0,
             bool useSymbolDefaults = true, bool autoDST = true,
             bool focusPrimeOnly = false)
   {
      m_symbol = symbol;
      m_brokerUTCOffset = brokerUTCOffset;
      m_useSymbolDefaults = useSymbolDefaults;
      m_autoDST = autoDST;
      m_focusPrimeOnly = focusPrimeOnly;

      // Detect symbol type
      m_symbolType = ::GetSymbolType(m_symbol);
      m_isUSIndex = IsUSIndex(m_symbol);

      // Apply symbol-specific defaults if enabled
      if(m_useSymbolDefaults)
      {
         GetDefaultKillzonesForSymbol(m_symbol, m_enableAsian, m_enableLondonOpen,
                                      m_enableNY, m_enableLondonClose);
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Initialize with manual killzone selection                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, int brokerUTCOffset,
             bool enableAsian, bool enableLondon, bool enableNY, bool enableLondonClose,
             bool focusPrimeOnly = false, bool autoDST = true)
   {
      m_symbol = symbol;
      m_brokerUTCOffset = brokerUTCOffset;
      m_autoDST = autoDST;
      m_focusPrimeOnly = focusPrimeOnly;
      m_useSymbolDefaults = false;  // Using manual settings

      // Manual killzone settings
      m_enableAsian = enableAsian;
      m_enableLondonOpen = enableLondon;
      m_enableNY = enableNY;
      m_enableLondonClose = enableLondonClose;

      // Detect symbol type
      m_symbolType = ::GetSymbolType(m_symbol);
      m_isUSIndex = IsUSIndex(m_symbol);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Update - Call on new bar or periodically                         |
   //+------------------------------------------------------------------+
   void Update()
   {
      DetermineCurrentKillzone();
      CalculateQuality();
      CalculateRiskMultiplier();
   }

   //+------------------------------------------------------------------+
   //| Determine current active killzone                                |
   //+------------------------------------------------------------------+
   void DetermineCurrentKillzone()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Convert broker time to UTC
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;
      int utcMinute = dt.min;

      // Apply DST adjustment if enabled
      bool isDST = m_autoDST ? IsDST(TimeCurrent()) : false;

      // Get adjusted times based on DST
      int asianStart = GetAdjustedKillzoneTime(KZ_ASIAN_START_EST, isDST);
      int asianEnd = GetAdjustedKillzoneTime(KZ_ASIAN_END_EST, isDST);
      int londonStart = GetAdjustedKillzoneTime(KZ_LONDON_START_EST, isDST);
      int londonEnd = GetAdjustedKillzoneTime(KZ_LONDON_END_EST, isDST);
      int nyStart = GetAdjustedKillzoneTime(KZ_NY_START_EST, isDST);
      int nyEnd = GetAdjustedKillzoneTime(KZ_NY_END_EST, isDST);
      int londonCloseStart = GetAdjustedKillzoneTime(KZ_LONDON_CLOSE_START_EST, isDST);
      int londonCloseEnd = GetAdjustedKillzoneTime(KZ_LONDON_CLOSE_END_EST, isDST);
      int nyIndicesStart = GetAdjustedKillzoneTime(KZ_NY_INDICES_START_EST, isDST);
      int nyIndicesEnd = GetAdjustedKillzoneTime(KZ_NY_INDICES_END_EST, isDST);

      // Check for overlaps first (highest priority)
      bool inLondon = IsInTimeRange(utcHour, utcMinute, londonStart, 0, londonEnd, 0);
      bool inNY = IsInTimeRange(utcHour, utcMinute, nyStart, 0, nyEnd, 0);
      bool inAsian = IsInTimeRange(utcHour, utcMinute, asianStart, 0, asianEnd, 0);
      bool inLondonClose = IsInTimeRange(utcHour, utcMinute, londonCloseStart, 0, londonCloseEnd, 0);

      // Special handling for US Indices (13:30 start time)
      bool inNYIndices = false;
      if(m_isUSIndex)
      {
         inNYIndices = IsInTimeRange(utcHour, utcMinute, nyIndicesStart, KZ_NY_INDICES_START_MINUTE,
                                     nyIndicesEnd, 0);
      }

      // Determine active killzone (check overlaps first)
      // London-NY overlap is PRIME
      if(inLondon && inNY)
      {
         m_currentKillzone = KILLZONE_NY;  // NY takes precedence during overlap
         return;
      }

      // Asian-London overlap
      if(inAsian && inLondon)
      {
         m_currentKillzone = KILLZONE_LONDON_OPEN;  // London takes precedence
         return;
      }

      // Individual killzones
      if(m_isUSIndex && inNYIndices)
      {
         m_currentKillzone = KILLZONE_NY_INDICES;
         return;
      }

      if(inLondonClose)
      {
         m_currentKillzone = KILLZONE_LONDON_CLOSE;
         return;
      }

      if(inNY)
      {
         m_currentKillzone = KILLZONE_NY;
         return;
      }

      if(inLondon)
      {
         m_currentKillzone = KILLZONE_LONDON_OPEN;
         return;
      }

      if(inAsian)
      {
         m_currentKillzone = KILLZONE_ASIAN;
         return;
      }

      m_currentKillzone = KILLZONE_NONE;
   }

   //+------------------------------------------------------------------+
   //| Helper: Check if time is within range                            |
   //+------------------------------------------------------------------+
   bool IsInTimeRange(int hour, int minute, int startHour, int startMinute,
                      int endHour, int endMinute)
   {
      int currentMinutes = hour * 60 + minute;
      int startMinutes = startHour * 60 + startMinute;
      int endMinutes = endHour * 60 + endMinute;

      // Handle wraparound (e.g., 23:00 to 02:00)
      if(startMinutes > endMinutes)
      {
         return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
      }

      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   }

   //+------------------------------------------------------------------+
   //| Calculate killzone quality                                       |
   //+------------------------------------------------------------------+
   void CalculateQuality()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;
      bool isDST = m_autoDST ? IsDST(TimeCurrent()) : false;

      // Get adjusted overlap times
      int overlapStart = GetAdjustedKillzoneTime(KZ_LONDON_NY_OVERLAP_START_EST, isDST);
      int overlapEnd = GetAdjustedKillzoneTime(KZ_LONDON_NY_OVERLAP_END_EST, isDST);

      // Check if in prime overlap
      bool inPrimeOverlap = (utcHour >= overlapStart && utcHour < overlapEnd);

      // Quality based on killzone
      switch(m_currentKillzone)
      {
         case KILLZONE_NY:
            // If during London-NY overlap, it's PRIME
            m_currentQuality = inPrimeOverlap ? KZ_QUALITY_PRIME : KZ_QUALITY_STRONG;
            break;

         case KILLZONE_LONDON_OPEN:
            m_currentQuality = KZ_QUALITY_STRONG;
            break;

         case KILLZONE_NY_INDICES:
            m_currentQuality = KZ_QUALITY_STRONG;  // US market open is prime for indices
            break;

         case KILLZONE_LONDON_CLOSE:
            m_currentQuality = KZ_QUALITY_STRONG;  // London close/Fix is strong
            break;

         case KILLZONE_ASIAN:
            m_currentQuality = KZ_QUALITY_FAIR;  // Lower volatility
            break;

         case KILLZONE_NONE:
         default:
            m_currentQuality = KZ_QUALITY_WEAK;
            break;
      }

      // Day of week adjustments
      // Friday afternoon - reduce quality
      if(dt.day_of_week == 5 && dt.hour >= 18)
         m_currentQuality = (ENUM_KILLZONE_QUALITY)MathMax((int)m_currentQuality - 1, 0);

      // Sunday/Monday early - reduce quality
      if(dt.day_of_week == 0 || (dt.day_of_week == 1 && dt.hour < 7))
         m_currentQuality = KZ_QUALITY_WEAK;
   }

   //+------------------------------------------------------------------+
   //| Calculate risk multiplier based on killzone quality              |
   //+------------------------------------------------------------------+
   void CalculateRiskMultiplier()
   {
      switch(m_currentQuality)
      {
         case KZ_QUALITY_PRIME:
            m_riskMultiplier = 1.0;    // Full risk
            break;

         case KZ_QUALITY_STRONG:
            m_riskMultiplier = 0.9;    // 90% risk
            break;

         case KZ_QUALITY_FAIR:
            m_riskMultiplier = 0.7;    // 70% risk
            break;

         case KZ_QUALITY_WEAK:
         default:
            m_riskMultiplier = 0.5;    // 50% risk
            break;
      }

      // Additional adjustments
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;
      bool isDST = m_autoDST ? IsDST(TimeCurrent()) : false;

      // First 30 minutes of major killzone - slightly reduced (wait for direction)
      int londonStart = GetAdjustedKillzoneTime(KZ_LONDON_START_EST, isDST);
      int nyStart = GetAdjustedKillzoneTime(KZ_NY_START_EST, isDST);

      if(utcHour == londonStart || utcHour == nyStart)
      {
         if(dt.min < 30)
            m_riskMultiplier *= 0.9;
      }

      // Peak overlap hours - boost
      int overlapStart = GetAdjustedKillzoneTime(KZ_LONDON_NY_OVERLAP_START_EST, isDST);
      int overlapEnd = GetAdjustedKillzoneTime(KZ_LONDON_NY_OVERLAP_END_EST, isDST);

      if(utcHour >= overlapStart && utcHour < overlapEnd)
      {
         // Peak London-NY overlap
         if(utcHour >= (overlapStart + 1) && utcHour <= (overlapEnd - 1))
            m_riskMultiplier = 1.0;  // Full risk during prime overlap
      }
   }

   //+------------------------------------------------------------------+
   //| Check if trading is allowed                                      |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      if(m_currentKillzone == KILLZONE_NONE)
         return false;

      // Check if current killzone is enabled
      bool killzoneEnabled = false;

      switch(m_currentKillzone)
      {
         case KILLZONE_ASIAN:
            killzoneEnabled = m_enableAsian;
            break;

         case KILLZONE_LONDON_OPEN:
            killzoneEnabled = m_enableLondonOpen;
            break;

         case KILLZONE_NY:
         case KILLZONE_NY_INDICES:
            killzoneEnabled = m_enableNY;
            break;

         case KILLZONE_LONDON_CLOSE:
            killzoneEnabled = m_enableLondonClose;
            break;

         default:
            killzoneEnabled = false;
            break;
      }

      if(!killzoneEnabled)
         return false;

      // If focus on prime only, check quality
      if(m_focusPrimeOnly && m_currentQuality != KZ_QUALITY_PRIME)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if currently in prime killzone                             |
   //+------------------------------------------------------------------+
   bool IsInPrimeKillzone()
   {
      return (m_currentQuality == KZ_QUALITY_PRIME);
   }

   //+------------------------------------------------------------------+
   //| Get minutes until next major killzone                            |
   //+------------------------------------------------------------------+
   int GetMinutesUntilNextKillzone()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int utcHour = (dt.hour - m_brokerUTCOffset + 24) % 24;
      int utcMinute = dt.min;
      int currentMinutes = utcHour * 60 + utcMinute;

      bool isDST = m_autoDST ? IsDST(TimeCurrent()) : false;

      // Get adjusted killzone start times
      int londonStart = GetAdjustedKillzoneTime(KZ_LONDON_START_EST, isDST) * 60;
      int nyStart = GetAdjustedKillzoneTime(KZ_NY_START_EST, isDST) * 60;
      int asianStart = GetAdjustedKillzoneTime(KZ_ASIAN_START_EST, isDST) * 60;

      // Find next killzone start
      int killzoneStarts[] = {asianStart, londonStart, nyStart};
      int minDiff = 24 * 60;  // 24 hours in minutes

      for(int i = 0; i < ArraySize(killzoneStarts); i++)
      {
         int diff;
         if(killzoneStarts[i] > currentMinutes)
            diff = killzoneStarts[i] - currentMinutes;
         else
            diff = (24 * 60) - currentMinutes + killzoneStarts[i];

         if(diff < minDiff)
            minDiff = diff;
      }

      return minDiff;
   }

   //+------------------------------------------------------------------+
   //| Get confluence score contribution (0-0.5)                        |
   //+------------------------------------------------------------------+
   double GetConfluenceScore()
   {
      switch(m_currentQuality)
      {
         case KZ_QUALITY_PRIME:    return 0.5;
         case KZ_QUALITY_STRONG:   return 0.3;
         case KZ_QUALITY_FAIR:     return 0.1;
         default:                  return 0.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   ENUM_KILLZONE GetCurrentKillzone() { return m_currentKillzone; }
   ENUM_KILLZONE_QUALITY GetCurrentQuality() { return m_currentQuality; }
   double GetRiskMultiplier() { return m_riskMultiplier; }
   ENUM_SYMBOL_TYPE GetSymbolType() { return m_symbolType; }

   //+------------------------------------------------------------------+
   //| Set broker UTC offset                                            |
   //+------------------------------------------------------------------+
   void SetBrokerOffset(int offset) { m_brokerUTCOffset = offset; }

   //+------------------------------------------------------------------+
   //| Get killzone name                                                |
   //+------------------------------------------------------------------+
   string GetKillzoneName()
   {
      return KillzoneToString(m_currentKillzone);
   }

   //+------------------------------------------------------------------+
   //| Get quality name                                                 |
   //+------------------------------------------------------------------+
   string GetQualityName()
   {
      return QualityToString(m_currentQuality);
   }

   //+------------------------------------------------------------------+
   //| Get string representation                                        |
   //+------------------------------------------------------------------+
   string ToString()
   {
      string dstStatus = m_autoDST && IsDST(TimeCurrent()) ? " (EDT)" : " (EST)";
      return "KILLZONE: " + GetKillzoneName() + " (" + GetQualityName() + ") " +
             DoubleToString(m_riskMultiplier * 100, 0) + "%" + dstStatus;
   }

   //+------------------------------------------------------------------+
   //| Get estimated spread multiplier based on killzone                |
   //+------------------------------------------------------------------+
   double GetExpectedSpreadMultiplier()
   {
      switch(m_currentKillzone)
      {
         case KILLZONE_NY:
         case KILLZONE_LONDON_OPEN:
            return 1.0;  // Tightest spreads during major killzones

         case KILLZONE_NY_INDICES:
            return 1.0;  // US market open has tight spreads

         case KILLZONE_LONDON_CLOSE:
            return 1.1;  // Slightly wider

         case KILLZONE_ASIAN:
            return 1.5;  // Wider spreads in Asian session

         default:
            return 2.0;  // Widest spreads off-hours
      }
   }

   //+------------------------------------------------------------------+
   //| Check if approaching killzone end                                |
   //+------------------------------------------------------------------+
   bool IsNearKillzoneEnd()
   {
      if(m_currentKillzone == KILLZONE_NONE)
         return false;

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Within 30 minutes of killzone end
      return (dt.min >= 30);  // Simplified: check if in last half of hour
   }
};

#endif
