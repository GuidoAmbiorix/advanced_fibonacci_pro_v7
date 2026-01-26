//+------------------------------------------------------------------+
//|                                              R_Config_MICRO.mqh  |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|              MICRO ACCOUNT - Para cuentas pequeñas $100-$500     |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"
#property version   "3.01"

//+------------------------------------------------------------------+
//| Enumeraciones (DEBEN IR PRIMERO)                                 |
//+------------------------------------------------------------------+

enum ENUM_TRAILING_TYPE {
   TRAILING_NONE,
   TRAILING_ATR,
   TRAILING_STEP,
   TRAILING_PERCENT
};

enum ENUM_KILLZONE {
   KILLZONE_NONE,
   KILLZONE_ASIAN,
   KILLZONE_LONDON_OPEN,
   KILLZONE_LONDON_CLOSE,
   KILLZONE_NY_OPEN,
   KILLZONE_OVERLAP_LONDON_NY
};

//+------------------------------------------------------------------+
//| Parámetros MICRO ACCOUNT - Ultra Conservador                     |
//+------------------------------------------------------------------+

//=== LOTES Y MARTINGALE ===
input group "═══ LOTES Y MARTINGALE (MICRO) ═══"
input double   Lots              = 0.01;    // Lote inicial MICRO
input bool     UseAutoLotSize    = true;    // 🆕 Auto-calcular lote según equity
input double   RiskPercentPerTrade = 2.0;   // 🆕 Riesgo % por trade (si auto)
input bool     UseFibonacciProgression = false; // 🆕 DESACTIVADO para micro
input double   LotMultiplier     = 1.2;     // 🆕 Multiplicador conservador (1.2x vs 1.5x)
input double   MaxLots           = 0.05;    // 🆕 REDUCIDO drásticamente
input double   TakeProfit        = 80.0;    // 🆕 AUMENTADO para mejor RR

//=== KILLZONES ICT ===
input group "═══ KILLZONES ICT ═══"
input bool     UseKillzones           = true;
input bool     TradeAsianKillzone     = false;
input bool     TradeLondonOpen        = true;
input bool     TradeLondonClose       = false;
input bool     TradeNYOpen            = false;
input bool     TradeLondonNYOverlap   = true;
input int      ServerTimeOffset       = 0;

//=== TRAILING STOP ===
input group "═══ TRAILING STOP ═══"
input bool     UseTrailingStop        = true;
input ENUM_TRAILING_TYPE TrailingType = TRAILING_ATR;
input double   TrailingActivation     = 30.0;   // 🆕 AUMENTADO (más conservador)
input double   TrailingDistance       = 20.0;
input double   TrailingStep           = 15.0;
input double   ATR_TrailingMultiplier = 2.0;    // 🆕 AUMENTADO

//=== BREAKEVEN ===
input group "═══ BREAKEVEN ═══"
input bool     UseBreakeven           = true;
input double   BreakevenActivation    = 20.0;   // 🆕 AUMENTADO
input double   BreakevenOffset        = 8.0;    // 🆕 AUMENTADO

//=== PARTIAL TAKE PROFIT ===
input group "═══ PARTIAL TAKE PROFIT ═══"
input bool     UsePartialTP           = true;
input double   TP1_Level              = 40.0;   // 🆕 AUMENTADO
input double   TP1_Percent            = 40.0;   // 🆕 Cerrar MÁS temprano
input double   TP2_Level              = 70.0;   // 🆕 AUMENTADO
input double   TP2_Percent            = 40.0;
input double   TP3_Level              = 100.0;  // 🆕 AUMENTADO
input double   TP3_Percent            = 20.0;

//=== GESTIÓN DE RIESGO (CRÍTICO PARA MICRO) ===
input group "═══ GESTIÓN DE RIESGO ═══"
input double   MetaGananciaDiaria     = 20.0;   // 🆕 REDUCIDO a $20 (realista)
input double   MaxDailyDrawdown       = 8.0;    // 🆕 REDUCIDO a 8%
input double   MaxDrawdownPerTrade    = 4.0;    // 🆕 REDUCIDO a 4%
input bool     StopOnDrawdownHit      = true;
input int      MaxOperacionesGrid     = 4;      // 🆕 REDUCIDO a 4 (vs 8)
input double   Min_Margin_Level       = 1000.0; // 🆕 AUMENTADO a 1000%
input double   Min_FreeMargin_Percent = 50.0;   // 🆕 Min 50% free margin

//=== INDICADORES ===
input group "═══ INDICADORES ═══"
input int      ATR_Period             = 14;
input double   ATR_Multiplier         = 3.0;    // 🆕 AUMENTADO (más espaciado)
input int      Max_Spread             = 25;     // 🆕 Más estricto
input bool     UseAdaptiveStep        = true;

//=== DASHBOARD ===
input group "═══ DASHBOARD ═══"
input bool     Enable_Dashboard       = true;
input bool     Enable_KillzoneInfo    = true;
input bool     Enable_SessionStats    = true;
input int      DashboardCorner        = 0;
input int      DashboardXOffset       = 10;
input int      DashboardYOffset       = 10;

//=== IDENTIFICACIÓN ===
input group "═══ IDENTIFICACIÓN ═══"
input int      MagicNumber_Hilo       = 11111;

//+------------------------------------------------------------------+
//| Variables Globales                                                |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

CTrade         trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;

//+------------------------------------------------------------------+
//| Constantes MICRO                                                  |
//+------------------------------------------------------------------+
#define EA_NAME         "ROUDO MICRO"
#define EA_VERSION      "3.01"
#define EA_MARKET       "ORO"
#define EA_ACCOUNT_SIZE 500

// 🆕 Progresión ULTRA CONSERVADORA para cuentas pequeñas
// En lugar de Fibonacci agresivo, usar multiplicador lineal bajo
double MICRO_PROGRESSION[] = {
   1.0,  // Nivel 0: 0.01
   1.2,  // Nivel 1: 0.012 (solo +20%)
   1.4,  // Nivel 2: 0.014 (+40%)
   1.7,  // Nivel 3: 0.017 (+70%)
   2.0   // Nivel 4: 0.02  (MÁXIMO - solo 2x)
};

// Colores
#define COLOR_PROFIT    clrLimeGreen
#define COLOR_LOSS      clrCrimson
#define COLOR_NEUTRAL   clrGold
#define COLOR_KILLZONE  clrDodgerBlue
#define COLOR_WARNING   clrOrangeRed
#define COLOR_INFO      clrWhite
#define COLOR_PANEL_BG  C'20,20,30'

// Killzones horarios (EDT)
#define ASIAN_START_HOUR      19
#define ASIAN_START_MINUTE    0
#define ASIAN_END_HOUR        21
#define ASIAN_END_MINUTE      0

#define LONDON_OPEN_START_HOUR   2
#define LONDON_OPEN_START_MINUTE 0
#define LONDON_OPEN_END_HOUR     5
#define LONDON_OPEN_END_MINUTE   0

#define LONDON_CLOSE_START_HOUR   10
#define LONDON_CLOSE_START_MINUTE 0
#define LONDON_CLOSE_END_HOUR     12
#define LONDON_CLOSE_END_MINUTE   0

#define NY_OPEN_START_HOUR    7
#define NY_OPEN_START_MINUTE  0
#define NY_OPEN_END_HOUR      10
#define NY_OPEN_END_MINUTE    0

//+------------------------------------------------------------------+
