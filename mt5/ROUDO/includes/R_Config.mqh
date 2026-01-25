//+------------------------------------------------------------------+
//|                                                     R_Config.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"
#property version   "2.12"

//+------------------------------------------------------------------+
//| Parámetros de Configuración                                      |
//+------------------------------------------------------------------+

//--- Lotes y Martingala
input double   Lots              = 0.01;   // Lote inicial (Recomendado para $500)
input double   LotExponent       = 1.50;   // Exponente de Multiplicación
input double   MaxLots           = 2.0;    // Lote máximo permitido
input double   TakeProfit        = 50.0;   // Meta en puntos (5 pips en Oro)

//--- Identificación
input int      MagicNumber_Hilo  = 11111;  // Número mágico del EA

//--- Meta Diaria y Riesgo
input double   MetaGananciaDiaria = 50.0;  // Ganancia diaria objetivo ($50)
input int      MaxOperacionesGrid = 10;    // Máximo de órdenes por red
input double   Min_Margin_Level   = 600.0; // Nivel de margen mínimo de seguridad

//--- Indicadores (ATR)
input int      ATR_Period         = 14;    // Periodo del ATR
input double   ATR_Multiplier     = 2.0;   // Distancia dinámica entre órdenes
input int      Max_Spread         = 40;    // Spread máximo permitido

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
//| Constantes del Sistema                                           |
//+------------------------------------------------------------------+
#define EA_NAME    "ROUDO"
#define EA_VERSION "2.12"
#define EA_MARKET  "ORO"
//+------------------------------------------------------------------+
