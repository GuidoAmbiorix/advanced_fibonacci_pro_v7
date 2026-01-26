//+------------------------------------------------------------------+
//|                                                R_Dashboard.mqh   |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Dashboard Visual Profesional                            |
//+------------------------------------------------------------------+
class CDashboardManager
{
private:

   //--- Crear barra de progreso
   string CreateProgressBar(double current, double target, int length = 15)
   {
      if(target <= 0) return "";

      double percent = (current / target) * 100.0;
      percent = MathMin(percent, 100.0);

      int filled = (int)((percent / 100.0) * length);
      filled = MathMax(0, MathMin(filled, length));

      string bar = "";
      for(int i = 0; i < filled; i++) bar += "█";
      for(int i = filled; i < length; i++) bar += "░";

      return bar + " " + DoubleToString(percent, 1) + "%";
   }

   //--- Formatear moneda
   string FormatCurrency(double amount)
   {
      string sign = (amount >= 0) ? "+" : "";
      return sign + "$" + DoubleToString(amount, 2);
   }

public:
   //--- Constructor
   CDashboardManager() {}

   //--- Mostrar dashboard completo
   void ShowDashboard()
   {
      if(!Enable_Dashboard) {
         // Fallback a UI simple
         g_ui.DisplayInfo();
         return;
      }

      string output = "";

      // Header
      output += "╔═══════════════════════════════════════════════════════════╗\n";
      output += "║      ROUDO GOD MODE v" + EA_VERSION + " - THE TITAN SCALPER          ║\n";
      output += "╠═══════════════════════════════════════════════════════════╣\n";

      // Sección: Estadísticas Diarias
      if(Enable_SessionStats) {
         output += "║ 📊 ESTADÍSTICAS DIARIAS                                   ║\n";

         double daily_profit = g_stats.GetDailyProfit();
         string profit_bar = CreateProgressBar(MathAbs(daily_profit), MetaGananciaDiaria, 12);

         output += "║ Profit Diario: " + FormatCurrency(daily_profit) + " / " +
                   FormatCurrency(MetaGananciaDiaria) + "\n";
         output += "║ " + profit_bar + "\n";

         // Drawdown
         if(Enable_SessionStats) {
            output += "║ " + g_drawdown.GetDrawdownInfo() + "\n";
         }

         output += "╠═══════════════════════════════════════════════════════════╣\n";
      }

      // Sección: Killzone
      if(Enable_KillzoneInfo && UseKillzones) {
         output += "║ ⏰ KILLZONE STATUS                                        ║\n";

         ENUM_KILLZONE current_kz = g_killzones.GetCurrentKillzone();
         string kz_name = g_killzones.GetKillzoneName(current_kz);
         string kz_symbol = g_killzones.GetKillzoneStatusSymbol();

         bool can_trade = g_killzones.CanTradeNow();
         string status_text = can_trade ? "TRADING ACTIVO" : "PAUSADO";

         output += "║ Actual: " + kz_name + " " + kz_symbol + " (" + status_text + ")\n";
         output += "║ Próxima: " + g_killzones.GetNextKillzone() + "\n";

         output += "╠═══════════════════════════════════════════════════════════╣\n";
      }

      // Sección: Posiciones Abiertas
      output += "║ 📈 POSICIONES ABIERTAS                                    ║\n";

      int total_positions = g_stats.GetTotalPositions();
      output += "║ Órdenes: " + IntegerToString(total_positions) + " / " +
                IntegerToString(MaxOperacionesGrid) + "\n";

      double total_volume = g_stats.GetTotalVolume();
      output += "║ Volumen Total: " + DoubleToString(total_volume, 2) + " lotes\n";

      // Grid info
      if(total_positions > 0) {
         #ifdef R_CONFIG_MICRO
         string progression_info = g_martingale_micro.GetProgressionInfo();
         #else
         string progression_info = g_martingale_pro.GetProgressionInfo();
         #endif
         output += "║ Grid: " + progression_info + "\n";

         #ifdef R_CONFIG_MICRO
         double next_lot = g_martingale_micro.GetNextLot();
         #else
         double next_lot = g_martingale_pro.GetNextLot();
         #endif
         output += "║ Próximo lote: " + DoubleToString(next_lot, 2) + "\n";
      }

      // Profit flotante
      double floating_profit = g_stats.GetFloatingProfit();
      output += "║ Profit Flotante: " + FormatCurrency(floating_profit);

      if(floating_profit > 0) output += " 🟢";
      else if(floating_profit < 0) output += " 🔴";
      output += "\n";

      // Protecciones activas
      if(total_positions > 0) {
         string protections = "║ Protecciones: ";

         if(UseBreakeven) protections += "BE🔒 ";
         if(UseTrailingStop) protections += "TS📊 ";
         if(UsePartialTP) protections += "PTP🎯 ";

         output += protections + "\n";
      }

      output += "╠═══════════════════════════════════════════════════════════╣\n";

      // Sección: Riesgo y Margen
      output += "║ 🎯 RIESGO Y MARGEN                                        ║\n";

      double margin_level = g_symbol_manager.GetMarginLevel();
      output += "║ Margen: " + DoubleToString(margin_level, 1) + "%";

      if(margin_level > Min_Margin_Level) output += " ✓";
      else if(margin_level > Min_Margin_Level * 0.9) output += " ⚠️";
      else output += " 🔴";
      output += "\n";

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      output += "║ Balance: " + FormatCurrency(balance) + " | Equity: " +
                FormatCurrency(equity) + "\n";

      int spread = g_symbol_manager.GetSpread();
      output += "║ Spread: " + IntegerToString(spread) + " / " +
                IntegerToString(Max_Spread);

      if(spread <= Max_Spread) output += " ✓";
      else output += " ⚠️";
      output += "\n";

      double atr = g_indicators.GetATR();
      output += "║ ATR(14): " + DoubleToString(atr / _Point, 1) + " pips\n";

      output += "╚═══════════════════════════════════════════════════════════╝\n";

      // Mensajes de estado
      if(g_risk.IsDailyTargetReached()) {
         output += "\n✅ Meta diaria alcanzada. Operación pausada hasta mañana.";
      }

      if(g_drawdown.IsLimitHit()) {
         output += "\n⚠️ Drawdown máximo alcanzado. Trading detenido.";
      }

      if(!g_killzones.CanTradeNow() && UseKillzones) {
         output += "\n⏸️ Fuera de killzone. Esperando próxima sesión.";
      }

      if(total_positions >= MaxOperacionesGrid) {
         output += "\n⚠️ Límite de órdenes alcanzado (" + IntegerToString(MaxOperacionesGrid) + ").";
      }

      if(margin_level < Min_Margin_Level && margin_level > 0) {
         output += "\n🔴 ADVERTENCIA: Margen bajo (" + DoubleToString(margin_level, 1) + "%)";
      }

      Comment(output);
   }

   //--- Mostrar estadísticas de sesión
   void ShowSessionStats()
   {
      // Esta función puede expandirse para mostrar stats detalladas por killzone
      Print("╔════════════════════════════════════════╗");
      Print("║  ESTADÍSTICAS DE SESIÓN                ║");
      Print("╠════════════════════════════════════════╣");
      Print("║  Killzone: ", g_killzones.GetKillzoneName());
      Print("║  Posiciones: ", g_stats.GetTotalPositions());
      Print("║  Profit Hoy: $", DoubleToString(g_stats.GetDailyProfit(), 2));
      Print("╚════════════════════════════════════════╝");
   }
};

//--- Instancia global
CDashboardManager g_dashboard;
//+------------------------------------------------------------------+
