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

#include "Include\Engines\SymbolEngineWrapper.mqh"

CSymbolEngineWrapper engine;
SymbolEngineParams params;

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

input group "======= SESSION GOVERNOR ======="
input bool              InpUseSessionGovernor = true;     // Enable Session Governor
input int               InpMaxTradesPerSession = 3;       // Max Trades Per Session
input double            InpMaxProfitPerSession_R = 5.0;   // Max Profit Per Session (R)
input double            InpMaxLossPerSession_R = 2.0;     // Max Loss Per Session (R)
input double            InpMinSessionConfidence = 0.4;    // Min Session Confidence (0-1)
input int               InpTradeCooldownMinutes = 15;     // Cooldown Between Trades (minutes)
input bool              InpEnableSessionBlacklist = true; // Enable Session Blacklist

input group "======= PORTFOLIO PROTECTION ======="
input bool              InpUseCorrelationFilter = true;   // Enable Correlation Protection
input double            InpDailyMaxLoss_R = 4.0;          // Daily Max Loss (R) - Circuit Breaker
input int               InpLossCooldownMinutes = 30;      // Cooldown After Loss (minutes)

input group "======= OVERTRADING PROTECTION ======="
input int               InpMaxConsecutiveLosses = 5;      // Max Consecutive Losses (Circuit Breaker)
input bool              InpUseReversalFilter = true;      // Enable Enhanced Reversal Filter
input int               InpReversalCooldownMinutes = 15;  // Same-Direction Cooldown (minutes)

//+------------------------------------------------------------------+
//| Init                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   // Map ALL input parameters to params struct

   // IDENTITY
   params.MagicNumber = InpMagicNumber;
   params.Direction = InpDirection;
   params.BrokerUTCOffset = InpBrokerUTCOffset;

   // KILLZONES
   params.UseKillzoneFilter = InpUseKillzoneFilter;
   params.UseSymbolDefaults = InpUseSymbolDefaults;
   params.AutoDST = InpAutoDST;
   params.EnableAsianKZ = false;  // Using symbol defaults
   params.EnableLondonOpenKZ = true;
   params.EnableNYKZ = true;
   params.EnableLondonCloseKZ = false;
   params.FocusPrimeOnly = false;

   // FIBONACCI
   params.SwingLookback = InpSwingLookback;
   params.FibLevelLow = InpFibLevelLow;
   params.FibLevelHigh = InpFibLevelHigh;
   params.ZoneTolerance = InpZoneTolerance;

   // DISPLACEMENT
   params.UseDisplacement = InpUseDisplacement;
   params.DisplacementATR = InpDisplacementATR;
   params.DisplacementLookback = InpDisplacementLookback;

   // RSI
   params.RSI_Period = InpRSI_Period;
   params.RSI_Oversold = InpRSI_Oversold;
   params.RSI_Overbought = InpRSI_Overbought;
   params.RSI_Momentum = InpRSI_Momentum;

   // TREND
   params.EMA_Period = InpEMA_Period;
   params.UseTrendFilter = InpUseTrendFilter;
   params.EMA_MinSlope = InpEMA_MinSlope;

   // CHOP FILTER
   params.UseChopFilter = InpUseChopFilter;
   params.ChopThreshold = InpChopThreshold;
   params.ATR_MA_Period = InpATR_MA_Period;

   // CONFLUENCE
   params.MinConfluenceEntry = InpMinConfluenceEntry;
   params.EnableAddOns = InpEnableAddOns;
   params.AddOn1_R = InpAddOn1_R;
   params.AddOn2_R = InpAddOn2_R;
   params.MaxPositions = InpMaxPositions;

   // RISK
   params.RiskBase = InpRiskBase;
   params.RiskAddOn1 = InpRiskAddOn1;
   params.RiskAddOn2 = InpRiskAddOn2;
   params.MaxRisk = InpMaxRisk;
   params.MaxLotsPerTrade = InpMaxLotsPerTrade;
   params.EnableMarginCheck = InpEnableMarginCheck;

   // TAKE PROFIT
   params.TPMode = InpTPMode;
   params.FixedTP_R = InpFixedTP_R;
   params.MinTP_R = InpMinTP_R;
   params.MaxTP_R = InpMaxTP_R;
   params.TPUseLearnedMFE = InpTPUseLearnedMFE;

   // EXIT
   params.TrailingMode = InpTrailingMode;
   params.PartialTP_R = InpPartialTP_R;
   params.PartialClosePercent = InpPartialClosePercent;
   params.BE_Threshold_R = InpBE_Threshold_R;
   params.TrailStart_R = InpTrailStart_R;
   params.TrailATR_Mult = InpTrailATR_Mult;

   // SPREAD
   params.MaxSpreadPoints = InpMaxSpreadPoints;

   // SMC
   params.UseSMC = InpUseSMC;
   params.SMC_SwingLookback = InpSMC_SwingLookback;
   params.SMC_MinImpulseATR = InpSMC_MinImpulseATR;
   params.SMC_MinFVG_ATR = InpSMC_MinFVG_ATR;

   // MTF
   params.UseMTF = InpUseMTF;
   params.HTF = InpHTF;
   params.MTF = InpMTF;
   params.MTF_EMAPeriod = InpMTF_EMAPeriod;

   // NEWS
   params.UseNewsFilter = InpUseNewsFilter;
   params.NewsMinutesBefore = InpNewsMinutesBefore;
   params.NewsMinutesAfter = InpNewsMinutesAfter;

   // KELLY
   params.UseKelly = InpUseKelly;
   params.KellyFraction = InpKellyFraction;
   params.DailyMaxDD = InpDailyMaxDD;
   params.WeeklyMaxDD = InpWeeklyMaxDD;

   // LEARNING
   params.EnableLearning = InpEnableLearning;
   params.LogTradesToFile = InpLogTradesToFile;
   params.LearningHistory = InpLearningHistory;
   params.MinTradesForLearning = InpMinTradesForLearning;

   // ADAPTIVE
   params.EnableAdaptiveRisk = InpEnableAdaptiveRisk;
   params.EnableAdaptiveExits = InpEnableAdaptiveExits;
   params.EnableAdaptiveFilters = InpEnableAdaptiveFilters;

   // SESSION GOVERNOR
   params.UseSessionGovernor = InpUseSessionGovernor;
   params.MaxTradesPerSession = InpMaxTradesPerSession;
   params.MaxProfitPerSession_R = InpMaxProfitPerSession_R;
   params.MaxLossPerSession_R = InpMaxLossPerSession_R;
   params.MinSessionConfidence = InpMinSessionConfidence;
   params.TradeCooldownMinutes = InpTradeCooldownMinutes;
   params.EnableSessionBlacklist = InpEnableSessionBlacklist;

   // PORTFOLIO PROTECTION
   params.UseCorrelationFilter = InpUseCorrelationFilter;
   params.DailyMaxLoss_R = InpDailyMaxLoss_R;
   params.LossCooldownMinutes = InpLossCooldownMinutes;
   params.MaxConsecutiveLosses = InpMaxConsecutiveLosses;
   params.UseReversalFilter = InpUseReversalFilter;
   params.ReversalCooldownMinutes = InpReversalCooldownMinutes;

   // EMA REVERSAL FILTER
   params.EMA50_Period = 50;
   params.EMA100_Period = 100;
   params.EMA_SeparationATR = 0.5;

   // EXECUTION
   params.FillingType = ORDER_FILLING_FOK;
   params.Deviation = 10;
   params.TradeComment = "SE_v2";

   // Initialize engine
   if(!engine.Init(_Symbol, params))
   {
      Print("❌ Symbol Engine initialization failed");
      return INIT_FAILED;
   }

   Print("✅ Symbol Engine v2.0 initialized - Thin Wrapper Mode");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   engine.Deinit();
}

//+------------------------------------------------------------------+
//| Main Tick Handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   engine.OnTick();
}

//+------------------------------------------------------------------+
//| Trade Event Handler (Optional)                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
   engine.OnTrade();
}

// ========== END OF SYMBOL ENGINE THIN WRAPPER ==========
