//+------------------------------------------------------------------+
//|                                              R_TrailingStop.mqh  |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Gestión de Trailing Stop                                |
//+------------------------------------------------------------------+
class CTrailingStopManager
{
private:

   //--- Calcular SL para trailing ATR
   double CalculateATRTrailingSL(ENUM_POSITION_TYPE type, double current_price)
   {
      double atr = g_indicators.GetATR();
      if(atr <= 0) return 0;

      double trailing_distance = atr * ATR_TrailingMultiplier;

      if(type == POSITION_TYPE_BUY) {
         return NormalizeDouble(current_price - trailing_distance, _Digits);
      }
      else {
         return NormalizeDouble(current_price + trailing_distance, _Digits);
      }
   }

   //--- Calcular SL para trailing por pasos
   double CalculateStepTrailingSL(ENUM_POSITION_TYPE type, double open_price, double current_price, double current_sl)
   {
      double step_points = TrailingStep * _Point;
      double distance_points = TrailingDistance * _Point;

      if(type == POSITION_TYPE_BUY) {
         double profit_points = current_price - open_price;
         int steps = (int)MathFloor(profit_points / step_points);

         if(steps > 0) {
            double new_sl = open_price + (steps * step_points / 2.0); // Mover la mitad del paso
            new_sl = NormalizeDouble(new_sl, _Digits);

            if(new_sl > current_sl) {
               return new_sl;
            }
         }
      }
      else {
         double profit_points = open_price - current_price;
         int steps = (int)MathFloor(profit_points / step_points);

         if(steps > 0) {
            double new_sl = open_price - (steps * step_points / 2.0);
            new_sl = NormalizeDouble(new_sl, _Digits);

            if(new_sl < current_sl || current_sl == 0) {
               return new_sl;
            }
         }
      }

      return 0; // No cambiar
   }

   //--- Verificar si la posición tiene suficiente profit para activar trailing
   bool HasSufficientProfit(ulong ticket)
   {
      if(!m_position.SelectByTicket(ticket)) return false;

      double open_price = m_position.PriceOpen();
      double current_price = (m_position.PositionType() == POSITION_TYPE_BUY) ?
                            g_symbol_manager.Bid() : g_symbol_manager.Ask();

      double profit_points = 0;

      if(m_position.PositionType() == POSITION_TYPE_BUY) {
         profit_points = (current_price - open_price) / _Point;
      }
      else {
         profit_points = (open_price - current_price) / _Point;
      }

      return (profit_points >= TrailingActivation);
   }

public:
   //--- Constructor
   CTrailingStopManager() {}

   //--- Actualizar trailing stop para todas las posiciones
   void UpdateTrailingStop()
   {
      if(!UseTrailingStop) return;
      if(TrailingType == TRAILING_NONE) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_position.SelectByIndex(i)) continue;

         if(m_position.Symbol() != _Symbol) continue;
         if(m_position.Magic() != MagicNumber_Hilo) continue;

         ulong ticket = m_position.Ticket();

         // Verificar si tiene suficiente profit
         if(!HasSufficientProfit(ticket)) continue;

         // Aplicar trailing según tipo
         ApplyTrailing(ticket);
      }
   }

   //--- Aplicar trailing a una posición específica
   bool ApplyTrailing(ulong ticket)
   {
      if(!m_position.SelectByTicket(ticket)) return false;

      ENUM_POSITION_TYPE type = m_position.PositionType();
      double current_sl = m_position.StopLoss();
      double current_tp = m_position.TakeProfit();
      double open_price = m_position.PriceOpen();

      double current_price = (type == POSITION_TYPE_BUY) ?
                            g_symbol_manager.Bid() : g_symbol_manager.Ask();

      double new_sl = 0;

      // Calcular nuevo SL según tipo de trailing
      switch(TrailingType) {
         case TRAILING_ATR:
            new_sl = CalculateATRTrailingSL(type, current_price);
            break;

         case TRAILING_STEP:
            new_sl = CalculateStepTrailingSL(type, open_price, current_price, current_sl);
            break;

         case TRAILING_PERCENT: {
            // Trailing basado en porcentaje de profit
            double profit = m_position.Profit();
            if(profit > 0) {
               double trailing_dist = TrailingDistance * _Point;
               if(type == POSITION_TYPE_BUY) {
                  new_sl = current_price - trailing_dist;
               } else {
                  new_sl = current_price + trailing_dist;
               }
               new_sl = NormalizeDouble(new_sl, _Digits);
            }
            break;
         }
      }

      if(new_sl == 0) return false;

      // Verificar que el nuevo SL sea mejor que el actual
      bool should_modify = false;

      if(type == POSITION_TYPE_BUY) {
         if(new_sl > current_sl || current_sl == 0) {
            should_modify = true;
         }
      }
      else {
         if(new_sl < current_sl || current_sl == 0) {
            should_modify = true;
         }
      }

      if(should_modify) {
         if(trade.PositionModify(ticket, new_sl, current_tp)) {
            Print("✓ Trailing aplicado: Ticket=", ticket,
                  " Tipo=", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " Nuevo SL=", DoubleToString(new_sl, _Digits));
            return true;
         }
      }

      return false;
   }

   //--- Obtener estado del trailing para una posición
   string GetTrailingStatus(ulong ticket)
   {
      if(!UseTrailingStop) return "OFF";

      if(!m_position.SelectByTicket(ticket)) return "N/A";

      if(!HasSufficientProfit(ticket)) {
         double needed = TrailingActivation;
         return "Esperando +" + DoubleToString(needed, 1) + " pips";
      }

      string type_name = "";
      switch(TrailingType) {
         case TRAILING_ATR:
            type_name = "ATR";
            break;
         case TRAILING_STEP:
            type_name = "STEP";
            break;
         case TRAILING_PERCENT:
            type_name = "%";
            break;
         default:
            type_name = "OFF";
      }

      return "ACTIVO (" + type_name + ")";
   }
};

//--- Instancia global
CTrailingStopManager g_trailing;
//+------------------------------------------------------------------+
