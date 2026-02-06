//+------------------------------------------------------------------+
//|                                          NotificationManager.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef NOTIFICATION_MANAGER_MQH
#define NOTIFICATION_MANAGER_MQH

#include <Trade\AccountInfo.mqh>
#include "PortfolioGlobals.mqh"
#include "DatabaseManager.mqh"

//+------------------------------------------------------------------+
//| Session Enumeration                                               |
//+------------------------------------------------------------------+
enum ENUM_TRADING_SESSION
{
   SESSION_CLOSED,
   SESSION_ASIAN,
   SESSION_LONDON,
   SESSION_NEWYORK
};

//+------------------------------------------------------------------+
//| CNotificationManager Class                                        |
//| Handles Push Notifications for Session Open/Close and Risks      |
//+------------------------------------------------------------------+
class CNotificationManager
{
private:
   CAccountInfo      m_account;
   CDatabaseManager* m_dbManager; // Pointer to DB Manager
   
   // Session State
   ENUM_TRADING_SESSION m_currentSession;
   datetime             m_lastCheckTime;
   
   // Performance Tracking
   double               m_sessionStartEquity;
   double               m_sessionStartBalance;
   int                  m_sessionStartTrades;
   
   // Configuration
   bool                 m_enabled;
   int                  m_asianStartHour;
   int                  m_londonStartHour;
   int                  m_nyStartHour;
   int                  m_nyEndHour;

public:
   CNotificationManager();
   ~CNotificationManager();

   // Core Methods
   void     Init(CDatabaseManager* dbManager, bool enable = true);
   void     OnTick(double currentEquity, int activeTradesCount, string topConfluences);
   
   // Risk Alerts (Immediate)
   void     SendRiskAlert(string message);

private:
   // Internal Logic
   void                 CheckSessionTransition(double equity);
   ENUM_TRADING_SESSION GetSessionForTime(datetime time);
   string               GetSessionName(ENUM_TRADING_SESSION session);
   void                 SendSessionOpenAlert(ENUM_TRADING_SESSION session, double equity);
   void                 SendSessionCloseAlert(ENUM_TRADING_SESSION session, double equity);
   void                 SendStartupAlert();
   
   string               FormatCurrency(double value);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CNotificationManager::CNotificationManager() : 
   m_dbManager(NULL),
   m_currentSession(SESSION_CLOSED),
   m_lastCheckTime(0),
   m_sessionStartEquity(0),
   m_sessionStartBalance(0),
   m_sessionStartTrades(0),
   m_enabled(true),
   m_asianStartHour(0),   // 00:00 UTC (Adjust as per broker)
   m_londonStartHour(8),  // 08:00 UTC
   m_nyStartHour(13),     // 13:00 UTC
   m_nyEndHour(22)        // 22:00 UTC
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CNotificationManager::~CNotificationManager()
{
}

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
void CNotificationManager::Init(CDatabaseManager* dbManager, bool enable)
{
   m_enabled = enable;
   m_dbManager = dbManager;
   
   m_sessionStartEquity = m_account.Equity();
   m_sessionStartBalance = m_account.Balance();
   
   m_currentSession = GetSessionForTime(TimeCurrent());
   
   if(m_enabled)
   {
      string msg = "📱 NotificationManager Initialized | Session: " + GetSessionName(m_currentSession);
      Print(msg);
      if(m_dbManager != NULL) m_dbManager.LogSystemEvent("NotificationManager", "INFO", msg);
      
      SendStartupAlert();
   }
}

//+------------------------------------------------------------------+
//| Main Tick Loop (Call every tick, handles throttling internally)   |
//+------------------------------------------------------------------+
void CNotificationManager::OnTick(double currentEquity, int activeTradesCount, string topConfluences)
{
   if(!m_enabled) return;
   
   // Check once per minute
   if(TimeCurrent() - m_lastCheckTime < 60) return;
   m_lastCheckTime = TimeCurrent();
   
   // Periodic Log (Heartbeat) - Every 15 minutes
   if(TimeCurrent() % 900 < 60) 
   {
       string hbMsg = "💓 [GOV] Alive | Session: " + GetSessionName(m_currentSession) + 
                      " | Eq: " + FormatCurrency(currentEquity) + 
                      " | Trades: " + IntegerToString(activeTradesCount);
       Print(hbMsg);
       
       if(m_dbManager != NULL) m_dbManager.LogSystemEvent("Heartbeat", "INFO", hbMsg);
   }
   
   CheckSessionTransition(currentEquity);
}

//+------------------------------------------------------------------+
//| Send Startup Alert                                                |
//+------------------------------------------------------------------+
void CNotificationManager::SendStartupAlert()
{
   string title = "🚀 Portfolio Governor STARTED";
   string body = "Session: " + GetSessionName(m_currentSession) + "\n";
   body += "💰 Balance: " + FormatCurrency(m_account.Balance());
   
   if(!SendNotification(title + "\n" + body))
   {
       string err = "❌ Push Notification FAILED (Error " + IntegerToString(GetLastError()) + ")";
       Print(err);
       Print("   >> Ensure MetaQuotes ID is set in Tools -> Options -> Notifications");
       
       if(m_dbManager != NULL) m_dbManager.LogSystemEvent("NotificationManager", "ERROR", err);
   }
   else
   {
       Print("✅ Startup Notification SENT");
   }
}

//+------------------------------------------------------------------+
//| Check for Session Changes                                         |
//+------------------------------------------------------------------+
void CNotificationManager::CheckSessionTransition(double equity)
{
   ENUM_TRADING_SESSION newSession = GetSessionForTime(TimeCurrent());
   
   if(newSession != m_currentSession)
   {
      // 1. Close Previous Session (Report)
      if(m_currentSession != SESSION_CLOSED)
      {
         SendSessionCloseAlert(m_currentSession, equity);
      }
      
      // 2. Open New Session (Alert)
      if(newSession != SESSION_CLOSED)
      {
         SendSessionOpenAlert(newSession, equity);
         
         // Reset Tracking for new session
         m_sessionStartEquity = equity;
         m_sessionStartBalance = m_account.Balance();
      }
      
      m_currentSession = newSession;
   }
}

//+------------------------------------------------------------------+
//| Determine Session from Time                                       |
//+------------------------------------------------------------------+
ENUM_TRADING_SESSION CNotificationManager::GetSessionForTime(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   int h = dt.hour;
   
   if(h >= m_asianStartHour && h < m_londonStartHour) return SESSION_ASIAN;
   if(h >= m_londonStartHour && h < m_nyStartHour)    return SESSION_LONDON;
   if(h >= m_nyStartHour && h < m_nyEndHour)          return SESSION_NEWYORK;
   
   return SESSION_CLOSED; 
}

//+------------------------------------------------------------------+
//| Get Session Name                                                  |
//+------------------------------------------------------------------+
string CNotificationManager::GetSessionName(ENUM_TRADING_SESSION session)
{
   switch(session)
   {
      case SESSION_ASIAN: return "Asian Session";
      case SESSION_LONDON: return "London Session";
      case SESSION_NEWYORK: return "New York Session";
      default: return "Market Closed";
   }
}

//+------------------------------------------------------------------+
//| Send Session Open Alert                                           |
//+------------------------------------------------------------------+
void CNotificationManager::SendSessionOpenAlert(ENUM_TRADING_SESSION session, double equity)
{
   string title = "🔔 " + GetSessionName(session) + " OPEN";
   string body = "";
   
   body += "Starting Session...\n";
   body += "💰 Bal: " + FormatCurrency(m_account.Balance()) + "\n";
   body += "📊 Eq: " + FormatCurrency(equity) + "\n";
   body += "🎯 Free Margin: " + FormatCurrency(m_account.FreeMargin());
   
   if(!SendNotification(title + "\n" + body))
   {
       Print("❌ Push Notification FAILED (Error ", GetLastError(), ")");
   }
   else
   {
       Print(title);
   }
}

//+------------------------------------------------------------------+
//| Send Session Close Alert                                          |
//+------------------------------------------------------------------+
void CNotificationManager::SendSessionCloseAlert(ENUM_TRADING_SESSION session, double equity)
{
   string title = "📊 " + GetSessionName(session) + " CLOSE";
   string body = "";
   
   double profit = equity - m_sessionStartEquity;
   string profitStr = (profit >= 0 ? "+" : "") + FormatCurrency(profit);
   string emoji = (profit >= 0 ? "✅" : "🔻");
   
   body += "Session Result: " + emoji + " " + profitStr + "\n";
   body += "💰 End Eq: " + FormatCurrency(equity) + "\n";
   body += "📈 Total PnL: " + FormatCurrency(equity - m_sessionStartBalance) + "\n"; // Day tracking approx
   
   SendNotification(title + "\n" + body);
   Print(title);
}

//+------------------------------------------------------------------+
//| Send Risk Alert                                                   |
//+------------------------------------------------------------------+
void CNotificationManager::SendRiskAlert(string message)
{
   if(!m_enabled) return;
   SendNotification("⚠️ RISK ALERT: " + message);
}

//+------------------------------------------------------------------+
//| Helper: Format Currency                                           |
//+------------------------------------------------------------------+
string CNotificationManager::FormatCurrency(double value)
{
   return "$" + DoubleToString(value, 2);
}

#endif
