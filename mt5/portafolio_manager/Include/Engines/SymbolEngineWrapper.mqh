//+------------------------------------------------------------------+
//|                                         SymbolEngineWrapper.mqh   |
//|          Encapsulated Symbol Engine for Governor Integration      |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef SYMBOL_ENGINE_WRAPPER_MQH
#define SYMBOL_ENGINE_WRAPPER_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include "../PortfolioGlobals.mqh"
#include "../FailSafe.mqh"
#include "../MarketRegime.mqh"
#include "../KillSwitch.mqh"
#include "../Learning_MFE_MAE.mqh"
#include "../GovernorAllocator.mqh"
#include "../SessionGovernor.mqh"
#include "../Lib/DatabaseManager.mqh"


// Smart Money Concepts Modules
#include "../SMC_StructureBreak.mqh"
#include "../SMC_OrderBlocks.mqh"
#include "../SMC_FairValueGap.mqh"
#include "../SMC_LiquiditySweep.mqh"
// GOD LEVEL SMC Modules
#include "../SMC_MarketStructure.mqh"
#include "../SMC_Inducement.mqh"
#include "../SMC_PremiumDiscount.mqh"

// Multi-Timeframe and Filters
#include "../MTF_Confluence.mqh"
#include "../NewsFilter.mqh"
#include "../KillzoneOptimizer.mqh"
#include "../KellyPositionSizer.mqh"
// GOD LEVEL Fibonacci
#include "../Fibonacci_Advanced.mqh"

// Learning & Memory Modules
#include "../Memory/TradeJournal.mqh"
#include "../Memory/PatternMemory.mqh"
#include "../Learning/PerformanceAnalyzer.mqh"
#include "../Learning/PatternRecognizer.mqh"

// Adaptive Modules
#include "../Adaptive/AdaptiveRiskManager.mqh"
#include "../Adaptive/AdaptiveExitManager.mqh"
#include "../Adaptive/AdaptiveFilterManager.mqh"

// H1 ENHANCEMENT MODULES (Phase 2)
#include "../VolumeAnalysis.mqh"
#include "../CurrencyStrength.mqh"
#include "../CorrelationMatrix.mqh"
#include "../SMC_BreakerBlocks.mqh"
#include "../ICT_MacroWindows.mqh"
#include "../ICT_PowerOf3.mqh"

// ADVANCED MODULES (Phase 3)
#include "../DivergenceDetector.mqh"
#include "../WyckoffAnalysis.mqh"

//+------------------------------------------------------------------+
//| Engine Configuration Parameters                                   |
//+------------------------------------------------------------------+
struct SymbolEngineParams
{
   // IDENTITY
   int      MagicNumber;
   int      Direction;           // 0=Both, 1=Buy, 2=Sell
   int      BrokerUTCOffset;

   // KILLZONES
   bool     UseKillzoneFilter;
   bool     UseSymbolDefaults;
   bool     AutoDST;
   bool     EnableAsianKZ;
   bool     EnableLondonOpenKZ;
   bool     EnableNYKZ;
   bool     EnableLondonCloseKZ;
   bool     FocusPrimeOnly;

   // FIBONACCI
   int      SwingLookback;
   double   FibLevelLow;
   double   FibLevelHigh;
   double   ZoneTolerance;

   // DISPLACEMENT
   bool     UseDisplacement;
   double   DisplacementATR;
   int      DisplacementLookback;

   // RSI
   int      RSI_Period;
   int      RSI_Oversold;
   int      RSI_Overbought;
   bool     RSI_Momentum;
   
   // NOTIFICATIONS
   bool     EnablePushNotifications;

   // TREND
   int      EMA_Period;
   bool     UseTrendFilter;
   double   EMA_MinSlope;

   // CHOP FILTER
   bool     UseChopFilter;
   double   ChopThreshold;
   int      ATR_MA_Period;

   // CONFLUENCE
   int      MinConfluenceEntry;
   bool     EnableAddOns;
   double   AddOn1_R;
   double   AddOn2_R;
   int      MaxPositions;

   // RISK
   double   RiskBase;
   double   RiskAddOn1;
   double   RiskAddOn2;
   double   MaxRisk;
   double   MaxLotsPerTrade;
   bool     EnableMarginCheck;

   // TAKE PROFIT
   int      TPMode;              // 0=None, 1=Fixed, 2=Adaptive, 3=Hybrid
   double   FixedTP_R;
   double   MinTP_R;
   double   MaxTP_R;
   bool     TPUseLearnedMFE;

   // EXIT
   int      TrailingMode;        // 0=Off, 1=Runner, 2=Full
   double   PartialTP_R;
   double   PartialClosePercent;
   double   BE_Threshold_R;
   double   TrailStart_R;
   double   TrailATR_Mult;

   // SPREAD
   int      MaxSpreadPoints;

   // SMC
   bool     UseSMC;
   int      SMC_SwingLookback;
   double   SMC_MinImpulseATR;
   double   SMC_MinFVG_ATR;

   // MTF
   bool     UseMTF;
   ENUM_TIMEFRAMES HTF;
   ENUM_TIMEFRAMES MTF;
   int      MTF_EMAPeriod;

   // NEWS
   bool     UseNewsFilter;
   int      NewsMinutesBefore;
   int      NewsMinutesAfter;

   // KELLY
   bool     UseKelly;
   double   KellyFraction;
   double   DailyMaxDD;
   double   WeeklyMaxDD;

   // LEARNING
   bool     EnableLearning;
   bool     LogTradesToFile;
   int      LearningHistory;
   int      MinTradesForLearning;

   // ADAPTIVE
   bool     EnableAdaptiveRisk;
   bool     EnableAdaptiveExits;
   bool     EnableAdaptiveFilters;

   // SESSION GOVERNOR
   bool     UseSessionGovernor;
   int      MaxTradesPerSession;
   double   MaxProfitPerSession_R;
   double   MaxLossPerSession_R;
   double   MinSessionConfidence;
   int      TradeCooldownMinutes;
   bool     EnableSessionBlacklist;

   // PORTFOLIO PROTECTION
   bool     UseCorrelationFilter;
   double   DailyMaxLoss_R;
   int      LossCooldownMinutes;
   int      MaxConsecutiveLosses;       // Circuit breaker after N consecutive losses
   bool     UseReversalFilter;          // Enable EMA50/100 reversal filter
   int      ReversalCooldownMinutes;    // Same-direction cooldown (min time between same-direction trades)

   // EMA REVERSAL FILTER
   int      EMA50_Period;               // EMA50 for reversal detection
   int      EMA100_Period;              // EMA100 for reversal detection
   double   EMA_SeparationATR;          // Min EMA separation for valid trend (ATR multiple)

   // EXECUTION
   ENUM_ORDER_TYPE_FILLING FillingType;
   int      Deviation;
   string   TradeComment;

   // INDICATOR RECOVERY SETTINGS
   bool     AllowTradingWithoutATR;      // Allow trading if ATR fails permanently
   int      MaxConsecutiveFailures;      // Max failures before permanent disable
   int      MinRecoveryInterval;         // Min seconds between recoveries
   int      MaxRecoveryInterval;         // Max backoff time (seconds)
   int      InitialBackoffSeconds;       // Initial backoff (5 seconds default)
};

//+------------------------------------------------------------------+
//| SYMBOL ENGINE CLASS                                               |
//+------------------------------------------------------------------+
class CSymbolEngineWrapper
{
public:
   string         m_symbol;
   SymbolEngineParams m_params;
   CDatabaseManager *m_db; // Pointer to global DB manager

   
   // Trade Objects
   CTrade         m_trade;
   CPositionInfo  m_position;
   CAccountInfo   m_account;
   CSymbolInfo    m_symbolInfo;
   
   // Module Objects
   CFailSafe         m_failSafe;
   CMarketRegime     m_regime;
   CKillSwitch       m_killSwitch;
   CLearningEngine   m_learning;
   CGovernorAllocator m_allocator;
   CSessionGovernor  m_sessionGov;
   
   // SMC Modules (Original)
   CSMCStructureBreak  m_smcStructure;
   CSMCOrderBlocks     m_smcOrderBlocks;
   CSMCFairValueGap    m_smcFVG;
   CSMCLiquiditySweep  m_smcLiquidity;
   
   // GOD LEVEL SMC Modules
   CSMCMarketStructure m_smcMSS;           // Market Structure Shift detector
   CSMCInducement      m_smcInducement;    // Liquidity grab detector
   CSMCPremiumDiscount m_smcPriceZone;     // Premium/Discount zones
   
   // Filter Modules
   CMTFConfluence      m_mtfAnalysis;
   CNewsFilter         m_newsFilter;
   CKillzoneOptimizer  m_killzoneOptimizer;
   CKellyPositionSizer m_kellySizer;
   
   // GOD LEVEL Fibonacci
   CFibonacciAdvanced  m_fibAdvanced;      // Multi-swing clusters + OTE
   
   // Learning Modules
   CTradeJournal       m_tradeJournal;
   CPatternMemory      m_patternMemory;
   CPerformanceAnalyzer m_performanceAnalyzer;
   CPatternRecognizer  m_patternRecognizer;
   
   // Adaptive Modules
   CAdaptiveRiskManager   m_adaptiveRisk;
   CAdaptiveExitManager   m_adaptiveExit;
   CAdaptiveFilterManager m_adaptiveFilter;

   // H1 Enhancement Modules (Phase 2)
   CVolumeAnalysis        m_volumeAnalysis;       // Volume Profile, POC, VWAP
   CCurrencyStrength      m_currencyStrength;     // 8-currency strength meter
   CCorrelationMatrix     m_correlationMatrix;    // Portfolio correlation
   CBreakerBlocks         m_breakerBlocks;        // Failed OB detection
   CICTMacroWindows       m_macroWindows;         // ICT timing windows
   CICTPowerOf3           m_powerOf3;             // Accumulation/Distribution

   // Advanced Modules (Phase 3)
   CDivergenceDetector    m_divergence;           // RSI/MACD divergence
   CWyckoffAnalysis       m_wyckoff;              // Wyckoff phases
   
   // Indicator Handles & Buffers
   int m_hRSI, m_hATR, m_hEMA;
   int m_hEMA50, m_hEMA100;   // Reversal filter EMAs
   double m_g_RSI, m_g_RSI_Prev, m_g_ATR, m_g_EMA, m_g_EMA_Prev, m_g_ATR_MA;
   double m_g_EMA50, m_g_EMA100;   // Reversal filter EMA values
   double m_rsiBuffer[];

   // Per-Indicator Health Tracking
   struct IndicatorHealthState
   {
      datetime lastRecoveryAttempt;
      int consecutiveFailures;
      int totalRecoveryAttempts;
      bool isPermanentlyFailed;
      datetime permanentFailureTime;
      int currentBackoffSeconds;
   };

   IndicatorHealthState m_rsiHealth;
   IndicatorHealthState m_atrHealth;
   IndicatorHealthState m_emaHealth;
   IndicatorHealthState m_ema50Health;
   IndicatorHealthState m_ema100Health;

   // Configuration
   int m_maxConsecutiveFailures;
   int m_minRecoveryInterval;
   int m_maxRecoveryInterval;
   int m_initialBackoff;
   bool m_allowTradingWithoutATR;

   // Recovery State (Legacy - kept for compatibility)
   bool m_indicatorsHealthy;
   datetime m_lastRecoveryTime;
   int m_recoveryAttempts;
   int m_consecutiveDataFailures;  // Track temporary 4807/4806 errors before triggering recovery

   // State Variables
   long     m_helperChartId; // Helper Chart ID for data persistence
   datetime m_lastBarTime;
   int      m_entryDirection;
   double   m_currentConfluence;
   int      m_positionCount;
   bool     m_addOn1Triggered;
   bool     m_addOn2Triggered;
   datetime m_lastCloseTime;
   ulong    m_lastTickTime;
   int      m_bias;
   datetime m_lastLossTime;
   MARKET_REGIME m_currentRegime;
   double   m_dailyLossR;
   datetime m_lastResetDate;

   // Overtrading Protection State
   datetime m_lastBuyTime;     // Last BUY trade entry time
   datetime m_lastSellTime;    // Last SELL trade entry time
   int      m_consecutiveLosses;   // Consecutive loss counter for circuit breaker

   // Optimization Cache
   double   m_cachedBuyScore;
   double   m_cachedSellScore;
   datetime m_lastScoreCalcTime;

   // Performance Monitoring
   int      m_barCount;
   int      m_tradesExecuted;

   // INTRA-BAR PERSISTENCE (Controlled Aggression)
   datetime m_signalStartTime;       // Timestamp when confluence first met threshold
   int      m_lastSignalDirection;   // Direction of the persistent signal
   int      m_persistenceSeconds;    // Required duration (default 10s)

   // ADAPTIVE CONFLUENCE RANKING (Percentile System)
   bool     m_allowedToTradeThisCycle;  // Set by Portfolio Governor based on rank
   double   m_currentBestScore;         // Current best confluence score (buy or sell)

   // State Struct
   struct PositionState {
      ulong ticket;
      bool  partialClosed;
      double initialRisk;
      ENUM_ENTRY_TIER quality;
   };
   PositionState m_states[];

   //+------------------------------------------------------------------+
   //| GET DEFAULT PARAMETERS (Institutional Grade)                      |
   //+------------------------------------------------------------------+
   static SymbolEngineParams GetDefaults()
   {
      SymbolEngineParams p;
      ZeroMemory(p);
      
      // IDENTITY
      p.MagicNumber = 0;
      p.Direction = 0; // Both
      p.BrokerUTCOffset = 2;

      // KILLZONES
      p.UseKillzoneFilter = true;
      p.UseSymbolDefaults = true;
      p.AutoDST = true;
      p.FocusPrimeOnly = false;  // CHANGED: Trade all enabled killzones, not just prime overlap

      // FIBONACCI (M5 Optimized)
      p.SwingLookback = 12;      // Faster pivot detection for M5
      p.FibLevelLow = 0.618;
      p.FibLevelHigh = 0.786;
      p.ZoneTolerance = 0.15;

      // DISPLACEMENT (M5 Optimized)
      p.UseDisplacement = true;
      p.DisplacementATR = 0.8;   // Lowered from 1.2 for M5 volatility
      p.DisplacementLookback = 3;

      // RSI (M5 Fast)
      p.RSI_Period = 14;
      p.RSI_Oversold = 30;
      p.RSI_Overbought = 70;
      p.RSI_Momentum = true;

      // TREND (Faster EMAs for M5)
      p.EMA_Period = 100;        // Was 200 (too lagging for M5)
      p.UseTrendFilter = true;
      p.EMA_MinSlope = 0.1;

      // CHOP FILTER
      p.UseChopFilter = true;
      p.ChopThreshold = 60.0;
      p.ATR_MA_Period = 14;

      // CONFLUENCE (M5 High Frequency)
      p.MinConfluenceEntry = 7; // Raised default baseline for quality
      p.MaxPositions = 1;
      
      // RISK
      p.RiskBase = 1.0;
      p.MaxRisk = 2.0;
      p.MaxLotsPerTrade = 50.0;
      p.EnableMarginCheck = true;

      // TAKE PROFIT (M5 Scalping)
      p.TPMode = 3; // Hybrid
      p.FixedTP_R = 2.0;
      p.MinTP_R = 1.2;           // M5: Minimum 1.2R (Raised from 0.8)
      p.MaxTP_R = 4.0;           // Allow runners
      p.TPUseLearnedMFE = true;

      // EXIT (Active Management)
      p.TrailingMode = 2; // Adaptive
      p.PartialTP_R = 1.5;
      p.PartialClosePercent = 50.0;
      p.BE_Threshold_R = 1.0;    // Break-even sooner on M5
      p.TrailStart_R = 1.5;
      p.TrailATR_Mult = 1.5;

      // SPREAD
      p.MaxSpreadPoints = 50;

      // SMC (M5 Tuned)
      p.UseSMC = true;
      p.SMC_SwingLookback = 10;       // Faster structure mapping
      p.SMC_MinImpulseATR = 1.2;      // Detected smaller M5 impulses
      p.SMC_MinFVG_ATR = 0.25;        // Capture micro-gaps

      // MTF (M5 Structure)
      p.UseMTF = true;
      // M5 Hierarchy: H1 (Macro) -> M15 (Structure) -> M5 (Entry)
      p.HTF = PERIOD_H1;         
      p.MTF = PERIOD_M15;        
      p.MTF_EMAPeriod = 100;
      
      // NEWS (Tighter window for scalping)
      p.UseNewsFilter = true;
      p.NewsMinutesBefore = 30;  // Reduced from 60
      p.NewsMinutesAfter = 30;

      // KELLY
      p.UseKelly = true;
      p.KellyFraction = 0.5;
      p.DailyMaxDD = 3.0;
      p.WeeklyMaxDD = 6.0;

      // LEARNING
      p.EnableLearning = true;
      p.LogTradesToFile = true;
      p.LearningHistory = 30;
      p.MinTradesForLearning = 5;

      // ADAPTIVE
      p.EnableAdaptiveRisk = true;
      p.EnableAdaptiveExits = true;
      p.EnableAdaptiveFilters = true;

      // SESSION GOVERNOR
      p.UseSessionGovernor = true;
      p.MaxTradesPerSession = 2;
      p.MaxProfitPerSession_R = 5.0;
      p.MaxLossPerSession_R = 2.0;

      // PORTFOLIO PROTECTION
      p.UseCorrelationFilter = true;
      p.DailyMaxLoss_R = 4.0;
      p.LossCooldownMinutes = 30;
      p.MaxConsecutiveLosses = 5;
      p.UseReversalFilter = true;
      p.ReversalCooldownMinutes = 15;

      // EMA REVERSAL FILTER
      p.EMA50_Period = 50;
      p.EMA100_Period = 100;
      p.EMA_SeparationATR = 0.5;

      // EXECUTION
      p.FillingType = ORDER_FILLING_FOK;
      p.Deviation = 10;
      p.TradeComment = "Engine_Pro";

      // INDICATOR RECOVERY SETTINGS
      p.AllowTradingWithoutATR = false;
      p.MaxConsecutiveFailures = 20;
      p.MinRecoveryInterval = 30;
      p.MaxRecoveryInterval = 300;
      p.InitialBackoffSeconds = 5;

      return p;
   }

public:
   CSymbolEngineWrapper() : m_db(NULL)
   {

      m_hRSI = INVALID_HANDLE;
      m_hATR = INVALID_HANDLE;
      m_hEMA = INVALID_HANDLE;
      m_hEMA50 = INVALID_HANDLE;
      m_hEMA100 = INVALID_HANDLE;
      m_lastBarTime = 0;
      m_lastBuyTime = 0;
      m_lastSellTime = 0;
      m_consecutiveLosses = 0;
      m_currentRegime = REGIME_UNKNOWN;
      m_barCount = 0;
      m_tradesExecuted = 0;
      m_allowedToTradeThisCycle = true;   // Default: allowed
      m_currentBestScore = 0.0;
      
      m_indicatorsHealthy = false;
      m_lastRecoveryTime = 0;
      m_recoveryAttempts = 0;
      m_consecutiveDataFailures = 0;  // Initialize error counter
      m_helperChartId = 0;

      // Intra-Bar Init
      m_signalStartTime = 0;
      m_lastSignalDirection = 0;
      m_persistenceSeconds = 10; // 10s stability filter

      // Initialize indicator health tracking
      InitializeIndicatorHealth();
   }

   ~CSymbolEngineWrapper()
   {
      Deinit();
   }

   //+------------------------------------------------------------------+
   //| Initialize Indicator Health Tracking System                      |
   //+------------------------------------------------------------------+
   void InitializeIndicatorHealth()
   {
      // Initialize RSI health state
      m_rsiHealth.lastRecoveryAttempt = 0;
      m_rsiHealth.consecutiveFailures = 0;
      m_rsiHealth.totalRecoveryAttempts = 0;
      m_rsiHealth.isPermanentlyFailed = false;
      m_rsiHealth.permanentFailureTime = 0;
      m_rsiHealth.currentBackoffSeconds = 5;

      // Initialize ATR health state
      m_atrHealth.lastRecoveryAttempt = 0;
      m_atrHealth.consecutiveFailures = 0;
      m_atrHealth.totalRecoveryAttempts = 0;
      m_atrHealth.isPermanentlyFailed = false;
      m_atrHealth.permanentFailureTime = 0;
      m_atrHealth.currentBackoffSeconds = 5;

      // Initialize EMA health state
      m_emaHealth.lastRecoveryAttempt = 0;
      m_emaHealth.consecutiveFailures = 0;
      m_emaHealth.totalRecoveryAttempts = 0;
      m_emaHealth.isPermanentlyFailed = false;
      m_emaHealth.permanentFailureTime = 0;
      m_emaHealth.currentBackoffSeconds = 5;

      // Initialize EMA50 health state
      m_ema50Health.lastRecoveryAttempt = 0;
      m_ema50Health.consecutiveFailures = 0;
      m_ema50Health.totalRecoveryAttempts = 0;
      m_ema50Health.isPermanentlyFailed = false;
      m_ema50Health.permanentFailureTime = 0;
      m_ema50Health.currentBackoffSeconds = 5;

      // Initialize EMA100 health state
      m_ema100Health.lastRecoveryAttempt = 0;
      m_ema100Health.consecutiveFailures = 0;
      m_ema100Health.totalRecoveryAttempts = 0;
      m_ema100Health.isPermanentlyFailed = false;
      m_ema100Health.permanentFailureTime = 0;
      m_ema100Health.currentBackoffSeconds = 5;

      // Configuration defaults (will be overridden by params in Init)
      m_maxConsecutiveFailures = 20;
      m_minRecoveryInterval = 30;
      m_maxRecoveryInterval = 300;
      m_initialBackoff = 5;
      m_allowTradingWithoutATR = false;
   }
   
   
   //+------------------------------------------------------------------+
   //| Initialization Modificada                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, SymbolEngineParams &params, CDatabaseManager *db = NULL)
   {
      m_symbol = symbol;
      m_params = params;
      m_db = db;

      // Load indicator recovery configuration
      m_allowTradingWithoutATR = m_params.AllowTradingWithoutATR;
      m_maxConsecutiveFailures = m_params.MaxConsecutiveFailures;
      m_minRecoveryInterval = m_params.MinRecoveryInterval;
      m_maxRecoveryInterval = m_params.MaxRecoveryInterval;
      m_initialBackoff = m_params.InitialBackoffSeconds;

      // FORZAR selección del símbolo primero
      if(!SymbolSelect(m_symbol, true))
      {
         Print("❌ ERROR: Cannot select symbol ", m_symbol);
         return false;
      }
      
      if(!m_symbolInfo.Name(m_symbol)) return false;
      
      // Esperar activamente a que el símbolo tenga datos
      Print("⏳ Waiting for symbol data: ", m_symbol);
      int waitAttempts = 0;
      while(waitAttempts < 20) // 20 intentos = 2 segundos
      {
         m_symbolInfo.RefreshRates();
         if(m_symbolInfo.Bid() > 0 && m_symbolInfo.Ask() > 0)
            break;
         Sleep(100);
         waitAttempts++;
      }
      
      if(m_symbolInfo.Bid() <= 0 || m_symbolInfo.Ask() <= 0)
      {
         Print("❌ ERROR: No price data for ", m_symbol);
         return false;
      }
      
      m_trade.SetExpertMagicNumber(m_params.MagicNumber);
      m_trade.SetDeviationInPoints(m_params.Deviation);
      m_trade.SetTypeFilling(m_params.FillingType);
      
      // NUEVO: Crear indicadores con sistema robusto
      if(!CreateIndicatorsWithRetry())
      {
         Print("❌ ERROR: Failed to create indicators for ", m_symbol);
         return false;
      }
      
      // CRÍTICO: Verificar que los indicadores son válidos inmediatamente
      if(!VerifyIndicators())
      {
         Print("⚠️ WARNING: Indicators created but not immediately healthy");
         // No fallamos aquí, el sistema de recuperación lo manejará
      }
      
      m_failSafe.Init(m_params.MaxSpreadPoints);
      ArrayResize(m_states, 0);
      
      // Initialize Learning
      if(m_params.EnableLearning)
      {
         m_learning.Init(m_symbol, true);
         // Pass DB to TradeJournal (accessed via learning or directly if refactored, 
         // assuming m_tradeJournal is member of this class - Yes, line 251)
         m_tradeJournal.Init(m_symbol, m_params.LearningHistory, m_db); 
      }

      
      // Initialize SMC
      if(m_params.UseSMC)
      {
         m_smcStructure.Init(m_symbol, PERIOD_CURRENT, m_params.SMC_SwingLookback);
         m_smcOrderBlocks.Init(m_symbol, PERIOD_CURRENT, 50, 5, m_params.SMC_MinImpulseATR);
         m_smcFVG.Init(m_symbol, PERIOD_CURRENT, 50, 10, m_params.SMC_MinFVG_ATR);
         m_smcLiquidity.Init(m_symbol, PERIOD_CURRENT, m_params.SMC_SwingLookback);
         
         // GOD LEVEL SMC Modules
         m_smcMSS.Init(m_symbol, PERIOD_CURRENT, m_params.SMC_SwingLookback);
         m_smcInducement.Init(m_symbol, PERIOD_CURRENT, 10);
         m_smcPriceZone.Init(m_symbol, PERIOD_CURRENT, 50);
      }
      
      // Initialize GOD LEVEL Fibonacci
      m_fibAdvanced.Init(m_symbol, PERIOD_CURRENT, 100, 5);

      // Initialize H1 Enhancement Modules (Phase 2)
      m_volumeAnalysis.Init(m_symbol, PERIOD_CURRENT);
      m_currencyStrength.Init(PERIOD_CURRENT);
      m_correlationMatrix.Init(PERIOD_CURRENT);
      m_breakerBlocks.Init(m_symbol, PERIOD_CURRENT, 50);
      m_macroWindows.Init(m_symbol, m_params.BrokerUTCOffset);
      m_powerOf3.Init(m_symbol, PERIOD_CURRENT, 50);

      // Initialize Advanced Modules (Phase 3)
      m_divergence.Init(m_symbol, PERIOD_CURRENT, m_params.RSI_Period);
      m_wyckoff.Init(m_symbol, PERIOD_CURRENT, 50);

       // Initialize MTF
      if(m_params.UseMTF)
      {
         m_mtfAnalysis.Init(m_symbol, m_params.HTF, m_params.MTF, PERIOD_CURRENT, m_params.MTF_EMAPeriod);
      }

      // Initialize News
      if(m_params.UseNewsFilter)
      {
         m_newsFilter.Init(m_symbol, m_params.NewsMinutesBefore, m_params.NewsMinutesAfter, true);
      }
      
      // Initialize Killzones
      if(m_params.UseKillzoneFilter)
      {
          if(m_params.UseSymbolDefaults)
             m_killzoneOptimizer.Init(m_symbol, m_params.BrokerUTCOffset, true, m_params.AutoDST, m_params.FocusPrimeOnly);
          else
             m_killzoneOptimizer.Init(m_symbol, m_params.BrokerUTCOffset, m_params.EnableAsianKZ, m_params.EnableLondonOpenKZ, 
                                      m_params.EnableNYKZ, m_params.EnableLondonCloseKZ, m_params.FocusPrimeOnly, m_params.AutoDST);
      }
      
      // Link Adaptive Modules
      if(m_params.EnableLearning)
      {
          if(m_params.EnableAdaptiveExits)
          {
             ExitParameters exitParams;
             exitParams.trailStartR = m_params.TrailStart_R;
             exitParams.trailDistanceATR = m_params.TrailATR_Mult;
             exitParams.beThresholdR = m_params.BE_Threshold_R;
             exitParams.partialTPR = m_params.PartialTP_R;
             exitParams.partialPercent = m_params.PartialClosePercent;
             
             m_adaptiveExit.Init(m_symbol, &m_learning, exitParams, m_params.EnableAdaptiveExits);
          }
      }
      
      // CRÍTICO: Marcar indicadores como saludables después de init exitoso
      m_indicatorsHealthy = true;
      m_recoveryAttempts = 0;
      
      Print("✅ SUCCESS: Engine initialized for ", m_symbol);
      return true;
   }
   
   void Deinit()
   {
      if(m_helperChartId > 0)
      {
         ChartClose(m_helperChartId);
         m_helperChartId = 0;
      }

      if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
      if(m_hEMA != INVALID_HANDLE) IndicatorRelease(m_hEMA);
      if(m_hEMA50 != INVALID_HANDLE) IndicatorRelease(m_hEMA50);
      if(m_hEMA100 != INVALID_HANDLE) IndicatorRelease(m_hEMA100);

      // Module cleanup handled by destructors
   }

   //+------------------------------------------------------------------+
   //| Getters for Dashboard Integration                                |
   //+------------------------------------------------------------------+
   double GetBuyConfluence()  { return m_cachedBuyScore; }
   double GetSellConfluence() { return m_cachedSellScore; }

   string GetStatus()
   {
      // Check killzone
      if(m_params.UseKillzoneFilter && !m_killzoneOptimizer.IsTradingAllowed())
         return "OFF-HOURS";

      // Check if in cooldown
      datetime now = TimeCurrent();
      int buyCooldown = (int)((now - m_lastBuyTime) / 60);
      int sellCooldown = (int)((now - m_lastSellTime) / 60);

      if(buyCooldown < m_params.ReversalCooldownMinutes && sellCooldown < m_params.ReversalCooldownMinutes)
         return "COOLING";

      // Check if has active position
      if(m_positionCount > 0)
         return "IN TRADE";

      // Check confluence quality
      double maxScore = MathMax(m_cachedBuyScore, m_cachedSellScore);
      if(maxScore >= 9.0)
         return "ELITE SETUP";
      else if(maxScore >= 7.0)
         return "STRONG";
      else if(maxScore >= 6.0)
         return "MONITORING";
      else
         return "SCANNING";
   }

   //+------------------------------------------------------------------+
   //| Getters para mostrar estado de salud                             |
   //+------------------------------------------------------------------+
   string GetHealthStatus()
   {
      // Check for permanent failures first
      if(m_rsiHealth.isPermanentlyFailed) return "RSI_PERMANENT_FAIL";
      if(m_emaHealth.isPermanentlyFailed) return "EMA_PERMANENT_FAIL";
      if(m_atrHealth.isPermanentlyFailed && !m_allowTradingWithoutATR) return "ATR_PERMANENT_FAIL";

      if(!m_indicatorsHealthy) return "UNHEALTHY";

      // Check for high failure counts (warning state)
      if(m_rsiHealth.consecutiveFailures >= m_maxConsecutiveFailures / 2)
         return "RSI_WARNING";
      if(m_atrHealth.consecutiveFailures >= m_maxConsecutiveFailures / 2)
         return "ATR_WARNING";
      if(m_emaHealth.consecutiveFailures >= m_maxConsecutiveFailures / 2)
         return "EMA_WARNING";

      // Verificar handles
      string status = "HEALTHY";
      if(m_hRSI == INVALID_HANDLE) status = "RSI_BAD";
      if(m_hATR == INVALID_HANDLE && !m_atrHealth.isPermanentlyFailed) status = "ATR_BAD";
      if(m_hEMA == INVALID_HANDLE) status = "EMA_BAD";

      // Verificar datos recientes
      static datetime lastHealthCheck = 0;
      if(TimeCurrent() - lastHealthCheck > 60)
      {
         if(!AreIndicatorsHealthy())
         {
            status = "DATA_STALE";
         }
         lastHealthCheck = TimeCurrent();
      }

      return status;
   }

   void DebugIndicatorStatus()
   {
       Print("╔══════════════════════════════════════════════════════════════");
       Print("║ INDICATOR HEALTH DIAGNOSTIC: ", m_symbol);
       Print("╠══════════════════════════════════════════════════════════════");
       Print("║ Global Status:");
       Print("║   Indicators Healthy: ", (m_indicatorsHealthy ? "YES" : "NO"));
       Print("║   Legacy Recovery Attempts: ", m_recoveryAttempts);
       Print("║   Last Global Recovery: ", TimeToString(m_lastRecoveryTime));
       Print("║   Consecutive Data Failures: ", m_consecutiveDataFailures);
       Print("╠══════════════════════════════════════════════════════════════");

       PrintIndicatorHealthStatus("RSI", m_hRSI, m_rsiHealth);
       PrintIndicatorHealthStatus("ATR", m_hATR, m_atrHealth);
       PrintIndicatorHealthStatus("EMA", m_hEMA, m_emaHealth);

       if(m_params.UseReversalFilter)
       {
          PrintIndicatorHealthStatus("EMA50", m_hEMA50, m_ema50Health);
          PrintIndicatorHealthStatus("EMA100", m_hEMA100, m_ema100Health);
       }

       Print("╠══════════════════════════════════════════════════════════════");
       Print("║ Configuration:");
       Print("║   Allow Trading Without ATR: ", (m_allowTradingWithoutATR ? "YES" : "NO"));
       Print("║   Max Consecutive Failures: ", m_maxConsecutiveFailures);
       Print("║   Min Recovery Interval: ", m_minRecoveryInterval, "s");
       Print("║   Max Recovery Backoff: ", m_maxRecoveryInterval, "s");
       Print("╚══════════════════════════════════════════════════════════════");
   }

   void PrintIndicatorHealthStatus(string name, int handle, IndicatorHealthState &health)
   {
       int barsCalc = BarsCalculated(handle);

       Print("║ ");
       Print("║ ", name, ":");
       Print("║   Handle: ", (handle == INVALID_HANDLE ? "INVALID" : IntegerToString(handle)));
       Print("║   Bars Calculated: ", barsCalc);
       Print("║   Consecutive Failures: ", health.consecutiveFailures);
       Print("║   Total Recovery Attempts: ", health.totalRecoveryAttempts);
       Print("║   Current Backoff: ", health.currentBackoffSeconds, " seconds");
       Print("║   Permanently Failed: ", (health.isPermanentlyFailed ? "YES ⚠️" : "NO"));

       if(health.isPermanentlyFailed)
       {
          Print("║   Failure Time: ", TimeToString(health.permanentFailureTime));
       }

       // Test data read
       if(handle != INVALID_HANDLE && !health.isPermanentlyFailed)
       {
          ResetLastError();
          double test[1];
          if(CopyBuffer(handle, 0, 0, 1, test) > 0)
             Print("║   Data Test: ✅ OK (Value: ", DoubleToString(test[0], 4), ")");
          else
             Print("║   Data Test: ❌ FAILED (Error: ", GetLastError(), ")");
       }
   }

   int GetPositionCount() { return m_positionCount; }

   //+------------------------------------------------------------------+
   //| ADAPTIVE CONFLUENCE RANKING - Percentile System                  |
   //+------------------------------------------------------------------+
   // Get best confluence score (used by Governor for ranking)
   //+------------------------------------------------------------------+
   //| Get Confluence Breakdown for Dashboard                           |
   //+------------------------------------------------------------------+
   void GetConfluenceBreakdown(int direction, double &coreScore, double &smcScore, 
                                double &fibScore, double &mtfScore, double &timingScore)
   {
      coreScore = 0;
      smcScore = 0;
      fibScore = 0;
      mtfScore = 0;
      timingScore = 0;
      
      double currentPrice = m_symbolInfo.Bid();
      
      // CORE TECHNICAL (0-7)
      double emaSlope = m_g_EMA - m_g_EMA_Prev;
      bool slopeStrong = MathAbs(emaSlope) >= (m_g_ATR * m_params.EMA_MinSlope);
      
      if(direction == 1 && currentPrice > m_g_EMA && emaSlope > 0 && slopeStrong) coreScore += 1.0;
      if(direction == -1 && currentPrice < m_g_EMA && emaSlope < 0 && slopeStrong) coreScore += 1.0;
      
      int highestBar = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, m_params.SwingLookback, 1);
      int lowestBar = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, m_params.SwingLookback, 1);
      if(direction == 1 && lowestBar < highestBar) coreScore += 1.0;
      if(direction == -1 && highestBar < lowestBar) coreScore += 1.0;
      
      if(direction == 1 && m_g_RSI <= m_params.RSI_Oversold) coreScore += 1.0;
      if(direction == -1 && m_g_RSI >= m_params.RSI_Overbought) coreScore += 1.0;
      
      if(m_params.RSI_Momentum)
      {
         if(direction == 1 && m_g_RSI > m_g_RSI_Prev) coreScore += 0.5;
         if(direction == -1 && m_g_RSI < m_g_RSI_Prev) coreScore += 0.5;
      }
      
      if(CheckDisplacement(direction)) coreScore += 1.0;
      
      double atrRatio = m_g_ATR / m_g_ATR_MA;
      if(atrRatio >= 0.8 && atrRatio <= 1.3) coreScore += 1.5;
      else if(atrRatio >= 0.6 && atrRatio <= 1.5) coreScore += 0.75;
      
      if(m_params.UseChopFilter && atrRatio > 0.5) coreScore += 1.0;
      
      // SMC (0-12)
      if(m_params.UseSMC)
      {
         smcScore += m_smcOrderBlocks.GetConfluenceScore(direction);
         smcScore += m_smcFVG.GetConfluenceScore(direction);
         smcScore += m_smcLiquidity.GetConfluenceScore(direction);
         smcScore += m_smcMSS.GetConfluenceScore(direction);
         smcScore += m_smcInducement.GetConfluenceScore(direction);
         smcScore += m_smcPriceZone.GetConfluenceScore(direction);
         smcScore += m_smcStructure.GetConfluenceScore(direction);
      }
      
      // FIBONACCI (0-3)
      fibScore = m_fibAdvanced.GetConfluenceScore(direction);
      
      // MULTI-TIMEFRAME (0-3)
      if(m_params.UseMTF)
         mtfScore = m_mtfAnalysis.GetConfluenceScore(direction);
      
      // TIMING (0-5)
      if(m_params.UseKillzoneFilter)
         timingScore += m_killzoneOptimizer.GetConfluenceScore();
      
      double regimeBonus = 0;
      if(m_currentRegime == REGIME_TREND)
      {
         if((direction == 1 && emaSlope > 0) || (direction == -1 && emaSlope < 0))
            regimeBonus = 2.0;
      }
      else if(m_currentRegime == REGIME_RANGE)
      {
         if((direction == 1 && m_g_RSI <= m_params.RSI_Oversold) ||
            (direction == -1 && m_g_RSI >= m_params.RSI_Overbought))
            regimeBonus = 1.5;
      }
      timingScore += regimeBonus;
      
      if(m_params.UseNewsFilter && m_newsFilter.IsTradingAllowed())
         timingScore += 1.0;
   }
   
   //+------------------------------------------------------------------+
   //| Get SMC Status for Dashboard                                      |
   //+------------------------------------------------------------------+
   void GetSMCIntel(string &mssStatus, string &obStatus, string &fvgStatus,
                     string &inducementStatus, string &zoneStatus)
   {
      // MSS/ChoCh Status
      MSSEvent lastMSS;
      if(m_smcMSS.GetLastMSS(lastMSS))
      {
         if(lastMSS.confirmed)
         {
            if(lastMSS.type == MSS_BULLISH) mssStatus = "CONFIRMED BULLISH";
            else if(lastMSS.type == MSS_BEARISH) mssStatus = "CONFIRMED BEARISH";
            else if(lastMSS.type == MSS_CHOCH_BULLISH) mssStatus = "ChoCh BULLISH";
            else if(lastMSS.type == MSS_CHOCH_BEARISH) mssStatus = "ChoCh BEARISH";
         }
         else
            mssStatus = "DETECTED (Unconfirmed)";
      }
      else
         mssStatus = "None";
      
      // Order Block Status
      double obTop, obBottom;
      if(m_smcOrderBlocks.IsInOrderBlock(1, obTop, obBottom))
         obStatus = "BULLISH OB ACTIVE";
      else if(m_smcOrderBlocks.IsInOrderBlock(-1, obTop, obBottom))
         obStatus = "BEARISH OB ACTIVE";
      else
         obStatus = "None";
      
      // FVG Status
      double fvgTop, fvgBottom;
      if(m_smcFVG.IsInFVG(1, fvgTop, fvgBottom))
         fvgStatus = "BULLISH FVG OPEN";
      else if(m_smcFVG.IsInFVG(-1, fvgTop, fvgBottom))
         fvgStatus = "BEARISH FVG OPEN";
      else
         fvgStatus = "None";
      
      // Inducement Status (simplified)
      if(m_smcInducement.GetConfluenceScore(1) > 0.5)
         inducementStatus = "BULLISH HUNT";
      else if(m_smcInducement.GetConfluenceScore(-1) > 0.5)
         inducementStatus = "BEARISH GRAB";
      else
         inducementStatus = "None";
      
      // Premium/Discount Zone
      double zoneScore1 = m_smcPriceZone.GetConfluenceScore(1);
      double zoneScore2 = m_smcPriceZone.GetConfluenceScore(-1);
      
      if(zoneScore1 > 0.5)
         zoneStatus = "DISCOUNT (Buy Zone)";
      else if(zoneScore2 > 0.5)
         zoneStatus = "PREMIUM (Sell Zone)";
      else
         zoneStatus = "EQUILIBRIUM";
   }

   double GetBestConfluenceScore()
   {
      return MathMax(m_cachedBuyScore, m_cachedSellScore);
   }

   // Set trading permission (called by Governor after ranking)
   void SetTradingPermission(bool allowed)
   {
      m_allowedToTradeThisCycle = allowed;
   }

   // Check if allowed to trade this cycle
   bool IsAllowedToTrade()
   {
      return m_allowedToTradeThisCycle;
   }

   //+------------------------------------------------------------------+
   //| Pre-calculate scores for ranking (called before OnTick)          |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| Pre-calculate scores for ranking - MODIFICADO                    |
   //+------------------------------------------------------------------+
   void UpdateScoresForRanking()
   {
      // Continuous intra-bar scoring enabled
      
      // CRÍTICO: Verificar salud de indicadores ANTES de todo
      if(!m_indicatorsHealthy)
      {
         // Intentar recuperación silenciosa para ranking
         if(!RecoverIndicators())
         {
            Print("❌ Cannot calculate scores - indicators unhealthy");
            m_cachedBuyScore = 0;
            m_cachedSellScore = 0;
            m_currentBestScore = 0;
            return;
         }
      }
      
      // Debe tener indicadores válidos
      if(!UpdateIndicatorsEnhanced()) 
      {
         Print("⚠️ Failed to update indicators for ranking");
         return;
      }

      // Update modules
      UpdateModules();

      // Calculate and cache scores (without permission check)
      double buyScore = CalculateConfluenceScore(1);
      double sellScore = CalculateConfluenceScore(-1);

      m_cachedBuyScore = buyScore;
      m_cachedSellScore = sellScore;
      m_currentBestScore = MathMax(buyScore, sellScore);
      m_lastScoreCalcTime = TimeCurrent();
   }

    //+------------------------------------------------------------------+
   //| Main Processing Loop - MODIFICADO                                |
   //+------------------------------------------------------------------+
   void OnTick()
   {
      m_symbolInfo.RefreshRates();
      
      // Actualizar contador de posiciones
      m_positionCount = CountPositions();
      if(m_positionCount == 0) ResetTradeState();

      // Manage positions every tick for stop/TP updates
      ManagePositions();

      // RESTORED: Bar-based processing to reduce indicator checks from ~300/bar to 1/bar
      if(!IsNewBar())
      {
         return;  // Skip indicator updates until new bar
      }

      Print("🔔 NEW BAR | ", m_symbol, " | Time: ", TimeToString(TimeCurrent(), TIME_SECONDS));
      
      // PRIMERO: Verificar salud de indicadores antes de cualquier cosa
      if(!m_indicatorsHealthy)
      {
         Print("⚠️ Indicators unhealthy at start of OnTick, attempting recovery...");
         if(!RecoverIndicators())
         {
            Print("❌ Unable to recover indicators. Skipping tick.");
            return;
         }
      }
      
      // Verificar nuevo día y reiniciar contadores diarios
      CheckNewDay();
      
      // USAR ACTUALIZACIÓN MEJORADA
      if(!UpdateIndicatorsEnhanced())
      {
         Print("❌ BLOCKED | ", m_symbol, " | UpdateIndicatorsEnhanced() failed");
         m_indicatorsHealthy = false;
         return;
      }
      Print("✅ PASSED | ", m_symbol, " | Indicators updated");

      // Update Modules
      UpdateModules();

      // CRITICAL: Update Killzone Optimizer to determine current active killzone
      if(m_params.UseKillzoneFilter)
         m_killzoneOptimizer.Update();

      // Safety Checks
      if(!m_failSafe.IsExecutionSafe())
      {
         Print("⛔ BLOCKED: FailSafe.IsExecutionSafe() = false");
         return;
      }
      if(m_params.UseNewsFilter && !m_newsFilter.IsTradingAllowed())
      {
         Print("⛔ BLOCKED: News filter active");
         return;
      }
      if(m_params.UseKillzoneFilter && !m_killzoneOptimizer.IsTradingAllowed())
      {
         Print("⛔ BLOCKED: Outside killzone");
         return;
      }

      // Regime
      m_currentRegime = m_regime.Detect(m_g_ATR, m_g_ATR_MA, m_g_EMA, m_g_EMA_Prev);
      if(m_currentRegime == REGIME_CHAOS)
      {
         Print("⛔ BLOCKED: Regime = CHAOS");
         return;
      }

      // Filters
      if(!CheckSpread())
      {
         Print("⛔ BLOCKED: Spread too wide");
         return;
      }

      Print("🚦 ALL CHECKS PASSED - Calling ScanForEntry");

      // Signal Scan
      ScanForEntry();
   }

   //+------------------------------------------------------------------+
   //| OnTrade Handler (Backup for Closed Trade Processing)             |
   //+------------------------------------------------------------------+
   void OnTrade()
   {
       static datetime lastTradeEventTime = 0;
       datetime currentTime = TimeCurrent();

       // Don't process if no time has passed
       if(currentTime == lastTradeEventTime) return;
       lastTradeEventTime = currentTime;

       // Check recent history (last 60 seconds)
       if(!HistorySelect(currentTime - 60, currentTime)) return;

       int dealCount = HistoryDealsTotal();
       for(int i = 0; i < dealCount; i++)
       {
           ulong ticket = HistoryDealGetTicket(i);
           if(ticket == 0) continue;

           // Check entry type
           if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

           // Check if it's our trade
           long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
           if(magic != m_params.MagicNumber) continue;

           double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
           double rOutcome = (profit > 0) ? 1.0 : -1.0;

           // Estimate R multiple from profit
           double equity = m_account.Equity();
           if(equity > 0 && m_params.RiskBase > 0)
           {
               double profitPct = (profit / equity) * 100.0;
               rOutcome = profitPct / m_params.RiskBase;
           }

           // Update modules (backup in case ManagePositions missed it)
           m_killSwitch.OnTradeClosed(rOutcome);
           if(m_params.EnableLearning)
               m_learning.OnTradeClosed(ticket);
       }
   }

   //+------------------------------------------------------------------+
   //| SOLUCIÓN DE RAÍZ: OnTimer para mantener datos activos           |
   //| Previene que MT5 libere las series de tiempo del símbolo        |
   //+------------------------------------------------------------------+
   void OnTimer()
   {
      // CRÍTICO: Acceder a las series de tiempo cada 90 segundos
      // Esto mantiene los datos "retenidos" en memoria y evita error 4807
      MqlRates rates[1];
      if(CopyRates(m_symbol, PERIOD_CURRENT, 0, 1, rates) > 0)
      {
         // Datos retenidos exitosamente
         static int retentionCount = 0;
         retentionCount++;

         // Log cada 10 ciclos (15 minutos) para confirmar que funciona
         if(retentionCount % 10 == 0)
            Print("🔄 Data retention active for ", m_symbol, " (", retentionCount, " cycles, ", (retentionCount * 90 / 60), " min)");
      }
      else
      {
         // Si falla la retención, los indicadores podrían volverse unhealthy
         Print("⚠️ Failed to retain timeseries for ", m_symbol, " - Error: ", GetLastError());

         // Intentar refrescar symbol info
         m_symbolInfo.RefreshRates();
      }
   }

private:
   //+------------------------------------------------------------------+
   //| Helper Functions (Private)                                        |
   //+------------------------------------------------------------------+
   bool IsNewBar()
   {
      datetime currentBarTime = iTime(m_symbol, PERIOD_CURRENT, 0);
      if(currentBarTime != m_lastBarTime)
      {
         m_lastBarTime = currentBarTime;
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| NUEVO: Crear indicadores con reintentos robustos                 |
   //+------------------------------------------------------------------+
   bool CreateIndicatorsWithRetry()
   {
      Print("🔧 Creating indicators for ", m_symbol, "...");

      // SOLUCIÓN DE RAÍZ #1: Pre-cargar datos del símbolo ANTES de crear indicadores
      Print("📊 Pre-loading timeseries data for ", m_symbol);
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(m_symbol, PERIOD_CURRENT, 0, 100, rates);
      if(copied <= 0)
      {
         Print("⏳ Waiting for ", m_symbol, " data to download from server...");
         Sleep(2000); // Dar tiempo a MT5 para descargar
         copied = CopyRates(m_symbol, PERIOD_CURRENT, 0, 100, rates);
      }

      if(copied > 0)
         Print("✅ ", m_symbol, " timeseries loaded: ", copied, " bars");
      else
         Print("⚠️ WARNING: Could not pre-load ", m_symbol, " data (Error ", GetLastError(), ")");

      // SOLUCIÓN DE RAÍZ #2: Crear Helper Chart PERSISTENTE para mantener datos activos
      if(m_helperChartId == 0)
      {
         m_helperChartId = ChartOpen(m_symbol, PERIOD_CURRENT);
         if(m_helperChartId > 0)
            Print("✅ Persistent helper chart created for ", m_symbol, " (ID: ", m_helperChartId, ")");
         else
            Print("⚠️ WARNING: Could not create helper chart for ", m_symbol);
      }

      for(int attempt = 1; attempt <= 3; attempt++)
      {
         Print("   Attempt ", attempt, "/3");

         // Liberar handles existentes
         if(m_hRSI != INVALID_HANDLE) { IndicatorRelease(m_hRSI); m_hRSI = INVALID_HANDLE; }
         if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
         if(m_hEMA != INVALID_HANDLE) { IndicatorRelease(m_hEMA); m_hEMA = INVALID_HANDLE; }
         if(m_hEMA50 != INVALID_HANDLE) { IndicatorRelease(m_hEMA50); m_hEMA50 = INVALID_HANDLE; }
         if(m_hEMA100 != INVALID_HANDLE) { IndicatorRelease(m_hEMA100); m_hEMA100 = INVALID_HANDLE; }

         // SOLUCIÓN DE RAÍZ #3: Crear indicadores con delays secuenciales
         m_hRSI = iRSI(m_symbol, PERIOD_CURRENT, m_params.RSI_Period, PRICE_CLOSE);
         if(m_hRSI == INVALID_HANDLE)
         {
            Print("   ❌ Failed to create RSI handle");
            Sleep(1000);
            continue;
         }
         Sleep(300); // Aumentado de 200 a 300ms

         m_hATR = iATR(m_symbol, PERIOD_CURRENT, 14); // Standard ATR period
         if(m_hATR == INVALID_HANDLE)
         {
            Print("   ❌ Failed to create ATR handle");
            Sleep(1000);
            continue;
         }
         Sleep(300);

         m_hEMA = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
         if(m_hEMA == INVALID_HANDLE)
         {
            Print("   ❌ Failed to create EMA handle");
            Sleep(1000);
            continue;
         }
         Sleep(300);

         // Crear indicadores de filtro de reversión si están habilitados
         if(m_params.UseReversalFilter)
         {
            m_hEMA50 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
            Sleep(300);
            m_hEMA100 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA100_Period, 0, MODE_EMA, PRICE_CLOSE);
            Sleep(300);
         }

         // SOLUCIÓN DE RAÍZ #4: Esperar a que los indicadores calculen datos
         Print("   ⏳ Waiting for indicators to calculate...");
         int timeout = 0;
         bool allCalculated = false;

         while(timeout < 30) // Max 30 segundos
         {
            int bars_rsi = BarsCalculated(m_hRSI);
            int bars_atr = BarsCalculated(m_hATR);
            int bars_ema = BarsCalculated(m_hEMA);

            if(bars_rsi > 0 && bars_atr > 0 && bars_ema > 0)
            {
               Print("   ✅ All indicators calculated - RSI: ", bars_rsi, " | ATR: ", bars_atr, " | EMA: ", bars_ema);
               allCalculated = true;
               break;
            }

            Sleep(1000);
            timeout++;
         }

         if(!allCalculated)
         {
            Print("   ⚠️ Timeout waiting for indicators to calculate on attempt ", attempt);
            continue;
         }

         // Verificar si se crearon correctamente
         if(VerifyIndicatorHandles())
         {
            Print("   ✅ Indicators created successfully on attempt ", attempt);

            // Verificar que tengan datos
            if(VerifyIndicatorData())
            {
               Print("   ✅ Indicators have valid data");
               return true;
            }
            else
            {
               Print("   ⚠️ Indicators created but no data yet");
            }
         }
         else
         {
            Print("   ❌ Failed to create indicators on attempt ", attempt);
            if(attempt < 3)
            {
               Sleep(500); // Esperar más antes de reintentar
            }
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| NUEVO: Verificar manejadores de indicadores                      |
   //+------------------------------------------------------------------+
   bool VerifyIndicatorHandles()
   {
      if(m_hRSI == INVALID_HANDLE)
      {
         Print("   ❌ RSI handle invalid");
         return false;
      }
      if(m_hATR == INVALID_HANDLE)
      {
         Print("   ❌ ATR handle invalid");
         return false;
      }
      if(m_hEMA == INVALID_HANDLE)
      {
         Print("   ❌ EMA handle invalid");
         return false;
      }
      
      if(m_params.UseReversalFilter)
      {
         if(m_hEMA50 == INVALID_HANDLE)
         {
            Print("   ❌ EMA50 handle invalid");
            return false;
         }
         if(m_hEMA100 == INVALID_HANDLE)
         {
            Print("   ❌ EMA100 handle invalid");
            return false;
         }
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| NUEVO: Verificar datos de indicadores                            |
   //+------------------------------------------------------------------+
   bool VerifyIndicatorData()
   {
      ResetLastError();
      
      // Verificar RSI
      double test[1];
      if(CopyBuffer(m_hRSI, 0, 0, 1, test) <= 0)
      {
         Print("   ❌ RSI no data, error: ", GetLastError());
         return false;
      }
      
      // Verificar ATR
      if(CopyBuffer(m_hATR, 0, 0, 1, test) <= 0)
      {
         Print("   ❌ ATR no data, error: ", GetLastError());
         return false;
      }
      
      // Verificar EMA
      if(CopyBuffer(m_hEMA, 0, 0, 1, test) <= 0)
      {
         Print("   ❌ EMA no data, error: ", GetLastError());
         return false;
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| NUEVO: Verificar indicadores (usado en Init)                     |
   //+------------------------------------------------------------------+
   bool VerifyIndicators()
   {
      return (AreIndicatorsHealthy() && VerifyIndicatorData());
   }

   void CheckNewDay()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      MqlDateTime last;
      TimeToStruct(m_lastResetDate, last);

      if(dt.day != last.day)
      {
         m_dailyLossR = 0;  // Reset daily loss tracking
         m_lastResetDate = TimeCurrent();
         m_consecutiveLosses = 0;  // Reset consecutive losses
         m_lastLossTime = 0;  // Reset loss timer

         Print("ðŸ“… New Day: ", m_symbol, " | Daily loss reset");
      }
   }

   //+------------------------------------------------------------------+
   //| Enhanced Indicator Recovery System                               |
   //+------------------------------------------------------------------+
   
   void ResetIndicatorBuffers()
   {
      ArrayFree(m_rsiBuffer);
      m_g_RSI = 0;
      m_g_RSI_Prev = 0;
      m_g_ATR = 0;
      m_g_EMA = 0;
      m_g_EMA_Prev = 0;
      m_g_ATR_MA = 0;
      m_g_EMA50 = 0;
      m_g_EMA100 = 0;
   }
   
   bool AreIndicatorsHealthy()
   {
      // Quick check if handles are valid
      if(m_hRSI == INVALID_HANDLE || m_hATR == INVALID_HANDLE || m_hEMA == INVALID_HANDLE)
      {
         Print("⚠️ Indicator handles invalid - RSI:", m_hRSI, " ATR:", m_hATR, " EMA:", m_hEMA);
         return false;
      }
      
      // Check if handles are still valid (not 4807 error)
      ResetLastError();
      double test[1];
      
      if(CopyBuffer(m_hRSI, 0, 0, 1, test) <= 0)
      {
         int err = GetLastError();
         if(err == 4807 || err == 0) // 4807 = invalid handle, 0 = no data
         {
            Print("⚠️ RSI handle invalidated, error: ", err);
            return false;
         }
      }
      
      if(CopyBuffer(m_hATR, 0, 0, 1, test) <= 0)
      {
         int err = GetLastError();
         if(err == 4807 || err == 0)
         {
            Print("⚠️ ATR handle invalidated, error: ", err);
            return false;
         }
      }
      
      if(CopyBuffer(m_hEMA, 0, 0, 1, test) <= 0)
      {
         int err = GetLastError();
         if(err == 4807 || err == 0)
         {
            Print("⚠️ EMA handle invalidated, error: ", err);
            return false;
         }
      }
      
      return true;
   }
   
   bool RecoverIndicators()
   {
      datetime now = TimeCurrent();
      
      // Prevent rapid re-recovery attempts - MODIFICADO: cooldown más corto para M5
      if(m_lastRecoveryTime > 0 && (now - m_lastRecoveryTime) < 30) // 30 segundos en lugar de 60
      {
         int secondsSince = (int)(now - m_lastRecoveryTime);
         Print("⏳ Recovery cooldown active. Last recovery: ", secondsSince, " seconds ago");
         return m_indicatorsHealthy; // Retornar estado actual
      }
      
      m_lastRecoveryTime = now;
      m_recoveryAttempts++;
      
      Print("🔄 ATTEMPTING INDICATOR RECOVERY #", m_recoveryAttempts, 
            " for ", m_symbol, " at ", TimeToString(now));
      
      // Step 1: Reset all handles and buffers
      ResetIndicatorBuffers();
      
      // Step 2: Force chart data reload
      // METHOD 1: Soft Reload (Background) - Try this first to avoid UI flashing
      bool softReloadSuccess = false;
      if(m_recoveryAttempts <= 1)
      {
         ResetLastError();
         MqlRates rates[];
         // Asking for recent data forces the terminal to sync
         if(CopyRates(m_symbol, PERIOD_CURRENT, 0, 10, rates) > 0)
         {
            Print("📊 Soft data synchronization successful for ", m_symbol);
            softReloadSuccess = true;
         }
         else
         {
            Print("⚠️ Soft synchronization failed for ", m_symbol, " (Error ", GetLastError(), ")");
         }
      }
      
      // METHOD 2: Hard Reload (Persistence Mode)
      if(!softReloadSuccess || m_recoveryAttempts > 1)
      {
         long currentChartId = ChartID(); // Save current Governor chart ID
         
         // Reuse existing helper chart if available
         if(m_helperChartId > 0 && ChartSymbol(m_helperChartId) == m_symbol)
         {
             Print("📊 Refining persistent helper chart for ", m_symbol);
             ChartRedraw(m_helperChartId);
         }
         else
         {
             // Open new helper chart if not exists
             m_helperChartId = ChartOpen(m_symbol, PERIOD_CURRENT);
             
             if(m_helperChartId > 0)
             {
                Print("📊 Opened persistent helper chart for ", m_symbol, " (ID: ", m_helperChartId, ")");
                
                // Set chart cleanly to background (remove grid, etc if needed - optional)
                ChartSetInteger(m_helperChartId, CHART_SHOW, false); // Try to hide contents
             }
         }
         
         if(m_helperChartId > 0)
         {
            // TRICK: Immediately bring Governor back to top to minimize "flash"
            if(currentChartId > 0) 
               ChartSetInteger(currentChartId, CHART_BRING_TO_TOP, true);
            
            Sleep(150); // Small delay to allow data pump
            // DO NOT CLOSE - Keep open for data stream
         }
      }
      
      // Step 3: Release invalid handles
      if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
      if(m_hEMA != INVALID_HANDLE) IndicatorRelease(m_hEMA);
      if(m_hEMA50 != INVALID_HANDLE) IndicatorRelease(m_hEMA50);
      if(m_hEMA100 != INVALID_HANDLE) IndicatorRelease(m_hEMA100);
      
      // Step 4: Recreate indicators with delays
      m_hRSI = iRSI(m_symbol, PERIOD_CURRENT, m_params.RSI_Period, PRICE_CLOSE);
      Sleep(100);
      
      m_hATR = iATR(m_symbol, PERIOD_CURRENT, 14);
      Sleep(100);
      
      m_hEMA = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      Sleep(100);
      
      if(m_params.UseReversalFilter)
      {
         m_hEMA50 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
         Sleep(100);
         m_hEMA100 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA100_Period, 0, MODE_EMA, PRICE_CLOSE);
         Sleep(100);
      }
      
      // Step 5: Verify recovery
      m_indicatorsHealthy = AreIndicatorsHealthy();
      
      if(m_indicatorsHealthy)
      {
         Print("✅ INDICATOR RECOVERY SUCCESSFUL for ", m_symbol);
         m_recoveryAttempts = 0;
         m_consecutiveDataFailures = 0;  // Reset error counter after successful recovery
         return true;
      }
      else
      {
         Print("❌ INDICATOR RECOVERY FAILED for ", m_symbol);
         
         // Si hemos intentado demasiadas veces, desactivar temporalmente
         if(m_recoveryAttempts >= 5)
         {
            Print("🚨 CRITICAL: Multiple recovery failures (", m_recoveryAttempts, 
                  ") for ", m_symbol, ". Entering safe mode.");
            m_indicatorsHealthy = false;
            // Podrías agregar un temporizador más largo aquí
            m_lastRecoveryTime = now + 300; // No intentar por 5 minutos
         }
         
         return false;
      }
   }

   //+------------------------------------------------------------------+
   //| Helper Functions for Enhanced Recovery System                    |
   //+------------------------------------------------------------------+

   // Check if we can attempt global recovery (cooldown check)
   bool CanAttemptRecovery()
   {
      datetime now = TimeCurrent();
      if(m_lastRecoveryTime > 0 && (now - m_lastRecoveryTime) < m_minRecoveryInterval)
      {
         int secondsSince = (int)(now - m_lastRecoveryTime);
         Print("⏳ Global recovery cooldown active. Last recovery: ", secondsSince, "s ago (min: ", m_minRecoveryInterval, "s)");
         return false;
      }
      return true;
   }

   // Check if we can recover a specific indicator (per-indicator cooldown + backoff)
   bool CanRecoverIndicator(IndicatorHealthState &health, string name)
   {
      // Check if permanently failed
      if(health.isPermanentlyFailed)
      {
         Print("❌ ", name, " is permanently failed. Skipping recovery.");
         return false;
      }

      // Check per-indicator cooldown with exponential backoff
      datetime now = TimeCurrent();
      if(health.lastRecoveryAttempt > 0)
      {
         int secondsSince = (int)(now - health.lastRecoveryAttempt);
         if(secondsSince < health.currentBackoffSeconds)
         {
            Print("⏳ ", name, " recovery cooldown active. Last attempt: ", secondsSince, "s ago (backoff: ", health.currentBackoffSeconds, "s)");
            return false;
         }
      }

      return true;
   }

   // Wait for indicator to calculate with polling and timeout
   bool WaitForIndicatorCalculation(int handle, string name, int timeoutSec)
   {
      Print("⏳ Waiting for ", name, " to calculate (timeout: ", timeoutSec, "s)...");

      for(int i = 0; i < timeoutSec; i++)
      {
         int calc = BarsCalculated(handle);
         if(calc > 0)
         {
            Print("✅ ", name, " calculated successfully (", calc, " bars) after ", i, "s");
            return true;
         }

         // Log progress every 10 seconds
         if(i > 0 && i % 10 == 0)
            Print("⏳ Still waiting for ", name, "... (", i, "s elapsed)");

         Sleep(1000);
      }

      Print("❌ ", name, " calculation timeout after ", timeoutSec, "s");
      return false;
   }

   // Record recovery failure and update backoff exponentially
   void RecordRecoveryFailure(IndicatorHealthState &health, string name)
   {
      health.consecutiveFailures++;
      health.totalRecoveryAttempts++;
      health.lastRecoveryAttempt = TimeCurrent();

      // Exponential backoff: double the wait time, up to max
      health.currentBackoffSeconds = MathMin(health.currentBackoffSeconds * 2, m_maxRecoveryInterval);

      Print("📊 ", name, " recovery failed | Consecutive failures: ", health.consecutiveFailures,
            " | Total attempts: ", health.totalRecoveryAttempts,
            " | Next backoff: ", health.currentBackoffSeconds, "s");

      // Check if we should mark as permanently failed
      if(health.consecutiveFailures >= m_maxConsecutiveFailures)
      {
         MarkIndicatorAsPermanentlyFailed(name, health);
      }
   }

   // Reset indicator health on successful recovery
   void ResetIndicatorHealth(IndicatorHealthState &health)
   {
      health.consecutiveFailures = 0;
      health.currentBackoffSeconds = m_initialBackoff;  // Reset to initial backoff
      health.lastRecoveryAttempt = TimeCurrent();
      health.totalRecoveryAttempts++;
   }

   // Mark indicator as permanently failed
   void MarkIndicatorAsPermanentlyFailed(string name, IndicatorHealthState &health)
   {
      health.isPermanentlyFailed = true;
      health.permanentFailureTime = TimeCurrent();

      Print("🚨 CRITICAL: ", name, " marked as PERMANENTLY FAILED for ", m_symbol);
      Print("   Total recovery attempts: ", health.totalRecoveryAttempts);
      Print("   Consecutive failures: ", health.consecutiveFailures);
      Print("   Failure time: ", TimeToString(health.permanentFailureTime));

      // Send push notification if enabled
      if(m_params.EnablePushNotifications)
      {
         string msg = "⚠️ " + m_symbol + " | " + name + " PERMANENTLY FAILED after " +
                      IntegerToString(health.totalRecoveryAttempts) + " attempts";
         SendNotification(msg);
      }

      // Special handling for ATR
      if(name == "ATR" && !m_allowTradingWithoutATR)
      {
         Print("🚨 ATR failed and trading without ATR is disabled. Symbol will not trade.");
      }
   }

   //+------------------------------------------------------------------+
   //| ENHANCED RECOVERY: Per-Indicator with Circuit Breaker            |
   //| Uses exponential backoff and permanent failure detection         |
   //+------------------------------------------------------------------+
   bool RecoverBrokenIndicators()
   {
      Print("🔧 ENHANCED RECOVERY: Starting per-indicator recovery for ", m_symbol);

      // Check global cooldown
      if(!CanAttemptRecovery())
      {
         return false;
      }

      m_lastRecoveryTime = TimeCurrent();

      bool allCriticalRecovered = true;  // Track if ALL critical indicators recover

      // === RECOVER RSI ===
      int bars_rsi = BarsCalculated(m_hRSI);
      if(bars_rsi == -1)
      {
         // SOFT RECOVERY: Check if handle is valid but just pending data
         int err = GetLastError();
         if(err != 4807 && err != 4002) // 4807=Invalid Handle
         {
            Print("⚠️ RSI data pending (", err, "). Waiting...");
            if(WaitForIndicatorCalculation(m_hRSI, "RSI", 10)) // Try waiting 10s
            {
                Print("✅ RSI recovered (soft wait)");
                ResetIndicatorHealth(m_rsiHealth);
                bars_rsi = BarsCalculated(m_hRSI); // Succcess
            }
         }
      
         if(bars_rsi == -1 && CanRecoverIndicator(m_rsiHealth, "RSI"))
         {
            Print("   🔄 Recreating broken RSI handle...");
            if(m_hRSI != INVALID_HANDLE) IndicatorRelease(m_hRSI);
            m_hRSI = iRSI(m_symbol, PERIOD_CURRENT, m_params.RSI_Period, PRICE_CLOSE);

            // Wait with exponential backoff
            Sleep(m_rsiHealth.currentBackoffSeconds * 1000);

            if(WaitForIndicatorCalculation(m_hRSI, "RSI", 30))
            {
               Print("   ✅ RSI recovered");
               ResetIndicatorHealth(m_rsiHealth);
            }
            else
            {
               Print("   ❌ RSI recovery failed");
               RecordRecoveryFailure(m_rsiHealth, "RSI");
               allCriticalRecovered = false;
            }
         }
         else if(bars_rsi == -1)
         {
            allCriticalRecovered = false;
         }
      }


      // === RECOVER ATR ===
      int bars_atr = BarsCalculated(m_hATR);
      if(bars_atr == -1)
      {
         // SOFT RECOVERY: Check if handle is valid but just pending data
         int err = GetLastError();
         if(err != 4807 && err != 4002) 
         {
            Print("⚠️ ATR data pending (", err, "). Waiting...");
            if(WaitForIndicatorCalculation(m_hATR, "ATR", 10)) 
            {
                Print("✅ ATR recovered (soft wait)");
                ResetIndicatorHealth(m_atrHealth);
                bars_atr = BarsCalculated(m_hATR); 
            }
         }
      
         if(bars_atr == -1 && CanRecoverIndicator(m_atrHealth, "ATR"))
         {
            Print("   🔄 Recreating broken ATR handle...");
            if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
            m_hATR = iATR(m_symbol, PERIOD_CURRENT, 14);

            // Wait with exponential backoff
            Sleep(m_atrHealth.currentBackoffSeconds * 1000);

            // ATR gets longer timeout (60s) as it's most problematic
            if(WaitForIndicatorCalculation(m_hATR, "ATR", 60))
            {
               Print("   ✅ ATR recovered");
               ResetIndicatorHealth(m_atrHealth);
            }
            else
            {
               Print("   ❌ ATR recovery failed");
               RecordRecoveryFailure(m_atrHealth, "ATR");

               // ATR failure only critical if trading without it is disabled
               if(!m_allowTradingWithoutATR)
                  allCriticalRecovered = false;
            }
         }
         else if(bars_atr == -1)
         {
            if(!m_allowTradingWithoutATR)
               allCriticalRecovered = false;
         }
      }


      // === RECOVER EMA ===
      int bars_ema = BarsCalculated(m_hEMA);
      if(bars_ema == -1)
      {
         // SOFT RECOVERY: Check if handle is valid but just pending data
         int err = GetLastError();
         if(err != 4807 && err != 4002) 
         {
            Print("⚠️ EMA data pending (", err, "). Waiting...");
            if(WaitForIndicatorCalculation(m_hEMA, "EMA", 10)) 
            {
                Print("✅ EMA recovered (soft wait)");
                ResetIndicatorHealth(m_emaHealth);
                bars_ema = BarsCalculated(m_hEMA); 
            }
         }
      
         if(bars_ema == -1 && CanRecoverIndicator(m_emaHealth, "EMA"))
         {
            Print("   🔄 Recreating broken EMA handle...");
            if(m_hEMA != INVALID_HANDLE) IndicatorRelease(m_hEMA);
            m_hEMA = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

            // Wait with exponential backoff
            Sleep(m_emaHealth.currentBackoffSeconds * 1000);

            if(WaitForIndicatorCalculation(m_hEMA, "EMA", 30))
            {
               Print("   ✅ EMA recovered");
               ResetIndicatorHealth(m_emaHealth);
            }
            else
            {
               Print("   ❌ EMA recovery failed");
               RecordRecoveryFailure(m_emaHealth, "EMA");
               allCriticalRecovered = false;
            }
         }
         else if(bars_ema == -1)
         {
            allCriticalRecovered = false;
         }
      }


      // === RECOVER EMA50/100 (if reversal filter enabled) ===
      if(m_params.UseReversalFilter)
      {
         int bars_ema50 = BarsCalculated(m_hEMA50);
         if(bars_ema50 == -1)
         {
            if(CanRecoverIndicator(m_ema50Health, "EMA50"))
            {
               Print("   🔄 Recreating broken EMA50 handle...");
               if(m_hEMA50 != INVALID_HANDLE) IndicatorRelease(m_hEMA50);
               m_hEMA50 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);

               Sleep(m_ema50Health.currentBackoffSeconds * 1000);

               if(WaitForIndicatorCalculation(m_hEMA50, "EMA50", 30))
               {
                  Print("   ✅ EMA50 recovered");
                  ResetIndicatorHealth(m_ema50Health);
               }
               else
               {
                  RecordRecoveryFailure(m_ema50Health, "EMA50");
                  // EMA50 not critical for basic trading
               }
            }
         }

         int bars_ema100 = BarsCalculated(m_hEMA100);
         if(bars_ema100 == -1)
         {
            if(CanRecoverIndicator(m_ema100Health, "EMA100"))
            {
               Print("   🔄 Recreating broken EMA100 handle...");
               if(m_hEMA100 != INVALID_HANDLE) IndicatorRelease(m_hEMA100);
               m_hEMA100 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA100_Period, 0, MODE_EMA, PRICE_CLOSE);

               Sleep(m_ema100Health.currentBackoffSeconds * 1000);

               if(WaitForIndicatorCalculation(m_hEMA100, "EMA100", 30))
               {
                  Print("   ✅ EMA100 recovered");
                  ResetIndicatorHealth(m_ema100Health);
               }
               else
               {
                  RecordRecoveryFailure(m_ema100Health, "EMA100");
                  // EMA100 not critical for basic trading
               }
            }
         }
      }

      // CRITICAL FIX: Return true only if ALL critical indicators recovered
      if(allCriticalRecovered)
      {
         Print("✅ All critical indicators recovered for ", m_symbol);
         return true;
      }
      else
      {
         Print("❌ Some critical indicators failed to recover for ", m_symbol);
         return false;
      }
   }

   bool UpdateIndicatorsEnhanced()
   {
      // ENHANCED: Check for permanently failed critical indicators at start
      if(m_rsiHealth.isPermanentlyFailed || m_emaHealth.isPermanentlyFailed)
      {
         Print("❌ Critical indicators permanently failed for ", m_symbol, " - Cannot trade");
         return false;
      }

      // Check if ATR permanently failed AND trading without ATR is disabled
      if(m_atrHealth.isPermanentlyFailed && !m_allowTradingWithoutATR)
      {
         Print("❌ ATR permanently failed and trading without ATR is disabled for ", m_symbol);
         return false;
      }

      // PRIMERO: Verificar salud de indicadores ANTES de intentar actualizar
      if(!m_indicatorsHealthy)
      {
         Print("⚠️ Indicators marked unhealthy, attempting recovery before update...");
         if(!RecoverIndicators())
         {
            Print("❌ Cannot update indicators - recovery failed");
            return false;
         }
      }

      // Ahora intentar actualización normal
      if(UpdateIndicatorsStandard())
      {
         m_indicatorsHealthy = true;
         m_consecutiveDataFailures = 0; // Reset counter on success
         return true;
      }

      // Si la actualización normal falla, verificar el error
      int lastError = GetLastError();

      // ENHANCED: Increased transient error tolerance from 10 to 15 failures
      // Error 4807/4806 es NORMAL en multi-símbolo (datos temporalmente no disponibles)
      if(lastError == 4807 || lastError == 4806)
      {
         m_consecutiveDataFailures++;

         // Tolerar hasta 15 fallos consecutivos antes de entrar en recovery mode
         if(m_consecutiveDataFailures < 15)
         {
            // Solo log cada 5 fallos para no spam
            if(m_consecutiveDataFailures % 5 == 1)
               Print("⏳ Data temporarily unavailable (4807/4806) - retry #", m_consecutiveDataFailures, "/15");
            return false; // Retry next tick - NO marcar unhealthy
         }

         // Después de 15 fallos, usar full recovery en lugar de surgical
         Print("⚠️ Persistent data unavailability (", m_consecutiveDataFailures, " failures). Attempting full recovery...");

         if(RecoverIndicators())
         {
            m_consecutiveDataFailures = 0;

            // ENHANCED: Add 3-second sleep after full recovery
            Print("⏳ Waiting 3 seconds after full recovery for indicators to stabilize...");
            Sleep(3000);

            // Intentar de nuevo después de la recuperación
            if(UpdateIndicatorsStandard())
            {
               Print("✅ Update successful after full recovery");
               return true;
            }
         }
      }
      // ENHANCED: Use full recovery instead of surgical for non-4807 errors
      else if(!AreIndicatorsHealthy())
      {
         Print("⚠️ Indicator handles invalid (Error ", lastError, "). Attempting full recovery...");

         if(RecoverIndicators())
         {
            // Add sleep after recovery
            Sleep(3000);

            if(UpdateIndicatorsStandard())
            {
               Print("✅ Update successful after full recovery");
               return true;
            }
         }
      }

      // Si llegamos aquí, la recuperación falló
      m_indicatorsHealthy = false;
      return false;
   }

   bool UpdateIndicatorsStandard()
   {
      // Check for permanently failed critical indicators at start
      if(m_rsiHealth.isPermanentlyFailed || m_emaHealth.isPermanentlyFailed)
      {
         Print("❌ Critical indicators permanently failed for ", m_symbol);
         return false;
      }

      // Skip ATR check if permanently failed AND trading without ATR is allowed
      bool skipATR = (m_atrHealth.isPermanentlyFailed && m_allowTradingWithoutATR);

      // SOLUCIÓN DE RAÍZ: Verificar handles válidos ANTES de BarsCalculated()
      if(m_hRSI == INVALID_HANDLE || m_hEMA == INVALID_HANDLE)
      {
         Print("❌ Invalid critical indicator handles for ", m_symbol);
         return false;
      }

      if(!skipATR && m_hATR == INVALID_HANDLE)
      {
         Print("❌ Invalid ATR handle for ", m_symbol);
         return false;
      }

      // ENHANCED: Increased retry count from 20 to 50
      int maxRetries = 50;
      int bars_rsi = -1, bars_atr = -1, bars_ema = -1;

      for(int i=0; i<maxRetries; i++)
      {
         ResetLastError();

         bars_rsi = BarsCalculated(m_hRSI);
         if(!skipATR) bars_atr = BarsCalculated(m_hATR);
         else bars_atr = 14;  // Assume valid if skipping
         bars_ema = BarsCalculated(m_hEMA);

         // Log failures on first attempt only (don't track them here)
         if(bars_rsi == -1 && i == 0)
            Print("⚠️ RSI BarsCalculated = -1 for ", m_symbol);

         if(bars_atr == -1 && !skipATR && i == 0)
            Print("⚠️ ATR BarsCalculated = -1 for ", m_symbol);

         if(bars_ema == -1 && i == 0)
            Print("⚠️ EMA BarsCalculated = -1 for ", m_symbol);

         // SOLUCIÓN DE RAÍZ: BarsCalculated() devuelve -1 si hay error
         if(bars_rsi == -1 || bars_atr == -1 || bars_ema == -1)
         {
            int error = GetLastError();
            if(i == 0)
               Print("⚠️ BarsCalculated error for ", m_symbol, " - RSI: ", bars_rsi, " ATR: ", bars_atr, " EMA: ", bars_ema, " Error: ", error);

            // Graduated sleep intervals: 500ms -> 1000ms based on retry count
            if(i < 20)
               Sleep(500);
            else if(i < 40)
               Sleep(1000);
            else
               Sleep(2000);

            continue;
         }

         // Verificar suficientes barras calculadas
         if(bars_rsi >= 2 && bars_atr >= 14 && bars_ema >= 2)
         {
            // Success - reset failure counters
            m_rsiHealth.consecutiveFailures = 0;
            m_atrHealth.consecutiveFailures = 0;
            m_emaHealth.consecutiveFailures = 0;
            break;
         }

         // Graduated sleep
         if(i < 20)
            Sleep(500);
         else if(i < 40)
            Sleep(1000);
         else
            Sleep(2000);
      }

      // After retry loop completes, if still failed, DON'T mark permanent here
      // Let the recovery system handle it through RecordRecoveryFailure()
      // which properly tracks recovery attempts, not individual check failures

      // SOLUCIÓN DE RAÍZ: Si hay handles corruptos (-1), intentar recovery selectivo
      if(bars_rsi == -1 || bars_atr == -1 || bars_ema == -1)
      {
         Print("⚠️ DETECTED CORRUPTED HANDLES for ", m_symbol, " - RSI:", bars_rsi, " ATR:", bars_atr, " EMA:", bars_ema);

         // Intentar recovery quirúrgico (solo recrea los corruptos)
         if(RecoverBrokenIndicators())
         {
            Print("✅ Broken indicators recovered, retrying update...");

            // Wait 2 seconds after recovery for indicators to stabilize
            Sleep(2000);

            // Reintentar verificación después de recovery
            bars_rsi = BarsCalculated(m_hRSI);
            if(!skipATR) bars_atr = BarsCalculated(m_hATR);
            else bars_atr = 14;  // If ATR permanently failed, assume valid
            bars_ema = BarsCalculated(m_hEMA);

            // Si siguen corruptos después de recovery (critical indicators only)
            if(bars_rsi == -1)
            {
               Print("❌ CRITICAL | ", m_symbol, " | RSI still broken after recovery");
               return false;
            }
            if(bars_atr == -1 && !skipATR)
            {
               Print("❌ WARNING | ", m_symbol, " | ATR still broken after recovery (will retry)");
               // Don't return false if trading without ATR is allowed
               // Recovery system will handle permanent failure through RecordRecoveryFailure()
            }
            if(bars_ema == -1)
            {
               Print("❌ CRITICAL | ", m_symbol, " | EMA still broken after recovery");
               return false;
            }

            Print("✅ All indicators recovered successfully (or using fallback)");
         }
         else
         {
            Print("❌ Surgical recovery failed");
            return false;
         }
      }

      if(bars_rsi < 2)
      {
         Print("⏳ WAITING | ", m_symbol, " | RSI calculating... (", bars_rsi, " bars ready) Error: ", GetLastError());
         return false;
      }
      if(bars_atr < 14 && !skipATR)
      {
         Print("⏳ WAITING | ", m_symbol, " | ATR calculating... (", bars_atr, " bars ready) Error: ", GetLastError());
         return false;
      }
      if(bars_ema < 2)
      {
         Print("⏳ WAITING | ", m_symbol, " | EMA calculating... (", bars_ema, " bars ready) Error: ", GetLastError());
         return false;
      }
      
      double rsi[], atr[], ema[];
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(ema, true);

      int copied = CopyBuffer(m_hRSI, 0, 0, 2, rsi);
      if(copied < 2)
      {
         Print("⚠️ UpdateIndicators FAILED | ", m_symbol, " | RSI buffer: copied ", copied, "/2 bars");
         return false;
      }

      // Only copy ATR if not skipped
      if(!skipATR)
      {
         copied = CopyBuffer(m_hATR, 0, 0, 14, atr);
         if(copied < 14)
         {
            Print("⚠️ UpdateIndicators FAILED | ", m_symbol, " | ATR buffer: copied ", copied, "/14 bars");
            return false;
         }
         m_g_ATR = atr[0];
      }
      else
      {
         // Use default ATR value if permanently failed
         m_g_ATR = m_symbolInfo.Point() * 100;  // Fallback ATR estimate
      }

      copied = CopyBuffer(m_hEMA, 0, 0, 2, ema);
      if(copied < 2)
      {
         Print("⚠️ UpdateIndicators FAILED | ", m_symbol, " | EMA buffer: copied ", copied, "/2 bars");
         return false;
      }

      m_g_RSI = rsi[0];
      m_g_RSI_Prev = rsi[1];
      m_g_EMA = ema[0];
      m_g_EMA_Prev = ema[1];

      // Update EMA50/100 for reversal filter
      if(m_params.UseReversalFilter)
      {
         int bars_ema50 = BarsCalculated(m_hEMA50);
         int bars_ema100 = BarsCalculated(m_hEMA100);
         
         if(bars_ema50 < 1 || bars_ema100 < 1)
         {
            Print("⏳ WAITING | ", m_symbol, " | EMA50/100 calculating...");
            return false;
         }
         
         double ema50[], ema100[];
         ArraySetAsSeries(ema50, true);
         ArraySetAsSeries(ema100, true);

         if(CopyBuffer(m_hEMA50, 0, 0, 1, ema50) < 1)
         {
            Print("⚠️ UpdateIndicators FAILED | ", m_symbol, " | EMA50 buffer");
            return false;
         }
         if(CopyBuffer(m_hEMA100, 0, 0, 1, ema100) < 1)
         {
            Print("⚠️ UpdateIndicators FAILED | ", m_symbol, " | EMA100 buffer");
            return false;
         }

         m_g_EMA50 = ema50[0];
         m_g_EMA100 = ema100[0];
      }

      // Calculate ATR MA (skip if ATR permanently failed)
      if(!skipATR)
      {
         double sum = 0;
         for(int i=0; i<14; i++) sum += atr[i];
         m_g_ATR_MA = sum / 14.0;
      }
      else
      {
         m_g_ATR_MA = m_g_ATR;  // Use fallback ATR
      }

      return true;
   }
   
   int CountPositions()
   {
      int count = 0;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         if(m_position.SelectByIndex(i))
         {
            if(m_position.Symbol() == m_symbol && m_position.Magic() == m_params.MagicNumber)
               count++;
         }
      }
      return count;
   }
   
   void ResetTradeState() { m_entryDirection = 0; m_addOn1Triggered = false; m_addOn2Triggered = false; }
   
   bool CheckSpread()
   {
      return (SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) <= m_params.MaxSpreadPoints);
   }

   //+------------------------------------------------------------------+
   //| Convert ENUM_ENTRY_TIER to ENTRY_QUALITY for Learning Module     |
   //+------------------------------------------------------------------+
   ENTRY_QUALITY ConvertTierToQuality(ENUM_ENTRY_TIER tier)
   {
       switch(tier)
       {
           case TIER_WEAK:   return EQ_WEAK;
           case TIER_GOOD:   return EQ_GOOD;
           case TIER_STRONG: return EQ_STRONG;
           case TIER_ELITE:  return EQ_ELITE;
           default:          return EQ_WEAK;  // Safe default
       }
   }

   bool CheckDisplacement(int dir)
   {
      if(!m_params.UseDisplacement) return true;

       // Scan last 5 bars for aligned displacement (including current intra-bar 0)
       for(int i = 0; i <= 5; i++)  
      {
         double o = iOpen(m_symbol, PERIOD_CURRENT, i);
         double c = iClose(m_symbol, PERIOD_CURRENT, i);
         double candleSize = MathAbs(c - o);

         // Raise threshold to 1.0 ATR for M15 (was 0.5 ATR - too loose)
         if(candleSize >= m_g_ATR * 1.0)
         {
            // CRITICAL: Check direction alignment
            bool isBullish = (c > o);
            bool isAligned = (dir == 1 && isBullish) || (dir == -1 && !isBullish);

            if(isAligned)
            {
               return true;  // Found aligned displacement
            }
         }
      }

      return false; // No aligned displacement found
   }

   void UpdateModules()
   {
      if(m_params.UseSMC)
      {
         // Update all SMC modules on new bar
         m_smcStructure.Update();
         m_smcOrderBlocks.Update();
         m_smcFVG.Update();
         m_smcLiquidity.Update();
         
         // GOD LEVEL SMC Updates
         m_smcMSS.Update();
         m_smcInducement.Update();
         m_smcPriceZone.Update();
      }
      
      // GOD LEVEL Fib Updates
      m_fibAdvanced.Update();

      // MTF Updates
      if(m_params.UseMTF)
         m_mtfAnalysis.Update();

      // NOTE: H1 Enhancement modules (Volume, Currency, Breaker, Macro, Power of 3, Divergence, Wyckoff)
      // calculate on-demand in GetConfluenceScore() - no Update() needed
   }
   
   void ScanForEntry()
   {
       // Removed excessive logging: Print("📊 SCANFORENTRY CALLED | Symbol: ", m_symbol);


       // Calculate Buy/Sell Scores
       double buyScore = CalculateConfluenceScore(1);
       double sellScore = CalculateConfluenceScore(-1);

       // Cache for dashboard display
       m_cachedBuyScore = buyScore;
       m_cachedSellScore = sellScore;
       m_lastScoreCalcTime = TimeCurrent();

       double bestScore = MathMax(buyScore, sellScore);
       m_currentBestScore = bestScore;  // Store for ranking
       int    direction = (buyScore > sellScore) ? 1 : -1;

       // Determine quality tier
       ENUM_ENTRY_TIER quality = (bestScore >= 14.0) ? TIER_ELITE : (bestScore >= 12.0 ? TIER_STRONG : TIER_GOOD);

       // INTRA-BAR PERSISTENCE (Stability Filter)
       if(direction != m_lastSignalDirection || bestScore < m_params.MinConfluenceEntry)
       {
           m_signalStartTime = TimeCurrent(); // Reset timer if direction changes or score drops
           m_lastSignalDirection = direction;
           return; // Wait for next tick to start counting
       }


       int secondsHeld = (int)(TimeCurrent() - m_signalStartTime);
       if(secondsHeld < m_persistenceSeconds)
       {
           Print("⏳ STABILIZING | Signal held for ", secondsHeld, "s / ", m_persistenceSeconds, "s");
           return;
       }

       Print("✅ STABILIZED SIGNAL (", secondsHeld, "s) - Continuing to filters...");

       // DB LOGGING: Log all stabilized signals (even if rejected later)
       if(CheckPointer(m_db) != POINTER_INVALID)
       {
           double smcScore = 0;
           double fibScore = m_fibAdvanced.GetConfluenceScore(direction);
           if(m_params.UseSMC) 
               smcScore = m_smcOrderBlocks.GetConfluenceScore(direction) + m_smcFVG.GetConfluenceScore(direction) + 
                          m_smcLiquidity.GetConfluenceScore(direction) + m_smcMSS.GetConfluenceScore(direction);
           
           // Determine rejection reason (preview)
           string rejection = "None";
           if(!CheckReversalFilter(direction)) rejection = "ReversalFilter";
           else if(!CheckDirectionCooldown(direction)) rejection = "DirectionCooldown";
           else if(m_consecutiveLosses >= m_params.MaxConsecutiveLosses) rejection = "CircuitBreaker";
           
           // Note: We don't know "GovernorBlocked" yet, but we log this pre-check snapshot
           m_db.LogSignal(m_symbol, direction, bestScore, 0, (rejection == "None"), rejection, smcScore, fibScore);
       }


       // OVERTRADING PROTECTION: Reversal Filter
       if(!CheckReversalFilter(direction)) return;

       // OVERTRADING PROTECTION: Same-Direction Cooldown
       if(!CheckDirectionCooldown(direction)) return;

       // OVERTRADING PROTECTION: Consecutive Losses Circuit Breaker
       if(m_consecutiveLosses >= m_params.MaxConsecutiveLosses)
       {
           Print("ðŸ›‘ CIRCUIT BREAKER: ", m_symbol, " | ", m_consecutiveLosses, " consecutive losses");
           return;
       }

       // Updated quality tier (H1 ENHANCED 22-point scale)
       quality = TIER_GOOD;
       
       // H1 ENHANCED Thresholds (22 point max):
       // ELITE:  â‰¥14 points (64%+) - God-tier institutional H1 setups
       // STRONG: â‰¥12 points (55%) - High-probability professional setups  
       // GOOD:   â‰¥10 points (45%) - Acceptable entry with confluence
       // WEAK:   < 10 points   - Do not trade (below minimum)
       
       if(bestScore >= 14.0) quality = TIER_ELITE;
       else if(bestScore >= 12.0) quality = TIER_STRONG;
       else if(bestScore >= 10.0) quality = TIER_GOOD;
       else quality = TIER_WEAK;  // Scores below 10.0 use WEAK tier (wider stops, conservative TP)

       // MANDATORY INSTITUTIONAL FOOTPRINT (prevents pure technical trades)
       // Require at least ONE SMC factor for non-elite setups (lowered to 0.5 for real-world detection rates)
       bool hasInstitutionalFootprint =
           (m_smcOrderBlocks.GetConfluenceScore(direction) >= 0.5) ||
           (m_smcMSS.GetConfluenceScore(direction) >= 0.5) ||
           (m_smcLiquidity.GetConfluenceScore(direction) >= 0.5) ||
           (m_smcInducement.GetConfluenceScore(direction) >= 0.5);

       // DEBUG: Log SMC scores
       Print("🔍 SMC CHECK | Score: ", DoubleToString(bestScore, 1),
             " | OB:", DoubleToString(m_smcOrderBlocks.GetConfluenceScore(direction), 1),
             " | MSS:", DoubleToString(m_smcMSS.GetConfluenceScore(direction), 1),
             " | Liq:", DoubleToString(m_smcLiquidity.GetConfluenceScore(direction), 1),
             " | Ind:", DoubleToString(m_smcInducement.GetConfluenceScore(direction), 1),
             " | HasFootprint: ", (hasInstitutionalFootprint ? "YES" : "NO"));

       // Reject pure technical setups below 16.0 score
       if(!hasInstitutionalFootprint && bestScore < 16.0)
       {
           Print("❌ REJECTED: No institutional footprint");
           return; // Reject pure technical setups
       }

       Print("✅ PASSED SMC CHECK - Sending to Governor");

       // Governor Check
       GovernorRequest req;
       req.symbol = m_symbol;
       req.baseRisk = m_params.RiskBase;
       req.winRate = 0.5; // Default or get from learning
       req.rollingR = 1.0;
       req.regime = (int)m_currentRegime;

       double approvedRisk = m_allocator.RequestRisk(req);

       Print("🏛️ GOVERNOR RESPONSE | ApprovedRisk: ", DoubleToString(approvedRisk, 2), "%");

       if(approvedRisk > 0.0)
       {
           Print("✅ EXECUTING TRADE | Direction: ", (direction == 1 ? "BUY" : "SELL"),
                 " | Quality: ", EnumToString(quality), " | Risk: ", DoubleToString(approvedRisk, 2), "%");
           m_currentConfluence = bestScore;
           ExecuteTrade(direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, approvedRisk, "Eng_Entry", quality);
       }
       else
       {
           Print("❌ GOVERNOR BLOCKED | Risk = 0.0 (Check position limits, exposure, or allocator rules)");
       }
   }
   
   //+------------------------------------------------------------------+
   //| GOD LEVEL Confluence Score (0-30 Point System)                   |
   //| Max: 30 | ELITE: â‰¥18 | STRONG: â‰¥14 | GOOD: â‰¥10                   |
   //+------------------------------------------------------------------+
   double CalculateConfluenceScore(int direction)
   {
       double score = 0;
       double currentPrice = m_symbolInfo.Bid();

       // ============================================
       // H1 ENHANCED SCORING SYSTEM (22 POINTS MAX)
       // ============================================
       // Core SMC: 5.0 pts
       // Advanced ICT: 5.5 pts
       // Volume Analysis: 2.5 pts
       // MTF: 2.0 pts
       // Currency Strength: 1.5 pts
       // Divergence: 1.5 pts
       // Wyckoff: 1.5 pts
       // Fibonacci: 1.5 pts
       // Regime: 1.0 pt
       // ============================================

       // ============ CORE SMC (0-5.0) ============
       
       // 1. Trend (EMA 200 + slope) - 1.0 point
       double emaSlope = m_g_EMA - m_g_EMA_Prev;
       bool slopeStrong = MathAbs(emaSlope) >= (m_g_ATR * m_params.EMA_MinSlope);
       
       if(direction == 1 && currentPrice > m_g_EMA && emaSlope > 0 && slopeStrong) score += 1.0;
       if(direction == -1 && currentPrice < m_g_EMA && emaSlope < 0 && slopeStrong) score += 1.0;
       
       // 2. Market structure (Higher Highs/Lows) - up to 1.0 point (QUALITY-WEIGHTED)
       int highestBar = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, m_params.SwingLookback, 1);
       int lowestBar = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, m_params.SwingLookback, 1);

       if(highestBar >= 0 && lowestBar >= 0)
       {
           double swingHigh = iHigh(m_symbol, PERIOD_CURRENT, highestBar);
           double swingLow = iLow(m_symbol, PERIOD_CURRENT, lowestBar);
           double structureRange = swingHigh - swingLow;
           double structureStrength = structureRange / m_g_ATR;

           // Ignore weak/choppy structure (below 2.0 ATR range)
           if(structureStrength >= 2.0)
           {
               // Graduated scoring: 0.5 at 2 ATR, 1.0 at 4+ ATR
               double structureScore = MathMin(1.0, (structureStrength - 2.0) / 2.0 + 0.5);

               if(direction == 1 && lowestBar < highestBar) score += structureScore;
               if(direction == -1 && highestBar < lowestBar) score += structureScore;
           }
       }
       
       // 3. RSI extremes - 1.0 point (REGIME-AWARE)
       if(m_currentRegime == REGIME_TREND)
       {
           // In trending market: reward pullback RSI (NOT extremes)
           // Uptrend: RSI 40-60 (healthy pullback to moving average)
           // Downtrend: RSI 40-60 (bounce to moving average)
           if(direction == 1 && m_g_RSI >= 40 && m_g_RSI <= 60) score += 1.0;
           else if(direction == -1 && m_g_RSI >= 40 && m_g_RSI <= 60) score += 1.0;
       }
       else // REGIME_RANGE or REGIME_VOLATILE
       {
           // In ranging market: use mean reversion (extremes)
           if(direction == 1 && m_g_RSI <= m_params.RSI_Oversold) score += 1.0;
           if(direction == -1 && m_g_RSI >= m_params.RSI_Overbought) score += 1.0;
       }
       
       // 4. RSI momentum - 0.5 point
       if(m_params.RSI_Momentum)
       {
           if(direction == 1 && m_g_RSI > m_g_RSI_Prev) score += 0.5;
           if(direction == -1 && m_g_RSI < m_g_RSI_Prev) score += 0.5;
       }
       
       // 5. Displacement (price velocity) - 1.0 point
       if(CheckDisplacement(direction)) score += 1.0;
       
       // 6. Volatility filter (ATR normalized) - 1.5 points
       double atrRatio = m_g_ATR / m_g_ATR_MA;
       if(atrRatio >= 0.8 && atrRatio <= 1.3) score += 1.5;  // Optimal volatility
       else if(atrRatio >= 0.6 && atrRatio <= 1.5) score += 0.75;  // Acceptable
       
       // 7. Chop filter - 1.0 point
       if(m_params.UseChopFilter)
       {
           if(atrRatio > 0.5) score += 1.0;  // Not choppy
       }

       // ============ CORE SMC (0-5.0) ============

       if(m_params.UseSMC)
       {
           // Structure Break (BOS) - up to 1.0 pt
           score += m_smcStructure.GetConfluenceScore(direction);

           // Order Blocks - up to 1.5 pts
           score += m_smcOrderBlocks.GetConfluenceScore(direction);

           // Fair Value Gaps - up to 1.0 pt
           score += m_smcFVG.GetConfluenceScore(direction);

           // Liquidity Sweep - up to 1.5 pts
           score += m_smcLiquidity.GetConfluenceScore(direction);
       }

       // ============ ADVANCED ICT (0-5.5) ============

       if(m_params.UseSMC)
       {
           // Breaker Blocks (Failed OBs) - up to 2.0 pts
           score += m_breakerBlocks.GetBreakerScore(direction);

           // Macro Windows (Silver Bullet timing) - up to 1.5 pts
           score += m_macroWindows.GetMacroScore();

           // Power of 3 Phases - up to 2.0 pts
           score += m_powerOf3.GetPhaseScore();
       }

       // ============ VOLUME ANALYSIS (0-2.5) ============

       // Volume Profile confluence
       score += m_volumeAnalysis.GetConfluenceScore(direction);

       // ============ MULTI-TIMEFRAME (0-2.0) ============

       if(m_params.UseMTF)
       {
           // HTF Trend Alignment - up to 2.0 pts
           score += m_mtfAnalysis.GetConfluenceScore(direction);
       }

       // ============ CURRENCY STRENGTH (0-1.5) ============

       // Pair strength differential
       score += m_currencyStrength.GetConfluenceScore(m_symbol, direction);

       // ============ DIVERGENCE (0-1.5) ============

       // Regular/Hidden divergence detection
       score += m_divergence.GetDivergenceScore(direction);

       // ============ WYCKOFF (0-1.5) ============

       // Wyckoff phase alignment
       score += m_wyckoff.GetWyckoffScore(direction);

       // ============ FIBONACCI (0-1.5) ============

       // Advanced Fibonacci (Clusters + OTE)
       score += m_fibAdvanced.GetConfluenceScore(direction);

       // ============ REGIME CONFIRMATION (0-1.0) ============

       // ML Regime Detection - up to 1.0 pt
       double regimeBonus = 0;
       if(m_currentRegime == REGIME_TREND ||
          m_currentRegime == MR_TRENDING_HIGH_VOL ||
          m_currentRegime == MR_TRENDING_LOW_VOL)
       {
           // Trend regime: reward alignment with trend
           double emaSlope = m_g_EMA - m_g_EMA_Prev;
           if((direction == 1 && emaSlope > 0) || (direction == -1 && emaSlope < 0))
               regimeBonus = 1.0;
       }
       else if(m_currentRegime == REGIME_RANGE ||
               m_currentRegime == MR_RANGING_HIGH_VOL ||
               m_currentRegime == MR_RANGING_LOW_VOL)
       {
           // Range regime: reward mean reversion
           if((direction == 1 && m_g_RSI <= m_params.RSI_Oversold) ||
              (direction == -1 && m_g_RSI >= m_params.RSI_Overbought))
               regimeBonus = 0.75;
       }
       score += regimeBonus;

       // ============ CONTEXT MULTIPLIERS ============
       // Apply regime-based weighting
       if(m_currentRegime == REGIME_VOLATILE)
       {
           score *= 0.8;  // Reduce in volatile conditions (need higher confirmation)
       }

       // Final score (capped at 30)
       return MathMin(score, 30.0);
   }

   //+------------------------------------------------------------------+
   //| Enhanced Reversal Filter (Multi-Factor Momentum Confirmation)    |
   //+------------------------------------------------------------------+
   bool CheckReversalFilter(int direction)
   {
       if(!m_params.UseReversalFilter) return true;

       double currentPrice = m_symbolInfo.Bid();

       // Factor 1: EMA Alignment
       bool emaAligned = false;
       if(direction == 1 && m_g_EMA50 > m_g_EMA100) emaAligned = true;
       if(direction == -1 && m_g_EMA50 < m_g_EMA100) emaAligned = true;

       // Factor 2: Price vs EMA50
       bool priceCorrect = false;
       if(direction == 1 && currentPrice > m_g_EMA50) priceCorrect = true;
       if(direction == -1 && currentPrice < m_g_EMA50) priceCorrect = true;

       // Factor 3: EMA Separation (trend strength)
       double separation = MathAbs(m_g_EMA50 - m_g_EMA100);
       bool strongTrend = (separation >= m_g_ATR * m_params.EMA_SeparationATR);

       // Factor 4: RSI Confirmation
       bool rsiOK = false;
       if(direction == 1 && m_g_RSI < 70) rsiOK = true;
       if(direction == -1 && m_g_RSI > 30) rsiOK = true;

       // Must pass at least 3 of 4 factors
       int score = (emaAligned ? 1 : 0) + (priceCorrect ? 1 : 0) + (strongTrend ? 1 : 0) + (rsiOK ? 1 : 0);

       if(score < 3)
       {
           Print("ðŸš« REVERSAL FILTER: ", m_symbol, " ", (direction == 1 ? "BUY" : "SELL"),
                 " | Score: ", score, "/4 | EMAs: ", DoubleToString(m_g_EMA50, 5), "/", DoubleToString(m_g_EMA100, 5));
           return false;
       }

       return true;
   }

   //+------------------------------------------------------------------+
   //| Same-Direction Cooldown Check                                     |
   //+------------------------------------------------------------------+
   bool CheckDirectionCooldown(int direction)
   {
       if(m_params.ReversalCooldownMinutes <= 0) return true;

       datetime now = TimeCurrent();
       datetime lastTime = (direction == 1) ? m_lastBuyTime : m_lastSellTime;

       if(lastTime > 0)
       {
           int minutesSince = (int)((now - lastTime) / 60);
           if(minutesSince < m_params.ReversalCooldownMinutes)
           {
               int remaining = m_params.ReversalCooldownMinutes - minutesSince;
               Print("â¸ï¸ COOLDOWN: ", m_symbol, " ", (direction == 1 ? "BUY" : "SELL"),
                     " | ", remaining, " min remaining");
               return false;
           }
       }

       return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate Lot Size Based on Risk                                 |
   //+------------------------------------------------------------------+
   double CalculateLotSize(double slDist, double riskPct)
   {
       if(slDist <= 0 || riskPct <= 0)
       {
           Print("ERROR: Invalid lot calculation inputs - slDist:", slDist, " riskPct:", riskPct);
           return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
       }

       double equity = m_account.Equity();
       if(equity <= 0) equity = m_account.Balance();
       if(equity <= 0)
       {
           Print("ERROR: Invalid account equity/balance");
           return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
       }

       double riskAmt = equity * (riskPct / 100.0);
       double tv = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
       double ts = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);

       if(ts <= 0 || tv <= 0)
       {
           Print("ERROR: Invalid symbol tick info - ts:", ts, " tv:", tv);
           return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
       }

       double lots = riskAmt / ((slDist / ts) * tv);

       // Get volume limits
       double minL = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
       double maxL = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
       double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

       // Clamp to broker limits
       if(lots < minL) lots = minL;
       if(lots > maxL) lots = maxL;

       // Additional safety limit
       if(lots > m_params.MaxLotsPerTrade)
       {
           Print("âš ï¸ Lots capped: ", DoubleToString(lots, 3), " â†’ ", DoubleToString(m_params.MaxLotsPerTrade, 2));
           lots = m_params.MaxLotsPerTrade;
       }

       // Round to step size
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
   //| Calculate Take Profit Level                                      |
   //+------------------------------------------------------------------+
   double CalculateTakeProfit(double price, double slDist, int direction, ENUM_ENTRY_TIER quality)
   {
       if(m_params.TPMode == 0) return 0;  // No TP

       double tpR = m_params.FixedTP_R;  // Default fallback to prevent zero TP

       // MODE 1: Fixed TP
       if(m_params.TPMode == 1)
       {
           tpR = m_params.FixedTP_R;
       }
       // MODE 2 & 3: Adaptive TP
       else if(m_params.TPMode == 2 || m_params.TPMode == 3)
       {
           // Use learned MFE if enabled and available
           if(m_params.TPUseLearnedMFE && m_params.EnableLearning)
           {
               double avgMFE = m_learning.GetAvgMFE();
               if(avgMFE > 0 && m_g_ATR > 0)
               {
                   tpR = (avgMFE / m_g_ATR) * 0.75;  // 75% of learned MFE
               }
               else
               {
                   tpR = m_params.FixedTP_R;
               }
           }
           else
           {
               tpR = m_params.FixedTP_R;
           }

           // Quality adjustments (NON-COMPOUNDING)
           double qualityMult = 1.0;
           if(quality == TIER_ELITE) qualityMult = 1.2;
           else if(quality == TIER_STRONG) qualityMult = 1.1;
           else if(quality == TIER_WEAK) qualityMult = 0.8;

           // Regime adjustments (NON-COMPOUNDING)
           double regimeMult = 1.0;
           if(m_currentRegime == REGIME_TREND) regimeMult = 1.3;
           else if(m_currentRegime == REGIME_RANGE) regimeMult = 0.85;
           else if(m_currentRegime == REGIME_VOLATILE) regimeMult = 1.1;

           // Use MAX of multipliers (don't compound)
           // Prevents unrealistic targets like Elite+Trend = 1.56x
           double appliedMult = MathMax(qualityMult, regimeMult);
           tpR = m_params.FixedTP_R * appliedMult;
       }

       // CRITICAL: Ensure minimum TP ratio
       if(tpR < m_params.MinTP_R) tpR = m_params.MinTP_R;
       if(tpR > m_params.MaxTP_R) tpR = m_params.MaxTP_R;

       // SAFETY: Absolute minimum to prevent zero TP
       if(tpR < 1.0) tpR = 1.0;

       // Calculate TP price
       double tpDist = slDist * tpR;

       // CRITICAL FIX: Ensure TP distance is meaningful (minimum 0.5 ATR)
       double minTpDist = m_g_ATR * 0.5;
       if(tpDist < minTpDist) tpDist = minTpDist;

       double tp = (direction == 1) ? price + tpDist : price - tpDist;

       // Ensure TP meets broker requirements
       double stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * m_symbolInfo.Point();
       double minDist = MathMax(stopsLevel, 20.0 * m_symbolInfo.Point());  // Min 20 points

       if(direction == 1 && (tp - price) < minDist)
           tp = price + minDist;
       else if(direction == -1 && (price - tp) < minDist)
           tp = price - minDist;

       double finalTp = NormalizeDouble(tp, (int)m_symbolInfo.Digits());

       // FINAL VALIDATION: Ensure TP is different from entry
       if(MathAbs(finalTp - price) < m_symbolInfo.Point() * 10)
       {
           Print("âš ï¸ TP TOO CLOSE TO ENTRY! Setting to 2R | Price: ", price, " | BadTP: ", finalTp);
           finalTp = (direction == 1) ? price + (slDist * 2.0) : price - (slDist * 2.0);
           finalTp = NormalizeDouble(finalTp, (int)m_symbolInfo.Digits());
       }

       return finalTp;
   }

   //+------------------------------------------------------------------+
   //| Check Margin Requirement                                         |
   //+------------------------------------------------------------------+
   bool CheckMarginRequirement(ENUM_ORDER_TYPE type, double lots)
   {
       if(!m_params.EnableMarginCheck) return true;

       double freeMargin = m_account.FreeMargin();
       double requiredMargin = 0;

       double price = (type == ORDER_TYPE_BUY) ? m_symbolInfo.Ask() : m_symbolInfo.Bid();

       if(!OrderCalcMargin(type, m_symbol, lots, price, requiredMargin))
       {
           Print("ERROR: Cannot calculate margin requirement for ", m_symbol, " ", DoubleToString(lots, 2), " lots");
           return false;
       }

       // Require at least 150% of needed margin for safety buffer
       double safetyMargin = requiredMargin * 1.5;

       if(freeMargin < safetyMargin)
       {
           Print("MARGIN CHECK FAILED for ", m_symbol, ":");
           Print("  Required: ", DoubleToString(requiredMargin, 2),
                 " | Free: ", DoubleToString(freeMargin, 2),
                 " | Safety needed: ", DoubleToString(safetyMargin, 2));
           return false;
       }

       return true;
   }

   //+------------------------------------------------------------------+
   //| Execute Trade with Full State Tracking                           |
   //+------------------------------------------------------------------+
   void ExecuteTrade(ENUM_ORDER_TYPE type, double riskPct, string label, ENUM_ENTRY_TIER quality)
   {
       double price = (type == ORDER_TYPE_BUY) ? m_symbolInfo.Ask() : m_symbolInfo.Bid();

       // M5 SCALPING STOP LOSS (Precision Entries)
       // Elite = tighter stop (precision entry) = better R:R
       // Weak = wider stop (uncertainty) = worse R:R
       double slDist = m_g_ATR * 1.5;  // Default for GOOD quality

       if(quality == TIER_ELITE) slDist = m_g_ATR * 1.0;       // 🎯 SURGICAL (1.0 ATR)
       else if(quality == TIER_STRONG) slDist = m_g_ATR * 1.3; // 🎯 TIGHT (1.3 ATR)
       else slDist = m_g_ATR * 1.8;  // 🛡️ SAFE (1.8 ATR)

       double stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * m_symbolInfo.Point();
       if(slDist < stopsLevel + 10 * m_symbolInfo.Point())
           slDist = stopsLevel + 10 * m_symbolInfo.Point();

       double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
       sl = NormalizeDouble(sl, (int)m_symbolInfo.Digits());

       double lots = CalculateLotSize(slDist, riskPct);

       string comment = m_params.TradeComment + "|" + label + "|Q" + IntegerToString((int)quality);

       // Calculate TP
       int dir = (type == ORDER_TYPE_BUY) ? 1 : -1;
       double tp = CalculateTakeProfit(price, slDist, dir, quality);

       // Validate margin
       if(!CheckMarginRequirement(type, lots))
       {
           Print("TRADE REJECTED: Insufficient margin for ", DoubleToString(lots, 2), " lots");
           m_failSafe.ReportFailure();
           return;
       }

       // Open position with TP
       if(m_trade.PositionOpen(m_symbol, type, lots, price, sl, tp, comment))
       {
           ulong ticket = m_trade.ResultOrder();
           if(ticket == 0 && PositionSelect(m_symbol)) ticket = PositionGetInteger(POSITION_TICKET);

           // Register with learning module
           if(m_params.EnableLearning)
           {
               m_learning.RegisterTrade(ticket, slDist, ConvertTierToQuality(quality));
           }

           // Store in local state
           int sz = ArraySize(m_states);
           ArrayResize(m_states, sz + 1);
           m_states[sz].ticket = ticket;
           m_states[sz].partialClosed = false;
           m_states[sz].initialRisk = slDist;
           m_states[sz].quality = quality;
           
           // SEND MOBILE NOTIFICATION
           if(m_params.EnablePushNotifications)
           {
              string notifyMsg = "🚀 NEW TRADE | " + m_symbol + " " + (type==ORDER_TYPE_BUY ? "BUY" : "SELL") + 
                                 "\nLot: " + DoubleToString(lots, 2) + 
                                 "\nPrice: " + DoubleToString(price, (int)m_symbolInfo.Digits()) +
                                 "\nSL: " + DoubleToString(sl, (int)m_symbolInfo.Digits()) +
                                 "\nTP: " + DoubleToString(tp, (int)m_symbolInfo.Digits()) +
                                 "\nQuality: " + EnumToString(quality) +
                                 "\nScore: " + DoubleToString(m_currentConfluence, 1);
              
              if(!SendNotification(notifyMsg))
              {
                 Print("⚠️ Failed to send push notification. Error: ", GetLastError());
              }
           }

           // Update cooldown tracking (CRITICAL FOR OVERTRADING PROTECTION)
           if(type == ORDER_TYPE_BUY)
               m_lastBuyTime = TimeCurrent();
           else
               m_lastSellTime = TimeCurrent();

            // CALCULATE BAR PROGRESS
            datetime barOpen = iTime(m_symbol, PERIOD_CURRENT, 0);
            int barElapsed = (int)(TimeCurrent() - barOpen);
            int barTotal = PeriodSeconds(PERIOD_CURRENT);
            double barProgress = (barTotal > 0) ? (double)barElapsed / barTotal * 100.0 : 0;
            int secondsHeld = (int)(TimeCurrent() - m_signalStartTime);

            // Log trade
            Print("===========================================");
            Print("✅ TRADE OPENED [Intra-Bar @ ", DoubleToString(barProgress, 1), "%] | ", m_symbol);
            Print("  Ticket: #", ticket);
            Print("  Type: ", EnumToString(type));
            Print("  Price: ", DoubleToString(price, (int)m_symbolInfo.Digits()));
            Print("  SL: ", DoubleToString(sl, (int)m_symbolInfo.Digits()), " (", DoubleToString(slDist / m_symbolInfo.Point(), 0), " pips)");
            if(tp > 0)
                Print("  TP: ", DoubleToString(tp, (int)m_symbolInfo.Digits()), " (", DoubleToString(MathAbs(tp - price) / slDist, 2), "R)");
            Print("  Lots: ", DoubleToString(lots, 2));
            Print("  Risk: ", DoubleToString(riskPct, 2), "%");
            Print("  Quality: ", EnumToString(quality));
            Print("  Confluence: ", DoubleToString(m_currentConfluence, 1), "/30");
            Print("  Persistence: ", secondsHeld, "s");
            Print("===========================================");

           m_tradesExecuted++;
       }
       else
       {
           Print("TRADE FAILED: ", m_trade.ResultRetcode(), " - ", m_trade.ResultRetcodeDescription());
           m_failSafe.ReportFailure();
       }
   }
   
   //+------------------------------------------------------------------+
   //| Manage Positions (Cleanup Closed + Trail Open)                   |
   //+------------------------------------------------------------------+
   void ManagePositions()
   {
       // ============ SECTION A: CLOSED POSITION CLEANUP ============
       for(int i = ArraySize(m_states) - 1; i >= 0; i--)
       {
           ulong ticket = m_states[i].ticket;
           if(!PositionSelectByTicket(ticket))
           {
               // Position closed - process results
               double profitMoney = 0;

               if(HistorySelectByPosition(ticket))
               {
                   int deals = HistoryDealsTotal();
                   for(int d = 0; d < deals; d++)
                       profitMoney += HistoryDealGetDouble(HistoryDealGetTicket(d), DEAL_PROFIT);

                   // Calculate profit in R
                   double risk = m_states[i].initialRisk;
                   double profitR = (risk > 0) ? profitMoney / (m_account.Equity() * (risk / 100.0)) : 0;

                   // Update learning modules
                   if(m_params.EnableLearning)
                   {
                       m_learning.OnTradeClosed(ticket);
                   }

                   // Update KillSwitch
                   double rOutcome = (profitMoney > 0) ? 1.0 : -1.0;
                   m_killSwitch.OnTradeClosed(rOutcome);

                   // CRITICAL: Track consecutive losses for circuit breaker
                   if(profitMoney < 0)
                   {
                       m_consecutiveLosses++;
                       m_lastLossTime = TimeCurrent();
                       Print("ðŸ“‰ LOSS: ", m_symbol, " | ", DoubleToString(profitR, 2), "R | Streak: ", m_consecutiveLosses);
                   }
                   else
                   {
                       if(m_consecutiveLosses > 0)
                           Print("âœ… WIN breaks losing streak of ", m_consecutiveLosses);
                       m_consecutiveLosses = 0;  // Reset on win
                   }

                   // Track daily loss
                   m_dailyLossR += profitR;
               }

               // Remove from states array
               for(int j = i; j < ArraySize(m_states) - 1; j++)
                   m_states[j] = m_states[j + 1];
               ArrayResize(m_states, ArraySize(m_states) - 1);
           }
       }

       // ============ SECTION B: OPEN POSITION MANAGEMENT ============
       for(int i = PositionsTotal() - 1; i >= 0; i--)
       {
           if(!m_position.SelectByIndex(i)) continue;
           if(m_position.Symbol() != m_symbol || m_position.Magic() != m_params.MagicNumber) continue;

           ulong ticket = m_position.Ticket();
           double open = m_position.PriceOpen();
           double curr = m_position.PriceCurrent();
           double sl = m_position.StopLoss();
           double tp = m_position.TakeProfit();
           double vol = m_position.Volume();
           long pType = m_position.PositionType();

           // Update learning stats (MFE/MAE tracking)
           if(m_params.EnableLearning)
           {
               m_learning.UpdateTrade(ticket, open, curr, (int)pType);
           }

           // Get/Create State
           int sIdx = -1;
           for(int s = 0; s < ArraySize(m_states); s++)
           {
               if(m_states[s].ticket == ticket)
               {
                   sIdx = s;
                   break;
               }
           }

           // Create state if not found
           if(sIdx == -1)
           {
               int sz = ArraySize(m_states);
               ArrayResize(m_states, sz + 1);
               m_states[sz].ticket = ticket;
               m_states[sz].partialClosed = false;
               m_states[sz].initialRisk = MathAbs(open - sl);
               m_states[sz].quality = TIER_GOOD;
               sIdx = sz;
           }

           double risk = m_states[sIdx].initialRisk;
           if(risk <= 0) risk = m_symbolInfo.Point() * 100;

           double rawProfit = (pType == POSITION_TYPE_BUY) ? (curr - open) : (open - curr);
           double profitR = rawProfit / risk;

           ENUM_ENTRY_TIER quality = m_states[sIdx].quality;

           // Skip trailing if mode is off
           if(m_params.TrailingMode == 0) continue;

           // Get trailing parameters
           double partTP = m_params.PartialTP_R;
           double trailStart = m_params.TrailStart_R;
           double beTrigger = m_params.BE_Threshold_R;
           double partialPercent = m_params.PartialClosePercent;

           // Quality adjustments
           if(quality == TIER_WEAK) { partTP *= 0.8; trailStart *= 0.7; }
           if(quality == TIER_ELITE) { partTP *= 1.5; trailStart *= 1.5; }

           // Regime adjustments
           if(m_currentRegime == REGIME_TREND) { partTP *= 1.2; trailStart *= 1.2; }
           else if(m_currentRegime == REGIME_RANGE) { partTP *= 0.8; trailStart *= 0.8; }

           // 1. Partial TP
           if(!m_states[sIdx].partialClosed && profitR >= partTP)
           {
               double closeVol = NormalizeDouble(vol * (partialPercent / 100.0), 2);
               double minV = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
               if(closeVol >= minV && (vol - closeVol) >= minV)
               {
                   if(m_trade.PositionClosePartial(ticket, closeVol))
                   {
                       m_states[sIdx].partialClosed = true;
                       if(m_params.EnableLearning)
                           m_learning.SetPartialClosed(ticket, true);
                       Print("ðŸ’° PARTIAL TP: ", m_symbol, " | ", closeVol, " lots @ ", DoubleToString(profitR, 2), "R");
                   }
               }
           }

           // 2. Break-Even
           if(profitR >= beTrigger && MathAbs(sl - open) > m_symbolInfo.Point())
           {
               bool better = (pType == POSITION_TYPE_BUY) ? sl < open : (sl > open || sl == 0);
               if(better)
               {
                   if(m_trade.PositionModify(ticket, open, tp))
                       Print("ðŸ”’ BREAK-EVEN: ", m_symbol, " @ ", DoubleToString(profitR, 2), "R");
               }
           }

           // 3. Trailing Stop (INSTITUTIONAL LOGIC)
           // Elite = tight trail (lock profits fast)
           // Weak = wide trail (give room to develop)
           if(profitR >= trailStart)
           {
               double mult = m_params.TrailATR_Mult;  // Default 1.5
               if(quality == TIER_ELITE) mult *= 0.7;   // ✅ TIGHT trail (lock profits)
               else if(quality == TIER_STRONG) mult *= 1.0; // ✅ STANDARD trail
               else mult *= 1.3;  // ✅ WIDE trail (give room)

               double td = m_g_ATR * mult;
               double newSL = (pType == POSITION_TYPE_BUY) ? curr - td : curr + td;

               if((pType == POSITION_TYPE_BUY && newSL > sl && newSL < curr) ||
                  (pType == POSITION_TYPE_SELL && (newSL < sl || sl == 0) && newSL > curr))
               {
                   m_trade.PositionModify(ticket, newSL, tp);
               }
           }
       }
   }
};

#endif
