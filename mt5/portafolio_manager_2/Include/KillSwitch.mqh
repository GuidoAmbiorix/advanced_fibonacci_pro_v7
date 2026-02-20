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

//+------------------------------------------------------------------+
//| KILL SWITCH MODULE                                                |
//| Responsibility: "Protect Capital Aggressively"                   |
//+------------------------------------------------------------------+
class CKillSwitch
{
private:
   double   m_rollingR;
   double   m_winRate;
   int      m_totalTrades;
   int      m_wins;
   bool     m_hardLock;
   datetime m_disabledUntil;

public:
   CKillSwitch() : m_rollingR(0), m_winRate(0), m_totalTrades(0), m_wins(0), m_hardLock(false), m_disabledUntil(0) {}

   void OnTradeClosed(double rOutcome)
   {
      m_totalTrades++;
      if(rOutcome > 0) m_wins++;

      // Update Win Rate
      m_winRate = (m_totalTrades > 0) ? (double)m_wins / m_totalTrades : 0;

      // Update Rolling R (exponential moving average)
      m_rollingR = (m_rollingR == 0) ? rOutcome : (m_rollingR * 0.9 + rOutcome * 0.1);

      // Auto-Cooldown on heavy loss
      if(rOutcome < -1.5)
      {
         m_disabledUntil = TimeCurrent() + 1800; // 30m Cooldown
         Print("⛔ KillSwitch: Heavy Loss. Cooldown 30m.");
      }
   }

   bool IsEnabled()
   {
      // Check cooldown
      if(TimeCurrent() < m_disabledUntil) return false;

      // Hard lock: auto-reset daily in backtest, permanent in live
      if(m_hardLock)
      {
         if(MQLInfoInteger(MQL_TESTER))
         {
            // In backtest: reset hard lock after 24h so other days can be tested
            if(TimeCurrent() >= m_disabledUntil + 86400)
            {
               m_hardLock = false;
               m_rollingR = 0;
               Print("🔄 KillSwitch: Daily reset (backtest mode)");
            }
            else
               return false;
         }
         else
            return false;  // Live: hard lock is permanent until manual reset
      }

      // Check rolling R threshold
      if(m_rollingR < -3.0)
      {
         m_hardLock = true;
         m_disabledUntil = TimeCurrent();
         Print("💀 KillSwitch: Rolling R=", DoubleToString(m_rollingR, 2), " below -3.0. Hard lock engaged.");
         return false;
      }

      return true;
   }

   string GetStatus()
   {
      if(TimeCurrent() < m_disabledUntil) return "🥶 COOL " + IntegerToString((int)(m_disabledUntil-TimeCurrent())/60) + "m";
      if(!IsEnabled()) return "💀 KILLED";
      return "🟢 ACTIVE";
   }

   double GetRollingR() { return m_rollingR; }
   double GetWinRate() { return m_winRate; }

   void Reset()
   {
      m_hardLock = false;
      m_disabledUntil = 0;
   }
};

#endif
