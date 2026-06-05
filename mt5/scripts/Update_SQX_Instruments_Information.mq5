//+------------------------------------------------------------------+
//|         Update_SQX_Instruments_Information.mq5                   |
//|   Exporta especificaciones de instrumentos del broker a CSV      |
//|   para configurar manualmente el Broker Profile en SQX.          |
//+------------------------------------------------------------------+
#property copyright   "StrategyQuant X - CSV Exporter"
#property link        "https://strategyquant.com"
#property version     "3.00"
#property description "Exporta datos de instrumentos a un unico CSV para SQX"
#property script_show_inputs

//--- Parámetros de entrada
input string  InpFileName           = "Broker_Instruments_Goat.csv"; // Nombre del archivo CSV
input bool    InpOnlyMarketWatch    = true;                          // Solo simbolos en MarketWatch
input string  InpSymbolFilter       = "";                            // Filtro (Ej: "EUR")

//+------------------------------------------------------------------+
//| Función principal                                                |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("==================================================");
   Print("  SQX Broker CSV Exporter v3.00");
   Print("==================================================");

   //--- Abrir archivo para escritura
   int handle = FileOpen(InpFileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
     {
      Print("[ERROR] No se pudo crear el archivo: ", InpFileName, " | Error: ", GetLastError());
      return;
     }

   //--- Escribir Encabezado (Paso 2 del manual)
   FileWrite(handle, 
             "Symbol", 
             "ContractSize", 
             "MinLot", 
             "MaxLot", 
             "LotStep", 
             "TickSize", 
             "TickValue", 
             "StopsLevel", 
             "FreezeLevel", 
             "Digits");

   int totalSymbols = SymbolsTotal(InpOnlyMarketWatch);
   int exported     = 0;

   Print("[INFO] Procesando ", totalSymbols, " simbolos...");

   for(int i = 0; i < totalSymbols; i++)
     {
      string symbol = SymbolName(i, InpOnlyMarketWatch);
      if(symbol == "") continue;

      // Filtrado
      if(InpSymbolFilter != "" && StringFind(symbol, InpSymbolFilter) < 0) continue;

      // Seleccionar para leer datos
      if(!SymbolSelect(symbol, true)) continue;

      //--- Extraer Datos (Paso 1 del manual)
      double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double minLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      long   stopsLevel   = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long   freezeLevel  = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      long   digits       = SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      //--- Escribir Fila en CSV
      FileWrite(handle, 
                symbol, 
                DoubleToString(contractSize, 2),
                DoubleToString(minLot, 2),
                DoubleToString(maxLot, 2),
                DoubleToString(lotStep, 2),
                DoubleToString(tickSize, (int)digits),
                DoubleToString(tickValue, 6),
                IntegerToString(stopsLevel),
                IntegerToString(freezeLevel),
                IntegerToString(digits));

      exported++;
      Print("[OK] Agregado: ", symbol);
     }

   FileClose(handle);

   Print("==================================================");
   PrintFormat("  ✓ EXPORTACION EXITOSA: %d simbolos", exported);
   PrintFormat("  Archivo: MQL5\\Files\\%s", InpFileName);
   Print("==================================================");
   Print("  PROXIMO PASO:");
   Print("  Abre el CSV en Excel o Notepad para ver los datos");
   Print("  e ingresalos en el Broker Profile de StrategyQuant X.");
   Print("==================================================");
  }
