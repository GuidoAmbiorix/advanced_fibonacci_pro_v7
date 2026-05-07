//+------------------------------------------------------------------+
//| Governor.mq5                                                      |
//| Portfolio Risk Manager for Symbol Engine                          |
//|                                                                   |
//| Attach to ONE chart only (any symbol, any TF).                   |
//| Monitors all Symbol Engine positions by magic number range.       |
//| Closes positions directly — does NOT require Symbol Engine mods.  |
//+------------------------------------------------------------------+
#property copyright "Portfolio Governor"
#property version   "1.00"
#property description "Portfolio-level risk manager. Attach to one chart only."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Magic number range
input group "======= SYMBOL ENGINE MAGIC RANGE ======="
input int    InpMagicMin             = 100001;  // Lowest magic number to monitor
input int    InpMagicMax             = 100020;  // Highest magic number to monitor

//--- Daily P&L
input group "======= DAILY P&L CONTROL ======="
input double InpDailyProfitTarget    = 0.0;     // Daily profit target in $ (0 = disabled)
input double InpDailyLossLimit       = -20.0;   // Daily max loss in $ (negative value)
input bool   InpPauseOnProfitTarget  = true;    // Pause new entries when target hit
input bool   InpCloseOnDailyLoss     = true;    // Close ALL positions on daily loss limit

//--- Portfolio drawdown
input group "======= PORTFOLIO DRAWDOWN ======="
input double InpMaxPortfolioDD_Pct   = 15.0;    // Emergency close: max DD % from equity peak
input double InpReduceRiskAt_Pct     = 8.0;     // Reduce risk signal at this DD %
input bool   InpCloseAllOnMaxDD      = true;    // Emergency close when max DD hit

//--- Correlation filter
input group "======= CORRELATION FILTER ======="
input bool   InpUseCorrelFilter      = true;    // Enable correlation monitoring
input int    InpMaxSameCurrency      = 1;       // Max net positions per currency (e.g. 1 = no doubling GBP)
input bool   InpCloseCorrelOnBreech  = false;   // Close newest trade if correlation breached

//--- Friday close
input group "======= FRIDAY CLOSE ======="
input bool   InpFridayClose          = true;    // Close all managed positions on Friday
input int    InpFridayCloseHour      = 20;      // Server hour to close (0-23)
input int    InpFridayCloseMinute    = 0;       // Server minute to close

//--- Display
input group "======= DISPLAY ======="
input bool   InpShowDashboard        = true;    // Show dashboard via Comment
input int    InpRefreshSeconds       = 5;       // Timer interval in seconds
input int    InpDashboardCorner      = 0;       // 0=TopLeft (unused, Comment always top-left)

//--- Time filters
input group "======= TIEMPO Y COOLDOWN ======="
input int    InpFridayBlockHours     = 3;       // Hours before Friday close to block entries (0=disabled)
input int    InpSymbolCooldownHours  = 4;       // Cooldown hours per symbol after close (0=disabled)

//--- Trade limits
input group "======= LÍMITES DE OPERACIÓN ======="
input int    InpMaxOpenPositions     = 7;       // Max simultaneous open positions (0=disabled)
input int    InpMaxDailyTrades       = 10;      // Max trades opened today total (0=disabled)
input int    InpMaxWeeklyTrades      = 25;      // Max trades opened this week (0=disabled)

//--- Consecutive loss streak
input group "======= RACHA DE PÉRDIDAS ======="
input int    InpConsecLossReduce     = 5;       // Reduce risk 50% after N consecutive losses
input int    InpConsecLossPause      = 10;      // Pause trading after N consecutive losses

//--- Equity curve filter
input group "======= EQUITY CURVE FILTER ======="
input bool   InpUseEqCurve           = true;    // Enable equity curve MA filter
input int    InpEqCurvePeriod        = 20;      // Equity SMA period (snapshots every RefreshSeconds)
input double InpEqCurveReductMult    = 0.6;     // Risk multiplier when equity < SMA (0.0-1.0)

//+------------------------------------------------------------------+
//| GlobalVariable keys (Symbol Engine can read these)               |
//+------------------------------------------------------------------+
#define GV_CURRENT_DD        "GV_CURRENT_DD"          // Symbol Engine reads this (line 839)
#define GV_PAUSE_ENTRIES     "GOV_PAUSE_ENTRIES"       // 1.0 = pause new entries
#define GV_EMERGENCY_CLOSE   "GOV_EMERGENCY_CLOSE"     // 1.0 = close everything
#define GV_REDUCE_RISK       "GOV_REDUCE_RISK"         // Multiplier < 1.0 = reduce risk
#define GV_DAILY_TARGET_HIT  "GOV_DAILY_TARGET_HIT"   // 1.0 = daily profit target reached
#define GV_DAY_START_BAL     "GOV_DAY_START_BAL"       // Balance at start of today
#define GV_DAY_DATE          "GOV_DAY_DATE"            // Stored day timestamp
#define GV_EQUITY_PEAK       "GOV_EQUITY_PEAK"         // Running equity peak
// v2 additions
#define GV_PREFRIDAY_BLOCK   "GOV_PREFRIDAY_BLOCK"     // 1.0 = block new entries pre-weekend
#define GV_COOLDOWN_PREFIX   "GV_COOLDOWN_"            // + symbol = last close timestamp
#define GV_CONSEC_LOSSES     "GOV_CONSEC_LOSSES"       // current consecutive loss count

//+------------------------------------------------------------------+
//| State                                                             |
//+------------------------------------------------------------------+
CTrade    g_trade;
double    g_equityPeak   = 0;
double    g_dayStartBal  = 0;
datetime  g_lastDay      = 0;
bool      g_fridayClosed = false;

// Known base currencies for correlation check
string    g_currencies[] = {"EUR","GBP","USD","JPY","CHF","CAD","AUD","NZD","XAU","XAG"};

// v2: Equity curve buffer — size capped at 200 to prevent out-of-bounds
#define EQ_BUF_MAX 200
double   g_eqCurveBuf[EQ_BUF_MAX];
int      g_eqBufHead   = 0;
int      g_eqBufFilled = 0;

// v2: Consecutive losses
int      g_consecLosses  = 0;
datetime g_lastHistCheck = 0;

// v2: Per-symbol cooldown tracking
string   g_cdSymbols[];
datetime g_cdLastClose[];
bool     g_cdWasOpen[];
int      g_cdCount = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(0); // Governor closes by ticket — magic = 0 means any

   // Restore equity peak from GlobalVariable
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(GV_EQUITY_PEAK))
      g_equityPeak = MathMax(GlobalVariableGet(GV_EQUITY_PEAK), eq);
   else
      g_equityPeak = eq;
   GlobalVariableSet(GV_EQUITY_PEAK, g_equityPeak);

   // Restore or init day balance
   InitDayBalance();

   // Start clean — don't carry over emergency state from last session
   GlobalVariableSet(GV_PAUSE_ENTRIES,   0.0);
   GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);
   GlobalVariableSet(GV_REDUCE_RISK,     1.0);
   GlobalVariableSet(GV_DAILY_TARGET_HIT,0.0);
   GlobalVariableSet(GV_CURRENT_DD,      0.0);
   GlobalVariableSet(GV_PREFRIDAY_BLOCK, 0.0);
   GlobalVariableSet(GV_CONSEC_LOSSES,   0.0);

   // v2: init equity curve buffer
   ArrayInitialize(g_eqCurveBuf, 0.0);

   EventSetTimer(InpRefreshSeconds);

   Print("=== GOVERNOR initialized ===");
   Print("  Monitoring magic range: ", InpMagicMin, " - ", InpMagicMax);
   Print("  Daily loss limit: $", InpDailyLossLimit);
   Print("  Daily profit target: $", InpDailyProfitTarget);
   Print("  Max portfolio DD: ", InpMaxPortfolioDD_Pct, "%");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   // Clear all flags so Symbol Engine can still trade when Governor is removed
   GlobalVariableSet(GV_PAUSE_ENTRIES,   0.0);
   GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);
   GlobalVariableSet(GV_REDUCE_RISK,     1.0);
   GlobalVariableSet(GV_DAILY_TARGET_HIT,0.0);
   GlobalVariableSet(GV_PREFRIDAY_BLOCK, 0.0);
   Comment("");
   Print("Governor removed — all control flags cleared.");
}

void OnTick() { } // Timer does the work

//+------------------------------------------------------------------+
//| v2: Pre-Friday entry block                                        |
//+------------------------------------------------------------------+
bool IsPreFridayBlock()
{
   if(InpFridayBlockHours <= 0) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) return false;
   int blockHour = InpFridayCloseHour - InpFridayBlockHours;
   if(blockHour < 0) blockHour = 0;
   return (dt.hour >= blockHour);
}

//+------------------------------------------------------------------+
//| v2: Equity curve SMA filter — returns risk multiplier            |
//+------------------------------------------------------------------+
double GetEqCurveMultiplier()
{
   if(!InpUseEqCurve || InpEqCurvePeriod <= 0) return 1.0;

   int safePeriod = MathMin(InpEqCurvePeriod, EQ_BUF_MAX); // guard against oversized period
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   int idx = g_eqBufHead % safePeriod;
   g_eqCurveBuf[idx] = eq;
   g_eqBufHead++;
   if(g_eqBufFilled < safePeriod) g_eqBufFilled++;

   if(g_eqBufFilled < safePeriod / 2) return 1.0; // warmup

   double sum = 0;
   int n = MathMin(g_eqBufFilled, safePeriod);
   for(int i = 0; i < n; i++)
   {
      int bi = ((g_eqBufHead - 1 - i) % safePeriod + safePeriod) % safePeriod;
      sum += g_eqCurveBuf[bi];
   }
   double sma = sum / n;
   if(sma <= 0) return 1.0;

   if(eq < sma)
   {
      static datetime lastEqLog = 0;
      if(TimeCurrent() - lastEqLog > 300)
      {
         Print("[GOVERNOR] EqCurve: equity=", DoubleToString(eq,2),
               " < SMA", InpEqCurvePeriod, "=", DoubleToString(sma,2),
               " → risk x", DoubleToString(InpEqCurveReductMult,2));
         lastEqLog = TimeCurrent();
      }
      return InpEqCurveReductMult;
   }
   return 1.0;
}

//+------------------------------------------------------------------+
//| v2: Count ENTRY deals today for managed magic range              |
//+------------------------------------------------------------------+
int CountTodayTrades()
{
   if(InpMaxDailyTrades <= 0) return 0;
   datetime todayStart = GetDayStart(TimeCurrent());
   HistorySelect(todayStart, TimeCurrent());
   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      int magic = (int)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| v2: Count ENTRY deals this week                                   |
//+------------------------------------------------------------------+
int CountWeekTrades()
{
   if(InpMaxWeeklyTrades <= 0) return 0;
   datetime weekStart = (datetime)iTime(NULL, PERIOD_W1, 0);
   HistorySelect(weekStart, TimeCurrent());
   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      int magic = (int)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| v2: Detect consecutive losses from history                        |
//+------------------------------------------------------------------+
int CheckConsecLosses()
{
   if(TimeCurrent() - g_lastHistCheck < 30) return g_consecLosses;
   g_lastHistCheck = TimeCurrent();

   HistorySelect(TimeCurrent() - 30*24*3600, TimeCurrent());
   int total = HistoryDealsTotal();
   int streak = 0;

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      int magic = (int)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      if(profit < 0) streak++;
      else           break;
   }

   g_consecLosses = streak;
   GlobalVariableSet(GV_CONSEC_LOSSES, (double)streak);
   return streak;
}

//+------------------------------------------------------------------+
//| v2: Publish per-symbol cooldown when position closes             |
//+------------------------------------------------------------------+
void PublishCooldowns()
{
   if(InpSymbolCooldownHours <= 0) return;

   // Collect currently open managed symbols
   string nowOpen[];
   int nowCount = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      // Add if not duplicate
      bool dup = false;
      for(int k = 0; k < nowCount; k++) if(nowOpen[k] == sym) { dup = true; break; }
      if(!dup) { ArrayResize(nowOpen, nowCount+1); nowOpen[nowCount++] = sym; }
   }

   // Detect closes: symbols that were tracked as open but are now gone
   for(int t = 0; t < g_cdCount; t++)
   {
      if(!g_cdWasOpen[t]) continue;
      bool stillOpen = false;
      for(int o = 0; o < nowCount; o++)
         if(nowOpen[o] == g_cdSymbols[t]) { stillOpen = true; break; }

      if(!stillOpen)
      {
         // Position just closed — set cooldown
         g_cdLastClose[t] = TimeCurrent();
         g_cdWasOpen[t]   = false;
         GlobalVariableSet(GV_COOLDOWN_PREFIX + g_cdSymbols[t], (double)TimeCurrent());
         Print("[GOVERNOR] Cooldown set: ", g_cdSymbols[t], " locked for ",
               InpSymbolCooldownHours, "h");
      }
      // Expire cooldown
      if(g_cdLastClose[t] > 0 &&
         TimeCurrent() - g_cdLastClose[t] > (datetime)InpSymbolCooldownHours * 3600)
      {
         g_cdLastClose[t] = 0;
         GlobalVariableSet(GV_COOLDOWN_PREFIX + g_cdSymbols[t], 0.0);
      }
   }

   // Rebuild tracking array — copy old data BEFORE resize to avoid out-of-bounds
   string   oldSymbols[];
   datetime oldLastClose[];
   bool     oldWasOpen[];
   int      oldCount = g_cdCount;
   ArrayResize(oldSymbols,   oldCount);
   ArrayResize(oldLastClose, oldCount);
   ArrayResize(oldWasOpen,   oldCount);
   for(int k = 0; k < oldCount; k++)
   {
      oldSymbols[k]   = g_cdSymbols[k];
      oldLastClose[k] = g_cdLastClose[k];
      oldWasOpen[k]   = g_cdWasOpen[k];
   }

   // Build new tracking list:
   //   1) All currently open symbols (with restored cooldown data from old list)
   //   2) Closed symbols that still have an active cooldown — prevent data loss on mass-close
   string   keepSym[];
   datetime keepLastClose[];
   bool     keepWasOpen[];
   int      keepCount = 0;

   // Pass 1: currently open positions
   for(int o = 0; o < nowCount; o++)
   {
      ArrayResize(keepSym,       keepCount + 1);
      ArrayResize(keepLastClose, keepCount + 1);
      ArrayResize(keepWasOpen,   keepCount + 1);
      keepSym[keepCount]       = nowOpen[o];
      keepLastClose[keepCount] = 0;
      keepWasOpen[keepCount]   = true;
      for(int t = 0; t < oldCount; t++)
         if(oldSymbols[t] == nowOpen[o]) { keepLastClose[keepCount] = oldLastClose[t]; break; }
      keepCount++;
   }

   // Pass 2: old entries with active cooldown that are no longer open (preserve across mass-close)
   for(int t = 0; t < oldCount; t++)
   {
      if(oldLastClose[t] == 0) continue; // no active cooldown — skip
      bool alreadyIn = false;
      for(int k = 0; k < keepCount; k++)
         if(keepSym[k] == oldSymbols[t]) { alreadyIn = true; break; }
      if(alreadyIn) continue;
      ArrayResize(keepSym,       keepCount + 1);
      ArrayResize(keepLastClose, keepCount + 1);
      ArrayResize(keepWasOpen,   keepCount + 1);
      keepSym[keepCount]       = oldSymbols[t];
      keepLastClose[keepCount] = oldLastClose[t];
      keepWasOpen[keepCount]   = false;
      keepCount++;
   }

   ArrayResize(g_cdSymbols,   keepCount);
   ArrayResize(g_cdLastClose, keepCount);
   ArrayResize(g_cdWasOpen,   keepCount);
   for(int k = 0; k < keepCount; k++)
   {
      g_cdSymbols[k]   = keepSym[k];
      g_cdLastClose[k] = keepLastClose[k];
      g_cdWasOpen[k]   = keepWasOpen[k];
   }
   g_cdCount = keepCount;
}

//+------------------------------------------------------------------+
void OnTimer()
{
   CheckNewDay();

   //--- Update equity peak
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_equityPeak)
   {
      g_equityPeak = eq;
      GlobalVariableSet(GV_EQUITY_PEAK, g_equityPeak);
   }

   //--- Calculate portfolio drawdown
   double dd = 0.0;
   if(g_equityPeak > 0)
      dd = (g_equityPeak - eq) / g_equityPeak * 100.0;
   GlobalVariableSet(GV_CURRENT_DD, dd); // Symbol Engine reads this

   //--- Calculate daily P&L
   double dailyPnL = CalcDailyPnL();

   //--- Decision flags
   bool pauseEntries   = false;
   bool emergencyClose = false;
   double riskMult     = 1.0;
   string pauseReason  = "";
   string closeReason  = "";

   //--- Rule 1: Daily profit target
   if(InpDailyProfitTarget > 0 && dailyPnL >= InpDailyProfitTarget && InpPauseOnProfitTarget)
   {
      pauseEntries = true;
      pauseReason  = "Daily target hit";
      GlobalVariableSet(GV_DAILY_TARGET_HIT, 1.0);
   }
   else
   {
      GlobalVariableSet(GV_DAILY_TARGET_HIT, 0.0);
   }

   //--- Rule 2: Daily loss limit
   if(dailyPnL <= InpDailyLossLimit && InpCloseOnDailyLoss)
   {
      emergencyClose = true;
      pauseEntries   = true;
      closeReason    = StringFormat("Daily loss limit ($%.2f)", dailyPnL);
   }

   //--- Rule 3: Portfolio drawdown
   if(dd >= InpMaxPortfolioDD_Pct && InpCloseAllOnMaxDD)
   {
      emergencyClose = true;
      pauseEntries   = true;
      closeReason    = StringFormat("Max DD hit (%.2f%%)", dd);
   }
   else if(dd >= InpReduceRiskAt_Pct)
   {
      riskMult    = 0.5;
      pauseReason = StringFormat("DD %.1f%% — risk reduced 50%%", dd);
   }

   //--- Rule 4: Friday close
   if(InpFridayClose && IsFridayCloseTime() && !g_fridayClosed)
   {
      emergencyClose = true;
      pauseEntries   = true;
      closeReason    = "Friday close time";
      g_fridayClosed = true;
   }
   // Reset Friday flag on Monday
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) g_fridayClosed = false;

   //--- Rule 5: Pre-Friday entry block
   bool preFriday = IsPreFridayBlock();
   GlobalVariableSet(GV_PREFRIDAY_BLOCK, preFriday ? 1.0 : 0.0);
   if(preFriday && !pauseEntries)
   {
      pauseEntries = true;
      if(pauseReason == "") pauseReason = StringFormat("PRE_FRIDAY(%dh before close)", InpFridayBlockHours);
   }

   //--- Rule 6: Max open positions
   int nOpen = CountManagedPositions();
   if(InpMaxOpenPositions > 0 && nOpen >= InpMaxOpenPositions && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = StringFormat("MAX_POSITIONS(%d/%d)", nOpen, InpMaxOpenPositions);
   }

   //--- Rule 7: Max daily trades
   int todayTrades = CountTodayTrades();
   if(InpMaxDailyTrades > 0 && todayTrades >= InpMaxDailyTrades && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = StringFormat("MAX_DAILY(%d/%d)", todayTrades, InpMaxDailyTrades);
   }

   //--- Rule 8: Max weekly trades
   int weekTrades = CountWeekTrades();
   if(InpMaxWeeklyTrades > 0 && weekTrades >= InpMaxWeeklyTrades && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = StringFormat("MAX_WEEKLY(%d/%d)", weekTrades, InpMaxWeeklyTrades);
   }

   //--- Rule 9: Consecutive loss streak
   int consec = CheckConsecLosses();
   if(InpConsecLossPause > 0 && consec >= InpConsecLossPause && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = StringFormat("CONSEC_LOSS_PAUSE(%d losses)", consec);
   }
   else if(InpConsecLossReduce > 0 && consec >= InpConsecLossReduce)
      riskMult = MathMin(riskMult, 0.5);

   //--- Rule 10: Equity curve filter
   double eqMult = GetEqCurveMultiplier();
   if(eqMult < 1.0)
      riskMult = MathMin(riskMult, eqMult);

   //--- Correlation check BEFORE publishing pause flag (preventive, not just reactive)
   string correlWarning = "";
   if(InpUseCorrelFilter)
   {
      correlWarning = CheckCorrelation();
      if(correlWarning != "" && !pauseEntries)
      {
         pauseEntries = true;
         if(pauseReason == "")
            pauseReason = (correlWarning == "AT_CAP") ? "CORREL_AT_LIMIT" :
                          "CORRELATION: " + correlWarning;
      }
   }

   //--- Publish per-symbol cooldowns
   PublishCooldowns();

   //--- Execute emergency close
   if(emergencyClose)
   {
      Print("Governor EMERGENCY CLOSE — Reason: ", closeReason);
      CloseAllManagedPositions(closeReason);
      GlobalVariableSet(GV_EMERGENCY_CLOSE, 1.0);
   }
   else
   {
      GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);
   }

   GlobalVariableSet(GV_PAUSE_ENTRIES, pauseEntries ? 1.0 : 0.0);
   GlobalVariableSet(GV_REDUCE_RISK,   riskMult);

   //--- Dashboard
   if(InpShowDashboard)
      DrawDashboard(dailyPnL, dd, riskMult, eqMult, pauseEntries, pauseReason,
                    emergencyClose, closeReason, correlWarning, todayTrades, weekTrades);
}

//+------------------------------------------------------------------+
//| Day balance tracking                                              |
//+------------------------------------------------------------------+
void InitDayBalance()
{
   datetime today = GetDayStart(TimeCurrent());
   if(GlobalVariableCheck(GV_DAY_DATE) && (datetime)GlobalVariableGet(GV_DAY_DATE) == today)
   {
      g_dayStartBal = GlobalVariableGet(GV_DAY_START_BAL);
   }
   else
   {
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(GV_DAY_START_BAL, g_dayStartBal);
      GlobalVariableSet(GV_DAY_DATE, (double)today);
   }
   g_lastDay = today;
}

void CheckNewDay()
{
   datetime today = GetDayStart(TimeCurrent());
   if(today != g_lastDay)
   {
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(GV_DAY_START_BAL, g_dayStartBal);
      GlobalVariableSet(GV_DAY_DATE, (double)today);
      g_lastDay = today;
      // Reset daily flags — keep emergency active if still in critical DD
      GlobalVariableSet(GV_DAILY_TARGET_HIT, 0.0);
      double _eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double _dd = (g_equityPeak > 0) ? (g_equityPeak - _eq) / g_equityPeak * 100.0 : 0.0;
      bool _stillEmergency = (InpCloseAllOnMaxDD && _dd >= InpMaxPortfolioDD_Pct);
      if(!_stillEmergency)
      {
         GlobalVariableSet(GV_PAUSE_ENTRIES,   0.0);
         GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);
      }
      else
      {
         Print("Governor: New day — EMERGENCY stays active (DD=",
               DoubleToString(_dd,2), "% >= limit ", DoubleToString(InpMaxPortfolioDD_Pct,1), "%)");
      }
      Print("Governor: New trading day. Day start balance: $", DoubleToString(g_dayStartBal, 2));
   }
}

datetime GetDayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| P&L calculation: realized today + floating on managed positions   |
//+------------------------------------------------------------------+
double CalcDailyPnL()
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double floating = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      floating += PositionGetDouble(POSITION_PROFIT)
               +  PositionGetDouble(POSITION_SWAP);
   }
   return (balance - g_dayStartBal) + floating;
}

//+------------------------------------------------------------------+
//| Friday close check                                                |
//+------------------------------------------------------------------+
bool IsFridayCloseTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 &&
           (dt.hour > InpFridayCloseHour ||
           (dt.hour == InpFridayCloseHour && dt.min >= InpFridayCloseMinute)));
}

//+------------------------------------------------------------------+
//| Close all managed positions                                       |
//+------------------------------------------------------------------+
void CloseAllManagedPositions(string reason)
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(g_trade.PositionClose(ticket))
      {
         Print("Governor closed: ", sym, " ticket=", ticket, " [", reason, "]");
         closed++;
      }
      else
      {
         Print("Governor FAILED to close: ", sym, " ticket=", ticket,
               " error=", g_trade.ResultRetcodeDescription());
      }
   }
   if(closed > 0)
      Print("Governor: Closed ", closed, " positions. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Correlation check — returns warning string                        |
//+------------------------------------------------------------------+
string CheckCorrelation()
{
   // Net exposure per currency: positive = long bias, negative = short bias
   int exposure[];
   int nCurr = ArraySize(g_currencies);
   ArrayResize(exposure, nCurr);
   ArrayInitialize(exposure, 0);

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;

      string sym  = PositionGetString(POSITION_SYMBOL);
      int    type = (int)PositionGetInteger(POSITION_TYPE); // 0=buy, 1=sell
      int    dir  = (type == POSITION_TYPE_BUY) ? 1 : -1;

      // Extract base (first 3 chars) and quote (next 3 chars) from clean symbol
      string clean = SymbolClean(sym);
      if(StringLen(clean) < 6) continue;
      string base  = StringSubstr(clean, 0, 3);
      string quote = StringSubstr(clean, 3, 3);

      // Add exposure
      for(int c = 0; c < nCurr; c++)
      {
         if(base  == g_currencies[c]) exposure[c] += dir;
         if(quote == g_currencies[c]) exposure[c] -= dir;
      }
   }

   // Find over-correlated currencies
   string warning = "";
   bool   atCapacity = false; // at limit — block entries but don't close
   for(int c = 0; c < nCurr; c++)
   {
      int abs_exp = MathAbs(exposure[c]);
      if(abs_exp > InpMaxSameCurrency)
      {
         string side = (exposure[c] > 0) ? "LONG" : "SHORT";
         warning += StringFormat("%s: %d× %s  ", g_currencies[c], abs_exp, side);
      }
      else if(abs_exp == InpMaxSameCurrency)
         atCapacity = true; // at limit — prevent next entry but no close needed
   }

   if(warning != "" && InpCloseCorrelOnBreech)
   {
      // Close the newest managed position to reduce correlation
      CloseNewestManagedPosition();
   }

   // Prefix "AT_CAP" so OnTimer can set pauseEntries=true without closing
   if(warning == "" && atCapacity)
      warning = "AT_CAP";

   return warning;
}

// Strip broker suffix (m, .raw, .ECN, etc.) and uppercase
string SymbolClean(string sym)
{
   StringTrimRight(sym);
   StringTrimLeft(sym);
   StringToUpper(sym);
   // Keep only A-Z characters, stop after 6
   string result = "";
   for(int i = 0; i < StringLen(sym) && StringLen(result) < 6; i++)
   {
      ushort ch = StringGetCharacter(sym, i);
      if(ch >= 'A' && ch <= 'Z')
         result += ShortToString(ch);
   }
   return result;
}

void CloseNewestManagedPosition()
{
   datetime newest = 0;
   ulong    newestTicket = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime > newest) { newest = openTime; newestTicket = ticket; }
   }
   if(newestTicket > 0)
   {
      PositionSelectByTicket(newestTicket);
      Print("Governor: Closing newest position (correlation breached) — ",
            PositionGetString(POSITION_SYMBOL), " ticket=", newestTicket);
      g_trade.PositionClose(newestTicket);
   }
}

//+------------------------------------------------------------------+
//| Count managed positions                                           |
//+------------------------------------------------------------------+
int CountManagedPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic >= InpMagicMin && magic <= InpMagicMax) count++;
   }
   return count;
}

double GetManagedFloating()
{
   double total = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void DrawDashboard(double dailyPnL, double dd, double riskMult, double eqMult,
                   bool paused, string pauseReason,
                   bool emergency, string closeReason,
                   string correlWarning, int todayTrades, int weekTrades)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   int    nTrades  = CountManagedPositions();
   double floating = GetManagedFloating();

   string L = "═══════════════════════════════════════\n";
   string msg = "\n" + L;
   msg += "  ▶  GOVERNOR  —  PORTFOLIO RISK MGR  ◀\n";
   msg += L;

   // Account
   msg += StringFormat("  Balance   : $%-10.2f  Equity: $%.2f\n", balance, equity);
   msg += StringFormat("  Equity Peak: $%.2f\n", g_equityPeak);
   msg += "\n";

   // Daily P&L
   string pnlColor = (dailyPnL >= 0) ? "▲" : "▼";
   msg += StringFormat("  Daily P&L  : %s $%.2f", pnlColor, dailyPnL);
   if(InpDailyProfitTarget > 0)
      msg += StringFormat("  /  Target: $%.2f", InpDailyProfitTarget);
   msg += "\n";
   msg += StringFormat("  Day Start  : $%.2f\n", g_dayStartBal);
   msg += "\n";

   // Drawdown
   string ddStatus = (dd >= InpMaxPortfolioDD_Pct) ? "!! CRITICAL !!" :
                     (dd >= InpReduceRiskAt_Pct)    ? "CAUTION"        : "OK";
   msg += StringFormat("  Portfolio DD: %.2f%%  [%s]  Max: %.1f%%\n", dd, ddStatus, InpMaxPortfolioDD_Pct);
   msg += StringFormat("  Risk Mult   : %.2fx\n", riskMult);
   msg += "\n";

   // Positions
   msg += StringFormat("  Open Trades : %d  (magic %d-%d)\n", nTrades, InpMagicMin, InpMagicMax);
   msg += StringFormat("  Floating    : $%.2f\n", floating);
   msg += "\n";

   // v2: Trade counters (cached from OnTimer — no redundant HistorySelect)
   int td = todayTrades;
   int tw = weekTrades;
   msg += StringFormat("  Trades Today : %d", td);
   if(InpMaxDailyTrades > 0) msg += StringFormat("/%d", InpMaxDailyTrades);
   msg += StringFormat("  |  Week: %d", tw);
   if(InpMaxWeeklyTrades > 0) msg += StringFormat("/%d", InpMaxWeeklyTrades);
   msg += "\n";

   // v2: Consecutive losses
   if(g_consecLosses > 0)
      msg += StringFormat("  Streak: %d consec losses (reduce@%d pause@%d)\n",
                          g_consecLosses, InpConsecLossReduce, InpConsecLossPause);

   // v2: Equity curve (value passed from OnTimer — no double-sampling)
   if(InpUseEqCurve && eqMult < 1.0)
      msg += StringFormat("  EqCurve: equity BELOW SMA%d → risk x%.1f\n",
                          InpEqCurvePeriod, eqMult);

   msg += "\n";

   // Status
   msg += L;
   if(emergency)
      msg += StringFormat("  !! EMERGENCY CLOSE  !!  %s\n", closeReason);
   else if(paused)
      msg += StringFormat("  ⏸  ENTRIES PAUSED  —  %s\n", pauseReason);
   else
      msg += "  ✔  ENTRIES OPEN\n";

   if(correlWarning != "")
      msg += StringFormat("  ⚠ CORRELATION: %s\n", correlWarning);

   // Friday
   if(InpFridayClose)
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5)
         msg += StringFormat("  ⚠ FRIDAY — close at %02d:%02d server time\n",
                             InpFridayCloseHour, InpFridayCloseMinute);
   }

   msg += L;
   msg += StringFormat("  Updated: %s\n", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   msg += L;

   Comment(msg);
}
