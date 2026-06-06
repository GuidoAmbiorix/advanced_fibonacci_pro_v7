//+------------------------------------------------------------------+
//|                                              DatabaseManager.mqh |
//|          SQLite Database Manager for Portfolio Governor          |
//|                                  Copyright 2026, Infernal Portfolio Governor   |
//+------------------------------------------------------------------+
#ifndef DATABASE_MANAGER_MQH
#define DATABASE_MANAGER_MQH

#property copyright "Infernal Portfolio Governor"
#property strict

#include "KillzoneConfig.mqh"     // For ENUM_KILLZONE
#include "MarketRegime.mqh"       // For MARKET_REGIME enum
#include "Learning_MFE_MAE.mqh"  // For ENTRY_QUALITY enum

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
   ENTRY_QUALITY  quality;
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
                    quality(EQ_GOOD), confluenceScore(0), direction(0),
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
//| DATABASE MANAGER CLASS                                            |
//+------------------------------------------------------------------+
class CDatabaseManager
{
private:
   int            m_dbHandle;
   string         m_dbPath;
   bool           m_isOpen;

public:
   //+------------------------------------------------------------------+
   //| Get Trades from DB                                               |
   //+------------------------------------------------------------------+
   void GetTrades(TradeRecord &output[], string filter="")
   {
      if(!m_isOpen) return;

      string query = "SELECT * FROM Trades";
      if(filter != "") query += " WHERE " + filter;
      
      int request = DatabasePrepare(m_dbHandle, query);
      if(request == INVALID_HANDLE)
      {
         Print("❌ DB ERROR: Prepare failed for GetTrades. Error: ", GetLastError());
         return;
      }
      
      // Structure to bind results to
      struct TradeDBRow {
         ulong ticket;
         string symbol;
         long entry_time;
         int type;
         double lots;
         double entry_price;
         double sl;
         double tp;
         long close_time;
         double close_price;
         double profit;
         double commission;
         double swap;
         int magic;
         string strategy;
         double confluence_score;
         string regime;
         string killzone;
         string exit_reason;
         double mfe;
         double mae;
      } row;

      int count = 0;
      // First pass: Count or just resize dynamically? Dynamic is better.
      ArrayResize(output, 0);

      while(DatabaseReadBind(request, row))
      {
         count++;
         ArrayResize(output, count);
         int i = count - 1;
         
         // Map DB Row to TradeRecord
         output[i].entry.ticket = row.ticket;
         output[i].entry.symbol = row.symbol;
         output[i].entry.entryTime = (datetime)row.entry_time;
         output[i].entry.direction = (row.type == 0) ? 1 : -1; // 0=BUY, 1=SELL in DB; TradeRecord: 1=Buy, -1=Sell
         output[i].entry.lots = row.lots;
         output[i].entry.entryPrice = row.entry_price;
         output[i].entry.sl = row.sl;
         output[i].entry.tp = row.tp;
         output[i].entry.confluenceScore = row.confluence_score;
         output[i].entry.regime = StringToRegime(row.regime); // Need helper?
         output[i].entry.killzone = StringToKillzone(row.killzone); // Need helper?
         
         output[i].exit.exitTime = (datetime)row.close_time;
         output[i].exit.exitPrice = row.close_price;
         output[i].exit.profitMoney = row.profit + row.commission + row.swap;
         output[i].exit.exitType = row.exit_reason;
         output[i].exit.mfe = row.mfe;
         output[i].exit.mae = row.mae;
         
         // Calculate R if possible (approximate if initial risk unknown)
         double initialRisk = MathAbs(row.entry_price - row.sl);
         if(initialRisk > 0 && row.sl > 0)
             output[i].exit.profitR = (row.close_price - row.entry_price) * output[i].entry.direction / initialRisk;
         else
             output[i].exit.profitR = 0;

         output[i].isOpen = (row.close_time == 0);
      }
      
      DatabaseFinalize(request);
   }

   // Helpers for Enum Conversion (Simple versions)
   MARKET_REGIME StringToRegime(string s) {
      if(s == "TREND_STRONG" || s == "TREND") return REGIME_TREND_STRONG;
      if(s == "TREND_WEAK")                   return REGIME_TREND_WEAK;
      if(s == "RANGING"     || s == "RANGE")  return REGIME_RANGING;
      if(s == "VOLATILE")                     return REGIME_VOLATILE;
      if(s == "CRISIS")                       return REGIME_CRISIS;
      if(s == "CHOPPY")                       return REGIME_CHOPPY;
      if(s == "SQUEEZE")                      return REGIME_SQUEEZE;
      return REGIME_UNKNOWN;
   }
   
   ENUM_KILLZONE StringToKillzone(string s) {
      if(s == "Asian") return KILLZONE_ASIAN;
      if(s == "London Open") return KILLZONE_LONDON_OPEN;
      if(s == "NY") return KILLZONE_NY;
      if(s == "London Close") return KILLZONE_LONDON_CLOSE;
      return KILLZONE_NONE;
   }

   CDatabaseManager() : m_dbHandle(INVALID_HANDLE), m_isOpen(false)
   {
      m_dbPath = "PortfolioGovernor.sqlite";
   }

   ~CDatabaseManager()
   {
      Close();
   }

   //+------------------------------------------------------------------+
   //| Initialize & Open Database                                        |
   //+------------------------------------------------------------------+
   bool Init()
   {
      // Open or Create Database in MQL5/Files/PortfolioGovernor.sqlite
      // DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | DATABASE_OPEN_COMMON
      // Using FILE_COMMON to share between terminals if needed, or remove for local
      m_dbHandle = DatabaseOpen(m_dbPath, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | DATABASE_OPEN_COMMON);

      if(m_dbHandle == INVALID_HANDLE)
      {
         Print("❌ DB ERROR: Failed to open database '", m_dbPath, "'. Error: ", GetLastError());
         return false;
      }

      m_isOpen = true;
      Print("💾 DB: Connected to ", m_dbPath);

      // Create Tables if they don't exist
      if(!CreateSchema())
      {
         Close();
         return false;
      }

      // Import historical trades if database is empty
      ImportHistoricalTrades();

      return true;
   }

   //+------------------------------------------------------------------+
   //| Close Database                                                    |
   //+------------------------------------------------------------------+
   void Close()
   {
      if(m_isOpen && m_dbHandle != INVALID_HANDLE)
      {
         DatabaseClose(m_dbHandle);
         m_dbHandle = INVALID_HANDLE;
         m_isOpen = false;
         Print("💾 DB: Connection closed.");
      }
   }

   //+------------------------------------------------------------------+
   //| Execute Non-Query (INSERT, UPDATE, DELETE, CREATE)               |
   //+------------------------------------------------------------------+
   bool Execute(string sql)
   {
      if(!m_isOpen) return false;

      if(!DatabaseExecute(m_dbHandle, sql))
      {
         Print("❌ DB EXEC ERROR: ", sql, " | Error: ", GetLastError());
         return false;
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Log Trade Entry                                                   |
   //+------------------------------------------------------------------+
   bool LogTradeEntry(ulong ticket, string symbol, int type, double lots, 
                      double price, double sl, double tp, double score,
                      string strategy, string marketRegime, string killzone)
   {
      if(!m_isOpen) return false;

      string query = StringFormat(
         "INSERT OR IGNORE INTO Trades "
         "(ticket, symbol, entry_time, type, lots, entry_price, sl, tp, confluence_score, strategy, regime, killzone) "
         "VALUES (%I64u, '%s', %I64d, %d, %.2f, %.5f, %.5f, %.5f, %.2f, '%s', '%s', '%s');",
         ticket,
         symbol,
         (long)TimeCurrent(),
         type,
         lots,
         price,
         sl,
         tp,
         score,
         strategy,
         marketRegime,
         killzone
      );

      return Execute(query);
   }

   //+------------------------------------------------------------------+
   //| Log Trade Exit                                                    |
   //+------------------------------------------------------------------+
   bool LogTradeExit(ulong ticket, double price, double profit, double comm, double swap, string reason, double mfe, double mae)
   {
      if(!m_isOpen) return false;

      string query = StringFormat(
         "UPDATE Trades SET "
         "close_time = %I64d, "
         "close_price = %.5f, "
         "profit = %.2f, "
         "commission = %.2f, "
         "swap = %.2f, "
         "exit_reason = '%s', "
         "mfe = %.5f, "
         "mae = %.5f "
         "WHERE ticket = %I64u;",
         (long)TimeCurrent(),
         price,
         profit,
         comm,
         swap,
         reason,
         mfe,
         mae,
         ticket
      );

      return Execute(query);
   }

   //+------------------------------------------------------------------+
   //| Log Valid Signal (Shadow Mode / Analysis)                         |
   //+------------------------------------------------------------------+
   bool LogSignal(string symbol, int direction, double score, int rank, bool allowed, 
                  string rejectionReason, double smc, double fib)
   {
      if(!m_isOpen) return false;

      string query = StringFormat(
         "INSERT INTO Signals "
         "(time, symbol, direction, score, rank, allowed, rejection_reason, smc_score, fib_score) "
         "VALUES (%I64d, '%s', %d, %.2f, %d, %d, '%s', %.2f, %.2f);",
         (long)TimeCurrent(),
         symbol,
         direction,
         score,
         rank,
         (allowed ? 1 : 0),
         rejectionReason,
         smc,
         fib
      );

      return Execute(query);
   }

   //+------------------------------------------------------------------+
   //| Update State Variable (Persistence)                              |
   //+------------------------------------------------------------------+
   bool SetState(string key, double valNum, string valStr="")
   {
      if(!m_isOpen) return false;

      string query = StringFormat(
         "INSERT INTO GovernorState (key, value_num, value_str, updated_at) "
         "VALUES ('%s', %.5f, '%s', %I64d) "
         "ON CONFLICT(key) DO UPDATE SET "
         "value_num=excluded.value_num, "
         "value_str=excluded.value_str, "
         "updated_at=excluded.updated_at;",
         key, valNum, valStr, (long)TimeCurrent()
      );

      return Execute(query);
   }

   //+------------------------------------------------------------------+
   //| Get State Variable (Numeric)                                      |
   //+------------------------------------------------------------------+
   double GetStateNum(string key, double defaultVal=0.0)
   {
       if(!m_isOpen) return defaultVal;

       string query = StringFormat("SELECT value_num FROM GovernorState WHERE key='%s';", key);
       int request = DatabasePrepare(m_dbHandle, query);

       if(request == INVALID_HANDLE) return defaultVal;

       double result = defaultVal;
       if(DatabaseRead(request))
       {
           DatabaseColumnDouble(request, 0, result);
       }
       DatabaseFinalize(request);
       return result;
   }

   //+------------------------------------------------------------------+
   //| Import Historical Trades from Account History                    |
   //+------------------------------------------------------------------+
   bool ImportHistoricalTrades()
   {
      if(!m_isOpen) return false;

      // Check if we already have trades in the database
      string checkQuery = "SELECT COUNT(*) as count FROM Trades;";
      int request = DatabasePrepare(m_dbHandle, checkQuery);

      if(request == INVALID_HANDLE)
      {
         Print("❌ DB ERROR: Cannot check trade count");
         return false;
      }

      long existingTradesLong = 0;
      if(DatabaseRead(request))
      {
         DatabaseColumnLong(request, 0, existingTradesLong);
      }
      DatabaseFinalize(request);

      int existingTrades = (int)existingTradesLong;

      // If we already have trades, skip import
      if(existingTrades > 0)
      {
         Print("💾 DB: ", existingTrades, " trades already in database, skipping import");
         return true;
      }

      // Import all historical deals
      Print("💾 DB: Database is empty, importing historical trades...");

      datetime startDate = 0; // Import all history
      datetime endDate = TimeCurrent();

      HistorySelect(startDate, endDate);

      int totalDeals = HistoryDealsTotal();
      int importedTrades = 0;

      Print("💾 DB: Found ", totalDeals, " deals in history");

      // Process deals and group by position ticket
      for(int i = 0; i < totalDeals; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0) continue;

         // Only process DEAL_ENTRY_OUT (closed trades)
         long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(dealEntry != DEAL_ENTRY_OUT) continue;

         // Get deal details
         ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
         long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
         double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
         double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
         datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

         // Try to find the corresponding entry deal for this position
         double entryPrice = 0;
         datetime entryTime = 0;
         int tradeType = (dealType == DEAL_TYPE_BUY) ? 1 : 0; // Reverse: exit BUY means it was a SELL

         // Search for entry deal
         for(int j = 0; j < totalDeals; j++)
         {
            ulong entryDealTicket = HistoryDealGetTicket(j);
            if(entryDealTicket == 0) continue;

            ulong entryPosId = HistoryDealGetInteger(entryDealTicket, DEAL_POSITION_ID);
            long entryDealEntry = HistoryDealGetInteger(entryDealTicket, DEAL_ENTRY);

            if(entryPosId == positionId && entryDealEntry == DEAL_ENTRY_IN)
            {
               entryPrice = HistoryDealGetDouble(entryDealTicket, DEAL_PRICE);
               entryTime = (datetime)HistoryDealGetInteger(entryDealTicket, DEAL_TIME);
               long entryDealType = HistoryDealGetInteger(entryDealTicket, DEAL_TYPE);
               tradeType = (entryDealType == DEAL_TYPE_BUY) ? 0 : 1; // 0=BUY, 1=SELL
               break;
            }
         }

         // If we found entry, insert the complete trade
         if(entryPrice > 0)
         {
            string insertQuery = StringFormat(
               "INSERT OR IGNORE INTO Trades "
               "(ticket, symbol, entry_time, type, lots, entry_price, sl, tp, "
               "close_time, close_price, profit, commission, swap, "
               "strategy, confluence_score, regime, killzone, exit_reason) "
               "VALUES (%I64u, '%s', %I64d, %d, %.2f, %.5f, 0, 0, "
               "%I64d, %.5f, %.2f, %.2f, %.2f, "
               "'HISTORICAL', 0, 'UNKNOWN', 'UNKNOWN', 'HISTORICAL_IMPORT');",
               positionId,
               symbol,
               (long)entryTime,
               tradeType,
               volume,
               entryPrice,
               (long)dealTime,
               dealPrice,
               profit,
               commission,
               swap
            );

            if(Execute(insertQuery))
            {
               importedTrades++;
            }
         }
      }

      Print("💾 DB: Successfully imported ", importedTrades, " historical trades");
      SetState("history_imported", 1.0, "true");

      return true;
   }

   //+------------------------------------------------------------------+
   //| Aliases for state persistence (Module 1)                         |
   //+------------------------------------------------------------------+
   bool   SaveRuntimeState(string key, double val, string sval = "") { return SetState(key, val, sval); }
   double LoadRuntimeState(string key, double def = 0.0)             { return GetStateNum(key, def); }

   //+------------------------------------------------------------------+
   //| Log Gate Block (Module 2)                                        |
   //+------------------------------------------------------------------+
   bool LogGateBlock(string symbol, int direction, string regime,
                     string gateFailed, int gatesPassed, int gatesRequired)
   {
      if(!m_isOpen) return false;
      string query = StringFormat(
         "INSERT INTO GateLog (time, symbol, direction, regime, gate_failed, gates_passed, gates_required) "
         "VALUES (%I64d, '%s', %d, '%s', '%s', %d, %d);",
         (long)TimeCurrent(), symbol, direction, regime, gateFailed, gatesPassed, gatesRequired);
      return Execute(query);
   }

   //+------------------------------------------------------------------+
   //| Query score→WR stats per regime (Module 3)                       |
   //| Returns true if at least minTrades found; fills outMinScore      |
   //+------------------------------------------------------------------+
   bool GetScoreStats(string regime, int minTrades, double &outMinScore, double &outWinRate)
   {
      if(!m_isOpen) return false;
      outMinScore = 0; outWinRate = 0;

      // Find the score bucket (floor to nearest 2) where WR >= 55%
      // Bucketed by CAST(confluence_score/2)*2 — groups scores [0-2), [2-4), etc.
      string q = StringFormat(
         "SELECT CAST(confluence_score/2)*2 AS bucket, "
         "COUNT(*) AS cnt, "
         "SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END)*1.0/COUNT(*) AS wr "
         "FROM Trades "
         "WHERE regime='%s' AND close_time > 0 "
         "GROUP BY bucket HAVING cnt >= %d AND wr >= 0.55 "
         "ORDER BY wr DESC LIMIT 1;",
         regime, minTrades);

      int req = DatabasePrepare(m_dbHandle, q);
      if(req == INVALID_HANDLE) return false;

      bool found = false;
      if(DatabaseRead(req))
      {
         double bucket = 0, wr = 0;
         DatabaseColumnDouble(req, 0, bucket);
         DatabaseColumnDouble(req, 2, wr);
         outMinScore = bucket;
         outWinRate  = wr;
         found = true;
      }
      DatabaseFinalize(req);
      return found;
   }

   //+------------------------------------------------------------------+
   //| Query avg MFE_R per regime (Module 4)                            |
   //+------------------------------------------------------------------+
   bool GetMFEStats(string regime, double &outAvgMFE_R)
   {
      if(!m_isOpen) return false;
      outAvgMFE_R = 0;

      // mfe is stored as price distance; we approximate R = mfe / (entry_price - sl)
      string q = StringFormat(
         "SELECT AVG(CASE WHEN (entry_price - sl) != 0 "
         "THEN mfe / ABS(entry_price - sl) ELSE 0 END) AS avg_mfe_r "
         "FROM Trades "
         "WHERE regime='%s' AND close_time > 0 AND mfe > 0 AND sl != 0;",
         regime);

      int req = DatabasePrepare(m_dbHandle, q);
      if(req == INVALID_HANDLE) return false;

      bool found = false;
      if(DatabaseRead(req))
      {
         DatabaseColumnDouble(req, 0, outAvgMFE_R);
         found = (outAvgMFE_R > 0);
      }
      DatabaseFinalize(req);
      return found;
   }

   //+------------------------------------------------------------------+
   //| Log Daily Session Snapshot (Module 5)                            |
   //+------------------------------------------------------------------+
   bool LogDailySnapshot(int dayOfWeek, string killzone, string regime,
                         int trades, int wins, double totalR, double equityEnd)
   {
      if(!m_isOpen) return false;
      string q = StringFormat(
         "INSERT INTO DailySnapshot "
         "(date, day_of_week, killzone, regime, trades, wins, total_r, equity_end) "
         "VALUES (%I64d, %d, '%s', '%s', %d, %d, %.4f, %.2f);",
         (long)TimeCurrent(), dayOfWeek, killzone, regime, trades, wins, totalR, equityEnd);
      return Execute(q);
   }

   //+------------------------------------------------------------------+
   //| Update regime_at_exit + gates_passed on trade close              |
   //+------------------------------------------------------------------+
   bool UpdateTradeExit(ulong ticket, string regimeAtExit, int gatesPassed, double equityAtEntry = 0)
   {
      if(!m_isOpen) return false;
      string q = StringFormat(
         "UPDATE Trades SET regime_at_exit='%s', gates_passed=%d, equity_at_entry=%.2f "
         "WHERE ticket=%I64u;",
         regimeAtExit, gatesPassed, equityAtEntry, ticket);
      return Execute(q);
   }

   //+------------------------------------------------------------------+
   //| Query avg MAE_R per regime — for SL calibration                  |
   //+------------------------------------------------------------------+
   bool GetMAEStats(string regime, double &outAvgMAE_R)
   {
      if(!m_isOpen) return false;
      outAvgMAE_R = 0;
      string q = StringFormat(
         "SELECT AVG(CASE WHEN ABS(entry_price - sl) > 0 "
         "THEN mae / ABS(entry_price - sl) ELSE 0 END) "
         "FROM Trades "
         "WHERE regime='%s' AND close_time > 0 AND mae > 0 AND sl != 0;",
         regime);
      int req = DatabasePrepare(m_dbHandle, q);
      if(req == INVALID_HANDLE) return false;
      bool found = false;
      if(DatabaseRead(req)) { DatabaseColumnDouble(req, 0, outAvgMAE_R); found = (outAvgMAE_R > 0); }
      DatabaseFinalize(req);
      return found;
   }

   //+------------------------------------------------------------------+
   //| Query WR per (regime, killzone) — for session threshold filter   |
   //+------------------------------------------------------------------+
   bool GetKillzoneWR(string regime, string killzone, int minTrades,
                      double &outWR, int &outCount)
   {
      if(!m_isOpen) return false;
      outWR = 0; outCount = 0;
      string q = StringFormat(
         "SELECT COUNT(*) AS cnt, "
         "SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END)*1.0/COUNT(*) AS wr "
         "FROM Trades "
         "WHERE regime='%s' AND killzone='%s' AND close_time > 0;",
         regime, killzone);
      int req = DatabasePrepare(m_dbHandle, q);
      if(req == INVALID_HANDLE) return false;
      bool found = false;
      if(DatabaseRead(req))
      {
         long cnt = 0;
         DatabaseColumnLong(req, 0, cnt);
         outCount = (int)cnt;
         if(outCount >= minTrades) { DatabaseColumnDouble(req, 1, outWR); found = true; }
      }
      DatabaseFinalize(req);
      return found;
   }

   //+------------------------------------------------------------------+
   //| Query top blocking gate per regime from GateLog                  |
   //+------------------------------------------------------------------+
   bool GetTopGateBlock(string regime, string &outGateName, double &outBlockPct)
   {
      if(!m_isOpen) return false;
      outGateName = ""; outBlockPct = 0;

      // Total blocks for this regime
      string qTotal = StringFormat(
         "SELECT COUNT(*) FROM GateLog WHERE regime='%s';", regime);
      int rTotal = DatabasePrepare(m_dbHandle, qTotal);
      if(rTotal == INVALID_HANDLE) return false;
      long total = 0;
      if(DatabaseRead(rTotal)) DatabaseColumnLong(rTotal, 0, total);
      DatabaseFinalize(rTotal);
      if(total == 0) return false;

      // Top gate
      string qTop = StringFormat(
         "SELECT gate_failed, COUNT(*) AS cnt FROM GateLog "
         "WHERE regime='%s' GROUP BY gate_failed ORDER BY cnt DESC LIMIT 1;", regime);
      int rTop = DatabasePrepare(m_dbHandle, qTop);
      if(rTop == INVALID_HANDLE) return false;
      bool found = false;
      if(DatabaseRead(rTop))
      {
         long topCnt = 0;
         DatabaseColumnText(rTop, 0, outGateName);
         DatabaseColumnLong(rTop, 1, topCnt);
         outBlockPct = (total > 0) ? (double)topCnt / (double)total * 100.0 : 0;
         found = true;
      }
      DatabaseFinalize(rTop);
      return found;
   }

   //+------------------------------------------------------------------+
   //| Query avg profit R by exit type per regime                       |
   //+------------------------------------------------------------------+
   bool GetExitTypeAvgR(string regime, string exitType, double &outAvgR)
   {
      if(!m_isOpen) return false;
      outAvgR = 0;
      string q = StringFormat(
         "SELECT AVG(CASE WHEN ABS(entry_price - sl) > 0 "
         "THEN (close_price - entry_price) * (1 - 2*type) / ABS(entry_price - sl) "
         "ELSE 0 END) "
         "FROM Trades "
         "WHERE regime='%s' AND exit_reason='%s' AND close_time > 0 AND sl != 0;",
         regime, exitType);
      int req = DatabasePrepare(m_dbHandle, q);
      if(req == INVALID_HANDLE) return false;
      bool found = false;
      if(DatabaseRead(req)) { DatabaseColumnDouble(req, 0, outAvgR); found = true; }
      DatabaseFinalize(req);
      return found;
   }

   //+------------------------------------------------------------------+
   //| Count distinct active trading days in DailySnapshot              |
   //| (days with at least 1 trade in the last lookbackDays days).     |
   //| Used for FundingPips payout eligibility: need ≥7 in 30 days.   |
   //+------------------------------------------------------------------+
   int GetActiveTradingDays(int lookbackDays = 30)
   {
      if(!m_isOpen) return 0;
      datetime fromTime = TimeCurrent() - (datetime)(lookbackDays * 86400);
      // Group by day number (date/86400) to get distinct calendar days
      string q = StringFormat(
         "SELECT COUNT(DISTINCT date/86400) FROM DailySnapshot "
         "WHERE date >= %I64d AND trades > 0;",
         (long)fromTime);
      int req = DatabasePrepare(m_dbHandle, q);
      if(req == INVALID_HANDLE) return 0;
      long cnt = 0;
      if(DatabaseRead(req)) DatabaseColumnLong(req, 0, cnt);
      DatabaseFinalize(req);
      return (int)cnt;
   }

private:
   //+------------------------------------------------------------------+
   //| Create Schema                                                     |
   //+------------------------------------------------------------------+
   bool CreateSchema()
   {
      // 1. Trades Table
      string sqlTrades = 
         "CREATE TABLE IF NOT EXISTS Trades ("
         "ticket INTEGER PRIMARY KEY,"
         "symbol TEXT,"
         "entry_time INTEGER,"
         "type INTEGER,"
         "lots REAL,"
         "entry_price REAL,"
         "sl REAL,"
         "tp REAL,"
         "close_time INTEGER,"
         "close_price REAL,"
         "profit REAL,"
         "commission REAL,"
         "swap REAL,"
         "magic INTEGER,"
         "strategy TEXT,"
         "confluence_score REAL,"
         "regime TEXT,"
         "killzone TEXT,"
         "exit_reason TEXT,"
         "mfe REAL,"
         "mae REAL"
         ");";

      if(!Execute(sqlTrades)) return false;

      // 2. Signals Table
      string sqlSignals = 
         "CREATE TABLE IF NOT EXISTS Signals ("
         "id INTEGER PRIMARY KEY AUTOINCREMENT,"
         "time INTEGER,"
         "symbol TEXT,"
         "direction INTEGER,"
         "score REAL,"
         "rank INTEGER,"
         "allowed INTEGER,"
         "smc_score REAL,"
         "fib_score REAL,"
         "rejection_reason TEXT"
         ");";

      if(!Execute(sqlSignals)) return false;

      // 3. State Table
      string sqlState = 
         "CREATE TABLE IF NOT EXISTS GovernorState ("
         "key TEXT PRIMARY KEY,"
         "value_num REAL,"
         "value_str TEXT,"
         "updated_at INTEGER"
         ");";

      if(!Execute(sqlState)) return false;

      // 4. GateLog Table — tracks which gates block entries per regime
      string sqlGateLog =
         "CREATE TABLE IF NOT EXISTS GateLog ("
         "id INTEGER PRIMARY KEY AUTOINCREMENT,"
         "time INTEGER,"
         "symbol TEXT,"
         "direction INTEGER,"
         "regime TEXT,"
         "gate_failed TEXT,"
         "gates_passed INTEGER,"
         "gates_required INTEGER"
         ");";
      if(!Execute(sqlGateLog)) return false;

      // 5. DailySnapshot Table — session performance heatmap
      string sqlSnapshot =
         "CREATE TABLE IF NOT EXISTS DailySnapshot ("
         "id INTEGER PRIMARY KEY AUTOINCREMENT,"
         "date INTEGER,"
         "day_of_week INTEGER,"
         "killzone TEXT,"
         "regime TEXT,"
         "trades INTEGER,"
         "wins INTEGER,"
         "total_r REAL,"
         "equity_end REAL"
         ");";
      if(!Execute(sqlSnapshot)) return false;

      // Schema migrations — add new columns to Trades if not present (ignore error if they exist)
      Execute("ALTER TABLE Trades ADD COLUMN regime_at_exit TEXT DEFAULT 'UNKNOWN';");
      Execute("ALTER TABLE Trades ADD COLUMN gates_passed INTEGER DEFAULT 0;");
      Execute("ALTER TABLE Trades ADD COLUMN equity_at_entry REAL DEFAULT 0;");

      return true;
   }
};

#endif
