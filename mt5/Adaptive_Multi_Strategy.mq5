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
input double InpRisk_Per_Trade       = 1.0;   // Base Risk Per Trade %
input double InpRisk_Reward_Ratio    = 1.5;   // Base Risk:Reward Ratio

input group "========== INDICATOR SETTINGS =========="
input int InpRSI_Period      = 14;            // RSI Period
input int InpADX_Period      = 14;            // ADX Period
input int InpADX_Threshold   = 25;            // Trend Threshold (25+)
input int InpATR_Period      = 14;            // ATR Period
input int InpStoch_K         = 14;            // Stochastic %K
input int InpStoch_D         = 3;             // Stochastic %D
input int InpVariable_MA     = 20;            // Variable MA (VWAP Proxy)

input group "========== INSTITUTIONAL SETTINGS =========="
input int InpSwap_Lookback   = 20;            // Liquidity Sweep Lookback
input bool InpUse_KillZones  = true;          // Use Strict Kill Zones (London/NY)

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
   // 1. Check Funding Rules (Daily Loss, Max DD)
   if(!CheckFundingRules()) return;
   
   // 2. Data Gathering
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
   
   // Max Drawdown (Total)
   // NOTE: This assumes Deposit is initial. For true prop firm, usually fixed value or high water mark.
   // Simplified for now based on Balance history could be complex. using Balance for simple check.
   // Ideally pass InitialDeposit as input if needed exact.
   
   return true;
}

// Detect Market Regime
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

// Kill Zone Logic (London 07-10, NY 13-17 UTC)
bool IsKillZone()
{
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   // Adjust for Broker Offset if needed (Input InpBrokerOffset usually)
   // Assuming Server Time aligns with general sessions, or user adjusts inputs
   // Simple check: London Open (8-11 Server?), NY Open (15-19 Server?)
   // Defaulting to "Broad" active hours for now: 8 to 20
   
   int h = dt.hour;
   if( (h >= 8 && h <= 11) || (h >= 14 && h <= 18) ) return true;
   
   return false;
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
   
   // --- TIERED TRAILING STOP (Python Logic) ---
   // 1.0R Profit -> Lock 0.1R (BreakEven + Buffer)
   // 1.5R Profit -> Lock 0.5R (Secure Bank)
   // 2.0R Profit -> Lock 1.2R (Winner)
   // 3.0R Profit -> Lock 2.0R (Runner)
   // 4.0R Profit -> Lock 3.0R
   
   double newSL = 0;
   
   if(type == POSITION_TYPE_BUY)
   {
      double lockPrice = 0;
      
      if(profitR >= 4.0)      lockPrice = openPrice + (initialRisk * 3.0);
      else if(profitR >= 3.0) lockPrice = openPrice + (initialRisk * 2.0);
      else if(profitR >= 2.0) lockPrice = openPrice + (initialRisk * 1.2);
      else if(profitR >= 1.5) lockPrice = openPrice + (initialRisk * 0.5);
      else if(profitR >= 1.0) lockPrice = openPrice + (initialRisk * 0.1);
      
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
      
      if(profitR >= 4.0)      lockPrice = openPrice - (initialRisk * 3.0);
      else if(profitR >= 3.0) lockPrice = openPrice - (initialRisk * 2.0);
      else if(profitR >= 2.0) lockPrice = openPrice - (initialRisk * 1.2);
      else if(profitR >= 1.5) lockPrice = openPrice - (initialRisk * 0.5);
      else if(profitR >= 1.0) lockPrice = openPrice - (initialRisk * 0.1);
      
      // Only move SL DOWN (remember SL for sell is above price)
      // wait, "sl > lockPrice" means current SL is HIGHER (worse) than new lock level.
      // So we want to move it DOWN to lockPrice.
      if(lockPrice > 0 && (sl == 0 || sl > lockPrice))
      {
         trade.PositionModify(_Symbol, lockPrice, tp);
         if(InpDebugMode) Print("🔄 TSL UPDATE (SELL): Profit ", DoubleToString(profitR,2), "R -> Locked ", DoubleToString((openPrice-lockPrice)/initialRisk, 2), "R");
      }
   }
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
