//+------------------------------------------------------------------+
//|                                          PortfolioGlobals.mqh    |
//|          Shared definitions for Portfolio Manager System         |
//|                 Enhanced with SMC and Advanced Filters            |
//+------------------------------------------------------------------+
#ifndef PORTFOLIO_GLOBALS_MQH
#define PORTFOLIO_GLOBALS_MQH

//+------------------------------------------------------------------+
//| GLOBAL VARIABLE KEYS (Communication Bus)                          |
//+------------------------------------------------------------------+
#define GV_GOVERNOR_ACTIVE       "PG_GovernorActive"       // 1 = running
#define GV_TOTAL_EXPOSURE        "PG_TotalExposure"        // % of equity at risk
#define GV_CURRENT_DD            "PG_CurrentDD"            // Current drawdown %
#define GV_PEAK_EQUITY           "PG_PeakEquity"           // Peak equity for DD calc
#define GV_ROLLING_PF            "PG_RollingPF"            // Last N trades PF
#define GV_RISK_MULTIPLIER       "PG_RiskMultiplier"       // Governor's risk scalar (0-1)
#define GV_TRADING_ENABLED       "PG_TradingEnabled"       // 1 = allowed, 0 = paused
#define GV_LAST_UPDATE           "PG_LastUpdate"           // Timestamp
#define GV_RANK_UPDATE           "PG_RankUpdate"           // Last ranking update timestamp

// RANKING SYSTEM (Dynamic Keys)
// Format: PG_Score_[Symbol] -> e.g. PG_Score_EURUSD = 28.5
// Format: PG_Rank_[Symbol]  -> e.g. PG_Rank_EURUSD = 1 (1st place)
#define GV_SCORE_PREFIX          "PG_Score_"
#define GV_REQ_PREFIX            "PG_Req_"
#define GV_DIR_PREFIX            "PG_Dir_"
#define GV_BAROPEN_PREFIX        "PG_Open_"        // Last Bar Open Time (datetime)
#define GV_PERIOD_PREFIX         "PG_Per_"         // Timeframe Period (seconds)
#define GV_KZ_PREFIX             "PG_KZ_"          // Killzone Status (1=Open, 0=Closed)
#define GV_RANK_PREFIX           "PG_Rank_"

// Correlation Group Risk Limits
#define GV_GROUP_USD_RISK        "PG_GroupUSD"
#define GV_GROUP_JPY_RISK        "PG_GroupJPY"
#define GV_GROUP_GBP_RISK        "PG_GroupGBP"
#define GV_GROUP_METALS_RISK     "PG_GroupMetals"
#define GV_GROUP_INDICES_RISK    "PG_GroupIndices"

// Daily/Weekly Limits
#define GV_DAILY_DD              "PG_DailyDD"              // Today's drawdown %
#define GV_WEEKLY_DD             "PG_WeeklyDD"             // This week's drawdown %
#define GV_DAILY_START_EQUITY    "PG_DailyStartEquity"     // Equity at day start
#define GV_WEEKLY_START_EQUITY   "PG_WeeklyStartEquity"    // Equity at week start
#define GV_DAILY_PROFIT          "PG_DailyProfit"          // Today's profit %
#define GV_DAILY_TARGET_HIT      "PG_DailyTargetHit"       // 1 = daily profit target reached today

// Consistency Rule (Prop Firm: Best Day <= X% of Total Profit)
#define GV_CONSISTENCY_BEST_DAY  "PG_ConsistencyBestDay"   // Best single-day profit ($)
#define GV_CONSISTENCY_TOTAL     "PG_ConsistencyTotal"      // Total accumulated positive profit ($)
#define GV_CONSISTENCY_RATIO     "PG_ConsistencyRatio"      // Best/Total ratio (0.0 – 1.0)
#define GV_CONSISTENCY_BLOCKED   "PG_ConsistencyBlocked"    // 1 = new trades blocked by consistency rule

// Session Status (Legacy - kept for backwards compatibility)
#define GV_CURRENT_SESSION       "PG_CurrentSession"       // Current trading session (legacy)
#define GV_SESSION_QUALITY       "PG_SessionQuality"       // Session quality rating (legacy)

// Killzone Status (New ICT-based system)
#define GV_CURRENT_KILLZONE      "PG_CurrentKillzone"       // Current killzone
#define GV_KILLZONE_QUALITY      "PG_KillzoneQuality"      // Killzone quality rating

// News Filter Status
#define GV_NEWS_BLOCKED          "PG_NewsBlocked"          // 1 = in news window
#define GV_NEWS_NEXT_TIME        "PG_NewsNextTime"         // Next news event time

// Market Regime
#define GV_MARKET_REGIME         "PG_MarketRegime"         // Current market regime

// Correlation Matrix
#define GV_CORR_EUR_GBP          "PG_CorrEURGBP"           // EUR/GBP correlation
#define GV_CORR_USD_JPY          "PG_CorrUSDJPY"           // USD/JPY correlation
#define GV_CORR_GOLD_USD         "PG_CorrGoldUSD"          // Gold/USD correlation

//+------------------------------------------------------------------+
//| CORRELATION GROUPS                                                |
//+------------------------------------------------------------------+
enum ENUM_CORR_GROUP
{
   GROUP_USD = 0,      // USD pairs
   GROUP_JPY = 1,      // JPY pairs
   GROUP_GBP = 2,      // GBP pairs
   GROUP_METALS = 3,   // Gold, Silver
   GROUP_INDICES = 4,  // NAS100, US30, etc.
   GROUP_OTHER = 5     // Uncategorized
};

//+------------------------------------------------------------------+
//| Get correlation group for a symbol                                |
//+------------------------------------------------------------------+
ENUM_CORR_GROUP GetCorrelationGroup(string symbol)
{
   string sym = symbol;
   StringToUpper(sym);
   
   // Metals
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0) return GROUP_METALS;
   if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0) return GROUP_METALS;
   
   // Indices
   if(StringFind(sym, "NAS") >= 0 || StringFind(sym, "US30") >= 0 || 
      StringFind(sym, "SP500") >= 0 || StringFind(sym, "DAX") >= 0 ||
      StringFind(sym, "USTEC") >= 0 || StringFind(sym, "US500") >= 0) return GROUP_INDICES;
   
   // Major currency groups (base or quote)
   if(StringFind(sym, "JPY") >= 0) return GROUP_JPY;
   if(StringFind(sym, "GBP") >= 0) return GROUP_GBP;
   if(StringFind(sym, "USD") >= 0) return GROUP_USD;
   
   return GROUP_OTHER;
}

//+------------------------------------------------------------------+
//| Get GV key for correlation group                                  |
//+------------------------------------------------------------------+
string GetGroupGVKey(ENUM_CORR_GROUP group)
{
   switch(group)
   {
      case GROUP_USD:     return GV_GROUP_USD_RISK;
      case GROUP_JPY:     return GV_GROUP_JPY_RISK;
      case GROUP_GBP:     return GV_GROUP_GBP_RISK;
      case GROUP_METALS:  return GV_GROUP_METALS_RISK;
      case GROUP_INDICES: return GV_GROUP_INDICES_RISK;
      default:            return "";
   }
}

//+------------------------------------------------------------------+
//| SEMANTIC CORRELATION LOGIC (Dynamic Draft)                        |
//+------------------------------------------------------------------+
#define CORR_FACTOR_HIGH         0.25  // 25% Penalty
#define CORR_FACTOR_MED          0.15  // 15% Penalty
#define CORR_FACTOR_LOW          0.05  // 5% Penalty

double GetSemanticCorrelation(string symA, string symB)
{
   ENUM_CORR_GROUP gA = GetCorrelationGroup(symA);
   ENUM_CORR_GROUP gB = GetCorrelationGroup(symB);
   
   if(gA == gB) return CORR_FACTOR_HIGH; // Same group = High Risk
   
   // Specific Inter-Group Rules
   if((gA == GROUP_USD && gB == GROUP_JPY)  || (gA == GROUP_JPY && gB == GROUP_USD)) return CORR_FACTOR_MED; // USDJPY vs Majors
   if((gA == GROUP_METALS && gB == GROUP_USD) || (gA == GROUP_USD && gB == GROUP_METALS)) return CORR_FACTOR_MED; // Gold vs USD
   if((gA == GROUP_METALS && gB == GROUP_JPY) || (gA == GROUP_JPY && gB == GROUP_METALS)) return CORR_FACTOR_MED; // Gold vs JPY
   
   // Crosses (Simple Logic for now, checking string)
   bool isCrossA = (gA == GROUP_OTHER && (StringFind(symA, "JPY")>0 || StringFind(symA, "GBP")>0));
   bool isCrossB = (gB == GROUP_OTHER && (StringFind(symB, "JPY")>0 || StringFind(symB, "GBP")>0));
   
   if(isCrossA || isCrossB) return CORR_FACTOR_MED;

   return CORR_FACTOR_LOW; // Default
}

//+------------------------------------------------------------------+
//| PERMISSION REQUEST STRUCTURE                                      |
//+------------------------------------------------------------------+
struct TradeRequest
{
   string symbol;
   double requestedRisk;    // % of equity
   bool   isAddOn;          // Entry vs Add-on
   ENUM_CORR_GROUP group;
};

//+------------------------------------------------------------------+
//| PERMISSION RESPONSE                                               |
//+------------------------------------------------------------------+
struct TradePermission
{
   bool   allowed;
   double approvedRisk;     // May be reduced
   string reason;           // If denied
};

//+------------------------------------------------------------------+
//| CHECK IF GOVERNOR IS ACTIVE                                       |
//+------------------------------------------------------------------+
bool IsGovernorActive()
{
   return GlobalVariableCheck(GV_GOVERNOR_ACTIVE) && 
          GlobalVariableGet(GV_GOVERNOR_ACTIVE) == 1;
}

//+------------------------------------------------------------------+
//| CHECK IF TRADING ENABLED                                          |
//+------------------------------------------------------------------+
bool IsTradingEnabled()
{
   if(!IsGovernorActive()) return true; // No governor = local control
   return GlobalVariableGet(GV_TRADING_ENABLED) == 1;
}

//+------------------------------------------------------------------+
//| GET RISK MULTIPLIER                                               |
//+------------------------------------------------------------------+
double GetRiskMultiplier()
{
   if(!IsGovernorActive()) return 1.0;
   double mult = GlobalVariableGet(GV_RISK_MULTIPLIER);
   return (mult > 0) ? mult : 1.0;
}

//+------------------------------------------------------------------+
//| GET CURRENT PORTFOLIO DD                                          |
//+------------------------------------------------------------------+
double GetPortfolioDD()
{
   if(!IsGovernorActive()) return 0;
   return GlobalVariableGet(GV_CURRENT_DD);
}

//+------------------------------------------------------------------+
//| GET TOTAL EXPOSURE                                                |
//+------------------------------------------------------------------+
double GetTotalExposure()
{
   if(!IsGovernorActive()) return 0;
   return GlobalVariableGet(GV_TOTAL_EXPOSURE);
}

//+------------------------------------------------------------------+
//| GET DAILY DRAWDOWN                                                |
//+------------------------------------------------------------------+
double GetDailyDD()
{
   if(!IsGovernorActive()) return 0;
   if(!GlobalVariableCheck(GV_DAILY_DD)) return 0;
   return GlobalVariableGet(GV_DAILY_DD);
}

//+------------------------------------------------------------------+
//| GET WEEKLY DRAWDOWN                                               |
//+------------------------------------------------------------------+
double GetWeeklyDD()
{
   if(!IsGovernorActive()) return 0;
   if(!GlobalVariableCheck(GV_WEEKLY_DD)) return 0;
   return GlobalVariableGet(GV_WEEKLY_DD);
}

//+------------------------------------------------------------------+
//| GET DAILY PROFIT %                                                |
//+------------------------------------------------------------------+
double GetDailyProfit()
{
   if(!IsGovernorActive()) return 0;
   if(!GlobalVariableCheck(GV_DAILY_PROFIT)) return 0;
   return GlobalVariableGet(GV_DAILY_PROFIT);
}

//+------------------------------------------------------------------+
//| CHECK IF DAILY PROFIT TARGET WAS HIT                             |
//+------------------------------------------------------------------+
bool IsDailyTargetHit()
{
   if(!IsGovernorActive()) return false;
   if(!GlobalVariableCheck(GV_DAILY_TARGET_HIT)) return false;
   return GlobalVariableGet(GV_DAILY_TARGET_HIT) == 1;
}

//+------------------------------------------------------------------+
//| CHECK IF IN NEWS WINDOW                                           |
//+------------------------------------------------------------------+
bool IsInNewsWindow()
{
   if(!GlobalVariableCheck(GV_NEWS_BLOCKED)) return false;
   return GlobalVariableGet(GV_NEWS_BLOCKED) == 1;
}

//+------------------------------------------------------------------+
//| GET CURRENT SESSION                                               |
//+------------------------------------------------------------------+
int GetCurrentSession()
{
   if(!GlobalVariableCheck(GV_CURRENT_SESSION)) return 0;
   return (int)GlobalVariableGet(GV_CURRENT_SESSION);
}

//+------------------------------------------------------------------+
//| GET SESSION QUALITY                                               |
//+------------------------------------------------------------------+
int GetSessionQuality()
{
   if(!GlobalVariableCheck(GV_SESSION_QUALITY)) return 0;
   return (int)GlobalVariableGet(GV_SESSION_QUALITY);
}

//+------------------------------------------------------------------+
//| GET CURRENT KILLZONE                                              |
//+------------------------------------------------------------------+
int GetCurrentKillzone()
{
   if(!GlobalVariableCheck(GV_CURRENT_KILLZONE)) return 0;
   return (int)GlobalVariableGet(GV_CURRENT_KILLZONE);
}

//+------------------------------------------------------------------+
//| GET KILLZONE QUALITY                                              |
//+------------------------------------------------------------------+
int GetKillzoneQuality()
{
   if(!GlobalVariableCheck(GV_KILLZONE_QUALITY)) return 0;
   return (int)GlobalVariableGet(GV_KILLZONE_QUALITY);
}

//+------------------------------------------------------------------+
//| CONFLUENCE SCORE THRESHOLDS                                       |
//+------------------------------------------------------------------+
#define CONFLUENCE_ELITE    14.0   // Elite entry: 14+/30 points (M15 Enhancement)
#define CONFLUENCE_STRONG   12.0   // Strong entry: 12-13.9/30 points
#define CONFLUENCE_GOOD     10.0   // Good entry: 10-11.9/30 points
#define CONFLUENCE_WEAK     0.0    // Weak entry: <10/30 points - NO TRADE

//+------------------------------------------------------------------+
//| ENTRY TIER ENUM (for new confluence system)                       |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_TIER
{
   TIER_NO_TRADE = 0,   // Score < 10: Skip
   TIER_GOOD = 1,       // Score 10-11.9: 60% position
   TIER_STRONG = 2,     // Score 12-13.9: 80% position
   TIER_ELITE = 3       // Score 14+: 100% position
};

//+------------------------------------------------------------------+
//| GET ENTRY TIER FROM CONFLUENCE SCORE                              |
//+------------------------------------------------------------------+
ENUM_ENTRY_TIER GetEntryTier(double confluenceScore)
{
   if(confluenceScore >= CONFLUENCE_ELITE) return TIER_ELITE;
   if(confluenceScore >= CONFLUENCE_STRONG) return TIER_STRONG;
   if(confluenceScore >= CONFLUENCE_GOOD) return TIER_GOOD;
   return TIER_NO_TRADE;
}

//+------------------------------------------------------------------+
//| GET POSITION SIZE MULTIPLIER FOR TIER                             |
//+------------------------------------------------------------------+
double GetTierSizeMultiplier(ENUM_ENTRY_TIER tier)
{
   switch(tier)
   {
      case TIER_ELITE:  return 1.0;    // 100%
      case TIER_STRONG: return 0.8;    // 80%
      case TIER_GOOD:   return 0.6;    // 60%
      default:          return 0.0;    // No trade
   }
}

//+------------------------------------------------------------------+
//| CORRELATION THRESHOLDS                                            |
//+------------------------------------------------------------------+
#define CORR_HIGH_POSITIVE    0.70    // High positive correlation
#define CORR_HIGH_NEGATIVE   -0.70    // High negative correlation
#define CORR_REDUCTION_FACTOR 0.50    // Size reduction for correlated pairs

//+------------------------------------------------------------------+
//| PAIR CORRELATION STRUCTURE                                        |
//+------------------------------------------------------------------+
struct PairCorrelation
{
   string pair1;
   string pair2;
   double correlation;
};

//+------------------------------------------------------------------+
//| KNOWN CORRELATIONS (Static reference)                             |
//+------------------------------------------------------------------+
// These are approximate average correlations for reference
// EURUSD/GBPUSD: +0.85 (high positive)
// EURUSD/USDCHF: -0.90 (high negative)
// XAUUSD/EURUSD: +0.60 (medium positive)
// USDJPY/XAUUSD: -0.70 (medium negative)
// AUDUSD/NZDUSD: +0.90 (high positive)

//+------------------------------------------------------------------+
//| ATOMIC OPERATIONS (FIX: Prevent race conditions)                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Atomic Add - Thread-safe addition to GlobalVariable               |
//+------------------------------------------------------------------+
bool AtomicAdd(string varName, double value, int maxRetries = 3)
{
   string lockName = varName + "_LOCK";

   for(int attempt = 0; attempt < maxRetries; attempt++)
   {
      // Try to acquire lock (using temp variable with 60-second expiry)
      // GlobalVariableTemp returns true when CREATED (lock acquired), false if already exists
      if(GlobalVariableTemp(lockName))
      {
         // Lock acquired, perform operation
         double currentValue = GlobalVariableGet(varName);
         double newValue = currentValue + value;
         GlobalVariableSet(varName, newValue);

         // Release lock
         GlobalVariableDel(lockName);
         return true;
      }

      // Lock failed, wait and retry
      Sleep(100);  // 100ms delay between retries
   }

   Print("ERROR: AtomicAdd failed after ", maxRetries, " attempts for ", varName);
   return false;
}

//+------------------------------------------------------------------+
//| Atomic Subtract - Thread-safe subtraction from GlobalVariable     |
//+------------------------------------------------------------------+
bool AtomicSubtract(string varName, double value, int maxRetries = 3)
{
   return AtomicAdd(varName, -value, maxRetries);
}

//+------------------------------------------------------------------+
//| Atomic Set with Validation - Thread-safe set with timestamp check |
//+------------------------------------------------------------------+
bool AtomicSetWithValidation(string varName, double value, datetime &lastUpdate)
{
   string lockName = varName + "_LOCK";

   // Try to acquire lock
   if(!GlobalVariableTemp(lockName))
   {
      // Check if another update happened while waiting
      datetime currentUpdate = (datetime)GlobalVariableGet(varName + "_TIMESTAMP");
      if(currentUpdate > lastUpdate)
      {
         // Stale update, abort
         GlobalVariableDel(lockName);
         return false;
      }

      // Perform update
      GlobalVariableSet(varName, value);
      GlobalVariableSet(varName + "_TIMESTAMP", (double)TimeCurrent());
      lastUpdate = TimeCurrent();

      // Release lock
      GlobalVariableDel(lockName);
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if GlobalVariable is locked                                 |
//+------------------------------------------------------------------+
bool IsGlobalVariableLocked(string varName)
{
   return GlobalVariableCheck(varName + "_LOCK");
}

#endif
