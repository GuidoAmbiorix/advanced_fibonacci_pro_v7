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
//| STRUCTURE BREAK PARAMETERS (H1 OPTIMIZED)                        |
//+------------------------------------------------------------------+
const int    CFG_SMC_SWING_LOOKBACK = 45;       // Swing lookback bars (H1: 20→45)
const int    CFG_SMC_BOS_LOOKBACK = 80;         // Break of Structure lookback (H1: 50→80)

//+------------------------------------------------------------------+
//| ORDER BLOCK PARAMETERS (H1 OPTIMIZED)                            |
//+------------------------------------------------------------------+
const int    CFG_SMC_OB_LOOKBACK = 90;          // Order block lookback bars (H1: 50→90)
const int    CFG_SMC_OB_VALIDITY = 5;           // Order block validity period
const double CFG_SMC_MIN_IMPULSE_ATR = 2.5;     // Min impulse size (ATR mult) (H1: 2.0→2.5)

//+------------------------------------------------------------------+
//| FAIR VALUE GAP (FVG) PARAMETERS (H1 OPTIMIZED)                   |
//+------------------------------------------------------------------+
const int    CFG_SMC_FVG_LOOKBACK = 80;         // FVG lookback bars (H1: 50→80)
const int    CFG_SMC_FVG_VALIDITY = 10;         // FVG validity period
const double CFG_SMC_MIN_FVG_ATR = 0.8;         // Min FVG size (ATR mult) (H1: 0.5→0.8)

//+------------------------------------------------------------------+
//| LIQUIDITY SWEEP PARAMETERS (H1 OPTIMIZED)                        |
//+------------------------------------------------------------------+
const int    CFG_SMC_LIQ_LOOKBACK = 35;         // Liquidity lookback bars (H1: 20→35)
const double CFG_SMC_LIQ_BUFFER = 0.1;          // Buffer for sweep detection (ATR)

//+------------------------------------------------------------------+
//| CONFLUENCE WEIGHTS                                                |
//+------------------------------------------------------------------+
const double CFG_SMC_STRUCTURE_WEIGHT = 1.0;    // Structure break weight
const double CFG_SMC_OB_WEIGHT = 1.5;           // Order block weight
const double CFG_SMC_FVG_WEIGHT = 1.0;          // FVG weight
const double CFG_SMC_LIQ_WEIGHT = 1.5;          // Liquidity sweep weight

#endif
