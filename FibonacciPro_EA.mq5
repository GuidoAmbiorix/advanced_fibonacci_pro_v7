//+------------------------------------------------------------------+
//|                                              FibonacciPro_EA.mq5 |
//|                                    Advanced Fibonacci Trading Bot |
//|                        Converted from TradingView Pine Script v7 |
//+------------------------------------------------------------------+
#property copyright "Fibonacci Pro Trading System"
#property link      "https://www.fibopro.trading"
#property version   "1.00"
#property description "Advanced Fibonacci Trading System with Multi-Timeframe Analysis"
#property description "Features: Auto Fibonacci, RSI, MACD, Stochastic, Volume Analysis"
#property description "AI-Enhanced Signals, Smart Money Tracking, Professional Risk Management"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Global objects
CTrade trade;
CPositionInfo position;
COrderInfo order;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+

//--- Professional Mode Settings
input group "========== PROFESSIONAL MODE =========="
input bool     InpProMode = true;                    // Enable Professional Features
input bool     InpMTFEnabled = true;                 // Multi-Timeframe Analysis
input bool     InpAISignals = true;                  // AI-Enhanced Signals
input bool     InpSmartMoney = true;                 // Smart Money Tracking
input bool     InpVolumeProfile = true;              // Volume Profile Analysis

//--- Fibonacci Configuration
input group "========== FIBONACCI SETTINGS =========="
input int      InpLookbackPeriod = 89;               // Lookback Period (21,34,55,89,144,233)
input int      InpSwingStrength = 5;                 // Swing Detection Sensitivity (2-21)
input bool     InpShowGoldenZone = true;             // Show Golden Zone (0.618-0.65)
input bool     InpShowKillZone = true;               // Show Kill Zone (0.886)

//--- Fibonacci Levels Selection
input group "========== FIBONACCI LEVELS =========="
input bool     InpRet_0236 = true;                   // 0.236 - Shallow Retracement
input bool     InpRet_0382 = true;                   // 0.382 - Key Support
input bool     InpRet_0500 = true;                   // 0.500 - Psychological
input bool     InpRet_0618 = true;                   // 0.618 - Golden Ratio
input bool     InpRet_0786 = true;                   // 0.786 - Deep Retracement
input bool     InpExt_1272 = true;                   // 1.272 - Initial Extension Target
input bool     InpExt_1618 = true;                   // 1.618 - Golden Extension
input bool     InpExt_2618 = true;                   // 2.618 - Extended Target

//--- Technical Indicators
input group "========== TECHNICAL INDICATORS =========="
input bool     InpUseRSI = true;                     // RSI Integration
input int      InpRSILength = 14;                    // RSI Period
input int      InpRSIOverbought = 70;                // RSI Overbought Level
input int      InpRSIOversold = 30;                  // RSI Oversold Level
input bool     InpUseMacd = true;                    // MACD Integration
input int      InpMacdFast = 12;                     // MACD Fast Period
input int      InpMacdSlow = 26;                     // MACD Slow Period
input int      InpMacdSignal = 9;                    // MACD Signal Period
input bool     InpUseStoch = true;                   // Stochastic Integration
input int      InpStochLength = 14;                  // Stochastic Period

//--- Volume Analysis
input group "========== VOLUME ANALYSIS =========="
input bool     InpUseVolume = true;                  // Volume Confirmation Required
input int      InpVolMaLength = 20;                  // Volume MA Length
input double   InpVolThreshold = 1.5;                // Volume Spike Multiplier (1.0-5.0)

//--- Signal Configuration
input group "========== SIGNAL CONFIGURATION =========="
input ENUM_SIGNAL_MODE InpSignalMode = SIGNAL_CONSERVATIVE; // Signal Mode
input bool     InpEnableLongs = true;                // Enable Long Signals
input bool     InpEnableShorts = true;               // Enable Short Signals
input int      InpConfluenceFactors = 4;             // Custom Confluence Required (1-7)

//--- Risk Management
input group "========== RISK MANAGEMENT =========="
input ENUM_RISK_MODE InpRiskMode = RISK_DYNAMIC_ATR; // Stop Loss Method
input int      InpATRLength = 14;                    // ATR Length
input double   InpATRMultiplier = 1.5;               // ATR Multiplier
input double   InpRRRatio = 2.0;                     // Risk:Reward Ratio
input double   InpMaxRiskPercent = 2.0;              // Max Risk % per Trade
input double   InpAccountSize = 10000;               // Account Size (0=Auto)

//--- Partial Profit Taking
input group "========== PROFIT MANAGEMENT =========="
input bool     InpUsePartialTP = true;               // Use Partial Take Profit
input double   InpTP1Percent = 50.0;                 // % to Close at TP1
input double   InpTP2Percent = 30.0;                 // % to Close at TP2
input double   InpTP3Percent = 20.0;                 // % to Close at TP3 (Remainder)
input double   InpTP1Multiplier = 0.5;               // TP1 at x RR Ratio
input double   InpTP2Multiplier = 1.0;               // TP2 at x RR Ratio
input double   InpTP3Multiplier = 1.5;               // TP3 at x RR Ratio

//--- Multi-Timeframe Settings
input group "========== MULTI-TIMEFRAME =========="
input ENUM_TIMEFRAMES InpHTF1 = PERIOD_CURRENT;      // Higher Timeframe 1 (0=Auto)
input ENUM_TIMEFRAMES InpHTF2 = PERIOD_CURRENT;      // Higher Timeframe 2 (0=Auto)

//--- Advanced Features
input group "========== ADVANCED FEATURES =========="
input bool     InpShowDashboard = true;              // Show Analytics Dashboard
input bool     InpShowPerformance = true;            // Show Performance Metrics
input int      InpMagicNumber = 123456;              // Magic Number
input string   InpTradeComment = "FiboPro";          // Trade Comment

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+

enum ENUM_SIGNAL_MODE
{
   SIGNAL_AGGRESSIVE = 0,      // Aggressive (More Signals)
   SIGNAL_MODERATE = 1,        // Moderate (Balanced)
   SIGNAL_CONSERVATIVE = 2,    // Conservative (High Accuracy)
   SIGNAL_CUSTOM = 3          // Custom (Manual Confluence)
};

enum ENUM_RISK_MODE
{
   RISK_FIXED_PERCENT = 0,     // Fixed Percentage
   RISK_DYNAMIC_ATR = 1,       // Dynamic ATR Based
   RISK_SWING_POINTS = 2,      // Based on Swing Points
   RISK_FIBONACCI = 3          // Fibonacci Based
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// Indicator Handles
int handleRSI, handleMACD, handleStoch, handleATR;
int handleRSI_HTF1, handleRSI_HTF2, handleMACD_HTF1, handleMACD_HTF2;

// Fibonacci Variables
double currentSwingHigh = 0;
double currentSwingLow = 0;
int swingHighBar = 0;
int swingLowBar = 0;
bool isBullishTrend = false;

// Fibonacci Levels
double fib0, fib100, fib236, fib382, fib500, fib618, fib650, fib786, fib886;
double fib1272, fib1618, fib2618;
double goldenZoneTop, goldenZoneBottom;

// Signal Scores
double bullScore = 0;
double bearScore = 0;
int fibConfluence = 0;

// Performance Tracking
int totalSignals = 0;
int winningTrades = 0;
int losingTrades = 0;
double totalPnL = 0;
double maxDrawdown = 0;
double peakEquity = 0;

// Trade Management
datetime lastBarTime = 0;
bool isNewBar = false;
ulong currentTicket = 0;
bool tp1Hit = false;
bool tp2Hit = false;
bool tp3Hit = false;

// Multi-Timeframe
ENUM_TIMEFRAMES htf1, htf2;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set trade parameters
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   // Initialize multi-timeframe periods
   InitializeTimeframes();

   // Initialize indicators
   if(!InitializeIndicators())
   {
      Print("Failed to initialize indicators!");
      return INIT_FAILED;
   }

   // Set account size
   if(InpAccountSize <= 0)
      peakEquity = AccountInfoDouble(ACCOUNT_BALANCE);
   else
      peakEquity = InpAccountSize;

   Print("========================================");
   Print("Fibonacci Pro EA v1.0 Initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(_Period));
   Print("Account Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print("========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleMACD != INVALID_HANDLE) IndicatorRelease(handleMACD);
   if(handleStoch != INVALID_HANDLE) IndicatorRelease(handleStoch);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleRSI_HTF1 != INVALID_HANDLE) IndicatorRelease(handleRSI_HTF1);
   if(handleRSI_HTF2 != INVALID_HANDLE) IndicatorRelease(handleRSI_HTF2);
   if(handleMACD_HTF1 != INVALID_HANDLE) IndicatorRelease(handleMACD_HTF1);
   if(handleMACD_HTF2 != INVALID_HANDLE) IndicatorRelease(handleMACD_HTF2);

   // Clean up chart objects
   ObjectsDeleteAll(0, "FiboPro_");

   Print("Fibonacci Pro EA Stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   CheckNewBar();

   // Update dashboard on every tick for real-time display
   if(InpShowDashboard)
      UpdateDashboard();

   // Process only on new bar
   if(!isNewBar) return;

   // Calculate Fibonacci levels
   CalculateFibonacciLevels();

   // Draw Fibonacci levels on chart
   if(InpProMode)
      DrawFibonacciLevels();

   // Calculate technical indicators
   double rsi, rsiMA;
   double macdMain, macdSignal, macdHist;
   double stochMain, stochSignal;
   double atr;

   GetTechnicalIndicators(rsi, rsiMA, macdMain, macdSignal, macdHist, stochMain, stochSignal, atr);

   // Multi-timeframe analysis
   bool mtfBullish = false, mtfBearish = false;
   if(InpMTFEnabled)
      GetMultiTimeframeSignals(mtfBullish, mtfBearish);

   // Volume analysis
   bool volumeSpike = false, bullishVolume = false, bearishVolume = false;
   if(InpUseVolume || InpVolumeProfile)
      GetVolumeAnalysis(volumeSpike, bullishVolume, bearishVolume);

   // Smart money tracking
   bool accumulation = false, distribution = false, institutionalVolume = false;
   if(InpSmartMoney)
      GetSmartMoneySignals(accumulation, distribution, institutionalVolume);

   // Calculate signal scores
   CalculateSignalScores(rsi, rsiMA, macdMain, macdSignal, macdHist, stochMain, stochSignal,
                         volumeSpike, bullishVolume, bearishVolume, mtfBullish, mtfBearish,
                         accumulation, distribution);

   // Generate trading signals
   bool longSignal = false, shortSignal = false;
   GenerateTradingSignals(longSignal, shortSignal, bullishVolume, bearishVolume);

   // Manage existing positions
   ManageOpenPositions(atr);

   // Execute new trades if no position open
   if(!HasOpenPosition())
   {
      if(longSignal && InpEnableLongs)
         ExecuteLongTrade(atr);
      else if(shortSignal && InpEnableShorts)
         ExecuteShortTrade(atr);
   }
}

//+------------------------------------------------------------------+
//| Initialize Timeframes                                            |
//+------------------------------------------------------------------+
void InitializeTimeframes()
{
   // Auto-select higher timeframes based on current timeframe
   if(InpHTF1 == PERIOD_CURRENT)
   {
      switch(_Period)
      {
         case PERIOD_M1:  htf1 = PERIOD_M5; break;
         case PERIOD_M5:  htf1 = PERIOD_M15; break;
         case PERIOD_M15: htf1 = PERIOD_H1; break;
         case PERIOD_M30: htf1 = PERIOD_H1; break;
         case PERIOD_H1:  htf1 = PERIOD_H4; break;
         case PERIOD_H4:  htf1 = PERIOD_D1; break;
         default:         htf1 = PERIOD_D1; break;
      }
   }
   else
      htf1 = InpHTF1;

   if(InpHTF2 == PERIOD_CURRENT)
   {
      switch(_Period)
      {
         case PERIOD_M1:  htf2 = PERIOD_M15; break;
         case PERIOD_M5:  htf2 = PERIOD_H1; break;
         case PERIOD_M15: htf2 = PERIOD_H4; break;
         case PERIOD_M30: htf2 = PERIOD_H4; break;
         case PERIOD_H1:  htf2 = PERIOD_D1; break;
         case PERIOD_H4:  htf2 = PERIOD_W1; break;
         default:         htf2 = PERIOD_W1; break;
      }
   }
   else
      htf2 = InpHTF2;
}

//+------------------------------------------------------------------+
//| Initialize Indicators                                            |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
   // RSI
   if(InpUseRSI)
   {
      handleRSI = iRSI(_Symbol, _Period, InpRSILength, PRICE_CLOSE);
      if(handleRSI == INVALID_HANDLE)
      {
         Print("Error creating RSI indicator: ", GetLastError());
         return false;
      }

      if(InpMTFEnabled)
      {
         handleRSI_HTF1 = iRSI(_Symbol, htf1, InpRSILength, PRICE_CLOSE);
         handleRSI_HTF2 = iRSI(_Symbol, htf2, InpRSILength, PRICE_CLOSE);
      }
   }

   // MACD
   if(InpUseMacd)
   {
      handleMACD = iMACD(_Symbol, _Period, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
      if(handleMACD == INVALID_HANDLE)
      {
         Print("Error creating MACD indicator: ", GetLastError());
         return false;
      }

      if(InpMTFEnabled)
      {
         handleMACD_HTF1 = iMACD(_Symbol, htf1, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
         handleMACD_HTF2 = iMACD(_Symbol, htf2, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
      }
   }

   // Stochastic
   if(InpUseStoch)
   {
      handleStoch = iStochastic(_Symbol, _Period, InpStochLength, 3, 3, MODE_SMA, STO_LOWHIGH);
      if(handleStoch == INVALID_HANDLE)
      {
         Print("Error creating Stochastic indicator: ", GetLastError());
         return false;
      }
   }

   // ATR (always needed for risk management)
   handleATR = iATR(_Symbol, _Period, InpATRLength);
   if(handleATR == INVALID_HANDLE)
   {
      Print("Error creating ATR indicator: ", GetLastError());
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
void CheckNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   isNewBar = (currentBarTime != lastBarTime);
   if(isNewBar)
      lastBarTime = currentBarTime;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                       |
//+------------------------------------------------------------------+
void CalculateFibonacciLevels()
{
   // Find swing highs and lows
   int highestBar = iHighest(_Symbol, _Period, MODE_HIGH, InpLookbackPeriod, 0);
   int lowestBar = iLowest(_Symbol, _Period, MODE_LOW, InpLookbackPeriod, 0);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, InpLookbackPeriod + 10, rates);

   if(copied <= 0)
   {
      Print("Error copying rates: ", GetLastError());
      return;
   }

   // Update swing points
   currentSwingHigh = rates[highestBar].high;
   currentSwingLow = rates[lowestBar].low;
   swingHighBar = highestBar;
   swingLowBar = lowestBar;

   // Determine trend direction
   isBullishTrend = (lowestBar > highestBar);

   // Calculate Fibonacci range
   double fibRange = currentSwingHigh - currentSwingLow;

   // Calculate base levels (0% and 100%)
   if(isBullishTrend)
   {
      fib0 = currentSwingLow;
      fib100 = currentSwingHigh;
   }
   else
   {
      fib0 = currentSwingHigh;
      fib100 = currentSwingLow;
   }

   // Calculate retracement levels
   if(isBullishTrend)
   {
      fib236 = currentSwingLow + fibRange * 0.236;
      fib382 = currentSwingLow + fibRange * 0.382;
      fib500 = currentSwingLow + fibRange * 0.500;
      fib618 = currentSwingLow + fibRange * 0.618;
      fib650 = currentSwingLow + fibRange * 0.650;
      fib786 = currentSwingLow + fibRange * 0.786;
      fib886 = currentSwingLow + fibRange * 0.886;

      // Extension levels
      fib1272 = currentSwingHigh + fibRange * 0.272;
      fib1618 = currentSwingHigh + fibRange * 0.618;
      fib2618 = currentSwingHigh + fibRange * 1.618;
   }
   else
   {
      fib236 = currentSwingHigh - fibRange * 0.236;
      fib382 = currentSwingHigh - fibRange * 0.382;
      fib500 = currentSwingHigh - fibRange * 0.500;
      fib618 = currentSwingHigh - fibRange * 0.618;
      fib650 = currentSwingHigh - fibRange * 0.650;
      fib786 = currentSwingHigh - fibRange * 0.786;
      fib886 = currentSwingHigh - fibRange * 0.886;

      // Extension levels
      fib1272 = currentSwingLow - fibRange * 0.272;
      fib1618 = currentSwingLow - fibRange * 0.618;
      fib2618 = currentSwingLow - fibRange * 1.618;
   }

   // Calculate Golden Zone
   goldenZoneTop = MathMax(fib618, fib650);
   goldenZoneBottom = MathMin(fib618, fib650);
}

//+------------------------------------------------------------------+
//| Get Technical Indicators Values                                  |
//+------------------------------------------------------------------+
void GetTechnicalIndicators(double &rsi, double &rsiMA, double &macdMain, double &macdSignal,
                             double &macdHist, double &stochMain, double &stochSignal, double &atr)
{
   double rsiBuffer[], macdBuffer[], signalBuffer[], stochBuffer[], stochSigBuffer[], atrBuffer[];

   // RSI
   if(InpUseRSI && handleRSI != INVALID_HANDLE)
   {
      ArraySetAsSeries(rsiBuffer, true);
      if(CopyBuffer(handleRSI, 0, 0, 15, rsiBuffer) > 0)
      {
         rsi = rsiBuffer[0];
         // Calculate RSI MA manually
         double sum = 0;
         for(int i = 0; i < 14; i++)
            sum += rsiBuffer[i];
         rsiMA = sum / 14.0;
      }
   }

   // MACD
   if(InpUseMacd && handleMACD != INVALID_HANDLE)
   {
      ArraySetAsSeries(macdBuffer, true);
      ArraySetAsSeries(signalBuffer, true);
      if(CopyBuffer(handleMACD, 0, 0, 3, macdBuffer) > 0 &&
         CopyBuffer(handleMACD, 1, 0, 3, signalBuffer) > 0)
      {
         macdMain = macdBuffer[0];
         macdSignal = signalBuffer[0];
         macdHist = macdMain - macdSignal;
      }
   }

   // Stochastic
   if(InpUseStoch && handleStoch != INVALID_HANDLE)
   {
      ArraySetAsSeries(stochBuffer, true);
      ArraySetAsSeries(stochSigBuffer, true);
      if(CopyBuffer(handleStoch, 0, 0, 2, stochBuffer) > 0 &&
         CopyBuffer(handleStoch, 1, 0, 2, stochSigBuffer) > 0)
      {
         stochMain = stochBuffer[0];
         stochSignal = stochSigBuffer[0];
      }
   }

   // ATR
   if(handleATR != INVALID_HANDLE)
   {
      ArraySetAsSeries(atrBuffer, true);
      if(CopyBuffer(handleATR, 0, 0, 1, atrBuffer) > 0)
         atr = atrBuffer[0];
   }
}

//+------------------------------------------------------------------+
//| Multi-Timeframe Analysis                                         |
//+------------------------------------------------------------------+
void GetMultiTimeframeSignals(bool &mtfBullish, bool &mtfBearish)
{
   double rsiHTF1[], rsiHTF2[], macdHTF1[], signalHTF1[], macdHTF2[], signalHTF2[];

   ArraySetAsSeries(rsiHTF1, true);
   ArraySetAsSeries(rsiHTF2, true);
   ArraySetAsSeries(macdHTF1, true);
   ArraySetAsSeries(signalHTF1, true);
   ArraySetAsSeries(macdHTF2, true);
   ArraySetAsSeries(signalHTF2, true);

   bool htf1Bull = false, htf2Bull = false;
   bool htf1Bear = false, htf2Bear = false;

   // HTF1 Analysis
   if(handleRSI_HTF1 != INVALID_HANDLE && CopyBuffer(handleRSI_HTF1, 0, 0, 1, rsiHTF1) > 0)
   {
      if(rsiHTF1[0] > 50) htf1Bull = true;
      if(rsiHTF1[0] < 50) htf1Bear = true;
   }

   if(handleMACD_HTF1 != INVALID_HANDLE &&
      CopyBuffer(handleMACD_HTF1, 0, 0, 1, macdHTF1) > 0 &&
      CopyBuffer(handleMACD_HTF1, 1, 0, 1, signalHTF1) > 0)
   {
      if(macdHTF1[0] > signalHTF1[0]) htf1Bull = htf1Bull && true;
      else htf1Bull = false;

      if(macdHTF1[0] < signalHTF1[0]) htf1Bear = htf1Bear && true;
      else htf1Bear = false;
   }

   // HTF2 Analysis
   if(handleRSI_HTF2 != INVALID_HANDLE && CopyBuffer(handleRSI_HTF2, 0, 0, 1, rsiHTF2) > 0)
   {
      if(rsiHTF2[0] > 50) htf2Bull = true;
      if(rsiHTF2[0] < 50) htf2Bear = true;
   }

   if(handleMACD_HTF2 != INVALID_HANDLE &&
      CopyBuffer(handleMACD_HTF2, 0, 0, 1, macdHTF2) > 0 &&
      CopyBuffer(handleMACD_HTF2, 1, 0, 1, signalHTF2) > 0)
   {
      if(macdHTF2[0] > signalHTF2[0]) htf2Bull = htf2Bull && true;
      else htf2Bull = false;

      if(macdHTF2[0] < signalHTF2[0]) htf2Bear = htf2Bear && true;
      else htf2Bear = false;
   }

   mtfBullish = htf1Bull && htf2Bull;
   mtfBearish = htf1Bear && htf2Bear;
}

//+------------------------------------------------------------------+
//| Volume Analysis                                                  |
//+------------------------------------------------------------------+
void GetVolumeAnalysis(bool &volumeSpike, bool &bullishVolume, bool &bearishVolume)
{
   long volumes[];
   ArraySetAsSeries(volumes, true);

   if(CopyTickVolume(_Symbol, _Period, 0, InpVolMaLength + 1, volumes) > 0)
   {
      // Calculate volume MA
      double volumeSum = 0;
      for(int i = 1; i <= InpVolMaLength; i++)
         volumeSum += volumes[i];
      double volumeMA = volumeSum / InpVolMaLength;

      // Check for volume spike
      volumeSpike = (volumes[0] > volumeMA * InpVolThreshold);

      // Get close prices to determine bullish/bearish volume
      double close[];
      ArraySetAsSeries(close, true);
      if(CopyClose(_Symbol, _Period, 0, 2, close) > 0)
      {
         bullishVolume = (close[0] > close[1]) && volumeSpike;
         bearishVolume = (close[0] < close[1]) && volumeSpike;
      }
   }
}

//+------------------------------------------------------------------+
//| Smart Money Tracking                                             |
//+------------------------------------------------------------------+
void GetSmartMoneySignals(bool &accumulation, bool &distribution, bool &institutionalVolume)
{
   long volumes[];
   ArraySetAsSeries(volumes, true);

   if(CopyTickVolume(_Symbol, _Period, 0, 51, volumes) > 0)
   {
      // Calculate average volumes
      double sum20 = 0, sum50 = 0;
      for(int i = 0; i < 20; i++)
         sum20 += volumes[i];
      for(int i = 0; i < 50; i++)
         sum50 += volumes[i];

      double avgVol20 = sum20 / 20.0;
      double avgVol50 = sum50 / 50.0;
      double maxAvg = MathMax(avgVol20, avgVol50);

      // Institutional volume detection
      institutionalVolume = (volumes[0] > maxAvg * 2.0);

      // Simplified Accumulation/Distribution
      double high[], low[], close[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);

      if(CopyHigh(_Symbol, _Period, 0, 21, high) > 0 &&
         CopyLow(_Symbol, _Period, 0, 21, low) > 0 &&
         CopyClose(_Symbol, _Period, 0, 21, close) > 0)
      {
         double adCurrent = 0, adPrev = 0;

         for(int i = 0; i < 20; i++)
         {
            double range = high[i] - low[i];
            if(range > 0)
            {
               double ad = ((close[i] - low[i]) - (high[i] - close[i])) / range * volumes[i];
               if(i < 10)
                  adCurrent += ad;
               else
                  adPrev += ad;
            }
         }

         accumulation = (adCurrent > adPrev) && (adCurrent > 0);
         distribution = (adCurrent < adPrev) && (adCurrent < 0);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Signal Scores                                          |
//+------------------------------------------------------------------+
void CalculateSignalScores(double rsi, double rsiMA, double macdMain, double macdSignal, double macdHist,
                           double stochMain, double stochSignal, bool volumeSpike, bool bullishVolume,
                           bool bearishVolume, bool mtfBullish, bool mtfBearish,
                           bool accumulation, bool distribution)
{
   // Reset scores
   bullScore = 0;
   bearScore = 0;
   fibConfluence = 0;

   double close[];
   ArraySetAsSeries(close, true);
   CopyClose(_Symbol, _Period, 0, 1, close);
   double currentClose = close[0];

   // Get ATR for tolerance
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   CopyBuffer(handleATR, 0, 0, 1, atrBuffer);
   double tolerance = atrBuffer[0] * 0.3;

   // Fibonacci Confluence Score
   if(MathAbs(currentClose - fib236) < tolerance && InpRet_0236) fibConfluence += 1;
   if(MathAbs(currentClose - fib382) < tolerance && InpRet_0382) fibConfluence += 2;
   if(MathAbs(currentClose - fib500) < tolerance && InpRet_0500) fibConfluence += 2;
   if(MathAbs(currentClose - fib618) < tolerance && InpRet_0618) fibConfluence += 3;
   if(MathAbs(currentClose - fib786) < tolerance && InpRet_0786) fibConfluence += 2;

   bool inGoldenZone = (currentClose >= goldenZoneBottom && currentClose <= goldenZoneTop);
   bool inKillZone = (MathAbs(currentClose - fib886) < atrBuffer[0] * 0.5);

   if(inGoldenZone && InpShowGoldenZone) fibConfluence += 4;
   if(inKillZone && InpShowKillZone) fibConfluence += 3;

   // Technical Indicator Scoring
   int technicalScore = 0;

   // RSI
   if(InpUseRSI)
   {
      bool rsiBullish = (rsi > 50 && rsi > rsiMA && rsi < InpRSIOverbought);
      bool rsiBearish = (rsi < 50 && rsi < rsiMA && rsi > InpRSIOversold);

      if(rsiBullish) technicalScore += 2;
      if(rsiBearish) technicalScore -= 2;
   }

   // MACD
   if(InpUseMacd)
   {
      bool macdBullish = (macdMain > macdSignal && macdHist > 0);
      bool macdBearish = (macdMain < macdSignal && macdHist < 0);

      if(macdBullish) technicalScore += 2;
      if(macdBearish) technicalScore -= 2;
   }

   // Stochastic
   if(InpUseStoch)
   {
      bool stochBullish = (stochMain > 20 && stochMain > stochSignal && stochMain < 80);
      bool stochBearish = (stochMain < 80 && stochMain < stochSignal && stochMain > 20);

      if(stochBullish) technicalScore += 1;
      if(stochBearish) technicalScore -= 1;
   }

   // Volume Scoring
   int volumeScore = 0;
   if(bullishVolume) volumeScore += 3;
   if(bearishVolume) volumeScore -= 3;

   // Multi-Timeframe Scoring
   int mtfScore = 0;
   if(mtfBullish) mtfScore += 3;
   if(mtfBearish) mtfScore -= 3;

   // Smart Money Scoring
   int smartScore = 0;
   if(accumulation) smartScore += 2;
   if(distribution) smartScore -= 2;

   // Accumulate Bullish Scores
   if(fibConfluence > 0)
      bullScore += fibConfluence;
   if(technicalScore > 0)
      bullScore += technicalScore;
   if(volumeScore > 0)
      bullScore += volumeScore;
   if(mtfScore > 0)
      bullScore += mtfScore;
   if(smartScore > 0)
      bullScore += smartScore;

   // Accumulate Bearish Scores
   if(fibConfluence > 0)
      bearScore += fibConfluence;
   if(technicalScore < 0)
      bearScore += MathAbs(technicalScore);
   if(volumeScore < 0)
      bearScore += MathAbs(volumeScore);
   if(mtfScore < 0)
      bearScore += MathAbs(mtfScore);
   if(smartScore < 0)
      bearScore += MathAbs(smartScore);

   // Normalize scores (0-10 scale)
   double maxScore = 20.0;
   bullScore = MathMin(10.0, (bullScore / maxScore) * 10.0);
   bearScore = MathMin(10.0, (bearScore / maxScore) * 10.0);
}

//+------------------------------------------------------------------+
//| Generate Trading Signals                                         |
//+------------------------------------------------------------------+
void GenerateTradingSignals(bool &longSignal, bool &shortSignal, bool bullishVolume, bool bearishVolume)
{
   // Determine signal threshold based on mode
   int signalThreshold = 0;
   switch(InpSignalMode)
   {
      case SIGNAL_AGGRESSIVE:    signalThreshold = 2 * 2; break;
      case SIGNAL_MODERATE:      signalThreshold = 3 * 2; break;
      case SIGNAL_CONSERVATIVE:  signalThreshold = 4 * 2; break;
      case SIGNAL_CUSTOM:        signalThreshold = InpConfluenceFactors * 2; break;
   }

   // Generate signals
   longSignal = (bullScore >= signalThreshold);
   shortSignal = (bearScore >= signalThreshold);

   // Volume confirmation if required
   if(InpUseVolume)
   {
      longSignal = longSignal && bullishVolume;
      shortSignal = shortSignal && bearishVolume;
   }
}

//+------------------------------------------------------------------+
//| Execute Long Trade                                               |
//+------------------------------------------------------------------+
void ExecuteLongTrade(double atr)
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Calculate stop loss
   double stopLoss = CalculateStopLoss(true, currentPrice, atr);
   double slDistance = currentPrice - stopLoss;

   // Calculate take profit levels
   double tp1 = currentPrice + (slDistance * InpRRRatio * InpTP1Multiplier);
   double tp2 = currentPrice + (slDistance * InpRRRatio * InpTP2Multiplier);
   double tp3 = currentPrice + (slDistance * InpRRRatio * InpTP3Multiplier);

   // Calculate position size
   double lotSize = CalculatePositionSize(slDistance);

   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);
   tp1 = NormalizeDouble(tp1, digits);

   // Open trade
   if(trade.Buy(lotSize, _Symbol, currentPrice, stopLoss, 0, InpTradeComment))
   {
      currentTicket = trade.ResultOrder();
      tp1Hit = false;
      tp2Hit = false;
      tp3Hit = false;
      totalSignals++;

      Print("========================================");
      Print("LONG TRADE OPENED");
      Print("Ticket: ", currentTicket);
      Print("Entry: ", currentPrice);
      Print("Stop Loss: ", stopLoss);
      Print("TP1: ", tp1, " (", InpTP1Percent, "%)");
      Print("TP2: ", tp2, " (", InpTP2Percent, "%)");
      Print("TP3: ", tp3, " (", InpTP3Percent, "%)");
      Print("Lot Size: ", lotSize);
      Print("Bull Score: ", DoubleToString(bullScore, 1), "/10");
      Print("========================================");
   }
   else
   {
      Print("Error opening long trade: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute Short Trade                                              |
//+------------------------------------------------------------------+
void ExecuteShortTrade(double atr)
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Calculate stop loss
   double stopLoss = CalculateStopLoss(false, currentPrice, atr);
   double slDistance = stopLoss - currentPrice;

   // Calculate take profit levels
   double tp1 = currentPrice - (slDistance * InpRRRatio * InpTP1Multiplier);
   double tp2 = currentPrice - (slDistance * InpRRRatio * InpTP2Multiplier);
   double tp3 = currentPrice - (slDistance * InpRRRatio * InpTP3Multiplier);

   // Calculate position size
   double lotSize = CalculatePositionSize(slDistance);

   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);
   tp1 = NormalizeDouble(tp1, digits);

   // Open trade
   if(trade.Sell(lotSize, _Symbol, currentPrice, stopLoss, 0, InpTradeComment))
   {
      currentTicket = trade.ResultOrder();
      tp1Hit = false;
      tp2Hit = false;
      tp3Hit = false;
      totalSignals++;

      Print("========================================");
      Print("SHORT TRADE OPENED");
      Print("Ticket: ", currentTicket);
      Print("Entry: ", currentPrice);
      Print("Stop Loss: ", stopLoss);
      Print("TP1: ", tp1, " (", InpTP1Percent, "%)");
      Print("TP2: ", tp2, " (", InpTP2Percent, "%)");
      Print("TP3: ", tp3, " (", InpTP3Percent, "%)");
      Print("Lot Size: ", lotSize);
      Print("Bear Score: ", DoubleToString(bearScore, 1), "/10");
      Print("========================================");
   }
   else
   {
      Print("Error opening short trade: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(bool isLong, double entryPrice, double atr)
{
   double slDistance = 0;

   switch(InpRiskMode)
   {
      case RISK_FIXED_PERCENT:
         slDistance = entryPrice * (InpMaxRiskPercent / 100.0);
         break;

      case RISK_DYNAMIC_ATR:
         slDistance = atr * InpATRMultiplier;
         break;

      case RISK_SWING_POINTS:
         slDistance = isLong ? (entryPrice - currentSwingLow) : (currentSwingHigh - entryPrice);
         break;

      case RISK_FIBONACCI:
         slDistance = isLong ? (entryPrice - fib786) : (fib786 - entryPrice);
         break;

      default:
         slDistance = atr * InpATRMultiplier;
         break;
   }

   // Ensure minimum stop distance
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = stopLevel * _Point;
   slDistance = MathMax(slDistance, minStop * 2);

   return isLong ? (entryPrice - slDistance) : (entryPrice + slDistance);
}

//+------------------------------------------------------------------+
//| Calculate Position Size                                          |
//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
{
   double accountBalance = (InpAccountSize > 0) ? InpAccountSize : AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (InpMaxRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double lotSize = 0;
   if(tickSize > 0 && slDistance > 0)
   {
      double moneyPerLot = (slDistance / tickSize) * tickValue;
      if(moneyPerLot > 0)
         lotSize = riskAmount / moneyPerLot;
   }

   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions(double atr)
{
   if(!position.Select(_Symbol)) return;

   ulong ticket = position.Ticket();
   double positionProfit = position.Profit();
   double entryPrice = position.PriceOpen();
   double currentPrice = position.PriceCurrent();
   double stopLoss = position.StopLoss();
   bool isLong = (position.Type() == POSITION_TYPE_BUY);
   double currentLots = position.Volume();

   // Calculate TP levels
   double slDistance = isLong ? (entryPrice - stopLoss) : (stopLoss - entryPrice);
   double tp1 = isLong ? entryPrice + (slDistance * InpRRRatio * InpTP1Multiplier) :
                         entryPrice - (slDistance * InpRRRatio * InpTP1Multiplier);
   double tp2 = isLong ? entryPrice + (slDistance * InpRRRatio * InpTP2Multiplier) :
                         entryPrice - (slDistance * InpRRRatio * InpTP2Multiplier);
   double tp3 = isLong ? entryPrice + (slDistance * InpRRRatio * InpTP3Multiplier) :
                         entryPrice - (slDistance * InpRRRatio * InpTP3Multiplier);

   // Partial profit taking
   if(InpUsePartialTP)
   {
      // TP1
      if(!tp1Hit && ((isLong && currentPrice >= tp1) || (!isLong && currentPrice <= tp1)))
      {
         double closeVolume = NormalizeDouble(currentLots * InpTP1Percent / 100.0, 2);
         if(closeVolume > 0)
         {
            trade.PositionClosePartial(ticket, closeVolume);
            tp1Hit = true;
            Print("TP1 Hit! Closed ", InpTP1Percent, "% at ", currentPrice);
         }
      }

      // TP2
      if(tp1Hit && !tp2Hit && ((isLong && currentPrice >= tp2) || (!isLong && currentPrice <= tp2)))
      {
         double closeVolume = NormalizeDouble(currentLots * InpTP2Percent / 100.0, 2);
         if(closeVolume > 0)
         {
            trade.PositionClosePartial(ticket, closeVolume);
            tp2Hit = true;
            Print("TP2 Hit! Closed ", InpTP2Percent, "% at ", currentPrice);
         }
      }

      // TP3 - Close remaining
      if(tp2Hit && !tp3Hit && ((isLong && currentPrice >= tp3) || (!isLong && currentPrice <= tp3)))
      {
         trade.PositionClose(ticket);
         tp3Hit = true;

         if(positionProfit > 0) winningTrades++;
         else losingTrades++;

         totalPnL += positionProfit;
         currentTicket = 0;

         Print("TP3 Hit! Closed remaining position at ", currentPrice);
         Print("Trade Profit: $", DoubleToString(positionProfit, 2));
      }
   }

   // Update performance tracking
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > peakEquity)
      peakEquity = currentEquity;

   double drawdown = peakEquity - currentEquity;
   if(drawdown > maxDrawdown)
      maxDrawdown = drawdown;
}

//+------------------------------------------------------------------+
//| Check if position is open                                        |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   return position.Select(_Symbol);
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Levels on Chart                                   |
//+------------------------------------------------------------------+
void DrawFibonacciLevels()
{
   // Delete old objects
   ObjectsDeleteAll(0, "FiboPro_Fib");

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   datetime time0 = iTime(_Symbol, _Period, swingLowBar);
   datetime time1 = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * 10;

   color lineColor = isBullishTrend ? clrLimeGreen : clrRed;

   // Draw main swing levels
   DrawHLine("FiboPro_Fib_0", fib0, clrBlue, STYLE_SOLID, 2, "0.0%");
   DrawHLine("FiboPro_Fib_100", fib100, clrBlue, STYLE_SOLID, 2, "100.0%");

   // Draw retracement levels
   if(InpRet_0236)
      DrawHLine("FiboPro_Fib_236", fib236, clrAqua, STYLE_DOT, 1, "23.6% (" + DoubleToString(fib236, digits) + ")");
   if(InpRet_0382)
      DrawHLine("FiboPro_Fib_382", fib382, clrYellow, STYLE_DASH, 1, "38.2% (" + DoubleToString(fib382, digits) + ")");
   if(InpRet_0500)
      DrawHLine("FiboPro_Fib_500", fib500, clrOrange, STYLE_SOLID, 2, "50.0% (" + DoubleToString(fib500, digits) + ")");
   if(InpRet_0618)
      DrawHLine("FiboPro_Fib_618", fib618, clrGold, STYLE_SOLID, 3, "61.8% GOLDEN (" + DoubleToString(fib618, digits) + ")");
   if(InpRet_0786)
      DrawHLine("FiboPro_Fib_786", fib786, clrYellow, STYLE_DASH, 1, "78.6% (" + DoubleToString(fib786, digits) + ")");

   // Draw Golden Zone rectangle
   if(InpShowGoldenZone)
   {
      string rectName = "FiboPro_Fib_GoldenZone";
      ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, time0, goldenZoneTop, time1, goldenZoneBottom);
      ObjectSetInteger(0, rectName, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
      ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
      ObjectSetString(0, rectName, OBJPROP_TEXT, "GOLDEN ZONE");
   }
}

//+------------------------------------------------------------------+
//| Draw Horizontal Line                                             |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string text)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!InpShowDashboard) return;

   // Create dashboard label
   string dashName = "FiboPro_Dashboard";
   int xPos = 10;
   int yPos = 20;

   string dashText = "=== FIBONACCI PRO v1.0 ===\n";
   dashText += "Symbol: " + _Symbol + "\n";
   dashText += "Trend: " + (isBullishTrend ? "BULLISH" : "BEARISH") + "\n";
   dashText += "Bull Score: " + DoubleToString(bullScore, 1) + "/10\n";
   dashText += "Bear Score: " + DoubleToString(bearScore, 1) + "/10\n";
   dashText += "Fib Confluence: " + IntegerToString(fibConfluence) + "\n";

   if(InpShowPerformance && totalSignals > 0)
   {
      dashText += "--- PERFORMANCE ---\n";
      dashText += "Total Signals: " + IntegerToString(totalSignals) + "\n";
      dashText += "Winning Trades: " + IntegerToString(winningTrades) + "\n";
      dashText += "Losing Trades: " + IntegerToString(losingTrades) + "\n";
      if(winningTrades + losingTrades > 0)
      {
         double winRate = (double)winningTrades / (winningTrades + losingTrades) * 100;
         dashText += "Win Rate: " + DoubleToString(winRate, 1) + "%\n";
      }
      dashText += "Total P/L: $" + DoubleToString(totalPnL, 2) + "\n";
   }

   // Create or update label
   if(ObjectFind(0, dashName) < 0)
   {
      ObjectCreate(0, dashName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, dashName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, dashName, OBJPROP_XDISTANCE, xPos);
      ObjectSetInteger(0, dashName, OBJPROP_YDISTANCE, yPos);
      ObjectSetInteger(0, dashName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, dashName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, dashName, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, dashName, OBJPROP_SELECTABLE, false);
   }

   ObjectSetString(0, dashName, OBJPROP_TEXT, dashText);
}
//+------------------------------------------------------------------+
