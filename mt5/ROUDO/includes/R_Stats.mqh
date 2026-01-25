//+------------------------------------------------------------------+
//|                                                      R_Stats.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Estadísticas y Conteo                                   |
//+------------------------------------------------------------------+
class CStatsManager
{
private:

public:
   //--- Constructor
   CStatsManager() {}

   //--- Calcular ganancia desde medianoche
   double GetDailyProfit()
   {
      double profit = 0;
      datetime last_midnight = iTime(_Symbol, PERIOD_D1, 0);

      if(!HistorySelect(last_midnight, TimeCurrent())) {
         Print("ERROR: No se pudo seleccionar historial");
         return 0;
      }

      for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber_Hilo) {
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         }
      }

      return profit;
   }

   //--- Contar posiciones abiertas del EA
   int GetTotalPositions()
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

   //--- Obtener información de posiciones por tipo
   int GetPositionsByType(ENUM_POSITION_TYPE type)
   {
      int count = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() == _Symbol &&
               m_position.Magic() == MagicNumber_Hilo &&
               m_position.PositionType() == type) {
               count++;
            }
         }
      }

      return count;
   }

   //--- Obtener volumen total de posiciones
   double GetTotalVolume()
   {
      double total_volume = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() == _Symbol && m_position.Magic() == MagicNumber_Hilo) {
               total_volume += m_position.Volume();
            }
         }
      }

      return total_volume;
   }

   //--- Obtener profit flotante actual
   double GetFloatingProfit()
   {
      double floating = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() == _Symbol && m_position.Magic() == MagicNumber_Hilo) {
               floating += m_position.Profit();
            }
         }
      }

      return floating;
   }
};

//--- Instancia global
CStatsManager g_stats;
//+------------------------------------------------------------------+
