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
#include "Include\KillzoneOptimizer.mqh"
#include "Include\KellyPositionSizer.mqh"

// Learning & Memory Modules
#include "Include\Memory\TradeJournal.mqh"
#include "Include\Memory\PatternMemory.mqh"
#include "Include\Learning\PerformanceAnalyzer.mqh"
#include "Include\Learning\PatternRecognizer.mqh"

// Adaptive Modules
#include "Include\Adaptive\AdaptiveRiskManager.mqh"
#include "Include\Adaptive\AdaptiveExitManager.mqh"
#include "Include\Adaptive\AdaptiveFilterManager.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "======= IDENTITY ======="
input int               InpMagicNumber = 100001;          // Magic Number (unique per symbol)

input group "======= DIRECTION ======="
input int               InpDirection = 0;                 // 0=Both, 1=Buy, 2=Sell
input int               InpBrokerUTCOffset = 2;

input group "======= KILLZONES ======="
input bool              InpUseKillzoneFilter = true;      // Enable Killzone Filter
input bool              InpUseSymbolDefaults = true;      // Use Symbol-Specific Defaults
input bool              InpAutoDST = true;                // Auto-adjust for DST

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

input group "======= KILLZONE SELECTION (if not using Symbol Defaults) ======="
input bool              InpEnableAsianKZ = false;         // Enable Asian Killzone
input bool              InpEnableLondonOpenKZ = true;     // Enable London Open Killzone
input bool              InpEnableNYKZ = true;             // Enable NY Killzone
input bool              InpEnableLondonCloseKZ = false;   // Enable London Close Killzone
input bool              InpFocusPrimeOnly = false;        // Only Trade Prime Killzones

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
input bool              InpEnableAdaptiveFilters = false; // Enable Adaptive Filters

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

// SMC MODULE OBJECTS
CSMCStructureBreak  smcStructure;
CSMCOrderBlocks     smcOrderBlocks;
CSMCFairValueGap    smcFVG;
CSMCLiquiditySweep  smcLiquidity;

// ADVANCED FILTER OBJECTS
CMTFConfluence      mtfAnalysis;
CNewsFilter         newsFilter;
CKillzoneOptimizer  killzoneOptimizer;
CKellyPositionSizer kellySizer;

// LEARNING & MEMORY OBJECTS
CTradeJournal       tradeJournal;
CPatternMemory      patternMemory;
CPerformanceAnalyzer performanceAnalyzer;
CPatternRecognizer  patternRecognizer;

// ADAPTIVE OBJECTS
CAdaptiveRiskManager   adaptiveRisk;
CAdaptiveExitManager   adaptiveExit;
CAdaptiveFilterManager adaptiveFilter;

int hRSI, hATR, hEMA;
double g_RSI, g_RSI_Prev, g_ATR, g_EMA, g_EMA_Prev, g_ATR_MA;

datetime lastBarTime = 0;

int g_entryDirection = 0;
double g_currentConfluence = 0;
int g_positionCount = 0;
bool g_addOn1Triggered = false;
bool g_addOn2Triggered = false;
datetime g_lastCloseTime = 0;
ulong g_lastTickTime = 0;

int g_bias = 0;
datetime g_lastLossTime = 0;
MARKET_REGIME g_currentRegime = REGIME_UNKNOWN;

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

   failSafe.Init(InpMaxSpreadPoints);
   ArrayResize(g_states, 0);

   // Initialize Learning Engine with persistence
   if(InpEnableLearning)
   {
      learning.Init(_Symbol, true);  // Enable persistence
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
   }

   // Initialize Killzone Optimizer
   if(InpUseKillzoneFilter)
   {
      if(InpUseSymbolDefaults)
      {
         // Use symbol-specific defaults
         killzoneOptimizer.Init(_Symbol, InpBrokerUTCOffset, true, InpAutoDST, InpFocusPrimeOnly);
      }
      else
      {
         // Use manual killzone selection
         killzoneOptimizer.Init(_Symbol, InpBrokerUTCOffset,
                                InpEnableAsianKZ, InpEnableLondonOpenKZ,
                                InpEnableNYKZ, InpEnableLondonCloseKZ,
                                InpFocusPrimeOnly, InpAutoDST);
      }
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

   // Initialize Trade Journal (Learning System)
   if(InpEnableLearning && InpLogTradesToFile)
   {
      if(!tradeJournal.Init(_Symbol, InpLearningHistory))
         Print("Warning: Trade Journal initialization failed");
   }

   // Initialize Performance Analyzer
   if(InpEnableLearning)
   {
      if(!performanceAnalyzer.Init(_Symbol, &tradeJournal, InpMinTradesForLearning))
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

   // Check if Governor is running
   string govStatus = allocator.IsGovernorActive() ? "Connected" : "Standalone";

   Print("===========================================");
   Print("  SYMBOL ENGINE v2.0: ", _Symbol);
   Print("  Magic: ", InpMagicNumber);
   Print("  Governor: ", govStatus);
   Print("  SMC: ", InpUseSMC ? "ON" : "OFF");
   Print("  MTF: ", InpUseMTF ? "ON" : "OFF");
   Print("  News Filter: ", InpUseNewsFilter ? "ON" : "OFF");
   Print("  Killzone Filter: ", InpUseKillzoneFilter ? "ON" : "OFF");
   Print("  Kelly Sizing: ", InpUseKelly ? "ON" : "OFF");
   Print("  Learning System: ", InpEnableLearning ? "ON" : "OFF");
   if(InpEnableLearning && InpLogTradesToFile)
      Print("  Trade Journal: ACTIVE (", InpLearningHistory, " days history)");
   if(InpEnableLearning)
   {
      Print("  Performance Analyzer: ACTIVE (", performanceAnalyzer.GetTradeCount(), " trades loaded)");
      Print("  Pattern Learning: ACTIVE (", patternMemory.GetPatternCount(), " patterns loaded)");
      Print("  Adaptive Risk: ", InpEnableAdaptiveRisk ? "ON" : "OFF");
      Print("  Adaptive Exits: ", InpEnableAdaptiveExits ? "ON" : "OFF");
      Print("  Adaptive Filters: ", InpEnableAdaptiveFilters ? "ON" : "OFF");
   }
   Print("===========================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);

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
   ArrayResize(g_states, 0);
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
         tpR = adaptiveExit.CalculateFixedTP(g_currentRegime, quality, atr, slDist);
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
   symbolInfo.RefreshRates();

   g_positionCount = CountPositions();
   if(g_positionCount == 0) ResetTradeState();

   ManagePositions();
   UpdateDashboard();

   if(!IsNewBar()) return;
   if(!UpdateIndicators()) return;

   // --- UPDATE ALL MODULES ON NEW BAR ---
   UpdateModules();

   // --- MODULE: FAIL SAFE ---
   if(!failSafe.IsExecutionSafe()) return;

   // --- MODULE: KILL SWITCH ---
   if(!killSwitch.IsEnabled()) return;

   // --- MODULE: NEWS FILTER ---
   if(InpUseNewsFilter && !newsFilter.IsTradingAllowed()) return;

   // --- MODULE: KILLZONE FILTER ---
   if(InpUseKillzoneFilter && !killzoneOptimizer.IsTradingAllowed()) return;

   // --- MODULE: KELLY POSITION SIZER (DD LIMITS) ---
   if(InpUseKelly && !kellySizer.IsTradingAllowed()) return;

   // --- MODULE: MARKET REGIME ---
   g_currentRegime = regime.Detect(g_ATR, g_ATR_MA, g_EMA, g_EMA_Prev);
   if(g_currentRegime == REGIME_CHAOS) return;

   // PRE-ENTRY FILTERS
   if(!CheckSpread()) return;

   // 1. RSI Compression Filter
   if(g_RSI > 48 && g_RSI < 52) return;

   // 2. EMA Proximity Filter
   if(MathAbs(symbolInfo.Bid() - g_EMA) < g_ATR * 0.35) return;

   // Check Governor Trading Permission
   if(!IsTradingEnabled()) return;

   // Calculate confluence (new 12-point system)
   double buyScore = CalculateConfluenceScore(1);
   double sellScore = CalculateConfluenceScore(-1);

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
         double killzoneMultiplier = InpUseKillzoneFilter ? killzoneOptimizer.GetRiskMultiplier() : 1.0;
         double regimeMultiplier = (g_currentRegime == REGIME_TREND) ? 1.0 : 0.8;

         baseRisk = kellySizer.GetAdjustedRisk(quality, newsMultiplier, killzoneMultiplier, regimeMultiplier);
      }

      // Apply tier multiplier
      baseRisk *= GetTierSizeMultiplier(tier);

      // Apply adaptive risk (if enabled and learning active)
      if(InpEnableLearning && InpEnableAdaptiveRisk && adaptiveRisk.IsAdaptationEnabled())
      {
         ENUM_KILLZONE currentKZ = InpUseKillzoneFilter ? killzoneOptimizer.GetCurrentKillzone() : KILLZONE_NONE;
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
          // Use new thresholds: minimum 5 points for entry (was InpMinConfluenceEntry)
          double minEntry = CONFLUENCE_GOOD;  // 5.0

          if(buyScore >= minEntry && (InpDirection == 0 || InpDirection == 1))
          {
             g_currentConfluence = buyScore;
             g_entryDirection = 1;
             ExecuteTrade(ORDER_TYPE_BUY, approvedRisk, "Entry", quality);
          }
          else if(sellScore >= minEntry && (InpDirection == 0 || InpDirection == 2))
          {
             g_currentConfluence = sellScore;
             g_entryDirection = -1;
             ExecuteTrade(ORDER_TYPE_SELL, approvedRisk, "Entry", quality);
          }
      }
   }
   // ADD-ONS
   else if(g_positionCount > 0 && InpEnableAddOns && g_positionCount < InpMaxPositions)
   {
      CheckAddOnOpportunity();
   }
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

      // LOG TO TRADE JOURNAL
      if(InpEnableLearning && InpLogTradesToFile)
      {
         TradeContext ctx;
         ctx.ticket = ticket;
         ctx.entryTime = TimeCurrent();
         ctx.symbol = _Symbol;
         ctx.killzone = InpUseKillzoneFilter ? killzoneOptimizer.GetCurrentKillzone() : KILLZONE_NONE;
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         ctx.dayOfWeek = dt.day_of_week;
         ctx.regime = g_currentRegime;
         ctx.quality = quality;
         ctx.confluenceScore = g_currentConfluence;
         ctx.direction = (type == ORDER_TYPE_BUY) ? 1 : -1;
         ctx.entryPrice = price;
         ctx.sl = sl;
         ctx.tp = tp;
         ctx.lots = lots;
         ctx.riskPercent = riskPct;
         ctx.winRateAtEntry = killSwitch.GetWinRate();
         ctx.rollingRAtEntry = killSwitch.GetRollingR();

         tradeJournal.LogEntry(ctx);
      }

      // Log with TP information
      string tpInfo = (tp > 0) ?
         " TP:" + DoubleToString(tp, (int)symbolInfo.Digits()) +
         " (" + DoubleToString((MathAbs(tp - price) / slDist), 2) + "R)" :
         " No TP";
      Print("Opened ", EnumToString(type), " Ticket:", ticket,
            " Quality:", EnumToString(quality), tpInfo);
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

             // LOG EXIT TO TRADE JOURNAL
             if(InpEnableLearning && InpLogTradesToFile)
             {
                ExitContext exitCtx;
                exitCtx.exitTime = TimeCurrent();
                exitCtx.exitPrice = 0;  // Get from history if needed
                exitCtx.exitType = (profitMoney > 0) ? "TP" : "SL";
                exitCtx.profitR = profitR;
                exitCtx.profitMoney = profitMoney;
                exitCtx.durationMinutes = 0;  // Calculate if needed
                exitCtx.mfe = mfe;
                exitCtx.mae = mae;
                exitCtx.partialClosed = g_states[i].partialClosed;

                tradeJournal.LogExit(ticket, exitCtx);

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
                factors.killzoneActive = InpUseKillzoneFilter && killzoneOptimizer.IsTradingAllowed();
                factors.mtfAligned = (g_currentConfluence >= 8.0);

                patternRecognizer.UpdatePatternDatabase(factors, profitR);
             }

             // Commit to Learning Engine
             learning.OnTradeClosed(ticket);

             // Commit to KillSwitch
             double rOutcome = (profitMoney > 0) ? 1.0 : -1.0;
             if(profitMoney < 0 && MathAbs(profitMoney) > account.Balance()*0.02) rOutcome = -2.0;

             killSwitch.OnTradeClosed(rOutcome);
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

      // Get/Create State
      int sIdx = -1;
      for(int s=0; s<ArraySize(g_states); s++) {
         if(g_states[s].ticket == ticket) { sIdx = s; break; }
      }
      if(sIdx == -1) {
         int sz = ArraySize(g_states);
         ArrayResize(g_states, sz + 1);
         g_states[sz].ticket = ticket;
         g_states[sz].partialClosed = false;
         g_states[sz].initialRisk = MathAbs(open - sl);
         if(g_states[sz].initialRisk == 0) g_states[sz].initialRisk = _Point * 100;
         g_states[sz].quality = EQ_GOOD;
         sIdx = sz;
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
   // Handle Closed Trades for KillSwitch and Kelly logic
   HistorySelect(TimeCurrent() - 60, TimeCurrent());
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
       ulong ticket = HistoryDealGetTicket(i);
       if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
       {
           long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
           if(magic != InpMagicNumber) continue;  // Only our trades

           double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
           double rOutcome = (profit > 0) ? 1.0 : -1.0;

           // Estimate R multiple from profit (rough estimate)
           double equity = AccountInfoDouble(ACCOUNT_EQUITY);
           if(equity > 0)
           {
               double profitPct = (profit / equity) * 100.0;
               rOutcome = profitPct / InpRiskBase;  // Convert to R multiple
           }

           killSwitch.OnTradeClosed(rOutcome);
           learning.OnTradeClosed(ticket);

           // Update Kelly sizer with trade result
           if(InpUseKelly)
           {
              // Get quality from state if available
              ENTRY_QUALITY quality = EQ_GOOD;
              for(int s = 0; s < ArraySize(g_states); s++)
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
   // Update SMC modules
   if(InpUseSMC)
   {
      smcStructure.Update();
      smcOrderBlocks.Update();
      smcFVG.Update();
      smcLiquidity.Update();
   }

   // Update MTF analysis
   if(InpUseMTF) mtfAnalysis.Update();

   // Update filters
   if(InpUseNewsFilter) newsFilter.Update();
   if(InpUseKillzoneFilter) killzoneOptimizer.Update();
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
   factors.killzoneActive = InpUseKillzoneFilter && killzoneOptimizer.IsTradingAllowed();
   factors.mtfAligned = (score >= 8.0);

   factors.killzone = InpUseKillzoneFilter ? killzoneOptimizer.GetCurrentKillzone() : KILLZONE_NONE;
   factors.regime = g_currentRegime;
   factors.confluenceScore = score;
}

//+------------------------------------------------------------------+
//| NEW Confluence Score (0-12) - Enhanced with SMC                   |
//+------------------------------------------------------------------+
double CalculateConfluenceScore(int direction)
{
   double score = 0;
   double currentPrice = symbolInfo.Bid();

   // ============ ORIGINAL FACTORS (0-6) ============

   // 1. Trend (EMA 200 + slope) - 1.0 point
   double emaSlope = g_EMA - g_EMA_Prev;
   bool slopeStrong = MathAbs(emaSlope) >= (g_ATR * InpEMA_MinSlope);
   if(direction == 1 && currentPrice > g_EMA && emaSlope > 0 && slopeStrong) score += 1.0;
   if(direction == -1 && currentPrice < g_EMA && emaSlope < 0 && slopeStrong) score += 1.0;

   // 2. Structure - 1.0 point
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 1);
   int lowestBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback, 1);
   if(direction == 1 && lowestBar < highestBar) score += 1.0;
   if(direction == -1 && highestBar < lowestBar) score += 1.0;

   // 3. Fib Zone - 1.0 point
   if(highestBar >= 0 && lowestBar >= 0)
   {
      double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, highestBar);
      double swingLow = iLow(_Symbol, PERIOD_CURRENT, lowestBar);
      double range = swingHigh - swingLow;
      double tolerance = g_ATR * InpZoneTolerance;

      if(range >= g_ATR * 1.5)
      {
         if(direction == 1)
         {
            double f618 = swingHigh - (range * InpFibLevelLow);
            double f786 = swingHigh - (range * InpFibLevelHigh);
            if(currentPrice <= f618 + tolerance && currentPrice >= f786 - tolerance) score += 1.0;
         }
         else
         {
            double f618 = swingLow + (range * InpFibLevelLow);
            double f786 = swingLow + (range * InpFibLevelHigh);
            if(currentPrice >= f618 - tolerance && currentPrice <= f786 + tolerance) score += 1.0;
         }
      }
   }

   // 4. RSI level - 1.0 point
   if(direction == 1 && g_RSI <= InpRSI_Oversold) score += 1.0;
   if(direction == -1 && g_RSI >= InpRSI_Overbought) score += 1.0;

   // 5. RSI momentum - 0.5 point
   if(InpRSI_Momentum)
   {
      if(direction == 1 && g_RSI > g_RSI_Prev) score += 0.5;
      if(direction == -1 && g_RSI < g_RSI_Prev) score += 0.5;
   }

   // 6. Displacement - 1.0 point
   if(CheckDisplacement(direction)) score += 1.0;

   // ============ NEW SMC FACTORS (0-6 additional) ============

   if(InpUseSMC)
   {
      // 7. HTF Trend Alignment (MTF) - up to 2.0 points
      if(InpUseMTF)
         score += mtfAnalysis.GetConfluenceScore(direction);

      // 8. Structure Break (BOS aligned) - up to 1.0 point
      score += smcStructure.GetConfluenceScore(direction);

      // 9. Order Block Entry - up to 1.5 points
      score += smcOrderBlocks.GetConfluenceScore(direction);

      // 10. Fair Value Gap - up to 1.0 point
      score += smcFVG.GetConfluenceScore(direction);

      // 11. Liquidity Sweep - up to 1.5 points
      score += smcLiquidity.GetConfluenceScore(direction);
   }

   // 12. Killzone Timing Bonus - up to 0.5 points
   if(InpUseKillzoneFilter)
      score += killzoneOptimizer.GetConfluenceScore();

   return score;  // Max possible: ~12 points
}

//+------------------------------------------------------------------+
//| Get Total Profit in R                                             |
//+------------------------------------------------------------------+
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

   if(CopyBuffer(hRSI, 0, 1, 2, bufRSI) != 2) return false;
   if(CopyBuffer(hATR, 0, 1, 1, bufATR) != 1) return false;
   if(CopyBuffer(hEMA, 0, 1, 2, bufEMA) != 2) return false;

   g_RSI_Prev = bufRSI[0];
   g_RSI = bufRSI[1];
   g_ATR = bufATR[0];
   g_EMA_Prev = bufEMA[0];
   g_EMA = bufEMA[1];

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
   return ((int)symbolInfo.Spread() <= InpMaxSpreadPoints);
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
   double equity = account.Equity();
   if(equity <= 0) equity = account.Balance();

   double riskAmt = equity * (riskPct / 100.0);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(ts <= 0 || tv <= 0 || slDist <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lots = riskAmt / ((slDist / ts) * tv);

   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lots < minL) lots = minL;
   if(lots > maxL) lots = maxL;

   // Additional safety limit for position size
   if(lots > InpMaxLotsPerTrade)
   {
      Print("Lots capped from ", DoubleToString(lots, 3), " to ", DoubleToString(InpMaxLotsPerTrade, 2), " (InpMaxLotsPerTrade)");
      lots = InpMaxLotsPerTrade;
   }

   lots = MathFloor(lots / step + 0.000001) * step;
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
   double buyS = CalculateConfluenceScore(1);
   double sellS = CalculateConfluenceScore(-1);

   string govStatus = allocator.IsGovernorActive() ? "Connected " + DoubleToString(GetRiskMultiplier()*100,0) + "%" : "Standalone";
   string tradingStatus = IsTradingEnabled() ? "ACTIVE" : "BLOCKED";

   // Check for blocks
   if(InpUseNewsFilter && !newsFilter.IsTradingAllowed()) tradingStatus = "NEWS BLOCKED";
   if(InpUseKillzoneFilter && !killzoneOptimizer.IsTradingAllowed()) tradingStatus = "KILLZONE OFF";
   if(InpUseKelly && !kellySizer.IsTradingAllowed()) tradingStatus = "DD LIMIT";

   string txt = "===========================================\n";
   txt += "  SYMBOL ENGINE v2.0: " + _Symbol + "\n";
   txt += "===========================================\n";
   txt += "Governor: " + govStatus + "\n";
   txt += "Trading: " + tradingStatus + "\n";
   txt += "-------------------------------------------\n";
   txt += "Price: " + DoubleToString(price, (int)symbolInfo.Digits()) + "\n";
   txt += "RSI: " + DoubleToString(g_RSI, 1) + "\n";

   // Killzone info
   if(InpUseKillzoneFilter)
      txt += killzoneOptimizer.ToString() + "\n";

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
   txt += "BUY Score: " + DoubleToString(buyS, 1) + "/12\n";
   txt += "SELL Score: " + DoubleToString(sellS, 1) + "/12\n";
   txt += "Entry Min: 5.0/12 (Good) | 6.0 (Strong) | 8.0 (Elite)\n";
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

   // Learning System stats
   if(InpEnableLearning && InpLogTradesToFile)
   {
      txt += "-------------------------------------------\n";
      txt += "LEARNING SYSTEM\n";
      txt += "Trades Logged: " + IntegerToString(tradeJournal.GetTotalTrades()) + "\n";
      txt += "Open Trades: " + IntegerToString(tradeJournal.GetOpenTrades()) + "\n";

      int totalTrades = tradeJournal.GetTotalTrades();
      bool learningActive = (totalTrades >= InpMinTradesForLearning);
      txt += "Status: " + (learningActive ? "ACTIVE" : "Collecting Data") + "\n";

      if(!learningActive && totalTrades > 0)
         txt += "Progress: " + IntegerToString(totalTrades) + "/" + IntegerToString(InpMinTradesForLearning) + " trades\n";

      // Show performance analytics if learning is active
      if(learningActive)
      {
         performanceAnalyzer.RefreshData();
         ContextStats overall = performanceAnalyzer.GetOverallStats();

         if(overall.tradeCount > 0)
         {
            txt += "Win Rate: " + DoubleToString(overall.winRate * 100, 1) + "% | ";
            txt += "Avg R: " + DoubleToString(overall.avgR, 2) + "\n";
            txt += "Expectancy: " + DoubleToString(overall.expectancy, 3) + "R | ";
            txt += "PF: " + DoubleToString(overall.profitFactor, 2) + "\n";

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
                  ENUM_KILLZONE currentKZ = InpUseKillzoneFilter ? killzoneOptimizer.GetCurrentKillzone() : KILLZONE_NONE;
                  txt += adaptiveRisk.GetAdjustmentSummary(currentKZ, g_currentRegime) + "\n";
               }

               if(InpEnableAdaptiveExits)
               {
                  txt += adaptiveExit.GetAdjustmentSummary(g_currentRegime) + "\n";
               }

               if(InpEnableAdaptiveFilters)
               {
                  ENUM_KILLZONE currentKZ = InpUseKillzoneFilter ? killzoneOptimizer.GetCurrentKillzone() : KILLZONE_NONE;
                  txt += adaptiveFilter.GetFilterStatus(currentKZ, g_currentRegime) + "\n";
               }
            }
         }
      }
   }

   txt += "===========================================\n";

   Comment(txt);
}
//+------------------------------------------------------------------+
