//+------------------------------------------------------------------+
//|                                                R_Breakeven.mqh   |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Gestión de Breakeven                                    |
//+------------------------------------------------------------------+
class CBreakevenManager
{
private:
   //--- Array para trackear posiciones ya movidas a BE
   ulong be_positions[];
   int be_count;

   //--- Verificar si posición ya está en BE
   bool IsAlreadyInBreakeven(ulong ticket)
   {
      for(int i = 0; i < be_count; i++) {
         if(be_positions[i] == ticket) {
            return true;
         }
      }
      return false;
   }

   //--- Agregar posición a lista de BE
   void AddToBreakevenList(ulong ticket)
   {
      ArrayResize(be_positions, be_count + 1);
      be_positions[be_count] = ticket;
      be_count++;
   }

   //--- Limpiar tickets cerrados de la lista
   void CleanupBreakevenList()
   {
      ulong temp[];
      int temp_count = 0;

      for(int i = 0; i < be_count; i++) {
         if(m_position.SelectByTicket(be_positions[i])) {
            ArrayResize(temp, temp_count + 1);
            temp[temp_count] = be_positions[i];
            temp_count++;
         }
      }

      ArrayCopy(be_positions, temp);
      be_count = temp_count;
   }

public:
   //--- Constructor
   CBreakevenManager() : be_count(0)
   {
      ArrayResize(be_positions, 0);
   }

   //--- Verificar si debe mover a breakeven
   bool ShouldMoveToBreakeven(ulong ticket)
   {
      if(!UseBreakeven) return false;
      if(IsAlreadyInBreakeven(ticket)) return false;

      if(!m_position.SelectByTicket(ticket)) return false;

      double open_price = m_position.PriceOpen();
      double current_sl = m_position.StopLoss();
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

      // Verificar si alcanzó el nivel de activación
      if(profit_points >= BreakevenActivation) {
         return true;
      }

      return false;
   }

   //--- Mover posición a breakeven
   bool MoveToBreakeven(ulong ticket)
   {
      if(!m_position.SelectByTicket(ticket)) return false;

      double open_price = m_position.PriceOpen();
      double current_tp = m_position.TakeProfit();
      ENUM_POSITION_TYPE type = m_position.PositionType();

      double new_sl = 0;
      double offset_points = BreakevenOffset * _Point;

      if(type == POSITION_TYPE_BUY) {
         new_sl = NormalizeDouble(open_price + offset_points, _Digits);
      }
      else {
         new_sl = NormalizeDouble(open_price - offset_points, _Digits);
      }

      // Modificar posición
      if(trade.PositionModify(ticket, new_sl, current_tp)) {
         AddToBreakevenList(ticket);

         Print("🔒 BREAKEVEN aplicado: Ticket=", ticket,
               " Tipo=", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
               " SL=", DoubleToString(new_sl, _Digits),
               " (Precio apertura + ", DoubleToString(BreakevenOffset, 1), " pips)");

         return true;
      }

      return false;
   }

   //--- Verificar y aplicar breakeven a todas las posiciones
   void CheckBreakeven()
   {
      if(!UseBreakeven) return;

      // Limpiar lista de tickets cerrados
      CleanupBreakevenList();

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_position.SelectByIndex(i)) continue;

         if(m_position.Symbol() != _Symbol) continue;
         if(m_position.Magic() != MagicNumber_Hilo) continue;

         ulong ticket = m_position.Ticket();

         if(ShouldMoveToBreakeven(ticket)) {
            MoveToBreakeven(ticket);
         }
      }
   }

   //--- Obtener estado de breakeven para una posición
   string GetBreakevenStatus(ulong ticket)
   {
      if(!UseBreakeven) return "OFF";

      if(IsAlreadyInBreakeven(ticket)) {
         return "ACTIVO 🔒";
      }

      if(!m_position.SelectByTicket(ticket)) return "N/A";

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

      double needed = BreakevenActivation - profit_points;

      if(needed > 0) {
         return "Esperando +" + DoubleToString(needed, 1) + " pips";
      }

      return "Listo";
   }

   //--- Reset (llamar al inicio del día)
   void Reset()
   {
      ArrayResize(be_positions, 0);
      be_count = 0;
   }
};

//--- Instancia global
CBreakevenManager g_breakeven;
//+------------------------------------------------------------------+
