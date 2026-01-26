//+------------------------------------------------------------------+
//|                                         R_MartingaleMicro.mqh    |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Martingale MICRO (Ultra Conservador)                    |
//+------------------------------------------------------------------+
class CMartingaleMicroManager
{
private:

   //--- Contar nivel de grid actual
   int GetCurrentGridLevel()
   {
      int count = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() == _Symbol && m_position.Magic() == MagicNumber_Hilo) {
               count++;
            }
         }
      }

      return count;
   }

public:
   //--- Constructor
   CMartingaleMicroManager() {}

   //--- Calcular siguiente lote con progresión MICRO
   double CalculateMicroLot(int grid_level)
   {
      double base_lot = Lots;

      // Si usa auto lot size, calcular dinámicamente
      if(UseAutoLotSize) {
         base_lot = g_autolot.CalculateAutoLotSize();
      }

      // Usar progresión MICRO ultra conservadora
      int micro_size = ArraySize(MICRO_PROGRESSION);

      if(grid_level >= micro_size) {
         grid_level = micro_size - 1; // Usar último valor
      }

      double multiplier = MICRO_PROGRESSION[grid_level];
      double calculated_lot = base_lot * multiplier;

      // Normalizar
      double volume_step = g_symbol_manager.GetVolumeStep();
      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

      calculated_lot = NormalizeDouble(calculated_lot, 2);
      calculated_lot = MathFloor(calculated_lot / volume_step) * volume_step;
      calculated_lot = MathMax(calculated_lot, min_lot);
      calculated_lot = MathMin(calculated_lot, max_lot);
      calculated_lot = MathMin(calculated_lot, MaxLots);

      return calculated_lot;
   }

   //--- Calcular grid step dinámico
   double GetDynamicGridStep()
   {
      double base_atr = g_indicators.GetATR();
      if(base_atr <= 0) {
         Print("ATR inválido, usando step mínimo");
         return 300 * _Point; // Aumentado para MICRO
      }

      double step = base_atr * ATR_Multiplier;

      // Límites MICRO (más espaciado)
      double min_step = 300 * _Point; // Mínimo 300 pips (vs 200)
      double max_step = 1000 * _Point; // Máximo 1000 pips (vs 800)

      step = MathMax(step, min_step);
      step = MathMin(step, max_step);

      return step;
   }

   //--- Gestión inteligente de grid MICRO
   void SmartGridManagement()
   {
      // Verificar permisos de riesgo
      if(!g_risk.CanAddMartingaleOrder()) return;

      // Obtener última posición
      double last_price = 0, last_lot = 0;
      ENUM_POSITION_TYPE position_type;

      if(!g_orders.GetLastPositionInfo(last_price, last_lot, position_type)) {
         return;
      }

      // Calcular step dinámico
      double step = GetDynamicGridStep();

      // Obtener nivel actual
      int grid_level = GetCurrentGridLevel();

      // Calcular nuevo lote
      double new_lot = CalculateMicroLot(grid_level);

      // Verificar condiciones de precio
      double ask = g_symbol_manager.Ask();
      double bid = g_symbol_manager.Bid();

      bool should_add = false;

      if(position_type == POSITION_TYPE_BUY && ask < (last_price - step)) {
         should_add = true;
      }
      else if(position_type == POSITION_TYPE_SELL && bid > (last_price + step)) {
         should_add = true;
      }

      if(!should_add) return;

      // Abrir nueva orden
      bool result = false;

      string comment = "ROUDO MICRO L" + IntegerToString(grid_level) + " (×" +
                      DoubleToString(MICRO_PROGRESSION[MathMin(grid_level, ArraySize(MICRO_PROGRESSION)-1)], 1) + ")";

      if(position_type == POSITION_TYPE_BUY) {
         result = trade.Buy(new_lot, _Symbol, ask, 0, 0, comment);

         if(result) {
            Print("═══════════════════════════════════════");
            Print("  📈 MICRO GRID BUY AGREGADO");
            Print("  Nivel: ", grid_level);
            Print("  Lote: ", DoubleToString(new_lot, 3));
            Print("  Multiplicador: ×", DoubleToString(MICRO_PROGRESSION[MathMin(grid_level, ArraySize(MICRO_PROGRESSION)-1)], 1));
            Print("  Precio: ", DoubleToString(ask, _Digits));
            Print("  Step: ", DoubleToString(step / _Point, 1), " pips");
            Print("═══════════════════════════════════════");

            g_orders.UpdateGlobalTakeProfit(POSITION_TYPE_BUY);
         }
      }
      else {
         result = trade.Sell(new_lot, _Symbol, bid, 0, 0, comment);

         if(result) {
            Print("═══════════════════════════════════════");
            Print("  📉 MICRO GRID SELL AGREGADO");
            Print("  Nivel: ", grid_level);
            Print("  Lote: ", DoubleToString(new_lot, 3));
            Print("  Multiplicador: ×", DoubleToString(MICRO_PROGRESSION[MathMin(grid_level, ArraySize(MICRO_PROGRESSION)-1)], 1));
            Print("  Precio: ", DoubleToString(bid, _Digits));
            Print("  Step: ", DoubleToString(step / _Point, 1), " pips");
            Print("═══════════════════════════════════════");

            g_orders.UpdateGlobalTakeProfit(POSITION_TYPE_SELL);
         }
      }
   }

   //--- Obtener información de progresión
   string GetProgressionInfo()
   {
      int grid_level = GetCurrentGridLevel();

      string info = "MICRO L" + IntegerToString(grid_level);

      if(grid_level > 0 && grid_level < ArraySize(MICRO_PROGRESSION)) {
         info += " (×" + DoubleToString(MICRO_PROGRESSION[grid_level], 1) + ")";
      }

      return info;
   }

   //--- Obtener próximo lote
   double GetNextLot()
   {
      int grid_level = GetCurrentGridLevel();
      return CalculateMicroLot(grid_level);
   }
};

//--- Instancia global
CMartingaleMicroManager g_martingale_micro;
//+------------------------------------------------------------------+
