//+------------------------------------------------------------------+
//|                                          PortfolioGlobals.mqh    |
//|          Shared definitions for Portfolio Manager System         |
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

#endif
