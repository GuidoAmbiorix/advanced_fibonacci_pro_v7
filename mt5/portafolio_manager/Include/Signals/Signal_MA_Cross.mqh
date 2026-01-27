//+------------------------------------------------------------------+
//|                                              Signal_MA_Cross.mqh |
//|          Example Strategy: Moving Average Crossover              |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

#include "..\SignalInterface.mqh"

class CSignal_MA_Cross : public CSignalStrategy
{
private:
   int m_fastPeriod;
   int m_slowPeriod;

public:
   CSignal_MA_Cross(int fast = 9, int slow = 21)
   {
      m_fastPeriod = fast;
      m_slowPeriod = slow;
   }
   
   string GetName() override { return "MA_Cross"; }

   int GetSignal(string symbol, ENUM_TIMEFRAMES timeframe) override
   {
      double maFast[], maSlow[];
      ArraySetAsSeries(maFast, true);
      ArraySetAsSeries(maSlow, true);
      
      int hFast = iMA(symbol, timeframe, m_fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      int hSlow = iMA(symbol, timeframe, m_slowPeriod, 0, MODE_SMA, PRICE_CLOSE);
      
      if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE) return 0;
      
      if(CopyBuffer(hFast, 0, 0, 2, maFast) < 2) return 0;
      if(CopyBuffer(hSlow, 0, 0, 2, maSlow) < 2) return 0;
      
      // Crossover Logic
      // Buy: Fast crosses above Slow (Current > Current, Prev <= Prev)
      if(maFast[0] > maSlow[0] && maFast[1] <= maSlow[1]) return 1;
      
      // Sell: Fast crosses below Slow
      if(maFast[0] < maSlow[0] && maFast[1] >= maSlow[1]) return -1;
      
      return 0;
   }
   
   double GetStopLoss(string symbol, int signalDir, double entryPrice) override
   {
      // ATR Based SL
      double atr = iATR(symbol, PERIOD_H1, 14, 0); // Handle needs management, simplify for now
      // Simple fallback if handle fails or just use tick size
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return (signalDir == 1) ? entryPrice - 500 * point : entryPrice + 500 * point; 
   }
   
   double GetTakeProfit(string symbol, int signalDir, double entryPrice) override
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return (signalDir == 1) ? entryPrice + 1000 * point : entryPrice - 1000 * point;
   }
};
