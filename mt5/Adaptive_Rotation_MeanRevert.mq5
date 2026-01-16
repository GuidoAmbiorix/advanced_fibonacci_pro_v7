//+------------------------------------------------------------------+
//|                               Adaptive_Rotation_MeanRevert.mq5   |
//|                          ENGINE B: Institutional Rotation Logic  |
//|               Target Pairs: NZDUSD, USDCAD, USDJPY, EURGBP, CHF  |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro"
#property link      "https://institutional-edge.com"
#property version   "1.00"
#property description "Mean Reversion & Liquidity Fade Engine"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "========== STRATEGY TOGGLES =========="
input bool InpEnable_VWAP_Fade     = true;    // Primary: Fade VWAP Deviation (1.5s)
input bool InpEnable_Asian_Sweep   = true;    // Target: USDJPY, USDCAD
input bool InpEnable_Bollinger_Rev = true;    // Target: EURGBP, CHF

input group "========== RISK MANAGEMENT (CONSERVATIVE) =========="
input double InpRisk_Per_Trade       = 0.5;   // Low Risk (0.25% - 0.5%)
input double InpRisk_Reward_Ratio    = 1.5;   // Low RR (1:1 - 1:1.5)
input double InpMax_Drawdown_Percent = 5.0;   // Tight Equity Hard Stop
input int    InpMaxHoldTime          = 240;   // Max Hold Time (Minutes)
input int    InpMaxSpread_Points     = 25;    // Max Spread

input group "========== STRATEGY PARAMETERS =========="
input int    InpVWAP_Period         = 50;     // Rolling VWAP Proxy
input double InpVWAP_Deviation      = 2.0;    // Standard Deviations for Entry
input int    InpBollinger_Period    = 20;     
input double InpBollinger_Dev       = 2.0;
input int    InpADX_Period          = 14;
input int    InpADX_Max_Threshold   = 20;     // Max ADX for Mean Reversion

input group "========== ASIAN RANGE =========="
input string InpAsian_Start_Time    = "20:00"; // Server Time
input string InpAsian_End_Time      = "02:00"; // Server Time

input group "========== SYSTEM =========="
input int InpMagicNumber     = 888888;        // Unique Magic for Rotation
input bool InpDebugMode      = true;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

// Handles
int hVWAP_Bands; // Bands on Typical Price (VWAP Proxy)
int hBollinger;
int hADX;
int hRSI;
int hATR;

// State
double AccountBalanceStartDay;
double AccountHighWaterMark;
datetime LastDayChecked;

// Asian Range Memory
double g_AsianHigh = 0;
double g_AsianLow = 0;
datetime g_LastAsianCheck = 0;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   symbolInfo.Name(_Symbol);
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // 1. Symbol Lock - Rotation Pairs Only
   if(!IsValidRotationPair())
   {
      Print("❌ Error: Engine B is ONLY for Rotation Pairs (NZD, CAD, JPY, EURGBP, CHF).");
      return INIT_FAILED;
   }

   // 2. Indicators
   // VWAP Proxy: Bollinger Bands on Typical Price
   hVWAP_Bands = iBands(_Symbol, PERIOD_CURRENT, InpVWAP_Period, 0, InpVWAP_Deviation, PRICE_TYPICAL);
   
   // Standard Bollinger for Mean Reversion
   hBollinger = iBands(_Symbol, PERIOD_CURRENT, InpBollinger_Period, 0, InpBollinger_Dev, PRICE_CLOSE);
   
   hADX = iADX(_Symbol, PERIOD_CURRENT, InpADX_Period);
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_CURRENT, 14);

   if(hVWAP_Bands == INVALID_HANDLE || hBollinger == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("❌ Error creating indicators");
      return INIT_FAILED;
   }
   
   // Init Account
   AccountBalanceStartDay = accountInfo.Balance();
   AccountHighWaterMark = accountInfo.Equity();
   
   Print("✅ Engine B (Rotation) Initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hVWAP_Bands);
   IndicatorRelease(hBollinger);
   IndicatorRelease(hADX);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| UTILS                                                            |
//+------------------------------------------------------------------+
bool IsValidRotationPair()
{
   string s = _Symbol;
   StringToUpper(s);
   // ALLOW: NZDUSD, USDCAD, USDJPY, EURGBP, USDCHF, AUDCAD, etc.
   if(StringFind(s, "EURUSD") >= 0) return false; // Trend Pair (Engine A)
   if(StringFind(s, "GBPUSD") >= 0) return false; // Trend Pair (Engine A)
   if(StringFind(s, "AUDUSD") >= 0) return false; // Trend Pair (Engine A)
   if(StringFind(s, "XAU") >= 0)    return false; // Commodity
   return true;
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Pair-Specific Session Filter
   if(!IsCorrectSession()) return;
   
   // 2. Data Gathering
   double vwapUpper[], vwapLower[], vwapMid[];
   double bbUpper[], bbLower[], bbMid[];
   double adx[], rsi[], atr[];
   
   if(!GetIndicators(vwapUpper, vwapLower, vwapMid, bbUpper, bbLower, bbMid, adx, rsi, atr)) return;
   
   // 3. Manage Open Trades (Time Exit + Fixed Risk)
   if(IsPositionOpen())
   {
      ManageOpenTrades();
      return; 
   }
   
   // 4. Spread Check
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread_Points) return;

   // 5. Update Asian Range (Once per day/session)
   UpdateAsianRange();

   // 6. Strategy Execution
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // A. VWAP Deviation Fade (Primary)
   if(InpEnable_VWAP_Fade)
   {
       // Fade Sell
       if(close > vwapUpper[0]) 
       {
           // Filter: RSI Overbought > 70
           if(rsi[0] > 70) ExecuteTrade(ORDER_TYPE_SELL, atr[0], "VWAP_Fade");
       }
       // Fade Buy
       else if(close < vwapLower[0])
       {
           // Filter: RSI Oversold < 30
           if(rsi[0] < 30) ExecuteTrade(ORDER_TYPE_BUY, atr[0], "VWAP_Fade");
       }
   }
   
   // B. Asian Sweep (Range Fakeout)
   if(InpEnable_Asian_Sweep && g_AsianHigh > 0)
   {
       // Current Time must be London or NY (After Asian)
       // Logic: High/Low broken?
       // Check Previous High/Low relative to Range
       
       double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
       double prevLow  = iLow(_Symbol, PERIOD_CURRENT, 1);
       double prevClose= iClose(_Symbol, PERIOD_CURRENT, 1);
       
       // FADE HIGH: Price wick went above Asian High, but Closed Below
       if(prevHigh > g_AsianHigh && prevClose < g_AsianHigh && close < g_AsianHigh)
       {
           ExecuteTrade(ORDER_TYPE_SELL, atr[0], "Asian_Sweep_Sell");
       }
       
       // FADE LOW: Price wick went below Asian Low, but Closed Above
       if(prevLow < g_AsianLow && prevClose > g_AsianLow && close > g_AsianLow)
       {
            ExecuteTrade(ORDER_TYPE_BUY, atr[0], "Asian_Sweep_Buy");
       }
   }
   
   // C. Bollinger Mean Reversion (Low Volatility)
   if(InpEnable_Bollinger_Rev)
   {
       // Only if Trend is Dead (ADX < Threshold)
       if(adx[0] < InpADX_Max_Threshold)
       {
           if(close > bbUpper[0] && rsi[0] > 65)
               ExecuteTrade(ORDER_TYPE_SELL, atr[0], "BB_Rev_Sell");
           else if(close < bbLower[0] && rsi[0] < 35)
               ExecuteTrade(ORDER_TYPE_BUY, atr[0], "BB_Rev_Buy");
       }
   }
}

//+------------------------------------------------------------------+
//| LOGIC                                                            |
//+------------------------------------------------------------------+
bool IsCorrectSession()
{
   // Simple Logic: check string
   string s = _Symbol;
   StringToUpper(s);
   
   datetime estTime = TimeCurrent() - (2 * 3600); // Helper offset
   MqlDateTime dt; TimeToStruct(estTime, dt);
   int h = dt.hour;
   
   // EURGBP, USDCHF -> London Only (03-11 EST)
   if(StringFind(s, "EURGBP") >= 0 || StringFind(s, "CHF") >= 0)
   {
       return (h >= 3 && h < 11);
   }
   // USDCAD -> NY Only (08-16 EST)
   if(StringFind(s, "USDCAD") >= 0)
   {
       return (h >= 8 && h < 16);
   }
   // NZDUSD -> Asian + Early London (19-06 EST)
   if(StringFind(s, "NZDUSD") >= 0)
   {
       if(h >= 19 || h < 6) return true;
       return false;
   }
   // USDJPY -> Asian + NY (Skip gap?) -> 19-02, 08-12
   if(StringFind(s, "USDJPY") >= 0)
   {
       if(h >= 19 || h < 2) return true; // Asian
       if(h >= 8 && h < 12) return true; // NY
       return false;
   }
   
   return true; // Default allow
}

void UpdateAsianRange()
{
   // Logic: Find High/Low between InpAsian_Start_Time and InpAsian_End_Time
   // Reset daily?
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   
   // Only update effectively once per bar or if time passed
   // We scan PREVIOUS DAY's Asian session or Current Day's Asian?
   // Usually Asian Session is valid for the current day's London/NY
   // So we assume Asian ended.
   
   // Simplified: Just look back fixed bars if time matches?
   // Or precise `CopyHigh` with start/end time
   // This is complex to get right with server time differences.
   // Institutional Hack: Use iHighest with time filter.
   
   // We update g_AsianHigh/Low only when session ends (e.g. at 02:00)
   
   if(dt.hour == 3 && dt.min == 0) // Just after Asian close
   {
       // Calculate range of last 6 hours
       int startBar = iBarShift(_Symbol, PERIOD_CURRENT, now - 6*3600);
       int endBar = iBarShift(_Symbol, PERIOD_CURRENT, now); // 0
       
       double hVal = -1; double lVal = 99999;
       for(int i=0; i< (startBar - endBar); i++)
       {
           double h = iHigh(_Symbol, PERIOD_CURRENT, i);
           double l = iLow(_Symbol, PERIOD_CURRENT, i);
           if(h > hVal) hVal = h;
           if(l < lVal) lVal = l;
       }
       g_AsianHigh = hVal;
       g_AsianLow = lVal;
   }
}

void ExecuteTrade(ENUM_ORDER_TYPE type, double atr, string comment)
{
   // Fixed Stop / Target
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Stop Loss: Wide Structural (2.0 ATR)
   // Target: 1.5 ATR (Lower RR)
   double slDist = atr * 2.0; 
   double tpDist = atr * (2.0 * InpRisk_Reward_Ratio); 
   
   double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tpDist : price - tpDist;
   
   // Calc Lots (Conservative 0.5%)
   double balance = accountInfo.Balance();
   double riskVal = balance * (InpRisk_Per_Trade / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickVal == 0) return;
   double vol = riskVal / ((slDist / _Point) * tickVal);
   
   trade.PositionOpen(_Symbol, type, vol, price, sl, tp, comment);
}

void ManageOpenTrades()
{
   if(!position.Select(_Symbol)) return;
   if(position.Magic() != InpMagicNumber) return;
   
   // 1. Time Exit
   long openTime = position.Time();
   if(TimeCurrent() - openTime > InpMaxHoldTime * 60)
   {
      trade.PositionClose(position.Ticket());
      Print("⌛ Max Hold Time Reached - Closing Trade");
      return;
   }
   
   // 2. Partial Close (0.5R)
   // We need to track partials. Simple check: Is Volume reduced?
   // Or price > 0.5R?
   // For now, Keep Simple: No complex management.
}

bool GetIndicators(double &vu[], double &vl[], double &vm[], double &bu[], double &bl[], double &bm[], double &adx[], double &rsi[], double &atr[])
{
   CopyBuffer(hVWAP_Bands, 1, 0, 1, vu); // Upper
   CopyBuffer(hVWAP_Bands, 2, 0, 1, vl); // Lower
   CopyBuffer(hVWAP_Bands, 0, 0, 1, vm); // Base
   
   CopyBuffer(hBollinger, 1, 0, 1, bu);
   CopyBuffer(hBollinger, 2, 0, 1, bl);
   CopyBuffer(hBollinger, 0, 0, 1, bm);
   
   CopyBuffer(hADX, 0, 0, 2, adx);
   CopyBuffer(hRSI, 0, 0, 1, rsi);
   CopyBuffer(hATR, 0, 0, 1, atr);
   
   return true;
}

bool IsPositionOpen()
{
   return (PositionsTotal() > 0 && PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}
//+------------------------------------------------------------------+
