//+------------------------------------------------------------------+
//|                                                   ROUDO_GOD.mq5  |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
//|  ROUDO GOD MODE v3.0 - THE TITAN SCALPER                         |
//|  Professional Grade Expert Advisor                               |
//|  Arquitectura Modular con Killzones ICT                          |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"
#property version   "3.00"
#property strict
#property description "ROUDO GOD MODE - THE TITAN SCALPER"
#property description "Professional EA with ICT Killzones, Fibonacci Martingale"
#property description "Trailing Stop, Breakeven, Partial TP, Drawdown Control"

//+------------------------------------------------------------------+
//| Includes de Módulos GOD                                          |
//+------------------------------------------------------------------+
#include "includes/R_Config_GOD.mqh"    // Configuración GOD Mode
#include "includes/R_Symbol.mqh"        // Gestión de símbolo
#include "includes/R_Indicators.mqh"    // MACD, ATR
#include "includes/R_Stats.mqh"         // Estadísticas
#include "includes/R_Killzones.mqh"     // 🆕 ICT Killzones
#include "includes/R_Drawdown.mqh"      // 🆕 Control de drawdown
#include "includes/R_Risk.mqh"          // Gestión de riesgo
#include "includes/R_Breakeven.mqh"     // 🆕 Breakeven automático
#include "includes/R_TrailingStop.mqh"  // 🆕 Trailing stop
#include "includes/R_PartialTP.mqh"     // 🆕 Partial take profits
#include "includes/R_Orders.mqh"        // Gestión de órdenes
#include "includes/R_MartingalePro.mqh" // 🆕 Martingale Fibonacci (BEFORE Dashboard!)
#include "includes/R_Dashboard.mqh"     // 🆕 Dashboard visual (uses g_martingale_pro)
#include "includes/R_UI.mqh"            // UI base

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║                    ROUDO GOD MODE v3.0                     ║");
   Print("║                  THE TITAN SCALPER PRO                     ║");
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  🚀 Inicializando sistema profesional...                  ║");
   Print("╚════════════════════════════════════════════════════════════╝");

   // 1. Inicializar símbolo
   if(!g_symbol_manager.Init()) {
      Print("❌ ERROR: Fallo al inicializar gestor de símbolo");
      return INIT_FAILED;
   }
   Print("✓ Símbolo inicializado: ", _Symbol);

   // 2. Configurar Trade
   trade.SetExpertMagicNumber(MagicNumber_Hilo);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   Print("✓ Trade configurado (Magic: ", MagicNumber_Hilo, ")");

   // 3. Inicializar indicadores
   if(!g_indicators.Init()) {
      Print("❌ ERROR: Fallo al inicializar indicadores");
      return INIT_FAILED;
   }
   Print("✓ Indicadores inicializados (MACD M1, ATR ", ATR_Period, ")");

   // 4. Mostrar configuración
   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║  CONFIGURACIÓN GOD MODE                                    ║");
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  Lote inicial: ", DoubleToString(Lots, 2));
   Print("║  Progresión: ", (UseFibonacciProgression ? "Fibonacci ⭐" : "Exponencial"));
   Print("║  Max Lotes: ", DoubleToString(MaxLots, 2));
   Print("║  Grid Limit: ", MaxOperacionesGrid);
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  🕐 KILLZONES ICT                                          ║");
   Print("║  Sistema: ", (UseKillzones ? "ACTIVO ✓" : "DESACTIVADO"));

   if(UseKillzones) {
      Print("║  London-NY Overlap: ", (TradeLondonNYOverlap ? "SI ⭐" : "NO"));
      Print("║  London Open: ", (TradeLondonOpen ? "SI" : "NO"));
      Print("║  NY Open: ", (TradeNYOpen ? "SI" : "NO"));
      Print("║  Asian: ", (TradeAsianKillzone ? "SI" : "NO"));
   }

   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  🛡️ PROTECCIONES                                           ║");
   Print("║  Trailing Stop: ", (UseTrailingStop ? "ACTIVO (" + EnumToString(TrailingType) + ")" : "OFF"));
   Print("║  Breakeven: ", (UseBreakeven ? "ACTIVO (+" + DoubleToString(BreakevenActivation,1) + " pips)" : "OFF"));
   Print("║  Partial TP: ", (UsePartialTP ? "ACTIVO (3 niveles)" : "OFF"));
   Print("║  Max DD Diario: ", DoubleToString(MaxDailyDrawdown, 1), "%");
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  🎯 OBJETIVOS                                              ║");
   Print("║  Meta Diaria: $", DoubleToString(MetaGananciaDiaria, 2));
   Print("║  Max Drawdown: ", DoubleToString(MaxDailyDrawdown, 1), "%");
   Print("║  Margen Min: ", DoubleToString(Min_Margin_Level, 0), "%");
   Print("╚════════════════════════════════════════════════════════════╝");

   // 5. Log inicial de killzone
   g_killzones.LogKillzoneChange();

   Print("");
   Print("🚀 ROUDO GOD MODE v3.0 LISTO PARA OPERAR");
   Print("");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Función Principal OnTick                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Reset diario (verificar cambio de día)
   g_drawdown.DailyReset();

   // 2. Verificar condiciones básicas de mercado
   if(!g_symbol_manager.CanTrade()) return;

   // 3. Verificar killzones (si está habilitado)
   if(!g_killzones.CanTradeNow()) {
      g_dashboard.ShowDashboard();
      return;
   }

   // 4. Verificar drawdown
   if(!g_drawdown.CanContinueTrading()) {
      g_dashboard.ShowDashboard();
      return;
   }

   // 5. Verificar meta diaria
   if(!g_risk.CanOpenNewPosition()) {
      g_dashboard.ShowDashboard();
      return;
   }

   // 6. Gestión de protecciones (aplicar primero)
   g_breakeven.CheckBreakeven();       // Mover a breakeven si aplica
   g_trailing.UpdateTrailingStop();     // Actualizar trailing stops
   g_partial_tp.CheckPartialTakeProfit(); // Ejecutar partial TPs

   // 7. Obtener posiciones actuales
   int total_positions = g_stats.GetTotalPositions();

   // 8. Lógica de trading
   if(total_positions == 0) {
      // No hay posiciones: Buscar señal de entrada inicial
      g_orders.OpenInitialPosition();
   }
   else {
      // Hay posiciones: Gestionar grid martingale profesional
      g_martingale_pro.SmartGridManagement();
   }

   // 9. Log de cambios de killzone
   g_killzones.LogKillzoneChange();

   // 10. Actualizar dashboard
   g_dashboard.ShowDashboard();
}

//+------------------------------------------------------------------+
//| Función de Desinicialización                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");

   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║  ROUDO GOD MODE FINALIZADO                                 ║");
   Print("╠════════════════════════════════════════════════════════════╣");

   string reason_text = "";
   switch(reason) {
      case REASON_PROGRAM:     reason_text = "EA detenido manualmente"; break;
      case REASON_REMOVE:      reason_text = "EA removido del gráfico"; break;
      case REASON_RECOMPILE:   reason_text = "EA recompilado"; break;
      case REASON_CHARTCHANGE: reason_text = "Cambio de símbolo/timeframe"; break;
      case REASON_CHARTCLOSE:  reason_text = "Gráfico cerrado"; break;
      case REASON_PARAMETERS:  reason_text = "Parámetros modificados"; break;
      case REASON_ACCOUNT:     reason_text = "Cambio de cuenta"; break;
      default:                 reason_text = "Razón desconocida (" + IntegerToString(reason) + ")"; break;
   }

   Print("║  Razón: ", reason_text);
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  📊 RESUMEN DE SESIÓN                                      ║");

   double daily_profit = g_stats.GetDailyProfit();
   Print("║  Profit del día: $", DoubleToString(daily_profit, 2));
   Print("║  Balance final: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));

   int total_positions = g_stats.GetTotalPositions();
   Print("║  Posiciones abiertas: ", total_positions);

   if(total_positions > 0) {
      Print("║  ⚠️ ADVERTENCIA: Hay ", total_positions, " posiciones abiertas");
   }

   Print("╚════════════════════════════════════════════════════════════╝");
   Print("");
   Print("Gracias por usar ROUDO GOD MODE v3.0");
   Print("THE TITAN SCALPER - Professional Trading System");
}

//+------------------------------------------------------------------+
//| Función OnTimer (opcional - para monitoreo)                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Puede usarse para enviar notificaciones periódicas
   // o realizar tareas de mantenimiento
}

//+------------------------------------------------------------------+
//| Función OnTrade (opcional - para logging)                        |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Se ejecuta cuando hay cambios en posiciones
   // Útil para logging detallado
}
//+------------------------------------------------------------------+
