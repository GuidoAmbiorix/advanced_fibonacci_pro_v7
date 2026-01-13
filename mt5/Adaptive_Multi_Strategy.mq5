//+------------------------------------------------------------------+
//|                                      Adaptive_Multi_Strategy.mq5 |
//|                                  Based on Python Adaptive Engine |
//|                                       Institutional Edge Pro     |
//+------------------------------------------------------------------+
#property copyright "Institutional Edge Pro"
#property link      "https://institutional-edge.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| INPUTS & CONFIGURATION                                           |
//+------------------------------------------------------------------+
input group "========== STRATEGY TOGGLES =========="
input bool InpEnable_Institutional = true;    // Institutional Sweep (Liquidity+CVD)
input bool InpEnable_VWAP_Scalp    = true;    // VWAP Scalping (Mean Reversion)
input bool InpEnable_Fibonacci     = true;    // Fibonacci Golden Zone
input bool InpEnable_Stochastic    = true;    // Stochastic Momentum Burst
input bool InpEnable_Breakout      = false;   // Breakout Momentum (Lower WinRate)

input group "========== RISK MANAGEMENT =========="
input double InpMax_Drawdown_Percent = 7.0;   // Max Total Drawdown % (Funding Rule)
input double InpDaily_Loss_Percent   = 3.0;   // Max Daily Loss % (Funding Rule)
input int    InpMax_Daily_Trades     = 5;     // Max Trades Per Day (0 = Disable)
input double InpTarget_Daily_Profit  = 2.0;   // Daily Profit Target % (0 = Disable)
input double InpRisk_Per_Trade       = 1.0;   // Base Risk Per Trade %
input double InpRisk_Reward_Ratio    = 1.5;   // Base Risk:Reward Ratio

input group "========== TRAILING STOP TIERS =========="
input double InpTier1_Profit_R = 1.0;   // Tier 1: Profit (R)
input double InpTier1_Lock_R   = 0.1;   // Tier 1: Lock (R)
input double InpTier2_Profit_R = 2.0;   // Tier 2: Profit (R)
input double InpTier2_Lock_R   = 1.2;   // Tier 2: Lock (R)
input double InpTier3_Profit_R = 4.0;   // Tier 3: Profit (R)
input double InpTier3_Lock_R   = 3.0;   // Tier 3: Lock (R)

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;            // RSI Period
input int InpADX_Period      = 14;            // ADX Period
input int InpADX_Threshold   = 25;            // Trend Threshold (25+)
input int InpATR_Period      = 14;            // ATR Period
input int InpStoch_K         = 14;            // Stochastic %K
input int InpStoch_D         = 3;             // Stochastic %D
input int InpVariable_MA     = 20;            // Variable MA (VWAP Proxy)

input group "========== KILLZONES (EST TIME) =========="
input int    InpServerTimeOffset        = 2;     // Server Time Offset from EST (e.g. +2 for UTC+2)
input bool   InpUse_London_Killzone     = true;  // London Killzone (02:00-05:00 EST)
input string InpLondon_Start            = "02:00";
input string InpLondon_End              = "05:00";
input bool   InpUse_NY_Killzone         = true;  // NY Killzone (08:00-11:00 EST)
input string InpNY_Start                = "08:00";
input string InpNY_End                  = "11:00";
input bool   InpUse_LondonClose_Killzone= true;  // London Close (10:00-12:00 EST)
input string InpLondonClose_Start       = "10:00";
input string InpLondonClose_End         = "12:00";
input bool   InpCloseTrades_At_SessionEnd = true; // Close all trades outside Killzones?

input group "========== NEWS FILTER =========="
input bool   InpUse_NewsFilter       = true;  // Enable News Filter
input bool   InpNews_HighImpact_Only = true;  // High Impact Only
input int    InpNews_Before_Mins     = 30;    // Pause Minutes Before News
input int    InpNews_After_Mins      = 30;    // Pause Minutes After News

input group "========== SYSTEM =========="
input int InpMagicNumber     = 999999;        // Magic Number
input bool InpDebugMode      = true;          // Enable Detailed Logs

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

// Indicator Handles
int hRSI, hADX, hATR, hStoch, hMACD, hEMA20, hEMA50, hEMA200;
int hVWAP; // Custom or approximation

// State Variables
double AccountBalanceStartDay;
datetime LastDayChecked;
int DailyTradeCount;   // New: Track trades today
double DailyRealizedPL; // New: Track Profit today

enum ENUM_REGIME {
   REGIME_TRENDING,
   REGIME_RANGING,
   REGIME_VOLATILE,
   REGIME_BREAKOUT,
   REGIME_UNKNOWN
};

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize Objects
   symbolInfo.Name(_Symbol);
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Initialize Indicators
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   hADX = iADX(_Symbol, PERIOD_CURRENT, InpADX_Period);
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   hStoch = iStochastic(_Symbol, PERIOD_CURRENT, InpStoch_K, InpStoch_D, 3, MODE_SMA, STO_LOWHIGH);
   hMACD = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   hEMA20 = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
   hVWAP = iMA(_Symbol, PERIOD_CURRENT, InpVariable_MA, 0, MODE_SMA, PRICE_TYPICAL); // SMA of Typical Price as VWAP Proxy
   
   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE || 
      hStoch == INVALID_HANDLE || hMACD == INVALID_HANDLE || hEMA20 == INVALID_HANDLE || hVWAP == INVALID_HANDLE) 
   {
      Print("Error creating indicators!");
      return INIT_FAILED;
   }

   // Initialize Account Tracking
   AccountBalanceStartDay = accountInfo.Balance();
   LastDayChecked = iTime(_Symbol, PERIOD_D1, 0);

   Print("Adaptive Multi-Strategy EA Initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   IndicatorRelease(hADX);
   IndicatorRelease(hATR);
   IndicatorRelease(hStoch);
   IndicatorRelease(hMACD);
   IndicatorRelease(hEMA20);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hEMA200);
   IndicatorRelease(hVWAP);
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Manage Open Trades (Trailing Stop) - Always run management!
   ManageTrade();
   
   // 2. Session Close Check
   CheckSessionClose();

   // 3. Check Funding Rules (Daily Loss, Max DD, Daily Limits)
   if(!CheckFundingRules()) return;
   
   // 4. Data Gathering
   double rsi[], adx[], atr[], stochK[], stochD[], macd[], macdSig[], ema20[], ema50[], ema200[], vwap[];
   if(!GetIndicators(rsi, adx, atr, stochK, stochD, macd, macdSig, ema20, ema50, ema200, vwap)) return;
   
   // 3. Detect Market Regime
   ENUM_REGIME regime = DetectRegime(adx[0], atr[0]);
   
   // 4. Update Smart State (e.g., Daily High/Low for CVD)
   // ...
   
   // 5. Execute Strategies
   if(InpEnable_Institutional) RunInstitutionalStrategy(regime, rsi, atr, ema50, ema200);
   if(InpEnable_VWAP_Scalp)    RunVWAPStrategy(regime, vwap, rsi, ema20, ema50, atr);
   if(InpEnable_Fibonacci)     RunFibonacciStrategy(regime, ema20, ema50, atr, rsi);
   if(InpEnable_Stochastic)    RunStochasticStrategy(regime, stochK, stochD, ema20, ema50, atr);
   
   // 6. Manage Open Trades (Trailing Stop)
   ManageTrade();
}

//+------------------------------------------------------------------+
//| DATA & INDICATORS                                                |
//+------------------------------------------------------------------+
bool GetIndicators(double &rsi[], double &adx[], double &atr[], 
                  double &stochK[], double &stochD[], 
                  double &macd[], double &macdSig[],
                  double &ema20[], double &ema50[], double &ema200[], double &vwap[])
{
   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return false;
   if(CopyBuffer(hADX, 0, 0, 3, adx) < 3) return false;
   if(CopyBuffer(hATR, 0, 0, 3, atr) < 3) return false;
   if(CopyBuffer(hStoch, 0, 0, 3, stochK) < 3) return false;
   if(CopyBuffer(hStoch, 1, 0, 3, stochD) < 3) return false;
   if(CopyBuffer(hMACD, 0, 0, 3, macd) < 3) return false;
   if(CopyBuffer(hMACD, 1, 0, 3, macdSig) < 3) return false;
   if(CopyBuffer(hEMA20, 0, 0, 3, ema20) < 3) return false;
   if(CopyBuffer(hEMA50, 0, 0, 3, ema50) < 3) return false;
   if(CopyBuffer(hEMA200, 0, 0, 3, ema200) < 3) return false;
   if(CopyBuffer(hVWAP, 0, 0, 3, vwap) < 3) return false;
   
   // Set Array Series
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(macdSig, true);
   ArraySetAsSeries(ema20, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema200, true);
   ArraySetAsSeries(vwap, true);
   
   return true;
}

//+------------------------------------------------------------------+
//| LOGIC FUNCTIONS                                                  |
//+------------------------------------------------------------------+

// Check Funding Firm Rules
bool CheckFundingRules()
{
   // Check New Day for Daily Loss Reset
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != LastDayChecked)
   {
      AccountBalanceStartDay = accountInfo.Balance();
      LastDayChecked = currentDay;
   }
   
   double currentEquity = accountInfo.Equity();
   
   // Daily Loss Limit
   double dailyLoss = (AccountBalanceStartDay - currentEquity) / AccountBalanceStartDay * 100.0;
   if(dailyLoss >= InpDaily_Loss_Percent)
   {
      if(InpDebugMode) Print("STOP: Daily Loss Limit Hit (" + DoubleToString(dailyLoss, 2) + "%)");
      return false;
   }
   
   // --- NEW: Daily Limits Calculation ---
   CalculateDailyStats();
   
   // 1. Max Daily Trades
   if(InpMax_Daily_Trades > 0 && DailyTradeCount >= InpMax_Daily_Trades)
   {
      if(InpDebugMode) Print("STOP: Max Daily Trades Reached (" + IntegerToString(DailyTradeCount) + ")");
      return false;
   }
   
   // 2. Daily Profit Target
   if(InpTarget_Daily_Profit > 0)
   {
      double profitSide = (DailyRealizedPL + (currentEquity - accountInfo.Balance())); // Realized + Floating? Usually target is Realized.
      // Let's stick to Realized for "Target Reached, Stop Trading".
      
      double profitPct = (DailyRealizedPL / AccountBalanceStartDay) * 100.0;
      if(profitPct >= InpTarget_Daily_Profit)
      {
         if(InpDebugMode) Print("STOP: Daily Profit Target Hit (" + DoubleToString(profitPct, 2) + "%)");
         return false;
      }
   }
   
   // Max Drawdown (Total)
   // NOTE: This assumes Deposit is initial. For true prop firm, usually fixed value or high water mark.
   
   return true;
}

//+------------------------------------------------------------------+
//| UTILS                                                            |
//+------------------------------------------------------------------+
void CalculateDailyStats()
{
   DailyTradeCount = 0;
   DailyRealizedPL = 0.0;
   
   // Get History for Today
   HistorySelect(LastDayChecked, TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i=0; i<total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         
         if(magic == InpMagicNumber)
         {
            // Count Exits (Out or Out/By) as closed trades
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
            {
               DailyTradeCount++;
               DailyRealizedPL += HistoryDealGetDouble(ticket, DEAL_PROFIT);
               DailyRealizedPL += HistoryDealGetDouble(ticket, DEAL_SWAP);
               DailyRealizedPL += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            }
         }
      }
   }
}

// Check Funding Firm Rules (Block New Entries)
ENUM_REGIME DetectRegime(double adxVal, double atrVal)
{
   if(adxVal > InpADX_Threshold) return REGIME_TRENDING;
   
   // Simplistic volatility check (refine later if needed)
   // if(atrVal > ... ) return REGIME_VOLATILE;
   
   return REGIME_RANGING;
}

//+------------------------------------------------------------------+
//| STRATEGY 1: INSTITUTIONAL SWEEP (High Win Rate)                  |
//+------------------------------------------------------------------+
void RunInstitutionalStrategy(ENUM_REGIME regime, double &rsi[], double &atr[], double &ema50[], double &ema200[])
{
   // 0. Kill Zone Filter (Critical)
   if(InpUse_KillZones && !IsKillZone()) return;
   
   // 0b. News Filter
   if(InpUse_NewsFilter && IsNewsTime()) {
       if(InpDebugMode) Print("⚠️ News Filter Active: Trade Blocked");
       return;
   }
   
   if(position.Select(_Symbol)) return; // One trade at a time per symbol
   
   // 1. Identify Liquidity POOLS (20 candle High/Low)
   // We look back 20 candles EXCLUDING current (1 to 21)
   double swingHigh = 0;
   double swingLow = 999999;
   
   int lookback = InpSwap_Lookback;
   
   // Get Highs/Lows
   double highs[], lows[];
   CopyHigh(_Symbol, PERIOD_CURRENT, 1, lookback, highs);
   CopyLow(_Symbol, PERIOD_CURRENT, 1, lookback, lows);
   
   for(int i=0; i<lookback; i++) {
      if(highs[i] > swingHigh) swingHigh = highs[i];
      if(lows[i] < swingLow) swingLow = lows[i];
   }
   
   // 2. Logic: Price Breaks Level but Closes Inside
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double high  = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double low   = iLow(_Symbol, PERIOD_CURRENT, 0);
   
   // --- BULLISH SWEEP ---
   // Low sweeps SwingLow, but Close is above SwingLow
   if(low < swingLow && close > swingLow)
   {
      // Confirmation 1: H1/H4 Trend (EMA50 > EMA200)
      bool trendOk = ema50[0] > ema200[0];
      
      // Confirmation 2: RSI Oversold (Cheap)
      bool rsiOk = rsi[0] < 45; // Flexible oversold
      
      if(trendOk && rsiOk)
      {
         double sl = swingLow - (atr[0] * 0.5); // Tight SL behind the sweep
         double tp = close + (close - sl) * InpRisk_Reward_Ratio;
         
         if(InpDebugMode) Print("⚡ Institutional BUY: Sweep Low ", swingLow, " SL=", sl);
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Inst_Sweep_Buy");
      }
   }
   
   // --- BEARISH SWEEP ---
   // High sweeps SwingHigh, but Close is below SwingHigh
   else if(high > swingHigh && close < swingHigh)
   {
      // Confirmation 1: Trend
      bool trendOk = ema50[0] < ema200[0];
      
      // Confirmation 2: RSI Overbought (Expensive)
      bool rsiOk = rsi[0] > 55;
      
      if(trendOk && rsiOk)
      {
         double sl = swingHigh + (atr[0] * 0.5);
         double tp = close - (sl - close) * InpRisk_Reward_Ratio;
         
         if(InpDebugMode) Print("⚡ Institutional SELL: Sweep High ", swingHigh, " SL=", sl);
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Inst_Sweep_Sell");
      }
   }
}

// Kill Zone Logic (London 02-05, NY 08-11, Close 10-12 EST)
bool IsKillZone()
{
   // Current Server Time
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   // Convert Server Time to EST Estimate (Simple Hour Offset)
   // If Server is UTC+2 and EST is UTC-5, Offset should be -7? 
   // User Input InpServerTimeOffset is "Server Offset from EST".
   // e.g. If Server=14:00 and EST=07:00. Server is +7 hours ahead of EST.
   // So EST_Time = Server_Time - Offset.
   
   int estHour = dt.hour - InpServerTimeOffset;
   if(estHour < 0) estHour += 24;
   if(estHour >= 24) estHour -= 24;
   
   // Create a string "HH:MM" for comparison
   string currentEST = StringFormat("%02d:%02d", estHour, dt.min);
   
   bool inLondon = false;
   bool inNY = false;
   bool inLondonClose = false;
   
   // London (02:00 - 05:00)
   if(InpUse_London_Killzone) {
      if(CheckTimeRange(currentEST, InpLondon_Start, InpLondon_End)) inLondon = true;
   }
   
   // NY (08:00 - 11:00)
   if(InpUse_NY_Killzone) {
      if(CheckTimeRange(currentEST, InpNY_Start, InpNY_End)) inNY = true;
   }
   
   // London Close (10:00 - 12:00)
   if(InpUse_LondonClose_Killzone) {
      if(CheckTimeRange(currentEST, InpLondonClose_Start, InpLondonClose_End)) inLondonClose = true;
   }
   
   return (inLondon || inNY || inLondonClose);
}

// Helper: Check if Current "HH:MM" is inside Start "HH:MM" and End "HH:MM"
bool CheckTimeRange(string current, string start, string end)
{
   if(start < end) {
      // Normal range: 08:00 to 11:00
      return (current >= start && current <= end);
   } else {
      // Overnight range: 22:00 to 02:00
      return (current >= start || current <= end);
   }
}

// Session Close Logic
void CheckSessionClose()
{
   if(!InpCloseTrades_At_SessionEnd) return;
   
   // If we are NOT in a KillZone, Close All
   if(!IsKillZone())
   {
      if(position.Select(_Symbol)) // If we have a position
      {
          // Close it
          trade.PositionClose(_Symbol);
          if(InpDebugMode) Print("⌛ Session End: Forced Close of " + _Symbol);
      }
   }
}

// Execution Wrapper
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl, double tp, string comment)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = CalculateLotSize(MathAbs(price - sl));
   
   trade.PositionOpen(_Symbol, type, lot, price, sl, tp, comment);
}

double CalculateLotSize(double slDist)
{
   if(slDist == 0) return 0.01;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance = accountInfo.Balance();
   
   double riskMoney = balance * InpRisk_Per_Trade / 100.0; // 1% Risk
   double points = slDist / tickSize;
   
   double lot = riskMoney / (points * tickValue);
   lot = MathFloor(lot * 100) / 100.0; // Round to 0.01
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   
   return lot;
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT (Tiered Trailing Stop)                          |
//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!position.Select(_Symbol)) return;
   if(position.Magic() != InpMagicNumber) return;
   
   double openPrice = position.PriceOpen();
   double currentPrice = position.PriceCurrent();
   double sl = position.StopLoss();
   double tp = position.TakeProfit();
   long type = position.PositionType();
   
   double currentProfitPoints = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
   double initialRisk = MathAbs(openPrice - sl);
   
   // Avoid division by zero
   if(initialRisk == 0) return;
   
   double profitR = currentProfitPoints / initialRisk; // Profit in R
   
   // --- TIERED TRAILING STOP (Configurable) ---
   // Tier 1: Profit >= X -> Lock Y
   // Tier 2: Profit >= A -> Lock B
   // Tier 3: Profit >= C -> Lock D
   
   double newSL = 0;
   
   if(type == POSITION_TYPE_BUY)
   {
      double lockPrice = 0;
      
      // Check Highest Tier First
      if(profitR >= InpTier3_Profit_R)      lockPrice = openPrice + (initialRisk * InpTier3_Lock_R);
      else if(profitR >= InpTier2_Profit_R) lockPrice = openPrice + (initialRisk * InpTier2_Lock_R);
      else if(profitR >= InpTier1_Profit_R) lockPrice = openPrice + (initialRisk * InpTier1_Lock_R);
      
      // Only move SL UP
      if(lockPrice > 0 && lockPrice > sl)
      {
         trade.PositionModify(_Symbol, lockPrice, tp);
         if(InpDebugMode) Print("🔄 TSL UPDATE (BUY): Profit ", DoubleToString(profitR,2), "R -> Locked ", DoubleToString((lockPrice-openPrice)/initialRisk, 2), "R");
      }
   }
   else if(type == POSITION_TYPE_SELL)
   {
      double lockPrice = 0;
      
      if(profitR >= InpTier3_Profit_R)      lockPrice = openPrice - (initialRisk * InpTier3_Lock_R);
      else if(profitR >= InpTier2_Profit_R) lockPrice = openPrice - (initialRisk * InpTier2_Lock_R);
      else if(profitR >= InpTier1_Profit_R) lockPrice = openPrice - (initialRisk * InpTier1_Lock_R);
      
      // Only move SL DOWN (sl > lockPrice for SELL means current is higher/worse)
      if(lockPrice > 0 && (sl == 0 || sl > lockPrice))
      {
         trade.PositionModify(_Symbol, lockPrice, tp);
         if(InpDebugMode) Print("🔄 TSL UPDATE (SELL): Profit ", DoubleToString(profitR,2), "R -> Locked ", DoubleToString((openPrice-lockPrice)/initialRisk, 2), "R");
      }
   }
}

//+------------------------------------------------------------------+
//| NEWS FILTER                                                      |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   if(!InpUse_NewsFilter) return false;
   
   datetime now = TimeCurrent();
   datetime start = now - (InpNews_After_Mins * 60); // Look back (for "After" impact)
   datetime end   = now + (InpNews_Before_Mins * 60); // Look forward (for "Before" impact)
   
   // Get Calendar Values
   MqlCalendarValue values[];
   
   // We search for events in the range [now - After, now + Before]
   // If any High Impact event exists in this range, we are "In News Time".
   
   // Filter by Currency
   string base = StringSubstr(_Symbol, 0, 3);
   string quote = StringSubstr(_Symbol, 3, 3);
   
   if(CalendarValueHistory(values, start, end, NULL, NULL))
   {
      int total = ArraySize(values);
      for(int i=0; i<total; i++)
      {
         long eventId = values[i].event_id;
         MqlCalendarEvent event;
         if(CalendarEventById(eventId, event))
         {
             // Check Currency
             if(StringFind(base, event.currency) < 0 && StringFind(quote, event.currency) < 0 && event.currency != "USD") // Always check USD? Optional.
                continue;
             // But actually "USD" is usually in the pair if it matters.
             
             // Check Importance
             if(InpNews_HighImpact_Only && event.importance != CALENDAR_IMPORTANCE_HIGH)
                continue;
                
             // If we found a relevant event in the danger zone
             // Check precise time:
             // Danger Start = EventTime - Before
             // Danger End   = EventTime + After
             // We are at 'now'.
             // EventTime is values[i].time (or event.time?) -> values[i].time refers to period usually.
             // event.time_mode?
             // Actually values[i].time is the event timestamp.
             
             datetime eventTime = values[i].time;
             
             if(now >= (eventTime - InpNews_Before_Mins*60) && now <= (eventTime + InpNews_After_Mins*60))
             {
                if(InpDebugMode) Print("📰 News Active: ", event.name, " (", event.currency, ")");
                return true;
             }
         }
      }
   }
   
   return false;
}
//+------------------------------------------------------------------+
//| STRATEGY 2: VWAP SCALPING (Mean Reversion)                       |
//+------------------------------------------------------------------+
void RunVWAPStrategy(ENUM_REGIME regime, double &vwap[], double &rsi[], double &ema20[], double &ema50[], double &atr[])
{
   // Only trade in Range/Trend, not Breakout
   if(regime == REGIME_BREAKOUT) return;
   if(position.Select(_Symbol)) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   // vwap[], rsi[], etc. passed as arrays
   
   // --- BUY SCALP ---
   // Uptrend (EMA20 > EMA50) but Price is 'Cheap' (Below VWAP)
   if(ema20[0] > ema50[0] && close < vwap[0])
   {
      // Confirmation: RSI Oversold
      if(rsi[0] < 35)
      {
         double sl = close - (atr[0] * 1.5);
         double tp = vwap[0] + (vwap[0] - close) * 0.5; // Target back to VWAP + extension
         
         if(InpDebugMode) Print("⚡ VWAP Scalp BUY: Price ", close, " < VWAP ", vwap[0]);
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "VWAP_Scalp_Buy");
      }
   }
   
   // --- SELL SCALP ---
   // Downtrend but Price is 'Expensive' (Above VWAP)
   else if(ema20[0] < ema50[0] && close > vwap[0])
   {
      if(rsi[0] > 65)
      {
         double sl = close + (atr[0] * 1.5);
         double tp = vwap[0] - (close - vwap[0]) * 0.5;
         
         if(InpDebugMode) Print("⚡ VWAP Scalp SELL: Price ", close, " > VWAP ", vwap[0]);
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "VWAP_Scalp_Sell");
      }
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 4: STOCHASTIC MOMENTUM                                  |
//+------------------------------------------------------------------+
void RunStochasticStrategy(ENUM_REGIME regime, double &stochK[], double &stochD[], double &ema20[], double &ema50[], double &atr[])
{
   if(position.Select(_Symbol)) return;
   
   bool uptrend = ema20[0] > ema50[0];
   bool downtrend = ema20[0] < ema50[0];
   
   // BUY: Uptrend + Stoch Cross UP in oversold (< 25)
   if(uptrend && stochK[1] < 25 && stochD[1] < 25)
   {
      // Cross Check: K crosses above D
      if(stochK[1] < stochD[1] && stochK[0] > stochD[0])
      {
         double close = iClose(_Symbol, PERIOD_CURRENT, 0);
         double sl = close - (atr[0] * 1.5);
         double tp = close + (atr[0] * 3.0);
         
         if(InpDebugMode) Print("🚀 Stoch Buy: Cross Up in Trend");
         ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Stoch_Mom_Buy");
      }
   }
   
   // SELL: Downtrend + Stoch Cross DOWN in overbought (> 75)
   else if(downtrend && stochK[1] > 75 && stochD[1] > 75)
   {
      if(stochK[1] > stochD[1] && stochK[0] < stochD[0])
      {
         double close = iClose(_Symbol, PERIOD_CURRENT, 0);
         double sl = close + (atr[0] * 1.5);
         double tp = close - (atr[0] * 3.0);
         
         if(InpDebugMode) Print("🚀 Stoch Sell: Cross Down in Trend");
         ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Stoch_Mom_Sell");
      }
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 3: FIBONACCI GOLDEN ZONE                                |
//+------------------------------------------------------------------+
void RunFibonacciStrategy(ENUM_REGIME regime, double &ema20[], double &ema50[], double &atr[], double &rsi[])
{
   if(position.Select(_Symbol)) return;
   
   // Find Swing Points (20 candles)
   int lookback = 20;
   
   // MQL5 Highest/Lowest Implementation
   double highArr[], lowArr[];
   CopyHigh(_Symbol, PERIOD_CURRENT, 1, lookback, highArr);
   CopyLow(_Symbol, PERIOD_CURRENT, 1, lookback, lowArr);
   
   int highIdx = ArrayMaximum(highArr);
   int lowIdx = ArrayMinimum(lowArr);
   
   double swingHigh = highArr[highIdx];
   double swingLow  = lowArr[lowIdx];
   double range     = swingHigh - swingLow;
   
   if(range == 0) return;
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // --- BUY ZONE (Retracement in Uptrend) ---
   if(ema20[0] > ema50[0])
   {
      double fib50 = swingLow + (range * 0.50);
      double fib618 = swingLow + (range * 0.618);
      
      // Price is inside Golden Zone
      if(close >= fib50 && close <= fib618)
      {
         if(rsi[0] < 45) // Oversold confirmation in uptrend
         {
            double sl = swingLow - (atr[0] * 0.5); // Stop below swing low
            double tp = swingHigh; // Target recent high
            
            if(InpDebugMode) Print("📐 Fib Golden Zone BUY @ ", close);
            ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Fib_Buy");
         }
      }
   }
   
   // --- SELL ZONE (Retracement in Downtrend) ---
   else if(ema20[0] < ema50[0])
   {
      double fib50 = swingHigh - (range * 0.50);
      double fib618 = swingHigh - (range * 0.618); 
      
      // If Price is between 50% and 61.8% (Golden Zone)
      if(close >= fib618 && close <= fib50)
      {
         if(rsi[0] > 55)
         {
            double sl = swingHigh + (atr[0] * 0.5);
            double tp = swingLow;
            
            if(InpDebugMode) Print("📐 Fib Golden Zone SELL @ ", close);
            ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Fib_Sell");
         }
      }
   }
}
