//+------------------------------------------------------------------+
//|                                              DatabaseManager.mqh |
//|          SQLite Database Manager for Portfolio Governor          |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef DATABASE_MANAGER_MQH
#define DATABASE_MANAGER_MQH

#property copyright "Guido Ambiorix"
#property strict

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
                      string strategy, string regime, string killzone)
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
         regime,
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

      return true;
   }
};

#endif
