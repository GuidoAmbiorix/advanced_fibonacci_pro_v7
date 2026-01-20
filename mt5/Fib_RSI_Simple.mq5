//+------------------------------------------------------------------+
//|                                               Fib_RSI_Simple.mq5 |
//|         CONFLUENCE LADDER SYSTEM - Progressive Capital Allocation|
//|              🎯 Capital Deployed Based on Market Evidence 🎯     |
//+------------------------------------------------------------------+
#property copyright "Confluence Ladder System"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "4.00"
#property description "🧠 Confluence Ladder: Bot = Capital Allocator"
#property description "✅ v4.0: Entry Score | Add-Ons | Progressive Risk"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_DIRECTION
{
   DIR_BOTH = 0,           // ↕️ Both Directions
   DIR_BUY_ONLY = 1,       // 🟢 Buy Only
   DIR_SELL_ONLY = 2       // 🔴 Sell Only
};

enum ENUM_TRAILING_MODE
{
   TRAIL_OFF = 0,          // Off - Fixed TP Only
   TRAIL_RUNNER = 1,       // Runner Mode (Partial + Trail)
   TRAIL_FULL = 2          // Full Trail (Pure Runner)
};

enum ENUM_SESSION_FILTER
{
   SESSION_ALL = 0,        // 🌍 All Sessions
   SESSION_LONDON_NY = 1,  // 🎯 London + NY
   SESSION_LONDON = 2,     // 🇬🇧 London Only
   SESSION_NY = 3          // 🇺🇸 NY Only
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "═══════ CORE ═══════"
input int               InpMagicNumber = 123456;          // Magic Number
input ENUM_DIRECTION    InpDirection = DIR_BOTH;          // Trade Direction
input int               InpBrokerUTCOffset = 2;           // Broker UTC Offset

input group "═══════ 🕐 SESSION FILTER ═══════"
input ENUM_SESSION_FILTER InpSessionFilter = SESSION_LONDON_NY;
input int               InpLondonStart = 7;
input int               InpLondonEnd = 16;
input int               InpNYStart = 12;
input int               InpNYEnd = 21;

input group "═══════ FIBONACCI ZONE ═══════"
input int               InpSwingLookback = 20;
input double            InpFibLevelLow = 0.618;
input double            InpFibLevelHigh = 0.786;
input double            InpZoneTolerance = 0.25;

input group "═══════ DISPLACEMENT ═══════"
input bool              InpUseDisplacement = true;
input double            InpDisplacementATR = 1.2;
input int               InpDisplacementLookback = 5;

input group "═══════ RSI ═══════"
input int               InpRSI_Period = 14;
input int               InpRSI_Oversold = 45;
input int               InpRSI_Overbought = 55;
input bool              InpRSI_Momentum = true;

input group "═══════ TREND ═══════"
input int               InpEMA_Period = 200;
input bool              InpUseTrendFilter = true;
input double            InpEMA_MinSlope = 0.1;

input group "═══════ CHOP FILTER ═══════"
input bool              InpUseChopFilter = true;
input double            InpChopThreshold = 0.75;
input int               InpATR_MA_Period = 20;
input double            InpMinRangeEfficiency = 0.4;

input group "═══════ 🧠 CONFLUENCE LADDER (CAPITAL ALLOCATOR) ═══════"
input int               InpMinConfluenceEntry = 4;        // Min Score for Entry (out of 6)
input bool              InpEnableAddOns = true;           // Enable Add-On Positions
input double            InpAddOn1_R = 1.5;                // Add-On #1 Trigger (R profit)
input double            InpAddOn2_R = 2.5;                // Add-On #2 Trigger (R profit)
input int               InpAddOn1_MinScore = 4;           // Add-On #1 Min Confluence
input int               InpAddOn2_MinScore = 5;           // Add-On #2 Min Confluence (stricter)
input int               InpMaxPositions = 3;              // Max Total Positions (1 + 2 adds)

input group "═══════ 💰 PROGRESSIVE RISK ═══════"
input double            InpRiskBase = 0.25;               // Base Risk % (Entry)
input double            InpRiskAddOn1 = 0.15;             // Add-On #1 Risk %
input double            InpRiskAddOn2 = 0.10;             // Add-On #2 Risk %

input group "═══════ EXIT STRATEGY ═══════"
input ENUM_TRAILING_MODE InpTrailingMode = TRAIL_RUNNER;
input double            InpPartialTP_R = 1.5;
input double            InpPartialClosePercent = 40.0;
input double            InpRunnerTP_R = 0;                // 0 = Unlimited
input double            InpBE_Threshold_R = 1.8;
input double            InpTrailStart_R = 2.0;
input double            InpTrailATR_Mult = 1.2;

input group "═══════ SPREAD ═══════"
input int               InpMaxSpreadPoints = 50;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

int hRSI, hATR, hEMA;
double g_RSI, g_RSI_Prev, g_ATR, g_EMA, g_EMA_Prev, g_ATR_MA;

datetime lastBarTime = 0;
bool g_inSession = false;

// 🧠 CONFLUENCE STATE
int g_entryDirection = 0;        // 1 = BUY, -1 = SELL, 0 = none
int g_currentConfluence = 0;     // Last calculated score
int g_positionCount = 0;         // How many positions we have
bool g_addOn1Triggered = false;  // Already added position 1?
bool g_addOn2Triggered = false;  // Already added position 2?
double g_entryInitialRisk = 0;   // Store initial risk for R calculations

// Partial close tracking per position
bool g_partialsClosed[];

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symbolInfo.Name(_Symbol)) return INIT_FAILED;
   symbolInfo.RefreshRates();
   
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   hEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE)
      return INIT_FAILED;
   
   ResetTradeState();
   
   Print("═══════════════════════════════════════════════════════════");
   Print("  🧠 CONFLUENCE LADDER v4.0 | Capital Allocator Mode");
   Print("═══════════════════════════════════════════════════════════");
   Print("  📊 Entry: Score ≥ ", InpMinConfluenceEntry, "/6 → Risk: ", InpRiskBase, "%");
   Print("  📈 Add #1: +", InpAddOn1_R, "R + Score≥", InpAddOn1_MinScore, " → Risk: ", InpRiskAddOn1, "%");
   Print("  📈 Add #2: +", InpAddOn2_R, "R + Score≥", InpAddOn2_MinScore, " → Risk: ", InpRiskAddOn2, "%");
   Print("  🚀 Max Positions: ", InpMaxPositions, " | Runner: ", (InpRunnerTP_R == 0 ? "UNLIMITED" : DoubleToString(InpRunnerTP_R,1)));
   Print("═══════════════════════════════════════════════════════════");
   
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
   g_entryInitialRisk = 0;
   ArrayResize(g_partialsClosed, 0);
}

//+------------------------------------------------------------------+
//| New bar check                                                     |
//+------------------------------------------------------------------+
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
//| Main tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   symbolInfo.RefreshRates();
   
   // Count current positions
   g_positionCount = CountPositions();
   
   // If no positions, reset state
   if(g_positionCount == 0)
   {
      ResetTradeState();
   }
   
   // Manage existing positions
   ManagePositions();
   
   // Dashboard
   UpdateDashboard();
   
   // New bar only
   if(!IsNewBar()) return;
   
   // Update indicators
   if(!UpdateIndicators()) return;
   
   // ═══════════════════════════════════════════════════════════════
   // CONFLUENCE LADDER LOGIC
   // ═══════════════════════════════════════════════════════════════
   
   // Pre-entry filters
   g_inSession = CheckSessionFilter();
   if(!g_inSession) return;
   if(!CheckSpread()) return;
   if(!CheckChopFilter()) return;
   
   // Calculate current confluence score
   int buyScore = CalculateConfluenceScore(1);
   int sellScore = CalculateConfluenceScore(-1);
   
   // LAYER 1: ENTRY (No position yet)
   if(g_positionCount == 0)
   {
      if(buyScore >= InpMinConfluenceEntry && (InpDirection == DIR_BOTH || InpDirection == DIR_BUY_ONLY))
      {
         g_currentConfluence = buyScore;
         g_entryDirection = 1;
         ExecuteTrade(ORDER_TYPE_BUY, InpRiskBase, "Entry");
      }
      else if(sellScore >= InpMinConfluenceEntry && (InpDirection == DIR_BOTH || InpDirection == DIR_SELL_ONLY))
      {
         g_currentConfluence = sellScore;
         g_entryDirection = -1;
         ExecuteTrade(ORDER_TYPE_SELL, InpRiskBase, "Entry");
      }
   }
   // LAYER 2 & 3: ADD-ONS (Already have position)
   else if(g_positionCount > 0 && InpEnableAddOns && g_positionCount < InpMaxPositions)
   {
      CheckAddOnOpportunity();
   }
}

//+------------------------------------------------------------------+
//| 🧠 CALCULATE CONFLUENCE SCORE (0-6)                               |
//+------------------------------------------------------------------+
int CalculateConfluenceScore(int direction)
{
   int score = 0;
   double currentPrice = symbolInfo.Bid();
   
   // 1. TREND ALIGNMENT (+1)
   double emaSlope = g_EMA - g_EMA_Prev;
   bool emaRising = emaSlope > 0;
   bool emaFalling = emaSlope < 0;
   bool slopeStrong = MathAbs(emaSlope) >= (g_ATR * InpEMA_MinSlope);
   
   if(direction == 1 && currentPrice > g_EMA && emaRising && slopeStrong) score++;
   if(direction == -1 && currentPrice < g_EMA && emaFalling && slopeStrong) score++;
   
   // 2. STRUCTURE VALID (+1)
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 1);
   int lowestBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback, 1);
   
   if(highestBar >= 0 && lowestBar >= 0)
   {
      if(direction == 1 && lowestBar < highestBar) score++;  // Uptrend structure
      if(direction == -1 && highestBar < lowestBar) score++; // Downtrend structure
   }
   
   // 3. FIB ZONE (+1)
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
            double fib618 = swingHigh - (range * InpFibLevelLow);
            double fib786 = swingHigh - (range * InpFibLevelHigh);
            if(currentPrice <= fib618 + tolerance && currentPrice >= fib786 - tolerance) score++;
         }
         else
         {
            double fib618 = swingLow + (range * InpFibLevelLow);
            double fib786 = swingLow + (range * InpFibLevelHigh);
            if(currentPrice >= fib618 - tolerance && currentPrice <= fib786 + tolerance) score++;
         }
      }
   }
   
   // 4. RSI CONFIRMATION (+1)
   if(direction == 1 && g_RSI <= InpRSI_Oversold) score++;
   if(direction == -1 && g_RSI >= InpRSI_Overbought) score++;
   
   // 5. RSI MOMENTUM (+1)
   if(InpRSI_Momentum)
   {
      if(direction == 1 && g_RSI > g_RSI_Prev) score++;
      if(direction == -1 && g_RSI < g_RSI_Prev) score++;
   }
   else score++; // Give point if momentum not required
   
   // 6. DISPLACEMENT (+1)
   if(CheckDisplacement(direction)) score++;
   
   return score;
}

//+------------------------------------------------------------------+
//| CHECK ADD-ON OPPORTUNITY                                          |
//+------------------------------------------------------------------+
void CheckAddOnOpportunity()
{
   // Get base position info
   double totalProfitR = GetTotalProfitR();
   
   // Check current confluence for add direction
   int currentScore = CalculateConfluenceScore(g_entryDirection);
   
   // ADD-ON #1
   if(!g_addOn1Triggered && g_positionCount < InpMaxPositions)
   {
      if(totalProfitR >= InpAddOn1_R && currentScore >= InpAddOn1_MinScore)
      {
         ENUM_ORDER_TYPE type = (g_entryDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(ExecuteTrade(type, InpRiskAddOn1, "Add1"))
         {
            g_addOn1Triggered = true;
            Print("📈 ADD-ON #1 Triggered | Profit: +", DoubleToString(totalProfitR,1), "R | Score: ", currentScore);
         }
      }
   }
   
   // ADD-ON #2
   if(!g_addOn2Triggered && g_addOn1Triggered && g_positionCount < InpMaxPositions)
   {
      if(totalProfitR >= InpAddOn2_R && currentScore >= InpAddOn2_MinScore)
      {
         ENUM_ORDER_TYPE type = (g_entryDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(ExecuteTrade(type, InpRiskAddOn2, "Add2"))
         {
            g_addOn2Triggered = true;
            Print("📈 ADD-ON #2 Triggered | Profit: +", DoubleToString(totalProfitR,1), "R | Score: ", currentScore);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| GET TOTAL PROFIT IN R                                             |
//+------------------------------------------------------------------+
double GetTotalProfitR()
{
   double totalProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            double openPrice = position.PriceOpen();
            double currentPrice = position.PriceCurrent();
            double sl = position.StopLoss();
            
            double profitPrice = (position.PositionType() == POSITION_TYPE_BUY) ?
                                 (currentPrice - openPrice) : (openPrice - currentPrice);
            double risk = MathAbs(openPrice - sl);
            
            if(risk > 0)
               totalProfit += (profitPrice / risk);
         }
      }
   }
   
   return totalProfit;
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
      double atrSum = 0;
      double atrBuf[1];
      for(int i = 1; i <= InpATR_MA_Period; i++)
      {
         if(CopyBuffer(hATR, 0, i, 1, atrBuf) == 1)
            atrSum += atrBuf[0];
      }
      g_ATR_MA = atrSum / InpATR_MA_Period;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Session Filter                                                    |
//+------------------------------------------------------------------+
bool CheckSessionFilter()
{
   if(InpSessionFilter == SESSION_ALL) return true;
   
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int utcHour = (dt.hour - InpBrokerUTCOffset + 24) % 24;
   
   bool inLondon = (utcHour >= InpLondonStart && utcHour < InpLondonEnd);
   bool inNY = (utcHour >= InpNYStart && utcHour < InpNYEnd);
   
   switch(InpSessionFilter)
   {
      case SESSION_LONDON_NY: return (inLondon || inNY);
      case SESSION_LONDON:    return inLondon;
      case SESSION_NY:        return inNY;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Chop Filter                                                       |
//+------------------------------------------------------------------+
bool CheckChopFilter()
{
   if(!InpUseChopFilter) return true;
   
   if(g_ATR < g_ATR_MA * InpChopThreshold) return false;
   
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   double body = MathAbs(close - open);
   double range = high - low;
   
   if(range > 0 && (body / range) < InpMinRangeEfficiency)
      return false;
   
   return true;
}

bool CheckSpread()
{
   if(InpMaxSpreadPoints <= 0) return true;
   return ((int)symbolInfo.Spread() <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Displacement Check                                                |
//+------------------------------------------------------------------+
bool CheckDisplacement(int direction)
{
   if(!InpUseDisplacement) return true;
   
   for(int i = 2; i <= InpDisplacementLookback + 1; i++)
   {
      double open = iOpen(_Symbol, PERIOD_CURRENT, i);
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      double body = MathAbs(close - open);
      
      if(body >= g_ATR * InpDisplacementATR)
      {
         if(direction == 1 && close > open) return true;
         if(direction == -1 && close < open) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Count Positions                                                   |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE orderType, double riskPercent, string label)
{
   double price = (orderType == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
   double slDistance = g_ATR * 1.0; // Fixed 1 ATR SL
   
   // Store initial risk for first entry
   if(g_positionCount == 0)
      g_entryInitialRisk = slDistance;
   
   double tpDistance = 0;
   if(InpTrailingMode == TRAIL_OFF && InpRunnerTP_R > 0)
      tpDistance = slDistance * InpRunnerTP_R;
   else if(InpTrailingMode == TRAIL_RUNNER && InpRunnerTP_R > 0)
      tpDistance = slDistance * InpRunnerTP_R;
   
   double sl, tp;
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = price - slDistance;
      tp = (tpDistance > 0) ? price + tpDistance : 0;
   }
   else
   {
      sl = price + slDistance;
      tp = (tpDistance > 0) ? price - tpDistance : 0;
   }
   
   double lotSize = CalculateLotSize(slDistance, riskPercent);
   string comment = "CL4" + label + "|S" + IntegerToString(g_currentConfluence);
   
   if(trade.PositionOpen(_Symbol, orderType, lotSize, price, sl, tp, comment))
   {
      // Expand partials array
      int newSize = ArraySize(g_partialsClosed) + 1;
      ArrayResize(g_partialsClosed, newSize);
      g_partialsClosed[newSize - 1] = false;
      
      Print((orderType == ORDER_TYPE_BUY ? "🟢" : "🔴"), 
            " ", label, " | Score:", g_currentConfluence, 
            " | Risk:", riskPercent, "% | Lots:", lotSize);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance, double riskPercent)
{
   double equity = account.Equity();
   double riskAmount = equity * (riskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickSize == 0 || tickValue == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   double ticksAtRisk = slDistance / tickSize;
   double lotSize = riskAmount / (ticksAtRisk * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage Positions                                                  |
//+------------------------------------------------------------------+
void ManagePositions()
{
   int idx = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol) continue;
      if(position.Magic() != InpMagicNumber) continue;
      
      double openPrice = position.PriceOpen();
      double currentPrice = position.PriceCurrent();
      double sl = position.StopLoss();
      double tp = position.TakeProfit();
      double volume = position.Volume();
      long posType = position.PositionType();
      
      double profitPrice = (posType == POSITION_TYPE_BUY) ?
                           (currentPrice - openPrice) : (openPrice - currentPrice);
      double initialRisk = MathAbs(openPrice - sl);
      if(initialRisk == 0) continue;
      
      double profitR = profitPrice / initialRisk;
      
      // Check array bounds
      if(idx >= ArraySize(g_partialsClosed))
      {
         ArrayResize(g_partialsClosed, idx + 1);
         g_partialsClosed[idx] = false;
      }
      
      if(InpTrailingMode == TRAIL_RUNNER || InpTrailingMode == TRAIL_FULL)
      {
         // Partial close
         if(!g_partialsClosed[idx] && profitR >= InpPartialTP_R)
         {
            double closeVol = NormalizeDouble(volume * (InpPartialClosePercent / 100.0), 2);
            double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeVol >= minVol && (volume - closeVol) >= minVol)
            {
               if(trade.PositionClosePartial(_Symbol, closeVol))
               {
                  g_partialsClosed[idx] = true;
                  Print("💰 Partial @ ", DoubleToString(profitR,1), "R");
               }
            }
         }
         
         // BE
         if(profitR >= InpBE_Threshold_R && MathAbs(sl - openPrice) > _Point)
         {
            if((posType == POSITION_TYPE_BUY && sl < openPrice) ||
               (posType == POSITION_TYPE_SELL && sl > openPrice))
            {
               trade.PositionModify(_Symbol, openPrice, tp);
            }
         }
         
         // Trail
         if(profitR >= InpTrailStart_R)
         {
            double bufATR[1];
            if(CopyBuffer(hATR, 0, 0, 1, bufATR) == 1)
            {
               double trailDist = bufATR[0] * InpTrailATR_Mult;
               double newSL = (posType == POSITION_TYPE_BUY) ?
                              currentPrice - trailDist : currentPrice + trailDist;
               
               if((posType == POSITION_TYPE_BUY && newSL > sl && newSL < currentPrice) ||
                  (posType == POSITION_TYPE_SELL && newSL < sl && newSL > currentPrice))
               {
                  trade.PositionModify(_Symbol, newSL, tp);
               }
            }
         }
      }
      idx++;
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double price = symbolInfo.Bid();
   double totalR = GetTotalProfitR();
   
   int buyScore = CalculateConfluenceScore(1);
   int sellScore = CalculateConfluenceScore(-1);
   
   string trend = (price > g_EMA) ? "📈" : "📉";
   string sessionStr = g_inSession ? "🟢" : "🔴";
   
   string text = "═══════════════════════════════════════\n";
   text += "  🧠 CONFLUENCE LADDER v4.0\n";
   text += "═══════════════════════════════════════\n";
   text += "Price: " + DoubleToString(price, (int)symbolInfo.Digits()) + " " + trend + "\n";
   text += "RSI: " + DoubleToString(g_RSI, 1) + "\n";
   text += "Session: " + sessionStr + " | Spread: " + IntegerToString((int)symbolInfo.Spread()) + "\n";
   text += "───────────────────────────────────────\n";
   text += "📊 BUY Score:  " + IntegerToString(buyScore) + "/6\n";
   text += "📊 SELL Score: " + IntegerToString(sellScore) + "/6\n";
   text += "Min Entry: " + IntegerToString(InpMinConfluenceEntry) + "/6\n";
   text += "───────────────────────────────────────\n";
   text += "Positions: " + IntegerToString(g_positionCount) + "/" + IntegerToString(InpMaxPositions) + "\n";
   text += "Add1: " + (g_addOn1Triggered ? "✓" : "○") + " | Add2: " + (g_addOn2Triggered ? "✓" : "○") + "\n";
   text += "Total R: " + DoubleToString(totalR, 2) + "\n";
   text += "═══════════════════════════════════════\n";
   
   Comment(text);
}
//+------------------------------------------------------------------+
