//+------------------------------------------------------------------+
//|        RSI_MACD_ATR_Scalper.mq5                                   |
//|        Pure Scalping Agent - Any Pair                             |
//+------------------------------------------------------------------+
#property copyright "Guido"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// ================= INPUTS =================
input double RiskPercent          = 0.5;

input int    RSI_Period           = 7;      // Faster RSI
input double RSI_Level            = 50.0;

input int    MACD_Fast            = 6;      // Faster MACD
input int    MACD_Slow            = 12;
input int    MACD_Signal          = 5;

input int    ATR_Period           = 14;
input double ATR_SL_Multiplier    = 1.0;    // Tighter SL
input double ATR_TP_Multiplier    = 1.5;    // Quicker TP
input double Min_ATR              = 0.0;    // Disable Volatility Filter

input bool   Use_ATR_Trailing     = true;
input double ATR_Trail_Multiplier = 0.8;    // Tighter Trail

input group "========== TREND FILTER =========="
input int    EMA_Period           = 200;    // Trend Filter

// --- Session filter ---
input int    TradeStartHour       = 7;   // London open
input int    TradeEndHour         = 20;  // NY close

// --- Spread & execution ---
input int    MaxSpreadPoints      = 20;
input int    SlippagePoints       = 5;

// --- News filter ---
input bool   Use_News_Filter      = true;
input int    NewsBlockMinutes     = 30;

// ================= GLOBALS =================
int rsiHandle, macdHandle, atrHandle, emaHandle;
datetime lastBarTime;

// ================= INIT =================
int OnInit()
{
   rsiHandle  = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   macdHandle = iMACD(_Symbol, _Period, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   atrHandle  = iATR(_Symbol, _Period, ATR_Period);
   emaHandle  = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(rsiHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetDeviationInPoints(SlippagePoints);
   return INIT_SUCCEEDED;
}

// ================= UTILS =================
bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

bool InSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   return (hour >= TradeStartHour && hour <= TradeEndHour);
}

bool SpreadOK()
{
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return spread <= MaxSpreadPoints;
}

bool NewsTime()
{
   if(!Use_News_Filter) return false;

   // CalendarEventNext is not a standard MQL5 function.
   // Logic disabled to prevent compilation errors.
   return false;
}

double LotSize(double stopPoints)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = riskMoney / (stopPoints * tickValue);
   return NormalizeDouble(lot, 2);
}

// ================= MAIN =================
void OnTick()
{
   if(!IsNewBar()) return;
   if(PositionSelect(_Symbol)) return;
   if(!InSession()) return;
   if(!SpreadOK()) return;
   if(NewsTime()) return;

   double rsi[4], macdHist[4], atr[1], ema[1], close[1];

   CopyBuffer(rsiHandle, 0, 0, 4, rsi);
   CopyBuffer(macdHandle, 2, 0, 4, macdHist);
   CopyBuffer(atrHandle, 0, 0, 1, atr);
   CopyBuffer(emaHandle, 0, 0, 1, ema);
   CopyClose(_Symbol, _Period, 0, 1, close);

   if(atr[0] < Min_ATR) return;

   double slDist = atr[0] * ATR_SL_Multiplier;
   double tpDist = atr[0] * ATR_TP_Multiplier;

   double lot = LotSize(slDist / _Point);

   // --- LOGIC: Trend + Momentum + Recent Cross ---
   
   // 1. Trend Filter
   bool bullTrend = close[0] > ema[0];
   bool bearTrend = close[0] < ema[0];
   
   // 2. Momentum Confirmation (Current Bar)
   bool rsiBull = rsi[0] > RSI_Level;
   bool macdBull = macdHist[0] > 0;
   bool rsiBear = rsi[0] < RSI_Level;
   bool macdBear = macdHist[0] < 0;
   
   // 3. Recent Signal (Within last 3 bars) - Avoids "exact bar" issue but ensures freshness
   bool rsiCrossUp   = (rsi[1] < RSI_Level && rsi[0] > RSI_Level) || (rsi[2] < RSI_Level && rsi[1] > RSI_Level) || (rsi[3] < RSI_Level && rsi[2] > RSI_Level);
   bool macdCrossUp  = (macdHist[1] < 0 && macdHist[0] > 0) || (macdHist[2] < 0 && macdHist[1] > 0) || (macdHist[3] < 0 && macdHist[2] > 0);
   
   bool rsiCrossDown  = (rsi[1] > RSI_Level && rsi[0] < RSI_Level) || (rsi[2] > RSI_Level && rsi[1] < RSI_Level) || (rsi[3] > RSI_Level && rsi[2] < RSI_Level);
   bool macdCrossDown = (macdHist[1] > 0 && macdHist[0] < 0) || (macdHist[2] > 0 && macdHist[1] < 0) || (macdHist[3] > 0 && macdHist[2] < 0);

   // BUY: Trend UP + Momentum UP + At least one recent cross signal
   if(bullTrend && rsiBull && macdBull && (rsiCrossUp || macdCrossUp))
   {
      trade.Buy(lot, _Symbol,
         SymbolInfoDouble(_Symbol, SYMBOL_ASK),
         SymbolInfoDouble(_Symbol, SYMBOL_ASK) - slDist,
         SymbolInfoDouble(_Symbol, SYMBOL_ASK) + tpDist,
         "RSI_MACD_BUY");
   }

   // SELL: Trend DOWN + Momentum DOWN + At least one recent cross signal
   if(bearTrend && rsiBear && macdBear && (rsiCrossDown || macdCrossDown))
   {
      trade.Sell(lot, _Symbol,
         SymbolInfoDouble(_Symbol, SYMBOL_BID),
         SymbolInfoDouble(_Symbol, SYMBOL_BID) + slDist,
         SymbolInfoDouble(_Symbol, SYMBOL_BID) - tpDist,
         "RSI_MACD_SELL");
   }
   
   // Debug
   /*
   PrintFormat("Trend: %s | RSI: %.2f, MACD: %.5f | CrossUp: %s, CrossDown: %s", 
               bullTrend ? "UP" : "DOWN",
               rsi[0], macdHist[0], 
               (rsiCrossUp || macdCrossUp) ? "Yes" : "No",
               (rsiCrossDown || macdCrossDown) ? "Yes" : "No");
   */
}

// ================= TRAILING =================
void OnTrade()
{
   if(!Use_ATR_Trailing) return;
   if(!PositionSelect(_Symbol)) return;

   double atr[];
   CopyBuffer(atrHandle, 0, 0, 1, atr);

   ulong ticket = PositionGetInteger(POSITION_TICKET);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   long type    = PositionGetInteger(POSITION_TYPE);

   double trail = atr[0] * ATR_Trail_Multiplier;

   if(type == POSITION_TYPE_BUY)
   {
      double newSL = SymbolInfoDouble(_Symbol, SYMBOL_BID) - trail;
      if(newSL > sl)
         trade.PositionModify(ticket, newSL, tp);
   }

   if(type == POSITION_TYPE_SELL)
   {
      double newSL = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + trail;
      if(newSL < sl)
         trade.PositionModify(ticket, newSL, tp);
   }
}
