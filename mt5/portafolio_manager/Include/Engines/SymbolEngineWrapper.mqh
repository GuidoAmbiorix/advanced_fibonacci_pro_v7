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

// Multi-Timeframe and Filters
#include "../MTF_Confluence.mqh"
#include "../NewsFilter.mqh"
#include "../KillzoneOptimizer.mqh"
#include "../KellyPositionSizer.mqh"

// Learning & Memory Modules
#include "../Memory/TradeJournal.mqh"
#include "../Memory/PatternMemory.mqh"
#include "../Learning/PerformanceAnalyzer.mqh"
#include "../Learning/PatternRecognizer.mqh"

// Adaptive Modules
#include "../Adaptive/AdaptiveRiskManager.mqh"
#include "../Adaptive/AdaptiveExitManager.mqh"
#include "../Adaptive/AdaptiveFilterManager.mqh"

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
   
   // SMC Modules
   CSMCStructureBreak  m_smcStructure;
   CSMCOrderBlocks     m_smcOrderBlocks;
   CSMCFairValueGap    m_smcFVG;
   CSMCLiquiditySweep  m_smcLiquidity;
   
   // Filter Modules
   CMTFConfluence      m_mtfAnalysis;
   CNewsFilter         m_newsFilter;
   CKillzoneOptimizer  m_killzoneOptimizer;
   CKellyPositionSizer m_kellySizer;
   
   // Learning Modules
   CTradeJournal       m_tradeJournal;
   CPatternMemory      m_patternMemory;
   CPerformanceAnalyzer m_performanceAnalyzer;
   CPatternRecognizer  m_patternRecognizer;
   
   // Adaptive Modules
   CAdaptiveRiskManager   m_adaptiveRisk;
   CAdaptiveExitManager   m_adaptiveExit;
   CAdaptiveFilterManager m_adaptiveFilter;
   
   // Indicator Handles & Buffers
   int m_hRSI, m_hATR, m_hEMA;
   int m_hEMA50, m_hEMA100;   // Reversal filter EMAs
   double m_g_RSI, m_g_RSI_Prev, m_g_ATR, m_g_EMA, m_g_EMA_Prev, m_g_ATR_MA;
   double m_g_EMA50, m_g_EMA100;   // Reversal filter EMA values
   double m_rsiBuffer[];

   // State Variables
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

      // CONFLUENCE (M5 SCALPING OPTIMIZED)
      p.MinConfluenceEntry = 3; // SCALPING: Lower threshold for M5 (was 5, now 3)
      p.MaxPositions = 1;
      
      // RISK
      p.RiskBase = 1.0;
      p.MaxRisk = 2.0;
      p.MaxLotsPerTrade = 50.0;
      p.EnableMarginCheck = true;

      // TAKE PROFIT (M5 SCALPING OPTIMIZED)
      p.TPMode = 3; // Hybrid
      p.FixedTP_R = 1.8;         // SCALPING: Quick 1.8R targets (was 3.0)
      p.MinTP_R = 0.8;           // SCALPING: Allow smaller wins (was 1.0)
      p.MaxTP_R = 2.5;           // SCALPING: Cap at 2.5R for quick exits
      p.TPUseLearnedMFE = true;

      // EXIT (Trade Management)
      p.TrailingMode = 2; // Adaptive
      p.PartialTP_R = 1.5;
      p.PartialClosePercent = 50.0;
      p.BE_Threshold_R = 1.2;
      p.TrailStart_R = 2.0;
      p.TrailATR_Mult = 1.5;

      // SPREAD
      p.MaxSpreadPoints = 30;

      // SMC
      p.UseSMC = true;
      p.SMC_SwingLookback = 20;
      p.SMC_MinImpulseATR = 1.5;  // SCALPING: More lenient OB detection (was 2.0)
      p.SMC_MinFVG_ATR = 0.3;     // SCALPING: Detect smaller FVGs (was 0.5)

      // MTF
      p.UseMTF = true;
      p.HTF = PERIOD_H4;
      p.MTF = PERIOD_H1;
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
   }
   
   ~CSymbolEngineWrapper()
   {
      Deinit();
   }
   
   //+------------------------------------------------------------------+
   //| Initialization                                                    |
   //+------------------------------------------------------------------+
   bool Init(string symbol, SymbolEngineParams &params)
   {
      m_symbol = symbol;
      m_params = params;
      
      if(!m_symbolInfo.Name(m_symbol)) return false;
      m_symbolInfo.RefreshRates();
      
      m_trade.SetExpertMagicNumber(m_params.MagicNumber);
      m_trade.SetDeviationInPoints(m_params.Deviation);
      m_trade.SetTypeFilling(m_params.FillingType);
      
      // Initialize Core Indicators
      m_hRSI = iRSI(m_symbol, PERIOD_CURRENT, m_params.RSI_Period, PRICE_CLOSE);
      m_hATR = iATR(m_symbol, PERIOD_CURRENT, 14);
      m_hEMA = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

      if(m_hRSI == INVALID_HANDLE || m_hATR == INVALID_HANDLE || m_hEMA == INVALID_HANDLE)
      {
         Print("Engine Init Failed: Core Indicators (", m_symbol, ")");
         return false;
      }

      // Initialize Reversal Filter Indicators
      if(m_params.UseReversalFilter)
      {
         m_hEMA50 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
         m_hEMA100 = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA100_Period, 0, MODE_EMA, PRICE_CLOSE);

         if(m_hEMA50 == INVALID_HANDLE || m_hEMA100 == INVALID_HANDLE)
         {
            Print("Engine Init Failed: Reversal Filter Indicators (", m_symbol, ")");
            return false;
         }
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
      }
      
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
      
      // Allocator is always connected in this context (Governor controls it)
      // If we are in Governor, we are "Connected".
      
      return true;
   }
   
   void Deinit()
   {
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

   int GetPositionCount() { return m_positionCount; }

   //+------------------------------------------------------------------+
   //| Main Processing Loop (Call from OnTick)                          |
   //+------------------------------------------------------------------+
   void OnTick()
   {
      m_symbolInfo.RefreshRates();

      // Update Position Count
      m_positionCount = CountPositions();
      if(m_positionCount == 0) ResetTradeState();

      ManagePositions();

      if(!IsNewBar()) return;

      if(!UpdateIndicators()) return;

      // Update Modules
      UpdateModules();

      // CRITICAL: Update Killzone Optimizer to determine current active killzone
      if(m_params.UseKillzoneFilter)
         m_killzoneOptimizer.Update();

      // Safety Checks
      if(!m_failSafe.IsExecutionSafe()) return;
      if(m_params.UseNewsFilter && !m_newsFilter.IsTradingAllowed()) return;
      if(m_params.UseKillzoneFilter && !m_killzoneOptimizer.IsTradingAllowed()) return;

      // Regime
      m_currentRegime = m_regime.Detect(m_g_ATR, m_g_ATR_MA, m_g_EMA, m_g_EMA_Prev);
      if(m_currentRegime == REGIME_CHAOS) return;

      // Filters
      if(!CheckSpread()) return;

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
   
   bool UpdateIndicators()
   {
      double rsi[], atr[], ema[];
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(ema, true);

      if(CopyBuffer(m_hRSI, 0, 0, 2, rsi) < 2) return false;
      if(CopyBuffer(m_hATR, 0, 0, 14, atr) < 14) return false;
      if(CopyBuffer(m_hEMA, 0, 0, 2, ema) < 2) return false;

      m_g_RSI = rsi[0];
      m_g_RSI_Prev = rsi[1];
      m_g_ATR = atr[0];
      m_g_EMA = ema[0];
      m_g_EMA_Prev = ema[1];

      // Update EMA50/100 for reversal filter
      if(m_params.UseReversalFilter)
      {
         double ema50[], ema100[];
         ArraySetAsSeries(ema50, true);
         ArraySetAsSeries(ema100, true);

         if(CopyBuffer(m_hEMA50, 0, 0, 1, ema50) < 1) return false;
         if(CopyBuffer(m_hEMA100, 0, 0, 1, ema100) < 1) return false;

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
      for(int i = 2; i <= m_params.DisplacementLookback + 1; i++)
      {
         double o = iOpen(m_symbol, PERIOD_CURRENT, i);
         double c = iClose(m_symbol, PERIOD_CURRENT, i);
         if(MathAbs(c - o) >= m_g_ATR * m_params.DisplacementATR)
         {
            if(dir == 1 && c > o) return true;
            if(dir == -1 && c < o) return true;
         }
      }
      return false;
   }

   void UpdateModules()
   {
      if(m_params.UseSMC)
      {
         // SMC updates can be heavy, do them on new bar
         // (Calling Init/Update inside modules usually handled implicitly or via dedicated update methods)
         // Our simplified modules generally re-calc on demand or via getter, assuming logic is stateless or self-updating.
      }
   }
   
   void ScanForEntry()
   {
       // Calculate Buy/Sell Scores
       double buyScore = CalculateConfluenceScore(1);
       double sellScore = CalculateConfluenceScore(-1);

       // Cache for dashboard display
       m_cachedBuyScore = buyScore;
       m_cachedSellScore = sellScore;
       m_lastScoreCalcTime = TimeCurrent();

       double bestScore = MathMax(buyScore, sellScore);
       int    direction = (buyScore > sellScore) ? 1 : -1;

       // Minimum threshold check
       if(bestScore < m_params.MinConfluenceEntry) return;

       // OVERTRADING PROTECTION: Reversal Filter
       if(!CheckReversalFilter(direction)) return;

       // OVERTRADING PROTECTION: Same-Direction Cooldown
       if(!CheckDirectionCooldown(direction)) return;

       // OVERTRADING PROTECTION: Consecutive Losses Circuit Breaker
       if(m_consecutiveLosses >= m_params.MaxConsecutiveLosses)
       {
           Print("🛑 CIRCUIT BREAKER: ", m_symbol, " | ", m_consecutiveLosses, " consecutive losses");
           return;
       }

       // Determine quality tier (dynamic based on MinConfluenceEntry)
       ENUM_ENTRY_TIER quality = TIER_GOOD;

       // For scalping (MinConf=3): ELITE≥7, STRONG≥5, GOOD≥3
       // For swing (MinConf=6): ELITE≥9, STRONG≥7, GOOD≥6
       double eliteThreshold = m_params.MinConfluenceEntry + 4.0;
       double strongThreshold = m_params.MinConfluenceEntry + 2.0;

       if(bestScore >= eliteThreshold) quality = TIER_ELITE;
       else if(bestScore >= strongThreshold) quality = TIER_STRONG;
       else if(bestScore >= m_params.MinConfluenceEntry) quality = TIER_GOOD;
       else return;  // Below minimum - NOW USES PARAMETER!

       // Governor Check
       GovernorRequest req;
       req.symbol = m_symbol;
       req.baseRisk = m_params.RiskBase;
       req.winRate = 0.5; // Default or get from learning
       req.rollingR = 1.0;
       req.regime = (int)m_currentRegime;

       double approvedRisk = m_allocator.RequestRisk(req);

       if(approvedRisk > 0.0)
       {
           m_currentConfluence = bestScore;
           ExecuteTrade(direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, approvedRisk, "Eng_Entry", quality);
       }
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Confluence Score (0-12 Point System)                   |
   //+------------------------------------------------------------------+
   double CalculateConfluenceScore(int direction)
   {
       double score = 0;
       double currentPrice = m_symbolInfo.Bid();

       // ============ ORIGINAL FACTORS (0-6) ============

       // 1. Trend (EMA 200 + slope) - 1.0 point
       double emaSlope = m_g_EMA - m_g_EMA_Prev;
       bool slopeStrong = MathAbs(emaSlope) >= (m_g_ATR * m_params.EMA_MinSlope);

       if(direction == 1 && currentPrice > m_g_EMA && emaSlope > 0 && slopeStrong) score += 1.0;
       if(direction == -1 && currentPrice < m_g_EMA && emaSlope < 0 && slopeStrong) score += 1.0;

       // 2. Structure - 1.0 point
       int highestBar = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, m_params.SwingLookback, 1);
       int lowestBar = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, m_params.SwingLookback, 1);
       if(direction == 1 && lowestBar < highestBar) score += 1.0;
       if(direction == -1 && highestBar < lowestBar) score += 1.0;

       // 3. Fib Zone - 1.0 point
       if(highestBar >= 0 && lowestBar >= 0)
       {
           double swingHigh = iHigh(m_symbol, PERIOD_CURRENT, highestBar);
           double swingLow = iLow(m_symbol, PERIOD_CURRENT, lowestBar);
           double range = swingHigh - swingLow;
           double tolerance = m_g_ATR * m_params.ZoneTolerance;

           if(range >= m_g_ATR * 1.5)
           {
               if(direction == 1)
               {
                   double f618 = swingHigh - (range * m_params.FibLevelLow);
                   double f786 = swingHigh - (range * m_params.FibLevelHigh);
                   if(currentPrice <= f618 + tolerance && currentPrice >= f786 - tolerance) score += 1.0;
               }
               else
               {
                   double f618 = swingLow + (range * m_params.FibLevelLow);
                   double f786 = swingLow + (range * m_params.FibLevelHigh);
                   if(currentPrice >= f618 - tolerance && currentPrice <= f786 + tolerance) score += 1.0;
               }
           }
       }

       // 4. RSI level - 1.0 point
       if(direction == 1 && m_g_RSI <= m_params.RSI_Oversold) score += 1.0;
       if(direction == -1 && m_g_RSI >= m_params.RSI_Overbought) score += 1.0;

       // 5. RSI momentum - 0.5 point
       if(m_params.RSI_Momentum)
       {
           if(direction == 1 && m_g_RSI > m_g_RSI_Prev) score += 0.5;
           if(direction == -1 && m_g_RSI < m_g_RSI_Prev) score += 0.5;
       }

       // 6. Displacement - 1.0 point
       if(CheckDisplacement(direction)) score += 1.0;

       // ============ SMC FACTORS (0-6 additional) ============

       if(m_params.UseSMC)
       {
           // 7. HTF Trend Alignment (MTF) - up to 2.0 points
           if(m_params.UseMTF)
               score += m_mtfAnalysis.GetConfluenceScore(direction);

           // 8. Structure Break (BOS aligned) - up to 1.0 point
           score += m_smcStructure.GetConfluenceScore(direction);

           // 9. Order Block Entry - up to 1.5 points
           score += m_smcOrderBlocks.GetConfluenceScore(direction);

           // 10. Fair Value Gap - up to 1.0 point
           score += m_smcFVG.GetConfluenceScore(direction);

           // 11. Liquidity Sweep - up to 1.5 points
           score += m_smcLiquidity.GetConfluenceScore(direction);
       }

       // 12. Killzone Timing Bonus - up to 0.5 points
       if(m_params.UseKillzoneFilter)
           score += m_killzoneOptimizer.GetConfluenceScore();

       return score;  // Max possible: ~12 points
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
           Print("🚫 REVERSAL FILTER: ", m_symbol, " ", (direction == 1 ? "BUY" : "SELL"),
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
               Print("⏸️ COOLDOWN: ", m_symbol, " ", (direction == 1 ? "BUY" : "SELL"),
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
           Print("⚠️ Lots capped: ", DoubleToString(lots, 3), " → ", DoubleToString(m_params.MaxLotsPerTrade, 2));
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

           // Quality adjustments
           if(quality == TIER_ELITE) tpR *= 1.2;
           else if(quality == TIER_STRONG) tpR *= 1.1;
           else if(quality == TIER_WEAK) tpR *= 0.8;

           // Regime adjustments
           if(m_currentRegime == REGIME_TREND) tpR *= 1.3;
           else if(m_currentRegime == REGIME_RANGE) tpR *= 0.85;
           else if(m_currentRegime == REGIME_VOLATILE) tpR *= 1.1;
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
           Print("⚠️ TP TOO CLOSE TO ENTRY! Setting to 2R | Price: ", price, " | BadTP: ", finalTp);
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

       // Adaptive SL based on quality
       double slDist = m_g_ATR * 1.2;  // Default
       if(quality == TIER_ELITE) slDist = m_g_ATR * 2.2;
       else if(quality == TIER_STRONG) slDist = m_g_ATR * 1.8;

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

           // Update cooldown tracking (CRITICAL FOR OVERTRADING PROTECTION)
           if(type == ORDER_TYPE_BUY)
               m_lastBuyTime = TimeCurrent();
           else
               m_lastSellTime = TimeCurrent();

           // Log trade
           Print("===========================================");
           Print("✅ TRADE OPENED: ", m_symbol);
           Print("  Ticket: #", ticket);
           Print("  Type: ", EnumToString(type));
           Print("  Price: ", DoubleToString(price, (int)m_symbolInfo.Digits()));
           Print("  SL: ", DoubleToString(sl, (int)m_symbolInfo.Digits()), " (", DoubleToString(slDist / m_symbolInfo.Point(), 0), " pips)");
           if(tp > 0)
               Print("  TP: ", DoubleToString(tp, (int)m_symbolInfo.Digits()), " (", DoubleToString(MathAbs(tp - price) / slDist, 2), "R)");
           Print("  Lots: ", DoubleToString(lots, 2));
           Print("  Risk: ", DoubleToString(riskPct, 2), "%");
           Print("  Quality: ", EnumToString(quality));
           Print("  Confluence: ", DoubleToString(m_currentConfluence, 1), "/12");
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
                       Print("📉 LOSS: ", m_symbol, " | ", DoubleToString(profitR, 2), "R | Streak: ", m_consecutiveLosses);
                   }
                   else
                   {
                       if(m_consecutiveLosses > 0)
                           Print("✅ WIN breaks losing streak of ", m_consecutiveLosses);
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
                       Print("💰 PARTIAL TP: ", m_symbol, " | ", closeVol, " lots @ ", DoubleToString(profitR, 2), "R");
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
                       Print("🔒 BREAK-EVEN: ", m_symbol, " @ ", DoubleToString(profitR, 2), "R");
               }
           }

           // 3. Trailing Stop
           if(profitR >= trailStart)
           {
               double mult = m_params.TrailATR_Mult;
               if(quality == TIER_WEAK) mult *= 0.7;
               if(quality == TIER_ELITE) mult *= 1.5;

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
