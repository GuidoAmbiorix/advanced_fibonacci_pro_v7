//+------------------------------------------------------------------+
//|                                            R_MartingalePro.mqh   |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Martingale Profesional con Fibonacci                    |
//+------------------------------------------------------------------+
class CMartingaleProManager
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

   //--- Obtener multiplicador de volatilidad
   double GetVolatilityMultiplier()
   {
      if(!UseAdaptiveStep) return ATR_Multiplier;

      double atr = g_indicators.GetATR();
      if(atr <= 0) return ATR_Multiplier;

      // Calcular ATR promedio de las últimas 20 velas
      double atr_sum = 0;
      int atr_count = 20;

      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(g_indicators.handle_atr, 0, 0, atr_count, atr_buffer) > 0) {
         for(int i = 0; i < atr_count; i++) {
            atr_sum += atr_buffer[i];
         }

         double atr_avg = atr_sum / atr_count;

         if(atr_avg > 0) {
            double volatility_ratio = atr / atr_avg;

            // Si volatilidad alta, aumentar spacing
            if(volatility_ratio > 1.3) {
               return ATR_Multiplier * 1.5;
            }
            // Si volatilidad baja, reducir spacing
            else if(volatility_ratio < 0.7) {
               return ATR_Multiplier * 0.8;
            }
         }
      }

      return ATR_Multiplier;
   }

public:
   //--- Constructor
   CMartingaleProManager() {}

   //--- Calcular siguiente lote con Fibonacci
   double CalculateFibonacciLot(int grid_level)
   {
      double base_lot = Lots;

      if(!UseFibonacciProgression) {
         // Usar exponencial clásico
         double lot = base_lot * MathPow(LotExponent, grid_level);
         return NormalizeLot(lot);
      }

      // Usar secuencia Fibonacci
      int fib_size = ArraySize(FIBONACCI_SEQUENCE);

      if(grid_level >= fib_size) {
         grid_level = fib_size - 1;
      }

      double multiplier = FIBONACCI_SEQUENCE[grid_level];
      double lot = base_lot * multiplier;

      return NormalizeLot(lot);
   }

   //--- Normalizar lote
   double NormalizeLot(double lot)
   {
      double volume_step = g_symbol_manager.GetVolumeStep();
      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

      lot = NormalizeDouble(lot, 2);
      lot = MathFloor(lot / volume_step) * volume_step;

      lot = MathMax(lot, min_lot);
      lot = MathMin(lot, max_lot);
      lot = MathMin(lot, MaxLots);

      return lot;
   }

   //--- Calcular grid step dinámico
   double GetDynamicGridStep()
   {
      double base_atr = g_indicators.GetATR();
      if(base_atr <= 0) {
         Print("ATR inválido, usando step mínimo");
         return 200 * _Point;
      }

      double volatility_mult = GetVolatilityMultiplier();
      double step = base_atr * volatility_mult;

      // Aplicar límites
      double min_step = 200 * _Point; // Mínimo 200 pips
      double max_step = 800 * _Point; // Máximo 800 pips

      step = MathMax(step, min_step);
      step = MathMin(step, max_step);

      return step;
   }

   //--- Gestión inteligente de grid
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
      double new_lot = CalculateFibonacciLot(grid_level);

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

      string progression = UseFibonacciProgression ? "Fibonacci" : "Exponencial";
      string comment = "ROUDO Grid L" + IntegerToString(grid_level) + " (" + progression + ")";

      if(position_type == POSITION_TYPE_BUY) {
         result = trade.Buy(new_lot, _Symbol, ask, 0, 0, comment);

         if(result) {
            Print("═══════════════════════════════════════");
            Print("  📈 GRID BUY AGREGADO");
            Print("  Nivel: ", grid_level);
            Print("  Lote: ", DoubleToString(new_lot, 2));
            Print("  Progresión: ", progression);
            Print("  Precio: ", DoubleToString(ask, _Digits));
            Print("  Step usado: ", DoubleToString(step / _Point, 1), " pips");
            Print("═══════════════════════════════════════");

            g_orders.UpdateGlobalTakeProfit(POSITION_TYPE_BUY);
         }
      }
      else {
         result = trade.Sell(new_lot, _Symbol, bid, 0, 0, comment);

         if(result) {
            Print("═══════════════════════════════════════");
            Print("  📉 GRID SELL AGREGADO");
            Print("  Nivel: ", grid_level);
            Print("  Lote: ", DoubleToString(new_lot, 2));
            Print("  Progresión: ", progression);
            Print("  Precio: ", DoubleToString(bid, _Digits));
            Print("  Step usado: ", DoubleToString(step / _Point, 1), " pips");
            Print("═══════════════════════════════════════");

            g_orders.UpdateGlobalTakeProfit(POSITION_TYPE_SELL);
         }
      }
   }

   //--- Obtener información de progresión
   string GetProgressionInfo()
   {
      int grid_level = GetCurrentGridLevel();

      string info = "";

      if(UseFibonacciProgression) {
         info += "Fibonacci L" + IntegerToString(grid_level);

         if(grid_level > 0 && grid_level < ArraySize(FIBONACCI_SEQUENCE)) {
            info += " (×" + DoubleToString(FIBONACCI_SEQUENCE[grid_level], 1) + ")";
         }
      }
      else {
         info += "Exponencial L" + IntegerToString(grid_level);

         if(grid_level > 0) {
            double mult = MathPow(LotExponent, grid_level);
            info += " (×" + DoubleToString(mult, 1) + ")";
         }
      }

      return info;
   }

   //--- Obtener próximo lote
   double GetNextLot()
   {
      int grid_level = GetCurrentGridLevel();
      return CalculateFibonacciLot(grid_level);
   }
};

//--- Instancia global
CMartingaleProManager g_martingale_pro;
//+------------------------------------------------------------------+
