//+------------------------------------------------------------------+
//|                                              DatabaseManager.mqh |
//|          SQLite Database Manager for Portfolio Governor          |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef DATABASE_MANAGER_MQH
#define DATABASE_MANAGER_MQH

#property copyright "Guido Ambiorix"
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
// ... (Init, Close, Execute methods remain same)

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
         output[i].entry.direction = (row.type == 0) ? 1 : -1; // 0=BUY in DB logic from Import? Wait, Import said dealType. 
                                                               // Importer: tradeType = (entryDealType == DEAL_TYPE_BUY) ? 0 : 1; 
                                                               // So 0=BUY, 1=SELL. 
                                                               // TradeRecord: 1=Buy, -1=Sell.
         output[i].entry.direction = (row.type == 0) ? 1 : -1; 
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
      if(s == "TREND") return REGIME_TREND;
      if(s == "RANGE") return REGIME_RANGE;
      if(s == "VOLATILE") return REGIME_VOLATILE;
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
   //| Save Symbol Configuration to DB                                   |
   //+------------------------------------------------------------------+
   bool SaveSymbolConfig(SymbolConfig &cfg)
   {
      if(!m_isOpen) return false;

      // Construct Big Query using concatenation (MQL5 StringFormat limit workaround)
      string sql = "INSERT OR REPLACE INTO SymbolConfigs VALUES (" +
         "'" + cfg.symbol + "', " +
         IntegerToString(cfg.magicNumber) + ", " +
         IntegerToString(cfg.enableMobileAlerts) + ", " +
         // Direction
         IntegerToString(cfg.direction) + ", " +
         IntegerToString(cfg.brokerUTCOffset) + ", " +
         // Fib
         IntegerToString(cfg.swingLookback) + ", " +
         DoubleToString(cfg.fibLevelLow, 3) + ", " +
         DoubleToString(cfg.fibLevelHigh, 3) + ", " +
         DoubleToString(cfg.zoneTolerance, 2) + ", " +
         // Displacement
         IntegerToString(cfg.useDisplacement) + ", " +
         DoubleToString(cfg.displacementATR, 2) + ", " +
         IntegerToString(cfg.displacementLookback) + ", " +
         // RSI
         IntegerToString(cfg.rsiPeriod) + ", " +
         IntegerToString(cfg.rsiOversold) + ", " +
         IntegerToString(cfg.rsiOverbought) + ", " +
         IntegerToString(cfg.rsiMomentum) + ", " +
         // Trend
         IntegerToString(cfg.emaPeriod) + ", " +
         IntegerToString(cfg.useTrendFilter) + ", " +
         DoubleToString(cfg.emaMinSlope, 5) + ", " +
         // Chop
         IntegerToString(cfg.useChopFilter) + ", " +
         DoubleToString(cfg.chopThreshold, 2) + ", " +
         IntegerToString(cfg.atrMaPeriod) + ", " +
         // Confluence
         IntegerToString(cfg.minConfluenceEntry) + ", " +
         IntegerToString(cfg.enableAddOns) + ", " +
         DoubleToString(cfg.addOn1_R, 2) + ", " +
         DoubleToString(cfg.addOn2_R, 2) + ", " +
         IntegerToString(cfg.maxPositions) + ", " +
         // Risk
         DoubleToString(cfg.riskBase, 2) + ", " +
         DoubleToString(cfg.riskAddOn1, 2) + ", " +
         DoubleToString(cfg.riskAddOn2, 2) + ", " +
         DoubleToString(cfg.maxRisk, 2) + ", " +
         DoubleToString(cfg.maxLotsPerTrade, 2) + ", " +
         IntegerToString(cfg.enableMarginCheck) + ", " +
         // TP
         IntegerToString(cfg.tpMode) + ", " +
         DoubleToString(cfg.fixedTP_R, 2) + ", " +
         DoubleToString(cfg.minTP_R, 2) + ", " +
         DoubleToString(cfg.maxTP_R, 2) + ", " +
         IntegerToString(cfg.tpUseLearnedMFE) + ", " +
         // Exit
         IntegerToString(cfg.trailingMode) + ", " +
         DoubleToString(cfg.partialTP_R, 2) + ", " +
         DoubleToString(cfg.partialClosePercent, 1) + ", " +
         DoubleToString(cfg.beThreshold_R, 2) + ", " +
         DoubleToString(cfg.trailStart_R, 2) + ", " +
         DoubleToString(cfg.trailATR_Mult, 2) + ", " +
         // Spread
         IntegerToString(cfg.maxSpreadPoints) + ", " +
         // SMC
         IntegerToString(cfg.useSMC) + ", " +
         IntegerToString(cfg.smcSwingLookback) + ", " +
         DoubleToString(cfg.smcMinImpulseATR, 2) + ", " +
         DoubleToString(cfg.smcMinFVG_ATR, 2) + ", " +
         // MTF
         IntegerToString(cfg.useMTF) + ", " +
         IntegerToString(cfg.htf) + ", " +
         IntegerToString(cfg.mtf) + ", " +
         IntegerToString(cfg.mtfEmaPeriod) + ", " +
         // News
         IntegerToString(cfg.useNewsFilter) + ", " +
         IntegerToString(cfg.newsMinutesBefore) + ", " +
         IntegerToString(cfg.newsMinutesAfter) + ", " +
         // Volatility
         IntegerToString(cfg.enableVolatilityFilter) + ", " +
         DoubleToString(cfg.volatilityThreshold, 2) + ", " +
         IntegerToString(cfg.volatilitySpikeCooldown) + ", " +
         // Kelly
         IntegerToString(cfg.useKelly) + ", " +
         DoubleToString(cfg.kellyFraction, 2) + ", " +
         DoubleToString(cfg.dailyMaxDD, 2) + ", " +
         DoubleToString(cfg.weeklyMaxDD, 2) + ", " +
         // Learning
         IntegerToString(cfg.enableLearning) + ", " +
         IntegerToString(cfg.logTradesToFile) + ", " +
         IntegerToString(cfg.learningHistory) + ", " +
         IntegerToString(cfg.minTradesForLearning) + ", " +
         // Adaptive
         IntegerToString(cfg.enableAdaptiveRisk) + ", " +
         IntegerToString(cfg.enableAdaptiveExits) + ", " +
         IntegerToString(cfg.enableAdaptiveFilters) + ", " +
         // Portfolio Protection
         IntegerToString(cfg.useCorrelationFilter) + ", " +
         DoubleToString(cfg.dailyMaxLoss_R, 2) + ", " +
         IntegerToString(cfg.lossCooldownMinutes) + ", " +
         IntegerToString(cfg.maxConsecutiveLosses) + ", " +
         IntegerToString(cfg.useReversalFilter) + ", " +
         IntegerToString(cfg.reversalCooldownMinutes) + ", " +
         // Killzones
         IntegerToString(cfg.useKillzoneFilter) + ", " +
         IntegerToString(cfg.enableAsianKZ) + ", " +
         IntegerToString(cfg.enableLondonOpenKZ) + ", " +
         IntegerToString(cfg.enableNYKZ) + ", " +
         IntegerToString(cfg.enableLondonCloseKZ) + ", " +
         // Session
         IntegerToString(cfg.useSessionGovernor) + ", " +
         IntegerToString(cfg.maxTradesPerSession) + ", " +
         IntegerToString(cfg.tradeCooldownMinutes) +
         ");";
      
      return Execute(sql);
   }

   //+------------------------------------------------------------------+
   //| Load All Symbol Configs                                           |
   //+------------------------------------------------------------------+
   int LoadSymbolConfigs(SymbolConfig &output[])
   {
      if(!m_isOpen) return 0;
      
      string query = "SELECT * FROM SymbolConfigs";
      int request = DatabasePrepare(m_dbHandle, query);
      if(request == INVALID_HANDLE) return 0;
      
      int count = 0;
      ArrayResize(output, 0);
      
      while(DatabaseRead(request))
      {
         count++;
         ArrayResize(output, count);
         int i = count - 1;
         
         // Binding columns (0-based)
         DatabaseColumnText(request, 0, output[i].symbol);
         DatabaseColumnLong(request, 1, output[i].magicNumber);
         double longVal; DatabaseColumnDouble(request, 2, longVal); output[i].enableMobileAlerts = (bool)longVal;
         
         long intVal;
         DatabaseColumnLong(request, 3, intVal); output[i].direction = (int)intVal;
         DatabaseColumnLong(request, 4, intVal); output[i].brokerUTCOffset = (int)intVal;
         
         DatabaseColumnLong(request, 5, intVal); output[i].swingLookback = (int)intVal;
         DatabaseColumnDouble(request, 6, output[i].fibLevelLow);
         DatabaseColumnDouble(request, 7, output[i].fibLevelHigh);
         DatabaseColumnDouble(request, 8, output[i].zoneTolerance);
         
         DatabaseColumnDouble(request, 9, longVal); output[i].useDisplacement = (bool)longVal;
         DatabaseColumnDouble(request, 10, output[i].displacementATR);
         DatabaseColumnLong(request, 11, intVal); output[i].displacementLookback = (int)intVal;
         
         DatabaseColumnLong(request, 12, intVal); output[i].rsiPeriod = (int)intVal;
         DatabaseColumnLong(request, 13, intVal); output[i].rsiOversold = (int)intVal;
         DatabaseColumnLong(request, 14, intVal); output[i].rsiOverbought = (int)intVal;
         DatabaseColumnDouble(request, 15, longVal); output[i].rsiMomentum = (bool)longVal;
         
         DatabaseColumnLong(request, 16, intVal); output[i].emaPeriod = (int)intVal;
         DatabaseColumnDouble(request, 17, longVal); output[i].useTrendFilter = (bool)longVal;
         DatabaseColumnDouble(request, 18, output[i].emaMinSlope); // Double
         
         DatabaseColumnDouble(request, 19, longVal); output[i].useChopFilter = (bool)longVal;
         DatabaseColumnDouble(request, 20, output[i].chopThreshold);
         DatabaseColumnLong(request, 21, intVal); output[i].atrMaPeriod = (int)intVal;
         
         DatabaseColumnLong(request, 22, intVal); output[i].minConfluenceEntry = (int)intVal;
         DatabaseColumnDouble(request, 23, longVal); output[i].enableAddOns = (bool)longVal;
         DatabaseColumnDouble(request, 24, output[i].addOn1_R);
         DatabaseColumnDouble(request, 25, output[i].addOn2_R);
         DatabaseColumnLong(request, 26, intVal); output[i].maxPositions = (int)intVal;
         
         DatabaseColumnDouble(request, 27, output[i].riskBase);
         DatabaseColumnDouble(request, 28, output[i].riskAddOn1);
         DatabaseColumnDouble(request, 29, output[i].riskAddOn2);
         DatabaseColumnDouble(request, 30, output[i].maxRisk);
         DatabaseColumnDouble(request, 31, output[i].maxLotsPerTrade);
         DatabaseColumnDouble(request, 32, longVal); output[i].enableMarginCheck = (bool)longVal;
         
         DatabaseColumnLong(request, 33, intVal); output[i].tpMode = (int)intVal;
         DatabaseColumnDouble(request, 34, output[i].fixedTP_R);
         DatabaseColumnDouble(request, 35, output[i].minTP_R);
         DatabaseColumnDouble(request, 36, output[i].maxTP_R);
         DatabaseColumnDouble(request, 37, longVal); output[i].tpUseLearnedMFE = (bool)longVal;
         
         DatabaseColumnLong(request, 38, intVal); output[i].trailingMode = (int)intVal;
         DatabaseColumnDouble(request, 39, output[i].partialTP_R);
         DatabaseColumnDouble(request, 40, output[i].partialClosePercent);
         DatabaseColumnDouble(request, 41, output[i].beThreshold_R);
         DatabaseColumnDouble(request, 42, output[i].trailStart_R);
         DatabaseColumnDouble(request, 43, output[i].trailATR_Mult);
         
         DatabaseColumnLong(request, 44, intVal); output[i].maxSpreadPoints = (int)intVal;
         
         DatabaseColumnDouble(request, 45, longVal); output[i].useSMC = (bool)longVal;
         DatabaseColumnLong(request, 46, intVal); output[i].smcSwingLookback = (int)intVal;
         DatabaseColumnDouble(request, 47, output[i].smcMinImpulseATR);
         DatabaseColumnDouble(request, 48, output[i].smcMinFVG_ATR);
         
         DatabaseColumnDouble(request, 49, longVal); output[i].useMTF = (bool)longVal;
         DatabaseColumnLong(request, 50, intVal); output[i].htf = (ENUM_TIMEFRAMES)intVal;
         DatabaseColumnLong(request, 51, intVal); output[i].mtf = (ENUM_TIMEFRAMES)intVal;
         DatabaseColumnLong(request, 52, intVal); output[i].mtfEmaPeriod = (int)intVal;
         
         DatabaseColumnDouble(request, 53, longVal); output[i].useNewsFilter = (bool)longVal;
         DatabaseColumnLong(request, 54, intVal); output[i].newsMinutesBefore = (int)intVal;
         DatabaseColumnLong(request, 55, intVal); output[i].newsMinutesAfter = (int)intVal;
         
         DatabaseColumnDouble(request, 56, longVal); output[i].enableVolatilityFilter = (bool)longVal;
         DatabaseColumnDouble(request, 57, output[i].volatilityThreshold);
         DatabaseColumnLong(request, 58, intVal); output[i].volatilitySpikeCooldown = (int)intVal;
         
         DatabaseColumnDouble(request, 59, longVal); output[i].useKelly = (bool)longVal;
         DatabaseColumnDouble(request, 60, output[i].kellyFraction);
         DatabaseColumnDouble(request, 61, output[i].dailyMaxDD);
         DatabaseColumnDouble(request, 62, output[i].weeklyMaxDD);
         
         DatabaseColumnDouble(request, 63, longVal); output[i].enableLearning = (bool)longVal;
         DatabaseColumnDouble(request, 64, longVal); output[i].logTradesToFile = (bool)longVal;
         DatabaseColumnLong(request, 65, intVal); output[i].learningHistory = (int)intVal;
         DatabaseColumnLong(request, 66, intVal); output[i].minTradesForLearning = (int)intVal;
         
         DatabaseColumnDouble(request, 67, longVal); output[i].enableAdaptiveRisk = (bool)longVal;
         DatabaseColumnDouble(request, 68, longVal); output[i].enableAdaptiveExits = (bool)longVal;
         DatabaseColumnDouble(request, 69, longVal); output[i].enableAdaptiveFilters = (bool)longVal;
         
         DatabaseColumnDouble(request, 70, longVal); output[i].useCorrelationFilter = (bool)longVal;
         DatabaseColumnDouble(request, 71, output[i].dailyMaxLoss_R);
         DatabaseColumnLong(request, 72, intVal); output[i].lossCooldownMinutes = (int)intVal;
         DatabaseColumnLong(request, 73, intVal); output[i].maxConsecutiveLosses = (int)intVal;
         DatabaseColumnDouble(request, 74, longVal); output[i].useReversalFilter = (bool)longVal;
         DatabaseColumnLong(request, 75, intVal); output[i].reversalCooldownMinutes = (int)intVal;
         
         DatabaseColumnDouble(request, 76, longVal); output[i].useKillzoneFilter = (bool)longVal;
         DatabaseColumnDouble(request, 77, longVal); output[i].enableAsianKZ = (bool)longVal;
         DatabaseColumnDouble(request, 78, longVal); output[i].enableLondonOpenKZ = (bool)longVal;
         DatabaseColumnDouble(request, 79, longVal); output[i].enableNYKZ = (bool)longVal;
         DatabaseColumnDouble(request, 80, longVal); output[i].enableLondonCloseKZ = (bool)longVal;
         
         DatabaseColumnDouble(request, 81, longVal); output[i].useSessionGovernor = (bool)longVal;
         DatabaseColumnLong(request, 82, intVal); output[i].maxTradesPerSession = (int)intVal;
         DatabaseColumnLong(request, 83, intVal); output[i].tradeCooldownMinutes = (int)intVal;
      }
      
      DatabaseFinalize(request);
      Print("💾 DB: Loaded ", count, " symbol configurations.");
      return count;
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

      // 4. Symbol Configs Table (Comprehensive)
      string sqlConfig = 
         "CREATE TABLE IF NOT EXISTS SymbolConfigs ("
         "symbol TEXT PRIMARY KEY,"
         "magic_number INTEGER,"
         "enable_mobile_alerts INTEGER,"
         // Direction
         "direction INTEGER,"
         "broker_utc_offset INTEGER,"
         // Fibonacci
         "swing_lookback INTEGER,"
         "fib_level_low REAL,"
         "fib_level_high REAL,"
         "zone_tolerance REAL,"
         // Displacement
         "use_displacement INTEGER,"
         "displacement_atr REAL,"
         "displacement_lookback INTEGER,"
         // RSI
         "rsi_period INTEGER,"
         "rsi_oversold INTEGER,"
         "rsi_overbought INTEGER,"
         "rsi_momentum INTEGER,"
         // Trend
         "ema_period INTEGER,"
         "use_trend_filter INTEGER,"
         "ema_min_slope REAL,"
         // Chop
         "use_chop_filter INTEGER,"
         "chop_threshold REAL,"
         "atr_ma_period INTEGER,"
         // Confluence
         "min_confluence_entry INTEGER,"
         "enable_addons INTEGER,"
         "addon1_r REAL,"
         "addon2_r REAL,"
         "max_positions INTEGER,"
         // Risk
         "risk_base REAL,"
         "risk_addon1 REAL,"
         "risk_addon2 REAL,"
         "max_risk REAL,"
         "max_lots_per_trade REAL,"
         "enable_margin_check INTEGER,"
         // TP
         "tp_mode INTEGER,"
         "fixed_tp_r REAL,"
         "min_tp_r REAL,"
         "max_tp_r REAL,"
         "tp_use_learned_mfe INTEGER,"
         // Exit
         "trailing_mode INTEGER,"
         "partial_tp_r REAL,"
         "partial_close_percent REAL,"
         "be_threshold_r REAL,"
         "trail_start_r REAL,"
         "trail_atr_mult REAL,"
         // Spread
         "max_spread_points INTEGER,"
         // SMC
         "use_smc INTEGER,"
         "smc_swing_lookback INTEGER,"
         "smc_min_impulse_atr REAL,"
         "smc_min_fvg_atr REAL,"
         // MTF
         "use_mtf INTEGER,"
         "htf INTEGER,"
         "mtf INTEGER,"
         "mtf_ema_period INTEGER,"
         // News
         "use_news_filter INTEGER,"
         "news_minutes_before INTEGER,"
         "news_minutes_after INTEGER,"
         // Volatility
         "enable_volatility_filter INTEGER,"
         "volatility_threshold REAL,"
         "volatility_spike_cooldown INTEGER,"
         // Kelly
         "use_kelly INTEGER,"
         "kelly_fraction REAL,"
         "daily_max_dd REAL,"
         "weekly_max_dd REAL,"
         // Learning
         "enable_learning INTEGER,"
         "log_trades_to_file INTEGER,"
         "learning_history INTEGER,"
         "min_trades_for_learning INTEGER,"
         // Adaptive
         "enable_adaptive_risk INTEGER,"
         "enable_adaptive_exits INTEGER,"
         "enable_adaptive_filters INTEGER,"
         // Portfolio Protection
         "use_correlation_filter INTEGER,"
         "daily_max_loss_r REAL,"
         "loss_cooldown_minutes INTEGER,"
         "max_consecutive_losses INTEGER,"
         "use_reversal_filter INTEGER,"
         "reversal_cooldown_minutes INTEGER,"
         // Killzones
         "use_killzone_filter INTEGER,"
         "enable_asian_kz INTEGER,"
         "enable_london_open_kz INTEGER,"
         "enable_ny_kz INTEGER,"
         "enable_london_close_kz INTEGER,"
         // Session
         "use_session_governor INTEGER,"
         "max_trades_per_session INTEGER,"
         "trade_cooldown_minutes INTEGER"
         ");";

      if(!Execute(sqlConfig)) return false;

      return true;
   }
};

#endif
