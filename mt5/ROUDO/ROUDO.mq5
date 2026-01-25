//+------------------------------------------------------------------+
//|                                                       ROUDO.mq5  |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
//|  THE TITAN SCALPER - ORO $500                                    |
//|  Arquitectura Modular Profesional                                |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"
#property version   "2.12"
#property strict
#property description "THE TITAN SCALPER - ORO $500"
#property description "Arquitectura Modular Profesional"

//+------------------------------------------------------------------+
//| Includes de Módulos                                              |
//+------------------------------------------------------------------+
#include "includes/R_Config.mqh"       // Configuración e inputs
#include "includes/R_Symbol.mqh"       // Gestión de símbolo y precios
#include "includes/R_Indicators.mqh"   // MACD, ATR, señales
#include "includes/R_Stats.mqh"        // Estadísticas y conteo
#include "includes/R_Risk.mqh"         // Gestión de riesgo
#include "includes/R_Orders.mqh"       // Gestión de órdenes y martingala
#include "includes/R_UI.mqh"           // Interfaz de usuario

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Inicializar símbolo
   if(!g_symbol_manager.Init()) {
      Print("ERROR: Fallo al inicializar gestor de símbolo");
      return INIT_FAILED;
   }

   // 2. Configurar Trade
   trade.SetExpertMagicNumber(MagicNumber_Hilo);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // 3. Inicializar indicadores
   if(!g_indicators.Init()) {
      Print("ERROR: Fallo al inicializar indicadores");
      return INIT_FAILED;
   }

   // 4. Mostrar mensaje de bienvenida
   g_ui.ShowInitMessage();

   Print("✓ ROUDO inicializado correctamente");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Función Principal OnTick                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Verificar condiciones de mercado
   if(!g_symbol_manager.CanTrade()) return;

   // 2. Verificar si se puede abrir nuevas posiciones
   if(!g_risk.CanOpenNewPosition()) {
      g_ui.DisplayInfo();
      return;
   }

   // 3. Obtener posiciones actuales
   int total_positions = g_stats.GetTotalPositions();

   // 4. Lógica de trading
   if(total_positions == 0) {
      // No hay posiciones: Buscar señal de entrada inicial
      g_orders.OpenInitialPosition();
   }
   else {
      // Hay posiciones: Gestionar martingala
      g_orders.ManageMartingale();
   }

   // 5. Actualizar interfaz
   g_ui.DisplayInfo();
}

//+------------------------------------------------------------------+
//| Función de Desinicialización                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   Print("ROUDO finalizado. Razón: ", reason);
}
//+------------------------------------------------------------------+
