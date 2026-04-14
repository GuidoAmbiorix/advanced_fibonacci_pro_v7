//+------------------------------------------------------------------+
//|                                            Symbol_Engine.mq5     |
//|          Symbol Engine - Requests Permission from Governor       |
//|             Confluence Ladder + Portfolio Integration            |
//+------------------------------------------------------------------+
#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property version   "2.10"
#property description "Infernal Portfolio Governor R Symbol Engine"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include "Include\PortfolioGlobals.mqh"
#include "Include\KillzoneConfig.mqh"
#include "Include\FailSafe.mqh"
#include "Include\Regime\RegimeEngine.mqh"
#include "Include\KillSwitch.mqh"
#include "Include\Learning_MFE_MAE.mqh"
#include "Include\SelfGovernor.mqh"

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

// ADVANCED CONFLUENCE MODULES (H4 ENHANCED)
#include "Include\Advanced\VolumeAnalysis.mqh"
#include "Include\Advanced\Divergence.mqh"
#include "Include\Advanced\Inst_Concepts.mqh"
#include "Include\Advanced\MetalsAnalysis.mqh"

// Visual Debugging
#include "Include\VisualDebug.mqh"

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
input int               InpMinConfluenceEntry = 4;
input double            InpDominanceThreshold = 2.0;      // Signal Dominance Threshold
input int               InpMaxPositions = 3;

input group "======= GOVERNOR ======="
input bool              InpGov_Enabled     = true;   // Enable drawdown-based risk control
input double            InpGov_DD_Reduce   = 5.0;    // Total DD % to start reducing risk
input double            InpGov_DD_Pause    = 10.0;   // Total DD % to pause trading entirely
input double            InpGov_ReducedMult = 0.5;    // Risk multiplier when in reduce zone
input double            InpGov_DailyMaxDD  = 5.0;    // Daily DD % to stop trading for the day

input group "======= RISK (Before Governor Scaling) ======="
input double            InpRiskBase = 0.25;
input double            InpMaxRisk = 0.75;               // Maximum Risk % (Kelly Limit)
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
input double            InpBE_Threshold_R = 0.6;         // Min profit to activate dynamic trail (R)
input double            InpTrailStart_R = 0.6;            // Trail activation (same as BE for dynamic)
input double            InpTrailATR_Mult = 1.5;           // Base ATR multiplier (decays with profit)
input double            InpTrailDecayRate = 0.30;         // Multiplier decay rate (0.1=slow, 0.5=fast)
input double            InpTrailMinMult = 0.50;           // Minimum ATR multiplier (floor)
input bool              InpTrailRegimeAware = true;       // Widen trail in trends, tighten in ranges
input double            InpTrailMinBufferATR = 0.30;       // Min buffer from price (ATR fraction)

input group "======= INFINITE ESCALATOR ======="
input double            InpEsc_FirstR = 0.5;              // Stage 0: Quick Lock trigger (R)
input double            InpEsc_FirstSL_R = -0.1;          // Stage 0: SL offset (neg=below entry)
input double            InpEsc_StepR = 0.7;               // Base step between harvest stages (R)
input double            InpEsc_GrowthFactor = 1.3;        // Step growth (>1=widening gaps between stages)
input double            InpEsc_BaseHarvest = 15.0;        // Base harvest % per stage
input double            InpEsc_HarvestDecay = 0.85;       // Harvest decay per stage (0.85=85% of prev)
input double            InpEsc_MinHarvest = 3.0;          // Minimum harvest % (floor)
input int               InpEsc_MaxStages = 20;            // Safety cap on stages
input double            InpRunnerTrailTight = 0.75;        // Runner: Wider trail multiplier
input double            InpTimeStaleMins = 240.0;          // Time-decay: minutes without new high
input double            InpTimeStaleTight1 = 0.8;          // Time-decay: moderate tightening
input double            InpTimeStaleTight2 = 0.65;         // Time-decay: aggressive tightening

input group "======= SCALE-IN PYRAMID ======="
input bool              InpPyr_Enable = true;             // Enable pyramid scale-in on winners
input int               InpPyr_Frequency = 3;             // Scale in every Nth stage
input double            InpPyr_FirstRiskPct = 0.15;       // First add-on risk %
input double            InpPyr_RiskDecay = 0.70;          // Risk decay per add-on (0.7=70% of prev)
input double            InpPyr_MinRiskPct = 0.05;         // Minimum add-on risk % (floor)
input int               InpPyr_MaxAddOns = 5;             // Maximum add-on positions
input double            InpPyr_MinProfitR = 1.0;          // Min group profit R before first scale-in
input double            InpAgg_MaxTotalRisk = 1.5;        // Max aggregate risk % for trade group
input int               InpAgg_MaxPositions = 6;          // Max positions per trade group

input group "======= ADAPTIVE ESCALATOR ======="
input bool   InpAdaptiveEscalator = true;       // Enable Adaptive Escalator
input double InpScoreAdaptFactor = 0.05;         // Score adaptation factor per point above 13
input bool   InpRegimeHarvest = true;            // Regime-aware harvest percentages
input bool   InpMFECalibration = true;           // MFE-calibrated stage triggers
input bool   InpMomentumTrail = true;            // RSI momentum trail for runner
input bool   InpChaosEmergencyLock = true;       // Emergency lock in CHAOS regime
input int    InpFridayCloseHour = 22;            // Friday close hour (broker time, 0=disabled)

input group "======= STALE TRADE EXIT ======="
input bool   InpUseStaleTrade = true;            // Exit trades stuck below Quick Lock for too long
input int    InpStaleBarLimit = 8;               // Bars at stage -1 (no Quick Lock yet) before exit
                                                  // H4: 8 bars = 32 hours. Set 0 to disable.

input group "======= SPREAD ======="
input int               InpMaxSpreadPoints = 50;

input group "======= SMC - SMART MONEY CONCEPTS ======="
input bool              InpUseSMC = true;                 // Enable SMC Analysis
input int               InpSMC_SwingLookback = 20;        // Swing Lookback Bars
input double            InpSMC_MinImpulseATR = 2.0;       // Min Impulse (ATR mult)
input double            InpSMC_MinFVG_ATR = 0.5;          // Min FVG Size (ATR mult)

input group "======= MULTI-TIMEFRAME ======="
input bool              InpUseMTF = true;                 // Enable MTF Analysis
input ENUM_TIMEFRAMES   InpHTF = PERIOD_W1;               // Higher Timeframe (Weekly)
input ENUM_TIMEFRAMES   InpMTF = PERIOD_D1;              // Medium Timeframe (Daily)
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
input bool              InpCloseOnKillzoneEnd = false;    // Close trades when their killzone ends
input int               InpKZBEMinutesBefore = 15;        // Mins before KZ end to force breakeven (0=off)
input double            InpKZBEMinProfitR    = 0.1;       // Min profit R required to force breakeven

input group "======= MOMENTUM EXIT ======="
input bool              InpUseMomentumExit      = true;   // Detect & exit trades that lost momentum
input int               InpMomADX_Period        = 14;     // ADX period for momentum measurement
input double            InpMomADX_Threshold     = 25.0;   // ADX must have been above this (was trending)
input double            InpMomATR_CollapseRatio = 0.55;   // Exit if ATR drops below X% of entry ATR
input int               InpMomBarsNoProgress    = 8;      // Bars without meaningful price progress
input double            InpMomProgressATR       = 0.3;    // Min ATR multiples to consider "progressing"
input int               InpMomSignalsToExit     = 3;      // Signals needed (1-5) to trigger momentum exit
input int               InpMomRecoveryMinScore  = 2;      // Recovery signals needed to spare a losing trade

input group "======= SESSION GOVERNOR ======="
input bool              InpUseSessionGovernor = true;     // Enable Session Governor
input int               InpMaxTradesPerSession = 3;       // Max Trades Per Session
input int               InpTradeCooldownMinutes = 30;     // Cooldown Between Trades
input bool              InpCloseIntradayProfits = true;   // Close Profitable Trades at EOD (H1 Intraday)
input int               InpEndOfDayHour = 22;             // EOD Hour (Broker Time, typically 22:00 or 23:00)

input group "======= VISUAL DEBUGGING ======="
input bool              InpEnableVisualLevels = true;     // Draw Trade Levels on Chart
input int               InpTickThrottleSeconds = 60;      // Performance: Tick Throttle (seconds)

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

// MODULE OBJECTS
CFailSafe         failSafe;
CRegimeEngine     g_regimeEngine;   // Adaptive regime detector (5 regimes)
RegimeContext     g_regimeCtx;      // Full context: regime + escalator + signals
EscalatorConfig   g_escCfg;         // Dynamic escalator config (updated each bar from regime)
CKillSwitch       killSwitch;
CLearningEngine   learning;
CSelfGovernor      selfGov;

// ADVANCED MODULE OBJECTS
CVolumeAnalysis   volumeAnalysis;
CDivergence       divergence;
CBreakerBlocks    breakerBlocks;
CMacroWindows     macroWindows;
CPowerOf3         powerOf3;
CWyckoff          wyckoff;
CMetalsAnalysis   metalsAnalysis;

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
int hADX  = INVALID_HANDLE;   // Momentum exit: ADX
int hMACD = INVALID_HANDLE;   // Momentum exit: MACD
double g_RSI, g_RSI_Prev, g_ATR, g_EMA, g_EMA_Prev, g_ATR_MA;
double g_EMA50, g_EMA50_Prev, g_EMA100, g_EMA100_Prev;


int g_entryDirection = 0;
double g_currentConfluence = 0;
int g_positionCount = 0;
int g_activeGroupId = 0;          // Current active trade group (0=none)
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

// Smart Reversal: previous cycle scores for velocity calculation
double g_prevBuyScore  = 0;
double g_prevSellScore = 0;

// Friday close flag
bool g_fridayCloseExecuted = false;

// PHASE 1: Indicator buffer caching (once per bar)
double g_cachedSMCScore_Buy = 0;
double g_cachedSMCScore_Sell = 0;
double g_cachedMTFScore_Buy = 0;
double g_cachedMTFScore_Sell = 0;
double g_cachedVolumeScore_Buy = 0;
double g_cachedVolumeScore_Sell = 0;
double g_cachedDivergenceScore_Buy = 0;
double g_cachedDivergenceScore_Sell = 0;
datetime g_lastIndicatorCacheTime = 0;

// PHASE 1: GlobalVariable batch caching
struct GVCache {
   double rankMultiplier;
   double scoreValue;
   datetime lastUpdate;
};
GVCache g_gvCache;

// OPTIMIZATION: Performance monitoring
ulong g_tickCount = 0;
ulong g_barCount = 0;
ulong g_tradesExecuted = 0;

// Position state for tracking (includes infinite escalator)
struct PositionState {
   ulong ticket;
   bool  partialClosed;
   bool  beMovedToEntry;            // Flag: SL moved to breakeven (entry price)
   double initialRisk;              // Risk percentage (0.30 = 0.30%)
   double dollarRisk;               // Actual dollar amount at risk for R-calculation
   double initialSLDist;            // SL distance in price units at entry R used for profitR (not current trailed SL)
   ENTRY_QUALITY quality;
   ConfluenceFactors entryFactors;  // Factors captured at entry bar R used for pattern learning at exit (not current bar)
   double entryScore;               // Confluence score at entry R used by Adaptive Escalator

   // Infinite Escalator
   int    currentStage;             // Highest completed stage (-1=none, 0=quick lock, 1+=harvest stages)
   double locked_sl;                // Current locked SL level from escalator
   double totalHarvestedPct;        // Running total % harvested from this position
   double initialVolume;            // Volume at entry (needed for harvest tracking)
   bool   isRunner;                 // True when volume too small to harvest R let it ride

   // Trade Group
   int    groupId;                  // Group ID linking original + add-ons
   bool   isAddOn;                  // true if this is a scale-in position
   int    addOnIndex;               // 0=original, 1=first add-on, etc.

   // Time-decay trailing
   datetime lastPeakTime;           // When max profit was last reached
   double   peakProfitR;            // Maximum profit R achieved so far

   // Stale trade tracking
   int      barsAtStageNeg1;        // Bars elapsed while still at stage -1 (no Quick Lock)

   // Killzone tracking
   ENUM_KILLZONE entryKillzone;     // Active killzone when trade was opened

   // Momentum exit tracking
   double entryATR;                 // ATR at entry bar (for collapse detection)
};
PositionState g_states[];

// Trade Group: links original entry + all scale-in add-ons
struct TradeGroup {
   int      groupId;
   int      direction;              // 1=Buy, -1=Sell
   ulong    originalTicket;         // The first position's ticket
   double   originalEntryPrice;     // Entry price of original (for SL floor calc)
   double   originalSLDist;         // SL distance of original (for R calc)
   int      addOnCount;             // How many add-ons opened so far
   int      highestStage;           // Highest escalator stage reached (any position in group)
   double   aggregateRiskPct;       // Sum of initialRisk across all positions
   bool     active;                 // false when all positions closed
};
TradeGroup g_groups[];
int g_nextGroupId = 1;

// REAL confluence factors captured during CalculateConfluenceScore()
// Used by AdaptiveFilterManager and PatternRecognizer instead of score proxies
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

   // Timeframe recommendation (H4 is optimal; EA works on any TF but is calibrated for H4)
   if(_Period != PERIOD_H4)
      Print("[WARN] Recommended timeframe is H4. Current: ", EnumToString(_Period),
            ". EA will run but parameters are calibrated for H4.");

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

   // Initialize Momentum Exit indicators
   if(InpUseMomentumExit)
   {
      hADX  = iADX(_Symbol, PERIOD_CURRENT, InpMomADX_Period);
      hMACD = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
      if(hADX == INVALID_HANDLE || hMACD == INVALID_HANDLE)
         Print("[WARN] Momentum Exit: indicator handles invalid - feature will be disabled");
      else
         Print("[OK] Momentum Exit initialized (ADX/MACD/RSI+ATR+Progress)");
   }

   failSafe.Init(InpMaxSpreadPoints);
   ArrayResize(g_states, 0);

   // OPTIMIZATION: Initialize Learning Engine with error checking
   // Disable file persistence in Strategy Tester (avoids symbol mismatch + file I/O errors on validator)
   if(InpEnableLearning)
   {
      bool enablePersistence = !MQLInfoInteger(MQL_TESTER);
      if(!learning.Init(_Symbol, enablePersistence))
      {
         Print("Warning: Learning engine initialization failed - continuing without learning");
      }
      else
      {
         Print("[OK] Learning engine initialized", enablePersistence ? " with persistence" : " (tester: no persistence)");
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
      double maxRiskAdjusted = InpMaxRisk;

      kellySizer.Init(InpRiskBase, 0.25, maxRiskAdjusted, InpKellyFraction, 30, InpDailyMaxDD, InpWeeklyMaxDD, InpDailyTarget);
   }

   // Initialize Database Manager (disabled in Strategy Tester to avoid file I/O errors on validator)
   if(InpEnableLearning && InpLogTradesToFile && !MQLInfoInteger(MQL_TESTER))
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

   // Initialize Metals Analysis (for metals symbols only)
   if(GetCorrelationGroup(_Symbol) == GROUP_METALS)
   {
      if(!metalsAnalysis.Init(_Symbol))
         Print("Warning: Metals Analysis initialization failed");
      else
         Print("[OK] Metals Analysis initialized for ", _Symbol);
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

   // Restore consecutive loss counter from persistent GV (survives EA restarts)
   g_consecutiveLosses = (int)GlobalVariableGet("PG_ConsecLoss_" + _Symbol);
   if(g_consecutiveLosses > 0)
      Print("Restored g_consecutiveLosses=", g_consecutiveLosses, " from GlobalVariable");

   // Initialize self-contained Governor
   selfGov.Init(InpGov_Enabled, InpGov_DD_Reduce, InpGov_DD_Pause, InpGov_ReducedMult, InpGov_DailyMaxDD);

   // Initialize Regime Engine (5-regime adaptive system)
   if(!g_regimeEngine.Init(_Symbol, PERIOD_CURRENT))
      Print("[WARN] RegimeEngine init failed — using input defaults for escalator");

   // Seed g_escCfg with .set file inputs as fallback (overwritten each bar by regime)
   g_escCfg.enabled          = true;
   g_escCfg.firstR            = InpEsc_FirstR;
   g_escCfg.firstSL_R         = InpEsc_FirstSL_R;
   g_escCfg.stepR             = InpEsc_StepR;
   g_escCfg.growthFactor      = InpEsc_GrowthFactor;
   g_escCfg.baseHarvest       = InpEsc_BaseHarvest;
   g_escCfg.harvestDecay      = InpEsc_HarvestDecay;
   g_escCfg.minHarvest        = InpEsc_MinHarvest;
   g_escCfg.maxStages         = InpEsc_MaxStages;
   g_escCfg.runnerTrailTight  = InpRunnerTrailTight;
   g_escCfg.timeStaleMins     = InpTimeStaleMins;

   Print("===========================================");
   Print("  [START] SYMBOL ENGINE v2.0: ", _Symbol);
   Print("===========================================");
   Print("  Magic: ", InpMagicNumber);
   Print("  Governor: ", selfGov.GetStatus());
   Print("-------------------------------------------");
   Print("  CORE MODULES:");
   Print("    SMC Analysis: ", InpUseSMC ? "ON" : "OFF");
   Print("    MTF Confluence: ", InpUseMTF ? "ON" : "OFF");
   Print("    News Filter: ", InpUseNewsFilter ? "ON" : "OFF");
   if(InpUseNewsFilter && InpEnableVolatilityFilter)
      Print("      [WARN] Flash Crash Protection: ON (Threshold: ", InpVolatilityThreshold, "x)");
   Print("    Kelly Sizing: ", InpUseKelly ? "ON" : "OFF");
   Print("-------------------------------------------");
   Print("  PORTFOLIO PROTECTION:");
   Print("    Correlation Filter: ", InpUseCorrelationFilter ? "ON" : "OFF");
   Print("    Daily Circuit Breaker: ", InpDailyMaxLoss_R, "R");
   Print("    Loss Cooldown: ", InpLossCooldownMinutes, " minutes");
   Print("    Reversal Filter: ", InpUseReversalFilter ? "ON (EMA50/100 momentum)" : "OFF");
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
      Print("    Learning Engine: ACTIVE");
      if(InpLogTradesToFile)
         Print("    Trade Journal: ACTIVE (", InpLearningHistory, " days)");
      Print("    Performance Analyzer: ", performanceAnalyzer.GetTradeCount(), " trades loaded");
      Print("    Pattern Memory: ", patternMemory.GetPatternCount(), " patterns");
      Print("    Adaptive Risk: ", InpEnableAdaptiveRisk ? "ON" : "OFF");
      Print("    Adaptive Exits: ", InpEnableAdaptiveExits ? "ON" : "OFF");
      Print("    Adaptive Filters: ", InpEnableAdaptiveFilters ? "ON" : "OFF");
      Print("-------------------------------------------");
   }
   Print("===========================================");

   g_prevBuyScore  = 0;
   g_prevSellScore = 0;

   // Initialize indicators on startup
   Print("  Initializing indicators...");
   if(!UpdateIndicators())
   {
      Print("  WARNING: Initial indicator update failed - will retry on first bar");
   }
   else
   {
      Print("  [OK] Indicators initialized: RSI=", DoubleToString(g_RSI, 2), " ATR=", DoubleToString(g_ATR, 5), " EMA=", DoubleToString(g_EMA, 5));
   }
   Print("===========================================");
   Print("[CONFIG] Killzone: ", InpUseKillzoneFilter ? "ACTIVE" : "OFF");
   Print("[CONFIG] Infinite Escalator: FirstR=", InpEsc_FirstR,
         " StepR=", InpEsc_StepR, " Growth=", InpEsc_GrowthFactor,
         " BaseHarvest=", InpEsc_BaseHarvest, "% Decay=", InpEsc_HarvestDecay,
         " MaxStages=", InpEsc_MaxStages);
   Print("[CONFIG] Pyramid: ", InpPyr_Enable ? "ON" : "OFF",
         " | Freq=", InpPyr_Frequency,
         " | FirstRisk=", InpPyr_FirstRiskPct, "% MaxAddOns=", InpPyr_MaxAddOns,
         " | AggMaxRisk=", InpAgg_MaxTotalRisk, "%");
   Print("[CONFIG] Adaptive: ScoreAdapt=", InpScoreAdaptFactor,
         " | RegimeHarvest=", InpRegimeHarvest,
         " | MFECalib=", InpMFECalibration,
         " | MomentumTrail=", InpMomentumTrail,
         " | ChaosLock=", InpChaosEmergencyLock);
   if(InpFridayCloseHour > 0) Print("[CONFIG] Friday Close: hour ", InpFridayCloseHour);

   EventSetTimer(5); // Dashboard timer: update every 5 seconds regardless of ticks

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Timer — keeps dashboard alive even with no market ticks          |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateDashboard();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
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

   // Cleanup Regime Engine
   g_regimeEngine.Deinit();

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

   // Deactivate current trade group
   if(g_activeGroupId > 0)
   {
      for(int i = 0; i < ArraySize(g_groups); i++)
         if(g_groups[i].groupId == g_activeGroupId)
            g_groups[i].active = false;
   }
   g_activeGroupId = 0;

   // OPTIMIZATION: Free memory properly
   if(ArraySize(g_states) > 0)
   {
      ArrayFree(g_states);
      ArrayResize(g_states, 0);
   }
}


// ... (rest of OnTick logic)

//+------------------------------------------------------------------+
//| INSTITUTIONAL STRATEGY HELPERS                                    |
//+------------------------------------------------------------------+
double GetAdaptiveSL(double score)
{
   // M5 Scalper: Tight stops R small ATR multipliers for fast in/out
   // Elite gets slightly more room to survive M5 noise wicks
   if(score >= 6.0) return g_ATR * 1.0;  // Elite: Room to breathe but still tight
   if(score >= 5.0) return g_ATR * 0.8;  // Strong: Standard M5 stop
   return g_ATR * 0.6;                   // Good: Cut very tight
}

double GetSymbolEdgeFactor()
{
   double winRate = killSwitch.GetWinRate();
   if(winRate > 0.6) return 1.2;
   if(winRate < 0.45) return 0.7;
   return 1.0;
}

//+------------------------------------------------------------------+
//| Get bars held since position open time                           |
//+------------------------------------------------------------------+
int GetBarsHeld(datetime openTime)
{
   int bars = Bars(_Symbol, PERIOD_CURRENT, openTime, TimeCurrent());
   return (bars > 0) ? bars - 1 : 0;
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
         Print("[DAILY] Reset: Day R=", DoubleToString(g_dailyLossR, 2), " | Trades: ", g_dailyTradesCount);
         ExportDailyPerformance(g_dailyTradesCount, g_dailyLossR);
      }
      g_dailyLossR = 0;
      g_consecutiveLosses = 0;
      GlobalVariableSet("PG_ConsecLoss_" + _Symbol, 0);
      g_dailyTradesCount = 0;
      g_fridayCloseExecuted = false;
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

      // Only check positions from same EA family (Governor range: 100000-100999; H1=100001-100008, M15=100101-100108)
      if(posMagic >= 100000 && posMagic <= 100999)
      {
         string posSymbol = position.Symbol();
         if(posSymbol == symbol) continue;  // Same symbol is OK

         ENUM_CORR_GROUP posGroup = GetCorrelationGroup(posSymbol);

         // Block if same correlation group (USD, GBP, JPY, METALS, INDICES)
         if(myGroup == posGroup && myGroup != GROUP_OTHER)
         {
            Print("[BLOCK] CORRELATION: Cannot trade ", symbol, " (", EnumToString(myGroup),
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

      // Regime adjustments (H4 calibrated, 5-regime)
      if(g_currentRegime == REGIME_TREND_STRONG) tpR *= 1.5;  // Let strong trends run
      else if(g_currentRegime == REGIME_TREND_WEAK) tpR *= 1.1; // Small extension
      else if(g_currentRegime == REGIME_RANGING)   tpR *= 0.65; // Tight — TP at mean
      else if(g_currentRegime == REGIME_VOLATILE)  tpR *= 1.2;  // Quick spike target
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


   // --- KILLZONE STATE CHANGE DETECTION ---
   {
      ENUM_KILLZONE currentKZ = GetActiveKillzone();
      if(currentKZ != g_lastKillzoneState)
      {
         // Notify on open
         if(currentKZ != KILLZONE_NONE && InpNotifyKillzoneOpen)
         {
             string msg = "[INFO] KILLZONE OPEN: " + KillzoneToString(currentKZ) + " on " + _Symbol;
             if(InpEnableMobileAlerts) SendNotification(msg);
             Print(msg);
         }

         // Close trades that belong to the killzone that just ended (unconditional - profit or loss)
         if(currentKZ == KILLZONE_NONE && InpCloseOnKillzoneEnd && g_lastKillzoneState != KILLZONE_NONE)
         {
            ENUM_KILLZONE closedKZ = g_lastKillzoneState;
            Print("[KZ CLOSE] ", KillzoneToString(closedKZ), " ended - scanning trades opened in that session");
            for(int i = ArraySize(g_states) - 1; i >= 0; i--)
            {
               if(g_states[i].entryKillzone != closedKZ) continue;
               if(!PositionSelectByTicket(g_states[i].ticket))   continue;
               double posProfit = PositionGetDouble(POSITION_PROFIT);
               if(trade.PositionClose(g_states[i].ticket))
                  Print("[KZ CLOSE] #", g_states[i].ticket, " closed at KZ end, P/L=", DoubleToString(posProfit,2));
               else
                  Print("[KZ CLOSE] Failed #", g_states[i].ticket, " err=", GetLastError());
            }
         }

         g_lastKillzoneState = currentKZ;
      }
   }

   g_tickCount++;  // Performance monitoring

   symbolInfo.RefreshRates();

   g_positionCount = CountPositions();
   if(g_positionCount == 0) ResetTradeState();

   // --- GOVERNOR EMERGENCY CLOSE GUARD ---
   if(!selfGov.IsTradingEnabled()) return; // Governor paused — do not manage positions during DD halt

   // --- FRIDAY PRE-WEEKEND BLOCK ---
   if(InpFridayCloseHour > 0)
   {
      MqlDateTime dtFri;
      TimeCurrent(dtFri);
      if(dtFri.day_of_week == 5 && dtFri.hour >= InpFridayCloseHour)
      {
         if(!g_fridayCloseExecuted) Print("[FRIDAY] Pre-weekend block active. No new signals.");
         g_fridayCloseExecuted = true;
         ManagePositions(); // Still manage existing positions
         return;            // Block new signal evaluation
      }
   }

   // --- EOD INTRADAY CLOSE GUARD ---
   if(InpCloseIntradayProfits && g_positionCount > 0)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.hour >= InpEndOfDayHour)
      {
         bool closedAny = false;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
            {
               if(position.Profit() > 0) // Only close if in profit to avoid locking in unnecessary losses
               {
                  if(trade.PositionClose(position.Ticket()))
                  {
                     Print("[EOD CLOSE] Intraday profit secured for ", _Symbol, " at hour ", dt.hour);
                     closedAny = true;
                  }
               }
            }
         }
         if(closedAny) g_positionCount = CountPositions();
      }
   }

   ManagePositions();

   // Update visual debugging lines
   UpdateAllPositionVisuals();

   // --- PERFORMANCE THROTTLE ---
   static datetime lastHeavyUpdate = 0;
   datetime now = TimeCurrent();
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(now - lastHeavyUpdate < InpTickThrottleSeconds) return;
   lastHeavyUpdate = now;

   // Simple bar count update without external function
   static datetime prevBarTime = 0;
   if(currentBarTime != prevBarTime)
   {
      g_barCount++;
      prevBarTime = currentBarTime;
   }

   if(!UpdateIndicators()) return;

   // --- UPDATE ALL MODULES ON NEW BAR ---
   UpdateModules();

   // --- MODULE: MARKET REGIME (5-regime adaptive engine) ---
   g_regimeCtx     = g_regimeEngine.Evaluate(InpMinConfluenceEntry, InpMaxSpreadPoints);
   g_currentRegime = g_regimeCtx.regime;
   // Update dynamic escalator config (overrides InpEsc_* with regime-calibrated values)
   if(g_regimeCtx.escalator.enabled)
      g_escCfg = g_regimeCtx.escalator;
   else
   {
      // CRISIS: disable escalator but keep struct populated safely
      g_escCfg.enabled    = false;
      g_escCfg.maxStages  = 0;
   }
   // g_currentRegime check moved down to allow score calculation for visibility

   // --- THROTTLED CONFLUENCE CALCULATION ---
   // Recalculate confluence scores based on throttle (not just on new bar)
   // Preserve previous cycle for velocity calculation
   g_prevBuyScore  = g_cachedBuyScore;
   g_prevSellScore = g_cachedSellScore;
   g_cachedBuyScore = CalculateConfluenceScore(1);
   g_cachedSellScore = CalculateConfluenceScore(-1);
   g_lastScoreCalcTime = now;

   // --- SIGNAL DOMINANCE FILTER ---
      if(InpDominanceThreshold > 0)
      {
         double delta = MathAbs(g_cachedBuyScore - g_cachedSellScore);
         if(delta < InpDominanceThreshold)
         {
            if(g_cachedBuyScore > InpMinConfluenceEntry || g_cachedSellScore > InpMinConfluenceEntry)
            {
               Print("R DOMINANCE FILTER: Blocked Signal. Buy=", DoubleToString(g_cachedBuyScore,1),
                     " Sell=", DoubleToString(g_cachedSellScore,1), " Delta=", DoubleToString(delta,1), " < ", InpDominanceThreshold);
            }
            g_cachedBuyScore = 0;
            g_cachedSellScore = 0;
            // Reset prev scores so velocity doesn't spike on next bar
            g_prevBuyScore  = 0;
            g_prevSellScore = 0;
         }
      }

      // --- RANKING SYSTEM: PUBLISH SCORE ---
      double maxScore = (g_cachedBuyScore > g_cachedSellScore) ? g_cachedBuyScore : g_cachedSellScore;
      double direction = (maxScore <= 0) ? 0.0 : (g_cachedBuyScore > g_cachedSellScore) ? 1.0 : -1.0;
      
      GlobalVariableSet(GV_SCORE_PREFIX + _Symbol, maxScore);
      GlobalVariableSet(GV_REQ_PREFIX + _Symbol, InpMinConfluenceEntry);
      GlobalVariableSet(GV_DIR_PREFIX + _Symbol, direction);
      
      // Timer Data
      GlobalVariableSet(GV_BAROPEN_PREFIX + _Symbol, (double)currentBarTime);
      GlobalVariableSet(GV_PERIOD_PREFIX + _Symbol, (double)PeriodSeconds(InpMTF));
      
      // Killzone Status
      bool isKZOpen = !InpUseKillzoneFilter || CheckKillzone();
      GlobalVariableSet(GV_KZ_PREFIX + _Symbol, isKZOpen ? 1.0 : 0.0);

      // ATR publish R required by RankManager for volatility-normalized adjScore
      GlobalVariableSet("PG_ATR_" + _Symbol, g_ATR);

      // Fix #3: Publish regime and signal quality for RankManager multipliers
      GlobalVariableSet("PG_Regime_" + _Symbol, (double)g_currentRegime);
      double bestQuality = 0;
      if(g_cachedBuyScore >= g_cachedSellScore && g_cachedBuyScore >= InpMinConfluenceEntry)
         bestQuality = (g_cachedBuyScore >= 22) ? 3.0 : (g_cachedBuyScore >= 18) ? 2.0 : 1.0;
      else if(g_cachedSellScore > g_cachedBuyScore && g_cachedSellScore >= InpMinConfluenceEntry)
         bestQuality = (g_cachedSellScore >= 22) ? 3.0 : (g_cachedSellScore >= 18) ? 2.0 : 1.0;
      GlobalVariableSet("PG_Quality_" + _Symbol, bestQuality);

      // --- SCAN LOG: visibility into regime and signal strength ---
      Print("[SCAN] ", _Symbol, " | ", g_regimeCtx.regimeLabel,
            "(", IntegerToString(g_regimeCtx.regimeScore), "%)",
            " | Buy=", DoubleToString(g_cachedBuyScore, 1),
            " Sell=", DoubleToString(g_cachedSellScore, 1),
            " | Need=", g_regimeCtx.minConfluence,
            " | Esc.FirstR=", DoubleToString(g_escCfg.firstR, 2),
            " Harvest=", DoubleToString(g_escCfg.baseHarvest, 0), "%");

   // --- MODULE: FAIL SAFE (Quick Exit) ---
   if(!failSafe.IsExecutionSafe()) return;

   // --- MODULE: KILL SWITCH (Quick Exit) ---
   if(!killSwitch.IsEnabled())
   {
      static datetime lastKillWarning = 0;
      if(TimeCurrent() - lastKillWarning > 300)
      {
         Print("[BLOCKED] Kill Switch - ", killSwitch.GetStatus(),
               " | RollingR: ", DoubleToString(killSwitch.GetRollingR(), 2));
         lastKillWarning = TimeCurrent();
      }
      return;
   }

   // --- MODULE: NEWS FILTER ---
   if(InpUseNewsFilter && !newsFilter.IsTradingAllowed()) return;


   // --- MODULE: KELLY POSITION SIZER (DD + DAILY TARGET LIMITS) ---
   if(InpUseKelly && !kellySizer.IsTradingAllowed()) return;


   // --- PORTFOLIO PROTECTION: DAILY LOSS CIRCUIT BREAKER ---
   ResetDailyLossIfNewDay();
   if(InpDailyMaxLoss_R > 0 && g_dailyLossR <= -InpDailyMaxLoss_R)
   {
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning > 300)  // Print warning every 5 minutes
      {
         Print("[STOP] DAILY LOSS LIMIT REACHED: ", DoubleToString(g_dailyLossR, 2), "R / ",
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
         Print("R [WARN] CORRELATION BLOCK: Cannot trade ", _Symbol, " - Correlated pair already active");
         lastCorrWarning = TimeCurrent();
      }
      return;
   }

   // --- PRE-ENTRY FILTER: KILLZONE CHECK ---
   if(InpUseKillzoneFilter)
   {
       // Check if current time is in an active killzone
       if(!CheckKillzone())
       {
          static datetime lastKZLog = 0;
          if(TimeCurrent() - lastKZLog > 300)
          {
             Print("[BLOCKED] Outside Killzone - Current time not in enabled killzones");
             lastKZLog = TimeCurrent();
          }
          return;
       }
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
         Print("[STOP] MAX LOSS STREAK: ", g_consecutiveLosses, " consecutive losses - Trading STOPPED for today (or until manual reset)");
         lastStreakWarning = TimeCurrent();
      }
      return;
   }



   // === TRADING FILTERS START HERE ===
   
   if(!g_regimeCtx.allowEntries) return;  // CRISIS regime: no new entries

   // PRE-ENTRY FILTERS (Quick Exits for Performance)
   if(!CheckSpread(true)) return;

   // OPTIMIZATION: RSI Compression Filter (avoid choppy middle zone)
   if(g_RSI > 48 && g_RSI < 52)
   {
      static datetime lastRSIWarning = 0;
      if(TimeCurrent() - lastRSIWarning > 300)
      {
         Print("R RSI in dead zone: ", DoubleToString(g_RSI, 1), " (48-52) - waiting for momentum");
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
         Print("R Too close to EMA 200: ", DoubleToString(emaDistance / _Point, 0),
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
         Print("[STOP] VOLATILITY UNSAFE: ATR=", DoubleToString(g_ATR, 5), " (Dead or Extreme) - Trading Paused");
         lastVolWarning = TimeCurrent();
      }
      return;
   }

   // Check Governor Trading Permission
   if(!selfGov.IsTradingEnabled()) return;

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

      // Get Entry Tier from confluence force multiplier system
      ENUM_ENTRY_TIER tier = GetEntryTier(bestScore);
      if(tier == TIER_NO_TRADE) return;  // Score < 8 = no trade

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
         double regimeMultiplier = g_regimeCtx.riskMultiplier;

         baseRisk = kellySizer.GetAdjustedRisk(quality, newsMultiplier, killzoneMultiplier, regimeMultiplier);
      }

      // Apply confluence force multiplier (continuous scaling by score)
      baseRisk *= GetConfluenceMultiplier(bestScore);

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


      // GOVERNOR: apply drawdown multiplier and account hard cap
      double approvedRisk = selfGov.ApproveRisk(baseRisk);

      if(approvedRisk > 0.05)
      {
          // Dynamic threshold: base from .set + regime adjustment
          double minEntry = (double)g_regimeCtx.minConfluence;

          // Use adaptive threshold if enabled
          if(InpEnableAdaptiveFilters && adaptiveFilter.IsAdaptationEnabled())
           {
              // Use REAL factors from last CalculateConfluenceScore() call
              ENUM_KILLZONE currentKZ = KILLZONE_NONE;
               ConfluenceFactors thresholdFactors;
               if(bestDirection == 1) thresholdFactors = g_lastBuyFactors;
               else thresholdFactors = g_lastSellFactors;


             minEntry = adaptiveFilter.CalculateDynamicThreshold(thresholdFactors, currentKZ, g_currentRegime);

             static datetime lastThresholdLog = 0;
             if(TimeCurrent() - lastThresholdLog > 3600)  // Log hourly
             {
                Print("[INFO] Dynamic Threshold: ", DoubleToString(minEntry, 2),
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
                      Print("R SAME-DIRECTION COOLDOWN: BUY blocked - ",
                            IntegerToString(remainingSec / 60), "m ", IntegerToString(remainingSec % 60), "s remaining");
                      lastCooldownWarning = TimeCurrent();
                   }
                   return;  // Skip this trade
                }
             }

             g_currentConfluence = buyScore;
             g_entryDirection = 1;
             if(ExecuteTrade(ORDER_TYPE_BUY, approvedRisk, "Entry", quality))
             {
                // Create trade group for the new entry
                int lastIdx = ArraySize(g_states) - 1;
                double ep = PositionSelectByTicket(g_states[lastIdx].ticket) ? PositionGetDouble(POSITION_PRICE_OPEN) : symbolInfo.Ask();
                g_activeGroupId = CreateTradeGroup(1, g_states[lastIdx].ticket, ep, g_states[lastIdx].initialSLDist, approvedRisk);
                g_states[lastIdx].groupId = g_activeGroupId;
             }
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
                      Print("R SAME-DIRECTION COOLDOWN: SELL blocked - ",
                            IntegerToString(remainingSec / 60), "m ", IntegerToString(remainingSec % 60), "s remaining");
                      lastCooldownWarning = TimeCurrent();
                   }
                   return;  // Skip this trade
                }
             }

             g_currentConfluence = sellScore;
             g_entryDirection = -1;
             if(ExecuteTrade(ORDER_TYPE_SELL, approvedRisk, "Entry", quality))
             {
                int lastIdx = ArraySize(g_states) - 1;
                double ep = PositionSelectByTicket(g_states[lastIdx].ticket) ? PositionGetDouble(POSITION_PRICE_OPEN) : symbolInfo.Bid();
                g_activeGroupId = CreateTradeGroup(-1, g_states[lastIdx].ticket, ep, g_states[lastIdx].initialSLDist, approvedRisk);
                g_states[lastIdx].groupId = g_activeGroupId;
             }
          }

         // ══════════════════════════════════════════════════════════════
         // REGIME ALTERNATIVE ENTRIES: Mean Reversion & Volatility
         // Fire only when main momentum entry did NOT qualify but the
         // regime engine found a regime-specific setup.
         // ══════════════════════════════════════════════════════════════
         bool mainEntryFired = (buyScore >= minEntry || sellScore >= minEntry);
         if(!mainEntryFired)
         {
         // ── RANGING: Mean Reversion ───────────────────────────────
         if(g_currentRegime == REGIME_RANGING && g_regimeCtx.mrSignalValid)
         {
            MRSignal mrSig = g_regimeCtx.mrSignal;
            if(mrSig.score >= 20)
            {
               double mrRisk = approvedRisk * g_regimeCtx.riskMultiplier;
               ENUM_ORDER_TYPE mrType = (mrSig.direction == ORDER_TYPE_BUY) ?
                                         ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               ENTRY_QUALITY   mrQ    = (mrSig.score >= 28) ? EQ_STRONG : EQ_GOOD;
               Print("[MR ENTRY] Regime=RANGING | Score=", mrSig.score, " | ", mrSig.reason);
               if(ExecuteTrade(mrType, mrRisk, "MR", mrQ))
               {
                  int lastIdx = ArraySize(g_states) - 1;
                  double ep = PositionSelectByTicket(g_states[lastIdx].ticket) ?
                              PositionGetDouble(POSITION_PRICE_OPEN) : symbolInfo.Ask();
                  g_activeGroupId = CreateTradeGroup(mrType == ORDER_TYPE_BUY ? 1 : -1,
                                    g_states[lastIdx].ticket, ep,
                                    g_states[lastIdx].initialSLDist, mrRisk);
                  g_states[lastIdx].groupId = g_activeGroupId;
               }
            }
         }
         // ── VOLATILE / TREND_WEAK: Compression Breakout ───────────
         else if((g_currentRegime == REGIME_VOLATILE || g_currentRegime == REGIME_TREND_WEAK)
                 && g_regimeCtx.volSignalValid)
         {
            VolSignal volSig = g_regimeCtx.volSignal;
            if(volSig.score >= 20)
            {
               double volRisk = approvedRisk * g_regimeCtx.riskMultiplier;
               ENUM_ORDER_TYPE volType = (volSig.direction == ORDER_TYPE_BUY) ?
                                          ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               ENTRY_QUALITY   volQ    = (volSig.score >= 28) ? EQ_STRONG : EQ_GOOD;
               Print("[VOL ENTRY] Regime=", g_regimeCtx.regimeLabel, " | Score=", volSig.score,
                     " | Breakout=", volSig.isBreakout ? "YES" : "NO", " | ", volSig.reason);
               if(ExecuteTrade(volType, volRisk, "VOL", volQ))
               {
                  int lastIdx = ArraySize(g_states) - 1;
                  double ep = PositionSelectByTicket(g_states[lastIdx].ticket) ?
                              PositionGetDouble(POSITION_PRICE_OPEN) : symbolInfo.Ask();
                  g_activeGroupId = CreateTradeGroup(volType == ORDER_TYPE_BUY ? 1 : -1,
                                    g_states[lastIdx].ticket, ep,
                                    g_states[lastIdx].initialSLDist, volRisk);
                  g_states[lastIdx].groupId = g_activeGroupId;
               }
            }
         }
         } // end !mainEntryFired
      } // end approvedRisk > 0.05
   } // end g_positionCount == 0

   // NOTE: Pyramiding is now handled by TryScaleIn() inside the Infinite Escalator loop
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
          // Reject trade: minimum lot would exceed allowed risk R do NOT tighten SL (creates unrealistic stops)
          Print("R TRADE REJECTED: min lot risk $", DoubleToString(minLotRiskDollar, 2),
                " > max allowed $", DoubleToString(maxRiskDollar, 2), " on ", _Symbol, ". Account too small for this SL.");
          return false;
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

   // RUNNER MODE: Override Hard TP to allow extended runs
   // If Runner Mode (1) is active, we don't want the broker to close EVERYTHING at FixedTP.
   // Instead, we push the Hard TP to MaxTP (safety net) and let the Dynamic Trail handle the exit.
   if(InpTrailingMode == 1)
   {
       double runnerTP_R = MathMax(InpMaxTP_R, 10.0); // Ensure at least 10R room
       double runnerDist = slDist * runnerTP_R;
       tp = (type == ORDER_TYPE_BUY) ? price + runnerDist : price - runnerDist;
       tp = NormalizeDouble(tp, (int)symbolInfo.Digits());
       
       // Log only if verbose debugging is needed, otherwise silent override
       // Print("ðŸƒ [INFO] RUNNER MODE: Hard TP extended to ", DoubleToString(runnerTP_R,1), "R");
   }

   // FIX: CONSECUTIVE LOSS PROTECTION - Check immediately before OrderSend
   if(InpMaxConsecutiveLosses > 0 && g_consecutiveLosses >= InpMaxConsecutiveLosses)
   {
      Print("[BLOCKED] TRADE BLOCKED: ", g_consecutiveLosses, " consecutive losses reached. Waiting for cooldown or winning trade.");

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
         Print("[STOP] DAILY TRADE LIMIT: ", g_dailyTradesCount, "/", InpMaxDailyTrades, " trades reached. No more trades today.");
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
      g_states[sz].beMovedToEntry = false;
      g_states[sz].initialRisk = riskPct;                                    // Store risk percentage
      g_states[sz].dollarRisk = account.Equity() * (riskPct / 100.0);       // Store actual dollar risk for R-calculation
      g_states[sz].initialSLDist = slDist;                                   // Store SL distance at entry for profitR (not current trailed SL)
      g_states[sz].quality = quality;
      g_states[sz].entryFactors = (type == ORDER_TYPE_BUY) ? g_lastBuyFactors : g_lastSellFactors; // Capture entry-bar factors for pattern learning
      g_states[sz].entryScore = g_currentConfluence;  // Capture confluence score for Adaptive Escalator
      // Initialize Infinite Escalator fields
      g_states[sz].currentStage = -1;
      g_states[sz].locked_sl = 0;
      g_states[sz].totalHarvestedPct = 0;
      g_states[sz].initialVolume = lots;
      g_states[sz].isRunner = false;
      g_states[sz].groupId = g_activeGroupId;
      g_states[sz].isAddOn = (label != "Entry");
      g_states[sz].addOnIndex = 0;
      g_states[sz].lastPeakTime = TimeCurrent();
      g_states[sz].peakProfitR = 0;
      g_states[sz].barsAtStageNeg1 = 0;
      g_states[sz].entryKillzone = GetActiveKillzone();
      g_states[sz].entryATR = g_ATR;             // Store ATR at entry for momentum collapse detection

      // LOG TO DB MANAGER (skip in Strategy Tester)
      if(InpEnableLearning && InpLogTradesToFile && !MQLInfoInteger(MQL_TESTER))
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
      Print("[OK] TRADE OPENED");
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
          string notifyText = "[TRADE] TRADE OPENED: " + _Symbol + "\n" +
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
//| INFINITE ESCALATOR: Formula Engine                                |
//+------------------------------------------------------------------+

// Calculate trigger R for stage N using geometric progression
// Stage 0 = Quick Lock (FirstR)  — uses dynamic g_escCfg (set per regime each bar)
// Stage 1+ = FirstR + StepR * (GrowthFactor^0 + ... + GrowthFactor^(n-1))
double CalculateStageR(int stageIndex)
{
   if(stageIndex <= 0) return g_escCfg.firstR;
   double sum = 0;
   for(int i = 0; i < stageIndex; i++)
      sum += MathPow(g_escCfg.growthFactor, (double)i);
   return g_escCfg.firstR + g_escCfg.stepR * sum;
}

// Calculate harvest % for stage N (decaying per regime)
double CalculateHarvestPct(int stageIndex)
{
   if(stageIndex <= 0) return 0.0;
   double pct = g_escCfg.baseHarvest * MathPow(g_escCfg.harvestDecay, (double)(stageIndex - 1));
   return MathMax(pct, g_escCfg.minHarvest);
}

// Calculate SL lock R for stage N
// Stage 0 = FirstSL_R (can be negative = below-entry buffer)
// Stage 1+ = lock at previous stage trigger (ratchet up)
double CalculateSLLockR(int stageIndex)
{
   if(stageIndex <= 0) return g_escCfg.firstSL_R;
   return CalculateStageR(stageIndex - 1);
}

// Check if remaining volume can be harvested
bool CanHarvest(ulong ticket, double harvestPct)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double currentVol = PositionGetDouble(POSITION_VOLUME);
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double closeVol = NormalizeDouble(currentVol * (harvestPct / 100.0), 2);
   // Need enough for harvest AND remaining >= minLot
   return (closeVol >= minV && (currentVol - closeVol) >= minV);
}

// Safe SL modify: validates new SL is far enough from current price (stops level check)
// Prevents "invalid stops" errors on brokers with high stops level (e.g. MetaQuotes validation server)
bool SafeModifySL(ulong ticket, double newSL, double tp)
{
   if(!PositionSelectByTicket(ticket)) return false;
   
   double curr = PositionGetDouble(POSITION_PRICE_CURRENT);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   // Skip modification if nothing changed functionally to prevent unnecessary requests
   if(NormalizeDouble(newSL, _Digits) == NormalizeDouble(currentSL, _Digits) &&
      NormalizeDouble(tp, _Digits) == NormalizeDouble(currentTP, _Digits)) return true;
      
   double stopsLv = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeLv = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double minDist = MathMax(stopsLv, freezeLv) + _Point * 5; // Small extra buffer

   // SL validation
   if(pType == POSITION_TYPE_BUY  && newSL > 0 && curr - newSL < minDist) return false;
   if(pType == POSITION_TYPE_SELL && newSL > 0 && newSL - curr < minDist) return false;
   
   // TP validation (if TP is uncomfortably close to current price, modifying the order will fail)
   if(pType == POSITION_TYPE_BUY  && tp > 0 && tp - curr < minDist) return false;
   if(pType == POSITION_TYPE_SELL && tp > 0 && curr - tp < minDist) return false;

   return trade.PositionModify(ticket, newSL, tp);
}

//+------------------------------------------------------------------+
//| TRADE GROUP HELPERS                                               |
//+------------------------------------------------------------------+

// Create a new trade group for an original entry
int CreateTradeGroup(int direction, ulong ticket, double entryPrice, double slDist, double riskPct)
{
   int gId = g_nextGroupId++;
   int sz = ArraySize(g_groups);
   ArrayResize(g_groups, sz + 1);
   g_groups[sz].groupId = gId;
   g_groups[sz].direction = direction;
   g_groups[sz].originalTicket = ticket;
   g_groups[sz].originalEntryPrice = entryPrice;
   g_groups[sz].originalSLDist = slDist;
   g_groups[sz].addOnCount = 0;
   g_groups[sz].highestStage = -1;
   g_groups[sz].aggregateRiskPct = riskPct;
   g_groups[sz].active = true;
   return gId;
}

// Find group index by ID
int FindGroupIndex(int groupId)
{
   for(int i = 0; i < ArraySize(g_groups); i++)
      if(g_groups[i].groupId == groupId) return i;
   return -1;
}

// Get the group SL floor price from stage level
double GetGroupSLFloor(int groupIdx, int stageIndex)
{
   if(groupIdx < 0) return 0;
   double entryPrice = g_groups[groupIdx].originalEntryPrice;
   double slDist = g_groups[groupIdx].originalSLDist;
   double slLockR = CalculateSLLockR(stageIndex);
   if(g_groups[groupIdx].direction == 1) // Buy
      return entryPrice + (slDist * slLockR);
   else // Sell
      return entryPrice - (slDist * slLockR);
}

// Apply group SL floor to all positions in the group
void ApplyGroupSLFloor(int groupId)
{
   int gIdx = FindGroupIndex(groupId);
   if(gIdx < 0) return;
   int highStage = g_groups[gIdx].highestStage;
   if(highStage < 0) return;

   double floorSL = GetGroupSLFloor(gIdx, highStage);
   int dir = g_groups[gIdx].direction;

   for(int i = 0; i < ArraySize(g_states); i++)
   {
      if(g_states[i].groupId != groupId) continue;
      if(!PositionSelectByTicket(g_states[i].ticket)) continue;

      double currentSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      bool shouldMove = (dir == 1) ? (floorSL > currentSL + _Point*5) : (floorSL < currentSL - _Point*5 || currentSL == 0);

      if(shouldMove)
      {
         if(SafeModifySL(g_states[i].ticket, floorSL, tp))
         {
            if(floorSL > g_states[i].locked_sl || g_states[i].locked_sl == 0)
               g_states[i].locked_sl = floorSL;
            if(g_states[i].isAddOn)
               Print("[GROUP SL] Add-on #", g_states[i].addOnIndex, " SL raised to group floor ", DoubleToString(floorSL, _Digits));
         }
      }
   }
}

// Try scale-in at current stage
void TryScaleIn(int groupId, int stageIndex, double profitR)
{
   if(!InpPyr_Enable) return;
   if(stageIndex <= 0 || stageIndex % InpPyr_Frequency != 0) return;
   if(profitR < InpPyr_MinProfitR) return;

   int gIdx = FindGroupIndex(groupId);
   if(gIdx < 0 || !g_groups[gIdx].active) return;
   if(g_groups[gIdx].addOnCount >= InpPyr_MaxAddOns) return;

   // Count total positions in group
   int groupPosCount = 0;
   for(int i = 0; i < ArraySize(g_states); i++)
      if(g_states[i].groupId == groupId && PositionSelectByTicket(g_states[i].ticket))
         groupPosCount++;
   if(groupPosCount >= InpAgg_MaxPositions) return;

   // Calculate risk with decay
   int addOnIdx = g_groups[gIdx].addOnCount;
   double addOnRisk = InpPyr_FirstRiskPct * MathPow(InpPyr_RiskDecay, (double)addOnIdx);
   addOnRisk = MathMax(addOnRisk, InpPyr_MinRiskPct);

   // Check aggregate risk budget
   double remainingBudget = InpAgg_MaxTotalRisk - g_groups[gIdx].aggregateRiskPct;
   if(addOnRisk > remainingBudget) addOnRisk = remainingBudget;
   if(addOnRisk < InpPyr_MinRiskPct) return; // Budget exhausted

   double approved = selfGov.ApproveRisk(addOnRisk);
   if(approved < 0.05) return;

   ENUM_ORDER_TYPE type = (g_groups[gIdx].direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string label = "Pyr" + IntegerToString(addOnIdx + 1);

   if(ExecuteTrade(type, approved, label, EQ_GOOD))
   {
      // Tag the new position state with group info
      int lastIdx = ArraySize(g_states) - 1;
      g_states[lastIdx].groupId = groupId;
      g_states[lastIdx].isAddOn = true;
      g_states[lastIdx].addOnIndex = addOnIdx + 1;

      g_groups[gIdx].addOnCount++;
      g_groups[gIdx].aggregateRiskPct += approved;

      Print("[PYRAMID #", addOnIdx + 1, "] Stage ", stageIndex,
            " | Risk: ", DoubleToString(approved, 2), "%",
            " | AggRisk: ", DoubleToString(g_groups[gIdx].aggregateRiskPct, 2), "%",
            " | ProfitR: ", DoubleToString(profitR, 2));

      // Apply group SL floor to the new add-on
      ApplyGroupSLFloor(groupId);
   }
}

//+------------------------------------------------------------------+
//| ADAPTIVE ESCALATOR HELPERS                                        |
//+------------------------------------------------------------------+

// Score-adaptive stage trigger R high score = wider, low score = tighter
double GetAdaptiveStageR(int stageIndex, double score)
{
   double baseR = CalculateStageR(stageIndex);
   if(!InpAdaptiveEscalator) return baseR;
   if(score >= CONFLUENCE_STRONG) // 13+
      return baseR * (1.0 + (score - CONFLUENCE_STRONG) * InpScoreAdaptFactor);
   if(score < CONFLUENCE_BASE)    // <10 (BASE tier)
      return baseR * 0.8;
   return baseR; // 10-12.9 = default
}

// Regime-aware harvest percentages — already baked into g_escCfg.baseHarvest,
// but this fine-tunes the formula output further if InpRegimeHarvest is on
double GetRegimeHarvestPct(int stageIndex, MARKET_REGIME reg)
{
   double basePct = CalculateHarvestPct(stageIndex);
   if(!InpRegimeHarvest) return basePct;

   if(reg == REGIME_TREND_STRONG) return basePct * 0.70;  // Let trend run, take less
   if(reg == REGIME_TREND_WEAK)   return basePct * 0.85;  // Slight reduction
   if(reg == REGIME_RANGING)      return basePct * 1.20;  // Take more — will reverse
   if(reg == REGIME_VOLATILE)     return basePct * 1.10;  // Slightly more — unpredictable
   return basePct; // CRISIS = already off via g_escCfg.enabled
}

// MFE-calibrated stage trigger (generalized for any stage)
double GetMFECalibratedStageR(int stageIndex, double entryScore = 0)
{
   double baseR = GetAdaptiveStageR(stageIndex, (entryScore > 0) ? entryScore : g_currentConfluence);
   if(!InpMFECalibration) return baseR;
   double avgMFE = learning.GetAvgMFE();
   if(avgMFE <= 0) return baseR;
   // Don't set stages beyond 90% of learned MFE (progressively conservative)
   double mfeCap = avgMFE * MathMax(0.5, 0.90 - stageIndex * 0.02);
   double prevStageR = (stageIndex > 0) ? CalculateStageR(stageIndex - 1) : 0;
   return MathMin(baseR, MathMax(mfeCap, prevStageR + 0.1));
}

//+------------------------------------------------------------------+
//| Momentum Exit: detect when trade lost its driving force          |
//| Returns true if position was closed (caller should continue)     |
//+------------------------------------------------------------------+
bool CheckMomentumExit(ulong ticket, int sIdx, long pType, double open, double curr, double profitR)
{
   if(!InpUseMomentumExit) return false;
   if(hADX == INVALID_HANDLE || hMACD == INVALID_HANDLE) return false;

   // ---- Read ADX buffers (3 bars: [0]=last closed, [1]=prev, [2]=2 bars ago) ----
   double adxMain[], diPlus[], diMinus[];
   ArraySetAsSeries(adxMain,  true);
   ArraySetAsSeries(diPlus,   true);
   ArraySetAsSeries(diMinus,  true);
   if(CopyBuffer(hADX, 0, 1, 3, adxMain)  < 3) return false;
   if(CopyBuffer(hADX, 1, 1, 3, diPlus)   < 3) return false;
   if(CopyBuffer(hADX, 2, 1, 3, diMinus)  < 3) return false;

   // ---- Read MACD histogram (buffer 2) ----
   double macdHist[];
   ArraySetAsSeries(macdHist, true);
   if(CopyBuffer(hMACD, 2, 1, 2, macdHist) < 2) return false;
   // [0]=last closed bar, [1]=bar before it

   // ============================================================
   // EVALUATE 5 MOMENTUM LOSS SIGNALS
   // ============================================================
   int exitScore = 0;
   string signals = "";

   // Signal 1: ADX was strong (>=Threshold) but now declining + DI flipped against trade
   bool adxWasStrong      = (adxMain[2] >= InpMomADX_Threshold || adxMain[1] >= InpMomADX_Threshold);
   bool adxNowFalling     = (adxMain[0] < adxMain[1]);
   bool diFlippedAgainst  = (pType == POSITION_TYPE_BUY) ? (diMinus[0] > diPlus[0])
                                                          : (diPlus[0] > diMinus[0]);
   if(adxWasStrong && adxNowFalling && diFlippedAgainst)
   { exitScore++; signals += "ADX "; }

   // Signal 2: RSI crossed the 50 midpoint against trade (momentum direction changed)
   bool rsiCrossedMid = (pType == POSITION_TYPE_BUY) ? (g_RSI_Prev >= 50.0 && g_RSI < 50.0)
                                                      : (g_RSI_Prev <= 50.0 && g_RSI > 50.0);
   if(rsiCrossedMid)
   { exitScore++; signals += "RSI50 "; }

   // Signal 3: MACD histogram crossed zero line against trade
   bool macdCrossedZero = (pType == POSITION_TYPE_BUY) ? (macdHist[1] > 0.0 && macdHist[0] <= 0.0)
                                                        : (macdHist[1] < 0.0 && macdHist[0] >= 0.0);
   if(macdCrossedZero)
   { exitScore++; signals += "MACD0 "; }

   // Signal 4: ATR collapsed relative to entry ATR (volatility drained — no energy left)
   if(g_states[sIdx].entryATR > _Point)
   {
      double atrRatio = g_ATR / g_states[sIdx].entryATR;
      if(atrRatio < InpMomATR_CollapseRatio)
      { exitScore++; signals += StringFormat("ATR%.0f%% ", atrRatio*100); }
   }

   // Signal 5: N bars without meaningful price progress in trade direction
   if(PositionSelectByTicket(ticket))
   {
      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      int barsHeld = GetBarsHeld(entryTime);
      if(barsHeld >= InpMomBarsNoProgress)
      {
         double minProgress = InpMomProgressATR * g_ATR;
         double maxMove = 0.0;
         if(pType == POSITION_TYPE_BUY)
         {
            int highBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, barsHeld, 1);
            maxMove = iHigh(_Symbol, PERIOD_CURRENT, highBar) - open;
         }
         else
         {
            int lowBar  = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, barsHeld, 1);
            maxMove = open - iLow(_Symbol, PERIOD_CURRENT, lowBar);
         }
         if(maxMove < minProgress)
         { exitScore++; signals += StringFormat("NoProgress(%db) ", barsHeld); }
      }
   }

   // ============================================================
   // EXIT DECISION
   // ============================================================
   if(exitScore < InpMomSignalsToExit) return false;

   if(!PositionSelectByTicket(ticket)) return false;
   double posProfit = PositionGetDouble(POSITION_PROFIT);
   bool   isLosing  = (posProfit < 0);

   if(!isLosing)
   {
      // Profitable trade: close — lock gains, momentum is gone
      Print("[MOM EXIT] #", ticket, " signals=", exitScore, "/5 [", signals, "]",
            " profit=", DoubleToString(posProfit,2), " profitR=", DoubleToString(profitR,2),
            " — closing (momentum exhausted)");
      if(InpEnableMobileAlerts)
         SendNotification("[MOM] " + _Symbol + " +" + DoubleToString(profitR,2) +
                          "R closed: momentum exhausted");
      trade.PositionClose(ticket);
      return true;
   }
   else
   {
      // ============================================================
      // LOSING TRADE: Evaluate recovery probability before closing
      // ============================================================
      int recoveryScore = 0;
      string recSignals = "";

      // Recovery 1: EMA200 trend still aligned with the trade
      bool trendAligned = (pType == POSITION_TYPE_BUY) ? (curr > g_EMA) : (curr < g_EMA);
      if(trendAligned) { recoveryScore++; recSignals += "EMA200 "; }

      // Recovery 2: RSI not deeply extended against trade direction (room to bounce)
      bool rsiHasRoom = (pType == POSITION_TYPE_BUY) ? (g_RSI > 25.0) : (g_RSI < 75.0);
      if(rsiHasRoom) { recoveryScore++; recSignals += "RSI-room "; }

      // Recovery 3: EMA50 still supportive (structure intact)
      if(hEMA50 != INVALID_HANDLE && InpUseReversalFilter)
      {
         bool ema50Aligned = (pType == POSITION_TYPE_BUY) ? (curr > g_EMA50) : (curr < g_EMA50);
         if(ema50Aligned) { recoveryScore++; recSignals += "EMA50 "; }
      }

      // Recovery 4: ADX still shows residual trend force (just declining, not dead)
      if(adxMain[0] > InpMomADX_Threshold * 0.65)
      { recoveryScore++; recSignals += "ADX-residual "; }

      Print("[MOM] #", ticket, " in loss (", DoubleToString(posProfit,2),
            ") | exitSig=", exitScore, "[", signals, "] | recovery=", recoveryScore,
            "/", InpMomRecoveryMinScore, " [", recSignals, "]");

      if(recoveryScore >= InpMomRecoveryMinScore)
      {
         Print("[MOM] Recovery signals present — keeping trade open");
         return false;
      }

      // No recovery: close the losing trade
      Print("[MOM EXIT] #", ticket, " no recovery — closing loss (",
            DoubleToString(profitR,2), "R)");
      if(InpEnableMobileAlerts)
         SendNotification("[MOM] " + _Symbol + " " + DoubleToString(profitR,2) +
                          "R closed: no recovery signal");
      trade.PositionClose(ticket);
      return true;
   }
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
                // Determine exit reason from DEAL_REASON (authoritative), not profit sign (unreliable)
                string exitReason = "UNKNOWN";
                for(int d = 0; d < HistoryDealsTotal(); d++)
                {
                   ulong dTick = HistoryDealGetTicket(d);
                   ENUM_DEAL_ENTRY dEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dTick, DEAL_ENTRY);
                   if(dEntry == DEAL_ENTRY_OUT || dEntry == DEAL_ENTRY_INOUT)
                   {
                      ENUM_DEAL_REASON dReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dTick, DEAL_REASON);
                      if(dReason == DEAL_REASON_SL)          exitReason = "SL";
                      else if(dReason == DEAL_REASON_TP)     exitReason = "TP";
                      else if(dReason == DEAL_REASON_EXPERT)
                         exitReason = "EA";
                      else                                   exitReason = "MANUAL";
                      break;
                   }
                }
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

                // Update Pattern Database R use factors captured at ENTRY bar, not current bar
                ConfluenceFactors factors = g_states[i].entryFactors;
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
                GlobalVariableSet("PG_ConsecLoss_" + _Symbol, g_consecutiveLosses); // Persist across restarts
                Print("[LOSS] Loss recorded: ", DoubleToString(profitR, 2), "R | Daily total: ",
                      DoubleToString(g_dailyLossR, 2), "R | Streak: ", g_consecutiveLosses);

                if(g_consecutiveLosses >= InpMaxConsecutiveLosses)
                {
                   Print("[WARNING] CONSECUTIVE LOSS LIMIT HIT: ", g_consecutiveLosses, " losses. Next trade will be blocked.");
                   GlobalVariableSet("GV_COOLDOWN_" + _Symbol, (double)TimeCurrent());
                }
             }
             else
             {
                if(g_consecutiveLosses > 0) Print("[WIN] Win breaks losing streak of ", g_consecutiveLosses);
                g_consecutiveLosses = 0;
                GlobalVariableSet("PG_ConsecLoss_" + _Symbol, 0); // Persist reset across restarts
             }
         }

         g_lastCloseTime = TimeCurrent();

          // Record ticket so OnTrade() won't double-call modules
          int pSz = ArraySize(g_processedOnTrade);
          ArrayResize(g_processedOnTrade, pSz + 1);
          g_processedOnTrade[pSz] = ticket;
          if(pSz > 100)  // Cap rolling window
          {
             for(int k = 0; k < pSz; k++) g_processedOnTrade[k] = g_processedOnTrade[k+1];
             ArrayResize(g_processedOnTrade, pSz);
          }
         for(int j=i; j<ArraySize(g_states)-1; j++) g_states[j] = g_states[j+1];
         ArrayResize(g_states, ArraySize(g_states)-1);
      }
   }

   // 2. Manage Open Positions
   // Momentum exit: gate to once per bar (crossover signals are bar-close events)
   static datetime s_prevMomBar = 0;
   datetime s_currBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isMomCheckBar = (s_currBar != s_prevMomBar);
   if(isMomCheckBar) s_prevMomBar = s_currBar;

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
         // Initialize infinite escalator fields
         g_states[stateCount].currentStage = -1;
         g_states[stateCount].locked_sl = 0;
         g_states[stateCount].totalHarvestedPct = 0;
         g_states[stateCount].initialVolume = vol;
         g_states[stateCount].isRunner = false;
         g_states[stateCount].groupId = g_activeGroupId;
         g_states[stateCount].isAddOn = false;
         g_states[stateCount].addOnIndex = 0;
         g_states[stateCount].lastPeakTime = TimeCurrent();
         g_states[stateCount].peakProfitR = 0;
         g_states[stateCount].barsAtStageNeg1 = 0;
         g_states[stateCount].entryKillzone  = GetActiveKillzone();
         g_states[stateCount].entryATR       = g_ATR;
         Print("Warning: Created fallback position state for ticket ", ticket, " - R-calculations may be approximate");
         sIdx = stateCount;
      }

      double risk = g_states[sIdx].initialRisk;  // kept for AdaptiveExitManager call below
      if(risk <= 0) risk = _Point * 100;

      double rawProfit = (pType == POSITION_TYPE_BUY) ? (curr - open) : (open - curr);
      // Use initialSLDist stored at entry R immune to trail movement; prevents premature partial/trail activation
      double slDist = (g_states[sIdx].initialSLDist > _Point) ? g_states[sIdx].initialSLDist
                    : (sl > 0)                                  ? MathAbs(open - sl)
                                                                : risk;
      double profitR = (slDist > _Point) ? rawProfit / slDist : 0;

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

      // ============================================================
      // LAYER 1: FORCE BREAKEVEN BEFORE KILLZONE ENDS
      // If KZ is about to close and trade has any profit but no Quick
      // Lock yet, force SL to entry so close-on-KZ-end exits at BE
      // worst case, not at a loss.
      // ============================================================
      if(InpCloseOnKillzoneEnd && InpKZBEMinutesBefore > 0 &&
         g_states[sIdx].currentStage < 0 &&
         g_states[sIdx].entryKillzone != KILLZONE_NONE &&
         g_states[sIdx].entryKillzone == GetActiveKillzone() &&
         profitR >= InpKZBEMinProfitR)
      {
         int minsLeft = GetMinutesToKZEnd();
         if(minsLeft >= 0 && minsLeft <= InpKZBEMinutesBefore)
         {
            // Move SL to entry + 1 point buffer to guarantee exit at BE or better
            double beSL = (pType == POSITION_TYPE_BUY)
                          ? open + _Point
                          : open - _Point;
            if(SafeModifySL(ticket, beSL, tp))
            {
               g_states[sIdx].locked_sl  = beSL;
               g_states[sIdx].currentStage = 0;  // Mark Quick Lock done (BE is set)
               Print("[KZ BE] Ticket #", ticket,
                     " forced BE - KZ ends in ", minsLeft, " mins"
                     " | profitR=", DoubleToString(profitR, 2));
               if(InpEnableMobileAlerts)
                  SendNotification("[KZ BE] " + _Symbol + " #" + IntegerToString((int)ticket) +
                                   " BE set, KZ ends in " + IntegerToString(minsLeft) + "m");
            }
         }
      }

      // ============================================================
      // STALE TRADE EXIT
      // If Quick Lock hasn't triggered after N bars, the trade is going
      // nowhere R exit before it bleeds further.
      // barsAtStageNeg1 = bars held since entry with no Quick Lock
      // ============================================================
      if(InpUseStaleTrade && InpStaleBarLimit > 0 && g_states[sIdx].currentStage < 0)
      {
         // Count bars elapsed since entry (not ticks) using the entry timestamp
         if(PositionSelectByTicket(ticket))
         {
            datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
            int barsHeld = GetBarsHeld(entryTime);
            g_states[sIdx].barsAtStageNeg1 = barsHeld;

            if(barsHeld >= InpStaleBarLimit)
            {
               if(profitR > 0)
               {
                  // In profit but stale: take what we have, no point waiting
                  Print("[STALE EXIT] Ticket #", ticket,
                        " | ", barsHeld, " bars with no Quick Lock",
                        " | ProfitR: ", DoubleToString(profitR, 2),
                        " | Closing in profit.");
                  if(InpEnableMobileAlerts)
                     SendNotification("[STALE] " + _Symbol + " closed +" + DoubleToString(profitR,2) + "R after " + IntegerToString(barsHeld) + " bars");
                  if(trade.PositionClose(ticket))
                     continue;
               }
               else
               {
                  // In loss: do NOT close manually (adds to loss). Let original SL protect.
                  // Tighten SL toward entry to cap further damage.
                  double entrySL = (pType == POSITION_TYPE_BUY)
                                   ? open - g_states[sIdx].initialSLDist * 0.5
                                   : open + g_states[sIdx].initialSLDist * 0.5;
                  if(SafeModifySL(ticket, entrySL, tp))
                     Print("[STALE TIGHTEN] Ticket #", ticket,
                           " | stale in loss (", DoubleToString(profitR,2), "R)"
                           " | SL tightened to 50% of initial distance");
               }
            }
         }
      }


      // ============================================================
      // MOMENTUM EXIT CHECK (once per bar, before trailing logic)
      // ============================================================
      if(isMomCheckBar && CheckMomentumExit(ticket, sIdx, pType, open, curr, profitR))
         continue;

      // Skip trailing if Mode 2 (Adaptive only) and TP is set
      if(InpTPMode == 2 && tp > 0 && InpTrailingMode == 0)
      {
         continue;  // Let TP handle exit
      }

      // Mode 3 (Hybrid): Allow trailing even with TP set
      // Mode 1 (Fixed): Respect InpTrailingMode setting
      if(InpTrailingMode >= 1)
      {
         // ============================================================
         // INFINITE ESCALATOR: N-Stage Dynamic Profit Locking
         // Stage 0: Quick Lock (SL near entry, no harvest)
         // Stage 1..N: Harvest declining %, ratchet SL up
         // Runner: When volume < 2*minLot, stop harvesting, let it ride
         // ============================================================

         // --- Update Peak Profit Tracking (for time-decay trail) ---
         if(profitR > g_states[sIdx].peakProfitR)
         {
            g_states[sIdx].peakProfitR = profitR;
            g_states[sIdx].lastPeakTime = TimeCurrent();
         }

         // --- CHAOS EMERGENCY LOCK ---
         if(InpChaosEmergencyLock && InpAdaptiveEscalator && g_currentRegime == REGIME_CHAOS)
         {
            if(g_states[sIdx].currentStage < 0 && profitR > 0)
            {
               // Force Quick Lock
               double emergSL = (pType == POSITION_TYPE_BUY)
                              ? open + (slDist * InpEsc_FirstSL_R)
                              : open - (slDist * InpEsc_FirstSL_R);
               bool canMoveE = (pType == POSITION_TYPE_BUY) ? (emergSL > sl || sl == 0) : (emergSL < sl || sl == 0);
               if(canMoveE && SafeModifySL(ticket, emergSL, tp))
               {
                  g_states[sIdx].currentStage = 0;
                  g_states[sIdx].beMovedToEntry = true;
                  g_states[sIdx].locked_sl = emergSL;
                  Print("[CHAOS LOCK] Emergency S0 @ ", DoubleToString(emergSL, _Digits));
               }
            }
            if(g_states[sIdx].currentStage == 0 && profitR > 0.3 && !g_states[sIdx].isRunner)
            {
               // Force first harvest
               double chaosHarvest = GetRegimeHarvestPct(1, g_currentRegime);
               if(CanHarvest(ticket, chaosHarvest))
               {
                  double currentVolC = PositionGetDouble(POSITION_VOLUME);
                  double closeVolC = NormalizeDouble(currentVolC * (chaosHarvest / 100.0), 2);
                  if(trade.PositionClosePartial(ticket, closeVolC))
                  {
                     g_states[sIdx].currentStage = 1;
                     g_states[sIdx].totalHarvestedPct += chaosHarvest;
                     g_states[sIdx].partialClosed = true;
                     double chaosSL = (pType == POSITION_TYPE_BUY) ? open + (slDist * CalculateSLLockR(1)) : open - (slDist * CalculateSLLockR(1));
                     bool canMoveC = (pType == POSITION_TYPE_BUY) ? (chaosSL > sl) : (chaosSL < sl);
                     if(canMoveC && SafeModifySL(ticket, chaosSL, tp)) g_states[sIdx].locked_sl = chaosSL;
                     Print("[CHAOS HARVEST] ", DoubleToString(closeVolC, 2), " lots @ ", DoubleToString(profitR, 2), "R");
                  }
               }
            }
         }

         // --- N-STAGE ESCALATOR LOOP ---
         if(!g_states[sIdx].isRunner)
         {
            for(int stage = g_states[sIdx].currentStage + 1; stage < g_escCfg.maxStages; stage++)
            {
               // MFE-calibrated trigger already includes score adaptation via GetAdaptiveStageR()
               double triggerR = InpMFECalibration
                               ? GetMFECalibratedStageR(stage, g_states[sIdx].entryScore)
                               : GetAdaptiveStageR(stage, g_states[sIdx].entryScore);
               if(profitR < triggerR) break; // Haven't reached next stage

               if(stage == 0)
               {
                  // --- QUICK LOCK: Move SL, no harvest ---
                  double lockSL = (pType == POSITION_TYPE_BUY)
                                ? open + (slDist * g_escCfg.firstSL_R)
                                : open - (slDist * g_escCfg.firstSL_R);
                  bool canMove0 = (pType == POSITION_TYPE_BUY)
                                ? (lockSL > sl || sl == 0)
                                : (lockSL < sl || sl == 0);
                  if(canMove0 && SafeModifySL(ticket, lockSL, tp))
                  {
                     g_states[sIdx].beMovedToEntry = true;
                     g_states[sIdx].locked_sl = lockSL;
                     Print("[ESC S0] Quick Lock @ ", DoubleToString(lockSL, _Digits),
                           " | R:", DoubleToString(profitR, 2));
                  }
               }
               else
               {
                  // --- HARVEST STAGE: Partial close + ratchet SL ---
                  double harvestPct = GetRegimeHarvestPct(stage, g_currentRegime);

                  if(!CanHarvest(ticket, harvestPct))
                  {
                     // Volume too small to harvest - become RUNNER
                     g_states[sIdx].isRunner = true;
                     Print("[ESC] -> RUNNER at stage ", stage,
                           " | Harvested: ", DoubleToString(g_states[sIdx].totalHarvestedPct, 1), "%",
                           " | R:", DoubleToString(profitR, 2));
                     break;
                  }

                  // Refresh volume after potential previous harvests in same tick
                  if(!PositionSelectByTicket(ticket)) break;
                  double currentVol = PositionGetDouble(POSITION_VOLUME);
                  double closeVol = NormalizeDouble(currentVol * (harvestPct / 100.0), 2);

                  if(trade.PositionClosePartial(ticket, closeVol))
                  {
                     g_states[sIdx].partialClosed = true;
                     g_states[sIdx].totalHarvestedPct += harvestPct;
                     if(stage == 1) learning.SetPartialClosed(ticket, true);

                     // Ratchet SL to previous stage's trigger level
                     double slLockR = CalculateSLLockR(stage);
                     double stageSL = (pType == POSITION_TYPE_BUY)
                                    ? open + (slDist * slLockR)
                                    : open - (slDist * slLockR);
                     bool canMoveS = (pType == POSITION_TYPE_BUY)
                                   ? (stageSL > sl)
                                   : (stageSL < sl);
                     if(canMoveS)
                     {
                        // Refresh TP after partial close
                        if(PositionSelectByTicket(ticket)) tp = PositionGetDouble(POSITION_TP);
                        if(SafeModifySL(ticket, stageSL, tp))
                           g_states[sIdx].locked_sl = stageSL;
                     }

                     Print("[ESC S", stage, "] Harvest ", DoubleToString(harvestPct, 1), "% (",
                           DoubleToString(closeVol, 2), " lots) @ ", DoubleToString(profitR, 2),
                           "R | SL: ", DoubleToString(stageSL, _Digits),
                           " | Total: ", DoubleToString(g_states[sIdx].totalHarvestedPct, 1), "%");

                     // --- SCALE-IN CHECK at this stage ---
                     if(g_states[sIdx].groupId > 0)
                        TryScaleIn(g_states[sIdx].groupId, stage, profitR);
                  }
               }

               g_states[sIdx].currentStage = stage;

               // Update group highest stage
               if(g_states[sIdx].groupId > 0)
               {
                  int gIdx = FindGroupIndex(g_states[sIdx].groupId);
                  if(gIdx >= 0 && stage > g_groups[gIdx].highestStage)
                  {
                     g_groups[gIdx].highestStage = stage;
                     ApplyGroupSLFloor(g_states[sIdx].groupId);
                  }
               }
            }
         }

         // ============================================================
         // DYNAMIC ATR TRAILING SYSTEM (with time-decay tightening)
         // Applies to RUNNER (after harvests exhausted) or full position
         // if stages haven't triggered yet
         // ============================================================
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
                if(quality == EQ_WEAK)  dynMult *= 0.8;
                if(quality == EQ_ELITE) dynMult *= 1.2;

                // Step 3: Regime-aware adjustment (5-regime)
                if(InpTrailRegimeAware)
                {
                   if(g_currentRegime == REGIME_TREND_STRONG) dynMult *= 1.2;
                   else if(g_currentRegime == REGIME_TREND_WEAK) dynMult *= 1.0;
                   else if(g_currentRegime == REGIME_RANGING)   dynMult *= 0.7;
                   else if(g_currentRegime == REGIME_VOLATILE)  dynMult *= 0.85;
                }

                // Step 4: Runner trail R WIDEN to let the 20% runner chase the home run
                // We already secured 80% of profits in Stage 2+3, so this runner gets room
                // InpRunnerTrailTight < 1.0 = tighter, > 1.0 = wider
                // For scalping: use wider trail (1.5x) so the runner can reach 2-3R
                if(g_states[sIdx].isRunner)
                {
                   // Runner gets breathing room R widen trail to let it ride
                   dynMult *= 1.5;  // 1.5x wider trail for the runner portion
                   // But cap it so it doesn't become absurd
                   dynMult = MathMin(dynMult, InpTrailATR_Mult * 2.0);
                }

                // Step 5: TIME-DECAY TIGHTENING
                // If profit hasn't made new high in X minutes, tighten trail aggressively
                // EXCEPTION: Runner gets 3x more patience (let it ride for the home run)
                double minutesSincePeak = (double)(TimeCurrent() - g_states[sIdx].lastPeakTime) / 60.0;
                double staleMins = g_escCfg.timeStaleMins;   // dynamic per regime
                if(g_states[sIdx].isRunner) staleMins *= 3.0; // runner gets 3x patience

                if(minutesSincePeak > staleMins)
                   dynMult *= InpTimeStaleTight2;   // Aggressive tightening (keep as input — fine-tune per pair)
                else if(minutesSincePeak > staleMins * 0.5)
                   dynMult *= InpTimeStaleTight1;   // Moderate tightening

                // Step 6: RSI MOMENTUM TRAIL (Adaptive Escalator 4D)
                if(InpMomentumTrail && InpAdaptiveEscalator && g_states[sIdx].isRunner)
                {
                   double rsiArr[1], rsiArr3[1];
                   if(CopyBuffer(hRSI, 0, 0, 1, rsiArr) == 1 && CopyBuffer(hRSI, 0, 3, 1, rsiArr3) == 1)
                   {
                      double rsiAccel = rsiArr[0] - rsiArr3[0];
                      bool isBuy = (pType == POSITION_TYPE_BUY);
                      // Momentum accelerating in our direction → widen trail
                      if((isBuy && rsiAccel > 5) || (!isBuy && rsiAccel < -5))
                         dynMult *= 1.3;
                      // Momentum decelerating → tighten trail
                      else if((isBuy && rsiAccel < -5) || (!isBuy && rsiAccel > 5))
                         dynMult *= 0.6;
                   }
                }

                // Re-apply floor after all adjustments
                dynMult = MathMax(dynMult, InpTrailMinMult * 0.5); // Allow tighter than base floor for time-decay

                // Step 6: Dynamic floor price (trail behind current price)
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

                // --- ESCALATOR FLOOR: Never go below locked SL level ---
                if(g_states[sIdx].locked_sl > 0)
                {
                   if(pType == POSITION_TYPE_BUY)
                      bestSL = MathMax(bestSL, g_states[sIdx].locked_sl);
                   else
                      bestSL = MathMin(bestSL, g_states[sIdx].locked_sl);
                }

                // --- MINIMUM BUFFER: broker stop level vs ATR noise floor ---
                double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                double minBuffer  = MathMax(stopsLevel, atrVal * InpTrailMinBufferATR);

                // --- APPLY: Only move SL in favorable direction with safe distance ---
                bool slBetter = (pType == POSITION_TYPE_BUY)
                                ? (bestSL > sl + _Point*5 && bestSL < curr - minBuffer)
                                : ((bestSL < sl - _Point*5 || sl == 0) && bestSL > curr + minBuffer);

                if(slBetter)
                {
                   if(SafeModifySL(ticket, bestSL, tp))
                   {
                      g_states[sIdx].locked_sl = bestSL; // Update locked SL
                      Print("DynTrail: mult=", DoubleToString(dynMult,2),
                            " stale=", DoubleToString(minutesSincePeak,0), "m",
                            " floor=", DoubleToString(dynFloor,_Digits),
                            " ce=", DoubleToString(chandelierSL,_Digits),
                            " best=", DoubleToString(bestSL,_Digits),
                            " R=", DoubleToString(profitR,2),
                            g_states[sIdx].isRunner ? " [RUNNER]" : "");
                   }
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

// NOTE: CheckAddOnOpportunity() removed R pyramiding now handled by
// TryScaleIn() inside the Infinite Escalator loop in ManagePositions()

//+------------------------------------------------------------------+
//| PHASE 1: Update all indicators once per bar with caching          |
//+------------------------------------------------------------------+
void UpdateAllIndicators()
{
   // Removed bar-based caching to allow throttled mid-bar updates
   g_lastIndicatorCacheTime = TimeCurrent();

   // Cache SMC scores
   if(InpUseSMC)
   {
      g_cachedSMCScore_Buy = 0;
      g_cachedSMCScore_Sell = 0;

      // Structure breaks
      double structScore = smcStructure.GetConfluenceScore(1);
      g_cachedSMCScore_Buy += structScore;
      structScore = smcStructure.GetConfluenceScore(-1);
      g_cachedSMCScore_Sell += structScore;

      // Order blocks
      double obScore = smcOrderBlocks.GetConfluenceScore(1);
      g_cachedSMCScore_Buy += obScore;
      obScore = smcOrderBlocks.GetConfluenceScore(-1);
      g_cachedSMCScore_Sell += obScore;

      // Fair Value Gaps
      double fvgScore = smcFVG.GetConfluenceScore(1);
      g_cachedSMCScore_Buy += fvgScore;
      fvgScore = smcFVG.GetConfluenceScore(-1);
      g_cachedSMCScore_Sell += fvgScore;

      // Liquidity sweeps
      double liqScore = smcLiquidity.GetConfluenceScore(1);
      g_cachedSMCScore_Buy += liqScore;
      liqScore = smcLiquidity.GetConfluenceScore(-1);
      g_cachedSMCScore_Sell += liqScore;
   }

   // Cache MTF scores
   if(InpUseMTF)
   {
      g_cachedMTFScore_Buy = mtfAnalysis.GetConfluenceScore(1);
      g_cachedMTFScore_Sell = mtfAnalysis.GetConfluenceScore(-1);
   }

   // Cache Volume scores
   g_cachedVolumeScore_Buy = volumeAnalysis.GetConfluenceScore(1);
   g_cachedVolumeScore_Sell = volumeAnalysis.GetConfluenceScore(-1);

   // Cache Divergence scores
   g_cachedDivergenceScore_Buy = divergence.GetDivergenceScore(1, hRSI);
   g_cachedDivergenceScore_Sell = divergence.GetDivergenceScore(-1, hRSI);
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

   // PHASE 1: Update all indicator caches once per bar
   UpdateAllIndicators();
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

   // PHASE 3: Get regime-adaptive weights
   double weights[];
   g_regimeEngine.GetAdaptiveWeights(g_currentRegime, weights);

   // ============ 1. CORE SMC & PRICE ACTION (Max ~13.0 pts) ============

   // A. Trend (EMA 200 + Slope) - 4.0 points (boosted: foundation signal)
   double emaSlope = g_EMA - g_EMA_Prev;
   bool slopeAligned = (direction == 1 && emaSlope > 0) || (direction == -1 && emaSlope < 0);
   bool priceAligned = (direction == 1 && currentPrice > g_EMA) || (direction == -1 && currentPrice < g_EMA);

   if(priceAligned) score += 2.0 * weights[0]; // Apply trend weight (was 1.5)
   if(slopeAligned) score += 2.0 * weights[0]; // Apply trend weight (was 1.5)

   // B. Structure (Bos/Choch) - 4.0 points (boosted: confirms intent)
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 1);
   int lowestBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback, 1);
   double structRange = 0;
   if(highestBar >= 0 && lowestBar >= 0)
      structRange = iHigh(_Symbol, PERIOD_CURRENT, highestBar) - iLow(_Symbol, PERIOD_CURRENT, lowestBar);

   bool validStructure = (structRange >= g_ATR * 2.0);

   if(direction == 1 && highestBar < lowestBar && validStructure) score += 4.0 * weights[1]; // (was 3.0)
   if(direction == -1 && lowestBar < highestBar && validStructure) score += 4.0 * weights[1]; // (was 3.0)

   // C. RSI Extremes - 2.0 points
   bool rsiValid = false;
   if(g_currentRegime == REGIME_TREND)
   {
      if(direction == 1 && g_RSI < 60 && g_RSI > 40) rsiValid = true;
      if(direction == -1 && g_RSI > 40 && g_RSI < 60) rsiValid = true;
   }
   else
   {
      if(direction == 1 && g_RSI <= InpRSI_Oversold) rsiValid = true;
      if(direction == -1 && g_RSI >= InpRSI_Overbought) rsiValid = true;
   }
   if(rsiValid) score += 2.0;

   // D. Displacement - 3.0 points (boosted: institutional movement force)
   bool hasDisplacement = CheckDisplacement(direction);
   if(hasDisplacement) score += 3.0; // Was 2.0


   // ============ 2. MOMENTUM & VOLATILITY (Max ~3.0 pts - reduced noise) ============

   // RSI Momentum - 1.5 points
   if(InpRSI_Momentum)
   {
      if(direction == 1 && g_RSI > g_RSI_Prev) score += 1.5;
      if(direction == -1 && g_RSI < g_RSI_Prev) score += 1.5;
   }

   // Volatility Ratio - 1.0 point (was 2.0 - fires on almost every bar, reduced)
   double atrRatio = 1.0;
   if(g_ATR > 0 && g_ATR_MA > 0) atrRatio = g_ATR / g_ATR_MA;
   if(atrRatio >= 0.7 && atrRatio <= 1.5) score += 1.0;

   // Chop Filter (Cleanliness) - 0.5 pts (was 1.5 - negative should block, positive shouldn't inflate)
   if(!CheckChopFilter()) score += 0.5;

   // ============ SIGNAL CONVICTION BONUS (+3.0 pts) ============
   // If 3+ core signals align, reward the confluence
   int coreSignals = 0;
   if(priceAligned || slopeAligned) coreSignals++;
   if(validStructure && ((direction == 1 && highestBar < lowestBar) || (direction == -1 && lowestBar < highestBar))) coreSignals++;
   if(hasDisplacement) coreSignals++;
   if(rsiValid) coreSignals++;
   if(coreSignals >= 3) score += 3.0; // Core conviction bonus


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

   // Institutional Volume - 4.0 pts (RVOL + Money Flow) - PHASE 3: volume weight
   score += volumeAnalysis.GetConfluenceScore(direction) * weights[3];

   // Multi-Timeframe - 2.0 pts - PHASE 3: MTF weight
   if(InpUseMTF)
      score += mtfAnalysis.GetConfluenceScore(direction) * weights[4];

   // Divergence - 2.0 pts
   double divergenceScore = divergence.GetDivergenceScore(direction, hRSI);
   score += divergenceScore * 2.0; // Scale 0-1 -> 0-2

   // Wyckoff - 2.0 pts
   score += wyckoff.GetWyckoffScore(direction, g_ATR) * 2.0;

   // ============ 4.5. METALS ANALYSIS (Metals Only, -5 to +6 pts) ============

   if(GetCorrelationGroup(_Symbol) == GROUP_METALS)
   {
      // Specialized metals analysis: DXY correlation, safe-haven flows, volatility regime, seasonal
      double metalsScore = metalsAnalysis.GetConfluenceScore(direction);
      score += metalsScore;
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
           if(divergenceScore < 0.5)
           {
               score -= 2.0; 
               if(score < 0) score = 0;
           }
       }
   }

   // PHASE 3: Confluence clustering bonus
   // Check if multiple factors align in same price zone (within 0.5 ATR)
   double clusterZone = g_ATR * 0.5;
   int factorsInCluster = 0;

   // Track key price levels
   double obTop = 0, obBottom = 0;
   bool hasOB = smcOrderBlocks.IsInOrderBlock(direction, obTop, obBottom);

   double fvgTop = 0, fvgBottom = 0;
   bool hasFVG = smcFVG.IsInFVG(direction, fvgTop, fvgBottom);

   // Check if multiple factors cluster around current price
   if(hasOB && MathAbs(currentPrice - obBottom) < clusterZone) factorsInCluster++;
   if(hasFVG && MathAbs(currentPrice - fvgBottom) < clusterZone) factorsInCluster++;

   // Check if Fib level is near current price
   if(highestBar >= 0 && lowestBar >= 0)
   {
      double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, highestBar);
      double swingLow = iLow(_Symbol, PERIOD_CURRENT, lowestBar);
      double range = swingHigh - swingLow;

      if(range >= g_ATR * 1.5)
      {
         double fibLevel = (direction == 1) ? (swingHigh - range * 0.618) : (swingLow + range * 0.618);
         if(MathAbs(currentPrice - fibLevel) < clusterZone) factorsInCluster++;
      }
   }

   // Award clustering bonus
   if(factorsInCluster >= 2) score += 1.0; // 2+ factors aligned
   if(factorsInCluster >= 3) score += 1.5; // 3+ factors aligned (strong cluster)

   // Populate REAL ConfluenceFactors for AdaptiveFilter and PatternRecognizer
   // These are the actual computed values, not score-based proxies
   ConfluenceFactors outFactors;
   if(direction == 1) outFactors = g_lastBuyFactors;
   else outFactors = g_lastSellFactors;
   outFactors.trendAligned   = priceAligned || slopeAligned;
   outFactors.structureBreak = validStructure;
   outFactors.fibZone        = false;  // Will be set by Fib Zone block above - approximated here
   outFactors.rsiMomentum    = rsiValid || (InpRSI_Momentum && ((direction==1 && g_RSI > g_RSI_Prev) || (direction==-1 && g_RSI < g_RSI_Prev)));
   outFactors.orderBlock     = hasOB;
   outFactors.fvg            = hasFVG;
   outFactors.liquiditySweep = InpUseSMC && smcLiquidity.GetConfluenceScore(direction) > 0;
   outFactors.killzoneActive = false;  // Set by killzone check upstream
   outFactors.mtfAligned     = InpUseMTF && mtfAnalysis.GetConfluenceScore(direction) > 0;
   outFactors.killzone       = KILLZONE_NONE;
   outFactors.regime         = g_currentRegime;
   outFactors.confluenceScore = score;

   // Write back to global factors
   if(direction == 1) g_lastBuyFactors = outFactors;
   else g_lastSellFactors = outFactors;

   return score;  // Max possible: ~30-37 points (with clustering bonus)
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

bool CheckSpread(bool isEntry = false)
{
   if(InpMaxSpreadPoints <= 0) return true;

   // OPTIMIZATION: Cache spread value to avoid multiple calls
   static int lastSpread = 0;
   static datetime lastSpreadCheck = 0;

   // Update spread every 5 seconds (spreads don't change that fast), or immediately if it's an entry
   if(isEntry || TimeCurrent() - lastSpreadCheck >= 5)
   {
      lastSpread = (int)symbolInfo.Spread();
      lastSpreadCheck = TimeCurrent();
   }

   if(lastSpread > InpMaxSpreadPoints)
   {
      static datetime lastSpreadWarning = 0;
      if(TimeCurrent() - lastSpreadWarning > 60)
      {
         Print("R [WARN] Spread too wide: ", lastSpread, " > ", InpMaxSpreadPoints, " points");
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
      Print("R Lots capped: ", DoubleToString(lots, 3), " -> ", DoubleToString(InpMaxLotsPerTrade, 2));
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

   string govStatus = selfGov.GetStatus();
   string tradingStatus = selfGov.IsTradingEnabled() ? "ACTIVE" : "PAUSED (DD)";

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

   // Escalator & Group info for active positions
   for(int si = 0; si < ArraySize(g_states); si++)
   {
      if(!PositionSelectByTicket(g_states[si].ticket)) continue;
      string tag = g_states[si].isRunner ? " [RUNNER]" : "";
      string addon = g_states[si].isAddOn ? " Pyr#" + IntegerToString(g_states[si].addOnIndex) : "";
      string staleTag = "";
      if(InpUseStaleTrade && g_states[si].currentStage < 0 && InpStaleBarLimit > 0)
      {
         int pct = (int)(100.0 * g_states[si].barsAtStageNeg1 / InpStaleBarLimit);
         staleTag = " STALE:" + IntegerToString(g_states[si].barsAtStageNeg1) + "/" + IntegerToString(InpStaleBarLimit) + "b";
         if(pct >= 75) staleTag += "!";
      }
      txt += "#" + IntegerToString((int)g_states[si].ticket) + addon +
             " S" + IntegerToString(g_states[si].currentStage) +
             " H:" + DoubleToString(g_states[si].totalHarvestedPct, 0) + "%" +
             tag + staleTag + "\n";
   }

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

   // 1. Asian Session (20:00 - 01:00 EST)
   if(InpEnableAsianKZ && (estHour >= 20 || estHour < 1)) return KILLZONE_ASIAN;

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

//+------------------------------------------------------------------+
//| Minutes remaining until current killzone ends (-1 if none)       |
//+------------------------------------------------------------------+
int GetMinutesToKZEnd()
{
   ENUM_KILLZONE kz = GetActiveKillzone();
   if(kz == KILLZONE_NONE) return -1;

   datetime utcTime = TimeCurrent() - (InpBrokerUTCOffset * 3600);
   MqlDateTime utcDt;
   TimeToStruct(utcTime, utcDt);
   int estHour = (utcDt.hour - 5 + 24) % 24;
   int currentMins = estHour * 60 + utcDt.min;

   int endMins = 0;
   if(kz == KILLZONE_ASIAN)        endMins =  1 * 60;  // ends 01:00 EST
   if(kz == KILLZONE_LONDON_OPEN)  endMins =  5 * 60;  // ends 05:00 EST
   if(kz == KILLZONE_NY)           endMins = 10 * 60;  // ends 10:00 EST
   if(kz == KILLZONE_LONDON_CLOSE) endMins = 12 * 60;  // ends 12:00 EST

   int remaining = endMins - currentMins;
   if(remaining < 0) remaining += 24 * 60;  // midnight wrap (Asian KZ)
   return remaining;
}

