//+------------------------------------------------------------------+
//|                                      PositionStateManager.mqh    |
//|                                 Universal Engine - Phase 3       |
//|                     Centralized position state management        |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7"
#property version   "1.00"
#property strict

#include "..\Learning_MFE_MAE.mqh"
#include "..\Memory\PatternMemory.mqh"

//+------------------------------------------------------------------+
//| Position State Structure                                         |
//| Tracks essential state for each open position                    |
//+------------------------------------------------------------------+
struct PositionState {
   ulong ticket;
   bool  partialClosed;
   double initialRisk;              // Risk percentage (0.30 = 0.30%)
   double dollarRisk;               // Actual dollar amount at risk for R-calculation
   double initialSLDist;            // SL distance in price units at entry — used for profitR (not current trailed SL)
   ENTRY_QUALITY quality;
   ConfluenceFactors entryFactors;  // Factors captured at entry bar — used for pattern learning at exit (not current bar)
};

//+------------------------------------------------------------------+
//| Position State Manager Class                                     |
//| Centralizes position state tracking, eliminating duplication     |
//+------------------------------------------------------------------+
class CPositionStateManager {
private:
   PositionState m_states[];
   int m_magicNumber;

public:
   //+------------------------------------------------------------------+
   //| Initialize manager with magic number                             |
   //+------------------------------------------------------------------+
   bool Init(int magicNumber) {
      m_magicNumber = magicNumber;
      ArrayResize(m_states, 0);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Find index of position state by ticket                           |
   //+------------------------------------------------------------------+
   int FindIndex(ulong ticket) {
      for(int i = 0; i < ArraySize(m_states); i++) {
         if(m_states[i].ticket == ticket)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Add new position to tracking                                     |
   //+------------------------------------------------------------------+
   bool AddPosition(ulong ticket, double riskPercent, double dollarRisk,
                    double slDistance, ENTRY_QUALITY quality,
                    ConfluenceFactors &factors) {

      // Check if already exists
      if(FindIndex(ticket) >= 0) {
         Print("WARNING: Position ", ticket, " already tracked");
         return false;
      }

      int size = ArraySize(m_states);
      ArrayResize(m_states, size + 1);

      m_states[size].ticket = ticket;
      m_states[size].partialClosed = false;
      m_states[size].initialRisk = riskPercent;
      m_states[size].dollarRisk = dollarRisk;
      m_states[size].initialSLDist = slDistance;
      m_states[size].quality = quality;
      m_states[size].entryFactors = factors;

      Print("Position State Added: Ticket=", ticket,
            " Risk=", riskPercent, "% ($", dollarRisk, ")",
            " Quality=", EnumToString(quality));

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get ticket by index                                              |
   //+------------------------------------------------------------------+
   ulong GetTicket(int index) {
      if(index >= 0 && index < ArraySize(m_states))
         return m_states[index].ticket;
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get individual fields by index                                   |
   //+------------------------------------------------------------------+
   bool GetPartialClosed(int index) {
      if(index >= 0 && index < ArraySize(m_states))
         return m_states[index].partialClosed;
      return false;
   }

   double GetInitialRisk(int index) {
      if(index >= 0 && index < ArraySize(m_states))
         return m_states[index].initialRisk;
      return 0;
   }

   double GetDollarRisk(int index) {
      if(index >= 0 && index < ArraySize(m_states))
         return m_states[index].dollarRisk;
      return 0;
   }

   double GetInitialSLDist(int index) {
      if(index >= 0 && index < ArraySize(m_states))
         return m_states[index].initialSLDist;
      return 0;
   }

   ENTRY_QUALITY GetQuality(int index) {
      if(index >= 0 && index < ArraySize(m_states))
         return m_states[index].quality;
      return EQ_WEAK;
   }

   void GetEntryFactors(int index, ConfluenceFactors &factors) {
      if(index >= 0 && index < ArraySize(m_states))
         factors = m_states[index].entryFactors;
   }

   //+------------------------------------------------------------------+
   //| Update partial close flag                                        |
   //+------------------------------------------------------------------+
   bool SetPartialClosed(ulong ticket, bool partialClosed = true) {
      int idx = FindIndex(ticket);
      if(idx >= 0) {
         m_states[idx].partialClosed = partialClosed;
         Print("Position ", ticket, " partial close flag set to ", partialClosed);
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Remove position from tracking                                    |
   //+------------------------------------------------------------------+
   bool RemovePosition(ulong ticket) {
      int idx = FindIndex(ticket);
      if(idx < 0) {
         Print("WARNING: Position ", ticket, " not found for removal");
         return false;
      }

      // Shift all subsequent elements down
      for(int i = idx; i < ArraySize(m_states) - 1; i++)
         m_states[i] = m_states[i + 1];

      ArrayResize(m_states, ArraySize(m_states) - 1);

      Print("Position State Removed: Ticket=", ticket);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get count of tracked positions                                   |
   //+------------------------------------------------------------------+
   int GetPositionCount() const {
      return ArraySize(m_states);
   }

   //+------------------------------------------------------------------+
   //| Clear all position states                                        |
   //+------------------------------------------------------------------+
   void Clear() {
      ArrayFree(m_states);
      Print("Position State Manager: All states cleared");
   }

   //+------------------------------------------------------------------+
   //| Check if position is tracked                                     |
   //+------------------------------------------------------------------+
   bool IsTracked(ulong ticket) const {
      for(int i = 0; i < ArraySize(m_states); i++) {
         if(m_states[i].ticket == ticket)
            return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Get total dollar risk across all positions                       |
   //+------------------------------------------------------------------+
   double GetTotalDollarRisk() const {
      double total = 0;
      for(int i = 0; i < ArraySize(m_states); i++)
         total += m_states[i].dollarRisk;
      return total;
   }

   //+------------------------------------------------------------------+
   //| Get total risk percentage across all positions                   |
   //+------------------------------------------------------------------+
   double GetTotalRiskPercent() const {
      double total = 0;
      for(int i = 0; i < ArraySize(m_states); i++)
         total += m_states[i].initialRisk;
      return total;
   }

   //+------------------------------------------------------------------+
   //| Print state summary for debugging                                |
   //+------------------------------------------------------------------+
   void PrintSummary() const {
      Print("====== POSITION STATE SUMMARY ======");
      Print("Magic Number: ", m_magicNumber);
      Print("Tracked Positions: ", ArraySize(m_states));
      Print("Total Risk: ", GetTotalRiskPercent(), "% ($", GetTotalDollarRisk(), ")");

      for(int i = 0; i < ArraySize(m_states); i++) {
         Print("  [", i, "] Ticket=", m_states[i].ticket,
               " Risk=", m_states[i].initialRisk, "%",
               " Partial=", m_states[i].partialClosed,
               " Quality=", EnumToString(m_states[i].quality));
      }
      Print("====================================");
   }
};
//+------------------------------------------------------------------+
