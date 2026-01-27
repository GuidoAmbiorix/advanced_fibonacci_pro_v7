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
   double m_g_RSI, m_g_RSI_Prev, m_g_ATR, m_g_EMA, m_g_EMA_Prev, m_g_ATR_MA;
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
   
   // Optimization Cache
   double   m_cachedBuyScore;
   double   m_cachedSellScore;
   datetime m_lastScoreCalcTime;
   
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
      p.FocusPrimeOnly = true;

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

      // CONFLUENCE
      p.MinConfluenceEntry = 6; // Strict
      p.MaxPositions = 1;
      
      // RISK
      p.RiskBase = 1.0;
      p.MaxRisk = 2.0;
      p.MaxLotsPerTrade = 50.0;
      p.EnableMarginCheck = true;

      // TAKE PROFIT
      p.TPMode = 3; // Hybrid
      p.FixedTP_R = 3.0;
      p.MinTP_R = 1.0;
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
      p.SMC_MinImpulseATR = 2.0;
      p.SMC_MinFVG_ATR = 0.5;

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
      m_lastBarTime = 0;
      m_currentRegime = REGIME_UNKNOWN;
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
      
      // Initialize Indicators
      m_hRSI = iRSI(m_symbol, PERIOD_CURRENT, m_params.RSI_Period, PRICE_CLOSE);
      m_hATR = iATR(m_symbol, PERIOD_CURRENT, 14);
      m_hEMA = iMA(m_symbol, PERIOD_CURRENT, m_params.EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      
      if(m_hRSI == INVALID_HANDLE || m_hATR == INVALID_HANDLE || m_hEMA == INVALID_HANDLE)
      {
         Print("Engine Init Failed: Indicators");
         return false;
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
      
      // Clean up other modules if they have Deinit...
      // (Assuming they handle their own cleanup or are stack instances which is fine)
   }
   
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
      
      // Safety Checks
      if(!m_failSafe.IsExecutionSafe()) return;
      if(m_params.UseNewsFilter && !m_newsFilter.IsTradingAllowed()) return;
      
      // Regime
      m_currentRegime = m_regime.Detect(m_g_ATR, m_g_ATR_MA, m_g_EMA, m_g_EMA_Prev);
      if(m_currentRegime == REGIME_CHAOS) return;
      
      // Filters
      if(!CheckSpread()) return;
      
      // Signal Scan
      ScanForEntry();
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
      double rsi[], atr[], ema[], emaPrev[];
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(ema, true);
      ArraySetAsSeries(emaPrev, true);
      
      if(CopyBuffer(m_hRSI, 0, 0, 2, rsi) < 2) return false;
      if(CopyBuffer(m_hATR, 0, 0, 14, atr) < 14) return false; // Need history for MA check
      if(CopyBuffer(m_hEMA, 0, 0, 2, ema) < 2) return false;
      
      m_g_RSI = rsi[0];
      m_g_RSI_Prev = rsi[1];
      m_g_ATR = atr[0];
      m_g_EMA = ema[0];
      m_g_EMA_Prev = ema[1];
      
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
       // Re-implementation of the Entry Logic
       // Calculate Buy/Sell Scores using Confluence Logic (simplified here for brevity, assuming standard logic)
       
       // Calculate Scores
       double buyScore = CalculateConfluenceScore(1);
       double sellScore = CalculateConfluenceScore(-1);
       
       double bestScore = MathMax(buyScore, sellScore);
       int    direction = (buyScore > sellScore) ? 1 : -1;
       
       if(bestScore < 6.0) return; // Strict threshold
       
       // Governor Check
       GovernorRequest req;
       req.symbol = m_symbol;
       req.baseRisk = m_params.RiskBase;
       req.winRate = 0.5; // Default or from Learning
       req.rollingR = 1.0;
       req.regime = (int)m_currentRegime;
       
       double approvedRisk = m_allocator.RequestRisk(req);
       
       if(approvedRisk > 0.0)
       {
          ExecuteTrade(direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, approvedRisk, "Eng_Entry", TIER_STRONG);
       }
   }
   
   double CalculateConfluenceScore(int direction)
   {
       // Basic Placeholder for the complex logic
       double score = 0;
       if(direction == 1 && m_g_RSI < 70 && m_g_EMA < m_symbolInfo.Bid()) score += 3.0;
       if(direction == -1 && m_g_RSI > 30 && m_g_EMA > m_symbolInfo.Bid()) score += 3.0;
       
       // SMC Additions
       if(m_params.UseSMC)
       {
           // Add logic here
           score += 2.0; 
       }
       return score;
   }
   
   void ExecuteTrade(ENUM_ORDER_TYPE type, double riskPct, string label, ENUM_ENTRY_TIER quality)
   {
       double price = (type == ORDER_TYPE_BUY) ? m_symbolInfo.Ask() : m_symbolInfo.Bid();
       double slDist = m_g_ATR * 1.5;
       double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
       double tp = (type == ORDER_TYPE_BUY) ? price + (slDist * 2.0) : price - (slDist * 2.0);
       
       // Lot Calculation logic...
       double lot = 0.01; // Placeholder
       
       m_trade.PositionOpen(m_symbol, type, lot, price, sl, tp, label);
   }
   
   void ManagePositions()
   {
       // Trailing Logic Loop
       for(int i=PositionsTotal()-1; i>=0; i--)
       {
          if(m_position.SelectByIndex(i))
          {
             if(m_position.Symbol() == m_symbol && m_position.Magic() == m_params.MagicNumber)
             {
                 // Apply Adaptive Exit Logic or Basic Trailing
             }
          }
       }
   }
};

#endif
