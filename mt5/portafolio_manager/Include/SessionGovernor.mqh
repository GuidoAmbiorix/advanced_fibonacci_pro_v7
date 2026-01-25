//+------------------------------------------------------------------+
//|                                            SessionGovernor.mqh   |
//|                    Session-Level Trading Control & Statistics    |
//|                                  Copyright 2026, Guido Ambiorix  |
//+------------------------------------------------------------------+
#ifndef SESSION_GOVERNOR_MQH
#define SESSION_GOVERNOR_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "KillzoneOptimizer.mqh"

//+------------------------------------------------------------------+
//| SESSION STATE STRUCTURE                                          |
//+------------------------------------------------------------------+
struct SessionState
{
   ENUM_KILLZONE session;
   datetime      startTime;
   datetime      endTime;

   // Trade Counters
   int           tradesOpened;
   int           tradesClosed;
   int           wins;
   int           losses;
   int           breakevens;

   // P&L Tracking
   double        profitR;           // Total profit in R
   double        lossR;             // Total loss in R
   double        profitMoney;
   double        lossMoney;
   double        currentR;          // Running R for session
   double        peakR;             // Peak R reached this session
   double        worstR;            // Worst DD in session

   // Learning Stats
   double        totalMFE;
   double        totalMAE;
   int           mfeMaeCount;

   // Confidence
   double        confidence;        // 0.0 to 1.0

   // Locks
   bool          profitLocked;      // Hit max profit
   bool          lossLocked;        // Hit max loss
   bool          tradeLimitHit;     // Hit max trades
   bool          blacklisted;       // Session blacklisted

   // Last Trade Time (for cooldown)
   datetime      lastTradeTime;

   SessionState()
   {
      session = KILLZONE_NONE;
      startTime = 0;
      endTime = 0;
      tradesOpened = 0;
      tradesClosed = 0;
      wins = 0;
      losses = 0;
      breakevens = 0;
      profitR = 0;
      lossR = 0;
      profitMoney = 0;
      lossMoney = 0;
      currentR = 0;
      peakR = 0;
      worstR = 0;
      totalMFE = 0;
      totalMAE = 0;
      mfeMaeCount = 0;
      confidence = 0.5;
      profitLocked = false;
      lossLocked = false;
      tradeLimitHit = false;
      blacklisted = false;
      lastTradeTime = 0;
   }
};

//+------------------------------------------------------------------+
//| SESSION STATISTICS (for learning)                                |
//+------------------------------------------------------------------+
struct SessionStats
{
   ENUM_KILLZONE session;
   int           totalTrades;
   double        winRate;
   double        avgR;
   double        expectancy;
   double        maxDD_R;
   double        avgMFE;
   double        avgMAE;
   double        confidenceScore;
   datetime      lastUpdate;

   SessionStats()
   {
      session = KILLZONE_NONE;
      totalTrades = 0;
      winRate = 0;
      avgR = 0;
      expectancy = 0;
      maxDD_R = 0;
      avgMFE = 0;
      avgMAE = 0;
      confidenceScore = 0.5;
      lastUpdate = 0;
   }
};

//+------------------------------------------------------------------+
//| SESSION GOVERNOR CLASS                                           |
//+------------------------------------------------------------------+
class CSessionGovernor
{
private:
   // Configuration
   string               m_symbol;
   CKillzoneOptimizer*  m_killzoneOpt;

   // Limits
   int                  m_maxTradesPerSession;
   double               m_maxProfitR;           // Max profit per session (R)
   double               m_maxLossR;             // Max loss per session (R)
   double               m_minConfidence;        // Min confidence to trade
   int                  m_cooldownMinutes;      // Cooldown between trades
   bool                 m_enableBlacklist;      // Enable session blacklisting

   // Current Session
   SessionState         m_currentSession;
   ENUM_KILLZONE        m_lastKillzone;

   // Historical Stats (per session type)
   SessionStats         m_asianStats;
   SessionStats         m_londonStats;
   SessionStats         m_nyStats;
   SessionStats         m_londonCloseStats;

   // Safety Locks
   bool                 m_revengeMode;          // Activated after 2 consecutive losses
   int                  m_consecutiveLosses;
   bool                 m_emergencyKill;        // Manual kill switch

   // Risk Scaling
   double               m_riskMultiplier;       // Session-based risk multiplier

   // File persistence
   int                  m_fileHandle;
   string               m_statsFilePath;

public:
   CSessionGovernor() : m_killzoneOpt(NULL), m_maxTradesPerSession(3),
                        m_maxProfitR(5.0), m_maxLossR(2.0),
                        m_minConfidence(0.4), m_cooldownMinutes(15),
                        m_enableBlacklist(true), m_lastKillzone(KILLZONE_NONE),
                        m_revengeMode(false), m_consecutiveLosses(0),
                        m_emergencyKill(false), m_riskMultiplier(1.0),
                        m_fileHandle(INVALID_HANDLE) {}

   ~CSessionGovernor() { SaveSessionStats(); }

   //+------------------------------------------------------------------+
   //| Initialize Session Governor                                      |
   //+------------------------------------------------------------------+
   bool Init(string symbol, CKillzoneOptimizer* killzoneOpt,
             int maxTrades = 3, double maxProfitR = 5.0, double maxLossR = 2.0,
             double minConfidence = 0.4, int cooldownMinutes = 15,
             bool enableBlacklist = true)
   {
      if(killzoneOpt == NULL)
      {
         Print("SessionGovernor ERROR: KillzoneOptimizer pointer is NULL");
         return false;
      }

      m_symbol = symbol;
      m_killzoneOpt = killzoneOpt;
      m_maxTradesPerSession = maxTrades;
      m_maxProfitR = maxProfitR;
      m_maxLossR = maxLossR;
      m_minConfidence = minConfidence;
      m_cooldownMinutes = cooldownMinutes;
      m_enableBlacklist = enableBlacklist;

      // Initialize stats file path
      m_statsFilePath = "SessionStats_" + m_symbol + ".csv";

      // Load historical stats
      LoadSessionStats();

      // Initialize current session
      ResetCurrentSession();
      m_lastKillzone = m_killzoneOpt.GetCurrentKillzone();
      m_currentSession.session = m_lastKillzone;
      m_currentSession.startTime = TimeCurrent();

      // Calculate initial confidence
      UpdateSessionConfidence();

      Print("SessionGovernor initialized for ", m_symbol);
      Print("  Max Trades/Session: ", m_maxTradesPerSession);
      Print("  Max Profit: ", m_maxProfitR, "R | Max Loss: ", m_maxLossR, "R");
      Print("  Min Confidence: ", DoubleToString(m_minConfidence * 100, 0), "%");
      Print("  Cooldown: ", m_cooldownMinutes, " minutes");

      return true;
   }

   //+------------------------------------------------------------------+
   //| Update - Call on every new bar                                   |
   //+------------------------------------------------------------------+
   void Update()
   {
      ENUM_KILLZONE currentKZ = m_killzoneOpt.GetCurrentKillzone();

      // Detect session change
      if(currentKZ != m_lastKillzone && currentKZ != KILLZONE_NONE)
      {
         OnSessionChange(m_lastKillzone, currentKZ);
         m_lastKillzone = currentKZ;
      }

      // Update risk multiplier
      UpdateRiskMultiplier();

      // Check if near session end (reduce risk)
      CheckSessionEndProximity();
   }

   //+------------------------------------------------------------------+
   //| Check if trading allowed for current session                     |
   //+------------------------------------------------------------------+
   bool IsSessionTradingAllowed()
   {
      // Emergency kill switch
      if(m_emergencyKill)
      {
         return false;
      }

      // Check if in valid killzone
      if(m_currentSession.session == KILLZONE_NONE)
      {
         return false;
      }

      // Check if session is blacklisted
      if(m_currentSession.blacklisted && m_enableBlacklist)
      {
         return false;
      }

      // Check profit lock
      if(m_currentSession.profitLocked)
      {
         return false;
      }

      // Check loss lock
      if(m_currentSession.lossLocked)
      {
         return false;
      }

      // Check trade limit
      if(m_currentSession.tradesOpened >= m_maxTradesPerSession)
      {
         if(!m_currentSession.tradeLimitHit)
         {
            m_currentSession.tradeLimitHit = true;
            Print("Session ", KillzoneToString(m_currentSession.session),
                  " TRADE LIMIT HIT: ", m_currentSession.tradesOpened, "/", m_maxTradesPerSession);
         }
         return false;
      }

      // Check confidence threshold
      if(m_currentSession.confidence < m_minConfidence)
      {
         return false;
      }

      // Check cooldown
      if(m_cooldownMinutes > 0 && m_currentSession.lastTradeTime > 0)
      {
         int secondsSince = (int)(TimeCurrent() - m_currentSession.lastTradeTime);
         if(secondsSince < m_cooldownMinutes * 60)
         {
            return false;
         }
      }

      // Check revenge mode
      if(m_revengeMode)
      {
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get session risk multiplier                                      |
   //+------------------------------------------------------------------+
   double GetSessionRiskMultiplier()
   {
      return m_riskMultiplier;
   }

   //+------------------------------------------------------------------+
   //| Register new trade                                               |
   //+------------------------------------------------------------------+
   void RegisterTrade(ulong ticket, int direction, double lots, double slDist)
   {
      m_currentSession.tradesOpened++;
      m_currentSession.lastTradeTime = TimeCurrent();
   }

   //+------------------------------------------------------------------+
   //| On trade closed                                                   |
   //+------------------------------------------------------------------+
   void OnTradeClosed(ulong ticket, double profitR, double profitMoney)
   {
      m_currentSession.tradesClosed++;

      // Update P&L
      if(profitR > 0)
      {
         m_currentSession.wins++;
         m_currentSession.profitR += profitR;
         m_currentSession.profitMoney += profitMoney;
         m_consecutiveLosses = 0;  // Reset consecutive losses
         m_revengeMode = false;    // Exit revenge mode
      }
      else if(profitR < 0)
      {
         m_currentSession.losses++;
         m_currentSession.lossR += MathAbs(profitR);
         m_currentSession.lossMoney += MathAbs(profitMoney);
         m_consecutiveLosses++;

         // Activate revenge mode after 2 consecutive losses
         if(m_consecutiveLosses >= 2)
         {
            m_revengeMode = true;
            Print("REVENGE MODE ACTIVATED - ", m_consecutiveLosses, " consecutive losses in ",
                  KillzoneToString(m_currentSession.session));
         }
      }
      else
      {
         m_currentSession.breakevens++;
         m_consecutiveLosses = 0;
         m_revengeMode = false;
      }

      // Update running R
      m_currentSession.currentR = m_currentSession.profitR - m_currentSession.lossR;

      // Update peak/worst
      if(m_currentSession.currentR > m_currentSession.peakR)
         m_currentSession.peakR = m_currentSession.currentR;
      if(m_currentSession.currentR < m_currentSession.worstR)
         m_currentSession.worstR = m_currentSession.currentR;

      // Check profit lock
      if(m_currentSession.currentR >= m_maxProfitR && !m_currentSession.profitLocked)
      {
         m_currentSession.profitLocked = true;
         Print("SESSION PROFIT TARGET HIT: ", DoubleToString(m_currentSession.currentR, 2),
               "R >= ", DoubleToString(m_maxProfitR, 1), "R - Session locked");
      }

      // Check loss lock
      if(-m_currentSession.currentR >= m_maxLossR && !m_currentSession.lossLocked)
      {
         m_currentSession.lossLocked = true;
         Print("SESSION LOSS LIMIT HIT: ", DoubleToString(-m_currentSession.currentR, 2),
               "R >= ", DoubleToString(m_maxLossR, 1), "R - Session locked");
      }

      // Update confidence
      UpdateSessionConfidence();

      // Check for blacklist conditions
      CheckBlacklistConditions();
   }

   //+------------------------------------------------------------------+
   //| Add MFE/MAE data                                                 |
   //+------------------------------------------------------------------+
   void AddMFEMAE(double mfe, double mae)
   {
      m_currentSession.totalMFE += mfe;
      m_currentSession.totalMAE += mae;
      m_currentSession.mfeMaeCount++;
   }

   //+------------------------------------------------------------------+
   //| Get session statistics string for dashboard                      |
   //+------------------------------------------------------------------+
   string ToString()
   {
      string txt = "";
      string sessionName = KillzoneToString(m_currentSession.session);

      txt += "Session: " + sessionName + "\n";
      txt += "Trades: " + IntegerToString(m_currentSession.tradesOpened) + "/" +
             IntegerToString(m_maxTradesPerSession);

      if(m_currentSession.tradesOpened >= m_maxTradesPerSession)
         txt += " [LIMIT]";
      txt += "\n";

      txt += "Session R: " + DoubleToString(m_currentSession.currentR, 2) + "R";
      txt += " (Peak: " + DoubleToString(m_currentSession.peakR, 2) + "R)\n";

      txt += "W/L/BE: " + IntegerToString(m_currentSession.wins) + "/" +
             IntegerToString(m_currentSession.losses) + "/" +
             IntegerToString(m_currentSession.breakevens) + "\n";

      // Win rate
      if(m_currentSession.tradesClosed > 0)
      {
         double wr = (double)m_currentSession.wins / m_currentSession.tradesClosed * 100.0;
         txt += "Win Rate: " + DoubleToString(wr, 1) + "%\n";
      }

      txt += "Confidence: " + DoubleToString(m_currentSession.confidence * 100, 0) + "%";

      if(m_currentSession.confidence < m_minConfidence)
         txt += " [LOW]";
      txt += "\n";

      // Locks
      string locks = "";
      if(m_currentSession.profitLocked) locks += "TP_LOCK ";
      if(m_currentSession.lossLocked) locks += "DD_LOCK ";
      if(m_currentSession.blacklisted) locks += "BLACKLIST ";
      if(m_revengeMode) locks += "REVENGE_MODE ";

      if(locks != "")
         txt += "Status: " + locks + "\n";

      // Risk multiplier
      txt += "Risk Mult: " + DoubleToString(m_riskMultiplier * 100, 0) + "%\n";

      return txt;
   }

   //+------------------------------------------------------------------+
   //| Get session stats for specific session type (returns by reference) |
   //+------------------------------------------------------------------+
   void GetSessionStats(ENUM_KILLZONE session, SessionStats &output)
   {
      switch(session)
      {
         case KILLZONE_ASIAN:        output = m_asianStats; break;
         case KILLZONE_LONDON_OPEN:  output = m_londonStats; break;
         case KILLZONE_NY:           output = m_nyStats; break;
         case KILLZONE_LONDON_CLOSE: output = m_londonCloseStats; break;
         default:
         {
            SessionStats empty;
            output = empty;
            break;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Manual controls                                                   |
   //+------------------------------------------------------------------+
   void SetEmergencyKill(bool enabled) { m_emergencyKill = enabled; }
   bool IsEmergencyKill() { return m_emergencyKill; }

private:
   //+------------------------------------------------------------------+
   //| Reset current session state                                      |
   //+------------------------------------------------------------------+
   void ResetCurrentSession()
   {
      SessionState newState;
      m_currentSession = newState;
      m_consecutiveLosses = 0;
      m_revengeMode = false;
   }

   //+------------------------------------------------------------------+
   //| Handle session change                                            |
   //+------------------------------------------------------------------+
   void OnSessionChange(ENUM_KILLZONE oldSession, ENUM_KILLZONE newSession)
   {
      // Save old session stats
      if(oldSession != KILLZONE_NONE)
      {
         SaveCurrentSessionToHistory(oldSession);
         PrintSessionSummary(oldSession);
      }

      // Reset for new session
      ResetCurrentSession();
      m_currentSession.session = newSession;
      m_currentSession.startTime = TimeCurrent();

      // Load historical confidence for new session
      UpdateSessionConfidence();

      Print("===========================================");
      Print("SESSION CHANGE: ", KillzoneToString(oldSession), " -> ", KillzoneToString(newSession));
      Print("New Session Confidence: ", DoubleToString(m_currentSession.confidence * 100, 0), "%");
      Print("===========================================");
   }

   //+------------------------------------------------------------------+
   //| Update session confidence score                                  |
   //+------------------------------------------------------------------+
   void UpdateSessionConfidence()
   {
      SessionStats stats;
      GetSessionStats(m_currentSession.session, stats);

      // If no historical data, use current session
      if(stats.totalTrades < 20)
      {
         // Use current session data with decay
         if(m_currentSession.tradesClosed > 0)
         {
            double sessionWR = (double)m_currentSession.wins / m_currentSession.tradesClosed;
            double sessionExp = 0;
            if(m_currentSession.tradesClosed > 0)
               sessionExp = m_currentSession.currentR / m_currentSession.tradesClosed;

            // Confidence = 60% WinRate + 40% Expectancy
            m_currentSession.confidence = (sessionWR * 0.6) + ((sessionExp > 0 ? 1.0 : 0.0) * 0.4);

            // Apply decay after losses
            if(m_consecutiveLosses > 0)
            {
               m_currentSession.confidence *= MathPow(0.9, m_consecutiveLosses);
            }
         }
         else
         {
            m_currentSession.confidence = 0.5;  // Neutral
         }
      }
      else
      {
         // Use historical stats
         m_currentSession.confidence = stats.confidenceScore;

         // Apply current session adjustment
         if(m_currentSession.tradesClosed > 2)
         {
            double sessionWR = (double)m_currentSession.wins / m_currentSession.tradesClosed;
            double adjustment = (sessionWR - stats.winRate) * 0.2;  // 20% weight to current
            m_currentSession.confidence += adjustment;
         }

         // Apply decay after losses
         if(m_consecutiveLosses > 0)
         {
            m_currentSession.confidence *= MathPow(0.85, m_consecutiveLosses);
         }
      }

      // Clamp to [0, 1]
      if(m_currentSession.confidence > 1.0) m_currentSession.confidence = 1.0;
      if(m_currentSession.confidence < 0.0) m_currentSession.confidence = 0.0;
   }

   //+------------------------------------------------------------------+
   //| Update risk multiplier based on session state                    |
   //+------------------------------------------------------------------+
   void UpdateRiskMultiplier()
   {
      m_riskMultiplier = 1.0;

      // Base multiplier per session type
      switch(m_currentSession.session)
      {
         case KILLZONE_ASIAN:        m_riskMultiplier = 0.5; break;  // Lower for Asian
         case KILLZONE_LONDON_OPEN:  m_riskMultiplier = 1.0; break;
         case KILLZONE_NY:           m_riskMultiplier = 1.0; break;
         case KILLZONE_LONDON_CLOSE: m_riskMultiplier = 0.7; break;
         default:                    m_riskMultiplier = 0.0; break;
      }

      // Reduce after consecutive losses
      if(m_consecutiveLosses >= 2)
         m_riskMultiplier *= 0.5;
      else if(m_consecutiveLosses >= 1)
         m_riskMultiplier *= 0.75;

      // Confidence-based scaling
      if(m_currentSession.confidence < 0.5)
         m_riskMultiplier *= 0.7;
      else if(m_currentSession.confidence > 0.7)
         m_riskMultiplier *= 1.1;  // Boost for high confidence

      // Near profit target - reduce to protect gains
      if(m_currentSession.currentR >= m_maxProfitR * 0.8)
         m_riskMultiplier *= 0.5;

      // Clamp
      if(m_riskMultiplier > 1.2) m_riskMultiplier = 1.2;
      if(m_riskMultiplier < 0.3) m_riskMultiplier = 0.3;
   }

   //+------------------------------------------------------------------+
   //| Check if near session end (reduce risk in last 30 min)          |
   //+------------------------------------------------------------------+
   void CheckSessionEndProximity()
   {
      // This would need session end time from killzone data
      // For now, simple implementation
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Reduce risk in last 30 minutes of prime sessions
      // London: 11:30-12:00 GMT
      // NY: 16:30-17:00 GMT
      // (This is simplified - would need proper session end detection)
   }

   //+------------------------------------------------------------------+
   //| Check blacklist conditions                                       |
   //+------------------------------------------------------------------+
   void CheckBlacklistConditions()
   {
      if(!m_enableBlacklist) return;

      // Blacklist if confidence drops too low with enough trades
      if(m_currentSession.tradesClosed >= 5 && m_currentSession.confidence < 0.2)
      {
         if(!m_currentSession.blacklisted)
         {
            m_currentSession.blacklisted = true;
            Print("SESSION BLACKLISTED: ", KillzoneToString(m_currentSession.session),
                  " - Confidence too low: ", DoubleToString(m_currentSession.confidence * 100, 0), "%");
         }
      }

      // Blacklist if 3+ consecutive losses
      if(m_consecutiveLosses >= 3)
      {
         if(!m_currentSession.blacklisted)
         {
            m_currentSession.blacklisted = true;
            Print("SESSION BLACKLISTED: ", KillzoneToString(m_currentSession.session),
                  " - ", m_consecutiveLosses, " consecutive losses");
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Save current session to historical stats                         |
   //+------------------------------------------------------------------+
   void SaveCurrentSessionToHistory(ENUM_KILLZONE session)
   {
      if(m_currentSession.tradesClosed == 0) return;

      SessionStats stats;
      GetSessionStats(session, stats);

      // Update stats with exponential moving average (70% historical, 30% current)
      double alpha = 0.3;

      if(stats.totalTrades == 0)
      {
         // First session, use current data
         stats.session = session;
         stats.totalTrades = m_currentSession.tradesClosed;
         stats.winRate = (double)m_currentSession.wins / m_currentSession.tradesClosed;
         stats.avgR = m_currentSession.currentR / m_currentSession.tradesClosed;
         stats.expectancy = stats.avgR;
         stats.maxDD_R = MathAbs(m_currentSession.worstR);

         if(m_currentSession.mfeMaeCount > 0)
         {
            stats.avgMFE = m_currentSession.totalMFE / m_currentSession.mfeMaeCount;
            stats.avgMAE = m_currentSession.totalMAE / m_currentSession.mfeMaeCount;
         }

         stats.confidenceScore = m_currentSession.confidence;
      }
      else
      {
         // Update with EMA
         stats.totalTrades += m_currentSession.tradesClosed;

         double sessionWR = (double)m_currentSession.wins / m_currentSession.tradesClosed;
         stats.winRate = (stats.winRate * (1 - alpha)) + (sessionWR * alpha);

         double sessionAvgR = m_currentSession.currentR / m_currentSession.tradesClosed;
         stats.avgR = (stats.avgR * (1 - alpha)) + (sessionAvgR * alpha);

         stats.expectancy = stats.avgR;

         if(MathAbs(m_currentSession.worstR) > stats.maxDD_R)
            stats.maxDD_R = MathAbs(m_currentSession.worstR);

         if(m_currentSession.mfeMaeCount > 0)
         {
            double sessionMFE = m_currentSession.totalMFE / m_currentSession.mfeMaeCount;
            double sessionMAE = m_currentSession.totalMAE / m_currentSession.mfeMaeCount;
            stats.avgMFE = (stats.avgMFE * (1 - alpha)) + (sessionMFE * alpha);
            stats.avgMAE = (stats.avgMAE * (1 - alpha)) + (sessionMAE * alpha);
         }

         // Recalculate confidence from updated stats
         stats.confidenceScore = (stats.winRate * 0.6) + ((stats.expectancy > 0 ? 1.0 : 0.0) * 0.4);
      }

      stats.lastUpdate = TimeCurrent();

      // Update the appropriate member variable
      switch(session)
      {
         case KILLZONE_ASIAN:        m_asianStats = stats; break;
         case KILLZONE_LONDON_OPEN:  m_londonStats = stats; break;
         case KILLZONE_NY:           m_nyStats = stats; break;
         case KILLZONE_LONDON_CLOSE: m_londonCloseStats = stats; break;
      }

      // Save to file
      SaveSessionStats();
   }

   //+------------------------------------------------------------------+
   //| Print session summary                                            |
   //+------------------------------------------------------------------+
   void PrintSessionSummary(ENUM_KILLZONE session)
   {
      Print("===========================================");
      Print("SESSION SUMMARY: ", KillzoneToString(session));
      Print("===========================================");
      Print("Trades: ", m_currentSession.tradesOpened, " opened, ", m_currentSession.tradesClosed, " closed");
      Print("W/L/BE: ", m_currentSession.wins, "/", m_currentSession.losses, "/", m_currentSession.breakevens);

      if(m_currentSession.tradesClosed > 0)
      {
         double wr = (double)m_currentSession.wins / m_currentSession.tradesClosed * 100.0;
         Print("Win Rate: ", DoubleToString(wr, 1), "%");
      }

      Print("Session R: ", DoubleToString(m_currentSession.currentR, 2), "R");
      Print("Peak R: ", DoubleToString(m_currentSession.peakR, 2), "R");
      Print("Worst DD: ", DoubleToString(m_currentSession.worstR, 2), "R");
      Print("Final Confidence: ", DoubleToString(m_currentSession.confidence * 100, 0), "%");

      if(m_currentSession.profitLocked)
         Print("Status: PROFIT TARGET HIT");
      if(m_currentSession.lossLocked)
         Print("Status: LOSS LIMIT HIT");
      if(m_currentSession.blacklisted)
         Print("Status: BLACKLISTED");

      Print("===========================================");
   }

   //+------------------------------------------------------------------+
   //| Save session stats to file                                       |
   //+------------------------------------------------------------------+
   void SaveSessionStats()
   {
      int handle = FileOpen(m_statsFilePath, FILE_WRITE | FILE_CSV | FILE_ANSI);
      if(handle == INVALID_HANDLE)
      {
         Print("Failed to save session stats to file: ", m_statsFilePath);
         return;
      }

      // Write header
      FileWrite(handle, "Session", "TotalTrades", "WinRate", "AvgR", "Expectancy",
                "MaxDD_R", "AvgMFE", "AvgMAE", "Confidence", "LastUpdate");

      // Write stats for each session
      WriteSessionStatToFile(handle, m_asianStats);
      WriteSessionStatToFile(handle, m_londonStats);
      WriteSessionStatToFile(handle, m_nyStats);
      WriteSessionStatToFile(handle, m_londonCloseStats);

      FileClose(handle);
   }

   //+------------------------------------------------------------------+
   //| Write single session stat to file                                |
   //+------------------------------------------------------------------+
   void WriteSessionStatToFile(int handle, const SessionStats &stats)
   {
      if(stats.totalTrades == 0) return;

      FileWrite(handle,
                KillzoneToString(stats.session),
                stats.totalTrades,
                DoubleToString(stats.winRate, 4),
                DoubleToString(stats.avgR, 4),
                DoubleToString(stats.expectancy, 4),
                DoubleToString(stats.maxDD_R, 4),
                DoubleToString(stats.avgMFE, 2),
                DoubleToString(stats.avgMAE, 2),
                DoubleToString(stats.confidenceScore, 4),
                TimeToString(stats.lastUpdate));
   }

   //+------------------------------------------------------------------+
   //| Load session stats from file                                     |
   //+------------------------------------------------------------------+
   void LoadSessionStats()
   {
      int handle = FileOpen(m_statsFilePath, FILE_READ | FILE_CSV | FILE_ANSI);
      if(handle == INVALID_HANDLE)
      {
         Print("No previous session stats found for ", m_symbol, " - starting fresh");
         return;
      }

      // Skip header
      string header = FileReadString(handle);

      // Read stats
      while(!FileIsEnding(handle))
      {
         string sessionName = FileReadString(handle);
         if(sessionName == "") break;

         SessionStats stats;
         stats.totalTrades = (int)FileReadNumber(handle);
         stats.winRate = FileReadNumber(handle);
         stats.avgR = FileReadNumber(handle);
         stats.expectancy = FileReadNumber(handle);
         stats.maxDD_R = FileReadNumber(handle);
         stats.avgMFE = FileReadNumber(handle);
         stats.avgMAE = FileReadNumber(handle);
         stats.confidenceScore = FileReadNumber(handle);
         string timeStr = FileReadString(handle);
         stats.lastUpdate = StringToTime(timeStr);

         // Map to session enum
         ENUM_KILLZONE kz = StringToKillzone(sessionName);
         stats.session = kz;

         // Store in appropriate stats structure
         switch(kz)
         {
            case KILLZONE_ASIAN:        m_asianStats = stats; break;
            case KILLZONE_LONDON_OPEN:  m_londonStats = stats; break;
            case KILLZONE_NY:           m_nyStats = stats; break;
            case KILLZONE_LONDON_CLOSE: m_londonCloseStats = stats; break;
         }
      }

      FileClose(handle);
      Print("Session stats loaded for ", m_symbol);
   }

   //+------------------------------------------------------------------+
   //| Convert string to killzone enum                                  |
   //+------------------------------------------------------------------+
   ENUM_KILLZONE StringToKillzone(string str)
   {
      if(str == "ASIAN") return KILLZONE_ASIAN;
      if(str == "LONDON OPEN") return KILLZONE_LONDON_OPEN;
      if(str == "NEW YORK") return KILLZONE_NY;
      if(str == "LONDON CLOSE") return KILLZONE_LONDON_CLOSE;
      if(str == "NY INDICES") return KILLZONE_NY_INDICES;
      return KILLZONE_NONE;
   }
};

#endif
