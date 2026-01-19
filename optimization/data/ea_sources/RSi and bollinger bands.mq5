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
input double RiskPercent = 2.0;
input double ATRMultiplierSL = 1.5;
input double ATRMultiplierTP = 2.5;
input int ATRPeriod = 14;
input ulong MagicNumber = 101;
input double RiskRewardRatio = 2.0;

//--- Global variables
int BB_Handle, RSI_Handle, ATR_Handle;
double AccountRisk;
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

    // Initialize ATR
    ATR_Handle = iATR(_Symbol, _Period, ATRPeriod);

    // Check if handles are valid
    if (BB_Handle == INVALID_HANDLE || RSI_Handle == INVALID_HANDLE || ATR_Handle == INVALID_HANDLE) {
        Print("Error initializing indicators. Error code: ", GetLastError());
        return INIT_FAILED;
    }

    // Set account risk
    AccountRisk = ACCOUNT_BALANCE * RiskPercent * 100;

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
    // Get current RSI and BB values
    double rsiValue = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    double bbUpper[], bbLower[];
    int handleUpper = iBands(_Symbol, PERIOD_CURRENT, BB_Period, BB_Deviation, 0, PRICE_CLOSE);
    int handleLower = iBands(_Symbol, PERIOD_CURRENT, BB_Period, BB_Deviation, 0, PRICE_CLOSE);
    
    // Copy the upper and lower Bollinger Bands values for the current bar (index 0)
    CopyBuffer(handleUpper, 0, 0, 1, bbUpper); // 0 is for the upper band
    CopyBuffer(handleLower, 1, 0, 1, bbLower); // 1 is for the lower band

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
    // Calculate ATR-based SL and TP
    double atrValue = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
    double slPips = atrValue * ATRMultiplierSL; // SL pips based on ATR
    double tpPips = slPips * RiskRewardRatio;   // TP pips based on Risk-Reward Ratio

    // Calculate volume based on risk
    double volume = CalculateVolume(ACCOUNT_BALANCE, RiskPercent, slPips);

    // Prepare trade request and result structures
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    // Prepare trade request
    PrepareTradeRequest(request, tradeType, volume, slPips, tpPips);

    // Send trade request
    if (!OrderSend(request, result)) {
        Print("Trade could not be opened. Error code: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Prepare trade request                                            |
//+------------------------------------------------------------------+
void PrepareTradeRequest( MqlTradeRequest &request, string tradeType, double volume, double slPips, double tpPips) {
    double marketPrice = SymbolInfoDouble(_Symbol, tradeType == "BUY" ? SYMBOL_ASK : SYMBOL_BID);
    double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

    // Normalize SL and TP
    double normalizedSL = tradeType == "BUY" ? marketPrice - slPips * _Point : marketPrice + slPips * _Point;
    double normalizedTP = tradeType == "BUY" ? marketPrice + tpPips * _Point : marketPrice - tpPips * _Point;

    // Ensure SL and TP are not too close to the current price
    if (MathAbs(normalizedSL - marketPrice) < stopLevel) {
        normalizedSL = tradeType == "BUY" ? marketPrice - stopLevel : marketPrice + stopLevel;
    }
    if (MathAbs(normalizedTP - marketPrice) < stopLevel) {
        normalizedTP = tradeType == "BUY" ? marketPrice + stopLevel : marketPrice - stopLevel;
    }

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = volume;
    request.type = tradeType == "BUY" ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = marketPrice;
    request.sl = normalizedSL;
    request.tp = normalizedTP;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "BollingerRSI Bot";
}
//+------------------------------------------------------------------+
//| Calculate trading volume based on risk and SL                    |
//+------------------------------------------------------------------+
double CalculateVolume(double slPips)
{
    double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double riskPerPip = AccountRisk / slPips;
    return riskPerPip / pipValue;
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


//+------------------------------------------------------------------+
//| Calculate trading volume based on account balance, risk, and SL  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Calculate trading volume based on account balance, risk, and SL  |
//+------------------------------------------------------------------+
double CalculateVolume(double accountBalance, double riskPercent, double slPips) {
    double riskMoney = accountBalance * riskPercent / 100.0; // Amount of money to risk
    double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double slInMoney = slPips * pipValue; // Stop loss in monetary terms
    double volume = riskMoney / slInMoney; // Volume based on risk and SL

    // Adjust the volume to the nearest allowed volume step
    double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    // Normalize volume to the nearest step
    volume = MathMax(minVolume, MathMin(maxVolume, volume));
    int steps = MathRound(volume / volumeStep);
    volume = steps * volumeStep;

    // Normalizing the volume (assuming 2 decimal places for volume, adjust if needed)
    volume = NormalizeDouble(volume, 2);

    return volume;
}
