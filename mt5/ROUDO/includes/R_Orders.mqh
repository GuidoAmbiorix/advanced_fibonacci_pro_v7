//+------------------------------------------------------------------+
//|                                                     R_Orders.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Gestión de Órdenes                                      |
//+------------------------------------------------------------------+
class COrderManager
{
private:

public:
   //--- Constructor
   COrderManager() {}

   //--- Abrir posición inicial basada en señal MACD
   bool OpenInitialPosition()
   {
      int signal = g_indicators.GetMACDSignal();

      if(signal == 0) return false; // Sin señal

      double ask = g_symbol_manager.Ask();
      double bid = g_symbol_manager.Bid();
      bool result = false;

      if(signal == 1) { // Señal BUY
         double tp = ask + TakeProfit * _Point;
         result = trade.Buy(Lots, _Symbol, ask, 0, tp, "ROUDO Initial BUY");
         if(result) Print("Posición BUY abierta en ", ask);
      }
      else if(signal == -1) { // Señal SELL
         double tp = bid - TakeProfit * _Point;
         result = trade.Sell(Lots, _Symbol, bid, 0, tp, "ROUDO Initial SELL");
         if(result) Print("Posición SELL abierta en ", bid);
      }

      return result;
   }

   //--- Obtener información de la última posición abierta
   bool GetLastPositionInfo(double &last_price, double &last_lot, ENUM_POSITION_TYPE &type)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Magic() == MagicNumber_Hilo && m_position.Symbol() == _Symbol) {
               last_price = m_position.PriceOpen();
               last_lot   = m_position.Volume();
               type       = m_position.PositionType();
               return true;
            }
         }
      }
      return false;
   }

   //--- Gestionar Martingala (agregar orden en grilla)
   void ManageMartingale()
   {
      // 1. Verificar permisos de riesgo
      if(!g_risk.CanAddMartingaleOrder()) return;

      // 2. Obtener información de la última posición
      double last_price = 0, last_lot = 0;
      ENUM_POSITION_TYPE position_type;

      if(!GetLastPositionInfo(last_price, last_lot, position_type)) {
         Print("No se encontró posición para martingala");
         return;
      }

      // 3. Calcular step basado en ATR
      double step = g_indicators.GetGridStep();

      // 4. Obtener precios actuales
      double ask = g_symbol_manager.Ask();
      double bid = g_symbol_manager.Bid();

      // 5. Verificar si se debe agregar orden
      bool should_add = false;

      if(position_type == POSITION_TYPE_BUY && ask < (last_price - step)) {
         should_add = true;
      }
      else if(position_type == POSITION_TYPE_SELL && bid > (last_price + step)) {
         should_add = true;
      }

      if(!should_add) return;

      // 6. Calcular nuevo lote
      double new_lot = g_risk.CalculateMartingaleLot(last_lot);

      // 7. Abrir orden
      bool result = false;

      if(position_type == POSITION_TYPE_BUY) {
         result = trade.Buy(new_lot, _Symbol, ask, 0, 0, "ROUDO Martingale BUY");
         if(result) {
            Print("Orden martingala BUY agregada: Lote=", new_lot, " Precio=", ask);
            UpdateGlobalTakeProfit(POSITION_TYPE_BUY);
         }
      }
      else {
         result = trade.Sell(new_lot, _Symbol, bid, 0, 0, "ROUDO Martingale SELL");
         if(result) {
            Print("Orden martingala SELL agregada: Lote=", new_lot, " Precio=", bid);
            UpdateGlobalTakeProfit(POSITION_TYPE_SELL);
         }
      }
   }

   //--- Actualizar TP global para todas las posiciones del mismo tipo
   void UpdateGlobalTakeProfit(ENUM_POSITION_TYPE type)
   {
      double total_volume = 0;
      double total_weighted_price = 0;

      // 1. Calcular precio promedio ponderado
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Magic() == MagicNumber_Hilo &&
               m_position.Symbol() == _Symbol &&
               m_position.PositionType() == type) {

               total_volume += m_position.Volume();
               total_weighted_price += m_position.PriceOpen() * m_position.Volume();
            }
         }
      }

      if(total_volume <= 0) return;

      // 2. Calcular break-even y nuevo TP
      double break_even = total_weighted_price / total_volume;
      double new_tp = 0;

      if(type == POSITION_TYPE_BUY) {
         new_tp = break_even + TakeProfit * _Point;
      } else {
         new_tp = break_even - TakeProfit * _Point;
      }

      // 3. Actualizar TP en todas las posiciones del tipo
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Magic() == MagicNumber_Hilo &&
               m_position.PositionType() == type) {

               trade.PositionModify(m_position.Ticket(), 0, new_tp);
            }
         }
      }

      Print("TP global actualizado para ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
            ": BE=", DoubleToString(break_even, _Digits),
            " TP=", DoubleToString(new_tp, _Digits));
   }
};

//--- Instancia global
COrderManager g_orders;
//+------------------------------------------------------------------+
