//+------------------------------------------------------------------+
//|                                       BollingerRSI_TradingBot.mq5|
//|                        Copyright 2022, Your Name Here            |
//|                                                                  |
//+------------------------------------------------------------------+

#property copyright "Copyright 2022, Your Name Here"
#property description "EA based on Bollinger Bands and RSI"
#property version   "1.0"
#property strict


//--- Input parameters
input int RSI_Period = 14;
input int BB_Period = 20;
input double BB_Deviation = 2.0;
input ulong MagicNumber = 101;
input double MaxDrawdownPercent = 20.0; // Maximum drawdown percentage
input double LotSize = 0.1; // User-defined volume
input double StopLoss = 50;  // User-defined stop loss in points
input double TakeProfit = 100; // User-defined take profit in points

//--- Global variables
int BB_Handle, RSI_Handle, ATR_Handle;
double PeakBalance = 0, MaxAllowedDrawdown;
datetime lastBarTime;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize Bollinger Bands
    BB_Handle = iBands(_Symbol, _Period, BB_Period, 0, BB_Deviation, PRICE_CLOSE);

    // Initialize RSI
    RSI_Handle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);

    // Set initial values for peak balance
    PeakBalance = ACCOUNT_BALANCE;
    MaxAllowedDrawdown = PeakBalance * (1 - (MaxDrawdownPercent / 100));
    
    CalculateStopLevels();

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Deinitialization code
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update peak balance
    if (ACCOUNT_BALANCE > PeakBalance) {
        PeakBalance = ACCOUNT_BALANCE;
        MaxAllowedDrawdown = PeakBalance * (1 - (MaxDrawdownPercent / 100));
    }

    // Check for drawdown
    if (ACCOUNT_BALANCE < MaxAllowedDrawdown) {
        Print("Maximum drawdown reached. Halting trading.");
        return;
    }

    // Check for new bar
    if (lastBarTime != iTime(_Symbol, _Period, 0)) {
        lastBarTime = iTime(_Symbol, _Period, 0);

        // Trading logic
        ExecuteTradingLogic();
    }
}

//+------------------------------------------------------------------+
//| Trading logic                                                    |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
    // Get current RSI values
    double rsiValues[];
    ArraySetAsSeries(rsiValues, true);
    CopyBuffer(RSI_Handle, 0, 0, 1, rsiValues);
    double rsiValue = rsiValues[0]; // Current RSI value

    // Get current Bollinger Bands values
    double bbUpper[], bbLower[];
    ArraySetAsSeries(bbUpper, true);
    ArraySetAsSeries(bbLower, true);
    CopyBuffer(BB_Handle, 1, 0, 1, bbUpper); // Upper Band
    CopyBuffer(BB_Handle, 2, 0, 1, bbLower); // Lower Band

    // Trading signals based on RSI and Bollinger Bands
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (rsiValue > 70 && currentPrice >= bbUpper[0]) {
        // Sell signal
        OpenTrade("SELL");
    } else if (rsiValue < 30 && currentPrice <= bbLower[0]) {
        // Buy signal
        OpenTrade("BUY");
    }

    // Manage existing trades
    ManageTrades();
}

//+------------------------------------------------------------------+
//| Open a new trade                                                 |
//+------------------------------------------------------------------+
void OpenTrade(string tradeType)
{
    // Prepare trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    PrepareTradeRequest(request, tradeType);

    // Send trade request
    if (!OrderSend(request, result)) {
        Print("Trade could not be opened. Error code: ", GetLastError());
    }
}
//+------------------------------------------------------------------+
//| Prepare trade request                                            |
//+------------------------------------------------------------------+
void PrepareTradeRequest(MqlTradeRequest &request, string tradeType) {
    double marketPrice = SymbolInfoDouble(_Symbol, tradeType == "BUY" ? SYMBOL_ASK : SYMBOL_BID);

  request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = tradeType == "BUY" ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = marketPrice;
    request.sl = tradeType == "BUY" ? marketPrice - StopLoss * _Point : marketPrice + StopLoss * _Point;
    request.tp = tradeType == "BUY" ? marketPrice + TakeProfit * _Point : marketPrice - TakeProfit * _Point;
    request.magic = MagicNumber;
    request.comment = "BollingerRSI Bot";
}



//+------------------------------------------------------------------+
//| Manage existing trades                                           |
//+------------------------------------------------------------------+
void ManageTrades()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            // Check if the position belongs to our EA
            if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentProfit = PositionGetDouble(POSITION_PROFIT);
                int type = PositionGetInteger(POSITION_TYPE);

                // Apply trailing stop loss
                ApplyTrailingStop(ticket, type, openPrice, currentProfit);

                // Apply break-even
                ApplyBreakEven(ticket, type, openPrice, currentProfit);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Apply trailing stop loss                                         |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, int type, double openPrice, double currentProfit)
{
    // Define trailing stop criteria
    double TrailingStop = 15.0; // Trailing stop in pips
    double TrailingStep = 5.0;  // Step of trailing stop in pips

    if (currentProfit > 0) {
        double trailDistance = TrailingStop * _Point;
        double trailStep = TrailingStep * _Point;
        double currentSL = PositionGetDouble(POSITION_SL);

        // Calculate new SL based on trailing criteria
        double newSL = (type == POSITION_TYPE_BUY) ?
            (openPrice + currentProfit - trailDistance) :
            (openPrice - currentProfit + trailDistance);

        if ((type == POSITION_TYPE_BUY && newSL > currentSL + trailStep) ||
            (type == POSITION_TYPE_SELL && newSL < currentSL - trailStep)) {
            // Modify SL of the position
            ModifyPosition(ticket, newSL);
        }
    }
}

//+------------------------------------------------------------------+
//| Apply break-even                                                 |
//+------------------------------------------------------------------+
void ApplyBreakEven(ulong ticket, int type, double openPrice, double currentProfit)
{
    // Define break-even criteria
    double BreakEvenProfit = 10.0; // Break-even activation in pips

    if (currentProfit > BreakEvenProfit * _Point) {
        double newSL = openPrice; // Set new SL to open price for break-even

        // Modify SL of the position
        ModifyPosition(ticket, newSL);
    }
}

//+------------------------------------------------------------------+
//| Modify position SL                                               |
//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double newSL)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP); // Keep existing TP
    request.symbol = _Symbol;
    request.magic = MagicNumber;

    // Send request to modify the position
    if (!OrderSend(request, result)) {
        Print("Error modifying position: ", GetLastError());
    }
}





// Function to calculate and print the minimum and maximum stop levels
void CalculateStopLevels()
{
    // Minimum stop level as per broker's conditions
    int minStopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double minStopLevelPrice = minStopLevelPoints * _Point;
    Print("Minimum Stop Level for ", _Symbol, ": ", minStopLevelPoints, " points (", minStopLevelPrice, " in price units)");

    // Example of a maximum stop level based on risk management
    // For instance, not risking more than 3% of account balance on a single trade
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double maxRiskPerTrade = 15; // 3% of account balance
    double maxRiskInPriceUnits = (accountBalance * maxRiskPerTrade) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

    Print("Hypothetical Maximum Stop Level based on 3% of account balance: ", maxRiskInPriceUnits, " in price units");
}