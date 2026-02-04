//+------------------------------------------------------------------+
//|                                              TradeJournal.mqh    |
//|                         Persistent Trade History Logger           |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef TRADE_JOURNAL_MQH
#define TRADE_JOURNAL_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "../Learning_MFE_MAE.mqh"  // For ENTRY_QUALITY enum
#include "../KillzoneConfig.mqh"     // For ENUM_KILLZONE
#include "../MarketRegime.mqh"       // For MARKET_REGIME enum
#include "../Lib/DatabaseManager.mqh"


//+------------------------------------------------------------------+
//| TRADE CONTEXT STRUCTURE (Entry Information)                      |
//+------------------------------------------------------------------+
struct TradeContext
{
   // Identification
   ulong          ticket;
   datetime       entryTime;
   string         symbol;

   // Market Context
   ENUM_KILLZONE  killzone;
   int            dayOfWeek;           // 0=Sunday, 1=Monday, etc.
   MARKET_REGIME  regime;

   // Entry Analysis
   ENUM_ENTRY_TIER quality;
   double         confluenceScore;

   // Trade Details
   int            direction;           // 1=Buy, -1=Sell
   double         entryPrice;
   double         sl;
   double         tp;
   double         lots;
   double         riskPercent;

   // System State at Entry
   double         winRateAtEntry;
   double         rollingRAtEntry;

   // Initialize with defaults
   TradeContext() : ticket(0), entryTime(0), symbol(""),
                    killzone(KILLZONE_NONE), dayOfWeek(0), regime(REGIME_UNKNOWN),
                    quality(TIER_GOOD), confluenceScore(0), direction(0),
                    entryPrice(0), sl(0), tp(0), lots(0), riskPercent(0),
                    winRateAtEntry(0), rollingRAtEntry(0) {}
};

//+------------------------------------------------------------------+
//| EXIT CONTEXT STRUCTURE (Exit Information)                        |
//+------------------------------------------------------------------+
struct ExitContext
{
   datetime       exitTime;
   double         exitPrice;
   string         exitType;            // "TP", "SL", "Trail", "Manual", "Partial"
   double         profitR;              // Profit in R multiples
   double         profitMoney;          // Profit in account currency
   int            durationMinutes;      // Trade duration
   double         mfe;                  // Maximum Favorable Excursion
   double         mae;                  // Maximum Adverse Excursion
   bool           partialClosed;        // Was position partially closed

   // Initialize with defaults
   ExitContext() : exitTime(0), exitPrice(0), exitType(""),
                   profitR(0), profitMoney(0), durationMinutes(0),
                   mfe(0), mae(0), partialClosed(false) {}
};

//+------------------------------------------------------------------+
//| COMPLETE TRADE RECORD (Entry + Exit)                             |
//+------------------------------------------------------------------+
struct TradeRecord
{
   TradeContext   entry;
   ExitContext    exit;
   bool           isOpen;               // true if exit not logged yet

   TradeRecord() : isOpen(true) {}
};

//+------------------------------------------------------------------+
//| TRADE JOURNAL CLASS                                               |
//| Responsibility: Persist all trades with full context to CSV      |
//+------------------------------------------------------------------+
class CTradeJournal
{
private:
   string         m_symbol;
   string         m_csvPath;
   CDatabaseManager *m_db;       // CheckPointer before use
   TradeRecord    m_cache[];            // In-memory cache

   int            m_cacheSize;
   int            m_maxCacheSize;       // Flush to disk after this many records
   datetime       m_lastFlush;
   int            m_totalTrades;        // Total trades logged lifetime
   int            m_retentionDays;      // Days to keep history

public:
   CTradeJournal() : m_cacheSize(0), m_maxCacheSize(100), m_db(NULL),
                     m_lastFlush(0), m_totalTrades(0), m_retentionDays(180) {}


   ~CTradeJournal() { Flush(); }        // Ensure data is saved on destruction

   //+------------------------------------------------------------------+
   //| Initialize Trade Journal                                          |
   //+------------------------------------------------------------------+
   bool Init(string symbol, int retentionDays = 180, CDatabaseManager *db = NULL)
   {
      m_symbol = symbol;
      m_retentionDays = retentionDays;
      m_db = db;


      // Create file path
      m_csvPath = "SymbolEngine_Trades_" + m_symbol + ".csv";

      // Initialize cache
      ArrayResize(m_cache, 0);
      m_cacheSize = 0;

      // Create CSV file with header if it doesn't exist
      if(!FileIsExist(m_csvPath, FILE_COMMON))
      {
         if(!WriteHeader())
         {
            Print("TradeJournal ERROR: Failed to create CSV file");
            return false;
         }
      }

      // Load recent history
      LoadRecent(m_retentionDays);

      Print("TradeJournal initialized: ", m_symbol, " | Trades loaded: ", m_cacheSize);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Log Trade Entry                                                   |
   //+------------------------------------------------------------------+
   void LogEntry(TradeContext &ctx)
   {
      // Add to cache
      int idx = m_cacheSize;
      ArrayResize(m_cache, m_cacheSize + 1);

      m_cache[idx].entry = ctx;
      m_cache[idx].isOpen = true;
      m_cacheSize++;

      Print("TradeJournal: Logged entry #", ctx.ticket, " | Confluence: ",
            DoubleToString(ctx.confluenceScore, 1), " | Killzone: ",
            KillzoneToString(ctx.killzone));

      // DB LOGGING
      if(CheckPointer(m_db) != POINTER_INVALID)
      {
         string strategy = "Governor_SMC"; // Default strategy tag
         m_db.LogTradeEntry(ctx.ticket, ctx.symbol, ctx.direction == 1 ? 0 : 1, ctx.lots,
                            ctx.entryPrice, ctx.sl, ctx.tp, ctx.confluenceScore,
                            strategy, EnumToString(ctx.regime), KillzoneToString(ctx.killzone));
      }

      // Auto-flush if cache is large
      if(m_cacheSize >= m_maxCacheSize)

         Flush();
   }

   //+------------------------------------------------------------------+
   //| Log Trade Exit                                                    |
   //+------------------------------------------------------------------+
   void LogExit(ulong ticket, ExitContext &exitCtx)
   {
      // Find trade in cache
      int idx = FindTradeIndex(ticket);

      if(idx >= 0)
      {
         m_cache[idx].exit = exitCtx;
         m_cache[idx].isOpen = false;

         Print("TradeJournal: Logged exit #", ticket, " | R: ",
               DoubleToString(exitCtx.profitR, 2), " | Exit: ", exitCtx.exitType);

         // DB LOGGING
         if(CheckPointer(m_db) != POINTER_INVALID)
         {
             m_db.LogTradeExit(ticket, exitCtx.exitPrice, exitCtx.profitMoney,
                               0.0, 0.0, // Commission/Swap not passed in ctx yet, assuming filtered later or 0
                               exitCtx.exitType, exitCtx.mfe, exitCtx.mae);
         }

         // Flush completed trade immediately
         FlushTrade(idx);
      }
      else
      {
         Print("TradeJournal WARNING: Exit logged for unknown ticket #", ticket);
      }
   }

   //+------------------------------------------------------------------+
   //| Flush Single Trade to CSV                                         |
   //+------------------------------------------------------------------+
   void FlushTrade(int idx)
   {
      if(idx < 0 || idx >= m_cacheSize) return;
      if(m_cache[idx].isOpen) return;  // Don't flush open trades

      // Open file in append mode
      int fileHandle = FileOpen(m_csvPath, FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON, ',');

      if(fileHandle == INVALID_HANDLE)
      {
         Print("TradeJournal ERROR: Cannot open CSV file for writing");
         return;
      }

      // Move to end of file
      FileSeek(fileHandle, 0, SEEK_END);

      // Write trade data
      WriteTradeToFile(fileHandle, m_cache[idx]);

      FileClose(fileHandle);
      m_totalTrades++;

      // Remove from cache
      for(int i = idx; i < m_cacheSize - 1; i++)
         m_cache[i] = m_cache[i + 1];

      ArrayResize(m_cache, m_cacheSize - 1);
      m_cacheSize--;
   }

   //+------------------------------------------------------------------+
   //| Flush All Completed Trades to CSV                                |
   //+------------------------------------------------------------------+
   void Flush()
   {
      int flushedCount = 0;

      for(int i = m_cacheSize - 1; i >= 0; i--)
      {
         if(!m_cache[i].isOpen)
         {
            FlushTrade(i);
            flushedCount++;
         }
      }

      if(flushedCount > 0)
      {
         m_lastFlush = TimeCurrent();
         Print("TradeJournal: Flushed ", flushedCount, " trades to CSV");
      }
   }

   //+------------------------------------------------------------------+
   //| Load Recent Trades from CSV                                       |
   //+------------------------------------------------------------------+
   bool LoadRecent(int days)
   {
      if(!FileIsExist(m_csvPath, FILE_COMMON))
         return true;  // No history yet, not an error

      int fileHandle = FileOpen(m_csvPath, FILE_READ|FILE_CSV|FILE_COMMON, ',');

      if(fileHandle == INVALID_HANDLE)
      {
         Print("TradeJournal WARNING: Cannot open CSV file for reading");
         return false;
      }

      // Skip header line
      string header = FileReadString(fileHandle);

      // Calculate cutoff time
      datetime cutoff = TimeCurrent() - (days * 24 * 60 * 60);

      int loadedCount = 0;

      // Read all trades
      while(!FileIsEnding(fileHandle))
      {
         TradeRecord record = ReadTradeFromFile(fileHandle);

         // Only load recent trades
         if(record.entry.entryTime >= cutoff)
         {
            // Add to cache (but mark as closed since we're loading history)
            record.isOpen = false;

            ArrayResize(m_cache, m_cacheSize + 1);
            m_cache[m_cacheSize] = record;
            m_cacheSize++;
            loadedCount++;
         }
      }

      FileClose(fileHandle);

      Print("TradeJournal: Loaded ", loadedCount, " trades from last ", days, " days");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Trades (filtered)                                            |
   //+------------------------------------------------------------------+
   void GetTrades(TradeRecord &output[], string filter = "")
   {
      // For now, return all closed trades
      // Future: implement filtering by killzone, regime, etc.

      int count = 0;
      for(int i = 0; i < m_cacheSize; i++)
      {
         if(!m_cache[i].isOpen)
            count++;
      }

      ArrayResize(output, count);
      int idx = 0;

      for(int i = 0; i < m_cacheSize; i++)
      {
         if(!m_cache[i].isOpen)
         {
            output[idx] = m_cache[i];
            idx++;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get Total Trades Logged                                          |
   //+------------------------------------------------------------------+
   int GetTotalTrades() { return m_totalTrades + m_cacheSize; }

   //+------------------------------------------------------------------+
   //| Get Open Trades Count                                            |
   //+------------------------------------------------------------------+
   int GetOpenTrades()
   {
      int count = 0;
      for(int i = 0; i < m_cacheSize; i++)
         if(m_cache[i].isOpen) count++;
      return count;
   }

private:
   //+------------------------------------------------------------------+
   //| Find Trade Index in Cache                                        |
   //+------------------------------------------------------------------+
   int FindTradeIndex(ulong ticket)
   {
      for(int i = 0; i < m_cacheSize; i++)
      {
         if(m_cache[i].entry.ticket == ticket)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Write CSV Header                                                  |
   //+------------------------------------------------------------------+
   bool WriteHeader()
   {
      int fileHandle = FileOpen(m_csvPath, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');

      if(fileHandle == INVALID_HANDLE)
         return false;

      // Write header
      FileWrite(fileHandle, "Timestamp", "Ticket", "Symbol", "Killzone", "DayOfWeek",
                "Regime", "EntryQuality", "ConfluenceScore", "Direction", "EntryPrice",
                "SL", "TP", "Lots", "RiskPercent", "ExitTime", "ExitPrice", "ExitType",
                "ProfitR", "ProfitMoney", "Duration", "MFE", "MAE", "PartialClosed",
                "WinRateAtEntry", "RollingRAtEntry");

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Write Trade to File                                              |
   //+------------------------------------------------------------------+
   void WriteTradeToFile(int fileHandle, TradeRecord &record)
   {
      FileWrite(fileHandle,
         TimeToString(record.entry.entryTime, TIME_DATE|TIME_MINUTES),
         IntegerToString(record.entry.ticket),
         record.entry.symbol,
         KillzoneToString(record.entry.killzone),
         IntegerToString(record.entry.dayOfWeek),
         IntegerToString((int)record.entry.regime),
         IntegerToString((int)record.entry.quality),
         DoubleToString(record.entry.confluenceScore, 2),
         IntegerToString(record.entry.direction),
         DoubleToString(record.entry.entryPrice, 5),
         DoubleToString(record.entry.sl, 5),
         DoubleToString(record.entry.tp, 5),
         DoubleToString(record.entry.lots, 2),
         DoubleToString(record.entry.riskPercent, 3),
         TimeToString(record.exit.exitTime, TIME_DATE|TIME_MINUTES),
         DoubleToString(record.exit.exitPrice, 5),
         record.exit.exitType,
         DoubleToString(record.exit.profitR, 3),
         DoubleToString(record.exit.profitMoney, 2),
         IntegerToString(record.exit.durationMinutes),
         DoubleToString(record.exit.mfe, 5),
         DoubleToString(record.exit.mae, 5),
         record.exit.partialClosed ? "YES" : "NO",
         DoubleToString(record.entry.winRateAtEntry, 3),
         DoubleToString(record.entry.rollingRAtEntry, 3)
      );
   }

   //+------------------------------------------------------------------+
   //| Read Trade from File                                             |
   //+------------------------------------------------------------------+
   TradeRecord ReadTradeFromFile(int fileHandle)
   {
      TradeRecord record;

      // Read all fields (must match header order)
      string timestamp = FileReadString(fileHandle);
      string ticketStr = FileReadString(fileHandle);
      record.entry.symbol = FileReadString(fileHandle);
      string killzoneStr = FileReadString(fileHandle);
      string dowStr = FileReadString(fileHandle);
      string regimeStr = FileReadString(fileHandle);
      string qualityStr = FileReadString(fileHandle);
      string confStr = FileReadString(fileHandle);
      string dirStr = FileReadString(fileHandle);
      string entryPriceStr = FileReadString(fileHandle);
      string slStr = FileReadString(fileHandle);
      string tpStr = FileReadString(fileHandle);
      string lotsStr = FileReadString(fileHandle);
      string riskStr = FileReadString(fileHandle);
      string exitTimeStr = FileReadString(fileHandle);
      string exitPriceStr = FileReadString(fileHandle);
      record.exit.exitType = FileReadString(fileHandle);
      string profitRStr = FileReadString(fileHandle);
      string profitMoneyStr = FileReadString(fileHandle);
      string durationStr = FileReadString(fileHandle);
      string mfeStr = FileReadString(fileHandle);
      string maeStr = FileReadString(fileHandle);
      string partialStr = FileReadString(fileHandle);
      string winRateStr = FileReadString(fileHandle);
      string rollingRStr = FileReadString(fileHandle);

      // Parse entry data
      record.entry.entryTime = StringToTime(timestamp);
      record.entry.ticket = (ulong)StringToInteger(ticketStr);
      record.entry.dayOfWeek = (int)StringToInteger(dowStr);
      record.entry.regime = (MARKET_REGIME)StringToInteger(regimeStr);
      record.entry.quality = (ENUM_ENTRY_TIER)StringToInteger(qualityStr);
      record.entry.confluenceScore = StringToDouble(confStr);
      record.entry.direction = (int)StringToInteger(dirStr);
      record.entry.entryPrice = StringToDouble(entryPriceStr);
      record.entry.sl = StringToDouble(slStr);
      record.entry.tp = StringToDouble(tpStr);
      record.entry.lots = StringToDouble(lotsStr);
      record.entry.riskPercent = StringToDouble(riskStr);
      record.entry.winRateAtEntry = StringToDouble(winRateStr);
      record.entry.rollingRAtEntry = StringToDouble(rollingRStr);

      // Parse exit data
      record.exit.exitTime = StringToTime(exitTimeStr);
      record.exit.exitPrice = StringToDouble(exitPriceStr);
      record.exit.profitR = StringToDouble(profitRStr);
      record.exit.profitMoney = StringToDouble(profitMoneyStr);
      record.exit.durationMinutes = (int)StringToInteger(durationStr);
      record.exit.mfe = StringToDouble(mfeStr);
      record.exit.mae = StringToDouble(maeStr);
      record.exit.partialClosed = (partialStr == "YES");

      record.isOpen = false;

      return record;
   }
};

#endif
