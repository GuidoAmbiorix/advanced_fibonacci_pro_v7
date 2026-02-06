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

#endif

//+------------------------------------------------------------------+
//| SYMBOL CONFIGURATION (Database-Driven)                            |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| SYMBOL CONFIGURATION (Full Database Mirror)                       |
//+------------------------------------------------------------------+
struct SymbolConfig
{
    // ======= IDENTITY =======
    string symbol;
    long   magicNumber;
    bool   enableMobileAlerts;

    // ======= DIRECTION =======
    int    direction;                 // 0=Both, 1=Buy, 2=Sell
    int    brokerUTCOffset;

    // ======= FIBONACCI =======
    int    swingLookback;
    double fibLevelLow;
    double fibLevelHigh;
    double zoneTolerance;

    // ======= DISPLACEMENT =======
    bool   useDisplacement;
    double displacementATR;
    int    displacementLookback;

    // ======= RSI =======
    int    rsiPeriod;
    int    rsiOversold;
    int    rsiOverbought;
    bool   rsiMomentum;

    // ======= TREND =======
    int    emaPeriod;
    bool   useTrendFilter;
    double emaMinSlope;

    // ======= CHOP FILTER =======
    bool   useChopFilter;
    double chopThreshold;
    int    atrMaPeriod;

    // ======= CONFLUENCE =======
    int    minConfluenceEntry;
    bool   enableAddOns;
    double addOn1_R;
    double addOn2_R;
    int    maxPositions;

    // ======= RISK =======
    double riskBase;
    double riskAddOn1;
    double riskAddOn2;
    double maxRisk;
    double maxLotsPerTrade;
    bool   enableMarginCheck;

    // ======= TAKE PROFIT =======
    int    tpMode;                    // 0=None, 1=Fixed, 2=Adaptive, 3=Hybrid
    double fixedTP_R;
    double minTP_R;
    double maxTP_R;
    bool   tpUseLearnedMFE;

    // ======= EXIT =======
    int    trailingMode;              // 0=Off, 1=Runner, 2=Full
    double partialTP_R;
    double partialClosePercent;
    double beThreshold_R;
    double trailStart_R;
    double trailATR_Mult;

    // ======= SPREAD =======
    int    maxSpreadPoints;

    // ======= SMC =======
    bool   useSMC;
    int    smcSwingLookback;
    double smcMinImpulseATR;
    double smcMinFVG_ATR;

    // ======= MULTI-TIMEFRAME =======
    bool   useMTF;
    ENUM_TIMEFRAMES htf;
    ENUM_TIMEFRAMES mtf;
    int    mtfEmaPeriod;

    // ======= NEWS FILTER =======
    bool   useNewsFilter;
    int    newsMinutesBefore;
    int    newsMinutesAfter;

    // ======= VOLATILITY =======
    bool   enableVolatilityFilter;
    double volatilityThreshold;
    int    volatilitySpikeCooldown;

    // ======= KELLY =======
    bool   useKelly;
    double kellyFraction;
    double dailyMaxDD;
    double weeklyMaxDD;

    // ======= LEARNING =======
    bool   enableLearning;
    bool   logTradesToFile;
    int    learningHistory;
    int    minTradesForLearning;

    // ======= ADAPTIVE =======
    bool   enableAdaptiveRisk;
    bool   enableAdaptiveExits;
    bool   enableAdaptiveFilters;

    // ======= PORTFOLIO PROTECTION =======
    bool   useCorrelationFilter;
    double dailyMaxLoss_R;
    int    lossCooldownMinutes;
    int    maxConsecutiveLosses;
    bool   useReversalFilter;
    int    reversalCooldownMinutes;

    // ======= KILLZONES =======
    bool   useKillzoneFilter;
    bool   enableAsianKZ;
    bool   enableLondonOpenKZ;
    bool   enableNYKZ;
    bool   enableLondonCloseKZ;

    // ======= SESSION GOVERNOR =======
    bool   useSessionGovernor;
    int    maxTradesPerSession;
    int    tradeCooldownMinutes;
    
    // Default Constructor
    SymbolConfig()
    {
       // Default Initialization (Matches Symbol_Engine defaults)
       symbol = "";
       magicNumber = 100001;
       enableMobileAlerts = true;
       
       direction = 0;
       brokerUTCOffset = 2;
       
       swingLookback = 20;
       fibLevelLow = 0.618;
       fibLevelHigh = 0.786;
       zoneTolerance = 0.25;
       
       useDisplacement = true;
       displacementATR = 1.2;
       displacementLookback = 5;
       
       rsiPeriod = 14;
       rsiOversold = 45;
       rsiOverbought = 55;
       rsiMomentum = true;
       
       emaPeriod = 200;
       useTrendFilter = true;
       emaMinSlope = 0.1;
       
       useChopFilter = true;
       chopThreshold = 0.75;
       atrMaPeriod = 20;
       
       minConfluenceEntry = 4;
       enableAddOns = true;
       addOn1_R = 1.5;
       addOn2_R = 2.5;
       maxPositions = 3;
       
       riskBase = 0.25;
       riskAddOn1 = 0.15;
       riskAddOn2 = 0.10;
       maxRisk = 0.75;
       maxLotsPerTrade = 0.5;
       enableMarginCheck = true;
       
       tpMode = 2;
       fixedTP_R = 3.0;
       minTP_R = 1.5;
       maxTP_R = 5.0;
       tpUseLearnedMFE = true;
       
       trailingMode = 1;
       partialTP_R = 1.5;
       partialClosePercent = 40.0;
       beThreshold_R = 1.8;
       trailStart_R = 2.0;
       trailATR_Mult = 1.2;
       
       maxSpreadPoints = 50;
       
       useSMC = true;
       smcSwingLookback = 20;
       smcMinImpulseATR = 2.0;
       smcMinFVG_ATR = 0.5;
       
       useMTF = true;
       htf = PERIOD_H4;
       mtf = PERIOD_H1;
       mtfEmaPeriod = 50;
       
       useNewsFilter = true;
       newsMinutesBefore = 30;
       newsMinutesAfter = 30;
       
       enableVolatilityFilter = true;
       volatilityThreshold = 3.0;
       volatilitySpikeCooldown = 15;
       
       useKelly = true;
       kellyFraction = 0.5;
       dailyMaxDD = 3.0;
       weeklyMaxDD = 6.0;
       
       enableLearning = true;
       logTradesToFile = true;
       learningHistory = 180;
       minTradesForLearning = 50;
       
       enableAdaptiveRisk = false;
       enableAdaptiveExits = false;
       enableAdaptiveFilters = false;
       
       useCorrelationFilter = true;
       dailyMaxLoss_R = 4.0;
       lossCooldownMinutes = 30;
       maxConsecutiveLosses = 2;
       useReversalFilter = true;
       reversalCooldownMinutes = 15;
       
       useKillzoneFilter = true;
       enableAsianKZ = false;
       enableLondonOpenKZ = true;
       enableNYKZ = true;
       enableLondonCloseKZ = false;
       
       useSessionGovernor = true;
       maxTradesPerSession = 3;
       tradeCooldownMinutes = 30;
    }
};
