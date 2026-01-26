//+------------------------------------------------------------------+
//|                                                  ROUDO_MICRO.mq5 |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
//|  ROUDO MICRO v3.01 - Para cuentas pequeñas $100-$500             |
//|  Ultra Conservador - Protección máxima contra stop out           |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"
#property version   "3.01"
#property strict
#property description "ROUDO MICRO - Ultra conservador para cuentas pequeñas"
#property description "Diseñado específicamente para $100-$500 en XAUUSD"
#property description "Protección anti-stopout con free margin control"

#define R_CONFIG_MICRO  // Define para activar modo MICRO

//+------------------------------------------------------------------+
//| Includes de Módulos MICRO                                        |
//+------------------------------------------------------------------+
#include "includes/R_Config_MICRO.mqh"  // Configuración MICRO
#include "includes/R_Symbol.mqh"
#include "includes/R_AutoLot.mqh"       // Auto lot calculation
#include "includes/R_Indicators.mqh"
#include "includes/R_Stats.mqh"
#include "includes/R_Killzones.mqh"
#include "includes/R_Drawdown.mqh"
#include "includes/R_Risk.mqh"
#include "includes/R_Breakeven.mqh"
#include "includes/R_TrailingStop.mqh"
#include "includes/R_PartialTP.mqh"
#include "includes/R_Orders.mqh"
#include "includes/R_MartingaleMicro.mqh"  // MICRO version (BEFORE Dashboard!)
#include "includes/R_Dashboard.mqh"        // Dashboard uses g_martingale_micro
#include "includes/R_UI.mqh"

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║                   ROUDO MICRO v3.01                        ║");
   Print("║           ULTRA CONSERVADOR PARA CUENTAS PEQUEÑAS          ║");
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  💰 Diseñado para: $100 - $500                            ║");
   Print("║  🛡️ Protección: Anti Stop-Out                             ║");
   Print("╚════════════════════════════════════════════════════════════╝");

   // Verificar tamaño de cuenta
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < 100) {
      Print("❌ ERROR: Balance muy bajo ($", balance, "). Mínimo recomendado: $100");
      Print("⚠️ ALTO RIESGO DE STOP OUT");
   }
   else if(balance < 300) {
      Print("⚠️ ADVERTENCIA: Balance bajo ($", balance, "). Recomendado: $300+");
   }

   // 1. Inicializar símbolo
   if(!g_symbol_manager.Init()) {
      Print("❌ ERROR: Fallo al inicializar símbolo");
      return INIT_FAILED;
   }
   Print("✓ Símbolo: ", _Symbol);

   // 2. Verificar que el símbolo permite micro lotes
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   Print("✓ Lote mínimo del broker: ", min_lot);

   if(min_lot > 0.01) {
      Print("⚠️ ADVERTENCIA: Este broker NO permite micro lotes (0.01)");
      Print("⚠️ Lote mínimo: ", min_lot, " - RIESGO ALTO");
   }

   // 3. Configurar Trade
   trade.SetExpertMagicNumber(MagicNumber_Hilo);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // 4. Inicializar indicadores
   if(!g_indicators.Init()) {
      Print("❌ ERROR: Fallo al inicializar indicadores");
      return INIT_FAILED;
   }
   Print("✓ Indicadores inicializados");

   // 5. Mostrar configuración MICRO
   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║  CONFIGURACIÓN MICRO (ULTRA CONSERVADORA)                  ║");
   Print("╠════════════════════════════════════════════════════════════╣");

   double initial_lot = UseAutoLotSize ? g_autolot.CalculateAutoLotSize() : Lots;
   Print("║  Lote inicial: ", DoubleToString(initial_lot, 3));
   Print("║  Auto Lot Size: ", (UseAutoLotSize ? "SI ✓" : "NO"));

   if(UseAutoLotSize) {
      Print("║  Riesgo por trade: ", RiskPercentPerTrade, "%");
   }

   Print("║  Max Lotes: ", DoubleToString(MaxLots, 3), " (MICRO)");
   Print("║  Max Grid: ", MaxOperacionesGrid, " órdenes");
   Print("║  Progresión: ", (UseFibonacciProgression ? "Fibonacci" : "MICRO Conservadora ⭐"));
   Print("║  Multiplicador: ", DoubleToString(LotMultiplier, 1), "x");
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  🛡️ PROTECCIÓN ANTI STOP-OUT                              ║");
   Print("║  Min Margin Level: ", DoubleToString(Min_Margin_Level, 0), "%");
   Print("║  Min Free Margin: ", DoubleToString(Min_FreeMargin_Percent, 0), "%");
   Print("║  Max DD Diario: ", DoubleToString(MaxDailyDrawdown, 1), "%");
   Print("║  Max DD por Trade: ", DoubleToString(MaxDrawdownPerTrade, 1), "%");
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  🎯 OBJETIVOS REALISTAS                                    ║");
   Print("║  Meta Diaria: $", DoubleToString(MetaGananciaDiaria, 2));

   double monthly_target = MetaGananciaDiaria * 20;
   double monthly_percent = (balance > 0) ? (monthly_target / balance * 100) : 0;
   Print("║  Meta Mensual: $", DoubleToString(monthly_target, 2), " (", DoubleToString(monthly_percent, 1), "%)");
   Print("╚════════════════════════════════════════════════════════════╝");

   // 6. Advertencias de seguridad
   Print("");
   Print("⚠️ ADVERTENCIAS IMPORTANTES:");
   Print("• Esta configuración es MUY CONSERVADORA pero AÚN TIENE RIESGO");
   Print("• SIEMPRE testear en DEMO primero (mínimo 2 semanas)");
   Print("• Con $500, el max drawdown de 8% = $40 de pérdida máxima");
   Print("• Retirar ganancias regularmente (semanal)");
   Print("• Nunca operar con dinero que no puedes perder");
   Print("");

   g_killzones.LogKillzoneChange();

   Print("🚀 ROUDO MICRO v3.01 LISTO");
   Print("");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Reset diario
   g_drawdown.DailyReset();

   // 2. Verificar condiciones de mercado
   if(!g_symbol_manager.CanTrade()) return;

   // 3. Verificar killzones
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

   // 6. 🆕 CRÍTICO: Verificar free margin antes de cualquier operación
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);

   if(margin > 0) {
      double free_margin_percent = (free_margin / (free_margin + margin)) * 100.0;

      if(free_margin_percent < Min_FreeMargin_Percent) {
         Print("⚠️ FREE MARGIN CRÍTICO: ", DoubleToString(free_margin_percent, 1), "%");
         Comment("⚠️ FREE MARGIN BAJO - NO SE ABREN MÁS POSICIONES\n",
                "Free Margin: ", DoubleToString(free_margin_percent, 1), "%\n",
                "Mínimo requerido: ", DoubleToString(Min_FreeMargin_Percent, 1), "%");
         return;
      }
   }

   // 7. Aplicar protecciones
   g_breakeven.CheckBreakeven();
   g_trailing.UpdateTrailingStop();
   g_partial_tp.CheckPartialTakeProfit();

   // 8. Lógica de trading
   int total_positions = g_stats.GetTotalPositions();

   if(total_positions == 0) {
      g_orders.OpenInitialPosition();
   }
   else {
      g_martingale_micro.SmartGridManagement(); // Usar versión MICRO
   }

   // 9. Update UI
   g_killzones.LogKillzoneChange();
   g_dashboard.ShowDashboard();
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");

   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║  ROUDO MICRO FINALIZADO                                    ║");
   Print("╠════════════════════════════════════════════════════════════╣");

   double daily_profit = g_stats.GetDailyProfit();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("║  Profit del día: $", DoubleToString(daily_profit, 2));
   Print("║  Balance final: $", DoubleToString(balance, 2));

   int total_pos = g_stats.GetTotalPositions();
   Print("║  Posiciones abiertas: ", total_pos);

   if(total_pos > 0) {
      Print("║  ⚠️ HAY ", total_pos, " POSICIONES ABIERTAS");
   }

   Print("╚════════════════════════════════════════════════════════════╝");
}
//+------------------------------------------------------------------+
