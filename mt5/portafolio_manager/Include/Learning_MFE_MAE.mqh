//+------------------------------------------------------------------+
//|                                           Learning_MFE_MAE.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef LEARNING_MFE_MAE_MQH
#define LEARNING_MFE_MAE_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

// Define ENTRY_QUALITY here as it is needed for state tracking
enum ENTRY_QUALITY { EQ_WEAK = 0, EQ_GOOD = 1, EQ_STRONG = 2, EQ_ELITE = 3 };

// Full State Tracking Struct
struct TradeState
{
   ulong  ticket;
   bool   partialClosed;
   double initialRisk;   
   ENTRY_QUALITY quality;
   
   // Tracking
   double mfe;
   double mae;
};

//+------------------------------------------------------------------+
//| LEARNING MODULE                                                   |
//| Responsibility: "How does price behave AFTER entry?"             |
//|                 + Owning Trade State & Quality                   |
//+------------------------------------------------------------------+
class CLearningEngine
{
private:
   TradeState m_states[];
   double     m_avgMFE;
   double     m_avgMAE;
   
public:
   CLearningEngine() : m_avgMFE(0), m_avgMAE(0) 
   {
      ArrayResize(m_states, 0);
   }
   
   // --- STATE MANAGEMENT ---
   
   void RegisterTrade(ulong ticket, double riskPoints, ENTRY_QUALITY quality)
   {
      int sz = ArraySize(m_states);
      ArrayResize(m_states, sz+1);
      
      m_states[sz].ticket = ticket;
      m_states[sz].partialClosed = false;
      m_states[sz].initialRisk = riskPoints;
      m_states[sz].quality = quality;
      m_states[sz].mfe = 0;
      m_states[sz].mae = 0;
   }
   
   // Main update loop called by Symbol Engine
   void UpdateTrade(ulong ticket, double openPrice, double currentPrice, int type)
   {
      int idx = FindIndex(ticket);
      if(idx == -1) // Auto-recovery if missing
      {
         RegisterTrade(ticket, 0, EQ_GOOD);
         idx = ArraySize(m_states) - 1;
      }
      
      double diff = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
      
      // Update MFE
      if(diff > m_states[idx].mfe) m_states[idx].mfe = diff;
      
      // Update MAE (Max Drawdown - positive value)
      if(diff < 0 && MathAbs(diff) > m_states[idx].mae) m_states[idx].mae = MathAbs(diff);
   }
   
   // Called when trade is closed
   double OnTradeClosed(ulong ticket)
   {
      int idx = FindIndex(ticket);
      if(idx == -1) return 0; // Not tracked
      
      double learnedMFE = m_states[idx].mfe;
      double learnedMAE = m_states[idx].mae;
      
      // Update Long Term Memory (Exp Moving Average)
      m_avgMFE = (m_avgMFE == 0) ? learnedMFE : (m_avgMFE * 0.9 + learnedMFE * 0.1);
      m_avgMAE = (m_avgMAE == 0) ? learnedMAE : (m_avgMAE * 0.9 + learnedMAE * 0.1);
      
      // Remove state
      for(int j=idx; j<ArraySize(m_states)-1; j++) m_states[j] = m_states[j+1];
      ArrayResize(m_states, ArraySize(m_states)-1);
      
      return learnedMAE; // Return MAE for analysis if needed
   }
   
   // --- GETTERS ---
   
   bool GetState(ulong ticket, bool &partialClosed, ENTRY_QUALITY &quality, double &initRisk)
   {
      int idx = FindIndex(ticket);
      if(idx == -1) return false;
      
      partialClosed = m_states[idx].partialClosed;
      quality = m_states[idx].quality;
      initRisk = m_states[idx].initialRisk;
      return true;
   }
   
   void SetPartialClosed(ulong ticket, bool closed)
   {
      int idx = FindIndex(ticket);
      if(idx != -1) m_states[idx].partialClosed = closed;
   }
   
   // --- INTELLIGENCE ---
   
   ENTRY_QUALITY CalculateQuality(double score)
   {
      if(score >= 6.0) return EQ_ELITE;
      if(score >= 5.0) return EQ_STRONG;
      if(score >= 4.0) return EQ_GOOD;
      return EQ_WEAK;
   }
   
   double GetLearnedTrail(double currentATR)
   {
      if(m_avgMFE <= 0) return 0;
      return m_avgMFE * 0.55;
   }
   
   double GetLearnedBE(double riskPoints)
   {
      if(m_avgMAE <= 0 || riskPoints == 0) return 0;
      return (m_avgMAE / riskPoints) * 1.2;
   }
   
   double GetAvgMFE() { return m_avgMFE; }
   double GetAvgMAE() { return m_avgMAE; }

private:
   int FindIndex(ulong ticket)
   {
      for(int i=0; i<ArraySize(m_states); i++)
         if(m_states[i].ticket == ticket) return i;
      return -1;
   }
};

#endif
