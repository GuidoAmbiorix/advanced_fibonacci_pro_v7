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
};

//+------------------------------------------------------------------+
//| SYMBOL ENGINE CLASS                                               |
//+------------------------------------------------------------------+
class CSymbolEngineWrapper
{
public:
   string         m_symbol;
   SymbolEngineParams m_params;
   
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

   // Recovery State
   bool m_indicatorsHealthy;
   datetime m_lastRecoveryTime;
   int m_recoveryAttempts;

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

      // FIBONACCI
      p.SwingLookback = 20;
      p.FibLevelLow = 0.618;
      p.FibLevelHigh = 0.786;
      p.ZoneTolerance = 0.15; // 15% of ATR

      // DISPLACEMENT
      p.UseDisplacement = true;
      p.DisplacementATR = 0.5;
      p.DisplacementLookback = 3;

      // RSI
      p.RSI_Period = 14;
      p.RSI_Oversold = 30;
      p.RSI_Overbought = 70;
      p.RSI_Momentum = true;

      // TREND
      p.EMA_Period = 200;
      p.UseTrendFilter = true;
      p.EMA_MinSlope = 0.1;

      // CHOP FILTER
      p.UseChopFilter = true;
      p.ChopThreshold = 60.0; // Filter if ATR is extremely high vs Avg? Or low? Logic depends on implementation.
      p.ATR_MA_Period = 14;

      // CONFLUENCE (M15 OPTIMIZED)
      p.MinConfluenceEntry = 4; // M15: Higher quality threshold (cleaner setups)
      p.MaxPositions = 1;
      
      // RISK
      p.RiskBase = 1.0;
      p.MaxRisk = 2.0;
      p.MaxLotsPerTrade = 50.0;
      p.EnableMarginCheck = true;

      // TAKE PROFIT (M5 SWING-SCALPING OPTIMIZED)
      p.TPMode = 3; // Hybrid
      p.FixedTP_R = 2.0;         // M5: Tighter targets for faster timeframe
      p.MinTP_R = 0.8;           // M5: Minimum 0.8R for scalp quality
      p.MaxTP_R = 3.0;           // M5: Allow runners to 3R
      p.TPUseLearnedMFE = true;

      // EXIT (Trade Management)
      p.TrailingMode = 2; // Adaptive
      p.PartialTP_R = 1.5;
      p.PartialClosePercent = 50.0;
      p.BE_Threshold_R = 1.2;
      p.TrailStart_R = 2.0;
      p.TrailATR_Mult = 1.5;

      // SPREAD
      p.MaxSpreadPoints = 50;

      // SMC
      p.UseSMC = true;
      // M5 OPTIMIZED SMC PARAMETERS
      p.SMC_SwingLookback = 15;       // M5: Tighter lookback
      p.SMC_MinImpulseATR = 1.5;      // M5: Lower impulse threshold
      p.SMC_MinFVG_ATR = 0.3;         // M5: Smaller gaps are significant on M5

      // MTF
      p.UseMTF = true;
      // M5 OPTIMIZED MTF HIERARCHY: H1 → M15 → M5
      p.HTF = PERIOD_H1;         // Highest: H1 for macro trend
      p.MTF = PERIOD_M15;        // Middle: M15 for structure
      p.MTF_EMAPeriod = 200;

      // NEWS
      p.UseNewsFilter = true;
      p.NewsMinutesBefore = 60;
      p.NewsMinutesAfter = 60;

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
      
      return p;
   }

public:
   CSymbolEngineWrapper()
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
      m_helperChartId = 0;

      // Intra-Bar Init
      m_signalStartTime = 0;
      m_lastSignalDirection = 0;
      m_persistenceSeconds = 10; // 10s stability filter
   }
   
   ~CSymbolEngineWrapper()
   {
      Deinit();
   }
   
   
   //+------------------------------------------------------------------+
   //| Initialization Modificada                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, SymbolEngineParams &params)
   {
      m_symbol = symbol;
      m_params = params;
      
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
      if(!m_indicatorsHealthy) return "UNHEALTHY";
      
      // Verificar handles
      string status = "HEALTHY";
      if(m_hRSI == INVALID_HANDLE) status = "RSI_BAD";
      if(m_hATR == INVALID_HANDLE) status = "ATR_BAD";
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
       Print("=== DEBUG INDICATOR STATUS ===");
       Print("Symbol: ", m_symbol);
       Print("RSI Handle: ", m_hRSI, " | Valid: ", (m_hRSI != INVALID_HANDLE ? "YES" : "NO"));
       Print("ATR Handle: ", m_hATR, " | Valid: ", (m_hATR != INVALID_HANDLE ? "YES" : "NO"));
       Print("EMA Handle: ", m_hEMA, " | Valid: ", (m_hEMA != INVALID_HANDLE ? "YES" : "NO"));
       Print("Indicators Healthy: ", (m_indicatorsHealthy ? "YES" : "NO"));
       Print("Recovery Attempts: ", m_recoveryAttempts);
       Print("Last Recovery: ", TimeToString(m_lastRecoveryTime));
       
       // Intentar leer datos
       ResetLastError();
       double test[1];
       if(CopyBuffer(m_hRSI, 0, 0, 1, test) > 0)
           Print("RSI Data: OK (", test[0], ")");
       else
           Print("RSI Data: FAILED - Error: ", GetLastError());
           
       Print("==============================");
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
      
      ManagePositions();
      
      // REMOVED: if(!IsNewBar()) { return; }
      // Intra-bar processing enabled
      
      static datetime lastScanTime = 0;
      if(TimeCurrent() == lastScanTime) return; // Prevent multiple scans per tick
      lastScanTime = TimeCurrent();
      
      Print("🔔 NEW BAR | ", m_symbol, " | OnTick called");
      
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
      
      for(int attempt = 1; attempt <= 3; attempt++)
      {
         Print("   Attempt ", attempt, "/3");
         
         // Liberar handles existentes
         if(m_hRSI != INVALID_HANDLE) { IndicatorRelease(m_hRSI); m_hRSI = INVALID_HANDLE; }
         if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
         if(m_hEMA != INVALID_HANDLE) { IndicatorRelease(m_hEMA); m_hEMA = INVALID_HANDLE; }
         if(m_hEMA50 != INVALID_HANDLE) { IndicatorRelease(m_hEMA50); m_hEMA50 = INVALID_HANDLE; }
         if(m_hEMA100 != INVALID_HANDLE) { IndicatorRelease(m_hEMA100); m_hEMA100 = INVALID_HANDLE; }
         
         // Crear indicadores principales
         m_hRSI = iRSI(m_symbol, PERIOD_CURRENT, m_params.RSI_Period, PRICE_CLOSE);
         Sleep(200);
         
         m_hATR = iATR(m_symbol, PERIOD_CURRENT, 14);
         Sleep(200);
         
         m_hEMA = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
         Sleep(200);
         
         // Crear indicadores de filtro de reversión si están habilitados
         if(m_params.UseReversalFilter)
         {
            m_hEMA50 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
            Sleep(200);
            m_hEMA100 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA100_Period, 0, MODE_EMA, PRICE_CLOSE);
            Sleep(200);
         }
         
         // Verificar si se crearon correctamente
         if(VerifyIndicatorHandles())
         {
            Print("   ✅ Indicators created successfully on attempt ", attempt);
            
            // Esperar a que se calculen algunos datos
            Sleep(300);
            
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
   
   bool UpdateIndicatorsEnhanced()
   {
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
         return true;
      }
      
      // Si la actualización normal falla, verificar el error
      int lastError = GetLastError();
      
      // Verificar si los indicadores están fundamentalmente rotos
      if(lastError == 4807 || !AreIndicatorsHealthy())
      {
         Print("⚠️ Indicators unhealthy after update (Error ", lastError, "). Attempting recovery...");
         
         if(RecoverIndicators())
         {
            // Intentar de nuevo después de la recuperación
            if(UpdateIndicatorsStandard())
            {
               Print("✅ Update successful after recovery");
               return true;
            }
         }
      }
      
      // Si llegamos aquí, la recuperación falló o el error no fue 4807
      m_indicatorsHealthy = false;
      return false;
   }

   bool UpdateIndicatorsStandard()
   {
      // CRITICAL: Check if indicators are fully calculated before reading
      // Retry loop to handle transient states 
      int maxRetries = 20; 
      int bars_rsi = -1, bars_atr = -1, bars_ema = -1;
      
      for(int i=0; i<maxRetries; i++)
      {
         bars_rsi = BarsCalculated(m_hRSI);
         bars_atr = BarsCalculated(m_hATR);
         bars_ema = BarsCalculated(m_hEMA);
         
         if(bars_rsi >= 2 && bars_atr >= 14 && bars_ema >= 2)
            break; // All good
            
         Sleep(100); 
      }
      
      if(bars_rsi < 2)
      {
         Print("⏳ WAITING | ", m_symbol, " | RSI calculating... (", bars_rsi, " bars ready) Error: ", GetLastError());
         return false;
      }
      if(bars_atr < 14)
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
      
      copied = CopyBuffer(m_hATR, 0, 0, 14, atr);
      if(copied < 14)
      {
         Print("⚠️ UpdateIndicators FAILED | ", m_symbol, " | ATR buffer: copied ", copied, "/14 bars");
         return false;
      }
      
      copied = CopyBuffer(m_hEMA, 0, 0, 2, ema);
      if(copied < 2)
      {
         Print("⚠️ UpdateIndicators FAILED | ", m_symbol, " | EMA buffer: copied ", copied, "/2 bars");
         return false;
      }

      m_g_RSI = rsi[0];
      m_g_RSI_Prev = rsi[1];
      m_g_ATR = atr[0];
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

      // Calculate ATR MA
      double sum = 0;
      for(int i=0; i<14; i++) sum += atr[i];
      m_g_ATR_MA = sum / 14.0;

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
       Print("📊 SCANFORENTRY CALLED | Symbol: ", m_symbol);

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

       // H1 OPTIMIZED STOP LOSS (Wider for H1 volatility)
       // Elite = tighter stop (precision entry) = better R:R
       // Weak = wider stop (uncertainty) = worse R:R
       double slDist = m_g_ATR * 2.5;  // Default for GOOD quality (H1 optimized)

       if(quality == TIER_ELITE) slDist = m_g_ATR * 2.0;       // ✅ TIGHT for H1 (was 1.0 for M15)
       else if(quality == TIER_STRONG) slDist = m_g_ATR * 2.2; // ✅ MODERATE for H1 (was 1.3 for M15)
       else slDist = m_g_ATR * 2.5;  // ✅ WIDE for H1 (was 1.8 for M15)

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
