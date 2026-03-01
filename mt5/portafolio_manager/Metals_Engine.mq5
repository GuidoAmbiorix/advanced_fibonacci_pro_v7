//+------------------------------------------------------------------+
//|                                            Metals_Engine.mq5     |
//|          🪙 Metals Engine: XAUUSD-Optimized Trading              |
//|             Confluence Ladder + Portfolio Integration            |
//+------------------------------------------------------------------+
#property copyright "Metals Engine - XAUUSD Specialized"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property description "🪙 Metals Engine: XAUUSD-Optimized with Session/Spread Filters"
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
#include "Include\SessionOptimizer.mqh"  // 🪙 METALS: Session scoring
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
enum ENUM_TRAIL_TYPE
{
   TRAIL_R_BASED,    // R-Multiple Based
   TRAIL_CHANDELIER, // Chandelier Exit
   TRAIL_STEP        // Step Trailing
};
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
input int               InpMinConfluenceEntry = 12;      // 🪙 Metals: Stricter (increased from 4)
input double            InpDominanceThreshold = 2.0;      // Signal Dominance Threshold
input bool              InpEnableAddOns = true;
input double            InpAddOn1_R = 1.5;
input double            InpAddOn2_R = 2.5;
input int               InpMaxPositions = 3;

input group "======= RISK (Before Governor Scaling) ======="
input double            InpRiskBase = 0.20;              // 🪙 Metals: Reduced from 0.25
input double            InpRiskAddOn1 = 0.15;
input double            InpRiskAddOn2 = 0.10;
input double            InpMaxRisk = 0.60;               // 🪙 Metals: Maximum Risk % (reduced from 0.75)
input double            InpMaxLotsPerTrade = 0.5;        // Max Lots Per Trade
input bool              InpEnableMarginCheck = true;     // Validate Margin Before Opening

input group "======= TAKE PROFIT ======="
input int               InpTPMode = 2;                    // 0=None, 1=Fixed, 2=Adaptive, 3=Hybrid, 4=Volatility
input double            InpFixedTP_R = 3.0;               // Fixed TP (R-multiple)
input double            InpMinTP_R = 1.5;                 // Minimum TP (R-multiple)
input double            InpMaxTP_R = 5.0;                 // Maximum TP (R-multiple)
input bool              InpTPUseLearnedMFE = true;        // Use Learned MFE for TP

input group "======= EXIT ======="
input int               InpTrailingMode = 1;              // 0=Off, 1=Runner, 2=Full
input ENUM_TRAIL_TYPE   InpTrailType = TRAIL_CHANDELIER;  // Trail Type
input double            InpTrailStepATR = 0.5;            // Step Trail (ATR)
input group "======= VOLATILITY FILTER ======="
input double            InpMinVolatilityPips = 5.0;       // Min Volatility (Pips)
input double            InpMaxVolatilityFactor = 3.0;     // Max Volatility (Factor of Avg)
input double            InpVolatilityTP_Mult = 3.0;       // Volatility TP Multiplier (ATR)
input double            InpPartialTP_R = 1.5;
input double            InpPartialClosePercent = 40.0;
input double            InpBE_Threshold_R = 1.0;         // Min profit to activate dynamic trail (R)
input double            InpTrailStart_R = 1.0;            // Trail activation (same as BE for dynamic)
input double            InpTrailATR_Mult = 2.0;           // Base ATR multiplier (wider for metals)
input double            InpTrailDecayRate = 0.15;         // Multiplier decay rate (slow for metals)
input double            InpTrailMinMult = 0.60;           // Minimum ATR multiplier (floor)
input bool              InpTrailRegimeAware = true;       // Widen trail in trends, tighten in ranges

input group "======= SPREAD ======="
input int               InpMaxSpreadPoints = 50;
input double            InpMetals_MaxSpreadUSD = 1.0;    // 🪙 Metals: Max Spread in USD (session-dependent)

input group "======= SMC - SMART MONEY CONCEPTS ======="
input bool              InpUseSMC = true;                 // Enable SMC Analysis
input int               InpSMC_SwingLookback = 20;        // Swing Lookback Bars
input double            InpSMC_MinImpulseATR = 2.0;       // Min Impulse (ATR mult)
input double            InpSMC_MinFVG_ATR = 0.5;          // Min FVG Size (ATR mult)

input group "======= MULTI-TIMEFRAME ======="
input bool              InpUseMTF = true;                 // Enable MTF Analysis
input ENUM_TIMEFRAMES   InpHTF = PERIOD_H1;               // Higher Timeframe
input ENUM_TIMEFRAMES   InpMTF = PERIOD_M15;              // Medium Timeframe
input int               InpMTF_EMAPeriod = 50;            // MTF EMA Period

input group "======= NEWS FILTER ======="
input bool              InpUseNewsFilter = true;          // Enable News Filter
input int               InpNewsMinutesBefore = 60;        // 🪙 Metals: 1-hour blackout (increased from 30)
input int               InpNewsMinutesAfter = 60;         // 🪙 Metals: 1-hour blackout (increased from 30)

input group "======= VOLATILITY SPIKE PROTECTION ======="
input bool              InpEnableVolatilityFilter = true; // Enable Flash Crash Detection
input double            InpVolatilityThreshold = 3.0;     // Volatility Spike Threshold (ATR multiplier)
input int               InpVolatilitySpikeCooldown = 15;  // Cooldown After Spike (minutes)

input group "======= KELLY POSITION SIZING ======="
input bool              InpUseKelly = true;               // Enable Kelly Sizing
input double            InpKellyFraction = 0.5;           // Kelly Fraction (0.5=Half Kelly)
input double            InpDailyMaxDD = 3.0;              // Daily Max Drawdown %
input double            InpWeeklyMaxDD = 6.0;             // Weekly Max Drawdown %
input double            InpDailyTarget = 0.0;             // Daily Profit Target % (0=disabled)

input group "======= LEARNING & ADAPTATION ======="
input bool              InpEnableLearning = true;         // Enable Learning System
input bool              InpLogTradesToFile = true;        // Log Trades to CSV
input int               InpLearningHistory = 180;         // Days of History to Load
input int               InpMinTradesForLearning = 50;     // Min Trades Before Learning

input group "======= ADAPTIVE BEHAVIOR (Advanced) ======="
input bool              InpEnableAdaptiveRisk = false;    // Enable Adaptive Risk
input bool              InpEnableAdaptiveExits = false;   // Enable Adaptive Exits
input bool              InpEnableAdaptiveFilters = true;  // FIX: Enable Adaptive Filters (Phase 5)

input group "======= PORTFOLIO PROTECTION ======="
input bool              InpUseCorrelationFilter = true;   // Enable Correlation Protection
input double            InpDailyMaxLoss_R = 4.0;          // Daily Max Loss (R) - Circuit Breaker
input int               InpLossCooldownMinutes = 30;      // Cooldown After Loss (minutes)
input int               InpMaxConsecutiveLosses = 2;      // Max Consecutive Losses Rule
input int               InpMaxDailyTrades = 5;            // Max Trades Per Day (prevents overtrading)
input bool              InpUseReversalFilter = true;      // Enable Reversal Trend Filter
input int               InpReversalCooldownMinutes = 15;  // Min Time Between Same-Direction Trades

input group "======= KILLZONES ======="
input bool              InpUseKillzoneFilter = true;      // Enable Killzone Filter
input bool              InpEnableAsianKZ = false;         // Enable Asian Killzone
input bool              InpEnableLondonOpenKZ = true;     // Enable London Open Killzone
input bool              InpEnableNYKZ = true;             // Enable NY Killzone
input bool              InpEnableLondonCloseKZ = false;   // Enable London Close Killzone
input bool              InpNotifyKillzoneOpen = true;     // Notify on Killzone Open


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
CSessionOptimizer   sessionOptimizer;  // 🪙 METALS: Session scoring
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
ENUM_KILLZONE g_lastKillzoneState = KILLZONE_NONE;
double g_dailyLossR = 0;
int    g_consecutiveLosses = 0;
int    g_dailyTradesCount = 0;  // FIX: Track daily trades to prevent overtrading
datetime g_lastResetDate = 0;
datetime g_lastBuyTime = 0;    // Last BUY trade entry time
datetime g_lastSellTime = 0;   // Last SELL trade entry time

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
   double initialRisk;         // Risk percentage (0.30 = 0.30%)
   double dollarRisk;          // Actual dollar amount at risk for R-calculation
   ENTRY_QUALITY quality;
};
PositionState g_states[];

// REAL confluence factors captured during CalculateConfluenceScore()
ConfluenceFactors g_lastBuyFactors;
ConfluenceFactors g_lastSellFactors;

// OnTrade dedup: track tickets already processed by ManagePositions
ulong g_processedOnTrade[];

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

   // 🪙 METALS: Initialize Session Optimizer
   sessionOptimizer.Init(_Symbol, InpBrokerUTCOffset);
   Print("🪙 METALS: Session Optimizer initialized for ", _Symbol);

   // Initialize Kelly Position Sizer
   if(InpUseKelly)
   {
      // Adjust maxRisk based on account size for safety
      double maxRiskAdjusted = InpMaxRisk;
      double equity = account.Equity();

      // 🪙 METALS: Apply commodity margin adjustment
      string sym = _Symbol;
      StringToUpper(sym);
      bool isMetals = (StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0);

      if(isMetals)
      {
         // METALS-SPECIFIC RISK LIMITS (due to higher margin requirements)
         if(equity < 10000)
         {
            maxRiskAdjusted = MathMin(InpMaxRisk, 0.40);   // Small accounts: 0.40%
            Print("🪙 METALS Small account ($", DoubleToString(equity, 2), ") - maxRisk limited to ", maxRiskAdjusted, "%");
         }
         else if(equity < 50000)
         {
            maxRiskAdjusted = MathMin(InpMaxRisk, 0.60);   // Medium accounts: 0.60%
            Print("🪙 METALS Medium account ($", DoubleToString(equity, 2), ") - maxRisk limited to ", maxRiskAdjusted, "%");
         }
         else
         {
            maxRiskAdjusted = InpMaxRisk;  // Large accounts: use input parameter
            Print("🪙 METALS Large account ($", DoubleToString(equity, 2), ") - using maxRisk: ", maxRiskAdjusted, "%");
         }
      }
      else
      {
         // STANDARD FX RISK LIMITS
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
      }

      kellySizer.Init(InpRiskBase, 0.25, maxRiskAdjusted, InpKellyFraction, 30, InpDailyMaxDD, InpWeeklyMaxDD, InpDailyTarget);
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
      if(g_lastResetDate > 0 && g_dailyLossR < 0)
      {
         Print("📊 Daily Reset: Previous day loss was ", DoubleToString(g_dailyLossR, 2), "R | Trades: ", g_dailyTradesCount);

         // FIX: Export daily performance (Phase 7)
         ExportDailyPerformance(g_dailyTradesCount, g_dailyLossR);
      }
      g_dailyLossR = 0;
      g_consecutiveLosses = 0;
      g_dailyTradesCount = 0;  // FIX: Reset daily trade counter
      g_lastResetDate = currentDate;
   }
}

//+------------------------------------------------------------------+
//| FIX: Export Daily Performance (Phase 7)                          |
//+------------------------------------------------------------------+
void ExportDailyPerformance(int trades, double totalR)
{
   MqlDateTime dt;
   TimeCurrent(dt);
   string filename = StringFormat("Daily_Performance_%s_%04d%02d%02d.csv",
                                  _Symbol, dt.year, dt.mon, dt.day);

   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, "Date", "Symbol", "Trades", "TotalR", "AvgR", "WinRate", "MaxDD", "ConfluenceAvg");

      double avgR = (trades > 0) ? totalR / trades : 0;
      double winRate = killSwitch.GetWinRate();
      double maxDD = GlobalVariableGet(GV_CURRENT_DD);

      FileWrite(handle,
               TimeToString(TimeCurrent(), TIME_DATE),
               _Symbol,
               IntegerToString(trades),
               DoubleToString(totalR, 2),
               DoubleToString(avgR, 2),
               DoubleToString(winRate * 100, 1),
               DoubleToString(maxDD, 2),
               DoubleToString(g_currentConfluence, 2));

      FileClose(handle);
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
   // MODE 4: Volatility Based
   else if(InpTPMode == 4)
   {
      // Calculate Volatility Target (e.g. 3x ATR)
      // Convert to R-multiple relative to SL distance
      if(atr > 0 && slDist > 0)
         tpR = (atr * InpVolatilityTP_Mult) / slDist;
      else
         tpR = InpFixedTP_R; // Fallback
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

      // Regime adjustments (H1-optimized)
      if(g_currentRegime == REGIME_TREND) tpR *= 1.5;        // H1: Increased from 1.3 to 1.5 (let H1 trends run)
      else if(g_currentRegime == REGIME_RANGE) tpR *= 0.70;  // H1: Reduced from 0.85 to 0.70 (tighten range exits)
      else if(g_currentRegime == REGIME_VOLATILE) tpR *= 1.2; // H1: Increased from 1.1 to 1.2
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


   // --- GOVERNOR EXECUTION GUARD ---
   // Check if Portfolio Governor has disabled trading (Daily Profit Target, Max DD, etc.)
   if(GlobalVariableCheck(GV_TRADING_ENABLED) && GlobalVariableGet(GV_TRADING_ENABLED) == 0)
   {
      static datetime lastGovernorLog = 0;
      if(TimeCurrent() - lastGovernorLog > 300)
      {
         Print("⛔ ENGINE PAUSED: Portfolio Governor has disabled trading (Daily Target or Max DD reached)");
         lastGovernorLog = TimeCurrent();
      }
      return;
   }
   
   // --- KILLZONE NOTIFICATION ---
   if(InpNotifyKillzoneOpen)
   {
      ENUM_KILLZONE currentKZ = GetActiveKillzone();
      if(currentKZ != g_lastKillzoneState)
      {
         // Only notify on OPEN (state change to non-NONE), not close
         if(currentKZ != KILLZONE_NONE)
         {
             string msg = "🟢 KILLZONE OPEN: " + KillzoneToString(currentKZ) + " on " + _Symbol;
             if(InpEnableMobileAlerts) SendNotification(msg);
             Print(msg);
         }
         g_lastKillzoneState = currentKZ;
      }
   }

   g_tickCount++;  // Performance monitoring

   symbolInfo.RefreshRates();

   g_positionCount = CountPositions();
   if(g_positionCount == 0) ResetTradeState();

   // OPTIMIZATION: Update dashboard less frequently (every 5 seconds instead of every tick)
   static datetime lastDashboardUpdate = 0;
   if(TimeCurrent() - lastDashboardUpdate >= 5)
   {
      UpdateDashboard();
      lastDashboardUpdate = TimeCurrent();
   }

   // --- CRITICAL: MANAGING POSITIONS ---
   // User requested logic to wait for new bar for stability.
   // However, trailing stops usually need tick data.
   // For now, adhering to user request for stability to stop immediate closures.
   if(!IsNewBar()) return;

   g_barCount++;  // Performance monitoring

   // --- GOVERNOR EMERGENCY CLOSE GUARD ---
   if(IsDailyTargetHit()) return; // Stop trailing/managing while Governor closes positions

   // Manage existing positions (Trailing, TP, BreakEven)
   ManagePositions();

   // Update Indicators & Modules
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

      // --- SIGNAL DOMINANCE FILTER ---
      if(InpDominanceThreshold > 0)
      {
         double delta = MathAbs(g_cachedBuyScore - g_cachedSellScore);
         if(delta < InpDominanceThreshold)
         {
            if(g_cachedBuyScore > InpMinConfluenceEntry || g_cachedSellScore > InpMinConfluenceEntry)
            {
               Print("⚠️ DOMINANCE FILTER: Blocked Signal. Buy=", DoubleToString(g_cachedBuyScore,1),
                     " Sell=", DoubleToString(g_cachedSellScore,1), " Delta=", DoubleToString(delta,1), " < ", InpDominanceThreshold);
            }
            g_cachedBuyScore = 0;
            g_cachedSellScore = 0;
         }
      }

      // --- RANKING SYSTEM: PUBLISH SCORE ---
      // Publish the higher of the two scores to represent the symbol's "Potential"
      double maxScore = (g_cachedBuyScore > g_cachedSellScore) ? g_cachedBuyScore : g_cachedSellScore;
      double direction = (g_cachedBuyScore > g_cachedSellScore) ? 1.0 : -1.0;
      
      GlobalVariableSet(GV_SCORE_PREFIX + _Symbol, maxScore);
      GlobalVariableSet(GV_REQ_PREFIX + _Symbol, InpMinConfluenceEntry);
      GlobalVariableSet(GV_DIR_PREFIX + _Symbol, direction);
      
      // Timer Data
      GlobalVariableSet(GV_BAROPEN_PREFIX + _Symbol, (double)currentBarTime);
      GlobalVariableSet(GV_PERIOD_PREFIX + _Symbol, (double)PeriodSeconds(InpMTF));
      
      // Killzone Status
      bool isKZOpen = !InpUseKillzoneFilter || CheckKillzone();
      GlobalVariableSet(GV_KZ_PREFIX + _Symbol, isKZOpen ? 1.0 : 0.0);
   }

   // --- MODULE: FAIL SAFE (Quick Exit) ---
   if(!failSafe.IsExecutionSafe())
   {
      static datetime lastFailSafeLog = 0;
      if(TimeCurrent() - lastFailSafeLog > 300)
      {
         Print("🚫 BLOCKED: Fail Safe - Execution not safe (spread/connection issues)");
         lastFailSafeLog = TimeCurrent();
      }
      return;
   }

   // --- MODULE: KILL SWITCH (Quick Exit) ---
   if(!killSwitch.IsEnabled())
   {
      static datetime lastKillWarning = 0;
      if(TimeCurrent() - lastKillWarning > 300)
      {
         Print("⛔ BLOCKED: Kill Switch - ", killSwitch.GetStatus(),
               " | RollingR: ", DoubleToString(killSwitch.GetRollingR(), 2));
         lastKillWarning = TimeCurrent();
      }
      return;
   }

   // --- MODULE: NEWS FILTER ---
   if(InpUseNewsFilter && !newsFilter.IsTradingAllowed())
   {
      static datetime lastNewsLog = 0;
      if(TimeCurrent() - lastNewsLog > 300)
      {
         string newsStatus = newsFilter.IsInNewsWindow() ? ("News window: " + newsFilter.GetCurrentEventName()) : "Volatility spike detected";
         Print("🚫 BLOCKED: News Filter - ", newsStatus);
         lastNewsLog = TimeCurrent();
      }
      return;
   }

   // --- MODULE: KELLY POSITION SIZER (DD + DAILY TARGET LIMITS) ---
   if(InpUseKelly && !kellySizer.IsTradingAllowed())
   {
      static datetime lastKellyLog = 0;
      if(TimeCurrent() - lastKellyLog > 300)
      {
         Print("BLOCKED: Kelly Sizer - Drawdown or daily profit target limits hit");
         lastKellyLog = TimeCurrent();
      }
      return;
   }


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

   if(g_currentRegime == REGIME_CHAOS)
   {
      static datetime lastRegimeLog = 0;
      if(TimeCurrent() - lastRegimeLog > 300)
      {
         Print("🚫 BLOCKED: Market Regime = CHAOS (ATR/ATR_MA ratio out of bounds)");
         lastRegimeLog = TimeCurrent();
      }
      return;
   }

   // PRE-ENTRY FILTERS (Quick Exits for Performance)
   if(!CheckSpread())
   {
      static datetime lastSpreadLog = 0;
      if(TimeCurrent() - lastSpreadLog > 300)
      {
         Print("🚫 BLOCKED: Spread too wide (CheckSpread failed)");
         lastSpreadLog = TimeCurrent();
      }
      return;
   }
   if(!IsSpreadAcceptable()) return;  // 🪙 METALS: Session-dependent spread filter (has own logging)

   // OPTIMIZATION: RSI Compression Filter (avoid choppy middle zone)
   if(g_RSI > 48 && g_RSI < 52)
   {
      static datetime lastRSIWarning = 0;
      if(TimeCurrent() - lastRSIWarning > 300)
      {
         Print("🚫 BLOCKED: RSI in dead zone: ", DoubleToString(g_RSI, 1), " (48-52) - waiting for momentum");
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
         Print("🚫 BLOCKED: Too close to EMA 200: ", DoubleToString(emaDistance / _Point, 0),
               " pips (min: ", DoubleToString(minDistance / _Point, 0), " pips)");
         lastEMAWarning = TimeCurrent();
      }
      return;
   }

   // FIX: Volatility Safety Check
   if(InpEnableAdaptiveFilters && !adaptiveFilter.IsVolatilitySafe(g_ATR, InpMinVolatilityPips, InpMaxVolatilityFactor, g_ATR_MA))
   {
      static datetime lastVolWarning = 0;
      if(TimeCurrent() - lastVolWarning > 300)
      {
         Print("🚫 BLOCKED: VOLATILITY UNSAFE - ATR=", DoubleToString(g_ATR, 5), " (Dead or Extreme)");
         lastVolWarning = TimeCurrent();
      }
      return;
   }

   // Check Governor Trading Permission
   if(!IsTradingEnabled())
   {
      static datetime lastGovLog = 0;
      if(TimeCurrent() - lastGovLog > 300)
      {
         Print("🚫 BLOCKED: Portfolio Governor - Trading not enabled for this symbol");
         lastGovLog = TimeCurrent();
      }
      return;
   }

   double buyScore = g_cachedBuyScore;
   double sellScore = g_cachedSellScore;

   // Apply adaptive filter (pattern bonus/penalty)
   if(InpEnableLearning && InpEnableAdaptiveFilters && performanceAnalyzer.IsLearningActive())
   {
      // Use REAL factors captured during CalculateConfluenceScore() (not score proxies)
      double buyBonus = adaptiveFilter.GetAdjustedConfluence(buyScore, g_lastBuyFactors) - buyScore;
      buyScore += buyBonus;

      double sellBonus = adaptiveFilter.GetAdjustedConfluence(sellScore, g_lastSellFactors) - sellScore;
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
          if(TimeCurrent() - lastTrade < InpTradeCooldownMinutes * 60)
          {
             static datetime lastCooldownSessionLog = 0;
             if(TimeCurrent() - lastCooldownSessionLog > 300)
             {
                int remaining = (int)((InpTradeCooldownMinutes * 60 - (TimeCurrent() - lastTrade)) / 60);
                Print("🚫 BLOCKED: Session Cooldown - ", remaining, " minutes remaining");
                lastCooldownSessionLog = TimeCurrent();
             }
             return;
          }

          // Max Trades Check (Simple Session Reset logic required or daily limit)
          // For now, using simple daily limit as proxy or relying on Allocator
      }

      // --- RANKING GUARD (Top 3 Only) ---
      // Check if this symbol is ranked high enough to trade
      // Defaulting to Top 3 if not specified
      double myRank = 999;
      if(GlobalVariableCheck(GV_RANK_PREFIX + _Symbol))
         myRank = GlobalVariableGet(GV_RANK_PREFIX + _Symbol);
      
      if(myRank > 3) 
      {
         static datetime lastRankLog = 0;
         if(TimeCurrent() - lastRankLog > 60) // Log every minute if blocked
         {
            Print("⏸️ RANKING WAIT: ", _Symbol, " Rank #", (int)myRank, " (Only Top 3 trade)");
            lastRankLog = TimeCurrent();
         }
         return; // Wait for better rank
      }

      // --- KILLZONES ---
      if(InpUseKillzoneFilter)
      {
          if(!CheckKillzone())
          {
             static datetime lastKZLog = 0;
             if(TimeCurrent() - lastKZLog > 300)
             {
                Print("🚫 BLOCKED: Outside Killzone - Current time not in enabled killzones");
                lastKZLog = TimeCurrent();
             }
             return;
          }
      }

      double bestScore = (buyScore > sellScore) ? buyScore : sellScore;
      int bestDirection = (buyScore > sellScore) ? 1 : -1;

      // Get Entry Tier from new confluence system
      ENUM_ENTRY_TIER tier = GetEntryTier(bestScore);
      if(tier == TIER_NO_TRADE)
      {
         static datetime lastTierLog = 0;
         if(TimeCurrent() - lastTierLog > 300)
         {
            Print("🚫 BLOCKED: Entry Tier = NO_TRADE - Best score: ", DoubleToString(bestScore, 2),
                  " (Min required: ", InpMinConfluenceEntry, ")");
            lastTierLog = TimeCurrent();
         }
         return;
      }

      // Calculate Quality using Learning Module Logic
      ENTRY_QUALITY quality = learning.CalculateQuality(bestScore);
      if(quality == EQ_WEAK)
      {
         static datetime lastQualityLog = 0;
         if(TimeCurrent() - lastQualityLog > 300)
         {
            Print("🚫 BLOCKED: Quality = WEAK - Score: ", DoubleToString(bestScore, 2));
            lastQualityLog = TimeCurrent();
         }
         return;
      }

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
         // Use REAL factors from last CalculateConfluenceScore() call
         ConfluenceFactors factors;
         if(bestDirection == 1) factors = g_lastBuyFactors;
         else factors = g_lastSellFactors;

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
          // FIX: Wire up dynamic threshold (Phase 5)
          double minEntry = InpMinConfluenceEntry;  // Base threshold from .set file

          // Use adaptive threshold if enabled
          if(InpEnableAdaptiveFilters && adaptiveFilter.IsAdaptationEnabled())
          {
             // Create confluence factors for dynamic threshold calculation
             ENUM_KILLZONE currentKZ = KILLZONE_NONE;
              // Use REAL factors from last CalculateConfluenceScore() call
              ConfluenceFactors thresholdFactors;
              if(bestDirection == 1) thresholdFactors = g_lastBuyFactors;
              else thresholdFactors = g_lastSellFactors;

             minEntry = adaptiveFilter.CalculateDynamicThreshold(thresholdFactors, currentKZ, g_currentRegime);

             static datetime lastThresholdLog = 0;
             if(TimeCurrent() - lastThresholdLog > 3600)  // Log hourly
             {
                Print("📊 Dynamic Threshold: ", DoubleToString(minEntry, 2),
                      " (base: ", DoubleToString(InpMinConfluenceEntry, 2), ")");
                lastThresholdLog = TimeCurrent();
             }
          }

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

   // --- GUARANTEED MAX RISK CAP ---
   // Check if the minimum lot size creates a dollar risk larger than our allowed Risk%
   double equity = account.Equity();
   if(equity <= 0) equity = account.Balance();
   double maxRiskDollar = equity * (riskPct / 100.0);
   
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   if (tv > 0 && ts > 0)
   {
       double minLotRiskDollar = (slDist / ts) * tv * minL;
       
       if (minLotRiskDollar > maxRiskDollar && maxRiskDollar > 0)
       {
          slDist = (maxRiskDollar / (minL * tv)) * ts;
          if(slDist < stopsLevel + 10 * _Point) slDist = stopsLevel + 10 * _Point;
          Print("⚠️ RISK CAP APPLIED: SL reduced to mathematically enforce ", DoubleToString(riskPct, 2), "% risk limit.");
       }
   }
   // --------------------------------

   double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   sl = NormalizeDouble(sl, (int)symbolInfo.Digits());
   double lots = CalculateLotSize(slDist, riskPct);

   string comment = "SE|" + label + "|Q" + IntegerToString((int)quality);

   // Calculate TP
   int dir = (type == ORDER_TYPE_BUY) ? 1 : -1;
   double tp = CalculateTakeProfit(price, slDist, dir, quality, g_ATR);

   // RUNNER MODE: Override Hard TP to allow extended runs for Gold
   // Gold trends can be massive (10R+), so we must uncap the hard TP
   if(InpTrailingMode == 1)
   {
       double runnerTP_R = MathMax(InpMaxTP_R, 15.0); // Gold needs more room (15R)
       double runnerDist = slDist * runnerTP_R;
       tp = (type == ORDER_TYPE_BUY) ? price + runnerDist : price - runnerDist;
       tp = NormalizeDouble(tp, (int)symbolInfo.Digits());
       
       // Print("🏃 GOLD RUNNER MODE: Hard TP extended to ", DoubleToString(runnerTP_R,1), "R");
   }

   // FIX: CONSECUTIVE LOSS PROTECTION - Check immediately before OrderSend
   if(InpMaxConsecutiveLosses > 0 && g_consecutiveLosses >= InpMaxConsecutiveLosses)
   {
      Print("⛔ TRADE BLOCKED: ", g_consecutiveLosses, " consecutive losses reached. Waiting for cooldown or winning trade.");

      // Set GlobalVariable to notify Governor
      string gvName = "GV_COOLDOWN_" + _Symbol;
      GlobalVariableSet(gvName, (double)TimeCurrent());

      return false;
   }

   // FIX: MAX DAILY TRADES PROTECTION - Prevent overtrading
   if(InpMaxDailyTrades > 0 && g_dailyTradesCount >= InpMaxDailyTrades)
   {
      static datetime lastOvertradeWarning = 0;
      if(TimeCurrent() - lastOvertradeWarning > 3600)  // Log once per hour
      {
         Print("⛔ DAILY TRADE LIMIT: ", g_dailyTradesCount, "/", InpMaxDailyTrades, " trades reached. No more trades today.");
         lastOvertradeWarning = TimeCurrent();
      }
      return false;
   }

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

      // FIX: Increment daily trade counter (overtrading protection)
      g_dailyTradesCount++;

      // Store in local backup state
      int sz = ArraySize(g_states);
      ArrayResize(g_states, sz + 1);
      g_states[sz].ticket = ticket;
      g_states[sz].partialClosed = false;
      g_states[sz].initialRisk = riskPct;                                    // Store risk percentage
      g_states[sz].dollarRisk = account.Equity() * (riskPct / 100.0);       // Store actual dollar risk for R-calculation
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

             // Calculate R-multiple using actual dollar risk stored at entry
             // FIX: Use dollarRisk instead of recalculating from current equity (which has changed)
             double dollarRisk = g_states[i].dollarRisk;
             double profitR = (dollarRisk > 0) ? profitMoney / dollarRisk : 0;

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

             // FIX: Update adaptive filter rolling window (Phase 5)
             if(InpEnableAdaptiveFilters)
             {
                adaptiveFilter.UpdateRecentPerformance(profitR);
             }

             // Track Daily Loss for Circuit Breaker
             g_dailyLossR += profitR;
             if(profitMoney < 0)
             {
                g_lastLossTime = TimeCurrent();  // Track last loss time for cooldown
                g_consecutiveLosses++;           // REVENGE TRADING PROTECTION
                Print("📉 Loss recorded: ", DoubleToString(profitR, 2), "R | Daily total: ",
                      DoubleToString(g_dailyLossR, 2), "R | Streak: ", g_consecutiveLosses);

                // FIX: Log to database if consecutive loss limit reached
                if(g_consecutiveLosses >= InpMaxConsecutiveLosses)
                {
                   Print("🚨 CONSECUTIVE LOSS LIMIT HIT: ", g_consecutiveLosses, " losses. Next trade will be blocked.");
                   // Notify Governor
                   GlobalVariableSet("GV_COOLDOWN_" + _Symbol, (double)TimeCurrent());
                }
             }
             else
             {
                if(g_consecutiveLosses > 0) Print("✅ Win breaks losing streak of ", g_consecutiveLosses);
                g_consecutiveLosses = 0;         // Reset on win
             }
         }

         g_lastCloseTime = TimeCurrent();

          // Record ticket so OnTrade() won't double-call modules
          int pSz = ArraySize(g_processedOnTrade);
          ArrayResize(g_processedOnTrade, pSz + 1);
          g_processedOnTrade[pSz] = ticket;
          if(pSz > 100)
          {
             for(int k = 0; k < pSz; k++) g_processedOnTrade[k] = g_processedOnTrade[k+1];
             ArrayResize(g_processedOnTrade, pSz);
          }
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

      // Create new state if not found (fallback - shouldn't happen if ExecuteTrade worked correctly)
      if(sIdx == -1)
      {
         ArrayResize(g_states, stateCount + 1);
         g_states[stateCount].ticket = ticket;
         g_states[stateCount].partialClosed = false;
         // Can't accurately determine dollar risk retrospectively, estimate using base risk
         g_states[stateCount].initialRisk = InpRiskBase;
         g_states[stateCount].dollarRisk = account.Equity() * (InpRiskBase / 100.0);
         g_states[stateCount].quality = EQ_GOOD;
         Print("Warning: Created fallback position state for ticket ", ticket, " - R-calculations may be approximate");
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

          // 2. DYNAMIC ATR TRAILING SYSTEM (replaces hardcoded waterfall)
          // Multiplier decays exponentially as profitR grows:
          //   mult = base * e^(-decayRate * profitR), floored at minMult
          // Regime-aware: wider in trends, tighter in ranges
          // Merges with Chandelier: takes the most protective SL of both
          if(profitR >= InpBE_Threshold_R)
          {
             double ab[1];
             if(CopyBuffer(hATR, 0, 0, 1, ab) == 1 && ab[0] > 0)
             {
                double atrVal = ab[0];

                // --- DYNAMIC FLOOR ---
                // Step 1: Exponential decay multiplier (tightens as profit grows)
                double dynMult = InpTrailATR_Mult * MathExp(-InpTrailDecayRate * profitR);
                dynMult = MathMax(dynMult, InpTrailMinMult);

                // Step 2: Quality adjustment
                if(quality == EQ_WEAK)  dynMult *= 0.8; // tighter for weak setups
                if(quality == EQ_ELITE) dynMult *= 1.2; // wider for elite (let runners run)

                // Step 3: Regime-aware adjustment
                if(InpTrailRegimeAware)
                {
                   if(g_currentRegime == REGIME_TREND)      dynMult *= 1.4;
                   else if(g_currentRegime == REGIME_RANGE)  dynMult *= 0.7;
                   // VOLATILE: keep as-is (high ATR already gives room)
                }

                // Step 4: Dynamic floor price (trail behind current price)
                double dynFloor = (pType == POSITION_TYPE_BUY)
                                  ? curr - (atrVal * dynMult)
                                  : curr + (atrVal * dynMult);

                // --- CHANDELIER EXIT ---
                double chandelierSL = 0;
                if(InpTrailType == TRAIL_CHANDELIER)
                {
                   double learnedTrail = learning.GetLearnedTrail(atrVal);
                   double baseMult = MathMax(dynMult, learnedTrail / atrVal);
                   chandelierSL = adaptiveExit.CalculateChandelierExit(20, atrVal,
                                  (pType == POSITION_TYPE_BUY ? 0 : 1), baseMult);
                }
                else if(InpTrailType == TRAIL_STEP)
                {
                   double td = atrVal * dynMult;
                   double proposed = (pType == POSITION_TYPE_BUY) ? curr - td : curr + td;
                   chandelierSL = adaptiveExit.CalculateStepTrail(sl, proposed, atrVal,
                                  InpTrailStepATR, (pType == POSITION_TYPE_BUY ? 0 : 1));
                }
                else // TRAIL_R_BASED
                {
                   double td = atrVal * dynMult;
                   chandelierSL = (pType == POSITION_TYPE_BUY) ? curr - td : curr + td;
                }

                // --- MERGE: Take the most protective SL of both ---
                double bestSL;
                if(pType == POSITION_TYPE_BUY)
                   bestSL = (chandelierSL > 0) ? MathMax(dynFloor, chandelierSL) : dynFloor;
                else
                   bestSL = (chandelierSL > 0) ? MathMin(dynFloor, chandelierSL) : dynFloor;

                // --- APPLY: Only move SL in favorable direction ---
                bool slBetter = (pType == POSITION_TYPE_BUY)
                                ? (bestSL > sl + _Point*5 && bestSL < curr)
                                : ((bestSL < sl - _Point*5 || sl == 0) && bestSL > curr);

                if(slBetter)
                {
                   if(trade.PositionModify(ticket, bestSL, tp))
                      Print("DynTrail: mult=", DoubleToString(dynMult,2),
                            " floor=", DoubleToString(dynFloor,_Digits),
                            " ce=", DoubleToString(chandelierSL,_Digits),
                            " best=", DoubleToString(bestSL,_Digits),
                            " R=", DoubleToString(profitR,2));
                }
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

   // FIX: Expand history window to 24 hours (86400 seconds) to catch all closed trades
   // Previous 60-second window could miss trades closed during high volatility or session gaps
   if(!HistorySelect(currentTime - 86400, currentTime)) return;

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

       // FIX: Calculate accurate R-multiple using stored dollarRisk from g_states
       ENTRY_QUALITY quality = EQ_GOOD;
       double dollarRisk = 0;
       bool foundState = false;

       int stateCount = ArraySize(g_states);
       for(int s = 0; s < stateCount; s++)
       {
          if(g_states[s].ticket == ticket)
          {
             dollarRisk = g_states[s].dollarRisk;
             quality = g_states[s].quality;
             foundState = true;
             break;
          }
       }

       // Calculate accurate R-multiple if we have the dollar risk
       if(foundState && dollarRisk > 0)
       {
          rOutcome = profit / dollarRisk;
       }
       else
       {
          // Fallback: Estimate from current equity (less accurate)
          double equity = account.Equity();
          if(equity > 0 && InpRiskBase > 0)
          {
              double profitPct = (profit / equity) * 100.0;
              rOutcome = profitPct / InpRiskBase;
          }
       }
        // Dedup guard: skip if ManagePositions already handled this ticket
        bool alreadyHandled = false;
        int pCount = ArraySize(g_processedOnTrade);
        for(int p = 0; p < pCount; p++)
        {
           if(g_processedOnTrade[p] == ticket) { alreadyHandled = true; break; }
        }
        if(alreadyHandled) continue;


       // Update modules (backup in case ManagePositions missed it)
       killSwitch.OnTradeClosed(rOutcome);
       learning.OnTradeClosed(ticket);

       // Update Kelly sizer
       if(InpUseKelly)
       {
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


   // ============ 1. CORE SMC & PRICE ACTION (Max ~10.0 pts) ============

   // A. Trend (EMA 200 + Slope) - 3.0 points 
   double emaSlope = g_EMA - g_EMA_Prev;
   bool slopeAligned = (direction == 1 && emaSlope > 0) || (direction == -1 && emaSlope < 0);
   bool priceAligned = (direction == 1 && currentPrice > g_EMA) || (direction == -1 && currentPrice < g_EMA);
   
   if(priceAligned) score += 1.5;
   if(slopeAligned) score += 1.5;

   // B. Structure (Bos/Choch) - 3.0 points
   // M15 Adaptation: Check for valid structure
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 1);
   int lowestBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback, 1);
   double structRange = 0;
   if(highestBar >= 0 && lowestBar >= 0) 
      structRange = iHigh(_Symbol, PERIOD_CURRENT, highestBar) - iLow(_Symbol, PERIOD_CURRENT, lowestBar);
   
   bool validStructure = (structRange >= g_ATR * 2.0); 
   
   if(direction == 1 && lowestBar < highestBar && validStructure) score += 3.0; // Boosted
   if(direction == -1 && highestBar < lowestBar && validStructure) score += 3.0; // Boosted

   // C. RSI Extremes - 2.0 points
   bool rsiValid = false;
   if(g_currentRegime == REGIME_TREND)
   {
      // In trend, look for pullbacks
      if(direction == 1 && g_RSI < 60 && g_RSI > 40) rsiValid = true; // Wider pullback zone
      if(direction == -1 && g_RSI > 40 && g_RSI < 60) rsiValid = true;
   }
   else
   {
      // In range, look for extremes
      if(direction == 1 && g_RSI <= InpRSI_Oversold) rsiValid = true;
      if(direction == -1 && g_RSI >= InpRSI_Overbought) rsiValid = true;
   }
   if(rsiValid) score += 2.0;

   // D. Displacement - 2.0 points
   if(CheckDisplacement(direction)) score += 2.0;


   // ============ 2. MOMENTUM & VOLATILITY (Max ~5.0 pts) ============
   
   // RSI Momentum - 1.5 points
   if(InpRSI_Momentum)
   {
      if(direction == 1 && g_RSI > g_RSI_Prev) score += 1.5;
      if(direction == -1 && g_RSI < g_RSI_Prev) score += 1.5;
   }

   // Volatility Ratio - 2.0 points
   double atrRatio = 1.0;
   if(g_ATR > 0 && g_ATR_MA > 0) atrRatio = g_ATR / g_ATR_MA;
   // Expanded window for M15: 0.7 to 1.5
   if(atrRatio >= 0.7 && atrRatio <= 1.5) score += 2.0;

   // Chop Filter (Cleanliness) - 1.5 pts
   if(!CheckChopFilter()) score += 1.5;


   // ============ 3. INSTITUTIONAL & SMC ADD-ONS (Max ~10.0 pts) ============
   
   if(InpUseSMC)
   {
       // Order Blocks - 2.5 pts
       score += smcOrderBlocks.GetConfluenceScore(direction) * 2.5; 
       
       // Liquidity Sweeps - 2.5 pts
       score += smcLiquidity.GetConfluenceScore(direction) * 2.5;
       
       // FVG - 2.0 pts
       score += smcFVG.GetConfluenceScore(direction) * 2.0;
       
       // Advanced ICT Concepts
       score += breakerBlocks.GetBreakerScore(direction, g_ATR) * 3.0; 
       score += powerOf3.GetPhaseScore(g_ATR) * 3.0; 
   }


   // ============ 4. ADVANCED CONFIRMATIONS (Max ~5-10 pts) ============

   // Institutional Volume - 4.0 pts (RVOL + Money Flow)
   score += volumeAnalysis.GetConfluenceScore(direction);

   // Multi-Timeframe - 2.0 pts
   if(InpUseMTF)
      score += mtfAnalysis.GetConfluenceScore(direction);

   // Divergence - 2.0 pts
   double divergenceScore = divergence.GetDivergenceScore(direction, hRSI);
   score += divergenceScore * 2.0; // Scale 0-1 -> 0-2

   // Wyckoff - 2.0 pts
   score += wyckoff.GetWyckoffScore(direction, g_ATR) * 2.0; 

   // Fib Zone - 2.0 pts
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
         if(inZone) score += 2.0;
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
           // Apply soft penalty only if NO divergence/reversal signals
           if(divergenceScore < 0.5)
           {
               score -= 2.0; 
               if(score < 0) score = 0;
           }
       }
   }

   // ============ 4. 🪙 METALS: SESSION SCORING (Max ~3.0 pts) ============

   // Check if this is a metals symbol (XAUUSD, GOLD, etc.)
   string sym = _Symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      sessionOptimizer.Update();  // Update session detection
      double sessionScore = sessionOptimizer.GetMetalsSessionScore();  // 0-10 scale
      double sessionPoints = (sessionScore / 10.0) * 2.5;  // Convert to 0-2.5 points
      score += sessionPoints;

      // Extra bonus for prime time (London-NY overlap)
      if(sessionOptimizer.IsPrimeTime())
         score += 0.5;

   }
   // Populate REAL ConfluenceFactors for AdaptiveFilter and PatternRecognizer
   ConfluenceFactors outFactors;
   if(direction == 1) outFactors = g_lastBuyFactors;
   else outFactors = g_lastSellFactors;
   outFactors.trendAligned   = priceAligned || slopeAligned;
   outFactors.structureBreak = validStructure;
   outFactors.fibZone        = false;
   outFactors.rsiMomentum    = rsiValid || (InpRSI_Momentum && ((direction==1 && g_RSI > g_RSI_Prev) || (direction==-1 && g_RSI < g_RSI_Prev)));
   outFactors.orderBlock     = InpUseSMC && smcOrderBlocks.GetConfluenceScore(direction) > 0;
   outFactors.fvg            = InpUseSMC && smcFVG.GetConfluenceScore(direction) > 0;
   outFactors.liquiditySweep = InpUseSMC && smcLiquidity.GetConfluenceScore(direction) > 0;
   outFactors.killzoneActive = false;
   outFactors.mtfAligned     = InpUseMTF && mtfAnalysis.GetConfluenceScore(direction) > 0;
   outFactors.killzone       = KILLZONE_NONE;
   outFactors.regime         = g_currentRegime;
   outFactors.confluenceScore = score;


   return score;  // Max possible: ~30-35 points (38 with metals session bonus)
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

//+------------------------------------------------------------------+
//| 🪙 METALS: Check Spread Acceptability (Session-Dependent)        |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   // Disable spread filter during backtesting (unreliable spread data)
   if(MQLInfoInteger(MQL_TESTER)) return true;

   // Check if this is a metals symbol
   string sym = _Symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
      return true;  // Not metals, skip this filter

   double currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double currentSpreadUSD = currentSpread;  // Price difference in USD (e.g. 0.30)

   // Determine current session using GMT time
   datetime utcTime = TimeCurrent() - (InpBrokerUTCOffset * 3600);
   MqlDateTime utcDt;
   TimeToStruct(utcTime, utcDt);
   int gmtHour = utcDt.hour;

   // Session-dependent thresholds (GMT times)
   double maxAllowed;
   string sessionName;

   if(gmtHour >= 13 && gmtHour < 16)
   {
      // London-NY Overlap (13:00-16:00 GMT) - PRIME TIME
      maxAllowed = 0.80;
      sessionName = "London-NY Overlap";
   }
   else if((gmtHour >= 8 && gmtHour < 13) || (gmtHour >= 16 && gmtHour < 17))
   {
      // London (08:00-13:00) or NY (16:00-17:00) - GOOD
      maxAllowed = 1.00;
      sessionName = (gmtHour < 13) ? "London" : "New York";
   }
   else if(gmtHour >= 7 && gmtHour < 8)
   {
      // Asian-London Overlap (07:00-08:00 GMT) - FAIR
      maxAllowed = 1.20;
      sessionName = "Asian-London Overlap";
   }
   else
   {
      // Asian / Off-hours - POOR
      maxAllowed = 1.50;
      sessionName = "Asian/Off-hours";
   }

   if(currentSpreadUSD > maxAllowed)
   {
      static datetime lastLog = 0;
      if(TimeCurrent() - lastLog >= 60)
      {
         Print("⛔ 🪙 METALS SPREAD REJECTED [", sessionName, "]: ",
               DoubleToString(currentSpreadUSD, 2), " USD > ",
               DoubleToString(maxAllowed, 2), " USD (Max allowed)");
         lastLog = TimeCurrent();
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
   else if(InpTPMode == 4) tpMode = "Volatility (" + DoubleToString(InpVolatilityTP_Mult, 1) + "x ATR)";

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
//| Check Killzone Time                                               |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Get Active Killzone                                               |
//+------------------------------------------------------------------+
ENUM_KILLZONE GetActiveKillzone()
{
   if(!InpUseKillzoneFilter) return KILLZONE_NONE;

   datetime utcTime = TimeCurrent() - (InpBrokerUTCOffset * 3600);
   MqlDateTime utcDt;
   TimeToStruct(utcTime, utcDt);

   // EST Calculation (Standard UTC-5)
   int estHour = (utcDt.hour - 5 + 24) % 24;

   // 1. Asian Session (20:00 - 00:00 EST)
   if(InpEnableAsianKZ && (estHour >= 20 || estHour < 0)) return KILLZONE_ASIAN;

   // 2. London Open (02:00 - 05:00 EST)
   if(InpEnableLondonOpenKZ && (estHour >= 2 && estHour < 5)) return KILLZONE_LONDON_OPEN;

   // 3. NY Open (07:00 - 10:00 EST)
   if(InpEnableNYKZ && (estHour >= 7 && estHour < 10)) return KILLZONE_NY;

   // 4. London Close (10:00 - 12:00 EST)
   if(InpEnableLondonCloseKZ && (estHour >= 10 && estHour < 12)) return KILLZONE_LONDON_CLOSE;

   return KILLZONE_NONE;
}

//+------------------------------------------------------------------+
//| Check Killzone Time (Wrapper)                                     |
//+------------------------------------------------------------------+
bool CheckKillzone()
{
   return GetActiveKillzone() != KILLZONE_NONE;
}


