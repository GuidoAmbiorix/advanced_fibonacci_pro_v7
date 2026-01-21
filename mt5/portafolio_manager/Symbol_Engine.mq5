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

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "======= IDENTITY ======="
input int               InpMagicNumber = 100001;          // Magic Number (unique per symbol)

input group "======= DIRECTION ======="
input int               InpDirection = 0;                 // 0=Both, 1=Buy, 2=Sell
input int               InpBrokerUTCOffset = 2;

input group "======= SESSION ======="
input int               InpSessionFilter = 1;             // 0=All, 1=London+NY
input int               InpLondonStart = 7;
input int               InpLondonEnd = 16;
input int               InpNYStart = 12;
input int               InpNYEnd = 21;

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

input group "======= EXIT ======="
input int               InpTrailingMode = 1;              // 0=Off, 1=Runner, 2=Full
input double            InpPartialTP_R = 1.5;
input double            InpPartialClosePercent = 40.0;
input double            InpBE_Threshold_R = 1.8;
input double            InpTrailStart_R = 2.0;
input double            InpTrailATR_Mult = 1.2;

input group "======= SPREAD ======="
input int               InpMaxSpreadPoints = 50;

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

int hRSI, hATR, hEMA;
double g_RSI, g_RSI_Prev, g_ATR, g_EMA, g_EMA_Prev, g_ATR_MA;

datetime lastBarTime = 0;
bool g_inSession = false;

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

   // Check if Governor is running
   string govStatus = allocator.IsGovernorActive() ? "Connected" : "Standalone";

   Print("===========================================");
   Print("  SYMBOL ENGINE: ", _Symbol);
   Print("  Magic: ", InpMagicNumber);
   Print("  Governor: ", govStatus);
   Print("===========================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
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

   // --- MODULE: FAIL SAFE ---
   if(!failSafe.IsExecutionSafe()) return;

   // --- MODULE: KILL SWITCH ---
   if(!killSwitch.IsEnabled()) return;

   // --- MODULE: MARKET REGIME ---
   g_currentRegime = regime.Detect(g_ATR, g_ATR_MA, g_EMA, g_EMA_Prev);
   if(g_currentRegime == REGIME_CHAOS) return;

   // PRE-ENTRY FILTERS
   g_inSession = CheckSessionFilter();
   if(!g_inSession) return;
   if(!CheckSpread()) return;

   // 1. RSI Compression Filter
   if(g_RSI > 48 && g_RSI < 52) return;

   // 2. EMA Proximity Filter
   if(MathAbs(symbolInfo.Bid() - g_EMA) < g_ATR * 0.35) return;

   // Check Governor Trading Permission
   if(!IsTradingEnabled()) return;

   // Calculate confluence
   double buyScore = CalculateConfluenceScore(1);
   double sellScore = CalculateConfluenceScore(-1);

   // Bias Penalty
   if(g_bias == 1) sellScore -= 1.0;
   if(g_bias == -1) buyScore -= 1.0;

   // ENTRY
   if(g_positionCount == 0)
   {
      double bestScore = (buyScore > sellScore) ? buyScore : sellScore;

      // Calculate Quality using Learning Module Logic
      ENTRY_QUALITY quality = learning.CalculateQuality(bestScore);
      if(quality == EQ_WEAK) return;

      // GOVERNOR REQUEST
      GovernorRequest req = allocator.BuildRequest(
          _Symbol,
          InpRiskBase,
          killSwitch.GetWinRate(),
          killSwitch.GetRollingR(),
          (int)g_currentRegime
      );

      double approvedRisk = allocator.RequestRisk(req);

      if(approvedRisk > 0.05)
      {
          if(buyScore >= InpMinConfluenceEntry && (InpDirection == 0 || InpDirection == 1))
          {
             g_currentConfluence = buyScore;
             g_entryDirection = 1;
             ExecuteTrade(ORDER_TYPE_BUY, approvedRisk, "Entry", quality);
          }
          else if(sellScore >= InpMinConfluenceEntry && (InpDirection == 0 || InpDirection == 2))
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

   if(trade.PositionOpen(_Symbol, type, lots, price, sl, 0, comment))
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

      Print("Opened ", EnumToString(type), " Ticket:", ticket, " Quality:", EnumToString(quality));
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

      // --- REGIME-AWARE PARAMETERS ---
      double partTP = InpPartialTP_R;
      double trailStart = InpTrailStart_R;

      if(g_currentRegime == REGIME_TREND) {
          partTP *= 1.2;
          trailStart *= 1.2;
      } else if(g_currentRegime == REGIME_RANGE) {
          partTP *= 0.8;
          trailStart *= 0.8;
      }

      if(quality == EQ_WEAK) { partTP *= 0.8; trailStart *= 0.7; }
      if(quality == EQ_ELITE) { partTP *= 1.5; trailStart *= 1.5; }

      if(InpTrailingMode >= 1)
      {
         // 1. Partial TP
         if(!g_states[sIdx].partialClosed && profitR >= partTP)
         {
            double closeVol = NormalizeDouble(vol * (InpPartialClosePercent / 100.0), 2);
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

         // 2. Adaptive Break-Even
         double learnedBE = learning.GetLearnedBE(risk);
         double beTrigger = (learnedBE > 0) ? learnedBE : InpBE_Threshold_R;

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
   // Handle Closed Trades for KillSwitch logic
   HistorySelect(TimeCurrent() - 60, TimeCurrent());
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
       ulong ticket = HistoryDealGetTicket(i);
       if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
       {
           double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
           double rOutcome = (profit > 0) ? 1.0 : -1.0;
           killSwitch.OnTradeClosed(rOutcome);
           learning.OnTradeClosed(ticket);
       }
   }
}

//+------------------------------------------------------------------+
//| Check Add-On Opportunity                                          |
//+------------------------------------------------------------------+
void CheckAddOnOpportunity()
{
   double totalR = GetTotalProfitR();
   int currentScore = CalculateConfluenceScore(g_entryDirection);

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
//| Confluence Score (0-6)                                            |
//+------------------------------------------------------------------+
int CalculateConfluenceScore(int direction)
{
   int score = 0;
   double currentPrice = symbolInfo.Bid();

   // 1. Trend
   double emaSlope = g_EMA - g_EMA_Prev;
   bool slopeStrong = MathAbs(emaSlope) >= (g_ATR * InpEMA_MinSlope);
   if(direction == 1 && currentPrice > g_EMA && emaSlope > 0 && slopeStrong) score++;
   if(direction == -1 && currentPrice < g_EMA && emaSlope < 0 && slopeStrong) score++;

   // 2. Structure
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 1);
   int lowestBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback, 1);
   if(direction == 1 && lowestBar < highestBar) score++;
   if(direction == -1 && highestBar < lowestBar) score++;

   // 3. Fib Zone
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
            if(currentPrice <= f618 + tolerance && currentPrice >= f786 - tolerance) score++;
         }
         else
         {
            double f618 = swingLow + (range * InpFibLevelLow);
            double f786 = swingLow + (range * InpFibLevelHigh);
            if(currentPrice >= f618 - tolerance && currentPrice <= f786 + tolerance) score++;
         }
      }
   }

   // 4. RSI level
   if(direction == 1 && g_RSI <= InpRSI_Oversold) score++;
   if(direction == -1 && g_RSI >= InpRSI_Overbought) score++;

   // 5. RSI momentum
   if(InpRSI_Momentum)
   {
      if(direction == 1 && g_RSI > g_RSI_Prev) score++;
      if(direction == -1 && g_RSI < g_RSI_Prev) score++;
   }
   else score++;

   // 6. Displacement
   if(CheckDisplacement(direction)) score++;

   return score;
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

bool CheckSessionFilter()
{
   if(InpSessionFilter == 0) return true;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int utc = (dt.hour - InpBrokerUTCOffset + 24) % 24;
   return ((utc >= InpLondonStart && utc < InpLondonEnd) || (utc >= InpNYStart && utc < InpNYEnd));
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

   lots = MathFloor(lots / step + 0.000001) * step;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double price = symbolInfo.Bid();
   double totalR = GetTotalProfitR();
   int buyS = CalculateConfluenceScore(1);
   int sellS = CalculateConfluenceScore(-1);

   string govStatus = allocator.IsGovernorActive() ? "Connected " + DoubleToString(GetRiskMultiplier()*100,0) + "%" : "Standalone";
   string tradingStatus = IsTradingEnabled() ? "ACTIVE" : "BLOCKED";

   string txt = "===========================================\n";
   txt += "  SYMBOL ENGINE: " + _Symbol + "\n";
   txt += "===========================================\n";
   txt += "Governor: " + govStatus + "\n";
   txt += "Trading: " + tradingStatus + "\n";
   txt += "-------------------------------------------\n";
   txt += "Price: " + DoubleToString(price, (int)symbolInfo.Digits()) + "\n";
   txt += "RSI: " + DoubleToString(g_RSI, 1) + "\n";
   txt += "Session: " + (g_inSession ? "Active" : "Inactive") + "\n";
   txt += "-------------------------------------------\n";
   txt += "BUY Score: " + IntegerToString(buyS) + "/6\n";
   txt += "SELL Score: " + IntegerToString(sellS) + "/6\n";
   txt += "Min: " + IntegerToString(InpMinConfluenceEntry) + "/6\n";
   txt += "-------------------------------------------\n";
   txt += "Positions: " + IntegerToString(g_positionCount) + "/" + IntegerToString(InpMaxPositions) + "\n";
   txt += "Total R: " + DoubleToString(totalR, 2) + "\n";
   txt += "===========================================\n";

   Comment(txt);
}
//+------------------------------------------------------------------+
