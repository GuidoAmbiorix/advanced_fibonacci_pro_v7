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
   Comment("");
   Print("Governor removed — all control flags cleared.");
}

void OnTick() { } // Timer does the work

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

   //--- Correlation check
   string correlWarning = "";
   if(InpUseCorrelFilter)
      correlWarning = CheckCorrelation();

   //--- Dashboard
   if(InpShowDashboard)
      DrawDashboard(dailyPnL, dd, riskMult, pauseEntries, pauseReason,
                    emergencyClose, closeReason, correlWarning);
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
      // Reset daily flags
      GlobalVariableSet(GV_DAILY_TARGET_HIT, 0.0);
      GlobalVariableSet(GV_PAUSE_ENTRIES,    0.0);
      GlobalVariableSet(GV_EMERGENCY_CLOSE,  0.0);
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
   for(int c = 0; c < nCurr; c++)
   {
      int abs_exp = MathAbs(exposure[c]);
      if(abs_exp > InpMaxSameCurrency)
      {
         string side = (exposure[c] > 0) ? "LONG" : "SHORT";
         warning += StringFormat("%s: %d× %s  ", g_currencies[c], abs_exp, side);
      }
   }

   if(warning != "" && InpCloseCorrelOnBreech)
   {
      // Close the newest managed position to reduce correlation
      CloseNewestManagedPosition();
   }

   return warning;
}

// Strip broker suffix (m, .raw, .ECN, etc.) and uppercase
string SymbolClean(string sym)
{
   sym = StringTrimLeft(StringTrimRight(sym));
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
void DrawDashboard(double dailyPnL, double dd, double riskMult,
                   bool paused, string pauseReason,
                   bool emergency, string closeReason,
                   string correlWarning)
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
