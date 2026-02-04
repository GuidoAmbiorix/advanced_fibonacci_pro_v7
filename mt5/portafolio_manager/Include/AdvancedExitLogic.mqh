//+------------------------------------------------------------------+
//|                                        AdvancedExitLogic.mqh     |
//|                       Advanced Exit Strategy Module               |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Exit Reason Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_EXIT_REASON
{
   EXIT_NONE = 0,
   EXIT_TAKE_PROFIT = 1,
   EXIT_STOP_LOSS = 2,
   EXIT_TRAILING_STOP = 3,
   EXIT_OPPOSING_SIGNAL = 4,
   EXIT_HTF_REVERSAL = 5,
   EXIT_SESSION_END = 6,
   EXIT_NEWS_APPROACHING = 7,
   EXIT_TIME_LIMIT = 8,
   EXIT_MANUAL = 9
};

//+------------------------------------------------------------------+
//| Exit Decision Structure                                          |
//+------------------------------------------------------------------+
struct ExitDecision
{
   bool              shouldExit;
   ENUM_EXIT_REASON  reason;
   double            exitPrice;
   string            description;
};

//+------------------------------------------------------------------+
//| Advanced Exit Logic Class                                        |
//+------------------------------------------------------------------+
class CAdvancedExitLogic
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   // Exit parameters
   int               m_maxHoldBarsH1;       // Maximum hold time for H1
   int               m_newsBufferMinutes;   // Minutes before news to exit
   bool              m_exitOnOpposingSignal;
   bool              m_exitOnHTFReversal;

   // Session parameters
   int               m_sessionEndHour;      // NY close hour

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CAdvancedExitLogic()
   {
      m_maxHoldBarsH1 = 72;                // 72 hours (3 days max on H1)
      m_newsBufferMinutes = 30;
      m_exitOnOpposingSignal = true;
      m_exitOnHTFReversal = true;
      m_sessionEndHour = 17;               // 5 PM NY time
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;

      // Adjust max hold time based on timeframe
      if(m_timeframe == PERIOD_M5)
         m_maxHoldBarsH1 = 72; // 72 * 5min = 6 hours (Scalp max hold)
      else if(m_timeframe == PERIOD_M15)
         m_maxHoldBarsH1 = 64; // 16 hours
      else if(m_timeframe == PERIOD_H1)
         m_maxHoldBarsH1 = 72;
      else if(m_timeframe == PERIOD_H4)
         m_maxHoldBarsH1 = 18;  // 72 hours / 4
      else if(m_timeframe == PERIOD_D1)
         m_maxHoldBarsH1 = 5;   // 5 days
   }

   //+------------------------------------------------------------------+
   //| Evaluate Exit Conditions                                        |
   //+------------------------------------------------------------------+
   ExitDecision EvaluateExit(long ticket, int positionDirection,
                            double entryPrice, datetime entryTime)
   {
      ExitDecision decision;
      decision.shouldExit = false;
      decision.reason = EXIT_NONE;
      decision.exitPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      decision.description = "No exit signal";

      // 1. Check Time Limit
      ExitDecision timeExit = CheckTimeLimit(entryTime);
      if(timeExit.shouldExit) return timeExit;

      // 2. Check News Proximity
      ExitDecision newsExit = CheckNewsProximity();
      if(newsExit.shouldExit) return newsExit;

      // 3. Check Session End
      ExitDecision sessionExit = CheckSessionEnd();
      if(sessionExit.shouldExit) return sessionExit;

      // 4. Check Opposing SMC Signal
      ExitDecision opposingExit = CheckOpposingSignal(positionDirection);
      if(opposingExit.shouldExit) return opposingExit;

      // 5. Check HTF Reversal
      ExitDecision htfExit = CheckHTFReversal(positionDirection);
      if(htfExit.shouldExit) return htfExit;

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Check Time Limit                                                |
   //+------------------------------------------------------------------+
   ExitDecision CheckTimeLimit(datetime entryTime)
   {
      ExitDecision decision;
      decision.shouldExit = false;
      decision.exitPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      // Calculate bars since entry
      int barsSinceEntry = Bars(m_symbol, m_timeframe, entryTime, TimeCurrent());

      if(barsSinceEntry >= m_maxHoldBarsH1)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_TIME_LIMIT;
         decision.description = StringFormat("Max hold time reached (%d bars)", barsSinceEntry);
      }

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Check News Proximity                                            |
   //+------------------------------------------------------------------+
   ExitDecision CheckNewsProximity()
   {
      ExitDecision decision;
      decision.shouldExit = false;
      decision.exitPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      // In real implementation, check economic calendar
      // For now, simplified check for common news times

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Check for NFP (First Friday of month at 8:30 EST)
      bool isFirstFriday = (dt.day_of_week == 5 && dt.day <= 7);
      bool isNFPTime = (dt.hour == 8 && dt.min >= 0 && dt.min < 60);

      if(isFirstFriday && isNFPTime)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_NEWS_APPROACHING;
         decision.description = "Major news event approaching (NFP)";
      }

      // Check for FOMC (typically 2:00 PM EST)
      bool isFOMCTime = (dt.hour == 14 && dt.min >= 0 && dt.min < 60);
      bool isFOMCWeek = (dt.day >= 1 && dt.day <= 7); // First week (simplified)

      if(isFOMCWeek && isFOMCTime)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_NEWS_APPROACHING;
         decision.description = "Major news event approaching (FOMC)";
      }

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Check Session End                                               |
   //+------------------------------------------------------------------+
   ExitDecision CheckSessionEnd()
   {
      ExitDecision decision;
      decision.shouldExit = false;
      decision.exitPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Exit 30 minutes before session end
      bool nearSessionEnd = (dt.hour == m_sessionEndHour - 1 && dt.min >= 30) ||
                           (dt.hour == m_sessionEndHour);

      // Only exit on Friday
      bool isFriday = (dt.day_of_week == 5);

      if(isFriday && nearSessionEnd)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_SESSION_END;
         decision.description = "Weekend - closing before session end";
      }

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Check Opposing SMC Signal                                       |
   //+------------------------------------------------------------------+
   ExitDecision CheckOpposingSignal(int positionDirection)
   {
      ExitDecision decision;
      decision.shouldExit = false;
      decision.exitPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(!m_exitOnOpposingSignal) return decision;

      // Check for opposing order blocks, FVGs, or liquidity sweeps
      // In real implementation, integrate with SMC modules

      // Simplified: Check for strong opposing candle
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) < 3)
         return decision;

      // Get ATR
      double atr[];
      ArraySetAsSeries(atr, true);
      int hATR = iATR(m_symbol, m_timeframe, 14);
      if(hATR == INVALID_HANDLE) return decision;

      if(CopyBuffer(hATR, 0, 0, 1, atr) < 1)
      {
         IndicatorRelease(hATR);
         return decision;
      }

      IndicatorRelease(hATR);

      // Check for strong opposing candle (> 2.0 ATR)
      double candle0Range = rates[0].high - rates[0].low;
      bool strongCandle = candle0Range > atr[0] * 2.0;

      // Long position, strong bearish candle
      if(positionDirection == 1 && strongCandle && rates[0].close < rates[0].open)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_OPPOSING_SIGNAL;
         decision.description = "Strong opposing bearish candle detected";
      }

      // Short position, strong bullish candle
      if(positionDirection == -1 && strongCandle && rates[0].close > rates[0].open)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_OPPOSING_SIGNAL;
         decision.description = "Strong opposing bullish candle detected";
      }

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Check HTF Structure Break                                       |
   //+------------------------------------------------------------------+
   ExitDecision CheckHTFReversal(int positionDirection)
   {
      ExitDecision decision;
      decision.shouldExit = false;
      decision.exitPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(!m_exitOnHTFReversal) return decision;

      // Check D1 and H4 for structure break
      ENUM_TIMEFRAMES htf = PERIOD_D1;
      
      if(m_timeframe == PERIOD_M5)
         htf = PERIOD_H1;  // M5 looks at H1 structure
      else if(m_timeframe == PERIOD_M15)
         htf = PERIOD_H4;
      else if(m_timeframe == PERIOD_H1)
         htf = PERIOD_D1;
      else if(m_timeframe == PERIOD_D1)
         htf = PERIOD_W1; // Use weekly for D1 positions

      MqlRates htfRates[];
      ArraySetAsSeries(htfRates, true);

      if(CopyRates(m_symbol, htf, 0, 20, htfRates) < 20)
         return decision;

      // Find recent swing high/low
      int highBar = ArrayMaximum(htfRates, 1, 10);
      int lowBar = ArrayMinimum(htfRates, 1, 10);

      double recentHigh = htfRates[highBar].high;
      double recentLow = htfRates[lowBar].low;

      // Check for structure break
      double currentPrice = htfRates[0].close;

      // Long position: Exit if HTF breaks below recent low
      if(positionDirection == 1 && currentPrice < recentLow)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_HTF_REVERSAL;
         decision.description = StringFormat("HTF structure break below %.5f", recentLow);
      }

      // Short position: Exit if HTF breaks above recent high
      if(positionDirection == -1 && currentPrice > recentHigh)
      {
         decision.shouldExit = true;
         decision.reason = EXIT_HTF_REVERSAL;
         decision.description = StringFormat("HTF structure break above %.5f", recentHigh);
      }

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Get Exit Reason Name                                            |
   //+------------------------------------------------------------------+
   string GetExitReasonName(ENUM_EXIT_REASON reason)
   {
      switch(reason)
      {
         case EXIT_TAKE_PROFIT:
            return "Take Profit";
         case EXIT_STOP_LOSS:
            return "Stop Loss";
         case EXIT_TRAILING_STOP:
            return "Trailing Stop";
         case EXIT_OPPOSING_SIGNAL:
            return "Opposing Signal";
         case EXIT_HTF_REVERSAL:
            return "HTF Reversal";
         case EXIT_SESSION_END:
            return "Session End";
         case EXIT_NEWS_APPROACHING:
            return "News Approaching";
         case EXIT_TIME_LIMIT:
            return "Time Limit";
         case EXIT_MANUAL:
            return "Manual";
         default:
            return "None";
      }
   }

   //+------------------------------------------------------------------+
   //| Setters                                                          |
   //+------------------------------------------------------------------+
   void SetMaxHoldBars(int bars) { m_maxHoldBarsH1 = bars; }
   void SetNewsBuffer(int minutes) { m_newsBufferMinutes = minutes; }
   void EnableOpposingSignalExit(bool enable) { m_exitOnOpposingSignal = enable; }
   void EnableHTFReversalExit(bool enable) { m_exitOnHTFReversal = enable; }
   void SetSessionEndHour(int hour) { m_sessionEndHour = hour; }
};
