//+------------------------------------------------------------------+
//|                                                     R_Symbol.mqh |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Gestión del Símbolo                                     |
//+------------------------------------------------------------------+
class CSymbolManager
{
private:

public:
   //--- Constructor
   CSymbolManager() {}

   //--- Inicialización
   bool Init()
   {
      if(!m_symbol.Name(_Symbol)) {
         Print("ERROR: No se pudo inicializar el símbolo ", _Symbol);
         return false;
      }
      return true;
   }

   //--- Actualizar precios
   bool RefreshRates()
   {
      return m_symbol.RefreshRates();
   }

   //--- Obtener spread actual
   int GetSpread()
   {
      return m_symbol.Spread();
   }

   //--- Verificar si el spread es válido
   bool IsSpreadValid()
   {
      return (m_symbol.Spread() <= Max_Spread);
   }

   //--- Obtener precios
   double Ask() { return m_symbol.Ask(); }
   double Bid() { return m_symbol.Bid(); }

   //--- Información de volumen
   double GetVolumeStep()
   {
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   }

   //--- Información de margen
   double GetMarginLevel()
   {
      return AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   }

   //--- Verificar condiciones de mercado
   bool CanTrade()
   {
      if(!RefreshRates()) {
         Print("No se pudieron actualizar los precios");
         return false;
      }

      if(!IsSpreadValid()) {
         Print("Spread muy alto: ", GetSpread(), " (Máx: ", Max_Spread, ")");
         return false;
      }

      return true;
   }
};

//--- Instancia global
CSymbolManager g_symbol_manager;
//+------------------------------------------------------------------+
