//+------------------------------------------------------------------+
//|                                        ExitStrategyConfig.mqh    |
//|                      Exit Strategy Configuration Defaults         |
//|                                  Copyright 2026, Infernal Portfolio Governor   |
//+------------------------------------------------------------------+
#ifndef EXIT_STRATEGY_CONFIG_MQH
#define EXIT_STRATEGY_CONFIG_MQH

#property copyright "Infernal Portfolio Governor"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| TRAILING STOP PARAMETERS                                          |
//+------------------------------------------------------------------+
const int    CFG_TRAILING_MODE = 1;             // 0=Off, 1=Runner, 2=Full
const double CFG_TRAIL_START_R = 2.0;           // Start trailing at R multiple
const double CFG_TRAIL_ATR_MULT = 1.2;          // Trail distance (ATR multiplier)

//+------------------------------------------------------------------+
//| PARTIAL TAKE PROFIT PARAMETERS                                   |
//+------------------------------------------------------------------+
const double CFG_PARTIAL_TP_R = 1.5;            // Partial TP at R multiple
const double CFG_PARTIAL_CLOSE_PERCENT = 40.0;  // Percentage to close (0-100)

//+------------------------------------------------------------------+
//| BREAK-EVEN PARAMETERS                                            |
//+------------------------------------------------------------------+
const double CFG_BE_THRESHOLD_R = 1.8;          // Move SL to BE at R multiple

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
//| EXIT TARGET LEVELS (R MULTIPLES)                                 |
//+------------------------------------------------------------------+
const double EXIT_R_SMALL = 1.0;                // Small target (1R)
const double EXIT_R_MEDIUM = 2.0;               // Medium target (2R)
const double EXIT_R_LARGE = 3.0;                // Large target (3R)
const double EXIT_R_RUNNER = 5.0;               // Runner target (5R+)

#endif
