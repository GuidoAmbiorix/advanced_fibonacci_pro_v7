//+------------------------------------------------------------------+
//|                                              SignalInterface.mqh |
//|          Standard Interface for Portfolio Strategy Modules       |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property strict

//+------------------------------------------------------------------+
//| Base Class for Signal Strategies                                  |
//+------------------------------------------------------------------+
class CSignalStrategy
{
public:
   // Virtual destructor
   virtual ~CSignalStrategy() {}
   
   // Main Signal Function
   // Returns: 1 (Buy), -1 (Sell), 0 (None)
   virtual int GetSignal(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      return 0; // Default: No signal
   }
   
   // Stop Loss Calculation
   virtual double GetStopLoss(string symbol, int signalDir, double entryPrice)
   {
      return 0.0; // Default: No SL (Dangerous!)
   }
   
   // Take Profit Calculation
   virtual double GetTakeProfit(string symbol, int signalDir, double entryPrice)
   {
      return 0.0; // Default: No TP
   }
   
   // Unique Name of Strategy
   virtual string GetName() { return "BaseStrategy"; }
};
