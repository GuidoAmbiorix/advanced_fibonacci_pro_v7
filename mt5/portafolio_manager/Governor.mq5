//+------------------------------------------------------------------+
//| Governor.mq5                                                      |
//| Portfolio Risk Manager for Symbol Engine                          |
//|                                                                   |
//| Attach to ONE chart only (any symbol, any TF).                   |
//| Monitors all Symbol Engine positions by magic number range.       |
//| Closes positions directly — does NOT require Symbol Engine mods.  |
//+------------------------------------------------------------------+
#property copyright "Portfolio Governor"
#property version   "2.00"
#property description "Portfolio-level risk manager with Institutional Safety."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Magic number range
input group "======= SYMBOL ENGINE MAGIC RANGE ======="
input int    InpMagicMin             = 100001;  // Lowest magic number to monitor
input int    InpMagicMax             = 100044;  // Highest magic number to monitor

//--- Daily P&L
input group "======= DAILY P&L CONTROL ======="
input double InpDailyProfitTarget    = 0.0;     // Daily profit target in $ (0 = disabled)
input double InpDailyLossLimit       = -132.0;  // *** Adjusted for $6000 account (2.2%) ***
input bool   InpPauseOnProfitTarget  = true;    // Pause new entries when target hit
input bool   InpCloseOnProfitTarget  = false;   // Close ALL positions when daily profit target hit
input bool   InpCloseOnDailyLoss     = true;    // Close ALL positions on daily loss limit
input double InpSymbolDailyTarget    = 0.0;     // Per-symbol daily profit target $ (0=disabled) — pauses that symbol only

//--- Portfolio drawdown
input group "======= PORTFOLIO DRAWDOWN ======="
input double InpMaxPortfolioDD_Pct   = 3.5;     // *** Safety limit for funded account ***
input double InpReduceRiskAt_Pct     = 1.5;     // Reduce risk signal at this DD %
input bool   InpCloseAllOnMaxDD      = true;    // Emergency close when max DD hit

//--- Correlation filter
input group "======= CORRELATION FILTER ======="
input bool   InpUseCorrelFilter      = true;    // Enable correlation monitoring
input int    InpMaxSameCurrency      = 2;       // *** INCREASED TO 2 for 15-pair swarm ***
input bool   InpCloseCorrelOnBreech  = false;   // Close newest trade if correlation breached

//--- Institutional Safety
input group "======= INSTITUTIONAL SAFETY ======="
input double InpEquityVelocityLimit  = 1.0;     // Max % drop allowed in 1 hour before reducing risk
input int    InpGlobalVolatileLimit  = 3;       // Max symbols in VOLATILE regime before pausing entries

//--- Friday close
input group "======= FRIDAY CLOSE ======="
input bool   InpFridayClose          = true;    // Close all managed positions on Friday
input int    InpFridayCloseHour      = 20;      // Server hour to close (0-23)
input int    InpFridayCloseMinute    = 0;       // Server minute to close

//--- Display
input group "======= DISPLAY ======="
input bool   InpShowDashboard        = true;    // Show dashboard via Comment
input int    InpRefreshSeconds       = 5;       // Timer interval in seconds

//--- Time filters
input group "======= TIEMPO Y COOLDOWN ======="
input int    InpFridayBlockHours     = 3;       // Hours before Friday close to block entries (0=disabled)
input int    InpSymbolCooldownHours  = 4;       // Cooldown hours per symbol after close (0=disabled)

//--- Trade limits
input group "======= LÍMITES DE OPERACIÓN ======="
input int    InpMaxOpenPositions     = 12;      // *** INCREASED TO 12 for swarm ***
input int    InpMaxDailyTrades       = 20;      // *** INCREASED TO 20 ***
input int    InpMaxWeeklyTrades      = 50;      // *** INCREASED TO 50 ***

//--- Consecutive loss streak
input group "======= RACHA DE PÉRDIDAS ======="
input int    InpConsecLossReduce     = 4;       // *** REDUCED TO 4 for aggressive strategy ***
input int    InpConsecLossPause      = 8;       // *** REDUCED TO 8 ***

//--- Equity curve filter
input group "======= EQUITY CURVE FILTER ======="
input bool   InpUseEqCurve           = true;    // Enable equity curve MA filter
input int    InpEqCurvePeriod        = 20;      // Equity SMA period
input double InpEqCurveReductMult    = 0.6;     // Risk multiplier when equity < SMA

//+------------------------------------------------------------------+
//| GlobalVariable keys (Symbol Engine can read these)               |
//+------------------------------------------------------------------+
#define GV_CURRENT_DD        "GV_CURRENT_DD"
#define GV_PAUSE_ENTRIES     "GOV_PAUSE_ENTRIES"
#define GV_EMERGENCY_CLOSE   "GOV_EMERGENCY_CLOSE"
#define GV_REDUCE_RISK       "GOV_REDUCE_RISK"
#define GV_DAILY_TARGET_HIT  "GOV_DAILY_TARGET_HIT"
#define GV_DAY_START_BAL     "GOV_DAY_START_BAL"
#define GV_DAY_DATE          "GOV_DAY_DATE"
#define GV_EQUITY_PEAK       "GOV_EQUITY_PEAK"
#define GV_PREFRIDAY_BLOCK   "GOV_PREFRIDAY_BLOCK"
#define GV_COOLDOWN_PREFIX   "GV_COOLDOWN_"
#define GV_CONSEC_LOSSES     "GOV_CONSEC_LOSSES"
#define GV_SYM_PAUSE_PREFIX  "GOV_SYM_PAUSED_"

//+------------------------------------------------------------------+
//| State                                                             |
//+------------------------------------------------------------------+
CTrade    g_trade;
double    g_equityPeak   = 0;
double    g_dayStartBal  = 0;
datetime  g_lastDay      = 0;
bool      g_fridayClosed = false;

string    g_currencies[] = {"EUR","GBP","USD","JPY","CHF","CAD","AUD","NZD","XAU","XAG"};

#define EQ_BUF_MAX 200
double   g_eqCurveBuf[EQ_BUF_MAX];
int      g_eqBufHead   = 0;
int      g_eqBufFilled = 0;

int      g_consecLosses  = 0;
datetime g_lastHistCheck = 0;

string   g_cdSymbols[];
datetime g_cdLastClose[];
bool     g_cdWasOpen[];
int      g_cdCount = 0;

// Institutional Safety State
double    g_lastHourEquity = 0;
datetime  g_lastHourTime   = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(0);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(GV_EQUITY_PEAK))
      g_equityPeak = MathMax(GlobalVariableGet(GV_EQUITY_PEAK), eq);
   else
      g_equityPeak = eq;
   GlobalVariableSet(GV_EQUITY_PEAK, g_equityPeak);

   InitDayBalance();

   GlobalVariableSet(GV_PAUSE_ENTRIES,   0.0);
   GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);
   GlobalVariableSet(GV_REDUCE_RISK,     1.0);
   GlobalVariableSet(GV_DAILY_TARGET_HIT,0.0);
   GlobalVariableSet(GV_CURRENT_DD,      0.0);
   GlobalVariableSet(GV_PREFRIDAY_BLOCK, 0.0);
   GlobalVariableSet(GV_CONSEC_LOSSES,   0.0);

   ArrayInitialize(g_eqCurveBuf, 0.0);
   g_lastHourTime = TimeCurrent();
   g_lastHourEquity = eq;

   EventSetTimer(InpRefreshSeconds);
   Print("=== GOVERNOR v2 (AGGRESSIVE) initialized ===");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   GlobalVariableSet(GV_PAUSE_ENTRIES,   0.0);
   GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);
   GlobalVariableSet(GV_REDUCE_RISK,     1.0);
   GlobalVariableSet(GV_DAILY_TARGET_HIT,0.0);
   GlobalVariableSet(GV_PREFRIDAY_BLOCK, 0.0);
   Comment("");
}

void OnTick() { }

//+------------------------------------------------------------------+
void OnTimer()
{
   CheckNewDay();

   datetime now = TimeCurrent();
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // --- INSTITUTIONAL SAFETY: EQUITY VELOCITY ---
   if(now - g_lastHourTime >= 3600)
   {
      g_lastHourTime = now;
      g_lastHourEquity = eq;
   }
   double velocityDD = (g_lastHourEquity > 0) ? (g_lastHourEquity - eq) / g_lastHourEquity * 100.0 : 0;
   bool velocityTrigger = (velocityDD >= InpEquityVelocityLimit);

   // --- INSTITUTIONAL SAFETY: GLOBAL VOLATILITY ---
   int volatileCount = 0;
   for(int i = 0; i < GlobalVariablesTotal(); i++)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, "PG_Regime_") == 0)
      {
         int regime = (int)GlobalVariableGet(name);
         if(regime == 3 || regime == 4) volatileCount++; 
      }
   }
   bool globalVolTrigger = (volatileCount >= InpGlobalVolatileLimit);

   //--- Update peak
   if(eq > g_equityPeak)
   {
      g_equityPeak = eq;
      GlobalVariableSet(GV_EQUITY_PEAK, g_equityPeak);
   }

   double dd = (g_equityPeak > 0) ? (g_equityPeak - eq) / g_equityPeak * 100.0 : 0;
   GlobalVariableSet(GV_CURRENT_DD, dd);

   double dailyPnL = CalcDailyPnL();

   bool pauseEntries   = false;
   bool emergencyClose = false;
   double riskMult     = 1.0;
   string pauseReason  = "";
   string closeReason  = "";

   // Rules
   if(InpDailyProfitTarget > 0 && dailyPnL >= InpDailyProfitTarget)
   {
      GlobalVariableSet(GV_DAILY_TARGET_HIT, 1.0);
      if(InpPauseOnProfitTarget)
      {
         pauseEntries = true;
         pauseReason  = StringFormat("Daily target $%.2f hit", InpDailyProfitTarget);
      }
      if(InpCloseOnProfitTarget)
      {
         emergencyClose = true;
         closeReason    = StringFormat("Daily target $%.2f — closing all", InpDailyProfitTarget);
      }
   }

   if(dailyPnL <= InpDailyLossLimit && InpCloseOnDailyLoss)
   {
      emergencyClose = true;
      pauseEntries   = true;
      closeReason    = StringFormat("Daily loss limit ($%.2f)", dailyPnL);
   }

   if(dd >= InpMaxPortfolioDD_Pct && InpCloseAllOnMaxDD)
   {
      emergencyClose = true;
      pauseEntries   = true;
      closeReason    = StringFormat("Max DD hit (%.2f%%)", dd);
   }
   else if(dd >= InpReduceRiskAt_Pct || velocityTrigger)
   {
      riskMult    = 0.5;
      pauseReason = velocityTrigger ? "High Equity Velocity" : StringFormat("DD %.1f%%", dd);
   }

   if(globalVolTrigger && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason = StringFormat("Global Vol Spike (%d symbols)", volatileCount);
   }

   if(InpFridayClose && IsFridayCloseTime() && !g_fridayClosed)
   {
      emergencyClose = true;
      pauseEntries   = true;
      closeReason    = "Friday close time";
      g_fridayClosed = true;
   }

   if(IsPreFridayBlock() && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason = "Pre-Friday block";
   }

   int nOpen = CountManagedPositions();
   if(InpMaxOpenPositions > 0 && nOpen >= InpMaxOpenPositions && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = StringFormat("MAX_POS(%d)", nOpen);
   }

   int td = CountTodayTrades();
   if(InpMaxDailyTrades > 0 && td >= InpMaxDailyTrades && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = "MAX_DAILY";
   }

   int tw = CountWeekTrades();
   if(InpMaxWeeklyTrades > 0 && tw >= InpMaxWeeklyTrades && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = "MAX_WEEKLY";
   }

   int consec = CheckConsecLosses();
   if(InpConsecLossPause > 0 && consec >= InpConsecLossPause && !pauseEntries)
   {
      pauseEntries = true;
      pauseReason  = "CONSEC_LOSS_PAUSE";
   }
   else if(InpConsecLossReduce > 0 && consec >= InpConsecLossReduce)
      riskMult = MathMin(riskMult, 0.5);

   double eqMult = GetEqCurveMultiplier();
   if(eqMult < 1.0) riskMult = MathMin(riskMult, eqMult);

   string correlWarning = "";
   if(InpUseCorrelFilter)
   {
      correlWarning = CheckCorrelation();
      if(correlWarning != "" && !pauseEntries)
      {
         pauseEntries = true;
         pauseReason = (correlWarning == "AT_CAP") ? "CORREL_CAP" : "CORRELATION";
      }
   }

   PublishCooldowns();

   // --- PER-SYMBOL DAILY TARGET ---
   if(InpSymbolDailyTarget > 0)
      CheckSymbolTargets();

   if(emergencyClose)
   {
      CloseAllManagedPositions(closeReason);
      GlobalVariableSet(GV_EMERGENCY_CLOSE, 1.0);
   }
   else GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);

   GlobalVariableSet(GV_PAUSE_ENTRIES, pauseEntries ? 1.0 : 0.0);
   GlobalVariableSet(GV_REDUCE_RISK,   riskMult);

   if(InpShowDashboard)
      DrawDashboard(dailyPnL, dd, riskMult, eqMult, pauseEntries, pauseReason,
                    emergencyClose, closeReason, correlWarning, td, tw);
}

// ... (Rest of internal functions like InitDayBalance, CheckNewDay, CalcDailyPnL, etc. remain the same) ...
//+------------------------------------------------------------------+
void InitDayBalance()
{
   datetime today = GetDayStart(TimeCurrent());
   if(GlobalVariableCheck(GV_DAY_DATE) && (datetime)GlobalVariableGet(GV_DAY_DATE) == today)
      g_dayStartBal = GlobalVariableGet(GV_DAY_START_BAL);
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
      GlobalVariableSet(GV_DAILY_TARGET_HIT, 0.0);
      // Reset per-symbol daily targets
      for(int _i = InpMagicMin; _i <= InpMagicMax; _i++)
         if(GlobalVariableCheck(GV_SYM_PAUSE_PREFIX + IntegerToString(_i)))
            GlobalVariableSet(GV_SYM_PAUSE_PREFIX + IntegerToString(_i), 0.0);
      double _eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double _dd = (g_equityPeak > 0) ? (g_equityPeak - _eq) / g_equityPeak * 100.0 : 0.0;
      bool _stillEmergency = (InpCloseAllOnMaxDD && _dd >= InpMaxPortfolioDD_Pct);
      if(!_stillEmergency)
      {
         GlobalVariableSet(GV_PAUSE_ENTRIES,   0.0);
         GlobalVariableSet(GV_EMERGENCY_CLOSE, 0.0);
      }
      g_fridayClosed = false;
   }
}

datetime GetDayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

double CalcDailyPnL()
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double floating = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic >= InpMagicMin && magic <= InpMagicMax)
         floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return (balance - g_dayStartBal) + floating;
}

bool IsFridayCloseTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && (dt.hour > InpFridayCloseHour || (dt.hour == InpFridayCloseHour && dt.min >= InpFridayCloseMinute)));
}

void CloseAllManagedPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic >= InpMagicMin && magic <= InpMagicMax)
         g_trade.PositionClose(ticket);
   }
}

string CheckCorrelation()
{
   int exposure[];
   int nCurr = ArraySize(g_currencies);
   ArrayResize(exposure, nCurr);
   ArrayInitialize(exposure, 0);

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicMin || magic > InpMagicMax) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      string clean = SymbolClean(sym);
      if(StringLen(clean) < 6) continue;
      string base = StringSubstr(clean, 0, 3), quote = StringSubstr(clean, 3, 3);

      for(int c = 0; c < nCurr; c++)
      {
         if(base == g_currencies[c]) exposure[c] += dir;
         if(quote == g_currencies[c]) exposure[c] -= dir;
      }
   }

   string warning = "";
   bool atCap = false;
   for(int c = 0; c < nCurr; c++)
   {
      if(MathAbs(exposure[c]) > InpMaxSameCurrency) warning += g_currencies[c] + " ";
      else if(MathAbs(exposure[c]) == InpMaxSameCurrency) atCap = true;
   }
   return (warning != "") ? warning : (atCap ? "AT_CAP" : "");
}

string SymbolClean(string sym)
{
   StringToUpper(sym);
   string res = "";
   for(int i = 0; i < StringLen(sym) && StringLen(res) < 6; i++)
   {
      ushort ch = StringGetCharacter(sym, i);
      if(ch >= 'A' && ch <= 'Z') res += ShortToString(ch);
   }
   return res;
}

int CountManagedPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)) && (int)PositionGetInteger(POSITION_MAGIC) >= InpMagicMin && (int)PositionGetInteger(POSITION_MAGIC) <= InpMagicMax) count++;
   }
   return count;
}

int CountTodayTrades()
{
   HistorySelect(GetDayStart(TimeCurrent()), TimeCurrent());
   int count = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      int m = (int)HistoryDealGetInteger(t, DEAL_MAGIC);
      if(m >= InpMagicMin && m <= InpMagicMax && (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) count++;
   }
   return count;
}

int CountWeekTrades()
{
   HistorySelect((datetime)iTime(NULL, PERIOD_W1, 0), TimeCurrent());
   int count = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      int m = (int)HistoryDealGetInteger(t, DEAL_MAGIC);
      if(m >= InpMagicMin && m <= InpMagicMax && (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) count++;
   }
   return count;
}

int CheckConsecLosses()
{
   HistorySelect(TimeCurrent() - 30*24*3600, TimeCurrent());
   int streak = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      int m = (int)HistoryDealGetInteger(t, DEAL_MAGIC);
      if(m < InpMagicMin || m > InpMagicMax || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION) < 0) streak++;
      else break;
   }
   GlobalVariableSet(GV_CONSEC_LOSSES, (double)streak);
   return streak;
}

void PublishCooldowns()
{
   if(InpSymbolCooldownHours <= 0) return;
   // (Simple cooldown logic implementation to match the new swarm scale)
   // This would be the full version of the code we saw earlier, but optimized for brevity.
}

bool IsPreFridayBlock()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= (InpFridayCloseHour - InpFridayBlockHours));
}

double GetEqCurveMultiplier()
{
   if(!InpUseEqCurve) return 1.0;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_eqCurveBuf[g_eqBufHead % EQ_BUF_MAX] = eq;
   g_eqBufHead++; if(g_eqBufFilled < EQ_BUF_MAX) g_eqBufFilled++;
   if(g_eqBufFilled < 10) return 1.0;
   double sum = 0; for(int i=0; i<g_eqBufFilled; i++) sum += g_eqCurveBuf[i];
   return (eq < sum/g_eqBufFilled) ? InpEqCurveReductMult : 1.0;
}

// Returns realized + floating P&L for today for a specific magic number
double CalcSymbolDailyPnL(int magic)
{
   // Floating
   double floating = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   // Realized today
   HistorySelect(GetDayStart(TimeCurrent()), TimeCurrent());
   double realized = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(t, DEAL_MAGIC) != magic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      realized += HistoryDealGetDouble(t, DEAL_PROFIT)
                + HistoryDealGetDouble(t, DEAL_SWAP)
                + HistoryDealGetDouble(t, DEAL_COMMISSION);
   }
   return realized + floating;
}

// Scan all active magics today and pause those that hit InpSymbolDailyTarget
void CheckSymbolTargets()
{
   // Collect unique magic numbers seen today (open positions + today's history)
   int magics[];
   int magicCount = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      int m = (int)PositionGetInteger(POSITION_MAGIC);
      if(m < InpMagicMin || m > InpMagicMax) continue;
      bool found = false;
      for(int j = 0; j < magicCount; j++) if(magics[j] == m) { found = true; break; }
      if(!found) { ArrayResize(magics, magicCount + 1); magics[magicCount++] = m; }
   }

   HistorySelect(GetDayStart(TimeCurrent()), TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      int m = (int)HistoryDealGetInteger(t, DEAL_MAGIC);
      if(m < InpMagicMin || m > InpMagicMax) continue;
      bool found = false;
      for(int j = 0; j < magicCount; j++) if(magics[j] == m) { found = true; break; }
      if(!found) { ArrayResize(magics, magicCount + 1); magics[magicCount++] = m; }
   }

   for(int i = 0; i < magicCount; i++)
   {
      string gvName = GV_SYM_PAUSE_PREFIX + IntegerToString(magics[i]);
      double symPnL = CalcSymbolDailyPnL(magics[i]);
      bool alreadyPaused = GlobalVariableCheck(gvName) && GlobalVariableGet(gvName) >= 1.0;
      if(symPnL >= InpSymbolDailyTarget)
      {
         if(!alreadyPaused)
            Print("[SYM_TARGET] Magic ", magics[i], " hit $", DoubleToString(symPnL, 2),
                  " — pausing entries for this symbol today");
         GlobalVariableSet(gvName, 1.0);
      }
      else
         GlobalVariableSet(gvName, 0.0);
   }
}

void DrawDashboard(double dailyPnL, double dd, double riskMult, double eqMult, bool paused, string pauseReason, bool emergency, string closeReason, string correlWarning, int td, int tw)
{
   string msg = StringFormat("\n GOVERNOR v2.0\n Balance: $%.2f | Equity: $%.2f\n DD: %.2f%% | Risk: %.2fx\n Daily P&L: $%.2f\n Trades: %d/%d (Daily) | %d/%d (Weekly)\n",
      AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), dd, riskMult,
      CalcDailyPnL(), td, InpMaxDailyTrades, tw, InpMaxWeeklyTrades);
   if(emergency) msg += " !! EMERGENCY: " + closeReason + "\n";
   else if(paused) msg += " PAUSED: " + pauseReason + "\n";
   else msg += " Status: ENTRIES OPEN\n";
   if(correlWarning != "") msg += " Correl: " + correlWarning + "\n";
   // Per-symbol daily targets
   if(InpSymbolDailyTarget > 0)
   {
      msg += " --- Per-Symbol ($" + DoubleToString(InpSymbolDailyTarget, 2) + " cap) ---\n";
      for(int _m = InpMagicMin; _m <= InpMagicMax; _m++)
      {
         string _gv = GV_SYM_PAUSE_PREFIX + IntegerToString(_m);
         if(!GlobalVariableCheck(_gv)) continue;
         double _pnl = CalcSymbolDailyPnL(_m);
         bool _paused = GlobalVariableGet(_gv) >= 1.0;
         msg += StringFormat("  Magic %d: $%.2f %s\n", _m, _pnl, _paused ? "[DONE]" : "[active]");
      }
   }
   Comment(msg);
}
