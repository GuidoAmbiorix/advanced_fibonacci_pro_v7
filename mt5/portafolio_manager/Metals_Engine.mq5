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

// Chameleon Multi-Strategy System
#include "Include\Strategies\BaseStrategy.mqh"
#include "Include\Strategies\SniperStrategy.mqh"
#include "Include\Strategies\RubberBandStrategy.mqh"
#include "Include\Strategies\BreakoutStrategy.mqh"
#include "Include\Strategy_Performance_Tracker.mqh"

// Smart Money Concepts Modules
// PHASE 1: Moved to custom indicators
// #include "Include\SMC_StructureBreak.mqh"
// #include "Include\SMC_OrderBlocks.mqh"
// #include "Include\SMC_FairValueGap.mqh"
// #include "Include\SMC_LiquiditySweep.mqh"

// Multi-Timeframe and Filters
// PHASE 2: MTF and Session moved to custom indicators
// #include "Include\MTF_Confluence.mqh"
#include "Include\NewsFilter.mqh"
// #include "Include\SessionOptimizer.mqh"  // 🪙 METALS: Session scoring
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
// PHASE 1&2: Advanced modules moved to custom indicators
// #include "Include\Advanced\VolumeAnalysis.mqh"
// #include "Include\Advanced\Divergence.mqh"
// #include "Include\Advanced\Inst_Concepts.mqh"

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

input group "======= CHAMELEON MULTI-STRATEGY SYSTEM ======="
input bool              InpEnableChameleon = true;        // Enable Chameleon System
input bool              InpEnableSniper = true;           // Enable Sniper Strategy
input bool              InpEnableRubberBand = true;       // Enable Rubber Band Strategy
input bool              InpEnableBreakout = true;         // Enable Breakout Strategy
input bool              InpAutoSwitchStrategy = true;     // Auto-Switch Based on Phase
input bool              InpUseLegacyMode = false;         // Use Legacy Confluence Mode

input group "======= MARKET PHASE ANALYZER ======="
input int               InpLookbackPeriod = 50;           // Autocorrelation Lookback
input double            InpTrendThreshold = 0.2;          // Autocorrelation Threshold
input int               InpADXPeriod = 14;                // ADX Period
input double            InpADXTrendLevel = 25.0;          // ADX Trend Level
input double            InpADXRangeLevel = 20.0;          // ADX Range Level
input int               InpBBPeriod = 20;                 // BB Period
input double            InpBBDeviation = 2.0;             // BB Deviation
input int               InpBBExpansionPercentile = 88;    // BB Expansion Percentile (lower for XAUUSD)
input int               InpMinVolume = 150;               // Minimum Volume (higher for XAUUSD)
input int               InpSwingLookbackPhase = 50;       // Phase Swing Lookback

input group "======= FIBONACCI GOLDEN POCKET ======="
input int               InpZigZagDepth = 18;              // ZigZag Depth (larger for XAUUSD)
input int               InpZigZagDeviation = 7;           // ZigZag Deviation
input int               InpZigZagBackstep = 3;            // ZigZag Backstep
input int               InpMaxSwingAge = 100;             // Max Swing Age
input bool              InpUseGoldenPocket618 = true;     // Use 61.8-78.6% Zone
input bool              InpDetectFakeouts = true;         // Detect Fakeouts
input int               InpMinSwingSize = 200;            // Min Swing Size (200 pips for XAUUSD)

input group "======= SESSION OPTIMIZER (METALS SPECIFIC) ======="
input int               InpOptimalSession = 2;            // Optimal Session (2=London-NY overlap)
input bool              InpAvoidAsianSession = true;      // Avoid Asian Session
input bool              InpAvoidLondonClose = false;      // Avoid London Close
input int               InpSessionScoreMin = 2;           // Min Session Quality (2=Good)

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
input ENUM_TIMEFRAMES   InpHTF = PERIOD_H4;               // Higher Timeframe
input ENUM_TIMEFRAMES   InpMTF = PERIOD_H1;               // Medium Timeframe
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
input bool              InpUseSessionOptimizer = true;    // 🪙 METALS: Use Session Optimizer

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

// MODULE OBJECTS
CFailSafe         failSafe;
// PHASE 4: Market Regime moved to custom indicator
// CMarketRegime     regime;
CKillSwitch       killSwitch;
CLearningEngine   learning;
CGovernorAllocator allocator;

// ADVANCED MODULE OBJECTS
// PHASE 1&2: Advanced modules moved to custom indicators
// CVolumeAnalysis   volumeAnalysis;
// CDivergence       divergence;
// CBreakerBlocks    breakerBlocks;
// CMacroWindows     macroWindows;
// CPowerOf3         powerOf3;
// CWyckoff          wyckoff;

// Forward Declaration
double CalculateConfluenceScore(int direction);

// PHASE 1: SMC MODULE OBJECTS - Replaced with custom indicators
// CSMCStructureBreak  smcStructure;
// CSMCOrderBlocks     smcOrderBlocks;
// CSMCFairValueGap    smcFVG;
// CSMCLiquiditySweep  smcLiquidity;

// PHASE 1 & 2: Custom Indicator Handles
int hSMC_Confluence = INVALID_HANDLE;       // SMC Confluence Indicator
int hVolume_Confluence = INVALID_HANDLE;    // Volume Confluence Indicator
int hMTF_Confluence = INVALID_HANDLE;       // MTF Confluence Indicator
int hICT_Advanced = INVALID_HANDLE;         // ICT Advanced Indicator
int hDivergence = INVALID_HANDLE;           // Divergence Indicator
int hSession_Optimizer = INVALID_HANDLE;    // 🪙 Session Optimizer (Metals)

// PHASE 4: Additional Custom Indicator Handles
int hKillzone_Detector = INVALID_HANDLE;    // Killzone Detector Indicator
int hNews_Filter = INVALID_HANDLE;          // News Filter Indicator
int hMarket_Regime = INVALID_HANDLE;        // Market Regime Indicator

// ADVANCED FILTER OBJECTS
// PHASE 2: MTF and Session moved to custom indicators
// CMTFConfluence      mtfAnalysis;
// PHASE 4: News Filter moved to custom indicator
// CNewsFilter         newsFilter;
// CSessionOptimizer   sessionOptimizer;  // 🪙 METALS: Session scoring
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

// CHAMELEON MULTI-STRATEGY OBJECTS
int hMarketPhase = INVALID_HANDLE;
int hFibGolden = INVALID_HANDLE;
CSniperStrategy sniperStrategy;
CRubberBandStrategy rubberBandStrategy;
CBreakoutStrategy breakoutStrategy;
CStrategyTracker strategyTracker;
int g_activeStrategy = 0;  // 0=Legacy, 1=Sniper, 2=RubberBand, 3=Breakout

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

   // PHASE 1: Initialize Custom Indicators instead of SMC Modules
   if(InpUseSMC)
   {
      hSMC_Confluence = iCustom(_Symbol, PERIOD_CURRENT,
         "Indicators\\SMC_Confluence",
         InpSMC_SwingLookback,     // InpSwingLookback
         InpSMC_MinImpulseATR,     // InpMinImpulseATR
         InpSMC_MinFVG_ATR,        // InpMinFVG_ATR
         5,                        // InpMaxOrderBlocks
         10);                      // InpMaxFVGs

      if(hSMC_Confluence == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create SMC_Confluence indicator");
         return INIT_FAILED;
      }

      // Wait for indicator to be ready
      if(!WaitForIndicator(hSMC_Confluence, 3))
      {
         Print("ERROR: SMC_Confluence indicator failed to initialize");
         return INIT_FAILED;
      }

      Print("✓ SMC_Confluence indicator initialized");
   }

   // PHASE 1: Initialize Volume Confluence Indicator
   hVolume_Confluence = iCustom(_Symbol, PERIOD_CURRENT,
      "Indicators\\Volume_Confluence",
      20,    // InpRVOL_Lookback
      5);    // InpMF_Period

   if(hVolume_Confluence == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Volume_Confluence indicator");
      return INIT_FAILED;
   }

   if(!WaitForIndicator(hVolume_Confluence, 3))
   {
      Print("ERROR: Volume_Confluence indicator failed to initialize");
      return INIT_FAILED;
   }

   Print("✓ Volume_Confluence indicator initialized");

   // PHASE 2: Initialize MTF Confluence Indicator
   if(InpUseMTF)
   {
      hMTF_Confluence = iCustom(_Symbol, PERIOD_CURRENT,
         "Indicators\\MTF_Confluence",
         InpHTF, InpMTF, PERIOD_CURRENT, InpMTF_EMAPeriod, 14);

      if(hMTF_Confluence == INVALID_HANDLE || !WaitForIndicator(hMTF_Confluence, 3))
         Print("Warning: MTF_Confluence indicator failed to load");
      else
         Print("✓ MTF_Confluence indicator initialized");
   }

   // PHASE 2: Initialize ICT Advanced Indicator
   if(InpUseSMC)
   {
      hICT_Advanced = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\ICT_Advanced");

      if(hICT_Advanced == INVALID_HANDLE || !WaitForIndicator(hICT_Advanced, 3))
         Print("Warning: ICT_Advanced indicator failed to load");
      else
         Print("✓ ICT_Advanced indicator initialized");
   }

   // PHASE 2: Initialize Divergence Indicator
   hDivergence = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Divergence", InpRSI_Period, 10);

   if(hDivergence == INVALID_HANDLE || !WaitForIndicator(hDivergence, 3))
      Print("Warning: Divergence indicator failed to load");
   else
      Print("✓ Divergence indicator initialized");

   // PHASE 2: 🪙 METALS: Initialize Session Optimizer Indicator
   if(InpUseSessionOptimizer)
   {
      hSession_Optimizer = iCustom(_Symbol, PERIOD_CURRENT,
         "Indicators\\Session_Optimizer", InpBrokerUTCOffset);

      if(hSession_Optimizer == INVALID_HANDLE || !WaitForIndicator(hSession_Optimizer, 3))
         Print("Warning: Session_Optimizer indicator failed to load");
      else
         Print("✓ 🪙 Session_Optimizer indicator initialized for ", _Symbol);
   }

   // PHASE 4: Initialize Killzone Detector Indicator
   hKillzone_Detector = iCustom(_Symbol, PERIOD_CURRENT,
      "Indicators\\Killzone_Detector",
      InpBrokerUTCOffset, InpEnableAsianKZ, InpEnableLondonOpenKZ,
      InpEnableNYKZ, InpEnableLondonCloseKZ);

   if(hKillzone_Detector == INVALID_HANDLE)
      Print("Warning: Killzone_Detector indicator failed to load");
   else
      Print("✓ Killzone_Detector indicator initialized");

   // PHASE 4: Initialize News Filter Indicator
   if(InpUseNewsFilter)
   {
      hNews_Filter = iCustom(_Symbol, PERIOD_CURRENT,
         "Indicators\\News_Filter",
         InpNewsMinutesBefore, InpNewsMinutesAfter, true,
         InpEnableVolatilityFilter, InpVolatilityThreshold, InpVolatilitySpikeCooldown);

      if(hNews_Filter == INVALID_HANDLE)
         Print("Warning: News_Filter indicator failed to load");
      else
         Print("✓ News_Filter indicator initialized");
   }

   // PHASE 4: Initialize Market Regime Indicator
   hMarket_Regime = iCustom(_Symbol, PERIOD_CURRENT,
      "Indicators\\Market_Regime", 14, 50);

   if(hMarket_Regime == INVALID_HANDLE)
      Print("Warning: Market_Regime indicator failed to load");
   else
      Print("✓ Market_Regime indicator initialized");

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

   // ===========================================
   // CHAMELEON MULTI-STRATEGY SYSTEM INITIALIZATION
   // ===========================================
   if(InpEnableChameleon && !InpUseLegacyMode)
   {
      Print("===========================================");
      Print("  CHAMELEON MULTI-STRATEGY SYSTEM");
      Print("===========================================");

      // Initialize Market Phase Analyzer indicator
      hMarketPhase = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Market_Phase_Analyzer",
                            InpLookbackPeriod,
                            InpTrendThreshold,
                            InpADXPeriod,
                            InpADXTrendLevel,
                            InpADXRangeLevel,
                            InpBBPeriod,
                            InpBBDeviation,
                            InpBBExpansionPercentile,
                            InpMinVolume,
                            InpSwingLookbackPhase);

      if(hMarketPhase == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create Market_Phase_Analyzer indicator");
         return INIT_FAILED;
      }
      Print("  Market Phase Analyzer: ACTIVE");

      // Initialize Fibonacci Golden Pocket indicator
      hFibGolden = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Fibonacci_GoldenPocket",
                          InpZigZagDepth,
                          InpZigZagDeviation,
                          InpZigZagBackstep,
                          InpMaxSwingAge,
                          InpUseGoldenPocket618,
                          InpDetectFakeouts,
                          InpMinSwingSize);

      if(hFibGolden == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create Fibonacci_GoldenPocket indicator");
         return INIT_FAILED;
      }
      Print("  Fibonacci Golden Pocket: ACTIVE");

      // Initialize strategy objects (with Session_Optimizer handle for Metals)
      if(!sniperStrategy.Init(hMarketPhase, hFibGolden, INVALID_HANDLE, INVALID_HANDLE, hSession_Optimizer, hRSI))
      {
         Print("ERROR: Failed to initialize Sniper strategy");
         return INIT_FAILED;
      }
      sniperStrategy.SetMagicNumber(InpMagicNumber);
      sniperStrategy.SetMinConfluence(14.0);  // XAUUSD: Higher threshold
      Print("  Sniper Strategy: ", InpEnableSniper ? "ENABLED" : "DISABLED");

      if(!rubberBandStrategy.Init(hMarketPhase, hFibGolden, INVALID_HANDLE, INVALID_HANDLE, hSession_Optimizer, hRSI))
      {
         Print("ERROR: Failed to initialize Rubber Band strategy");
         return INIT_FAILED;
      }
      rubberBandStrategy.SetMagicNumber(InpMagicNumber);
      rubberBandStrategy.SetMinConfluence(12.0);  // XAUUSD: Higher threshold
      Print("  Rubber Band Strategy: ", InpEnableRubberBand ? "ENABLED" : "DISABLED");

      if(!breakoutStrategy.Init(hMarketPhase, hFibGolden, INVALID_HANDLE, INVALID_HANDLE, hSession_Optimizer, hRSI))
      {
         Print("ERROR: Failed to initialize Breakout strategy");
         return INIT_FAILED;
      }
      breakoutStrategy.SetMagicNumber(InpMagicNumber);
      breakoutStrategy.SetMinConfluence(15.0);  // XAUUSD: Higher threshold
      Print("  Breakout Strategy: ", InpEnableBreakout ? "ENABLED" : "DISABLED");

      // Initialize strategy performance tracker
      if(!strategyTracker.Init(_Symbol))
      {
         Print("WARNING: Strategy Performance Tracker initialization failed");
      }
      else
      {
         Print("  Strategy Performance Tracker: ACTIVE");
      }

      // Set GlobalVariables for Chameleon dashboard
      GlobalVariableSet(GV_CHAMELEON_ENABLED + _Symbol, 1.0);
      GlobalVariableSet(GV_STRATEGY_PREFIX + _Symbol, 0.0);  // Start with Legacy

      Print("===========================================");
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

   // PHASE 1 & 2: Release custom indicator handles
   if(hSMC_Confluence != INVALID_HANDLE) IndicatorRelease(hSMC_Confluence);
   if(hVolume_Confluence != INVALID_HANDLE) IndicatorRelease(hVolume_Confluence);
   if(hMTF_Confluence != INVALID_HANDLE) IndicatorRelease(hMTF_Confluence);
   if(hICT_Advanced != INVALID_HANDLE) IndicatorRelease(hICT_Advanced);
   if(hDivergence != INVALID_HANDLE) IndicatorRelease(hDivergence);
   if(hSession_Optimizer != INVALID_HANDLE) IndicatorRelease(hSession_Optimizer);

   // PHASE 4: Release custom indicator handles
   if(hKillzone_Detector != INVALID_HANDLE) IndicatorRelease(hKillzone_Detector);
   if(hNews_Filter != INVALID_HANDLE) IndicatorRelease(hNews_Filter);
   if(hMarket_Regime != INVALID_HANDLE) IndicatorRelease(hMarket_Regime);

   // Release Chameleon indicator handles
   if(hMarketPhase != INVALID_HANDLE) IndicatorRelease(hMarketPhase);
   if(hFibGolden != INVALID_HANDLE) IndicatorRelease(hFibGolden);

   // Save learning data before exit
   if(InpEnableLearning)
   {
      learning.Deinit();
      patternMemory.Deinit();
   }

   // Cleanup global variables for this symbol
   GlobalVariableDel(GV_CHAMELEON_ENABLED + _Symbol);
   GlobalVariableDel(GV_STRATEGY_PREFIX + _Symbol);
   GlobalVariableDel(GV_PHASE_PREFIX + _Symbol);
   GlobalVariableDel(GV_SCORE_PREFIX + _Symbol);
   GlobalVariableDel(GV_REQ_PREFIX + _Symbol);
   GlobalVariableDel(GV_DIR_PREFIX + _Symbol);
   GlobalVariableDel(GV_KZ_PREFIX + _Symbol);
   GlobalVariableDel(GV_BAROPEN_PREFIX + _Symbol);
   GlobalVariableDel(GV_PERIOD_PREFIX + _Symbol);

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

//+------------------------------------------------------------------+
//| PHASE 1: Helper function to wait for indicator initialization   |
//+------------------------------------------------------------------+
bool WaitForIndicator(int handle, int attempts = 3)
{
   if(handle == INVALID_HANDLE) return false;

   for(int i = 0; i < attempts; i++)
   {
      double buf[1];
      if(CopyBuffer(handle, 0, 0, 1, buf) > 0)
         return true;
      Sleep(100);
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
//| Select Active Strategy Based on Market Phase                     |
//+------------------------------------------------------------------+
void SelectStrategy()
{
   if(!InpEnableChameleon || InpUseLegacyMode) {
      g_activeStrategy = 0;  // Legacy mode
      return;
   }

   // Read market phase from indicator
   double phaseBuf[1];
   if(CopyBuffer(hMarketPhase, 0, 0, 1, phaseBuf) <= 0) {
      g_activeStrategy = 0;  // Fallback to legacy
      return;
   }

   MARKET_PHASE currentPhase = (MARKET_PHASE)((int)phaseBuf[0]);

   // Store phase in GlobalVariable for Governor
   GlobalVariableSet(GV_PHASE_PREFIX + _Symbol, (double)currentPhase);

   // Don't trade in dormant phase
   if(currentPhase == PHASE_DORMANT) {
      g_activeStrategy = 0;
      static datetime lastDormantWarning = 0;
      if(TimeCurrent() - lastDormantWarning > 1800) {  // Log every 30 minutes
         Print("Market Phase: DORMANT - No trading");
         lastDormantWarning = TimeCurrent();
      }
      return;
   }

   // Select strategy based on phase
   int previousStrategy = g_activeStrategy;

   if(currentPhase == PHASE_TRENDING && InpEnableSniper) {
      if(!strategyTracker.ShouldDisableStrategy(1)) {
         g_activeStrategy = 1;  // Sniper
      } else {
         g_activeStrategy = 0;  // Disabled, use legacy
      }
   }
   else if(currentPhase == PHASE_RANGING && InpEnableRubberBand) {
      if(!strategyTracker.ShouldDisableStrategy(2)) {
         g_activeStrategy = 2;  // Rubber Band
      } else {
         g_activeStrategy = 0;  // Disabled, use legacy
      }
   }
   else if(currentPhase == PHASE_VOLATILE && InpEnableBreakout) {
      if(!strategyTracker.ShouldDisableStrategy(3)) {
         g_activeStrategy = 3;  // Breakout
      } else {
         g_activeStrategy = 0;  // Disabled, use legacy
      }
   }
   else {
      g_activeStrategy = 0;  // Fallback to legacy
   }

   // Log strategy switches
   if(previousStrategy != g_activeStrategy) {
      string strategyNames[] = {"Legacy", "Sniper", "RubberBand", "Breakout"};
      string phaseNames[] = {"DORMANT", "TRENDING", "RANGING", "VOLATILE", "UNDEFINED"};

      Print("STRATEGY SWITCH: ", strategyNames[previousStrategy], " -> ",
            strategyNames[g_activeStrategy], " (Phase: ", phaseNames[(int)currentPhase], ")");

      // Update GlobalVariable for dashboard
      GlobalVariableSet(GV_STRATEGY_PREFIX + _Symbol, (double)g_activeStrategy);
   }
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

   // Manage existing positions (Trailing, TP, BreakEven)
   ManagePositions();

   // Update Indicators & Modules
   if(!UpdateIndicators()) return;

   // --- UPDATE ALL MODULES ON NEW BAR ---
   UpdateModules();

   // --- MODULE: CHAMELEON STRATEGY SELECTION ---
   if(InpEnableChameleon && !InpUseLegacyMode)
   {
      SelectStrategy();
   }

   // --- MODULE: MARKET REGIME ---
   // PHASE 4: Get regime from Market_Regime indicator
   if(hMarket_Regime != INVALID_HANDLE)
   {
      double regimeBuf[1];
      if(CopyBuffer(hMarket_Regime, 0, 0, 1, regimeBuf) > 0)
         g_currentRegime = (MARKET_REGIME)regimeBuf[0];
      else
         g_currentRegime = REGIME_UNKNOWN;
   }
   else
   {
      g_currentRegime = REGIME_UNKNOWN;
   }
   // g_currentRegime check moved down to allow score calculation for visibility

   // OPTIMIZATION: Calculate confluence once per bar (expensive operation)
   // Moved here to ensure visibility in logs even if trading is blocked
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != g_lastScoreCalcTime)
   {
      // Use Chameleon strategy scoring if active, otherwise use legacy
      if(g_activeStrategy > 0)
      {
         // Chameleon mode: Use strategy-specific scoring
         switch(g_activeStrategy)
         {
            case 1:  // Sniper
               if(sniperStrategy.CheckEntry(1))
                  g_cachedBuyScore = sniperStrategy.GetConfluenceScore(1);
               else
                  g_cachedBuyScore = 0;

               if(sniperStrategy.CheckEntry(-1))
                  g_cachedSellScore = sniperStrategy.GetConfluenceScore(-1);
               else
                  g_cachedSellScore = 0;
               break;

            case 2:  // Rubber Band
               if(rubberBandStrategy.CheckEntry(1))
                  g_cachedBuyScore = rubberBandStrategy.GetConfluenceScore(1);
               else
                  g_cachedBuyScore = 0;

               if(rubberBandStrategy.CheckEntry(-1))
                  g_cachedSellScore = rubberBandStrategy.GetConfluenceScore(-1);
               else
                  g_cachedSellScore = 0;
               break;

            case 3:  // Breakout
               if(breakoutStrategy.CheckEntry(1))
                  g_cachedBuyScore = breakoutStrategy.GetConfluenceScore(1);
               else
                  g_cachedBuyScore = 0;

               if(breakoutStrategy.CheckEntry(-1))
                  g_cachedSellScore = breakoutStrategy.GetConfluenceScore(-1);
               else
                  g_cachedSellScore = 0;
               break;

            default:  // Fallback to legacy
               g_cachedBuyScore = CalculateConfluenceScore(1);
               g_cachedSellScore = CalculateConfluenceScore(-1);
               break;
         }
      }
      else
      {
         // Legacy mode
         g_cachedBuyScore = CalculateConfluenceScore(1);
         g_cachedSellScore = CalculateConfluenceScore(-1);
      }
      g_lastScoreCalcTime = currentBarTime;

      // Publish scores to global variables for Governor ranking
      double bestScore = MathMax(g_cachedBuyScore, g_cachedSellScore);
      int direction = (g_cachedBuyScore > g_cachedSellScore) ? 1 : -1;

      GlobalVariableSet(GV_SCORE_PREFIX + _Symbol, bestScore);
      GlobalVariableSet(GV_REQ_PREFIX + _Symbol, InpMinConfluenceEntry);
      GlobalVariableSet(GV_DIR_PREFIX + _Symbol, (double)direction);
      GlobalVariableSet(GV_KZ_PREFIX + _Symbol, CheckKillzone() ? 1.0 : 0.0);
      GlobalVariableSet(GV_BAROPEN_PREFIX + _Symbol, (double)iTime(_Symbol, PERIOD_CURRENT, 0));
      GlobalVariableSet(GV_PERIOD_PREFIX + _Symbol, (double)PeriodSeconds(PERIOD_CURRENT));

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
   // PHASE 4: Check trading allowed from News_Filter indicator (Buffer 4)
   if(InpUseNewsFilter && hNews_Filter != INVALID_HANDLE)
   {
      double tradingAllowedBuf[1], newsEventBuf[1], volSpikeBuf[1];
      if(CopyBuffer(hNews_Filter, 4, 0, 1, tradingAllowedBuf) > 0 &&
         CopyBuffer(hNews_Filter, 0, 0, 1, newsEventBuf) > 0 &&
         CopyBuffer(hNews_Filter, 3, 0, 1, volSpikeBuf) > 0)
      {
         if(tradingAllowedBuf[0] == 0.0)
         {
            static datetime lastNewsLog = 0;
            if(TimeCurrent() - lastNewsLog > 300)
            {
               string newsStatus = (newsEventBuf[0] == 1.0) ? "News event active" : "Volatility spike detected";
               Print("🚫 BLOCKED: News Filter - ", newsStatus);
               lastNewsLog = TimeCurrent();
            }
            return;
         }
      }
   }

   // --- MODULE: KELLY POSITION SIZER (DD LIMITS) ---
   if(InpUseKelly && !kellySizer.IsTradingAllowed())
   {
      static datetime lastKellyLog = 0;
      if(TimeCurrent() - lastKellyLog > 300)
      {
         Print("🚫 BLOCKED: Kelly Sizer - Drawdown limits exceeded");
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
      // Get alignment score from MTF_Confluence indicator (Buffer 3: 0-100%)
      double alignBuf[1];
      if(CopyBuffer(hMTF_Confluence, 3, 1, 1, alignBuf) > 0)
      {
         double alignment = alignBuf[0];

         // If alignment < 50% (trading against HTF), apply penalty
         if(alignment < 0.5)
         {
            buyScore -= 1.5;
            sellScore -= 1.5;
         }
      }
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
         double newsMultiplier = 1.0;
         if(InpUseNewsFilter && hNews_Filter != INVALID_HANDLE)
         {
            double tradingAllowedBuf[1], minToNewsBuf[1];
            if(CopyBuffer(hNews_Filter, 4, 0, 1, tradingAllowedBuf) > 0 &&
               CopyBuffer(hNews_Filter, 1, 0, 1, minToNewsBuf) > 0)
            {
               if(tradingAllowedBuf[0] == 0.0) newsMultiplier = 0.0;  // In news window
               else if(minToNewsBuf[0] <= InpNewsMinutesBefore * 2) newsMultiplier = 0.5;
            }
         }
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
          // FIX: Wire up dynamic threshold (Phase 5)
          double minEntry = InpMinConfluenceEntry;  // Base threshold from .set file

          // Use adaptive threshold if enabled
          if(InpEnableAdaptiveFilters && adaptiveFilter.IsAdaptationEnabled())
          {
             // Create confluence factors for dynamic threshold calculation
             ENUM_KILLZONE currentKZ = KILLZONE_NONE;
             ConfluenceFactors thresholdFactors;
             BuildConfluenceFactors(thresholdFactors, bestDirection, bestScore);

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

       // Update modules (backup in case ManagePositions missed it)
       killSwitch.OnTradeClosed(rOutcome);
       learning.OnTradeClosed(ticket);

       // Update Kelly sizer
       if(InpUseKelly)
       {
          kellySizer.AddTradeResult(rOutcome, quality);
       }

       // Update Chameleon strategy performance tracker
       if(InpEnableChameleon && !InpUseLegacyMode && g_activeStrategy > 0)
       {
          strategyTracker.OnTradeClose(g_activeStrategy, profit, dollarRisk, MathAbs(profit));
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
   // PHASE 1 & 2: All modules now handled by custom indicators
   // No manual updates needed - indicators update automatically

   // PHASE 4: News filter now handled by News_Filter indicator
   // if(InpUseNewsFilter) newsFilter.Update();  // Commented out - handled by indicator

   // OPTIMIZATION: Update filters only if enabled
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
   if(TimeCurrent() - lastDebug > 300) 
   {
      Print("DEBUG Indicators: EMA=", g_EMA, " ATR=", g_ATR, " RSI=", g_RSI, " Price=", currentPrice);
      lastDebug = TimeCurrent();
   }

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
       // PHASE 1: Use custom SMC_Confluence indicator
       // Combined score from all 4 SMC modules in one call
       double smcBuf[1];
       if(CopyBuffer(hSMC_Confluence, 4, 1, 1, smcBuf) > 0)  // Buffer 4 = Combined Score
       {
           // The indicator returns positive for bullish, negative for bearish
           double smcScore = smcBuf[0];

           // Apply the score based on direction alignment
           if((direction == 1 && smcScore > 0) || (direction == -1 && smcScore < 0))
           {
               score += MathAbs(smcScore);  // Max ~5.5 pts (1.5+1.5+1.0+1.5)
           }
       }

       // PHASE 2: Advanced ICT Concepts from custom indicator
       double ictBuf[1];
       if(CopyBuffer(hICT_Advanced, 3, 0, 1, ictBuf) > 0)  // Buffer 3 = Combined Score
       {
           double ictScore = ictBuf[0];
           // Apply score based on direction alignment
           if((direction == 1 && ictScore > 0) || (direction == -1 && ictScore < 0))
           {
               score += MathAbs(ictScore);  // Max ~6.0 pts
           }
       }
   }


   // ============ 4. ADVANCED CONFIRMATIONS (Max ~5-10 pts) ============

   // PHASE 1: Institutional Volume - 4.0 pts (RVOL + Money Flow) from custom indicator
   double volBuf[1];
   int volBufferIdx = (direction == 1) ? 2 : 3;  // Buffer 2 = Buy Score, Buffer 3 = Sell Score
   if(CopyBuffer(hVolume_Confluence, volBufferIdx, 0, 1, volBuf) > 0)
   {
       score += volBuf[0];  // Max 4.0 pts
   }

   // PHASE 2: Multi-Timeframe - 2.0 pts from custom indicator
   if(InpUseMTF && hMTF_Confluence != INVALID_HANDLE)
   {
       double mtfBuf[1];
       int mtfBufferIdx = (direction == 1) ? 4 : 5;  // Buffer 4 = Buy Score, Buffer 5 = Sell Score
       if(CopyBuffer(hMTF_Confluence, mtfBufferIdx, 0, 1, mtfBuf) > 0)
       {
           score += mtfBuf[0];  // Max 2.0 pts
       }
   }

   // PHASE 2: Divergence - 2.0 pts from custom indicator
   double divBuf[1];
   if(CopyBuffer(hDivergence, 2, 0, 1, divBuf) > 0)  // Buffer 2 = Combined Score
   {
       double divergenceScore = divBuf[0];
       // Score is positive for bullish div, negative for bearish
       if((direction == 1 && divergenceScore > 0) || (direction == -1 && divergenceScore < 0))
       {
           score += MathAbs(divergenceScore) * 2.0;  // Scale and apply
       }
   }

   // PHASE 2: 🪙 METALS: Session Bonus - 2.5-3.0 pts from custom indicator
   if(InpUseSessionOptimizer && hSession_Optimizer != INVALID_HANDLE)
   {
       double sessBuf[1];
       if(CopyBuffer(hSession_Optimizer, 2, 0, 1, sessBuf) > 0)  // Buffer 2 = Metals Score
       {
           score += sessBuf[0];  // Max 3.0 pts
       }
   } 

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
           // Get divergence score from Divergence indicator (Buffer 2: Combined Score 0-2.0)
           double divBuf[1];
           double divergenceScore = 0.0;
           if(CopyBuffer(hDivergence, 2, 1, 1, divBuf) > 0)
              divergenceScore = MathAbs(divBuf[0]);

           if(divergenceScore < 0.5)
           {
               score -= 2.0;
               if(score < 0) score = 0;
           }
       }
   }

   // ============ 4. 🪙 METALS: SESSION SCORING (Max ~3.0 pts) ============
   // NOTE: Session scoring is now handled by Session_Optimizer custom indicator
   // See lines 2231-2237 where hSession_Optimizer is used
   // This old sessionOptimizer object code is no longer needed

   // DEBUG: Print final score
   static datetime lastScoreDebug = 0;
   if(TimeCurrent() - lastScoreDebug > 300)
   {
      Print("DEBUG Score [", (direction == 1 ? "BUY" : "SELL"), "]: ", DoubleToString(score, 2), "/30");
      lastScoreDebug = TimeCurrent();
   }

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
   if(InpUseNewsFilter && hNews_Filter != INVALID_HANDLE)
   {
      double tradingAllowedBuf[1], newsEventBuf[1], volSpikeBuf[1];
      if(CopyBuffer(hNews_Filter, 4, 0, 1, tradingAllowedBuf) > 0 &&
         CopyBuffer(hNews_Filter, 0, 0, 1, newsEventBuf) > 0 &&
         CopyBuffer(hNews_Filter, 3, 0, 1, volSpikeBuf) > 0)
      {
         if(newsEventBuf[0] == 1.0) tradingStatus = "NEWS BLOCKED";
         else if(volSpikeBuf[0] == 1.0) tradingStatus = "VOLATILITY SPIKE";
      }
   }
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
   if(InpUseNewsFilter && hNews_Filter != INVALID_HANDLE)
   {
      double newsEventBuf[1], minToNewsBuf[1], volSpikeBuf[1];
      if(CopyBuffer(hNews_Filter, 0, 0, 1, newsEventBuf) > 0 &&
         CopyBuffer(hNews_Filter, 1, 0, 1, minToNewsBuf) > 0 &&
         CopyBuffer(hNews_Filter, 3, 0, 1, volSpikeBuf) > 0)
      {
         if(volSpikeBuf[0] == 1.0)
            txt += "NEWS: VOLATILITY SPIKE!\n";
         else if(newsEventBuf[0] == 1.0)
            txt += "NEWS: BLOCKED (Event active)\n";
         else if(minToNewsBuf[0] < 999999)
            txt += "NEWS: OK (Next: " + IntegerToString((int)minToNewsBuf[0]) + "m)\n";
         else
            txt += "NEWS: CLEAR\n";
      }
   }

   txt += "-------------------------------------------\n";

   // SMC Status
   if(InpUseSMC)
   {
      // PHASE 1: Display SMC scores from custom indicator
      double smcBuf[1];
      if(CopyBuffer(hSMC_Confluence, 4, 1, 1, smcBuf) > 0)
         txt += "SMC Score: " + DoubleToString(smcBuf[0], 2) + " (Structure+OB+FVG+Liq)\n";
   }

   // MTF Status
   if(InpUseMTF)
   {
      // Get MTF data from indicator
      double htfBuf[1], mtfBuf[1], ltfBuf[1], alignBuf[1];
      if(CopyBuffer(hMTF_Confluence, 0, 1, 1, htfBuf) > 0 &&
         CopyBuffer(hMTF_Confluence, 1, 1, 1, mtfBuf) > 0 &&
         CopyBuffer(hMTF_Confluence, 2, 1, 1, ltfBuf) > 0 &&
         CopyBuffer(hMTF_Confluence, 3, 1, 1, alignBuf) > 0)
      {
         txt += "MTF: HTF=" + DoubleToString(htfBuf[0], 1) +
                " MTF=" + DoubleToString(mtfBuf[0], 1) +
                " LTF=" + DoubleToString(ltfBuf[0], 1) +
                " Align=" + DoubleToString(alignBuf[0]*100, 0) + "%\n";
      }
   }

   txt += "-------------------------------------------\n";
   txt += "BUY Score: " + DoubleToString(buyS, 1) + "/30\n";
   txt += "SELL Score: " + DoubleToString(sellS, 1) + "/30\n";
   txt += "Entry Min: " + DoubleToString(InpMinConfluenceEntry, 1) + "/30 (Good) | " + DoubleToString(InpMinConfluenceEntry + 2.0, 1) + " (Strong) | " + DoubleToString(InpMinConfluenceEntry + 4.0, 1) + " (Elite)\n";

   // Chameleon Strategy Display
   if(InpEnableChameleon && !InpUseLegacyMode)
   {
      string strategyNames[] = {"Legacy", "Sniper", "RubberBand", "Breakout"};
      txt += "CHAMELEON: " + strategyNames[g_activeStrategy] + "\n";

      // Show strategy performance
      if(g_activeStrategy > 0)
      {
         txt += strategyTracker.GetDashboardText();
      }
   }

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
//| Get Active Killzone (PHASE 4: Now uses Killzone_Detector)        |
//+------------------------------------------------------------------+
ENUM_KILLZONE GetActiveKillzone()
{
   if(!InpUseKillzoneFilter) return KILLZONE_NONE;

   if(hKillzone_Detector != INVALID_HANDLE)
   {
      double kzBuf[1];
      if(CopyBuffer(hKillzone_Detector, 0, 0, 1, kzBuf) > 0)
         return (ENUM_KILLZONE)kzBuf[0];
   }

   return KILLZONE_NONE;
}

//+------------------------------------------------------------------+
//| Check Killzone Time (PHASE 4: Now uses Killzone_Detector)        |
//+------------------------------------------------------------------+
bool CheckKillzone()
{
   if(!InpUseKillzoneFilter) return true;

   if(hKillzone_Detector != INVALID_HANDLE)
   {
      double activeBuf[1];
      if(CopyBuffer(hKillzone_Detector, 1, 0, 1, activeBuf) > 0)
         return (activeBuf[0] == 1.0);
   }

   return false;
}


