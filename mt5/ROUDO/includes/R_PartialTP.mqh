//+------------------------------------------------------------------+
//|                                                 R_PartialTP.mqh  |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Estructura para trackear niveles de TP ejecutados                |
//+------------------------------------------------------------------+
struct PartialTPStatus {
   ulong ticket;
   bool tp1_executed;
   bool tp2_executed;
   bool tp3_executed;
};

//+------------------------------------------------------------------+
//| Clase de Gestión de Partial Take Profit                          |
//+------------------------------------------------------------------+
class CPartialTPManager
{
private:
   PartialTPStatus tp_status[];
   int status_count;

   //--- Obtener o crear status para ticket
   int GetStatusIndex(ulong ticket)
   {
      for(int i = 0; i < status_count; i++) {
         if(tp_status[i].ticket == ticket) {
            return i;
         }
      }

      // Crear nuevo
      ArrayResize(tp_status, status_count + 1);
      tp_status[status_count].ticket = ticket;
      tp_status[status_count].tp1_executed = false;
      tp_status[status_count].tp2_executed = false;
      tp_status[status_count].tp3_executed = false;

      status_count++;
      return status_count - 1;
   }

   //--- Limpiar tickets cerrados
   void CleanupStatusList()
   {
      PartialTPStatus temp[];
      int temp_count = 0;

      for(int i = 0; i < status_count; i++) {
         if(m_position.SelectByTicket(tp_status[i].ticket)) {
            ArrayResize(temp, temp_count + 1);
            temp[temp_count] = tp_status[i];
            temp_count++;
         }
      }

      ArrayCopy(tp_status, temp);
      status_count = temp_count;
   }

   //--- Calcular profit en pips
   double GetProfitInPips(ulong ticket)
   {
      if(!m_position.SelectByTicket(ticket)) return 0;

      double open_price = m_position.PriceOpen();
      ENUM_POSITION_TYPE type = m_position.PositionType();
      double current_price = (type == POSITION_TYPE_BUY) ?
                            g_symbol_manager.Bid() : g_symbol_manager.Ask();

      double profit_points = 0;

      if(type == POSITION_TYPE_BUY) {
         profit_points = (current_price - open_price) / _Point;
      }
      else {
         profit_points = (open_price - current_price) / _Point;
      }

      return profit_points;
   }

   //--- Cerrar parcialmente una posición
   bool ClosePartial(ulong ticket, double percent, string comment)
   {
      if(!m_position.SelectByTicket(ticket)) return false;

      double current_volume = m_position.Volume();
      double close_volume = NormalizeDouble(current_volume * percent / 100.0, 2);

      // Verificar volumen mínimo
      double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(close_volume < min_volume) {
         Print("Volumen de cierre muy pequeño: ", close_volume);
         return false;
      }

      // Verificar que quede volumen suficiente
      double remaining = current_volume - close_volume;
      if(remaining < min_volume && remaining > 0) {
         // Si queda muy poco, cerrar todo
         close_volume = current_volume;
      }

      Print("🎯 ", comment, ": Cerrando ", DoubleToString(percent, 0),
            "% (", DoubleToString(close_volume, 2), " lotes) de ticket ", ticket);

      return trade.PositionClosePartial(ticket, close_volume);
   }

public:
   //--- Constructor
   CPartialTPManager() : status_count(0)
   {
      ArrayResize(tp_status, 0);
   }

   //--- Verificar y ejecutar partial TPs
   void CheckPartialTakeProfit()
   {
      if(!UsePartialTP) return;

      CleanupStatusList();

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_position.SelectByIndex(i)) continue;

         if(m_position.Symbol() != _Symbol) continue;
         if(m_position.Magic() != MagicNumber_Hilo) continue;

         ulong ticket = m_position.Ticket();
         int status_idx = GetStatusIndex(ticket);

         double profit_pips = GetProfitInPips(ticket);

         // TP3 (último)
         if(!tp_status[status_idx].tp3_executed && profit_pips >= TP3_Level) {
            if(ClosePartial(ticket, TP3_Percent, "TP3")) {
               tp_status[status_idx].tp3_executed = true;
            }
         }
         // TP2 (medio)
         else if(!tp_status[status_idx].tp2_executed && profit_pips >= TP2_Level) {
            if(ClosePartial(ticket, TP2_Percent, "TP2")) {
               tp_status[status_idx].tp2_executed = true;
            }
         }
         // TP1 (primero)
         else if(!tp_status[status_idx].tp1_executed && profit_pips >= TP1_Level) {
            if(ClosePartial(ticket, TP1_Percent, "TP1")) {
               tp_status[status_idx].tp1_executed = true;
            }
         }
      }
   }

   //--- Obtener nivel de TP alcanzado
   int GetTPLevel(ulong ticket)
   {
      int status_idx = GetStatusIndex(ticket);

      if(tp_status[status_idx].tp3_executed) return 3;
      if(tp_status[status_idx].tp2_executed) return 2;
      if(tp_status[status_idx].tp1_executed) return 1;

      return 0;
   }

   //--- Obtener próximo nivel de TP
   string GetNextTPLevel(ulong ticket)
   {
      if(!UsePartialTP) return "OFF";

      double profit_pips = GetProfitInPips(ticket);
      int current_level = GetTPLevel(ticket);

      if(current_level == 0) {
         double needed = TP1_Level - profit_pips;
         if(needed > 0) {
            return "TP1 en +" + DoubleToString(needed, 1) + " pips";
         }
         return "TP1 listo";
      }
      else if(current_level == 1) {
         double needed = TP2_Level - profit_pips;
         if(needed > 0) {
            return "TP2 en +" + DoubleToString(needed, 1) + " pips";
         }
         return "TP2 listo";
      }
      else if(current_level == 2) {
         double needed = TP3_Level - profit_pips;
         if(needed > 0) {
            return "TP3 en +" + DoubleToString(needed, 1) + " pips";
         }
         return "TP3 listo";
      }

      return "Completado";
   }

   //--- Reset
   void Reset()
   {
      ArrayResize(tp_status, 0);
      status_count = 0;
   }
};

//--- Instancia global
CPartialTPManager g_partial_tp;
//+------------------------------------------------------------------+
