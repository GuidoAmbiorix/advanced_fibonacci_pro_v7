//+------------------------------------------------------------------+
//|                                                  R_Killzones.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Gestión de ICT Killzones                                |
//+------------------------------------------------------------------+
class CKillzoneManager
{
private:
   datetime last_check_time;
   ENUM_KILLZONE current_killzone;

   //--- Convertir hora del servidor a GMT/UTC
   datetime ConvertToGMT(datetime server_time)
   {
      return server_time - (ServerTimeOffset * 3600);
   }

   //--- Obtener hora actual del servidor
   MqlDateTime GetCurrentTime()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return dt;
   }

   //--- Verificar si está en rango de tiempo
   bool IsInTimeRange(int current_hour, int current_min, int start_hour, int start_min, int end_hour, int end_min)
   {
      int current_minutes = current_hour * 60 + current_min;
      int start_minutes = start_hour * 60 + start_min;
      int end_minutes = end_hour * 60 + end_min;

      // Manejar cruce de medianoche
      if(end_minutes < start_minutes) {
         return (current_minutes >= start_minutes || current_minutes <= end_minutes);
      }

      return (current_minutes >= start_minutes && current_minutes <= end_minutes);
   }

public:
   //--- Constructor
   CKillzoneManager() : last_check_time(0), current_killzone(KILLZONE_NONE) {}

   //--- Detectar killzone actual
   ENUM_KILLZONE DetectCurrentKillzone()
   {
      if(!UseKillzones) return KILLZONE_OVERLAP_LONDON_NY; // Si no usa filtro, permite todo

      MqlDateTime dt = GetCurrentTime();
      int hour = dt.hour;
      int minute = dt.min;

      // Ajustar por offset del servidor
      hour = (hour - ServerTimeOffset + 24) % 24;

      // Verificar overlap London-NY primero (prioritario)
      if(TradeLondonNYOverlap) {
         if(IsInTimeRange(hour, minute, NY_OPEN_START_HOUR, NY_OPEN_START_MINUTE,
                         NY_OPEN_END_HOUR, NY_OPEN_END_MINUTE)) {
            return KILLZONE_OVERLAP_LONDON_NY;
         }
      }

      // London Open
      if(TradeLondonOpen) {
         if(IsInTimeRange(hour, minute, LONDON_OPEN_START_HOUR, LONDON_OPEN_START_MINUTE,
                         LONDON_OPEN_END_HOUR, LONDON_OPEN_END_MINUTE)) {
            return KILLZONE_LONDON_OPEN;
         }
      }

      // London Close
      if(TradeLondonClose) {
         if(IsInTimeRange(hour, minute, LONDON_CLOSE_START_HOUR, LONDON_CLOSE_START_MINUTE,
                         LONDON_CLOSE_END_HOUR, LONDON_CLOSE_END_MINUTE)) {
            return KILLZONE_LONDON_CLOSE;
         }
      }

      // NY Open (solo si no está en overlap)
      if(TradeNYOpen && !TradeLondonNYOverlap) {
         if(IsInTimeRange(hour, minute, NY_OPEN_START_HOUR, NY_OPEN_START_MINUTE,
                         NY_OPEN_END_HOUR, NY_OPEN_END_MINUTE)) {
            return KILLZONE_NY_OPEN;
         }
      }

      // Asian
      if(TradeAsianKillzone) {
         if(IsInTimeRange(hour, minute, ASIAN_START_HOUR, ASIAN_START_MINUTE,
                         ASIAN_END_HOUR, ASIAN_END_MINUTE)) {
            return KILLZONE_ASIAN;
         }
      }

      return KILLZONE_NONE;
   }

   //--- Actualizar y obtener killzone actual
   ENUM_KILLZONE GetCurrentKillzone()
   {
      current_killzone = DetectCurrentKillzone();
      return current_killzone;
   }

   //--- Verificar si se puede operar ahora
   bool CanTradeNow()
   {
      if(!UseKillzones) return true; // Si no usa filtro, siempre permite

      ENUM_KILLZONE kz = GetCurrentKillzone();

      if(kz == KILLZONE_NONE) {
         return false;
      }

      return true;
   }

   //--- Obtener nombre de la killzone
   string GetKillzoneName(ENUM_KILLZONE kz = KILLZONE_NONE)
   {
      if(kz == KILLZONE_NONE) kz = current_killzone;

      switch(kz) {
         case KILLZONE_ASIAN:
            return "ASIAN SESSION";
         case KILLZONE_LONDON_OPEN:
            return "LONDON OPEN";
         case KILLZONE_LONDON_CLOSE:
            return "LONDON CLOSE";
         case KILLZONE_NY_OPEN:
            return "NY OPEN";
         case KILLZONE_OVERLAP_LONDON_NY:
            return "LONDON-NY OVERLAP ⭐";
         default:
            return "FUERA DE KILLZONE";
      }
   }

   //--- Obtener símbolo de estado
   string GetKillzoneStatusSymbol()
   {
      if(!UseKillzones) return "🔄"; // Siempre activo

      ENUM_KILLZONE kz = GetCurrentKillzone();

      if(kz == KILLZONE_NONE) return "⏸️"; // Pausado
      if(kz == KILLZONE_OVERLAP_LONDON_NY) return "⭐"; // Óptimo

      return "🟢"; // Activo
   }

   //--- Verificar si es overlap (mejor horario)
   bool IsLondonNYOverlap()
   {
      return (current_killzone == KILLZONE_OVERLAP_LONDON_NY);
   }

   //--- Obtener horario de próxima killzone
   string GetNextKillzone()
   {
      MqlDateTime dt = GetCurrentTime();
      int current_hour = (dt.hour - ServerTimeOffset + 24) % 24;
      int current_min = dt.min;

      // Calcular minutos desde medianoche
      int current_total_min = current_hour * 60 + current_min;

      // Horarios de inicio de killzones (en minutos desde medianoche)
      int asian_start = ASIAN_START_HOUR * 60;
      int london_start = LONDON_OPEN_START_HOUR * 60;
      int ny_start = NY_OPEN_START_HOUR * 60;

      int next_start = -1;
      string next_name = "";

      // Encontrar la próxima killzone
      if(TradeAsianKillzone && asian_start > current_total_min) {
         next_start = asian_start;
         next_name = "ASIAN";
      }
      else if(TradeLondonOpen && london_start > current_total_min) {
         if(next_start < 0 || london_start < next_start) {
            next_start = london_start;
            next_name = "LONDON OPEN";
         }
      }
      else if(TradeLondonNYOverlap && ny_start > current_total_min) {
         if(next_start < 0 || ny_start < next_start) {
            next_start = ny_start;
            next_name = "LONDON-NY OVERLAP";
         }
      }

      // Si no hay próxima hoy, la próxima es mañana
      if(next_start < 0) {
         if(TradeAsianKillzone) {
            next_start = asian_start + (24 * 60);
            next_name = "ASIAN";
         }
         else if(TradeLondonOpen) {
            next_start = london_start + (24 * 60);
            next_name = "LONDON OPEN";
         }
      }

      if(next_start < 0) return "N/A";

      int minutes_until = next_start - current_total_min;
      if(minutes_until < 0) minutes_until += (24 * 60);

      int hours = minutes_until / 60;
      int mins = minutes_until % 60;

      return next_name + " (en " + IntegerToString(hours) + "h " + IntegerToString(mins) + "m)";
   }

   //--- Log de cambio de killzone
   void LogKillzoneChange()
   {
      static ENUM_KILLZONE last_logged = KILLZONE_NONE;

      ENUM_KILLZONE current = GetCurrentKillzone();

      if(current != last_logged) {
         Print("╔════════════════════════════════════════╗");
         Print("║  CAMBIO DE KILLZONE                    ║");
         Print("╠════════════════════════════════════════╣");
         Print("║  ", GetKillzoneName(current));
         Print("║  Status: ", GetKillzoneStatusSymbol(), " ", CanTradeNow() ? "TRADING ACTIVO" : "TRADING PAUSADO");
         Print("╚════════════════════════════════════════╝");

         last_logged = current;
      }
   }
};

//--- Instancia global
CKillzoneManager g_killzones;
//+------------------------------------------------------------------+
