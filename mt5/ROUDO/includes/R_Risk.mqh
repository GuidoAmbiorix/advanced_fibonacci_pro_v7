//+------------------------------------------------------------------+
//|                                                       R_Risk.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Gestión de Riesgo                                       |
//+------------------------------------------------------------------+
class CRiskManager
{
private:

public:
   //--- Constructor
   CRiskManager() {}

   //--- Verificar si se alcanzó la meta diaria
   bool IsDailyTargetReached()
   {
      double daily_profit = g_stats.GetDailyProfit();

      if(daily_profit >= MetaGananciaDiaria) {
         return true;
      }

      return false;
   }

   //--- Verificar nivel de margen
   bool IsMarginSufficient()
   {
      double margin_level = g_symbol_manager.GetMarginLevel();

      if(margin_level < Min_Margin_Level && margin_level > 0) {
         Print("ADVERTENCIA: Margen bajo - ", DoubleToString(margin_level, 1), "%");
         return false;
      }

      return true;
   }

   //--- Verificar límite de órdenes
   bool CanAddMoreOrders()
   {
      int total_positions = g_stats.GetTotalPositions();

      if(total_positions >= MaxOperacionesGrid) {
         return false;
      }

      return true;
   }

   //--- Verificación completa antes de operar
   bool CanOpenNewPosition()
   {
      // 1. Verificar meta diaria
      if(IsDailyTargetReached()) {
         return false;
      }

      // 2. Verificar condiciones de mercado (spread)
      if(!g_symbol_manager.CanTrade()) {
         return false;
      }

      return true;
   }

   //--- 🆕 Verificar free margin suficiente
   bool HasSufficientFreeMargin()
   {
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double margin = AccountInfoDouble(ACCOUNT_MARGIN);

      if(margin <= 0) return true; // Sin posiciones aún

      double free_margin_percent = (free_margin / (free_margin + margin)) * 100.0;

      if(free_margin_percent < Min_FreeMargin_Percent) {
         Print("⚠️ Free Margin muy bajo: ", DoubleToString(free_margin_percent, 1),
               "% (Min: ", Min_FreeMargin_Percent, "%)");
         return false;
      }

      return true;
   }

   //--- Verificación antes de agregar orden martingala
   bool CanAddMartingaleOrder()
   {
      // 1. Verificar margen
      if(!IsMarginSufficient()) {
         Print("No se puede agregar orden: Margen insuficiente");
         return false;
      }

      // 2. 🆕 Verificar free margin (crítico para micro accounts)
      if(!HasSufficientFreeMargin()) {
         Print("No se puede agregar orden: Free Margin insuficiente");
         return false;
      }

      // 3. Verificar límite de órdenes
      if(!CanAddMoreOrders()) {
         Print("No se puede agregar orden: Límite de ", MaxOperacionesGrid, " alcanzado");
         return false;
      }

      return true;
   }

   //--- Calcular lote con exponente martingala
   double CalculateMartingaleLot(double last_volume)
   {
      double volume_step = g_symbol_manager.GetVolumeStep();

      // Aplicar exponente (compatible con GOD y MICRO)
      #ifdef R_CONFIG_MICRO
      double new_lot = NormalizeDouble(last_volume * LotMultiplier, 2);
      #else
      double new_lot = NormalizeDouble(last_volume * LotExponent, 2);
      #endif

      // Ajustar al step del símbolo
      new_lot = MathFloor(new_lot / volume_step) * volume_step;

      // Aplicar límite máximo
      if(new_lot > MaxLots) {
         Print("Lote limitado a MaxLots: ", MaxLots);
         new_lot = MaxLots;
      }

      return new_lot;
   }
};

//--- Instancia global
CRiskManager g_risk;
//+------------------------------------------------------------------+
