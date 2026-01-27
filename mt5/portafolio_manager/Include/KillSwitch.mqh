//+------------------------------------------------------------------+
//|                                                   KillSwitch.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef KILLSWITCH_MQH
#define KILLSWITCH_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include "PortfolioGlobals.mqh" 

//+------------------------------------------------------------------+
//| KILL REASON ENUM                                                  |
//+------------------------------------------------------------------+
enum ENUM_KILL_REASON
{
   KILL_NONE = 0,
   KILL_DRAWDOWN = 1,         // Max Account Drawdown Hit
   KILL_DAILY_LOSS = 2,       // Max Daily Loss Hit
   KILL_CONSECUTIVE_LOSS = 3, // Too many losses in a row
   KILL_CONNECTION_LOST = 4,  // Ping too high or no connection
   KILL_MARGIN_CALL = 5,      // Free margin dangerously low
   KILL_MANUAL = 6,           // Manually triggered
   KILL_ROLLING_R = 7         // Strategy failure
};

//+------------------------------------------------------------------+
//| CONNECTION MONITOR CLASS                                          |
//+------------------------------------------------------------------+
class CConnectionMonitor
{
private:
   datetime m_lastTickTime;
   int      m_tickDropCount;
   int      m_maxLatency;
   
   datetime m_initTime;
   
public:
   CConnectionMonitor() : m_lastTickTime(0), m_tickDropCount(0), m_maxLatency(500) 
   {
      m_initTime = TimeCurrent();
   }
   
   void OnTick()
   {
      m_lastTickTime = TimeCurrent();
      m_tickDropCount = 0;
   }
   
   bool IsStable(string &outReason)
   {
      // 0. Warmup Period (10 seconds)
      if(TimeCurrent() - m_initTime < 10) return true;
      
      // Check 1: Terminal Connected
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      {
         outReason = "Terminal Disconnected";
         return false;
      }
      
      // Check 2: Tick Gap (Heartbeat) - 60s without tick is suspicious
      if(TimeCurrent() - m_lastTickTime > 60)
      {
         m_tickDropCount++;
         if(m_tickDropCount > 3) // 3 checks failed
         {
            outReason = "No Ticks for " + IntegerToString((int)(TimeCurrent() - m_lastTickTime)) + "s";
            return false;
         }
      }
      
      // Check 3: Ping (TERMINAL_PING_LAST is in microseconds)
      long pingMicro = TerminalInfoInteger(TERMINAL_PING_LAST);
      
      // Filter out invalid ping (-1) or extreme startup spikes
      if(pingMicro < 0) return true; 
      
      int pingMs = (int)(pingMicro / 1000);
      
      if(pingMs > m_maxLatency)
      {
         outReason = "High Latency: " + IntegerToString(pingMs) + "ms";
         return false;
      }
      
      return true;
   }
};

//+------------------------------------------------------------------+
//| KILL SWITCH MODULE                                                |
//| Responsibility: "Protect Capital Aggressively"                   |
//+------------------------------------------------------------------+
class CKillSwitch
{
private:
   CTrade         m_trade;
   CAccountInfo   m_account;
   CConnectionMonitor m_connMonitor;
   
   // Limits
   double         m_maxDrawdownPercent;
   double         m_maxDailyDD;
   double         m_minMarginLevel;
   int            m_maxConsecutiveLosses;
   
   // State
   bool           m_hardLock;
   ENUM_KILL_REASON m_killReason;
   datetime       m_disabledUntil;
   
   // Daily Tracking
   double         m_dailyStartEquity;
   datetime       m_lastDayCheck;
   
   // Performance Tracking
   int            m_consecutiveLosses;
   double         m_rollingR;
   
   // Emergency Close State
   bool           m_isEmergencyClosing;
   datetime       m_lastCloseAttempt;

public:
   CKillSwitch() : m_maxDrawdownPercent(10.0), m_maxDailyDD(5.0), m_minMarginLevel(100.0),
                   m_maxConsecutiveLosses(5), m_hardLock(false), m_killReason(KILL_NONE),
                   m_disabledUntil(0), m_dailyStartEquity(0), m_lastDayCheck(0),
                   m_consecutiveLosses(0), m_rollingR(0), m_isEmergencyClosing(false), m_lastCloseAttempt(0) {}

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(double maxDD, double dailyDD, double minMargin, int maxLosses)
   {
      m_maxDrawdownPercent = maxDD;
      m_maxDailyDD = dailyDD;
      m_minMarginLevel = minMargin;
      m_maxConsecutiveLosses = maxLosses;
      
      m_dailyStartEquity = m_account.Equity();
      m_lastDayCheck = TimeCurrent();
      
      Print("🛡️ KillSwitch HARDENED v2.1");
      Print("   Max DD: ", maxDD, "% | Daily Limit: ", dailyDD, "% | Min Margin: ", minMargin, "%");
   }

   //+------------------------------------------------------------------+
   //| OnTick Monitor                                                    |
   //+------------------------------------------------------------------+
   void OnTick()
   {
      m_connMonitor.OnTick();
   }

   //+------------------------------------------------------------------+
   //| Main Monitoring Function                                          |
   //+------------------------------------------------------------------+
   bool CheckSafety()
   {
      if(m_hardLock) return false;
      
      // 1. Connection Monitor
      string connMsg;
      if(!m_connMonitor.IsStable(connMsg))
      {
         TriggerKill(KILL_CONNECTION_LOST, "Connection Unstable: " + connMsg);
         return false;
      }
      
      // 2. Check Margin
      double marginLevel = m_account.MarginLevel();
      if(marginLevel > 0 && marginLevel < m_minMarginLevel)
      {
         TriggerKill(KILL_MARGIN_CALL, "Critical Margin Level: " + DoubleToString(marginLevel, 2) + "%");
         return false;
      }
      
      // 3. New Day Reset
      CheckNewDay();
      
      // 4. Check Daily Drawdown
      double currentEquity = m_account.Equity();
      if(m_dailyStartEquity > 0)
      {
         double dailyLoss = ((m_dailyStartEquity - currentEquity) / m_dailyStartEquity) * 100.0;
         if(dailyLoss >= m_maxDailyDD)
         {
            TriggerKill(KILL_DAILY_LOSS, "Daily Loss Limit Hit: " + DoubleToString(dailyLoss, 2) + "%");
            return false;
         }
      }
      
      // 5. Check Peak Drawdown (Global)
      double peak = GlobalVariableGet(GV_PEAK_EQUITY);
      if(peak > 0)
      {
         double dd = ((peak - currentEquity) / peak) * 100.0;
         if(dd >= m_maxDrawdownPercent)
         {
            TriggerKill(KILL_DRAWDOWN, "Max Peak Drawdown Hit: " + DoubleToString(dd, 2) + "%");
            return false;
         }
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update Trade Results                                              |
   //+------------------------------------------------------------------+
   void OnTradeClosed(double rOutcome)
   {
      // ... same as before ...
      if(rOutcome < 0) m_consecutiveLosses++;
      else m_consecutiveLosses = 0;
      
      if(m_consecutiveLosses >= m_maxConsecutiveLosses)
      {
         m_disabledUntil = TimeCurrent() + 3600;
         Print("⚠️ KillSwitch: Loss Streak Cooldown (1h)");
         m_consecutiveLosses = 0;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Emergency Close All (Redundant Fail-Safe)                         |
   //+------------------------------------------------------------------+
   void EmergencyCloseAll()
   {
      if(m_isEmergencyClosing)
      {
         // Prevent re-entry rapid fire, space out attempts by 5s
         if(TimeCurrent() - m_lastCloseAttempt < 5) return;
      }
      
      m_isEmergencyClosing = true;
      m_lastCloseAttempt = TimeCurrent();
      
      Print("🚨 EMERGENCY CLOSE INITIATED 🚨");
      
      // PHASE 1: Graceful Close
      bool allClosed = CloseAllPositionsGraceful();
      
      // PHASE 2: Aggressive Hedge (if graceful failed)
      if(!allClosed)
      {
         Print("⚠️ Graceful close incomplete. Attempting AGGRESSIVE CLOSE.");
         CloseAllPositionsAggressive();
      }
      
      // PHASE 3: Nuclear (ExpertRemove if positions still stuck)
      if(PositionsTotal() > 0)
      {
         Print("💀 CRITICAL FAILURE: Positions STUCK. Disabling EA.");
         ExpertRemove(); 
      }
      
      m_isEmergencyClosing = false;
   }
   
   //+------------------------------------------------------------------+
   //| Trigger Kill                                                      |
   //+------------------------------------------------------------------+
   void TriggerKill(ENUM_KILL_REASON reason, string msg)
   {
      if(m_hardLock) return;
      
      m_hardLock = true;
      m_killReason = reason;
      Print("💀 KILL SWITCH TRIGGERED: ", msg);
      
      EmergencyCloseAll();
      
      GlobalVariableSet(GV_GOVERNOR_ACTIVE, 0);
      GlobalVariableSet(GV_TRADING_ENABLED, 0);
   }
   
   //+------------------------------------------------------------------+
   //| Reset Logic                                                       |
   //+------------------------------------------------------------------+
   bool Reset(string password)
   {
      if(password != "I_AM_SURE") return false;
      m_hardLock = false;
      m_killReason = KILL_NONE;
      m_dailyStartEquity = m_account.Equity();
      Print("♻️ KillSwitch RESET");
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Getters                                                           |
   //+------------------------------------------------------------------+
   bool IsEnabled() { return !m_hardLock && (TimeCurrent() >= m_disabledUntil); }
   
   string GetStatus()
   {
      if(m_hardLock) return "💀 DEAD (" + EnumToString(m_killReason) + ")";
      if(TimeCurrent() < m_disabledUntil) return "🥶 COOL";
      return "🟢 ACTIVE";
   }
   
   bool IsConnStable(string &reason) { return m_connMonitor.IsStable(reason); }

private:
   void CheckNewDay()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      MqlDateTime last;
      TimeToStruct(m_lastDayCheck, last);
      
      if(dt.day != last.day)
      {
         m_dailyStartEquity = m_account.Equity();
         m_lastDayCheck = TimeCurrent();
         m_consecutiveLosses = 0;
      }
   }
   
   bool CloseAllPositionsGraceful()
   {
      int initialTotal = PositionsTotal();
      if(initialTotal == 0) return true;
      
      CTrade trade;
      trade.SetAsyncMode(false); // Sync
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) trade.PositionClose(ticket);
      }
      
      return (PositionsTotal() == 0);
   }
   
   void CloseAllPositionsAggressive()
   {
      // Hedge logic: Open opposite to lock PnL
      CTrade trade;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
             string sym = PositionGetString(POSITION_SYMBOL);
             long type = PositionGetInteger(POSITION_TYPE);
             double vol = PositionGetDouble(POSITION_VOLUME);
             
             ENUM_ORDER_TYPE opType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
             double price = (opType == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
             
             trade.PositionOpen(sym, opType, vol, price, 0, 0, "EMERGENCY HEDGE");
         }
      }
   }
};

#endif
