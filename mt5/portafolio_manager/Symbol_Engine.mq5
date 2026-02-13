//+------------------------------------------------------------------+
//|                                            Symbol_Engine.mq5     |
//|          Symbol Engine - Requests Permission from Governor       |
//|             Confluence Ladder + Portfolio Integration            |
//+------------------------------------------------------------------+
#property copyright "Symbol Engine - Portfolio Aware"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "2.00"
#property description "Symbol Engine: Thin Shell Architecture"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include "Include\PortfolioGlobals.mqh"
#include "Include\KillzoneConfig.mqh"
#include "Include\FailSafe.mqh"
#include "Include\MarketRegime.mqh"
#include "Include\KillSwitch.mqh"
#include "Include\Learning_MFE_MAE.mqh"
#include "Include\GovernorAllocator.mqh"

// Smart Money Concepts Modules
#include "Include\SMC_StructureBreak.mqh"
#include "Include\SMC_OrderBlocks.mqh"
#include "Include\SMC_FairValueGap.mqh"
#include "Include\SMC_LiquiditySweep.mqh"

// Multi-Timeframe and Filters
#include "Include\MTF_Confluence.mqh"
#include "Include\NewsFilter.mqh"
#include "Include\KellyPositionSizer.mqh"

// Learning & Memory Modules
#include "Include\DatabaseManager.mqh"
#include "Include\Memory\PatternMemory.mqh"
// ... (rest of includes)

// LEARNING & MEMORY OBJECTS
CDatabaseManager    dbManager;
CPatternMemory      patternMemory;
#include "Include\Learning\PerformanceAnalyzer.mqh"
#include "Include\Learning\PatternRecognizer.mqh"

// Adaptive Modules
#include "Include\Adaptive\AdaptiveRiskManager.mqh"
#include "Include\Adaptive\AdaptiveExitManager.mqh"
#include "Include\Adaptive\AdaptiveFilterManager.mqh"

// ADVANCED CONFLUENCE MODULES (M15 ENHANCED)
#include "Include\Advanced\VolumeAnalysis.mqh"
#include "Include\Advanced\Divergence.mqh"
#include "Include\Advanced\Inst_Concepts.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "======= IDENTITY ======="
input int               InpMagicNumber = 100001;          // Magic Number (unique per symbol)
input bool              InpEnableMobileAlerts = true;     // Enable Mobile Push Notifications

input group "======= DIRECTION ======="
input int               InpDirection = 0;                 // 0=Both, 1=Buy, 2=Sell
input int               InpBrokerUTCOffset = 2;           // Broker Offset from UTC (e.g. 2 for EET)

input group "======= FIBONACCI ======="
input int               InpSwingLookback = 20;
input double            InpFibLevelLow = 0.618;
input double            InpFibLevelHigh = 0.786;
input double            InpZoneTolerance = 0.25;

input group "======= DISPLACEMENT ======="
input bool              InpUseDisplacement = true;
input double            InpDisplacementATR = 1.2;
input int               InpDisplacementLookback = 5;

input group "======= RSI ======="
input int               InpRSI_Period = 14;
input int               InpRSI_Oversold = 45;
input int               InpRSI_Overbought = 55;
input bool              InpRSI_Momentum = true;

input group "======= TREND ======="
input int               InpEMA_Period = 200;
input bool              InpUseTrendFilter = true;
input double            InpEMA_MinSlope = 0.1;

input group "======= CHOP FILTER ======="
input bool              InpUseChopFilter = true;
input double            InpChopThreshold = 0.75;
input int               InpATR_MA_Period = 20;

input group "======= CONFLUENCE ======="
input int               InpMinConfluenceEntry = 4;
input bool              InpEnableAddOns = true;
input double            InpAddOn1_R = 1.5;
input double            InpAddOn2_R = 2.5;
input int               InpMaxPositions = 3;

input group "======= RISK (Before Governor Scaling) ======="
input double            InpRiskBase = 0.25;
input double            InpRiskAddOn1 = 0.15;
input double            InpRiskAddOn2 = 0.10;
input double            InpMaxRisk = 0.75;               // Maximum Risk % (Kelly Limit)
input double            InpMaxLotsPerTrade = 0.5;        // Max Lots Per Trade
input bool              InpEnableMarginCheck = true;     // Validate Margin Before Opening

input group "======= TAKE PROFIT ======="
input int               InpTPMode = 2;                    // 0=None, 1=Fixed, 2=Adaptive, 3=Hybrid
input double            InpFixedTP_R = 3.0;               // Fixed TP (R-multiple)
input double            InpMinTP_R = 1.5;                 // Minimum TP (R-multiple)
input double            InpMaxTP_R = 5.0;                 // Maximum TP (R-multiple)
input bool              InpTPUseLearnedMFE = true;        // Use Learned MFE for TP

input group "======= EXIT ======="
input int               InpTrailingMode = 1;              // 0=Off, 1=Runner, 2=Full
input double            InpPartialTP_R = 1.5;
input double            InpPartialClosePercent = 40.0;
input double            InpBE_Threshold_R = 1.8;
input double            InpTrailStart_R = 2.0;
input double            InpTrailATR_Mult = 1.2;

input group "======= SPREAD ======="
input int               InpMaxSpreadPoints = 50;

input group "======= SMC - SMART MONEY CONCEPTS ======="
input bool              InpUseSMC = true;                 // Enable SMC Analysis
input int               InpSMC_SwingLookback = 20;        // Swing Lookback Bars
input double            InpSMC_MinImpulseATR = 2.0;       // Min Impulse (ATR mult)
input double            InpSMC_MinFVG_ATR = 0.5;          // Min FVG Size (ATR mult)

input group "======= MULTI-TIMEFRAME ======="
input bool              InpUseMTF = true;                 // Enable MTF Analysis
input ENUM_TIMEFRAMES   InpHTF = PERIOD_H4;               // Higher Timeframe
input ENUM_TIMEFRAMES   InpMTF = PERIOD_H1;               // Medium Timeframe
input int               InpMTF_EMAPeriod = 50;            // MTF EMA Period

input group "======= NEWS FILTER ======="
input bool              InpUseNewsFilter = true;          // Enable News Filter
input int               InpNewsMinutesBefore = 30;        // Minutes Before News
input int               InpNewsMinutesAfter = 30;         // Minutes After News

input group "======= VOLATILITY SPIKE PROTECTION ======="
input bool              InpEnableVolatilityFilter = true; // Enable Flash Crash Detection
input double            InpVolatilityThreshold = 3.0;     // Volatility Spike Threshold (ATR multiplier)
input int               InpVolatilitySpikeCooldown = 15;  // Cooldown After Spike (minutes)

input group "======= KELLY POSITION SIZING ======="
input bool              InpUseKelly = true;               // Enable Kelly Sizing
input double            InpKellyFraction = 0.5;           // Kelly Fraction (0.5=Half Kelly)
input double            InpDailyMaxDD = 3.0;              // Daily Max Drawdown %
input double            InpWeeklyMaxDD = 6.0;             // Weekly Max Drawdown %

input group "======= PROFIT TARGETS (Universal) ======="
input double            InpDailyProfitTarget = 0.0;       // Daily Profit Target ($) - 0=Disabled
input double            InpTotalProfitTarget = 0.0;       // Total Profit Target ($) - 0=Disabled
input bool              InpUseDailyProfitLimit = false;   // Enable Daily Profit Limit
input bool              InpUseTotalProfitLimit = false;   // Enable Total Profit Limit
input bool              InpPauseOnProfitTarget = false;   // Pause Trading When Target Hit

input group "======= TRADING DAYS TRACKING (Universal) ======="
input int               InpMinTradingDays = 0;            // Min Trading Days (0=Disabled, Tracking Only)
input bool              InpEnforceTradingDays = false;    // Enforce Minimum (false=Warn Only)

input group "======= LEARNING & ADAPTATION ======="
input bool              InpEnableLearning = true;         // Enable Learning System
input bool              InpLogTradesToFile = true;        // Log Trades to CSV
input int               InpLearningHistory = 180;         // Days of History to Load
input int               InpMinTradesForLearning = 50;     // Min Trades Before Learning

input group "======= ADAPTIVE BEHAVIOR (Advanced) ======="
input bool              InpEnableAdaptiveRisk = false;    // Enable Adaptive Risk
input bool              InpEnableAdaptiveExits = false;   // Enable Adaptive Exits
input bool              InpEnableAdaptiveFilters = false; // Enable Adaptive Filters

input group "======= PORTFOLIO PROTECTION ======="
input bool              InpUseCorrelationFilter = true;   // Enable Correlation Protection
input double            InpDailyMaxLoss_R = 4.0;          // Daily Max Loss (R) - Circuit Breaker
input int               InpLossCooldownMinutes = 30;      // Cooldown After Loss (minutes)
input int               InpMaxConsecutiveLosses = 2;      // Max Consecutive Losses Rule
input bool              InpUseReversalFilter = true;      // Enable Reversal Trend Filter
input int               InpReversalCooldownMinutes = 15;  // Min Time Between Same-Direction Trades

input group "======= KILLZONES ======="
input bool              InpUseKillzoneFilter = true;      // Enable Killzone Filter
input bool              InpEnableAsianKZ = false;         // Enable Asian Killzone
input bool              InpEnableLondonOpenKZ = true;     // Enable London Open Killzone
input bool              InpEnableNYKZ = true;             // Enable NY Killzone
input bool              InpEnableLondonCloseKZ = false;   // Enable London Close Killzone

input group "======= SESSION GOVERNOR ======="
input bool              InpUseSessionGovernor = true;     // Enable Session Governor
input int               InpMaxTradesPerSession = 3;       // Max Trades Per Session
input int               InpTradeCooldownMinutes = 30;     // Cooldown Between Trades

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

// MODULE OBJECTS
CFailSafe         failSafe;
CMarketRegime     regime;
CKillSwitch       killSwitch;
CLearningEngine   learning;
CGovernorAllocator allocator;

// ADVANCED MODULE OBJECTS
CVolumeAnalysis   volumeAnalysis;
CDivergence       divergence;
CBreakerBlocks    breakerBlocks;
CMacroWindows     macroWindows;
CPowerOf3         powerOf3;
CWyckoff          wyckoff;

// Forward Declaration
double CalculateConfluenceScore(int direction);

// SMC MODULE OBJECTS
CSMCStructureBreak  smcStructure;
CSMCOrderBlocks     smcOrderBlocks;
CSMCFairValueGap    smcFVG;
CSMCLiquiditySweep  smcLiquidity;

// ADVANCED FILTER OBJECTS
CMTFConfluence      mtfAnalysis;
CNewsFilter         newsFilter;
CKellyPositionSizer kellySizer;

// LEARNING & MEMORY OBJECTS
// dbManager already declared above
// patternMemory declarated above
CPerformanceAnalyzer performanceAnalyzer;
CPatternRecognizer  patternRecognizer;

// ADAPTIVE OBJECTS
CAdaptiveRiskManager   adaptiveRisk;
CAdaptiveExitManager   adaptiveExit;
CAdaptiveFilterManager adaptiveFilter;

int hRSI, hATR, hEMA;
int hEMA50, hEMA100;   // Reversal filter EMAs
double g_RSI, g_RSI_Prev, g_ATR, g_EMA, g_EMA_Prev, g_ATR_MA;
double g_EMA50, g_EMA50_Prev, g_EMA100, g_EMA100_Prev;

datetime lastBarTime = 0;

int g_entryDirection = 0;
double g_currentConfluence = 0;
int g_positionCount = 0;
bool g_addOn1Triggered = false;
bool g_addOn2Triggered = false;
datetime g_lastCloseTime = 0;
ulong g_lastTickTime = 0;
datetime g_lastHeartbeat = 0;

int g_bias = 0;
datetime g_lastLossTime = 0;
MARKET_REGIME g_currentRegime = REGIME_UNKNOWN;

// Portfolio Protection Tracking
double g_dailyLossR = 0;
int    g_consecutiveLosses = 0;
datetime g_lastResetDate = 0;
datetime g_lastBuyTime = 0;    // Last BUY trade entry time
datetime g_lastSellTime = 0;   // Last SELL trade entry time

// Profit Target Tracking (Phase 6.1 - Universal Account Compliance)
double   g_dailyProfit = 0.0;        // Daily profit in dollars
double   g_totalProfit = 0.0;        // Total cumulative profit in dollars
datetime g_profitResetDate = 0;      // Last profit reset date

// Trading Days Tracking (Phase 6.2 - Universal Account Compliance)
int      g_tradingDaysCount = 0;     // Number of trading days
datetime g_lastTradeDate = 0;        // Last trade date (for day increment)

// OPTIMIZATION: Cache confluence scores to avoid recalculation
double g_cachedBuyScore = 0;
double g_cachedSellScore = 0;
datetime g_lastScoreCalcTime = 0;

// OPTIMIZATION: Performance monitoring
ulong g_tickCount = 0;
ulong g_barCount = 0;
ulong g_tradesExecuted = 0;

// Minimal state for position tracking (backup)
struct PositionState {
   ulong ticket;
   bool  partialClosed;
   double initialRisk;
   ENTRY_QUALITY quality;
};
PositionState g_states[];

//+------------------------------------------------------------------+
//| Init                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symbolInfo.Name(_Symbol)) return INIT_FAILED;
   symbolInfo.RefreshRates();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);

   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);

   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   hEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE)
      return INIT_FAILED;

   // Initialize reversal filter EMAs
   if(InpUseReversalFilter)
   {
      hEMA50 = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      hEMA100 = iMA(_Symbol, PERIOD_CURRENT, 100, 0, MODE_EMA, PRICE_CLOSE);

      if(hEMA50 == INVALID_HANDLE || hEMA100 == INVALID_HANDLE)
      {
         Print("ERROR: Reversal filter EMA handles invalid");
         return INIT_FAILED;
      }
   }

   failSafe.Init(InpMaxSpreadPoints);
   ArrayResize(g_states, 0);

   // OPTIMIZATION: Initialize Learning Engine with error checking
   if(InpEnableLearning)
   {
      if(!learning.Init(_Symbol, true))  // Enable persistence
      {
         Print("Warning: Learning engine initialization failed - continuing without learning");
      }
      else
      {
         Print("✓ Learning engine initialized with persistence");
      }
   }

   // Initialize SMC Modules
   if(InpUseSMC)
   {
      if(!smcStructure.Init(_Symbol, PERIOD_CURRENT, InpSMC_SwingLookback))
         Print("Warning: SMC Structure module init failed");

      if(!smcOrderBlocks.Init(_Symbol, PERIOD_CURRENT, 50, 5, InpSMC_MinImpulseATR))
         Print("Warning: SMC Order Blocks module init failed");

      if(!smcFVG.Init(_Symbol, PERIOD_CURRENT, 50, 10, InpSMC_MinFVG_ATR))
         Print("Warning: SMC FVG module init failed");

      if(!smcLiquidity.Init(_Symbol, PERIOD_CURRENT, InpSMC_SwingLookback))
         Print("Warning: SMC Liquidity module init failed");
   }

   // Initialize MTF Analysis
   if(InpUseMTF)
   {
      if(!mtfAnalysis.Init(_Symbol, InpHTF, InpMTF, PERIOD_CURRENT, InpMTF_EMAPeriod))
         Print("Warning: MTF Confluence module init failed");
   }

   // Initialize News Filter
   if(InpUseNewsFilter)
   {
      newsFilter.Init(_Symbol, InpNewsMinutesBefore, InpNewsMinutesAfter, true);

      // Configure Volatility Spike Detection
      newsFilter.EnableVolatilityFilter(InpEnableVolatilityFilter);
      newsFilter.SetVolatilityThreshold(InpVolatilityThreshold);
      newsFilter.SetVolatilityCooldown(InpVolatilitySpikeCooldown);
   }

   // Initialize Kelly Position Sizer
   if(InpUseKelly)
   {
      // Adjust maxRisk based on account size for safety
      double maxRiskAdjusted = InpMaxRisk;
      double equity = account.Equity();

      // Auto-adjust for small accounts to prevent margin issues
      if(equity < 10000)
      {
         maxRiskAdjusted = MathMin(InpMaxRisk, 0.5);   // Small accounts: max 0.5%
         Print("Small account ($", DoubleToString(equity, 2), ") - maxRisk limited to ", maxRiskAdjusted, "%");
      }
      else if(equity < 50000)
      {
         maxRiskAdjusted = MathMin(InpMaxRisk, 0.75);  // Medium accounts: max 0.75%
         Print("Medium account ($", DoubleToString(equity, 2), ") - maxRisk limited to ", maxRiskAdjusted, "%");
      }
      else
      {
         maxRiskAdjusted = InpMaxRisk;  // Large accounts: use input parameter
         Print("Large account ($", DoubleToString(equity, 2), ") - using maxRisk: ", maxRiskAdjusted, "%");
      }

      kellySizer.Init(InpRiskBase, 0.25, maxRiskAdjusted, InpKellyFraction, 30, InpDailyMaxDD, InpWeeklyMaxDD);
   }

   // Initialize Database Manager (replaces Trade Journal)
   if(InpEnableLearning && InpLogTradesToFile)
   {
      if(!dbManager.Init())
         Print("Warning: Database Manager initialization failed");
   }

   // Initialize Performance Analyzer
   if(InpEnableLearning)
   {
      if(!performanceAnalyzer.Init(_Symbol, &dbManager, InpMinTradesForLearning))
         Print("Warning: Performance Analyzer initialization failed");
   }

   // Initialize Pattern Memory & Recognizer
   if(InpEnableLearning)
   {
      if(!patternMemory.Init(_Symbol, true, 10))
         Print("Warning: Pattern Memory initialization failed");

      if(!patternRecognizer.Init(_Symbol, &patternMemory, 15, 0.65, 0.5))
         Print("Warning: Pattern Recognizer initialization failed");
   }

   // Initialize Adaptive Modules
   if(InpEnableLearning)
   {
      // Adaptive Risk Manager
      if(!adaptiveRisk.Init(_Symbol, &performanceAnalyzer, &patternRecognizer,
                            InpRiskBase, 0.1, 0.5, InpEnableAdaptiveRisk))
         Print("Warning: Adaptive Risk Manager initialization failed");

      // Adaptive Exit Manager
      ExitParameters exitParams;
      exitParams.trailStartR = InpTrailStart_R;
      exitParams.trailDistanceATR = InpTrailATR_Mult;
      exitParams.beThresholdR = InpBE_Threshold_R;
      exitParams.partialTPR = InpPartialTP_R;
      exitParams.partialPercent = InpPartialClosePercent;

      if(!adaptiveExit.Init(_Symbol, &learning, exitParams, InpEnableAdaptiveExits))
         Print("Warning: Adaptive Exit Manager initialization failed");

      // Adaptive Filter Manager
      if(!adaptiveFilter.Init(_Symbol, &patternRecognizer, &performanceAnalyzer,
                              InpMinConfluenceEntry, InpEnableAdaptiveFilters))
         Print("Warning: Adaptive Filter Manager initialization failed");
   }

   // OPTIMIZATION: Validate all critical modules initialized
   int initErrors = 0;
   if(hRSI == INVALID_HANDLE) { Print("ERROR: RSI handle invalid"); initErrors++; }
   if(hATR == INVALID_HANDLE) { Print("ERROR: ATR handle invalid"); initErrors++; }
   if(hEMA == INVALID_HANDLE) { Print("ERROR: EMA handle invalid"); initErrors++; }

   if(initErrors > 0)
   {
      Print("CRITICAL: ", initErrors, " indicator(s) failed to initialize");
      return INIT_FAILED;
   }

   // Check if Governor is running
   string govStatus = allocator.IsGovernorActive() ? "Connected" : "Standalone";

   Print("===========================================");
   Print("  ✅ SYMBOL ENGINE v2.0: ", _Symbol);
   Print("===========================================");
   Print("  Magic: ", InpMagicNumber);
   Print("  Governor: ", govStatus);
   Print("-------------------------------------------");
   Print("  CORE MODULES:");
   Print("    SMC Analysis: ", InpUseSMC ? "✓ ON" : "✗ OFF");
   Print("    MTF Confluence: ", InpUseMTF ? "✓ ON" : "✗ OFF");
   Print("    News Filter: ", InpUseNewsFilter ? "✓ ON" : "✗ OFF");
   if(InpUseNewsFilter && InpEnableVolatilityFilter)
      Print("      ⚡ Flash Crash Protection: ✓ ON (Threshold: ", InpVolatilityThreshold, "x)");
   Print("    Kelly Sizing: ", InpUseKelly ? "✓ ON" : "✗ OFF");
   Print("-------------------------------------------");
   Print("  PORTFOLIO PROTECTION:");
   Print("    Correlation Filter: ", InpUseCorrelationFilter ? "✓ ON" : "✗ OFF");
   Print("    Daily Circuit Breaker: ", InpDailyMaxLoss_R, "R");
   Print("    Loss Cooldown: ", InpLossCooldownMinutes, " minutes");
   Print("    Reversal Filter: ", InpUseReversalFilter ? "✓ ON (EMA50/100 momentum)" : "✗ OFF");
   Print("    Same-Direction Cooldown: ", InpReversalCooldownMinutes, " minutes");
   Print("-------------------------------------------");
   Print("  RISK PARAMETERS:");
   Print("    Base Risk: ", DoubleToString(InpRiskBase, 2), "%");
   Print("    Entry Threshold: 10.0/30 (GOOD - STRICT)");
   Print("    Add-Ons: DISABLED (Performance)");
   Print("-------------------------------------------");

   if(InpEnableLearning)
   {
      Print("  LEARNING SYSTEM:");
      Print("    Learning Engine: ✓ ACTIVE");
      if(InpLogTradesToFile)
         Print("    Trade Journal: ✓ ACTIVE (", InpLearningHistory, " days)");
      Print("    Performance Analyzer: ", performanceAnalyzer.GetTradeCount(), " trades loaded");
      Print("    Pattern Memory: ", patternMemory.GetPatternCount(), " patterns");
      Print("    Adaptive Risk: ", InpEnableAdaptiveRisk ? "✓ ON" : "✗ OFF");
      Print("    Adaptive Exits: ", InpEnableAdaptiveExits ? "✓ ON" : "✗ OFF");
      Print("    Adaptive Filters: ", InpEnableAdaptiveFilters ? "✓ ON" : "✗ OFF");
      Print("-------------------------------------------");
   }
   Print("===========================================");

   // Initialize indicators on startup
   Print("  Initializing indicators...");
   if(!UpdateIndicators())
   {
      Print("  WARNING: Initial indicator update failed - will retry on first bar");
   }
   else
   {
      Print("  ✓ Indicators initialized: RSI=", DoubleToString(g_RSI, 2), " ATR=", DoubleToString(g_ATR, 5), " EMA=", DoubleToString(g_EMA, 5));
   }
   Print("===========================================");

   // Phase 6.2: Load Trading Days Counter from GlobalVariable
   string gvTradingDays = "GV_TRADING_DAYS_" + _Symbol;
   if(GlobalVariableCheck(gvTradingDays))
   {
      g_tradingDaysCount = (int)GlobalVariableGet(gvTradingDays);
      Print("  📅 Trading Days: ", g_tradingDaysCount, " days loaded from history");
   }
   else
   {
      g_tradingDaysCount = 0;
      Print("  📅 Trading Days: Starting fresh (0 days)");
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hEMA50 != INVALID_HANDLE) IndicatorRelease(hEMA50);
   if(hEMA100 != INVALID_HANDLE) IndicatorRelease(hEMA100);

   // Cleanup SMC modules
   if(InpUseSMC)
   {
      smcStructure.Deinit();
      smcOrderBlocks.Deinit();
      smcFVG.Deinit();
      smcLiquidity.Deinit();
   }

   // Cleanup MTF
   if(InpUseMTF) mtfAnalysis.Deinit();

   // Save learning data before exit
   if(InpEnableLearning)
   {
      learning.Deinit();
      patternMemory.Deinit();
   }

   Comment("");
}

void ResetTradeState()
{
   g_entryDirection = 0;
   g_positionCount = 0;
   g_addOn1Triggered = false;
   g_addOn2Triggered = false;

   // OPTIMIZATION: Free memory properly
   if(ArraySize(g_states) > 0)
   {
      ArrayFree(g_states);
      ArrayResize(g_states, 0);
   }
}

bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

// ... (rest of OnTick logic)

//+------------------------------------------------------------------+
//| INSTITUTIONAL STRATEGY HELPERS                                    |
//+------------------------------------------------------------------+
double GetAdaptiveSL(double score)
{
   if(score >= 6.0) return g_ATR * 2.2; // Elite: Let it breathe
   if(score >= 5.0) return g_ATR * 1.8; // Strong
   return g_ATR * 1.2;                  // Good: Cut tight
}

double GetSymbolEdgeFactor()
{
   double winRate = killSwitch.GetWinRate();
   if(winRate > 0.6) return 1.2;
   if(winRate < 0.45) return 0.7;
   return 1.0;
}

//+------------------------------------------------------------------+
//| Reset daily loss tracking on new trading day                     |
//+------------------------------------------------------------------+
void ResetDailyLossIfNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(currentDate != g_lastResetDate)
   {
      if(g_lastResetDate > 0)
      {
         if(g_dailyLossR < 0)
         {
            Print("📊 Daily Reset: Previous day loss was ", DoubleToString(g_dailyLossR, 2), "R");
         }

         // Phase 6.1: Report daily profit if enabled
         if(InpUseDailyProfitLimit && InpDailyProfitTarget > 0)
         {
            Print("💰 Daily Profit Reset: Previous day profit was $", DoubleToString(g_dailyProfit, 2),
                  " / $", DoubleToString(InpDailyProfitTarget, 2), " target");
         }
      }

      g_dailyLossR = 0;
      g_consecutiveLosses = 0;
      g_lastResetDate = currentDate;

      // Phase 6.1: Reset daily profit counter
      g_dailyProfit = 0.0;
      g_profitResetDate = currentDate;
   }
}

//+------------------------------------------------------------------+
//| Check if symbol can trade (correlation protection)               |
//+------------------------------------------------------------------+
bool CanTradeSymbol(string symbol)
{
   if(!InpUseCorrelationFilter) return true;

   ENUM_CORR_GROUP myGroup = GetCorrelationGroup(symbol);

   // Check all open positions for correlated pairs
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i)) continue;

      long posMagic = position.Magic();

      // Only check positions from same EA family (100000-100099 magic range)
      if(posMagic >= 100000 && posMagic < 100100)
      {
         string posSymbol = position.Symbol();
         if(posSymbol == symbol) continue;  // Same symbol is OK

         ENUM_CORR_GROUP posGroup = GetCorrelationGroup(posSymbol);

         // Block if same correlation group (USD, GBP, JPY, METALS, INDICES)
         if(myGroup == posGroup && myGroup != GROUP_OTHER)
         {
            Print("🚫 CORRELATION: Cannot trade ", symbol, " (", EnumToString(myGroup),
                  ") - Already trading ", posSymbol, " (", EnumToString(posGroup), ")");
            return false;
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit Level                                      |
//+------------------------------------------------------------------+
double CalculateTakeProfit(double price, double slDist, int direction,
                          ENTRY_QUALITY quality, double atr)
{
   if(InpTPMode == 0) return 0;  // No TP

   double tpR = 0;

   // MODE 1: Fixed TP
   if(InpTPMode == 1)
   {
      tpR = InpFixedTP_R;
   }
   // MODE 2 & 3: Adaptive TP
   else if(InpTPMode == 2 || InpTPMode == 3)
   {
      // Check if should use fixed TP based on regime
      if(InpEnableAdaptiveExits && adaptiveExit.ShouldUseFixedTP(g_currentRegime, quality))
      {
         // Use AdaptiveExitManager's learned TP calculation
         tpR = adaptiveExit.CalculateFixedTP(g_currentRegime, quality, atr);
      }
      else if(InpTPUseLearnedMFE)
      {
         // Fallback: Use MFE-based calculation
         double avgMFE = learning.GetAvgMFE();
         if(avgMFE > 0 && atr > 0)
         {
            tpR = (avgMFE / atr) * 0.75;  // 75% of learned MFE
         }
         else
         {
            tpR = InpFixedTP_R;  // Fallback to fixed if no learning data
         }
      }
      else
      {
         tpR = InpFixedTP_R;  // No learning data available
      }

      // Quality adjustments
      if(quality == EQ_ELITE) tpR *= 1.2;
      else if(quality == EQ_STRONG) tpR *= 1.1;
      else if(quality == EQ_WEAK) tpR *= 0.8;

      // Regime adjustments
      if(g_currentRegime == REGIME_TREND) tpR *= 1.3;
      else if(g_currentRegime == REGIME_RANGE) tpR *= 0.85;
      else if(g_currentRegime == REGIME_VOLATILE) tpR *= 1.1;
   }

   // Clamp to min/max
   if(tpR < InpMinTP_R) tpR = InpMinTP_R;
   if(tpR > InpMaxTP_R) tpR = InpMaxTP_R;

   // Calculate TP price
   double tpDist = slDist * tpR;
   double tp = (direction == 1) ? price + tpDist : price - tpDist;

   // Ensure TP meets broker requirements
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(direction == 1 && (tp - price) < stopsLevel)
      tp = price + stopsLevel + 10 * _Point;
   else if(direction == -1 && (price - tp) < stopsLevel)
      tp = price - stopsLevel - 10 * _Point;

   return NormalizeDouble(tp, (int)symbolInfo.Digits());
}

//+------------------------------------------------------------------+
//| Main Tick                                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   // Heartbeat Logger (Every 60 Seconds)
   if(TimeCurrent() - g_lastHeartbeat >= 60)
   {
      LogHeartbeat();
      g_lastHeartbeat = TimeCurrent();
   }

   g_tickCount++;  // Performance monitoring

   symbolInfo.RefreshRates();

   g_positionCount = CountPositions();
   if(g_positionCount == 0) ResetTradeState();

   ManagePositions();

   // OPTIMIZATION: Update dashboard less frequently (every 5 seconds instead of every tick)
   static datetime lastDashboardUpdate = 0;
   if(TimeCurrent() - lastDashboardUpdate >= 5)
   {
      UpdateDashboard();
      lastDashboardUpdate = TimeCurrent();
   }

   if(!IsNewBar()) return;

   g_barCount++;  // Performance monitoring

   if(!UpdateIndicators()) return;

   // --- UPDATE ALL MODULES ON NEW BAR ---
   UpdateModules();

   // --- MODULE: MARKET REGIME ---
   g_currentRegime = regime.Detect(g_ATR, g_ATR_MA, g_EMA, g_EMA_Prev);
   // g_currentRegime check moved down to allow score calculation for visibility

   // OPTIMIZATION: Calculate confluence once per bar (expensive operation)
   // Moved here to ensure visibility in logs even if trading is blocked
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != g_lastScoreCalcTime)
   {
      g_cachedBuyScore = CalculateConfluenceScore(1);
      g_cachedSellScore = CalculateConfluenceScore(-1);
      g_lastScoreCalcTime = currentBarTime;
   }

   // --- MODULE: FAIL SAFE (Quick Exit) ---
   if(!failSafe.IsExecutionSafe()) return;

   // --- MODULE: KILL SWITCH (Quick Exit) ---
   if(!killSwitch.IsEnabled())
   {
      static datetime lastKillWarning = 0;
      if(TimeCurrent() - lastKillWarning > 300)
      {
         Print("⛔ Kill Switch DISABLED - Trading stopped");
         lastKillWarning = TimeCurrent();
      }
      return;
   }

   // --- MODULE: NEWS FILTER ---
   if(InpUseNewsFilter && !newsFilter.IsTradingAllowed()) return;


   // --- MODULE: KELLY POSITION SIZER (DD LIMITS) ---
   if(InpUseKelly && !kellySizer.IsTradingAllowed()) return;


   // --- PORTFOLIO PROTECTION: DAILY LOSS CIRCUIT BREAKER ---
   ResetDailyLossIfNewDay();
   if(InpDailyMaxLoss_R > 0 && g_dailyLossR <= -InpDailyMaxLoss_R)
   {
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning > 300)  // Print warning every 5 minutes
      {
         Print("⛔ DAILY LOSS LIMIT REACHED: ", DoubleToString(g_dailyLossR, 2), "R / ",
               DoubleToString(-InpDailyMaxLoss_R, 1), "R - Trading STOPPED for today");
         lastWarning = TimeCurrent();
      }
      return;
   }

   // --- PHASE 6.1: PROFIT TARGET TRACKING (Universal Account Compliance) ---
   if(InpUseDailyProfitLimit && InpDailyProfitTarget > 0 && g_dailyProfit >= InpDailyProfitTarget)
   {
      static datetime lastProfitWarning = 0;
      if(TimeCurrent() - lastProfitWarning > 300)  // Print warning every 5 minutes
      {
         Print("✅ DAILY PROFIT TARGET REACHED: $", DoubleToString(g_dailyProfit, 2),
               " / $", DoubleToString(InpDailyProfitTarget, 2));

         if(InpPauseOnProfitTarget)
         {
            Print("⏸️ Trading PAUSED for today (InpPauseOnProfitTarget=true)");
         }
         else
         {
            Print("⚠️ WARNING: Trading continues despite hitting target (InpPauseOnProfitTarget=false)");
         }

         lastProfitWarning = TimeCurrent();
      }

      if(InpPauseOnProfitTarget)
         return;  // Hard stop: No new trades today
   }

   if(InpUseTotalProfitLimit && InpTotalProfitTarget > 0 && g_totalProfit >= InpTotalProfitTarget)
   {
      static datetime lastTotalProfitWarning = 0;
      if(TimeCurrent() - lastTotalProfitWarning > 300)  // Print warning every 5 minutes
      {
         Print("🎯 TOTAL PROFIT TARGET REACHED: $", DoubleToString(g_totalProfit, 2),
               " / $", DoubleToString(InpTotalProfitTarget, 2));

         if(InpPauseOnProfitTarget)
         {
            Print("⏸️ Trading PAUSED permanently (InpPauseOnProfitTarget=true)");
         }
         else
         {
            Print("⚠️ WARNING: Trading continues despite hitting total target (InpPauseOnProfitTarget=false)");
         }

         lastTotalProfitWarning = TimeCurrent();
      }

      if(InpPauseOnProfitTarget)
         return;  // Hard stop: Account target achieved
   }

   // --- PORTFOLIO PROTECTION: CORRELATION FILTER ---
   if(InpUseCorrelationFilter && !CanTradeSymbol(_Symbol))
   {
      static datetime lastCorrWarning = 0;
      if(TimeCurrent() - lastCorrWarning > 300)
      {
         Print("⚠️ CORRELATION BLOCK: Cannot trade ", _Symbol, " - Correlated pair already active");
         lastCorrWarning = TimeCurrent();
      }
      return;
   }

   // --- PORTFOLIO PROTECTION: LOSS COOLDOWN ---
   if(InpLossCooldownMinutes > 0 && g_lastLossTime > 0)
   {
      int secondsSinceLoss = (int)(TimeCurrent() - g_lastLossTime);
      if(secondsSinceLoss < InpLossCooldownMinutes * 60)
      {
         // Still in cooldown - don't trade
         return;
      }
   }

   // --- PORTFOLIO PROTECTION: CONSECUTIVE LOSS LIMIT ---
   if(InpMaxConsecutiveLosses > 0 && g_consecutiveLosses >= InpMaxConsecutiveLosses)
   {
      static datetime lastStreakWarning = 0;
      if(TimeCurrent() - lastStreakWarning > 300)
      {
         Print("⛔ MAX LOSS STREAK: ", g_consecutiveLosses, " consecutive losses - Trading STOPPED for today (or until manual reset)");
         lastStreakWarning = TimeCurrent();
      }
      return;
   }



   // === TRADING FILTERS START HERE ===
   
   if(g_currentRegime == REGIME_CHAOS) return;

   // PRE-ENTRY FILTERS (Quick Exits for Performance)
   if(!CheckSpread()) return;

   // OPTIMIZATION: RSI Compression Filter (avoid choppy middle zone)
   if(g_RSI > 48 && g_RSI < 52)
   {
      static datetime lastRSIWarning = 0;
      if(TimeCurrent() - lastRSIWarning > 300)
      {
         Print("⏸️ RSI in dead zone: ", DoubleToString(g_RSI, 1), " (48-52) - waiting for momentum");
         lastRSIWarning = TimeCurrent();
      }
      return;
   }

   // OPTIMIZATION: EMA Proximity Filter (avoid chop near EMA)
   double emaDistance = MathAbs(symbolInfo.Bid() - g_EMA);
   double minDistance = g_ATR * 0.35;
   if(emaDistance < minDistance)
   {
      static datetime lastEMAWarning = 0;
      if(TimeCurrent() - lastEMAWarning > 300)
      {
         Print("⏸️ Too close to EMA 200: ", DoubleToString(emaDistance / _Point, 0),
               " pips (min: ", DoubleToString(minDistance / _Point, 0), " pips)");
         lastEMAWarning = TimeCurrent();
      }
      return;
   }

   // Check Governor Trading Permission
   if(!IsTradingEnabled()) return;

   double buyScore = g_cachedBuyScore;
   double sellScore = g_cachedSellScore;

   // Apply adaptive filter (pattern bonus/penalty)
   if(InpEnableLearning && InpEnableAdaptiveFilters && performanceAnalyzer.IsLearningActive())
   {
      ConfluenceFactors buyFactors;
      BuildConfluenceFactors(buyFactors, 1, buyScore);
      double buyBonus = adaptiveFilter.GetAdjustedConfluence(buyScore, buyFactors) - buyScore;
      buyScore += buyBonus;

      ConfluenceFactors sellFactors;
      BuildConfluenceFactors(sellFactors, -1, sellScore);
      double sellBonus = adaptiveFilter.GetAdjustedConfluence(sellScore, sellFactors) - sellScore;
      sellScore += sellBonus;
   }

   // Bias Penalty
   if(g_bias == 1) sellScore -= 1.0;
   if(g_bias == -1) buyScore -= 1.0;

   // MTF Bias Penalty (if trading against HTF)
   if(InpUseMTF)
   {
      if(!mtfAnalysis.IsDirectionAligned(1) && mtfAnalysis.GetBias() != BIAS_NEUTRAL)
         buyScore -= 1.5;
      if(!mtfAnalysis.IsDirectionAligned(-1) && mtfAnalysis.GetBias() != BIAS_NEUTRAL)
         sellScore -= 1.5;
   }

   // ENTRY
   if(g_positionCount == 0)
   {
      // --- SESSION GOVERNOR ---
      if(InpUseSessionGovernor)
      {
          // Cooldown Check
          datetime lastTrade = (g_lastBuyTime > g_lastSellTime) ? g_lastBuyTime : g_lastSellTime;
          if(TimeCurrent() - lastTrade < InpTradeCooldownMinutes * 60) return;
          
          // Max Trades Check (Simple Session Reset logic required or daily limit)
          // For now, using simple daily limit as proxy or relying on Allocator
      }

      // --- KILLZONES ---
      if(InpUseKillzoneFilter)
      {
          if(!CheckKillzone()) return;
      }

      double bestScore = (buyScore > sellScore) ? buyScore : sellScore;
      int bestDirection = (buyScore > sellScore) ? 1 : -1;

      // Get Entry Tier from new confluence system
      ENUM_ENTRY_TIER tier = GetEntryTier(bestScore);
      if(tier == TIER_NO_TRADE) return;  // Score < 5 = no trade

      // Calculate Quality using Learning Module Logic
      ENTRY_QUALITY quality = learning.CalculateQuality(bestScore);
      if(quality == EQ_WEAK) return;

      // Calculate base risk
      double baseRisk = InpRiskBase;

      // Apply Kelly sizing if enabled
      if(InpUseKelly)
      {
         baseRisk = kellySizer.GetRiskForQuality(quality);

         // Apply additional multipliers
         double newsMultiplier = InpUseNewsFilter ? newsFilter.GetNewsRiskMultiplier() : 1.0;
         double killzoneMultiplier = 1.0;
         double regimeMultiplier = (g_currentRegime == REGIME_TREND) ? 1.0 : 0.8;

         baseRisk = kellySizer.GetAdjustedRisk(quality, newsMultiplier, killzoneMultiplier, regimeMultiplier);
      }

      // Apply tier multiplier
      baseRisk *= GetTierSizeMultiplier(tier);

      // Apply adaptive risk (if enabled and learning active)
      if(InpEnableLearning && InpEnableAdaptiveRisk && adaptiveRisk.IsAdaptationEnabled())
      {
         ENUM_KILLZONE currentKZ = KILLZONE_NONE;
         ConfluenceFactors factors;
         BuildConfluenceFactors(factors, bestDirection, bestScore);

         // Check if should skip trade based on poor context
         if(adaptiveRisk.ShouldSkipTrade(currentKZ, g_currentRegime))
         {
            Print("Adaptive Risk: Trade skipped due to poor context performance");
            return;  // Exit OnTick without trading
         }

         // Calculate adaptive risk
         baseRisk = adaptiveRisk.CalculateAdaptiveRisk(currentKZ, g_currentRegime, factors, quality);
      }


      // GOVERNOR REQUEST
      GovernorRequest req = allocator.BuildRequest(
          _Symbol,
          baseRisk,
          killSwitch.GetWinRate(),
          killSwitch.GetRollingR(),
          (int)g_currentRegime
      );

      double approvedRisk = allocator.RequestRisk(req);

      if(approvedRisk > 0.05)
      {
          // STRICTER ENTRY THRESHOLD: M15 ENHANCED SYSTEM
          // ELITE >= 14.0, STRONG >= 12.0, GOOD >= 10.0
          // Minimum entry is GOOD (10.0), but with institutional footprint check for scores < 16.0
          double minEntry = InpMinConfluenceEntry;  // User defined threshold

          if(buyScore >= minEntry && (InpDirection == 0 || InpDirection == 1))
          {
             // --- PORTFOLIO PROTECTION: SAME-DIRECTION COOLDOWN ---
             if(InpReversalCooldownMinutes > 0 && g_lastBuyTime > 0)
             {
                int secondsSince = (int)(TimeCurrent() - g_lastBuyTime);
                int requiredCooldown = InpReversalCooldownMinutes * 60;

                if(secondsSince < requiredCooldown)
                {
                   static datetime lastCooldownWarning = 0;
                   if(TimeCurrent() - lastCooldownWarning > 60)
                   {
                      int remainingSec = requiredCooldown - secondsSince;
                      Print("⏸️ SAME-DIRECTION COOLDOWN: BUY blocked - ",
                            IntegerToString(remainingSec / 60), "m ", IntegerToString(remainingSec % 60), "s remaining");
                      lastCooldownWarning = TimeCurrent();
                   }
                   return;  // Skip this trade
                }
             }

             g_currentConfluence = buyScore;
             g_entryDirection = 1;
             ExecuteTrade(ORDER_TYPE_BUY, approvedRisk, "Entry", quality);
          }
          else if(sellScore >= minEntry && (InpDirection == 0 || InpDirection == 2))
          {
             // --- PORTFOLIO PROTECTION: SAME-DIRECTION COOLDOWN ---
             if(InpReversalCooldownMinutes > 0 && g_lastSellTime > 0)
             {
                int secondsSince = (int)(TimeCurrent() - g_lastSellTime);
                int requiredCooldown = InpReversalCooldownMinutes * 60;

                if(secondsSince < requiredCooldown)
                {
                   static datetime lastCooldownWarning = 0;
                   if(TimeCurrent() - lastCooldownWarning > 60)
                   {
                      int remainingSec = requiredCooldown - secondsSince;
                      Print("⏸️ SAME-DIRECTION COOLDOWN: SELL blocked - ",
                            IntegerToString(remainingSec / 60), "m ", IntegerToString(remainingSec % 60), "s remaining");
                      lastCooldownWarning = TimeCurrent();
                   }
                   return;  // Skip this trade
                }
             }

             g_currentConfluence = sellScore;
             g_entryDirection = -1;
             ExecuteTrade(ORDER_TYPE_SELL, approvedRisk, "Entry", quality);
          }
      }
   }

   // OPTIMIZATION: Add-ons disabled in all .set files - skip processing
   // Uncomment if you re-enable add-ons:
   /*
   else if(g_positionCount > 0 && InpEnableAddOns && g_positionCount < InpMaxPositions)
   {
      CheckAddOnOpportunity();
   }
   */
}

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE type, double riskPct, string label, ENTRY_QUALITY quality)
{
   double price = (type == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();

   // Adaptive SL
   double slDist = (quality == EQ_ELITE) ? g_ATR * 2.2 : (quality == EQ_STRONG ? g_ATR * 1.8 : g_ATR * 1.2);

   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDist < stopsLevel + 10 * _Point) slDist = stopsLevel + 10 * _Point;

   double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   sl = NormalizeDouble(sl, (int)symbolInfo.Digits());
   double lots = CalculateLotSize(slDist, riskPct);

   string comment = "SE|" + label + "|Q" + IntegerToString((int)quality);

   // Calculate TP
   int dir = (type == ORDER_TYPE_BUY) ? 1 : -1;
   double tp = CalculateTakeProfit(price, slDist, dir, quality, g_ATR);

   // Validate margin availability BEFORE opening position
   if(!CheckMarginRequirement(_Symbol, type, lots))
   {
      Print("TRADE REJECTED: Insufficient margin for ", DoubleToString(lots, 2), " lots of ", _Symbol);
      Print("  Risk%: ", DoubleToString(riskPct, 3), " | Quality: ", EnumToString(quality));
      failSafe.ReportFailure();
      return false;
   }

   // Open position with TP
   if(trade.PositionOpen(_Symbol, type, lots, price, sl, tp, comment))
   {
      ulong ticket = trade.ResultOrder();
      if(ticket == 0) if(PositionSelect(_Symbol)) ticket = PositionGetInteger(POSITION_TICKET);

      // REGISTER STATE WITH LEARNING MODULE
      learning.RegisterTrade(ticket, slDist, quality);

      // Store in local backup state
      int sz = ArraySize(g_states);
      ArrayResize(g_states, sz + 1);
      g_states[sz].ticket = ticket;
      g_states[sz].partialClosed = false;
      g_states[sz].initialRisk = slDist;
      g_states[sz].quality = quality;

      // LOG TO DB MANAGER
      if(InpEnableLearning && InpLogTradesToFile)
      {
         string killzoneStr = "DISABLED";
         string strategyStr = "STANDARD"; // or derive from add-ons
         
         dbManager.LogTradeEntry(
            ticket, 
            _Symbol, 
            (type == ORDER_TYPE_BUY) ? 1 : -1, 
            lots, 
            price, 
            sl, 
            tp, 
            g_currentConfluence, 
            strategyStr, 
            IntegerToString((int)g_currentRegime), 
            killzoneStr
         );
      }


      // OPTIMIZATION: Enhanced logging with all key metrics
      string tpInfo = (tp > 0) ?
         " TP:" + DoubleToString(tp, (int)symbolInfo.Digits()) +
         " (" + DoubleToString((MathAbs(tp - price) / slDist), 2) + "R)" :
         " No TP";

      Print("===========================================");
      Print("✅ TRADE OPENED");
      Print("  Ticket: #", ticket);
      Print("  Type: ", EnumToString(type));
      Print("  Price: ", DoubleToString(price, (int)symbolInfo.Digits()));
      Print("  SL: ", DoubleToString(sl, (int)symbolInfo.Digits()), " (", DoubleToString(slDist / _Point, 0), " pips)");
      Print("  ", tpInfo);
      Print("  Lots: ", DoubleToString(lots, 2));
      Print("  Risk: ", DoubleToString(riskPct, 2), "%");
      Print("  Quality: ", EnumToString(quality));
      Print("  Confluence: ", DoubleToString(g_currentConfluence, 1), "/30");
      Print("===========================================");

      // Track last trade time per direction (for cooldown)
      if(type == ORDER_TYPE_BUY)
         g_lastBuyTime = TimeCurrent();
      else
         g_lastSellTime = TimeCurrent();

      g_tradesExecuted++;  // Performance monitoring
 
       // SEND MOBILE NOTIFICATION
       if(InpEnableMobileAlerts)
       {
          string notifyText = "🚀 TRADE OPENED: " + _Symbol + "\n" +
                              EnumToString(type) + " " + DoubleToString(lots, 2) + " Lots\n" +
                              "Price: " + DoubleToString(price, (int)symbolInfo.Digits()) + "\n" +
                              "Score: " + DoubleToString(g_currentConfluence, 1) + "/30";
          SendNotification(notifyText);
       }

      return true;
   }

   failSafe.ReportFailure();
   return false;
}

//+------------------------------------------------------------------+
//| Manage Positions                                                  |
//+------------------------------------------------------------------+
void ManagePositions()
{
   // 1. Cleanup Closed Positions & Update Stats
   for(int i=ArraySize(g_states)-1; i>=0; i--)
   {
      ulong ticket = g_states[i].ticket;
      if(!PositionSelectByTicket(ticket))
      {
         // Update Modules
         double profitMoney = 0;

         if(HistorySelectByPosition(ticket))
         {
             int deals = HistoryDealsTotal();
             for(int d=0; d<deals; d++) profitMoney += HistoryDealGetDouble(HistoryDealGetTicket(d), DEAL_PROFIT);

             // Get trade details for logging
             double risk = g_states[i].initialRisk;
             double profitR = (risk > 0) ? profitMoney / (account.Equity() * (g_states[i].initialRisk / 100.0)) : 0;

             // Get MFE/MAE from learning engine
             double mfe = 0, mae = 0;
             learning.GetMFEMAE(ticket, mfe, mae);

             // LOG EXIT TO DB MANAGER
             if(InpEnableLearning && InpLogTradesToFile)
             {
                string exitReason = (profitMoney > 0) ? "TP" : "SL";
                if(g_states[i].partialClosed) exitReason += "_PARTIAL";
                
                dbManager.LogTradeExit(
                   ticket, 
                   0, // Exit price (can retrieve from history if critical) 
                   profitMoney, 
                   0, // Commission (get from history)
                   0, // Swap (get from history)
                   exitReason, 
                   mfe, 
                   mae
                );

                // Reconstruct Context for Pattern Database (Legacy Support)
                ExitContext exitCtx;
                exitCtx.exitTime = TimeCurrent();
                exitCtx.exitType = exitReason;
                exitCtx.profitR = profitR;
                // ... (rest used below)

                // Update Pattern Database
                // Note: We reconstruct a simplified ConfluenceFactors from available data
                // Future enhancement: Store full factors at entry time
                ConfluenceFactors factors;
                factors.killzone = exitCtx.exitType == "TP" ? KILLZONE_LONDON_OPEN : KILLZONE_NONE;  // Placeholder
                factors.regime = g_currentRegime;
                factors.confluenceScore = g_currentConfluence;
                // Individual factors would need to be captured at entry for full accuracy
                // For now, we estimate based on score
                factors.trendAligned = (g_currentConfluence >= 1.0);
                factors.structureBreak = (g_currentConfluence >= 2.0);
                factors.fibZone = (g_currentConfluence >= 3.0);
                factors.rsiMomentum = (g_currentConfluence >= 4.0);
                factors.orderBlock = (g_currentConfluence >= 5.0);
                factors.fvg = (g_currentConfluence >= 6.0);
                factors.liquiditySweep = (g_currentConfluence >= 7.0);
                factors.killzoneActive = false;
                factors.mtfAligned = (g_currentConfluence >= 8.0);

                patternRecognizer.UpdatePatternDatabase(factors, profitR);
             }

             // Commit to Learning Engine
             learning.OnTradeClosed(ticket);

             // Commit to KillSwitch
             double rOutcome = (profitMoney > 0) ? 1.0 : -1.0;
             if(profitMoney < 0 && MathAbs(profitMoney) > account.Balance()*0.02) rOutcome = -2.0;

             killSwitch.OnTradeClosed(rOutcome);


             // Track Daily Loss for Circuit Breaker
             g_dailyLossR += profitR;
             if(profitMoney < 0)
             {
                g_lastLossTime = TimeCurrent();  // Track last loss time for cooldown
                g_consecutiveLosses++;           // REVENGE TRADING PROTECTION
                Print("📉 Loss recorded: ", DoubleToString(profitR, 2), "R | Daily total: ",
                      DoubleToString(g_dailyLossR, 2), "R | Streak: ", g_consecutiveLosses);
             }
             else
             {
                if(g_consecutiveLosses > 0) Print("✅ Win breaks losing streak of ", g_consecutiveLosses);
                g_consecutiveLosses = 0;         // Reset on win
             }
         }

         g_lastCloseTime = TimeCurrent();
         for(int j=i; j<ArraySize(g_states)-1; j++) g_states[j] = g_states[j+1];
         ArrayResize(g_states, ArraySize(g_states)-1);
      }
   }

   // 2. Manage Open Positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol || position.Magic() != InpMagicNumber) continue;

      ulong ticket = position.Ticket();
      double open = position.PriceOpen();
      double curr = position.PriceCurrent();
      double sl = position.StopLoss();
      double tp = position.TakeProfit();
      double vol = position.Volume();
      long pType = position.PositionType();

      // Update Learning Stats (MFE/MAE)
      learning.UpdateTrade(ticket, open, curr, (int)pType);

      // OPTIMIZATION: Get/Create State with early exit
      int sIdx = -1;
      int stateCount = ArraySize(g_states);

      for(int s = 0; s < stateCount; s++)
      {
         if(g_states[s].ticket == ticket)
         {
            sIdx = s;
            break;
         }
      }

      // Create new state if not found
      if(sIdx == -1)
      {
         ArrayResize(g_states, stateCount + 1);
         g_states[stateCount].ticket = ticket;
         g_states[stateCount].partialClosed = false;
         g_states[stateCount].initialRisk = MathAbs(open - sl);
         if(g_states[stateCount].initialRisk == 0) g_states[stateCount].initialRisk = _Point * 100;
         g_states[stateCount].quality = EQ_GOOD;
         sIdx = stateCount;
      }

      double risk = g_states[sIdx].initialRisk;
      if(risk <= 0) risk = _Point * 100;

      double rawProfit = (pType == POSITION_TYPE_BUY) ? (curr - open) : (open - curr);
      double profitR = rawProfit / risk;

      ENTRY_QUALITY quality = g_states[sIdx].quality;

      // --- REGIME-AWARE PARAMETERS (with Adaptive Exits if enabled) ---
      double partTP = InpPartialTP_R;
      double trailStart = InpTrailStart_R;
      double beTrigger = InpBE_Threshold_R;
      double partialPercent = InpPartialClosePercent;

      // Use Adaptive Exit Manager if enabled
      if(InpEnableLearning && InpEnableAdaptiveExits && adaptiveExit.IsAdaptationEnabled())
      {
         ExitParameters adaptiveParams = adaptiveExit.GetAdaptiveParameters(g_currentRegime, quality, g_ATR, risk);
         trailStart = adaptiveParams.trailStartR;
         beTrigger = adaptiveParams.beThresholdR;
         partTP = adaptiveParams.partialTPR;
         partialPercent = adaptiveParams.partialPercent;
      }
      else
      {
         // Default regime adjustments
         if(g_currentRegime == REGIME_TREND) {
             partTP *= 1.2;
             trailStart *= 1.2;
         } else if(g_currentRegime == REGIME_RANGE) {
             partTP *= 0.8;
             trailStart *= 0.8;
         }

         if(quality == EQ_WEAK) { partTP *= 0.8; trailStart *= 0.7; }
         if(quality == EQ_ELITE) { partTP *= 1.5; trailStart *= 1.5; }
      }

      // Skip trailing if Mode 2 (Adaptive only) and TP is set
      if(InpTPMode == 2 && tp > 0 && InpTrailingMode == 0)
      {
         continue;  // Let TP handle exit
      }

      // Mode 3 (Hybrid): Allow trailing even with TP set
      // Mode 1 (Fixed): Respect InpTrailingMode setting
      if(InpTrailingMode >= 1)
      {
         // 1. Partial TP (using adaptive parameters)
         if(!g_states[sIdx].partialClosed && profitR >= partTP)
         {
            double closeVol = NormalizeDouble(vol * (partialPercent / 100.0), 2);
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeVol >= minV && (vol - closeVol) >= minV)
            {
               if(trade.PositionClosePartial(ticket, closeVol))
               {
                  g_states[sIdx].partialClosed = true;
                  learning.SetPartialClosed(ticket, true);
                  Print("Partial TP (Q", (int)quality, "): ", closeVol, " lots @ ", DoubleToString(profitR,2), "R");
               }
            }
         }

         // 2. Break-Even (using adaptive trigger if not already set)
         if(profitR >= beTrigger && MathAbs(sl - open) > _Point)
         {
            bool better = (pType == POSITION_TYPE_BUY) ? sl < open : (sl > open || sl == 0);
            if(better) trade.PositionModify(ticket, open, tp);
         }

         // 3. Hybrid Trailing
         if(profitR >= trailStart)
         {
            double ab[1];
            if(CopyBuffer(hATR, 0, 0, 1, ab) == 1)
            {
               double mult = InpTrailATR_Mult;
               if(quality == EQ_WEAK) mult *= 0.7;
               if(quality == EQ_ELITE) mult *= 1.5;

               double learnedTrail = learning.GetLearnedTrail(ab[0]);
               double atrDist = ab[0] * mult;
               double td = MathMax(atrDist, learnedTrail);

               double newSL = (pType == POSITION_TYPE_BUY) ? curr - td : curr + td;
               if((pType == POSITION_TYPE_BUY && newSL > sl && newSL < curr) ||
                  (pType == POSITION_TYPE_SELL && (newSL < sl || sl == 0) && newSL > curr))
                  trade.PositionModify(ticket, newSL, tp);
            }
         }
      }
   }
}

void OnTrade()
{
   // OPTIMIZATION: Handle Closed Trades efficiently
   // Note: Most trade cleanup is done in ManagePositions(), this is backup

   static datetime lastTradeEventTime = 0;
   datetime currentTime = TimeCurrent();

   // OPTIMIZATION: Don't process if no time has passed (avoid redundant calls)
   if(currentTime == lastTradeEventTime) return;
   lastTradeEventTime = currentTime;

   // Check recent history (last 60 seconds)
   if(!HistorySelect(currentTime - 60, currentTime)) return;

   int dealCount = HistoryDealsTotal();
   for(int i = 0; i < dealCount; i++)
   {
       ulong ticket = HistoryDealGetTicket(i);
       if(ticket == 0) continue;

       // OPTIMIZATION: Check entry type first (fastest filter)
       if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

       // Check if it's our trade
       long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
       if(magic != InpMagicNumber) continue;

       double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
       double rOutcome = (profit > 0) ? 1.0 : -1.0;

       // OPTIMIZATION: Estimate R multiple from profit
       double equity = account.Equity();
       if(equity > 0 && InpRiskBase > 0)
       {
           double profitPct = (profit / equity) * 100.0;
           rOutcome = profitPct / InpRiskBase;
       }

       // Phase 6.1: Update profit counters (BEFORE module updates to capture all trades)
       g_dailyProfit += profit;   // Add to daily profit (can be negative for losses)
       g_totalProfit += profit;   // Add to total cumulative profit

       // Phase 6.2: Update trading days counter (increment on first trade of new day)
       MqlDateTime closeDt;
       TimeToStruct(HistoryDealGetInteger(ticket, DEAL_TIME), closeDt);
       datetime tradeDate = StringToTime(StringFormat("%04d.%02d.%02d", closeDt.year, closeDt.mon, closeDt.day));

       if(tradeDate != g_lastTradeDate)
       {
          g_tradingDaysCount++;
          g_lastTradeDate = tradeDate;

          // Save to GlobalVariable for persistence
          string gvTradingDays = "GV_TRADING_DAYS_" + _Symbol;
          GlobalVariableSet(gvTradingDays, g_tradingDaysCount);

          if(InpMinTradingDays > 0)
          {
             Print("📅 Trading Day #", g_tradingDaysCount, " / ", InpMinTradingDays, " required");
          }
          else
          {
             Print("📅 Trading Day #", g_tradingDaysCount, " (tracking only)");
          }
       }

       // Update modules (backup in case ManagePositions missed it)
       killSwitch.OnTradeClosed(rOutcome);
       learning.OnTradeClosed(ticket);

       // OPTIMIZATION: Update Kelly sizer
       if(InpUseKelly)
       {
          ENTRY_QUALITY quality = EQ_GOOD;

          // Try to find quality from states
          int stateCount = ArraySize(g_states);
          for(int s = 0; s < stateCount; s++)
          {
             if(g_states[s].ticket == ticket)
             {
                quality = g_states[s].quality;
                break;
             }
          }

          kellySizer.AddTradeResult(rOutcome, quality);
       }
   }
}

//+------------------------------------------------------------------+
//| Check Add-On Opportunity                                          |
//+------------------------------------------------------------------+
void CheckAddOnOpportunity()
{
   double totalR = GetTotalProfitR();
   double currentScore = CalculateConfluenceScore(g_entryDirection);

   if(!g_addOn1Triggered && g_positionCount < InpMaxPositions)
   {
      if(totalR >= InpAddOn1_R && currentScore >= InpMinConfluenceEntry)
      {
         GovernorRequest req = allocator.BuildRequest(_Symbol, InpRiskAddOn1, killSwitch.GetWinRate(), killSwitch.GetRollingR(), (int)g_currentRegime);
         double approved = allocator.RequestRisk(req);
         if(approved > 0.05)
         {
            ENUM_ORDER_TYPE type = (g_entryDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            if(ExecuteTrade(type, approved, "Add1", EQ_GOOD))
            {
               g_addOn1Triggered = true;
               Print("ADD #1 | R:", DoubleToString(totalR,1), " | Risk:", approved);
            }
         }
      }
   }

   if(!g_addOn2Triggered && g_addOn1Triggered && g_positionCount < InpMaxPositions)
   {
      if(totalR >= InpAddOn2_R && currentScore >= InpMinConfluenceEntry + 1)
      {
         GovernorRequest req = allocator.BuildRequest(_Symbol, InpRiskAddOn2, killSwitch.GetWinRate(), killSwitch.GetRollingR(), (int)g_currentRegime);
         double approved = allocator.RequestRisk(req);
         if(approved > 0.05)
         {
            ENUM_ORDER_TYPE type = (g_entryDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            if(ExecuteTrade(type, approved, "Add2", EQ_GOOD))
            {
               g_addOn2Triggered = true;
               Print("ADD #2 | R:", DoubleToString(totalR,1), " | Risk:", approved);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update all SMC and filter modules                                 |
//+------------------------------------------------------------------+
void UpdateModules()
{
   // OPTIMIZATION: Update SMC modules only if enabled
   if(InpUseSMC)
   {
      smcStructure.Update();
      smcOrderBlocks.Update();
      smcFVG.Update();
      smcLiquidity.Update();
   }

   // OPTIMIZATION: Update MTF analysis only if enabled
   if(InpUseMTF) mtfAnalysis.Update();

   // OPTIMIZATION: Update filters only if enabled
   if(InpUseNewsFilter) newsFilter.Update();
   if(InpUseKelly) kellySizer.Update();

}

//+------------------------------------------------------------------+
//| Build Confluence Factors Structure for Adaptive Filtering         |
//+------------------------------------------------------------------+
void BuildConfluenceFactors(ConfluenceFactors &factors, int direction, double score)
{
   // Estimate factors from score (simplified)
   // In future: capture actual factors during CalculateConfluenceScore
   factors.trendAligned = (score >= 1.0);
   factors.structureBreak = (score >= 2.0);
   factors.fibZone = (score >= 3.0);
   factors.rsiMomentum = (score >= 4.0);
   factors.orderBlock = (score >= 5.0);
   factors.fvg = (score >= 6.0);
   factors.liquiditySweep = (score >= 7.0);
   factors.killzoneActive = false;
   factors.mtfAligned = (score >= 8.0);

   factors.killzone = KILLZONE_NONE;
   factors.regime = g_currentRegime;
   factors.confluenceScore = score;
}

//+------------------------------------------------------------------+
//| NEW Confluence Score (0-30) - M15 Enhanced Analysis               |
//+------------------------------------------------------------------+
double CalculateConfluenceScore(int direction)
{
   double score = 0;
   double currentPrice = symbolInfo.Bid();

   // DEBUG: Print indicator values
   static datetime lastDebug = 0;
   if(TimeCurrent() - lastDebug > 300) // Print every 5 minutes
   {
      Print("DEBUG Indicators: EMA=", g_EMA, " ATR=", g_ATR, " RSI=", g_RSI, " Price=", currentPrice);
      lastDebug = TimeCurrent();
   }

   // ============ 1. CORE SMC & PRICE ACTION (~7.0 pts) ============

   // Trend (EMA 200 + Slope) - 2.5 points (Boosted from 1.0)
   double emaSlope = g_EMA - g_EMA_Prev;
   bool slopeStrong = MathAbs(emaSlope) >= (g_ATR * InpEMA_MinSlope);
   
   // 1. Price Alignment (1.5 pts)
   if(direction == 1 && currentPrice > g_EMA) score += 1.5;
   if(direction == -1 && currentPrice < g_EMA) score += 1.5;
   
   // 2. Slope Alignment (1.0 pt)
   if(direction == 1 && emaSlope > 0) score += 1.0;
   if(direction == -1 && emaSlope < 0) score += 1.0;

   // Market Structure - 1.0 point
   // M15 Adaptation: Check for valid structure
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 1);
   int lowestBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback, 1);
   
   // Structure Strength Check (M15)
   double structRange = 0;
   if(highestBar >= 0 && lowestBar >= 0) 
      structRange = iHigh(_Symbol, PERIOD_CURRENT, highestBar) - iLow(_Symbol, PERIOD_CURRENT, lowestBar);
   
   bool validStructure = (structRange >= g_ATR * 2.0); // Keep 2.0 ATR filter
   
   if(direction == 1 && lowestBar < highestBar && validStructure) score += 2.0;
   if(direction == -1 && highestBar < lowestBar && validStructure) score += 2.0;

   // RSI Extremes (Regime Aware) - 1.0 point
   if(g_currentRegime == REGIME_TREND)
   {
      // In trend, look for pullbacks
      if(direction == 1 && g_RSI < 50 && g_RSI > 30) score += 1.5;
      if(direction == -1 && g_RSI > 50 && g_RSI < 70) score += 1.5;
   }
   else
   {
      // In range, look for extremes
      if(direction == 1 && g_RSI <= InpRSI_Oversold) score += 1.5;
      if(direction == -1 && g_RSI >= InpRSI_Overbought) score += 1.5;
   }

   // RSI Momentum - 1.0 point
   if(InpRSI_Momentum)
   {
      if(direction == 1 && g_RSI > g_RSI_Prev) score += 1.0;
      if(direction == -1 && g_RSI < g_RSI_Prev) score += 1.0;
   }

   // Displacement - 1.5 point
   if(CheckDisplacement(direction)) score += 1.5;

   // Volatility - 1.5 pts
   // FIX: Validate both ATR and ATR_MA before division
   double atrRatio = 1.0;
   if(g_ATR > 0 && g_ATR_MA > 0)
      atrRatio = g_ATR / g_ATR_MA;
   if(atrRatio >= 0.8 && atrRatio <= 1.3) score += 1.5;

   // Chop Filter - 1.0 pt
   if(!CheckChopFilter()) {
      score += 1.0;
   }

   // ============ 2. INSTITUTIONAL CONCEPTS (~7.0 pts) ============
   
   if(InpUseSMC)
   {
       // Basic SMC
       score += smcStructure.GetConfluenceScore(direction);  // ~1.0
       score += smcOrderBlocks.GetConfluenceScore(direction) * 1.5; // ~2.25 (Boosted multiplier)
       score += smcFVG.GetConfluenceScore(direction);         // ~1.0
       score += smcLiquidity.GetConfluenceScore(direction) * 1.5;   // ~2.25 (Boosted multiplier)
       
       // Advanced ICT
       // Breaker Blocks (~2.0) - Fix: Pass ATR
       score += breakerBlocks.GetBreakerScore(direction, g_ATR) * 4.0; // Scale 0.5 -> 2.0
       
       // Macro Windows (~1.5)
       score += macroWindows.GetMacroScore() * 3.0; // Scale 0.5 -> 1.5
       
       // Power of 3 (~2.0) - Fix: Pass ATR
       score += powerOf3.GetPhaseScore(g_ATR) * 4.0; // Scale 0.5 -> 2.0
   }

   // ============ 3. ADVANCED CONFLUENCE (~16.0 pts) ============

   // Volume Profile (~2.5 pts)
   score += volumeAnalysis.GetConfluenceScore(direction);

   // Multi-Timeframe (~2.0 pts)
   if(InpUseMTF)
      score += mtfAnalysis.GetConfluenceScore(direction);

   // Divergence (~1.5 pts)
   // FIX: Pass hRSI handle + cache result to avoid duplicate calculation
   double divergenceScore = divergence.GetDivergenceScore(direction, hRSI);
   score += divergenceScore;

   // Wyckoff (~1.5 pts) - Fix: Pass ATR
   score += wyckoff.GetWyckoffScore(direction, g_ATR) * 3.0; // Scale 0.5 -> 1.5

   // Fib Zone (~1.5 pts)
   if(highestBar >= 0 && lowestBar >= 0)
   {
      double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, highestBar);
      double swingLow = iLow(_Symbol, PERIOD_CURRENT, lowestBar);
      double range = swingHigh - swingLow;
      double tolerance = g_ATR * InpZoneTolerance;

      if(range >= g_ATR * 1.5)
      {
         bool inZone = false;
         if(direction == 1)
         {
            double f618 = swingHigh - (range * InpFibLevelLow);
            double f786 = swingHigh - (range * InpFibLevelHigh);
            if(currentPrice <= f618 + tolerance && currentPrice >= f786 - tolerance) inZone = true;
         }
         else
         {
            double f618 = swingLow + (range * InpFibLevelLow);
            double f786 = swingLow + (range * InpFibLevelHigh);
            if(currentPrice >= f618 - tolerance && currentPrice <= f786 + tolerance) inZone = true;
         }
         if(inZone) score += 1.5;
      }
   }
   
   // Regime Confirmation (+1.0)
   if(g_currentRegime == REGIME_TREND) score += 1.0;


   // ============ CRITICAL FILTERS (Penalty/Block) ============

   // Reversal Filter (EMA 50/100)
   if(InpUseReversalFilter)
   {
       bool emaAlignment = (direction == 1) ? (currentPrice < g_EMA50 && g_EMA50 < g_EMA100)
                                            : (currentPrice > g_EMA50 && g_EMA50 > g_EMA100);

       if(emaAlignment)
       {
           // M15 Specific: Trend reversals are common but risky.
           // Penalize heavily if no divergence
           // FIX: Use cached divergenceScore to avoid duplicate calculation
           if(divergenceScore < 0.5)
           {
               score -= 2.0; // Reduced penalty (was 5.0)
               // FIX: Floor cap to prevent negative scores
               if(score < 0) score = 0;
           }
       }
   }

   // Context Multipliers
   // FIX: Removed volatile regime multiplier - was applied too late and caused
   // borderline scores (10-12) to fail entry threshold unexpectedly

   // DEBUG: Print final score
   static datetime lastScoreDebug = 0;
   if(TimeCurrent() - lastScoreDebug > 300) // Print every 5 minutes
   {
      Print("DEBUG Score [", (direction == 1 ? "BUY" : "SELL"), "]: ", DoubleToString(score, 2), "/30");
      lastScoreDebug = TimeCurrent();
   }

   return score;  // Max possible: ~30 points
}

double GetTotalProfitR()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            double open = position.PriceOpen();
            double curr = position.PriceCurrent();
            double sl = position.StopLoss();
            double profit = (position.PositionType() == POSITION_TYPE_BUY) ? (curr - open) : (open - curr);
            double risk = MathAbs(open - sl);
            if(risk > 0) total += (profit / risk);
         }
      }
   }
   return total;
}

//+------------------------------------------------------------------+
//| Update Indicators                                                 |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   double bufRSI[2], bufATR[1], bufEMA[2];

   if(CopyBuffer(hRSI, 0, 1, 2, bufRSI) != 2)
   {
      Print("ERROR: Failed to copy RSI buffer");
      return false;
   }
   if(CopyBuffer(hATR, 0, 1, 1, bufATR) != 1)
   {
      Print("ERROR: Failed to copy ATR buffer");
      return false;
   }
   if(CopyBuffer(hEMA, 0, 1, 2, bufEMA) != 2)
   {
      Print("ERROR: Failed to copy EMA buffer");
      return false;
   }

   g_RSI_Prev = bufRSI[0];
   g_RSI = bufRSI[1];
   g_ATR = bufATR[0];
   g_EMA_Prev = bufEMA[0];
   g_EMA = bufEMA[1];

   // DEBUG: Print updated values
   static datetime lastIndicatorDebug = 0;
   if(TimeCurrent() - lastIndicatorDebug > 300) // Print every 5 minutes
   {
      Print("DEBUG UpdateIndicators: RSI=", g_RSI, " ATR=", g_ATR, " EMA=", g_EMA);
      lastIndicatorDebug = TimeCurrent();
   }

   // Update reversal filter EMAs
   if(InpUseReversalFilter)
   {
      double bufEMA50[2], bufEMA100[2];
      if(CopyBuffer(hEMA50, 0, 1, 2, bufEMA50) != 2) return false;
      if(CopyBuffer(hEMA100, 0, 1, 2, bufEMA100) != 2) return false;

      g_EMA50_Prev = bufEMA50[0];
      g_EMA50 = bufEMA50[1];
      g_EMA100_Prev = bufEMA100[0];
      g_EMA100 = bufEMA100[1];
   }

   if(InpUseChopFilter)
   {
      double atrSum = 0, ab[1];
      for(int i = 1; i <= InpATR_MA_Period; i++)
         if(CopyBuffer(hATR, 0, i, 1, ab) == 1) atrSum += ab[0];
      g_ATR_MA = atrSum / InpATR_MA_Period;
   }

   return true;
}

bool CheckChopFilter()
{
   if(!InpUseChopFilter) return true;
   return (g_ATR >= g_ATR_MA * InpChopThreshold);
}

bool CheckSpread()
{
   if(InpMaxSpreadPoints <= 0) return true;

   // OPTIMIZATION: Cache spread value to avoid multiple calls
   static int lastSpread = 0;
   static datetime lastSpreadCheck = 0;

   // Update spread every 5 seconds (spreads don't change that fast)
   if(TimeCurrent() - lastSpreadCheck >= 5)
   {
      lastSpread = (int)symbolInfo.Spread();
      lastSpreadCheck = TimeCurrent();
   }

   if(lastSpread > InpMaxSpreadPoints)
   {
      static datetime lastSpreadWarning = 0;
      if(TimeCurrent() - lastSpreadWarning > 60)
      {
         Print("⚠️ Spread too wide: ", lastSpread, " > ", InpMaxSpreadPoints, " points");
         lastSpreadWarning = TimeCurrent();
      }
      return false;
   }

   return true;
}

bool CheckDisplacement(int dir)
{
   if(!InpUseDisplacement) return true;
   for(int i = 2; i <= InpDisplacementLookback + 1; i++)
   {
      double o = iOpen(_Symbol, PERIOD_CURRENT, i);
      double c = iClose(_Symbol, PERIOD_CURRENT, i);
      if(MathAbs(c - o) >= g_ATR * InpDisplacementATR)
      {
         if(dir == 1 && c > o) return true;
         if(dir == -1 && c < o) return true;
      }
   }
   return false;
}

int CountPositions()
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(position.SelectByIndex(i))
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
            cnt++;
   return cnt;
}

double CalculateLotSize(double slDist, double riskPct)
{
   // OPTIMIZATION: Validate inputs first
   if(slDist <= 0 || riskPct <= 0)
   {
      Print("ERROR: Invalid lot calculation inputs - slDist:", slDist, " riskPct:", riskPct);
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }

   double equity = account.Equity();
   if(equity <= 0) equity = account.Balance();
   if(equity <= 0)
   {
      Print("ERROR: Invalid account equity/balance");
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }

   double riskAmt = equity * (riskPct / 100.0);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // OPTIMIZATION: Validate symbol info
   if(ts <= 0 || tv <= 0)
   {
      Print("ERROR: Invalid symbol tick info - ts:", ts, " tv:", tv);
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }

   double lots = riskAmt / ((slDist / ts) * tv);

   // OPTIMIZATION: Get volume limits once
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // Clamp to broker limits
   if(lots < minL) lots = minL;
   if(lots > maxL) lots = maxL;

   // Additional safety limit
   if(lots > InpMaxLotsPerTrade)
   {
      Print("⚠️ Lots capped: ", DoubleToString(lots, 3), " → ", DoubleToString(InpMaxLotsPerTrade, 2));
      lots = InpMaxLotsPerTrade;
   }

   // OPTIMIZATION: Proper rounding to step size
   lots = MathFloor(lots / step + 0.000001) * step;

   // Final validation
   if(lots < minL || lots > maxL)
   {
      Print("ERROR: Calculated lot size out of range: ", lots);
      return minL;
   }

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Check if sufficient margin available for position                 |
//+------------------------------------------------------------------+
bool CheckMarginRequirement(string symbol, ENUM_ORDER_TYPE type, double lots)
{
   // Skip check if disabled
   if(!InpEnableMarginCheck) return true;

   double freeMargin = account.FreeMargin();
   double requiredMargin = 0;

   // Calculate required margin for this position
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);

   if(!OrderCalcMargin(type, symbol, lots, price, requiredMargin))
   {
      Print("ERROR: Cannot calculate margin requirement for ", symbol, " ", DoubleToString(lots, 2), " lots");
      return false;
   }

   // Require at least 150% of needed margin for safety buffer
   double safetyMultiplier = 1.5;
   double safetyMargin = requiredMargin * safetyMultiplier;

   if(freeMargin < safetyMargin)
   {
      Print("MARGIN CHECK FAILED for ", symbol, ":");
      Print("  Required: ", DoubleToString(requiredMargin, 2),
            " | Free: ", DoubleToString(freeMargin, 2),
            " | Safety needed: ", DoubleToString(safetyMargin, 2));
      Print("  Lots: ", DoubleToString(lots, 2),
            " | Type: ", EnumToString(type));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double price = symbolInfo.Bid();
   double totalR = GetTotalProfitR();

   // OPTIMIZATION: Use cached scores instead of recalculating
   double buyS = g_cachedBuyScore;
   double sellS = g_cachedSellScore;

   // If scores not calculated yet (first tick), calculate them
   // ALWAYS calculate for dashboard visibility (even if trading is blocked)
   if(g_lastScoreCalcTime == 0)
   {
      buyS = CalculateConfluenceScore(1);
      sellS = CalculateConfluenceScore(-1);
   }

   string govStatus = allocator.IsGovernorActive() ? "Connected " + DoubleToString(GetRiskMultiplier()*100,0) + "%" : "Standalone";
   string tradingStatus = IsTradingEnabled() ? "ACTIVE" : "BLOCKED";

   // Check for blocks
   if(InpUseNewsFilter && !newsFilter.IsTradingAllowed()) tradingStatus = "NEWS BLOCKED";
   if(InpUseKelly && !kellySizer.IsTradingAllowed()) tradingStatus = "DD LIMIT";
   if(InpUseKillzoneFilter && !CheckKillzone()) tradingStatus = "KILLZONE CLOSED";

   string kzStatus = "DISABLED";
   if(InpUseKillzoneFilter)
   {
       kzStatus = CheckKillzone() ? "OPEN " : "CLOSED ";
       // Identify active KZ for display
       datetime utcTime = TimeCurrent() - (InpBrokerUTCOffset * 3600);
       MqlDateTime utcDt; TimeToStruct(utcTime, utcDt);
       int estHour = (utcDt.hour - 5 + 24) % 24;
       if(estHour >= 20 || estHour < 0) kzStatus += "[Asia]";
       else if(estHour >= 2 && estHour < 5) kzStatus += "[LonOpen]";
       else if(estHour >= 7 && estHour < 10) kzStatus += "[NY]";
       else if(estHour >= 10 && estHour < 12) kzStatus += "[LonClose]";
       else kzStatus += "[OFF]";
   }

   string txt = "===========================================\n";
   txt += "  SYMBOL ENGINE v2.0: " + _Symbol + "\n";
   txt += "===========================================\n";
   txt += "Governor: " + govStatus + "\n";
   txt += "Trading: " + tradingStatus + "\n";
   txt += "Killzone: " + kzStatus + "\n";
   txt += "-------------------------------------------\n";
   txt += "Price: " + DoubleToString(price, (int)symbolInfo.Digits()) + "\n";
   txt += "RSI: " + DoubleToString(g_RSI, 1) + "\n";


   // News info
   if(InpUseNewsFilter)
      txt += newsFilter.ToString() + "\n";

   txt += "-------------------------------------------\n";

   // SMC Status
   if(InpUseSMC)
   {
      txt += "STRUCTURE: " + smcStructure.StructureToString() + "\n";
      txt += smcOrderBlocks.ToString() + " | " + smcFVG.ToString() + "\n";
      txt += smcLiquidity.ToString() + "\n";
   }

   // MTF Status
   if(InpUseMTF)
      txt += mtfAnalysis.ToString() + "\n";

   txt += "-------------------------------------------\n";
   txt += "BUY Score: " + DoubleToString(buyS, 1) + "/30\n";
   txt += "SELL Score: " + DoubleToString(sellS, 1) + "/30\n";
   txt += "Entry Min: " + DoubleToString(InpMinConfluenceEntry, 1) + "/30 (Good) | " + DoubleToString(InpMinConfluenceEntry + 2.0, 1) + " (Strong) | " + DoubleToString(InpMinConfluenceEntry + 4.0, 1) + " (Elite)\n";
   txt += "-------------------------------------------\n";

   // TP Mode Info
   string tpMode = "OFF";
   if(InpTPMode == 1) tpMode = "Fixed " + DoubleToString(InpFixedTP_R, 1) + "R";
   else if(InpTPMode == 2) tpMode = "Adaptive (MFE-based)";
   else if(InpTPMode == 3) tpMode = "Hybrid (Adaptive+Trail)";

   txt += "TP Mode: " + tpMode + "\n";

   // Show learned MFE/MAE if learning active
   if(InpEnableLearning && InpTPUseLearnedMFE)
   {
      double avgMFE = learning.GetAvgMFE();
      double avgMAE = learning.GetAvgMAE();
      if(avgMFE > 0 || avgMAE > 0)
      {
         txt += "Learned MFE: " + DoubleToString(avgMFE / _Point, 0) + " pts | ";
         txt += "MAE: " + DoubleToString(avgMAE / _Point, 0) + " pts\n";

         if(g_ATR > 0 && avgMFE > 0)
         {
            double projectedTPR = (avgMFE / g_ATR) * 0.75;
            txt += "Projected TP: " + DoubleToString(projectedTPR, 1) + "R\n";
         }
      }
   }

   txt += "-------------------------------------------\n";
   txt += "Positions: " + IntegerToString(g_positionCount) + "/" + IntegerToString(InpMaxPositions) + "\n";
   txt += "Total R: " + DoubleToString(totalR, 2) + "\n";

   // Kelly stats
   if(InpUseKelly)
   {
      txt += "-------------------------------------------\n";
      txt += kellySizer.ToString() + "\n";
      txt += "Daily DD: " + DoubleToString(kellySizer.GetDailyDD(), 2) + "/" + DoubleToString(InpDailyMaxDD, 1) + "%\n";
   }


   // Directional Cooldowns
   if(InpReversalCooldownMinutes > 0)
   {
      txt += "-------------------------------------------\n";
      txt += "DIRECTIONAL COOLDOWNS\n";

      if(g_lastBuyTime > 0)
      {
         int buySecondsSince = (int)(TimeCurrent() - g_lastBuyTime);
         int buyMinutesSince = buySecondsSince / 60;
         txt += "Last BUY: " + IntegerToString(buyMinutesSince) + "m ago";
         if(buyMinutesSince < InpReversalCooldownMinutes)
            txt += " [COOLING]";
         txt += "\n";
      }
      else
      {
         txt += "Last BUY: Never\n";
      }

      if(g_lastSellTime > 0)
      {
         int sellSecondsSince = (int)(TimeCurrent() - g_lastSellTime);
         int sellMinutesSince = sellSecondsSince / 60;
         txt += "Last SELL: " + IntegerToString(sellMinutesSince) + "m ago";
         if(sellMinutesSince < InpReversalCooldownMinutes)
            txt += " [COOLING]";
         txt += "\n";
      }
      else
      {
         txt += "Last SELL: Never\n";
      }

      txt += "Cooldown Period: " + IntegerToString(InpReversalCooldownMinutes) + " minutes\n";
   }

   // Learning System stats
   if(InpEnableLearning && InpLogTradesToFile)
   {
      txt += "-------------------------------------------\n";
      txt += "LEARNING SYSTEM (SQLite)\n";
      
      performanceAnalyzer.RefreshData();
      ContextStats overall = performanceAnalyzer.GetOverallStats();
      
      int totalTrades = overall.tradeCount;
      txt += "Trades in DB: " + IntegerToString(totalTrades) + "\n";
      
      if(totalTrades > 0)
      {
          txt += "Win Rate: " + DoubleToString(overall.winRate * 100, 1) + "% | ";
          txt += "PF: " + DoubleToString(overall.profitFactor, 2) + "\n";
          txt += "Avg R: " + DoubleToString(overall.avgR, 2) + "\n";
          txt += "Expectancy: " + DoubleToString(overall.expectancy, 3) + "R\n";

          // Show best performing contexts
          ENUM_KILLZONE bestKZ = performanceAnalyzer.GetBestKillzone();
          if(bestKZ != KILLZONE_NONE)
          {
             txt += "Best Killzone: " + KillzoneToString(bestKZ);
             ContextStats kzStats = performanceAnalyzer.GetStatsByKillzone(bestKZ);
             txt += " (WR: " + DoubleToString(kzStats.winRate * 100, 1) + "%)\n";
          }

          MARKET_REGIME bestRegime = performanceAnalyzer.GetBestRegime();
          if(bestRegime != REGIME_UNKNOWN)
          {
             txt += "Best Regime: " + IntegerToString((int)bestRegime);
             ContextStats regStats = performanceAnalyzer.GetStatsByRegime(bestRegime);
             txt += " (E: " + DoubleToString(regStats.expectancy, 2) + "R)\n";
          }

          // Show pattern recognition stats
          int patternCount = patternMemory.GetPatternCount();
          if(patternCount > 0)
          {
             txt += "\nPATTERN LEARNING\n";
             txt += patternRecognizer.GetStatsString() + "\n";
          }

          // Show adaptive module status
          if(InpEnableAdaptiveRisk || InpEnableAdaptiveExits || InpEnableAdaptiveFilters)
          {
             txt += "\nADAPTIVE BEHAVIOR\n";

             if(InpEnableAdaptiveRisk)
             {
                ENUM_KILLZONE currentKZ = KILLZONE_NONE;
                txt += adaptiveRisk.GetAdjustmentSummary(currentKZ, g_currentRegime) + "\n";
             }

             if(InpEnableAdaptiveExits)
             {
                txt += adaptiveExit.GetAdjustmentSummary(g_currentRegime) + "\n";
             }

             if(InpEnableAdaptiveFilters)
             {
                ENUM_KILLZONE currentKZ = KILLZONE_NONE;
                txt += adaptiveFilter.GetFilterStatus(currentKZ, g_currentRegime) + "\n";
             }
          }
      }
   }

   // OPTIMIZATION: Performance statistics
   if(g_barCount > 0)
   {
      txt += "-------------------------------------------\n";
      txt += "PERFORMANCE STATS\n";
      txt += "Bars Processed: " + IntegerToString(g_barCount) + "\n";
      txt += "Trades Executed: " + IntegerToString(g_tradesExecuted) + "\n";
      if(g_tradesExecuted > 0)
      {
         double barsPerTrade = (double)g_barCount / (double)g_tradesExecuted;
         txt += "Selectivity: 1 trade per " + IntegerToString((int)barsPerTrade) + " bars\n";
      }
   }

   txt += "===========================================\n";

   Comment(txt);
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Log Heartbeat                                                     |
//+------------------------------------------------------------------+
void LogHeartbeat()
{
   string heartbeat = "💓 HB: " + _Symbol + " | " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n";
   
   // 1. Logic Active Status
   bool tradingAllowed = true;
   
   heartbeat += "   Status: " + (tradingAllowed ? "ACTIVE ✅" : "IDLE zzz") + " | Regime: " + IntegerToString((int)g_currentRegime);
   if(InpUseKillzoneFilter) heartbeat += " | KZ: " + (CheckKillzone() ? "OPEN" : "CLOSED");
   heartbeat += "\n";
   
   // 2. Confluence Scores
   heartbeat += "   Scores: BUY=" + DoubleToString(g_cachedBuyScore, 1) + "/30 | SELL=" + DoubleToString(g_cachedSellScore, 1) + "/30\n";
   
   // 3. Open Positions
   heartbeat += "   Positions: " + IntegerToString(g_positionCount);
   if(g_positionCount > 0)
   {
      heartbeat += " (";
      for(int i=0; i<ArraySize(g_states); i++)
      {
         heartbeat += "#" + IntegerToString(g_states[i].ticket) + " ";
      }
      heartbeat += ")";
   }
   
   Print(heartbeat);
}

//+------------------------------------------------------------------+
//| Check Killzone Time                                               |
//+------------------------------------------------------------------+
bool CheckKillzone()
{
   if(!InpUseKillzoneFilter) return true;

   datetime utcTime = TimeCurrent() - (InpBrokerUTCOffset * 3600);
   MqlDateTime utcDt;
   TimeToStruct(utcTime, utcDt);

   // AST Calculation (Atlantic Standard Time UTC-4 for Dominican Republic)
   // Changed from EST (UTC-5) to AST (UTC-4) to match Dominican Republic timezone
   int estHour = (utcDt.hour - 4 + 24) % 24;

   // 1. Asian Session (20:00 - 00:00 AST / 8PM-12AM Dominican Republic)
   if(InpEnableAsianKZ)
   {
      if(estHour >= 20 || estHour < 0) return true;
   }

   // 2. London Open (02:00 - 05:00 AST / 2AM-5AM Dominican Republic)
   if(InpEnableLondonOpenKZ)
   {
      if(estHour >= 2 && estHour < 5) return true;
   }

   // 3. NY Open (07:00 - 10:00 AST / 7AM-10AM Dominican Republic)
   if(InpEnableNYKZ)
   {
      if(estHour >= 7 && estHour < 10) return true;
   }

   // 4. London Close (10:00 - 12:00 AST / 10AM-12PM Dominican Republic)
   if(InpEnableLondonCloseKZ)
   {
      if(estHour >= 10 && estHour < 12) return true;
   }

   return false;
}
