//+------------------------------------------------------------------+
//|                                           FibonacciConfig.mqh    |
//|                         Fibonacci Configuration Defaults          |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef FIBONACCI_CONFIG_MQH
#define FIBONACCI_CONFIG_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| FIBONACCI PARAMETERS                                              |
//| These define the Fibonacci retracement levels and swing analysis |
//+------------------------------------------------------------------+

// Swing Detection
const int    CFG_FIB_SWING_LOOKBACK = 20;      // Bars to look back for swing high/low

// Fibonacci Retracement Levels
const double CFG_FIB_LEVEL_LOW = 0.618;         // Lower Fib level (61.8%)
const double CFG_FIB_LEVEL_HIGH = 0.786;        // Upper Fib level (78.6%)

// Zone Tolerance
const double CFG_FIB_ZONE_TOLERANCE = 0.25;     // ATR multiplier for zone width

// Minimum Swing Range
const double CFG_FIB_MIN_SWING_ATR = 1.5;       // Minimum swing size in ATR multiples

//+------------------------------------------------------------------+
//| COMMON FIBONACCI LEVELS (Reference)                              |
//+------------------------------------------------------------------+
const double FIB_LEVEL_0 = 0.000;               // 0%
const double FIB_LEVEL_236 = 0.236;             // 23.6%
const double FIB_LEVEL_382 = 0.382;             // 38.2%
const double FIB_LEVEL_500 = 0.500;             // 50%
const double FIB_LEVEL_618 = 0.618;             // 61.8% (Golden Ratio)
const double FIB_LEVEL_786 = 0.786;             // 78.6%
const double FIB_LEVEL_886 = 0.886;             // 88.6%
const double FIB_LEVEL_1000 = 1.000;            // 100%

//+------------------------------------------------------------------+
//| FIBONACCI EXTENSION LEVELS (For Targets)                         |
//+------------------------------------------------------------------+
const double FIB_EXT_1272 = 1.272;              // 127.2% extension
const double FIB_EXT_1414 = 1.414;              // 141.4% extension (√2)
const double FIB_EXT_1618 = 1.618;              // 161.8% extension (Golden Ratio)
const double FIB_EXT_2000 = 2.000;              // 200% extension
const double FIB_EXT_2618 = 2.618;              // 261.8% extension

#endif
