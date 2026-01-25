//+------------------------------------------------------------------+
//|                                                R_Config_GOD.mqh  |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                      ROUDO GOD MODE - Configuración Avanzada     |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"
#property version   "3.00"

//+------------------------------------------------------------------+
//| Parámetros GOD MODE - Sistema Martingale Profesional             |
//+------------------------------------------------------------------+

//=== LOTES Y MARTINGALE ===
input group "═══ LOTES Y MARTINGALE ═══"
input double   Lots                   = 0.01;   // Lote inicial (para $500)
input bool     UseFibonacciProgression = true;  // Usar progresión Fibonacci (recomendado)
input double   LotExponent            = 1.50;   // Exponente si no usa Fibonacci
input double   MaxLots                = 3.0;    // Lote máximo permitido
input double   TakeProfit             = 50.0;   // Take profit en puntos

//=== KILLZONES ICT ===
input group "═══ KILLZONES ICT ═══"
input bool     UseKillzones           = true;   // Activar filtro de killzones
input bool     TradeAsianKillzone     = false;  // Asian (19:00-21:00 EDT) - Baja volatilidad
input bool     TradeLondonOpen        = true;   // London Open (02:00-05:00 EDT) - Alta liquidez
input bool     TradeLondonClose       = false;  // London Close (10:00-12:00 EDT) - Profit taking
input bool     TradeNYOpen            = false;  // NY Open (07:00-10:00 EDT) - Solo overlap
input bool     TradeLondonNYOverlap   = true;   // London-NY Overlap (07:00-10:00 EDT) ⭐ MEJOR
input int      ServerTimeOffset       = 0;      // Offset del broker GMT (ej: GMT+2 = 2)

//=== TRAILING STOP ===
input group "═══ TRAILING STOP ═══"
input bool     UseTrailingStop        = true;   // Activar trailing stop
input ENUM_TRAILING_TYPE TrailingType = TRAILING_ATR; // Tipo de trailing
input double   TrailingActivation     = 20.0;   // Activar trailing en +X pips
input double   TrailingDistance       = 15.0;   // Distancia del trailing (si fixed)
input double   TrailingStep           = 10.0;   // Paso para step trailing
input double   ATR_TrailingMultiplier = 1.5;    // Multiplicador ATR para trailing

//=== BREAKEVEN ===
input group "═══ BREAKEVEN ═══"
input bool     UseBreakeven           = true;   // Activar breakeven automático
input double   BreakevenActivation    = 15.0;   // Activar breakeven en +X pips
input double   BreakevenOffset        = 5.0;    // Offset de protección (pips)

//=== PARTIAL TAKE PROFIT ===
input group "═══ PARTIAL TAKE PROFIT ═══"
input bool     UsePartialTP           = true;   // Activar partial TP
input double   TP1_Level              = 30.0;   // TP1: Nivel en pips
input double   TP1_Percent            = 30.0;   // TP1: Cerrar % de volumen
input double   TP2_Level              = 50.0;   // TP2: Nivel en pips
input double   TP2_Percent            = 40.0;   // TP2: Cerrar % de volumen
input double   TP3_Level              = 80.0;   // TP3: Nivel en pips
input double   TP3_Percent            = 30.0;   // TP3: Cerrar % de volumen

//=== GESTIÓN DE RIESGO ===
input group "═══ GESTIÓN DE RIESGO ═══"
input double   MetaGananciaDiaria     = 50.0;   // Ganancia diaria objetivo ($)
input double   MaxDailyDrawdown       = 10.0;   // Máximo drawdown diario (%)
input double   MaxDrawdownPerTrade    = 5.0;    // Máximo drawdown por trade (%)
input bool     StopOnDrawdownHit      = true;   // Detener EA si se alcanza DD
input int      MaxOperacionesGrid     = 8;      // Máximo de órdenes en grid (reducido)
input double   Min_Margin_Level       = 800.0;  // Nivel de margen mínimo (aumentado)

//=== INDICADORES ===
input group "═══ INDICADORES ═══"
input int      ATR_Period             = 14;     // Periodo del ATR
input double   ATR_Multiplier         = 2.5;    // Multiplicador ATR para grid (aumentado)
input int      Max_Spread             = 30;     // Spread máximo permitido (más estricto)
input bool     UseAdaptiveStep        = true;   // Usar espaciado adaptativo ATR

//=== DASHBOARD ===
input group "═══ DASHBOARD ═══"
input bool     ShowDashboard          = true;   // Mostrar dashboard visual
input bool     ShowKillzoneInfo       = true;   // Mostrar info de killzones
input bool     ShowSessionStats       = true;   // Mostrar estadísticas de sesión
input int      DashboardCorner        = 0;      // Esquina (0=superior izq, 1=sup der, 2=inf izq, 3=inf der)
input int      DashboardXOffset       = 10;     // Offset X en píxeles
input int      DashboardYOffset       = 10;     // Offset Y en píxeles

//=== IDENTIFICACIÓN ===
input group "═══ IDENTIFICACIÓN ═══"
input int      MagicNumber_Hilo       = 11111;  // Número mágico del EA

//+------------------------------------------------------------------+
//| Enumeraciones GOD MODE                                           |
//+------------------------------------------------------------------+

// Tipos de trailing stop
enum ENUM_TRAILING_TYPE {
   TRAILING_NONE,      // Sin trailing
   TRAILING_ATR,       // Basado en ATR (recomendado)
   TRAILING_STEP,      // Por pasos fijos
   TRAILING_PERCENT    // Porcentaje de profit
};

// Killzones ICT
enum ENUM_KILLZONE {
   KILLZONE_NONE,              // Fuera de killzone
   KILLZONE_ASIAN,             // Asian Session (19:00-21:00 EDT)
   KILLZONE_LONDON_OPEN,       // London Open (02:00-05:00 EDT)
   KILLZONE_LONDON_CLOSE,      // London Close (10:00-12:00 EDT)
   KILLZONE_NY_OPEN,           // NY Open (07:00-10:00 EDT)
   KILLZONE_OVERLAP_LONDON_NY  // Overlap London-NY ⭐ MEJOR
};

//+------------------------------------------------------------------+
//| Variables Globales de Clases MT5                                 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

CTrade         trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;

//+------------------------------------------------------------------+
//| Constantes del Sistema GOD                                       |
//+------------------------------------------------------------------+
#define EA_NAME         "ROUDO GOD MODE"
#define EA_VERSION      "3.00"
#define EA_MARKET       "ORO"
#define EA_ACCOUNT_SIZE 500

// Secuencia Fibonacci para progresión de lotes
double FIBONACCI_SEQUENCE[] = {
   1.0,  // Nivel 0 (inicial)
   1.2,  // Nivel 1
   1.5,  // Nivel 2
   2.0,  // Nivel 3
   2.5,  // Nivel 4
   3.2,  // Nivel 5
   4.0,  // Nivel 6
   5.0,  // Nivel 7
   6.5,  // Nivel 8 (max)
   8.0   // Nivel 9 (extremo - no recomendado)
};

// Colores para dashboard
#define COLOR_PROFIT    clrLimeGreen
#define COLOR_LOSS      clrCrimson
#define COLOR_NEUTRAL   clrGold
#define COLOR_KILLZONE  clrDodgerBlue
#define COLOR_WARNING   clrOrangeRed
#define COLOR_INFO      clrWhite
#define COLOR_PANEL_BG  C'20,20,30'

// Horarios de Killzones (EDT - Eastern Daylight Time)
// Nota: Ajustar según el servidor del broker usando ServerTimeOffset

#define ASIAN_START_HOUR      19  // 19:00 EDT
#define ASIAN_START_MINUTE    0
#define ASIAN_END_HOUR        21  // 21:00 EDT
#define ASIAN_END_MINUTE      0

#define LONDON_OPEN_START_HOUR   2  // 02:00 EDT
#define LONDON_OPEN_START_MINUTE 0
#define LONDON_OPEN_END_HOUR     5  // 05:00 EDT
#define LONDON_OPEN_END_MINUTE   0

#define LONDON_CLOSE_START_HOUR   10 // 10:00 EDT
#define LONDON_CLOSE_START_MINUTE 0
#define LONDON_CLOSE_END_HOUR     12 // 12:00 EDT
#define LONDON_CLOSE_END_MINUTE   0

#define NY_OPEN_START_HOUR    7  // 07:00 EDT
#define NY_OPEN_START_MINUTE  0
#define NY_OPEN_END_HOUR      10 // 10:00 EDT
#define NY_OPEN_END_MINUTE    0

// Overlap London-NY: 07:00-10:00 EDT (cuando ambas sesiones están activas)

//+------------------------------------------------------------------+
//| Configuración Recomendada para Diferentes Cuentas                |
//+------------------------------------------------------------------+

/*
╔════════════════════════════════════════════════════════════════╗
║         CONFIGURACIÓN RECOMENDADA POR TAMAÑO DE CUENTA         ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  CUENTA $500 (ACTUAL):                                         ║
║    - Lote inicial: 0.01                                        ║
║    - MaxLots: 3.0                                              ║
║    - MaxOperacionesGrid: 8                                     ║
║    - MetaGananciaDiaria: $50 (10% mensual)                     ║
║    - MaxDailyDrawdown: 10% ($50)                               ║
║                                                                ║
║  CUENTA $1,000:                                                ║
║    - Lote inicial: 0.02                                        ║
║    - MaxLots: 6.0                                              ║
║    - MaxOperacionesGrid: 10                                    ║
║    - MetaGananciaDiaria: $100                                  ║
║    - MaxDailyDrawdown: 10% ($100)                              ║
║                                                                ║
║  CUENTA $5,000:                                                ║
║    - Lote inicial: 0.10                                        ║
║    - MaxLots: 30.0                                             ║
║    - MaxOperacionesGrid: 12                                    ║
║    - MetaGananciaDiaria: $500                                  ║
║    - MaxDailyDrawdown: 10% ($500)                              ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
*/

//+------------------------------------------------------------------+
