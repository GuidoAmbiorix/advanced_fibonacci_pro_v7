//+------------------------------------------------------------------+
//|                                          IndicatorConfig.mqh     |
//|                        Indicator Configuration Defaults           |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef INDICATOR_CONFIG_MQH
#define INDICATOR_CONFIG_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| RSI (RELATIVE STRENGTH INDEX) PARAMETERS                         |
//+------------------------------------------------------------------+
const int    CFG_RSI_PERIOD = 14;               // RSI calculation period
const int    CFG_RSI_OVERSOLD = 45;             // Oversold level (buy zone)
const int    CFG_RSI_OVERBOUGHT = 55;           // Overbought level (sell zone)
const bool   CFG_RSI_USE_MOMENTUM = true;       // Use RSI momentum confirmation

// Traditional RSI levels for reference
const int    RSI_TRADITIONAL_OVERSOLD = 30;     // Traditional oversold
const int    RSI_TRADITIONAL_OVERBOUGHT = 70;   // Traditional overbought

//+------------------------------------------------------------------+
//| EMA (EXPONENTIAL MOVING AVERAGE) PARAMETERS                      |
//+------------------------------------------------------------------+
const int    CFG_EMA_PERIOD = 200;              // EMA period (trend filter)
const bool   CFG_EMA_USE_TREND_FILTER = true;   // Enable EMA trend filtering
const double CFG_EMA_MIN_SLOPE = 0.1;           // Minimum slope (ATR multiplier)

// Common EMA periods for reference
const int    EMA_FAST = 20;                     // Fast EMA
const int    EMA_MEDIUM = 50;                   // Medium EMA
const int    EMA_SLOW = 200;                    // Slow EMA (long-term trend)

//+------------------------------------------------------------------+
//| ATR (AVERAGE TRUE RANGE) PARAMETERS                              |
//+------------------------------------------------------------------+
const int    CFG_ATR_PERIOD = 14;               // ATR calculation period
const int    CFG_ATR_MA_PERIOD = 20;            // ATR moving average period

//+------------------------------------------------------------------+
//| CHOP FILTER (CONSOLIDATION DETECTION)                            |
//+------------------------------------------------------------------+
const bool   CFG_USE_CHOP_FILTER = true;        // Enable chop filter
const double CFG_CHOP_THRESHOLD = 0.75;         // ATR ratio threshold (0.75 = 75%)

//+------------------------------------------------------------------+
//| DISPLACEMENT FILTER                                              |
//+------------------------------------------------------------------+
const bool   CFG_USE_DISPLACEMENT = true;       // Enable displacement filter
const double CFG_DISPLACEMENT_ATR = 1.2;        // Min candle size (ATR multiplier)
const int    CFG_DISPLACEMENT_LOOKBACK = 5;     // Bars to look back

//+------------------------------------------------------------------+
//| SPREAD FILTER                                                    |
//+------------------------------------------------------------------+
const int    CFG_MAX_SPREAD_POINTS = 50;        // Maximum allowed spread in points

#endif
