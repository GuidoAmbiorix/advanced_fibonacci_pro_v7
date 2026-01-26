//+------------------------------------------------------------------+
//|                                                 R_Indicators.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Gestión de Indicadores                                  |
//+------------------------------------------------------------------+
class CIndicatorManager
{
private:
   int handle_macd_M1;

public:
   int handle_atr; // Público para acceso desde otros módulos
   //--- Constructor
   CIndicatorManager() : handle_macd_M1(INVALID_HANDLE), handle_atr(INVALID_HANDLE) {}

   //--- Inicialización de indicadores
   bool Init()
   {
      // MACD en M1 (8,17,9)
      handle_macd_M1 = iMACD(_Symbol, PERIOD_M1, 8, 17, 9, PRICE_CLOSE);
      if(handle_macd_M1 == INVALID_HANDLE) {
         Print("ERROR: No se pudo crear el indicador MACD M1");
         return false;
      }

      // ATR en timeframe actual
      handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
      if(handle_atr == INVALID_HANDLE) {
         Print("ERROR: No se pudo crear el indicador ATR");
         return false;
      }

      Print("Indicadores inicializados correctamente");
      return true;
   }

   //--- Obtener señal MACD (BUY/SELL/NEUTRAL)
   int GetMACDSignal()
   {
      double macd_main[], macd_signal[];
      ArraySetAsSeries(macd_main, true);
      ArraySetAsSeries(macd_signal, true);

      if(CopyBuffer(handle_macd_M1, 0, 0, 2, macd_main) <= 0) {
         Print("ERROR: No se pudo copiar buffer MACD Main");
         return 0;
      }

      if(CopyBuffer(handle_macd_M1, 1, 0, 2, macd_signal) <= 0) {
         Print("ERROR: No se pudo copiar buffer MACD Signal");
         return 0;
      }

      // Señal de compra: Main cruza por encima de Signal
      if(macd_main[0] > macd_signal[0]) return 1;  // BUY

      // Señal de venta: Main cruza por debajo de Signal
      if(macd_main[0] < macd_signal[0]) return -1; // SELL

      return 0; // Neutral
   }

   //--- Obtener valor actual del ATR
   double GetATR()
   {
      double atr[];
      ArraySetAsSeries(atr, true);

      if(CopyBuffer(handle_atr, 0, 0, 1, atr) <= 0) {
         Print("ERROR: No se pudo copiar buffer ATR");
         return 0;
      }

      return atr[0];
   }

   //--- Calcular distancia para la siguiente orden martingala
   double GetGridStep()
   {
      double atr_value = GetATR();
      if(atr_value <= 0) {
         Print("ADVERTENCIA: ATR inválido, usando step mínimo");
         return 200 * _Point;
      }

      // Step = ATR * Multiplicador, mínimo 200 puntos
      double step = MathMax(atr_value * ATR_Multiplier, 200 * _Point);
      return step;
   }

   //--- Destructor
   ~CIndicatorManager()
   {
      if(handle_macd_M1 != INVALID_HANDLE) IndicatorRelease(handle_macd_M1);
      if(handle_atr != INVALID_HANDLE)     IndicatorRelease(handle_atr);
   }
};

//--- Instancia global
CIndicatorManager g_indicators;
//+------------------------------------------------------------------+
