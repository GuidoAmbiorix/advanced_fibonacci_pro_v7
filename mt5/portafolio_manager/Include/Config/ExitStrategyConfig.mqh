//+------------------------------------------------------------------+
//|                                        ExitStrategyConfig.mqh    |
//|                      Exit Strategy Configuration Defaults         |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef EXIT_STRATEGY_CONFIG_MQH
#define EXIT_STRATEGY_CONFIG_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| TRAILING STOP PARAMETERS (H1 OPTIMIZED)                          |
//+------------------------------------------------------------------+
const int    CFG_TRAILING_MODE = 1;             // 0=Off, 1=Runner, 2=Full
const double CFG_TRAIL_START_R = 2.5;           // Start trailing at R multiple (H1: 2.0→2.5)
const double CFG_TRAIL_ATR_MULT = 1.5;          // Trail distance (ATR multiplier) (H1: 1.2→1.5)

//+------------------------------------------------------------------+
//| PARTIAL TAKE PROFIT PARAMETERS (H1 OPTIMIZED)                    |
//+------------------------------------------------------------------+
const double CFG_PARTIAL_TP_R = 2.0;            // Partial TP at R multiple (H1: 1.5→2.0)
const double CFG_PARTIAL_CLOSE_PERCENT = 40.0;  // Percentage to close (0-100)

//+------------------------------------------------------------------+
//| BREAK-EVEN PARAMETERS (H1 OPTIMIZED)                             |
//+------------------------------------------------------------------+
const double CFG_BE_THRESHOLD_R = 2.2;          // Move SL to BE at R multiple (H1: 1.8→2.2)

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                              |
//+------------------------------------------------------------------+
const int    CFG_MAX_POSITIONS = 3;             // Maximum concurrent positions

//+------------------------------------------------------------------+
//| ADD-ON PARAMETERS                                                |
//+------------------------------------------------------------------+
const bool   CFG_ENABLE_ADDONS = true;          // Enable add-on positions
const double CFG_ADDON_1_R = 1.5;               // First add-on at R multiple
const double CFG_ADDON_2_R = 2.5;               // Second add-on at R multiple

//+------------------------------------------------------------------+
//| EXIT TARGET LEVELS (R MULTIPLES) (H1 OPTIMIZED)                  |
//+------------------------------------------------------------------+
const double EXIT_R_SMALL = 1.0;                // Small target (1R)
const double EXIT_R_MEDIUM = 3.0;               // Medium target (3R) (H1: 2.0→3.0)
const double EXIT_R_LARGE = 4.0;                // Large target (4R) (H1: 3.0→4.0)
const double EXIT_R_RUNNER = 6.0;               // Runner target (6R+) (H1: 5.0→6.0)

#endif
