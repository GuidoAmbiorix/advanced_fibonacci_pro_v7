//+------------------------------------------------------------------+
//|                                               SMCConfig.mqh      |
//|                     Smart Money Concepts Configuration            |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef SMC_CONFIG_MQH
#define SMC_CONFIG_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| SMART MONEY CONCEPTS PARAMETERS                                   |
//+------------------------------------------------------------------+
const bool   CFG_USE_SMC = true;                // Enable SMC analysis

//+------------------------------------------------------------------+
//| STRUCTURE BREAK PARAMETERS                                        |
//+------------------------------------------------------------------+
const int    CFG_SMC_SWING_LOOKBACK = 20;       // Swing lookback bars
const int    CFG_SMC_BOS_LOOKBACK = 50;         // Break of Structure lookback

//+------------------------------------------------------------------+
//| ORDER BLOCK PARAMETERS                                            |
//+------------------------------------------------------------------+
const int    CFG_SMC_OB_LOOKBACK = 50;          // Order block lookback bars
const int    CFG_SMC_OB_VALIDITY = 5;           // Order block validity period
const double CFG_SMC_MIN_IMPULSE_ATR = 2.0;     // Min impulse size (ATR mult)

//+------------------------------------------------------------------+
//| FAIR VALUE GAP (FVG) PARAMETERS                                  |
//+------------------------------------------------------------------+
const int    CFG_SMC_FVG_LOOKBACK = 50;         // FVG lookback bars
const int    CFG_SMC_FVG_VALIDITY = 10;         // FVG validity period
const double CFG_SMC_MIN_FVG_ATR = 0.5;         // Min FVG size (ATR mult)

//+------------------------------------------------------------------+
//| LIQUIDITY SWEEP PARAMETERS                                        |
//+------------------------------------------------------------------+
const int    CFG_SMC_LIQ_LOOKBACK = 20;         // Liquidity lookback bars
const double CFG_SMC_LIQ_BUFFER = 0.1;          // Buffer for sweep detection (ATR)

//+------------------------------------------------------------------+
//| CONFLUENCE WEIGHTS                                                |
//+------------------------------------------------------------------+
const double CFG_SMC_STRUCTURE_WEIGHT = 1.0;    // Structure break weight
const double CFG_SMC_OB_WEIGHT = 1.5;           // Order block weight
const double CFG_SMC_FVG_WEIGHT = 1.0;          // FVG weight
const double CFG_SMC_LIQ_WEIGHT = 1.5;          // Liquidity sweep weight

#endif
