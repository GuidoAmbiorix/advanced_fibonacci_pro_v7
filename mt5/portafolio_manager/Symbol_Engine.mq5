//+------------------------------------------------------------------+
//|                                            Symbol_Engine.mq5     |
//|          🎯 Symbol Engine - Requests Permission from Governor    |
//|             Confluence Ladder + Portfolio Integration            |
//+------------------------------------------------------------------+
#property copyright "Symbol Engine - Portfolio Aware"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property description "🎯 Symbol Engine: Asks Governor for Permission"
#property description "Use different Magic Numbers per symbol (Base + 1, 2, etc.)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include "Include\PortfolioGlobals.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "═══════ IDENTITY ═══════"
input int               InpMagicNumber = 100001;          // Magic Number (unique per symbol)

input group "═══════ DIRECTION ═══════"
input int               InpDirection = 0;                 // 0=Both, 1=Buy, 2=Sell
input int               InpBrokerUTCOffset = 2;

input group "═══════ SESSION ═══════"
input int               InpSessionFilter = 1;             // 0=All, 1=London+NY
input int               InpLondonStart = 7;
input int               InpLondonEnd = 16;
input int               InpNYStart = 12;
input int               InpNYEnd = 21;

input group "═══════ FIBONACCI ═══════"
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

input group "═══════ 🧠 CONFLUENCE ═══════"
input int               InpMinConfluenceEntry = 4;
input bool              InpEnableAddOns = true;
input double            InpAddOn1_R = 1.5;
input double            InpAddOn2_R = 2.5;
input int               InpMaxPositions = 3;

input group "═══════ 💰 RISK (Before Governor Scaling) ═══════"
input double            InpRiskBase = 0.25;
input double            InpRiskAddOn1 = 0.15;
input double            InpRiskAddOn2 = 0.10;

input group "═══════ EXIT ═══════"
input int               InpTrailingMode = 1;              // 0=Off, 1=Runner, 2=Full
input double            InpPartialTP_R = 1.5;
input double            InpPartialClosePercent = 40.0;
input double            InpBE_Threshold_R = 1.8;
input double            InpTrailStart_R = 2.0;
input double            InpTrailATR_Mult = 1.2;

input group "═══════ SPREAD ═══════"
input int               InpMaxSpreadPoints = 50;

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;
CSymbolInfo    symbolInfo;

int hRSI, hATR, hEMA;
double g_RSI, g_RSI_Prev, g_ATR, g_EMA, g_EMA_Prev, g_ATR_MA;

datetime lastBarTime = 0;
bool g_inSession = false;

int g_entryDirection = 0;
int g_currentConfluence = 0;
int g_positionCount = 0;
bool g_addOn1Triggered = false;
bool g_addOn2Triggered = false;
bool g_partialsClosed[];

//+------------------------------------------------------------------+
//| Init                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symbolInfo.Name(_Symbol)) return INIT_FAILED;
   symbolInfo.RefreshRates();
   
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   // Use more robust filling mode detection
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);
   
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   hEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE)
      return INIT_FAILED;
   
   ArrayResize(g_partialsClosed, 0);
   
   // Check if Governor is running
   string govStatus = IsGovernorActive() ? "🟢 Connected" : "🟡 Standalone";
   
   Print("═══════════════════════════════════════════");
   Print("  🎯 SYMBOL ENGINE: ", _Symbol);
   Print("  Magic: ", InpMagicNumber);
   Print("  Governor: ", govStatus);
   Print("═══════════════════════════════════════════");
   
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
   ArrayResize(g_partialsClosed, 0);
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
   
   // PRE-ENTRY FILTERS
   g_inSession = CheckSessionFilter();
   if(!g_inSession) return;
   if(!CheckSpread()) return;
   if(!CheckChopFilter()) return;
   
   // 🧠 CHECK GOVERNOR PERMISSION
   if(!IsTradingEnabled())
   {
      // Governor says no trading
      return;
   }
   
   // Calculate confluence
   int buyScore = CalculateConfluenceScore(1);
   int sellScore = CalculateConfluenceScore(-1);
   
   // ENTRY
   if(g_positionCount == 0)
   {
      if(buyScore >= InpMinConfluenceEntry && (InpDirection == 0 || InpDirection == 1))
      {
         double approvedRisk = RequestRiskFromGovernor(InpRiskBase);
         if(approvedRisk > 0.05)
         {
            g_currentConfluence = buyScore;
            g_entryDirection = 1;
            ExecuteTrade(ORDER_TYPE_BUY, approvedRisk, "Entry");
         }
      }
      else if(sellScore >= InpMinConfluenceEntry && (InpDirection == 0 || InpDirection == 2))
      {
         double approvedRisk = RequestRiskFromGovernor(InpRiskBase);
         if(approvedRisk > 0.05)
         {
            g_currentConfluence = sellScore;
            g_entryDirection = -1;
            ExecuteTrade(ORDER_TYPE_SELL, approvedRisk, "Entry");
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
//| 🧠 REQUEST RISK FROM GOVERNOR                                     |
//+------------------------------------------------------------------+
double RequestRiskFromGovernor(double requestedRisk)
{
   if(!IsGovernorActive())
   {
      // No governor - use requested risk directly
      return requestedRisk;
   }
   
   // Get risk multiplier from governor
   double mult = GetRiskMultiplier();
   double scaledRisk = requestedRisk * mult;
   
   // Check total exposure
   double totalExposure = GetTotalExposure();
   double maxPortfolio = 2.0; // Default max
   
   if(totalExposure + scaledRisk > maxPortfolio)
   {
      scaledRisk = MathMax(0, maxPortfolio - totalExposure);
   }
   
   return scaledRisk;
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
         double approvedRisk = RequestRiskFromGovernor(InpRiskAddOn1);
         if(approvedRisk > 0.05)
         {
            ENUM_ORDER_TYPE type = (g_entryDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            if(ExecuteTrade(type, approvedRisk, "Add1"))
            {
               g_addOn1Triggered = true;
               Print("📈 ADD #1 | R:", DoubleToString(totalR,1), " | Risk:", approvedRisk);
            }
         }
      }
   }
   
   if(!g_addOn2Triggered && g_addOn1Triggered && g_positionCount < InpMaxPositions)
   {
      if(totalR >= InpAddOn2_R && currentScore >= InpMinConfluenceEntry + 1)
      {
         double approvedRisk = RequestRiskFromGovernor(InpRiskAddOn2);
         if(approvedRisk > 0.05)
         {
            ENUM_ORDER_TYPE type = (g_entryDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            if(ExecuteTrade(type, approvedRisk, "Add2"))
            {
               g_addOn2Triggered = true;
               Print("📈 ADD #2 | R:", DoubleToString(totalR,1), " | Risk:", approvedRisk);
            }
         }
      }
   }
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

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE type, double riskPct, string label)
{
   double price = (type == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
   double slDist = g_ATR * 1.5; // Increased multiplier for safety
   
   // Ensure SL respects STOPS_LEVEL
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDist < stopsLevel + 10 * _Point) slDist = stopsLevel + 10 * _Point;
   
   double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   sl = NormalizeDouble(sl, (int)symbolInfo.Digits());
   double tp = 0; // Unlimited
   
   double lots = CalculateLotSize(slDist, riskPct);
   string comment = "SE|" + label + "|S" + IntegerToString(g_currentConfluence);
   
   PrintFormat("🚀 Trade Attempt: %s %.2f @ %.5f SL: %.5f (Risk: %.2f%%)", 
               EnumToString(type), lots, price, sl, riskPct);
   
   if(trade.PositionOpen(_Symbol, type, lots, price, sl, tp, comment))
   {
      int sz = ArraySize(g_partialsClosed);
      ArrayResize(g_partialsClosed, sz + 1);
      g_partialsClosed[sz] = false;
      Print((type == ORDER_TYPE_BUY ? "🟢 SUCCESS: Buy Opened" : "🔴 SUCCESS: Sell Opened"));
      return true;
   }
   
   PrintFormat("❌ Trade FAILED: %d - %s", trade.ResultRetcode(), trade.ResultComment());
   return false;
}

double CalculateLotSize(double slDist, double riskPct)
{
   double equity = account.Equity();
   if(equity <= 0) equity = account.Balance();
   
   double riskAmt = equity * (riskPct / 100.0);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Safety Check: Avoid Division by Zero or invalid data
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
//| Manage Positions                                                  |
//+------------------------------------------------------------------+
void ManagePositions()
{
   int idx = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol || position.Magic() != InpMagicNumber) continue;
      
      double open = position.PriceOpen();
      double curr = position.PriceCurrent();
      double sl = position.StopLoss();
      double tp = position.TakeProfit();
      double vol = position.Volume();
      long pType = position.PositionType();
      
      double profit = (pType == POSITION_TYPE_BUY) ? (curr - open) : (open - curr);
      double risk = MathAbs(open - sl);
      if(risk == 0) continue;
      double profitR = profit / risk;
      
      if(idx >= ArraySize(g_partialsClosed))
      {
         ArrayResize(g_partialsClosed, idx + 1);
         g_partialsClosed[idx] = false;
      }
      
      if(InpTrailingMode >= 1)
      {
         // Partial
         if(!g_partialsClosed[idx] && profitR >= InpPartialTP_R)
         {
            double closeVol = NormalizeDouble(vol * (InpPartialClosePercent / 100.0), 2);
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeVol >= minV && (vol - closeVol) >= minV)
            {
               if(trade.PositionClosePartial(_Symbol, closeVol))
                  g_partialsClosed[idx] = true;
            }
         }
         
         // BE
         if(profitR >= InpBE_Threshold_R && MathAbs(sl - open) > _Point)
         {
            if((pType == POSITION_TYPE_BUY && sl < open) || (pType == POSITION_TYPE_SELL && sl > open))
               trade.PositionModify(_Symbol, open, tp);
         }
         
         // Trail
         if(profitR >= InpTrailStart_R)
         {
            double ab[1];
            if(CopyBuffer(hATR, 0, 0, 1, ab) == 1)
            {
               double td = ab[0] * InpTrailATR_Mult;
               double newSL = (pType == POSITION_TYPE_BUY) ? curr - td : curr + td;
               if((pType == POSITION_TYPE_BUY && newSL > sl && newSL < curr) ||
                  (pType == POSITION_TYPE_SELL && newSL < sl && newSL > curr))
                  trade.PositionModify(_Symbol, newSL, tp);
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
   int buyS = CalculateConfluenceScore(1);
   int sellS = CalculateConfluenceScore(-1);
   
   string govStatus = IsGovernorActive() ? "🟢 " + DoubleToString(GetRiskMultiplier()*100,0) + "%" : "🟡 Standalone";
   string tradingStatus = IsTradingEnabled() ? "🟢" : "🔴 BLOCKED";
   
   string txt = "═══════════════════════════════════════\n";
   txt += "  🎯 SYMBOL ENGINE: " + _Symbol + "\n";
   txt += "═══════════════════════════════════════\n";
   txt += "Governor: " + govStatus + "\n";
   txt += "Trading: " + tradingStatus + "\n";
   txt += "───────────────────────────────────────\n";
   txt += "Price: " + DoubleToString(price, (int)symbolInfo.Digits()) + "\n";
   txt += "RSI: " + DoubleToString(g_RSI, 1) + "\n";
   txt += "Session: " + (g_inSession ? "🟢" : "🔴") + "\n";
   txt += "───────────────────────────────────────\n";
   txt += "BUY Score: " + IntegerToString(buyS) + "/6\n";
   txt += "SELL Score: " + IntegerToString(sellS) + "/6\n";
   txt += "Min: " + IntegerToString(InpMinConfluenceEntry) + "/6\n";
   txt += "───────────────────────────────────────\n";
   txt += "Positions: " + IntegerToString(g_positionCount) + "/" + IntegerToString(InpMaxPositions) + "\n";
   txt += "Total R: " + DoubleToString(totalR, 2) + "\n";
   txt += "═══════════════════════════════════════\n";
   
   Comment(txt);
}
//+------------------------------------------------------------------+
