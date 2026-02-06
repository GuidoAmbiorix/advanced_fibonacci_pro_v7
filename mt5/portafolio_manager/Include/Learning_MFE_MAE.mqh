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
//|                 + Persistent Memory (File Storage)               |
//+------------------------------------------------------------------+
class CLearningEngine
{
private:
   TradeState m_states[];
   double     m_avgMFE;
   double     m_avgMAE;

   // Persistence
   string     m_symbol;
   string     m_dataFile;
   bool       m_persistenceEnabled;

public:
   CLearningEngine() : m_avgMFE(0), m_avgMAE(0), m_symbol(""), m_persistenceEnabled(false)
   {
      ArrayResize(m_states, 0);
   }

   //+------------------------------------------------------------------+
   //| Initialize with persistence                                       |
   //+------------------------------------------------------------------+
   bool Init(string symbol, bool enablePersistence = true)
   {
      m_symbol = symbol;
      m_persistenceEnabled = enablePersistence;

      if(m_persistenceEnabled)
      {
         m_dataFile = "SymbolEngine_Learning_" + m_symbol + ".dat";

         // Try to load existing data
         if(!LoadFromFile())
         {
            Print("Learning: Starting fresh (no saved data)");
         }
         else
         {
            Print("Learning: Loaded MFE=", DoubleToString(m_avgMFE, 5),
                  " MAE=", DoubleToString(m_avgMAE, 5));
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Deinitialize - save data on exit                                 |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      if(m_persistenceEnabled)
         SaveToFile();
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

   //+------------------------------------------------------------------+
   //| Get MFE/MAE for specific ticket                                  |
   //+------------------------------------------------------------------+
   bool GetMFEMAE(ulong ticket, double &mfe, double &mae)
   {
      int idx = FindIndex(ticket);
      if(idx == -1) return false;

      mfe = m_states[idx].mfe;
      mae = m_states[idx].mae;
      return true;
   }

private:
   int FindIndex(ulong ticket)
   {
      for(int i=0; i<ArraySize(m_states); i++)
         if(m_states[i].ticket == ticket) return i;
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Save learning data to file                                       |
   //+------------------------------------------------------------------+
   bool SaveToFile()
   {
      if(!m_persistenceEnabled) return false;

      int fileHandle = FileOpen(m_dataFile, FILE_WRITE|FILE_BIN|FILE_COMMON);

      if(fileHandle == INVALID_HANDLE)
      {
         Print("Learning ERROR: Cannot save to file");
         return false;
      }

      // Write version
      int version = 2;
      FileWriteInteger(fileHandle, version);

      // Write averages
      FileWriteDouble(fileHandle, m_avgMFE);
      FileWriteDouble(fileHandle, m_avgMAE);

      // Write symbol with length prefix
      int symLen = StringLen(m_symbol);
      FileWriteInteger(fileHandle, symLen);
      FileWriteString(fileHandle, m_symbol, symLen);

      // Write timestamp
      FileWriteLong(fileHandle, TimeCurrent());

      FileClose(fileHandle);

      Print("Learning: Saved data to file | MFE=", DoubleToString(m_avgMFE, 5),
            " MAE=", DoubleToString(m_avgMAE, 5));
      return true;
   }

   //+------------------------------------------------------------------+
   //| Load learning data from file                                     |
   //+------------------------------------------------------------------+
   bool LoadFromFile()
   {
      if(!m_persistenceEnabled) return false;
      if(!FileIsExist(m_dataFile, FILE_COMMON)) return false;

      int fileHandle = FileOpen(m_dataFile, FILE_READ|FILE_BIN|FILE_COMMON);

      if(fileHandle == INVALID_HANDLE)
      {
         Print("Learning WARNING: Cannot load from file");
         return false;
      }

      // Read version
      int version = FileReadInteger(fileHandle);

      if(version != 2)
      {
         Print("Learning: Data version upgrade (", version, "->2). Starting fresh.");
         FileClose(fileHandle);
         return false;
      }

      // Read averages
      m_avgMFE = FileReadDouble(fileHandle);
      m_avgMAE = FileReadDouble(fileHandle);

      // Read symbol (verify it matches)
      int symLen = FileReadInteger(fileHandle);
      string savedSymbol = FileReadString(fileHandle, symLen);
      if(savedSymbol != m_symbol)
      {
         Print("Learning WARNING: Symbol mismatch (saved:", savedSymbol, " current:", m_symbol, ")");
         FileClose(fileHandle);
         return false;
      }

      // Read timestamp (for info)
      datetime savedTime = (datetime)FileReadLong(fileHandle);

      FileClose(fileHandle);

      Print("Learning: Loaded data from ", TimeToString(savedTime, TIME_DATE));
      return true;
   }
};

#endif
