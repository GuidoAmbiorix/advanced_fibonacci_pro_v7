//+------------------------------------------------------------------+
//|                                                         R_UI.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Interfaz de Usuario                                     |
//+------------------------------------------------------------------+
class CUIManager
{
private:

public:
   //--- Constructor
   CUIManager() {}

   //--- Mostrar información en pantalla
   void DisplayInfo()
   {
      string output = "";

      // Encabezado
      output += "╔════════════════════════════════════════╗\n";
      output += "║  ROUDO v" + EA_VERSION + " - " + EA_MARKET + " (THE TITAN SCALPER) ║\n";
      output += "╠════════════════════════════════════════╣\n";

      // Beneficio diario
      double daily_profit = g_stats.GetDailyProfit();
      output += "║ Beneficio Hoy: $" + DoubleToString(daily_profit, 2);
      output += " / $" + DoubleToString(MetaGananciaDiaria, 2);

      // Indicador de progreso
      double progress = (MetaGananciaDiaria > 0) ? (daily_profit / MetaGananciaDiaria * 100) : 0;
      output += " (" + DoubleToString(progress, 1) + "%)";
      output += "\n";

      // Órdenes abiertas
      int total_positions = g_stats.GetTotalPositions();
      output += "║ Órdenes abiertas: " + IntegerToString(total_positions);
      output += " / " + IntegerToString(MaxOperacionesGrid);
      output += "\n";

      // Volumen total
      double total_volume = g_stats.GetTotalVolume();
      output += "║ Volumen total: " + DoubleToString(total_volume, 2) + " lotes";
      output += "\n";

      // Profit flotante
      double floating_profit = g_stats.GetFloatingProfit();
      string profit_sign = (floating_profit >= 0) ? "+" : "";
      output += "║ Profit flotante: " + profit_sign + "$" + DoubleToString(floating_profit, 2);
      output += "\n";

      // Nivel de margen
      double margin_level = g_symbol_manager.GetMarginLevel();
      output += "║ Nivel de Margen: " + DoubleToString(margin_level, 1) + "%";
      output += "\n";

      // Spread actual
      int spread = g_symbol_manager.GetSpread();
      output += "║ Spread: " + IntegerToString(spread) + " / " + IntegerToString(Max_Spread);
      output += "\n";

      output += "╚════════════════════════════════════════╝\n";

      // Mensajes de estado
      if(g_risk.IsDailyTargetReached()) {
         output += "\n✓ Meta diaria alcanzada. Operación pausada hasta mañana.";
      }

      if(total_positions >= MaxOperacionesGrid) {
         output += "\n⚠ Límite de órdenes (" + IntegerToString(MaxOperacionesGrid) + ") alcanzado.";
      }

      if(margin_level < Min_Margin_Level && margin_level > 0) {
         output += "\n⚠ ADVERTENCIA: Margen bajo (" + DoubleToString(margin_level, 1) + "%)";
      }

      Comment(output);
   }

   //--- Mostrar mensaje de inicialización
   void ShowInitMessage()
   {
      Print("╔════════════════════════════════════════╗");
      Print("║  ROUDO v", EA_VERSION, " - ", EA_MARKET, "                 ║");
      Print("╠════════════════════════════════════════╣");
      Print("║  THE TITAN SCALPER                     ║");
      Print("║  Cuenta: $500                          ║");
      Print("║  Magic Number: ", MagicNumber_Hilo, "                 ║");
      Print("╚════════════════════════════════════════╝");
   }
};

//--- Instancia global
CUIManager g_ui;
//+------------------------------------------------------------------+
