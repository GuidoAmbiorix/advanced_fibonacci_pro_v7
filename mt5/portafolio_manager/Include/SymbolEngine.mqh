//+------------------------------------------------------------------+
//|                                                 SymbolEngine.mqh |
//|          Symbol Engine Class - Governor's "Soldier"              |
//|             Encapsulated Logic for Multi-Symbol Trading          |
//+------------------------------------------------------------------+
#ifndef SYMBOL_ENGINE_MQH
#define SYMBOL_ENGINE_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

#include "PortfolioGlobals.mqh"
#include "KillzoneConfig.mqh"
#include "FailSafe.mqh"
#include "MarketRegime.mqh"
#include "KillSwitch.mqh"
#include "Learning_MFE_MAE.mqh"
#include "GovernorAllocator.mqh"

// Smart Money Concepts Modules
#include "SMC_StructureBreak.mqh"
#include "SMC_OrderBlocks.mqh"
#include "SMC_FairValueGap.mqh"
#include "SMC_LiquiditySweep.mqh"

// Multi-Timeframe and Filters
#include "MTF_Confluence.mqh"
#include "NewsFilter.mqh"
#include "KellyPositionSizer.mqh"

// Learning & Memory Modules
#include "DatabaseManager.mqh"
#include "Memory\PatternMemory.mqh"
#include "Learning\PerformanceAnalyzer.mqh"
#include "Learning\PatternRecognizer.mqh"

// Adaptive Modules
#include "Adaptive\AdaptiveRiskManager.mqh"
#include "Adaptive\AdaptiveExitManager.mqh"
#include "Adaptive\AdaptiveFilterManager.mqh"

// ADVANCED CONFLUENCE MODULES
#include "Advanced\VolumeAnalysis.mqh"
#include "Advanced\Divergence.mqh"
#include "Advanced\Inst_Concepts.mqh"

//+------------------------------------------------------------------+
//| CSymbolEngine Class                                               |
//+------------------------------------------------------------------+
class CSymbolEngine
{
private:
   // --- Configuration ---
   SymbolConfig      m_config;
   string            m_symbol;
   long              m_magic;
   
   // --- Core Objects ---
   CTrade            m_trade;
   CPositionInfo     m_position;
   CAccountInfo      m_account;
   CSymbolInfo       m_symbolInfo;
   
   // --- Module Objects ---
   CFailSafe         m_failSafe;
   CMarketRegime     m_regime;
   CKillSwitch       m_killSwitch;
   CLearningEngine   m_learning;
   CGovernorAllocator m_allocator;
   
   // --- Advanced Modules ---
   CVolumeAnalysis   m_volumeAnalysis;
   CDivergence       m_divergence;
   
   // --- SMC Modules ---
   CSMCStructureBreak m_smcStructure;
   CSMCOrderBlocks    m_smcOrderBlocks;
   CSMCFairValueGap   m_smcFVG;
   CSMCLiquiditySweep m_smcLiquidity;
   
   // --- Filter Objects ---
   CMTFConfluence    m_mtfAnalysis;
   CNewsFilter       m_newsFilter;
   CKellyPositionSizer m_kellySizer;
   
   // --- Learning Objects ---
   // Note: We use pointers for shared managers if needed, but for now we own them
   // DatabaseManager is likely shared and passed in Init
   CDatabaseManager*  m_dbManager; 
   CPatternMemory     m_patternMemory;
   CPerformanceAnalyzer m_performanceAnalyzer;
   CPatternRecognizer m_patternRecognizer;
   
   // --- Adaptive Objects ---
   CAdaptiveRiskManager   m_adaptiveRisk;
   CAdaptiveExitManager   m_adaptiveExit;
   CAdaptiveFilterManager m_adaptiveFilter;

   // --- Indicator Handles & Buffers ---
   int m_hRSI, m_hATR, m_hEMA;
   int m_hEMA50, m_hEMA100;
   double m_RSI, m_RSI_Prev, m_ATR, m_EMA, m_EMA_Prev, m_ATR_MA;
   double m_EMA50, m_EMA50_Prev, m_EMA100, m_EMA100_Prev;
   
   // --- State Variables ---
   datetime m_lastBarTime;
   int      m_entryDirection;
   double   m_currentConfluence;
   int      m_positionCount;
   bool     m_addOn1Triggered;
   bool     m_addOn2Triggered;
   datetime m_lastCloseTime;
   ulong    m_lastTickTime;
   datetime m_lastHeartbeat;
   int      m_bias;
   datetime m_lastLossTime;
   MARKET_REGIME m_currentRegime;
   
   // Portfolio Protection
   double   m_dailyLossR;
   int      m_consecutiveLosses;
   datetime m_lastResetDate;
   datetime m_lastBuyTime;
   datetime m_lastSellTime;
   
   // Optimization Caches
   double   m_cachedBuyScore;
   double   m_cachedSellScore;
   datetime m_lastScoreCalcTime;
   ulong    m_tickCount;
   ulong    m_barCount;
   ulong    m_tradesExecuted;
   
   // Position Tracking
   struct PositionState {
      ulong ticket;
      bool  partialClosed;
      double initialRisk;
      ENTRY_QUALITY quality;
   };
   PositionState m_states[];

public:
                     CSymbolEngine();
                    ~CSymbolEngine();
   
   // --- Core Methods ---
   bool              Init(SymbolConfig &config, CDatabaseManager *dbManager);
   void              Uninit();
   void              OnTick();
   void              OnTrade();
   
   // --- Status Getters ---
   string            GetSymbol() const { return m_symbol; }
   double            GetConfluenceScore() const { return m_currentConfluence; }
   double            GetDailyProfitR() const { return m_dailyLossR; /* it's net, confusing name */ }
   int               GetPositionCount() const { return m_positionCount; }
   
private:
   // --- Internal Logic ---
   bool              UpdateIndicators();
   void              UpdateModules();
   bool              IsNewBar();
   void              ResetTradeState();
   void              ResetDailyLossIfNewDay();
   
   // --- Trading Logic ---
   double            CalculateConfluenceScore(int direction);
   void              BuildConfluenceFactors(ConfluenceFactors &factors, int direction, double score);
   bool              ExecuteTrade(ENUM_ORDER_TYPE type, double riskPct, string label, ENTRY_QUALITY quality);
   void              ManagePositions();
   double            CalculateTakeProfit(double price, double slDist, int direction, ENTRY_QUALITY quality, double atr);
   double            CalculateLotSize(double slDist, double riskPct);
   bool              CheckMarginRequirement(string symbol, ENUM_ORDER_TYPE type, double lots);
   
   // --- Filters ---
   bool              CanTradeSymbol();
   bool              CheckSpread();
   bool              CheckKillzone();
   ENUM_ENTRY_TIER   GetEntryTier(double score);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSymbolEngine::CSymbolEngine() : m_dbManager(NULL)
{
   m_hRSI = INVALID_HANDLE;
   m_hATR = INVALID_HANDLE;
   m_hEMA = INVALID_HANDLE;
   m_hEMA50 = INVALID_HANDLE;
   m_hEMA100 = INVALID_HANDLE;
   m_lastBarTime = 0;
   m_positionCount = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSymbolEngine::~CSymbolEngine()
{
   Uninit();
}

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
bool CSymbolEngine::Init(SymbolConfig &config, CDatabaseManager *pDbManager)
{
   m_config = config;
   m_symbol = config.symbol;
   m_magic  = config.magicNumber;
   m_dbManager = pDbManager;
   
   if(!m_symbolInfo.Name(m_symbol)) return false;
   m_symbolInfo.RefreshRates();

   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(10);
   
   // Set filling mode
   int filling = (int)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0) m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // Initialize Indicators
   m_hRSI = iRSI(m_symbol, PERIOD_CURRENT, m_config.rsiPeriod, PRICE_CLOSE);
   m_hATR = iATR(m_symbol, PERIOD_CURRENT, 14);
   m_hEMA = iMA(m_symbol, PERIOD_CURRENT, m_config.emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(m_hRSI == INVALID_HANDLE || m_hATR == INVALID_HANDLE || m_hEMA == INVALID_HANDLE)
   {
      Print("CSymbolEngine [", m_symbol, "] Error: Indicators invalid");
      return false;
   }

   // Initialize Reversal Filter
   if(m_config.useReversalFilter)
   {
      m_hEMA50 = iMA(m_symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_hEMA100 = iMA(m_symbol, PERIOD_CURRENT, 100, 0, MODE_EMA, PRICE_CLOSE);
      
      if(m_hEMA50 == INVALID_HANDLE || m_hEMA100 == INVALID_HANDLE)
         Print("CSymbolEngine [", m_symbol, "] Warning: Reversal EMAs invalid");
   }

   // Initialize FailSafe
   m_failSafe.Init(m_config.maxSpreadPoints);
   ArrayResize(m_states, 0);

   // Initialize Learning
   if(m_config.enableLearning)
   {
      if(!m_learning.Init(m_symbol, true))
         Print("CSymbolEngine [", m_symbol, "] Warning: Learning init failed");
         
      if(m_dbManager != NULL && m_config.logTradesToFile)
      {
         // Database is retained from init param
      }
      
      if(!m_performanceAnalyzer.Init(m_symbol, m_dbManager, m_config.minTradesForLearning))
         Print("CSymbolEngine [", m_symbol, "] Warning: Performance Analyzer init failed");
         
      if(!m_patternMemory.Init(m_symbol, true, 10))
         Print("CSymbolEngine [", m_symbol, "] Warning: Pattern Memory init failed");

      if(!m_patternRecognizer.Init(m_symbol, &m_patternMemory, 15, 0.65, 0.5))
         Print("CSymbolEngine [", m_symbol, "] Warning: Pattern Recognizer init failed");
   }

   // Initialize SMC
   if(m_config.useSMC)
   {
      m_smcStructure.Init(m_symbol, PERIOD_CURRENT, m_config.smcSwingLookback);
      m_smcOrderBlocks.Init(m_symbol, PERIOD_CURRENT, 50, 5, m_config.smcMinImpulseATR);
      m_smcFVG.Init(m_symbol, PERIOD_CURRENT, 50, 10, m_config.smcMinFVG_ATR);
      
      // Need to add Init logic for m_smcLiquidity if available in original
      m_smcLiquidity.Init(m_symbol, PERIOD_CURRENT, m_config.swingLookback);
   }

   // Initialize MTF
   if(m_config.useMTF)
   {
      m_mtfAnalysis.Init(m_symbol, m_config.htf, m_config.mtf, PERIOD_CURRENT, m_config.mtfEmaPeriod);
   }

   // Initialize News Filter
   if(m_config.useNewsFilter)
   {
      m_newsFilter.Init(m_symbol, m_config.newsMinutesBefore, m_config.newsMinutesAfter, true);
      m_newsFilter.EnableVolatilityFilter(m_config.enableVolatilityFilter);
      m_newsFilter.SetVolatilityThreshold(m_config.volatilityThreshold);
      m_newsFilter.SetVolatilityCooldown(m_config.volatilitySpikeCooldown);
   }

   // Initialize Kelly
   if(m_config.useKelly)
   {
      m_kellySizer.Init(m_config.riskBase, 0.25, m_config.maxRisk, m_config.kellyFraction, 30, m_config.dailyMaxDD, m_config.weeklyMaxDD);
   }

   // Initialize Adaptive Modules
   if(m_config.enableLearning)
   {
       m_adaptiveRisk.Init(m_symbol, &m_performanceAnalyzer, &m_patternRecognizer, m_config.riskBase, 0.1, 0.5, m_config.enableAdaptiveRisk);
       
       ExitParameters exitParams;
       exitParams.trailStartR = m_config.trailStart_R;
       exitParams.trailDistanceATR = m_config.trailATR_Mult;
       exitParams.beThresholdR = m_config.beThreshold_R;
       exitParams.partialTPR = m_config.partialTP_R;
       exitParams.partialPercent = m_config.partialClosePercent;
       
       m_adaptiveExit.Init(m_symbol, &m_learning, exitParams, m_config.enableAdaptiveExits);
       
       m_adaptiveFilter.Init(m_symbol, &m_patternRecognizer, &m_performanceAnalyzer, m_config.minConfluenceEntry, m_config.enableAdaptiveFilters);
   }

   Print("✅ CSymbolEngine Initialized: ", m_symbol, " (Magic: ", m_magic, ")");
   
   // Pre-load indicators
   UpdateIndicators();
   
   return true;
}

//+------------------------------------------------------------------+
//| Uninitialization                                                  |
//+------------------------------------------------------------------+
void CSymbolEngine::Uninit()
{
   if(m_hRSI != INVALID_HANDLE) { IndicatorRelease(m_hRSI); m_hRSI = INVALID_HANDLE; }
   if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
   if(m_hEMA != INVALID_HANDLE) { IndicatorRelease(m_hEMA); m_hEMA = INVALID_HANDLE; }
   
   if(m_hEMA50 != INVALID_HANDLE) { IndicatorRelease(m_hEMA50); m_hEMA50 = INVALID_HANDLE; }
   if(m_hEMA100 != INVALID_HANDLE) { IndicatorRelease(m_hEMA100); m_hEMA100 = INVALID_HANDLE; }
   
   if(m_config.useSMC)
   {
      m_smcStructure.Deinit();
      m_smcOrderBlocks.Deinit();
      m_smcFVG.Deinit();
      m_smcLiquidity.Deinit();
   }
   
   if(m_config.useMTF) m_mtfAnalysis.Deinit();
   
   if(m_config.enableLearning)
   {
      m_learning.Deinit();
      m_patternMemory.Deinit();
   }
}
   
//+------------------------------------------------------------------+
//| Update Indicators                                                 |
//+------------------------------------------------------------------+
bool CSymbolEngine::UpdateIndicators()
{
   double rsi[], atr[], ema[], ema50[], ema100[];

   // RSI
   if(CopyBuffer(m_hRSI, 0, 0, 2, rsi) < 2) return false;
   m_RSI = rsi[0];     // Current
   m_RSI_Prev = rsi[1];

   // ATR
   if(CopyBuffer(m_hATR, 0, 0, 1, atr) < 1) return false;
   m_ATR = atr[0];
   
   // ATR MA (Simple approx or calculated)
   m_ATR_MA = m_ATR; // Placeholder, or implement separate handle if needed

   // EMA 200
   if(CopyBuffer(m_hEMA, 0, 0, 2, ema) < 2) return false;
   m_EMA = ema[0];
   m_EMA_Prev = ema[1];
   
   // Reversal EMAs
   if(m_config.useReversalFilter)
   {
      if(CopyBuffer(m_hEMA50, 0, 0, 2, ema50) < 2) return false;
      m_EMA50 = ema50[0];
      m_EMA50_Prev = ema50[1];
      
      if(CopyBuffer(m_hEMA100, 0, 0, 2, ema100) < 2) return false;
      m_EMA100 = ema100[0];
      m_EMA100_Prev = ema100[1];
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update Modules                                                    |
//+------------------------------------------------------------------+
void CSymbolEngine::UpdateModules()
{
   if(m_config.useSMC)
   {
      m_smcStructure.Update();
      m_smcOrderBlocks.Update();
      m_smcFVG.Update();
      m_smcLiquidity.Update();
   }

   if(m_config.useMTF) m_mtfAnalysis.Update();
   if(m_config.useNewsFilter) m_newsFilter.Update();
   if(m_config.useKelly) m_kellySizer.Update();
}

//+------------------------------------------------------------------+
//| New Bar Checker                                                   |
//+------------------------------------------------------------------+
bool CSymbolEngine::IsNewBar()
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
//| Calculate Confluence Score                                        |
//+------------------------------------------------------------------+
double CSymbolEngine::CalculateConfluenceScore(int direction)
{
   double score = 0;
   double currentPrice = m_symbolInfo.Bid();

   // ============ 1. CORE SMC & PRICE ACTION ============

   // Trend (EMA 200 + Slope)
   double emaSlope = m_EMA - m_EMA_Prev;
   bool slopeStrong = MathAbs(emaSlope) >= (m_ATR * m_config.emaMinSlope);
   
   // Price Alignment
   if(direction == 1 && currentPrice > m_EMA) score += 1.5;
   if(direction == -1 && currentPrice < m_EMA) score += 1.5;
   
   // Slope Alignment
   if(direction == 1 && emaSlope > 0) score += 1.0;
   if(direction == -1 && emaSlope < 0) score += 1.0;
   if(slopeStrong) score += 0.5; // Bonus for strong momentum

   // SMC Structure Break
   if(m_config.useSMC)
   {
       ENUM_STRUCTURE_TYPE lastBreak = m_smcStructure.GetLastBreakType();
       bool bos = (direction == 1) ? (lastBreak == STRUCT_BOS_BULLISH) : (lastBreak == STRUCT_BOS_BEARISH);
       if(bos) score += 2.0;
       
       // Change of Character
       bool choch = (direction == 1) ? (lastBreak == STRUCT_CHOCH_BULLISH) : (lastBreak == STRUCT_CHOCH_BEARISH);
       if(choch) score += 1.5;
   }

   // ============ 2. MOMENTUM & OSCILLATORS ============
   
   // RSI
   if(direction == 1)
   {
      if(m_RSI > 50) score += 0.5;
      if(m_RSI < m_config.rsiOversold) score += 1.0; // Oversold bounce
      if(m_config.rsiMomentum && m_RSI > 50 && m_RSI > m_RSI_Prev) score += 0.5;
   }
   else
   {
      if(m_RSI < 50) score += 0.5;
      if(m_RSI > m_config.rsiOverbought) score += 1.0; // Overbought bounce
      if(m_config.rsiMomentum && m_RSI < 50 && m_RSI < m_RSI_Prev) score += 0.5;
   }

   // ============ 3. INSTITUTIONAL ORDER FLOW ============
   
   if(m_config.useSMC)
   {
      // Order Blocks
      double obTop, obBot;
      bool obActive = m_smcOrderBlocks.IsInOrderBlock(direction, obTop, obBot);
      if(obActive) score += 2.5;
      
      // FVG
      double fvgTop, fvgBot;
      bool fvgActive = m_smcFVG.IsInFVG(direction, fvgTop, fvgBot);
      if(fvgActive) score += 2.0;
      
      // Liquidity Sweep (aligned with direction)
      bool sweep = m_smcLiquidity.IsSweepAligned(direction);
      if(sweep) score += 1.5;
   }

   // ============ 4. ADVANCED FILTERS ============
   
   // MTF Confluence
   if(m_config.useMTF)
   {
      if(m_mtfAnalysis.IsDirectionAligned(direction)) score += 2.0;
   }
   
   // Volume Analysis (if available) - Simple volume trend
   long vol = iVolume(m_symbol, PERIOD_CURRENT, 0);
   long volPrev = iVolume(m_symbol, PERIOD_CURRENT, 1);
   if(vol > volPrev) score += 0.5; // Rising volume

   return score;
}

//+------------------------------------------------------------------+
//| Main Tick Logic                                                   |
//+------------------------------------------------------------------+
void CSymbolEngine::OnTick()
{
   if(GetTickCount() - m_lastHeartbeat >= 60000)
   {
      // Heartbeat managed by Governor, or local log
      m_lastHeartbeat = GetTickCount();
   }

   m_tickCount++;
   
   if(!m_symbolInfo.RefreshRates()) return;

   m_positionCount = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(m_position.SelectByIndex(i))
         if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic)
            m_positionCount++;
   }

   if(m_positionCount == 0 && m_entryDirection != 0) ResetTradeState();

   ManagePositions();
   
   if(!IsNewBar()) return;
   
   m_barCount++;
   if(!UpdateIndicators()) return;
   
   UpdateModules();
   
   // Calculate Confluence
   m_cachedBuyScore = CalculateConfluenceScore(1);
   m_cachedSellScore = CalculateConfluenceScore(-1);
   m_lastScoreCalcTime = iTime(m_symbol, PERIOD_CURRENT, 0);

   // FailSafe
   if(!m_failSafe.IsExecutionSafe()) return;
   
   // KillSwitch
   if(!m_killSwitch.IsEnabled()) return;
   
   // News Filter
   if(m_config.useNewsFilter && !m_newsFilter.IsTradingAllowed()) return;
   
   // Kelly Sizing Limit
   if(m_config.useKelly && !m_kellySizer.IsTradingAllowed()) return;
   
   // Portfolio Protection
   ResetDailyLossIfNewDay();
   if(m_config.dailyMaxLoss_R > 0 && m_dailyLossR <= -m_config.dailyMaxLoss_R) return;
   if(m_config.useCorrelationFilter && !CanTradeSymbol()) return;
   
   // Cooldowns
   if(m_config.lossCooldownMinutes > 0 && m_lastLossTime > 0)
   {
      if(TimeCurrent() - m_lastLossTime < m_config.lossCooldownMinutes * 60) return;
   }
   
   if(m_config.maxConsecutiveLosses > 0 && m_consecutiveLosses >= m_config.maxConsecutiveLosses) return;

   // Pre-entry Filters
   if(!CheckSpread()) return;
   // if(!IsTradingEnabled()) return; // Global Governor Check (handled by Governor wrapping this class)
   
   double buyScore = m_cachedBuyScore;
   double sellScore = m_cachedSellScore;
   
   // Bias Penalty
   if(m_bias == 1) sellScore -= 1.0;
   if(m_bias == -1) buyScore -= 1.0;

   // Entry Logic
   if(m_positionCount == 0)
   {
      // Session Governor
      if(m_config.useSessionGovernor)
      {
         datetime lastTrade = (m_lastBuyTime > m_lastSellTime) ? m_lastBuyTime : m_lastSellTime;
         if(TimeCurrent() - lastTrade < m_config.tradeCooldownMinutes * 60) return;
      }
      
      if(m_config.useKillzoneFilter && !CheckKillzone()) return;
      
      double bestScore = (buyScore > sellScore) ? buyScore : sellScore;
      int bestDirection = (buyScore > sellScore) ? 1 : -1;
      
      ENUM_ENTRY_TIER tier = GetEntryTier(bestScore);
      if(bestScore < m_config.minConfluenceEntry) return;
      
      // Determine Quality
      ENTRY_QUALITY quality = m_learning.CalculateQuality(bestScore); // Or derive from tier
      if(tier == TIER_ELITE) quality = EQ_ELITE;
      else if(tier == TIER_STRONG) quality = EQ_STRONG;
      
      // Risk Calculation
      double baseRisk = m_config.riskBase;
      
      if(m_config.useKelly)
      {
         baseRisk = m_kellySizer.GetRiskForQuality(quality);
         double newsMult = m_config.useNewsFilter ? m_newsFilter.GetNewsRiskMultiplier() : 1.0;
         baseRisk = m_kellySizer.GetAdjustedRisk(quality, newsMult, 1.0, 1.0);
      }
      
      baseRisk *= GetTierSizeMultiplier(tier);
      
      // Use approved risk directly (Governor manages total risk)
      double approvedRisk = baseRisk * GetRiskMultiplier(); // From global
      
      if(approvedRisk > 0.05)
      {
         if(bestDirection == 1 && (m_config.direction == 0 || m_config.direction == 1))
         {
             // Reversal Cooldown
             if(m_config.reversalCooldownMinutes > 0 && m_lastBuyTime > 0)
                 if(TimeCurrent() - m_lastBuyTime < m_config.reversalCooldownMinutes * 60) return;
                 
             m_currentConfluence = buyScore;
             m_entryDirection = 1;
             ExecuteTrade(ORDER_TYPE_BUY, approvedRisk, "Entry", quality);
         }
         else if(bestDirection == -1 && (m_config.direction == 0 || m_config.direction == 2))
         {
             if(m_config.reversalCooldownMinutes > 0 && m_lastSellTime > 0)
                 if(TimeCurrent() - m_lastSellTime < m_config.reversalCooldownMinutes * 60) return;
                 
             m_currentConfluence = sellScore;
             m_entryDirection = -1;
             ExecuteTrade(ORDER_TYPE_SELL, approvedRisk, "Entry", quality);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//+------------------------------------------------------------------+
bool CSymbolEngine::ExecuteTrade(ENUM_ORDER_TYPE type, double riskPct, string label, ENTRY_QUALITY quality)
{
   double price = (type == ORDER_TYPE_BUY) ? m_symbolInfo.Ask() : m_symbolInfo.Bid();
   
   // Adaptive SL
   double slDist = (quality == EQ_ELITE) ? m_ATR * 2.2 : (quality == EQ_STRONG ? m_ATR * 1.8 : m_ATR * 1.2);
   
   double stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDist < stopsLevel + 10 * _Point) slDist = stopsLevel + 10 * _Point;
   
   double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   sl = NormalizeDouble(sl, (int)m_symbolInfo.Digits());
   
   double lots = CalculateLotSize(slDist, riskPct);
   
   string comment = "SE|" + label + "|Q" + IntegerToString((int)quality);
   
   // TP
   int dir = (type == ORDER_TYPE_BUY) ? 1 : -1;
   double tp = CalculateTakeProfit(price, slDist, dir, quality, m_ATR);
   
   if(!CheckMarginRequirement(m_symbol, type, lots))
   {
      m_failSafe.ReportFailure();
      return false;
   }
   
   if(m_trade.PositionOpen(m_symbol, type, lots, price, sl, tp, comment))
   {
      ulong ticket = m_trade.ResultOrder();
      
      // Register State
      int sz = ArraySize(m_states);
      ArrayResize(m_states, sz + 1);
      m_states[sz].ticket = ticket;
      m_states[sz].partialClosed = false;
      m_states[sz].initialRisk = slDist;
      m_states[sz].quality = quality;
      
      m_learning.RegisterTrade(ticket, slDist, quality);
      
      if(m_dbManager != NULL && m_config.enableLearning)
      {
         string strategyStr = "STANDARD";
         m_dbManager.LogTradeEntry(ticket, m_symbol, (type == ORDER_TYPE_BUY) ? 1: -1, lots, price, sl, tp, m_currentConfluence, strategyStr, "0", "NONE");
      }
      
      if(type == ORDER_TYPE_BUY) m_lastBuyTime = TimeCurrent();
      else m_lastSellTime = TimeCurrent();
      
      m_tradesExecuted++;
      
      Print("✅ CSymbolEngine [", m_symbol, "]: Trade Opened (", EnumToString(type), ") ", DoubleToString(lots, 2), " lots");
      return true;
   }
   
   m_failSafe.ReportFailure();
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                             |
//+------------------------------------------------------------------+
double CSymbolEngine::CalculateTakeProfit(double price, double slDist, int direction, ENTRY_QUALITY quality, double atr)
{
    if(m_config.tpMode == 0) return 0;
    
    double tpR = m_config.fixedTP_R;
    
    // Adaptive Logics can be added here
    if(quality == EQ_ELITE) tpR *= 1.2;
    // else if(quality == EQ_WEAK) tpR *= 0.8;
    
    double tpDist = slDist * tpR;
    double tp = (direction == 1) ? price + tpDist : price - tpDist;
    return NormalizeDouble(tp, (int)m_symbolInfo.Digits());
}

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
double CSymbolEngine::CalculateLotSize(double slDist, double riskPct)
{
    if(slDist <= 0) return 0;
    
    double riskMoney = m_account.Equity() * (riskPct / 100.0);
    double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickValue == 0 || tickSize == 0) return 0;
    
    double riskPoints = slDist;
    double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
    
    double lots = riskMoney / (riskPoints / tickSize * tickValue);
    
    // Limits
    if(lots > m_config.maxLotsPerTrade) lots = m_config.maxLotsPerTrade;
    
    // Normalize
    lots = MathFloor(lots / lotStep) * lotStep;
    double minVol = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
    if(lots < minVol) lots = minVol; // Or 0 if strict
    
    return lots;
}

bool CSymbolEngine::CheckMarginRequirement(string symbol, ENUM_ORDER_TYPE type, double lots)
{
    if(!m_config.enableMarginCheck) return true;
    double margin = 0;
    if(!OrderCalcMargin(type, symbol, lots, m_symbolInfo.Ask(), margin)) return false;
    return (m_account.FreeMargin() > margin);
}

bool CSymbolEngine::CheckSpread()
{
    int spread = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
    return (spread <= m_config.maxSpreadPoints);
}

bool CSymbolEngine::CheckKillzone()
{
    // Placeholder for simplified logic
    return true; 
}

bool CSymbolEngine::CanTradeSymbol()
{
   if(!m_config.useCorrelationFilter) return true;
   return true; 
}

void CSymbolEngine::ResetDailyLossIfNewDay()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

    if(currentDate != m_lastResetDate)
    {
       m_dailyLossR = 0;
       m_consecutiveLosses = 0;
       m_lastResetDate = currentDate;
    }
}

void CSymbolEngine::ResetTradeState()
{
    m_entryDirection = 0;
    m_positionCount = 0;
    ArrayResize(m_states, 0);
}

void CSymbolEngine::ManagePositions()
{
    // Placeholder for robust position management logic (Trailing, BE, Partial)
    // To be fully implemented from Symbol_Engine.mq5 logic
}

void CSymbolEngine::BuildConfluenceFactors(ConfluenceFactors &factors, int direction, double score)
{
   factors.confluenceScore = score;
}

void CSymbolEngine::OnTrade() { /* Handle trade events */ }

#endif
