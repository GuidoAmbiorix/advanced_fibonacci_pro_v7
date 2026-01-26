//+------------------------------------------------------------------+
//|                                                    R_AutoLot.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Cálculo Automático de Lote                              |
//+------------------------------------------------------------------+
class CAutoLotManager
{
private:

public:
   //--- Constructor
   CAutoLotManager() {}

   //--- Calcular lote automático basado en riesgo
   double CalculateAutoLotSize()
   {
      // Verificar si está habilitado
      #ifdef UseAutoLotSize
         if(!UseAutoLotSize) return Lots;
      #else
         return Lots;
      #endif

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      #ifdef RiskPercentPerTrade
         double risk_percent = RiskPercentPerTrade;
      #else
         double risk_percent = 2.0; // Default
      #endif

      double risk_amount = equity * (risk_percent / 100.0);

      // Para oro: aproximadamente $1 por pip por 0.01 lote
      // Asumiendo SL virtual de 100 pips (conservador)
      double assumed_sl_pips = 100.0;
      double pip_value_per_microlot = 0.01; // $0.01 por pip por 0.01 lote

      double calculated_lot = (risk_amount / assumed_sl_pips) / pip_value_per_microlot;

      // Normalizar al step del símbolo
      double volume_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double volume_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      calculated_lot = NormalizeDouble(calculated_lot, 2);
      calculated_lot = MathFloor(calculated_lot / volume_step) * volume_step;
      calculated_lot = MathMax(calculated_lot, volume_min);
      calculated_lot = MathMin(calculated_lot, volume_max);

      #ifdef MaxLots
         calculated_lot = MathMin(calculated_lot, MaxLots);
      #endif

      Print("💰 Auto Lot Calculation:");
      Print("  Equity: $", equity);
      Print("  Risk: ", risk_percent, "% = $", DoubleToString(risk_amount, 2));
      Print("  Calculated Lot: ", DoubleToString(calculated_lot, 3));

      return calculated_lot;
   }
};

//--- Instancia global
CAutoLotManager g_autolot;
//+------------------------------------------------------------------+
