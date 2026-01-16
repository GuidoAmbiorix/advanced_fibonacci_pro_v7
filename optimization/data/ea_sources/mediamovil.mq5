//+------------------------------------------------------------------+
//|                     Media Móvil PRO v2.0 SCALPER                 |
//|                          Enhanced by Antigravity AI              |
//|      ADX + RSI + Triple MA + ATR Dynamic SL/TP (SCALPING)        |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Información del Asesor                                           |
//+------------------------------------------------------------------+

#property copyright "Enhanced by Antigravity AI - Original by José Martínez"
#property description "SCALPING MA System: Fast MAs + ADX + RSI + ATR Tight Stops | Use on M1-M15" 
#property link      ""
#property version   "2.00"

//+------------------------------------------------------------------+
//| Notas del Asesor v2.0                                            |
//+------------------------------------------------------------------+
// v2.0 UPGRADES (2024 Best Practices):
// - ADX Trend Strength Filter: Only trade when ADX > threshold
// - RSI Entry Filter: Prevent overbought/oversold entries  
// - Triple MA Confirmation: Fast + Medium + Slow alignment
// - ATR-based Dynamic SL/TP: Adapts to market volatility
// - Enhanced Dashboard: Real-time indicator display
// - Removed fixed point SL/TP in favor of ATR-based

//+------------------------------------------------------------------+
//| AE Enumeraciones                                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Variables Input y Globales                                       |
//+------------------------------------------------------------------+

sinput group                              "### AE AJUSTES GENERALES ###"
input ulong                               MagicNumber                      = 101;
input bool                                UsarPoliticaLlenado              = false;
input ENUM_ORDER_TYPE_FILLING             PoliticaLlenado                  = ORDER_FILLING_IOC;

sinput group                              "### MEDIA MÓVIL - SCALPING OPTIMIZED ###"
input int                                 PeriodoMA                        = 15;       // Medium MA (Scalping: 15)
input ENUM_MA_METHOD                      MetodoMA                         = MODE_EMA; // EMA for faster response
input int                                 ShiftMA                          = 0;
input ENUM_APPLIED_PRICE                  PrecioMA                         = PRICE_CLOSE;

sinput group                              "### TRIPLE MA - SCALPING ###"
input bool                                UseTripleMA                      = true;     // Enable Triple MA Filter
input int                                 FastMA_Period                    = 5;        // Fast MA (Scalping: 5)
input int                                 SlowMA_Period                    = 50;       // Slow MA (Scalping: 50)

sinput group                              "### ADX - SCALPING ###"
input bool                                UseADXFilter                     = true;     // Enable ADX Filter
input int                                 ADX_Period                       = 7;        // ADX Period (Scalping: 7 faster)
input int                                 ADX_Threshold                    = 20;       // Min ADX (Scalping: 20 more signals)

sinput group                              "### RSI - SCALPING ###"
input bool                                UseRSIFilter                     = true;     // Use RSI in Entry Logic
input int                                 RSI_Period                       = 7;        // RSI Period (Scalping: 7 faster)
input ENUM_APPLIED_PRICE                  RSI_Price                        = PRICE_CLOSE;
input int                                 RSI_BuyMax                       = 55;       // Max RSI for BUY (Scalping: 55)
input int                                 RSI_SellMin                      = 45;       // Min RSI for SELL (Scalping: 45)

sinput group                              "### ATR SCALPING SL/TP ###"
input bool                                UseATRStops                      = true;     // Use ATR-based SL/TP
input int                                 ATR_Period                       = 7;        // ATR Period (Scalping: 7)
input double                              ATR_SL_Mult                      = 0.8;      // SL = ATR × 0.8 (Tight for scalping)
input double                              ATR_TP_Mult                      = 1.5;      // TP = ATR × 1.5 (Quick profits)

sinput group                              "### GESTIÓN MONETARIA ###"
input double                              RiskPercent                      = 0.5;      // Risk Per Trade (Scalping: 0.5%)

sinput group                              "### GESTIÓN DE POSICIONES (LEGACY) ###"
input int                                 SLPuntosFijos                    = 0;        // Fixed SL (0 = use ATR)
input int                                 SLPuntosFijosMA                  = 0;        // SL from MA (0 = use ATR)
input int                                 TPPuntosFijos                    = 0;        // Fixed TP (0 = use ATR)
input int                                 TSLPuntosFijos                   = 50;       // Trailing SL (Scalping: 50 pts)
input int                                 BEPuntosFijos                    = 30;       // Break-Even (Scalping: 30 pts)


// Global Variables
datetime glTiempoBarraApertura;
int      ManejadorMA;
int      RSI_Handle;
int      ADX_Handle;
int      ATR_Handle;
int      FastMA_Handle;
int      SlowMA_Handle;

// Global Indicator Values
double g_RSI, g_ADX, g_ATR;
double g_FastMA, g_MediumMA, g_SlowMA;


//+------------------------------------------------------------------+
//| Procesadores de Eventos                                          |
//+------------------------------------------------------------------+


int OnInit()
{
   glTiempoBarraApertura = D'1971.01.01 00:00';
   
   // Initialize Medium MA (main signal MA)
   ManejadorMA = MA_Init(PeriodoMA, ShiftMA, MetodoMA, PrecioMA);
   if(ManejadorMA == -1) return(INIT_FAILED);
   
   // Initialize RSI
   RSI_Handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, RSI_Price);
   if(RSI_Handle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize ADX for trend strength
   ADX_Handle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   if(ADX_Handle == INVALID_HANDLE)
   {
      Print("Error creating ADX indicator handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize ATR for dynamic SL/TP
   ATR_Handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE)
   {
      Print("Error creating ATR indicator handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize Fast MA for Triple MA confirmation
   FastMA_Handle = iMA(_Symbol, PERIOD_CURRENT, FastMA_Period, 0, MetodoMA, PrecioMA);
   if(FastMA_Handle == INVALID_HANDLE)
   {
      Print("Error creating Fast MA indicator handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize Slow MA (EMA200) for trend filter
   SlowMA_Handle = iMA(_Symbol, PERIOD_CURRENT, SlowMA_Period, 0, MODE_EMA, PrecioMA);
   if(SlowMA_Handle == INVALID_HANDLE)
   {
      Print("Error creating Slow MA indicator handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   Print("🚀 Media Móvil PRO v2.0 Initialized!");
   Print("   ADX Filter: ", UseADXFilter ? "ON (>" + string(ADX_Threshold) + ")" : "OFF");
   Print("   RSI Filter: ", UseRSIFilter ? "ON" : "OFF");
   Print("   Triple MA: ", UseTripleMA ? "ON" : "OFF");
   Print("   ATR Stops: ", UseATRStops ? "ON" : "OFF");
   
   return(INIT_SUCCEEDED);
}
  
void OnDeinit(const int reason)
{
   // Release all indicator handles
   IndicatorRelease(ManejadorMA);
   IndicatorRelease(RSI_Handle);
   IndicatorRelease(ADX_Handle);
   IndicatorRelease(ATR_Handle);
   IndicatorRelease(FastMA_Handle);
   IndicatorRelease(SlowMA_Handle);
   
   ObjectsDeleteAll(0, "MAPRO_");
   Print("Media Móvil PRO v2.0 Removed");
}
  
void OnTick()
{  
   //------------------------//
   // CONTROL DE NUEVA BARRA //
   //------------------------//
   
   bool nuevaBarra = false;
   
   // Comprobación de nueva barra
   if(glTiempoBarraApertura != iTime(_Symbol,PERIOD_CURRENT,0))
   {
      nuevaBarra = true;
      glTiempoBarraApertura = iTime(_Symbol,PERIOD_CURRENT,0);
   }
   
   // Update indicators and dashboard on every tick
   UpdateAllIndicators();
   UpdateDashboard();
   
   if(nuevaBarra == true)
   {           
      //------------------------//
      // PRECIO E INDICADORES   //
      //------------------------//
      
      // Precio
      double cierre1 = Close(1);
      double cierre2 = Close(2);
      
      // Normalización a tick size (tamaño del tick)
      double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);     
      cierre1 = round(cierre1/tickSize) * tickSize; 
      cierre2 = round(cierre2/tickSize) * tickSize;
      
      // Media Móvil (MA)
      double ma1 = ma(ManejadorMA,1);
      double ma2 = ma(ManejadorMA,2);
      
      //------------------------//
      // CIERRE DE POSICIONES   //
      //------------------------//
      
      // Señal de cierre && Cierre de posiciones
      string exitSignal = MA_ExitSignal(cierre1,cierre2,ma1,ma2);
      
      if(exitSignal == "CIERRE_LARGO" || exitSignal == "CIERRE_CORTO"){
         CierrePosiciones(MagicNumber,exitSignal,UsarPoliticaLlenado,PoliticaLlenado);}
         
      Sleep(1000);   
      
      //------------------------//
      // COLOCACIÓN DE ÓRDENES  //
      //------------------------//   
   
      // Señal de entrada (MA Crossover básico)
      string entrySignal = MA_EntrySignal(cierre1,cierre2,ma1,ma2);
      
      // ========================================
      // V2.0 PROFESSIONAL FILTERS
      // ========================================
      bool filtersPass = true;
      string filterStatus = "";
      
      // 1. ADX Trend Strength Filter
      if(UseADXFilter)
      {
         if(g_ADX < ADX_Threshold)
         {
            filtersPass = false;
            filterStatus += "ADX(" + DoubleToString(g_ADX,1) + "<" + string(ADX_Threshold) + ") ";
         }
      }
      
      // 2. RSI Entry Filter
      if(UseRSIFilter && filtersPass)
      {
         if(entrySignal == "LARGO" && g_RSI > RSI_BuyMax)
         {
            filtersPass = false;
            filterStatus += "RSI(" + DoubleToString(g_RSI,1) + ">" + string(RSI_BuyMax) + ") ";
         }
         else if(entrySignal == "CORTO" && g_RSI < RSI_SellMin)
         {
            filtersPass = false;
            filterStatus += "RSI(" + DoubleToString(g_RSI,1) + "<" + string(RSI_SellMin) + ") ";
         }
      }
      
      // 3. Triple MA Confirmation
      if(UseTripleMA && filtersPass)
      {
         // For LONG: Fast > Medium > Slow (bullish alignment)
         // For SHORT: Fast < Medium < Slow (bearish alignment)
         if(entrySignal == "LARGO")
         {
            if(!(g_FastMA > g_MediumMA && g_MediumMA > g_SlowMA))
            {
               filtersPass = false;
               filterStatus += "TripleMA(Not Aligned) ";
            }
         }
         else if(entrySignal == "CORTO")
         {
            if(!(g_FastMA < g_MediumMA && g_MediumMA < g_SlowMA))
            {
               filtersPass = false;
               filterStatus += "TripleMA(Not Aligned) ";
            }
         }
      }
      
      // Log filter rejection
      if(!filtersPass && (entrySignal == "LARGO" || entrySignal == "CORTO"))
      {
         Print("❌ Signal ", entrySignal, " REJECTED: ", filterStatus);
      }
      
      // ========================================
      // EXECUTE TRADE IF ALL FILTERS PASS
      // ========================================
      if((entrySignal == "LARGO" || entrySignal == "CORTO") && 
         filtersPass && 
         RevisionPosicionesColocadas(MagicNumber) == false)
      {
         // Calculate SL distance for lot sizing
         double slDistance = g_ATR * ATR_SL_Mult;
         double slPoints = slDistance / _Point;
         
         // Calculate dynamic lot size based on risk
         double dynamicLotSize = CalculateDynamicLotSize(RiskPercent, slPoints);
         
         Print("✅ Signal ", entrySignal, " CONFIRMED! ADX:", DoubleToString(g_ADX,1), 
               " RSI:", DoubleToString(g_RSI,1), " ATR:", DoubleToString(g_ATR,_Digits));

         ulong ticket = AperturaTrades(entrySignal, MagicNumber, dynamicLotSize, UsarPoliticaLlenado, PoliticaLlenado);
         
         // Modificación de SL & TP
         if(ticket > 0)
         {
            double stopLoss = 0;
            double takeProfit = 0;
            
            // Use ATR-based SL/TP if enabled
            if(UseATRStops)
            {
               stopLoss = CalcularStopLossATR(entrySignal, g_ATR, ATR_SL_Mult);
               takeProfit = CalcularTakeProfitATR(entrySignal, g_ATR, ATR_TP_Mult);
            }
            else
            {
               // Legacy fixed point SL/TP
               stopLoss = CalcularStopLoss(entrySignal, SLPuntosFijos, SLPuntosFijosMA, ma1);
               takeProfit = CalcularTakeProfit(entrySignal, TPPuntosFijos);
            }
            
            ModificacionPosiciones(ticket, MagicNumber, stopLoss, takeProfit);        
         }
      }
           
      //------------------------//
      // GESTIÓN DE POSICIONES  //
      //------------------------//
      
      if(TSLPuntosFijos > 0) TrailingStopLoss(MagicNumber,TSLPuntosFijos);
      if(BEPuntosFijos > 0) BreakEven(MagicNumber,BEPuntosFijos);
   }
}


//+------------------------------------------------------------------+
//| AE Funciones                                                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate dynamic position size based on account balance         |
//+------------------------------------------------------------------+
double CalculateDynamicLotSize(double riskPercentage, double stopLossPips)
{
   if(stopLossPips <= 0)
      return 0; // Return 0 if stopLossPips is not set properly

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * riskPercentage ;

   double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / 
                     SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotSize = riskAmount / (stopLossPips * pipValue);

// Adjust lot size based on the minimum and maximum lot size allowed
   double minLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); // Smallest change in volume
   int decimals = -(int)MathLog10(lotStep); // Calculate decimals based on lot step
   lotSize = NormalizeDouble(MathMax(minLotSize, MathMin(lotSize, maxLotSize)), decimals);

   return lotSize;
}

//+----------+// Funciones del Precio //+----------+//

double Close(int pShift)
{
   MqlRates barra[];                            //Crea un objeto array del tipo estructura MqlRates
   ArraySetAsSeries(barra,true);                //Configura nuestro array como un array en serie (la vela actual se copiará en índice 0, la vela 1 en índice 1 y sucesivamente)
   CopyRates(_Symbol,PERIOD_CURRENT,0,3,barra); //Copia datos del precio de barras 0, 1 y 2 a nuestro array barra
   
   return barra[pShift].close;                  //Retorna precio de cierre del objeto barra
}

double Open(int pShift)
{
   MqlRates barra[];                            //Crea un objeto array del tipo estructura MqlRates
   ArraySetAsSeries(barra,true);                //Configura nuestro array como un array en serie (la vela actual se copiará en índice 0, la vela 1 en índice 1 y sucesivamente)
   CopyRates(_Symbol,PERIOD_CURRENT,0,3,barra); //Copia datos del precio de barras 0, 1 y 2 a nuestro array barra
   
   return barra[pShift].open;                   //Retorna precio de apertura del objeto barra
}

//+----------+// Funciones de la Media Móvil //+----------+//

int MA_Init(int pPeriodoMA,int pShiftMA,ENUM_MA_METHOD pMetodoMA,ENUM_APPLIED_PRICE pPrecioMA)
{
   //En caso de error al inicializar el MA, GetLastError() nos dará el código del error y lo almacenará en _LastError
   //ResetLastError cambiará el valor de la variable _LastError a 0
   ResetLastError();
   
   //El manejador es un identificador único para el indicador. Se utiliza para todas las acciones relacionadas con este, como obtener datos o eliminarlo
   int Manejador = iMA(_Symbol,PERIOD_CURRENT,pPeriodoMA,pShiftMA,pMetodoMA,pPrecioMA);
   
   if(Manejador == INVALID_HANDLE)
   {
      return -1;
      Print("Ha habido un error creando el manejador del indicador MA: ", GetLastError());
   }
   
   Print("El manejador del indicador MA se ha creado con éxito");
   
   return Manejador;
}

double ma(int pManejadorMA, int pShift)
{
   ResetLastError();
   
   //Creamos un array que llenaremos con los precios del indicador
   double ma[];
   ArraySetAsSeries(ma,true);
   
   //Llenamos el array con los 3 valores más recientes del MA
   bool resultado = CopyBuffer(pManejadorMA,0,0,3,ma);
   if(resultado == false){
      Print("ERROR AL COPIAR DATOS: ", GetLastError());}
      
   //Preguntamos por el valor del indicador almacenado en pShift
   double valorMA = ma[pShift];
   
   //Normalizamos valorMA a los dígitos de nuestro símbolo y lo retornamos
   valorMA = NormalizeDouble(valorMA,_Digits);
   
   return valorMA;   
}

string MA_EntrySignal(double pPrecio1, double pPrecio2, double pMA1, double pMA2)
{
   string str = "";
   string valores;
   
   if(pPrecio1 > pMA1 && pPrecio2 <= pMA2) {str = "LARGO";}
   else if(pPrecio1 < pMA1 && pPrecio2 >= pMA2) {str = "CORTO";}
   else {str = "NO_OPERAR";}
   
   StringConcatenate(valores,"MA 1: ", DoubleToString(pMA1,_Digits), " | ", "MA 2: ", DoubleToString(pMA2,_Digits), " | ",
                     "Cierre 1: ", DoubleToString(pPrecio1,_Digits), " | ", "Cierre 2: ", DoubleToString(pPrecio2,_Digits));
   
   Print("Valores del precio e indicadores: ", valores);
   
   return str;
}

string MA_ExitSignal(double pPrecio1, double pPrecio2, double pMA1, double pMA2)
{
   string str = "";
   string valores;
   
   if(pPrecio1 > pMA1 && pPrecio2 <= pMA2) {str = "CIERRE_CORTO";}
   else if(pPrecio1 < pMA1 && pPrecio2 >= pMA2) {str = "CIERRE_LARGO";}
   else {str = "NO_CIERRE";}
   
   StringConcatenate(valores,"MA 1: ", DoubleToString(pMA1,_Digits), " | ", "MA 2: ", DoubleToString(pMA2,_Digits), " | ",
                     "Cierre 1: ", DoubleToString(pPrecio1,_Digits), " | ", "Cierre 2: ", DoubleToString(pPrecio2,_Digits));
   
   Print("Valores del precio e indicadores: ", valores);
   
   return str;
}

//+----------+// Funciones de las Bandas de Bollinger //+----------+//

int BB_Init(int pPeriodoBB,int pShiftBB,double pDesviacionBB,ENUM_APPLIED_PRICE pPrecioBB)
{
   //En caso de error al inicializar las BB, GetLastError() nos dará el código del error y lo almacenará en _LastError
   //ResetLastError cambiará el valor de la variable _LastError a 0
   ResetLastError();
   
   //El manejador es un identificador único para el indicador. Se utiliza para todas las acciones relacionadas con este, como obtener datos o eliminarlo
   int Manejador = iBands(_Symbol,PERIOD_CURRENT,pPeriodoBB,pShiftBB,pDesviacionBB,pPrecioBB);
   
   if(Manejador == INVALID_HANDLE)
   {
      return -1;
      Print("Ha habido un error creando el manejador del indicador BB: ", GetLastError());
   }
   
   Print("El manejador del indicador BB se ha creado con éxito");
   
   return Manejador;
}

double BB(int pManejadorBB, int pBuffer, int pShift)
{
   ResetLastError();
   
   //Creamos un array que llenaremos con los precios del indicador
   double BB[];
   ArraySetAsSeries(BB,true);
   
   //Llenamos el array con los 3 valores más recientes del BB
   bool resultado = CopyBuffer(pManejadorBB,pBuffer,0,3,BB);
   if(resultado == false){
      Print("ERROR AL COPIAR DATOS: ", GetLastError());}
      
   //Preguntamos por el valor del indicador almacenado en pShift
   double valorBB = BB[pShift];
   
   //Normalizamos valorBB a los dígitos de nuestro símbolo y lo retornamos
   valorBB = NormalizeDouble(valorBB,_Digits);
   
   return valorBB;   
}

//+----------+// Funciones para la Colocación de Órdenes//+----------+//

ulong AperturaTrades(string pEntrySignal, ulong pMagicNumber, double pVolumenFijo, bool pUsarPoliticaLlenado, ENUM_ORDER_TYPE_FILLING pPoliticaLlenado)
{
   //Compramos al Ask pero cerramos al Bid
   //Vendemos al Bid pero cerramos al Ask
   
   double precioAsk  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double precioBid  = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double tickSize   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   
   //Precio debe ser normalizado a dígitos o tamaño del tick (ticksize)
   precioAsk = round(precioAsk/tickSize) * tickSize;
   precioBid = round(precioBid/tickSize) * tickSize;
   
   string comentario = pEntrySignal + " | " + _Symbol + " | " + string(pMagicNumber);
   
   //Declaración e inicialización de los objetos solicitud y resultado
   MqlTradeRequest solicitud  = {};
   MqlTradeResult resultado   = {}; 
   
   if(pEntrySignal == "LARGO")
   {
      //Parámetros de la solicitud
      solicitud.action     = TRADE_ACTION_DEAL;
      solicitud.symbol     = _Symbol;
      solicitud.volume     = pVolumenFijo;
      solicitud.type       = ORDER_TYPE_BUY;
      solicitud.price      = precioAsk;
      solicitud.deviation  = 30;
      solicitud.magic      = pMagicNumber;
      solicitud.comment    = comentario;
      
      if(pUsarPoliticaLlenado == true) solicitud.type_filling = pPoliticaLlenado;
      
      //Envío de la solicitud
      if(!OrderSend(solicitud,resultado))
         Print("Error en el envío de la orden: ", GetLastError());      //Si la solicitud no se envía, imprimimos código de error
      
      //Información de la operación
      Print("Abierta ", solicitud.symbol, " ",pEntrySignal," orden #",resultado.order,": ",resultado.retcode,", Volumen: ",resultado.volume,", Precio: ",DoubleToString(precioAsk,_Digits));
         
   }
   else if(pEntrySignal == "CORTO")
   {
      //Parámetros de la solicitud
      solicitud.action     = TRADE_ACTION_DEAL;
      solicitud.symbol     = _Symbol;
      solicitud.volume     = pVolumenFijo;
      solicitud.type       = ORDER_TYPE_SELL;
      solicitud.price      = precioBid;
      solicitud.deviation  = 30;
      solicitud.magic      = pMagicNumber;
      solicitud.comment    = comentario;

      if(pUsarPoliticaLlenado == true) solicitud.type_filling = pPoliticaLlenado;
      
      //Envío de la solicitud
      if(!OrderSend(solicitud,resultado))
         Print("Error en el envío de la orden: ", GetLastError());      //Si la solicitud no se envía, imprimimos código de error
      
      //Información de la operación
      Print("Abierta ", solicitud.symbol, " ",pEntrySignal," orden #",resultado.order,": ",resultado.retcode,", Volumen: ",resultado.volume,", Precio: ",DoubleToString(precioBid,_Digits));   
   }
   
   if(resultado.retcode == TRADE_RETCODE_DONE || resultado.retcode == TRADE_RETCODE_DONE_PARTIAL || resultado.retcode == TRADE_RETCODE_PLACED || resultado.retcode == TRADE_RETCODE_NO_CHANGES)
   {
      return resultado.order;
   }
   else return 0;      
}

void ModificacionPosiciones(ulong pTicket, ulong pMagicNumber, double pSLPrecio, double pTPPrecio)
{
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   
   MqlTradeRequest solicitud  = {};
   MqlTradeResult resultado   = {};
   
   solicitud.action = TRADE_ACTION_SLTP;
   solicitud.position = pTicket;
   solicitud.symbol = _Symbol;
   solicitud.sl = round(pSLPrecio/tickSize) * tickSize;
   solicitud.tp = round(pTPPrecio/tickSize) * tickSize;
   solicitud.comment = "MOD. " + " | " + _Symbol + " | " + string(pMagicNumber) + ", SL: " + DoubleToString(solicitud.sl,_Digits) + ", TP: " + DoubleToString(solicitud.tp,_Digits);
   
   if(solicitud.sl > 0 || solicitud.tp > 0)
   {
      Sleep(1000);
      bool sent = OrderSend(solicitud,resultado);
      Print(resultado.comment);
      
      if(!sent)
      {
         Print("Error de modificación OrderSend: ", GetLastError());
         Sleep(3000);
         
         sent = OrderSend(solicitud,resultado);
         Print(resultado.comment);
         if(!sent) Print("2o intento error de modificación OrderSend: ", GetLastError());
      }
   } 
}

bool RevisionPosicionesColocadas(ulong pMagicNumber)
{
   bool posicionColocada = false;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posicionTicket = PositionGetTicket(i);
      PositionSelectByTicket(posicionTicket);
      
      ulong posicionMagico = PositionGetInteger(POSITION_MAGIC);
      
      if(posicionMagico == pMagicNumber)
      {
         posicionColocada = true;
         break;
      }
   }
   
   return posicionColocada;
}

void CierrePosiciones(ulong pMagicNumber, string pExitSignal, bool pUsarPoliticaLlenado, ENUM_ORDER_TYPE_FILLING pPoliticaLlenado)
{
   //Declaración e inicialización de los objetos solicitud y resultado
   MqlTradeRequest solicitud  = {};
   MqlTradeResult resultado   = {};
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      //Reset de los valores de los objetos solicitud y resultado
      ZeroMemory(solicitud);
      ZeroMemory(resultado);
      
      ulong posicionTicket = PositionGetTicket(i);
      PositionSelectByTicket(posicionTicket);
      
      ulong posicionMagico = PositionGetInteger(POSITION_MAGIC);
      ulong posicionTipo = PositionGetInteger(POSITION_TYPE);
      
      if(posicionMagico == pMagicNumber && pExitSignal == "CIERRE_LARGO" && posicionTipo == POSITION_TYPE_BUY)
      {
         solicitud.action = TRADE_ACTION_DEAL;
         solicitud.type = ORDER_TYPE_SELL;
         solicitud.symbol = _Symbol;
         solicitud.position = posicionTicket;
         solicitud.volume = PositionGetDouble(POSITION_VOLUME);
         solicitud.price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         solicitud.deviation = 30;

         if(pUsarPoliticaLlenado == true) solicitud.type_filling = pPoliticaLlenado;
         
         bool sent = OrderSend(solicitud,resultado);
         if(sent == true){Print("Posición #",posicionTicket, " cerrada");}
      } 
      else if(posicionMagico == pMagicNumber && pExitSignal == "CIERRE_CORTO" && posicionTipo == POSITION_TYPE_SELL)
      {
         solicitud.action = TRADE_ACTION_DEAL;
         solicitud.type = ORDER_TYPE_BUY;
         solicitud.symbol = _Symbol;
         solicitud.position = posicionTicket;
         solicitud.volume = PositionGetDouble(POSITION_VOLUME);
         solicitud.price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         solicitud.deviation = 30;

         if(pUsarPoliticaLlenado == true) solicitud.type_filling = pPoliticaLlenado;
         
         bool sent = OrderSend(solicitud,resultado);
         if(sent == true){Print("Posición #",posicionTicket, " cerrada");}      
      }      
   }      
}

//+----------+// Funciones para el RSI //+----------+//
//+------------------------------------------------------------------+
//| Function to get RSI value                                        |
//+------------------------------------------------------------------+
double GetRSIValue(int shift)
{
   double rsiArray[];
   ArraySetAsSeries(rsiArray, true);
   if(CopyBuffer(RSI_Handle, 0, shift, 1, rsiArray) <= 0)
   {
      Print("Error getting RSI value: ", GetLastError());
      return(-1); // Error
   }
   return rsiArray[0];
}


//+----------+// Funciones para la Gestión de posiciones //+----------+//

double CalcularStopLoss(string pEntrySignal, int pSLPuntosFijos, int pSLPuntosFijosMA, double pMA)
{
   double stopLoss   = 0.0;
   double precioAsk  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double precioBid  = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double tickSize   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   
   if(pEntrySignal == "LARGO")
   {
      if(pSLPuntosFijos > 0){
         stopLoss = precioBid - (pSLPuntosFijos * _Point);}
      else if(pSLPuntosFijosMA > 0){
         stopLoss = pMA - (pSLPuntosFijosMA * _Point);}
      
      if(stopLoss > 0) stopLoss = AjusteNivelStopDebajo(precioBid,stopLoss);   
   }
   if(pEntrySignal == "CORTO")
   {
      if(pSLPuntosFijos > 0){
         stopLoss = precioAsk + (pSLPuntosFijos * _Point);}
      else if(pSLPuntosFijosMA > 0){
         stopLoss = pMA + (pSLPuntosFijosMA * _Point);}
      
      if(stopLoss > 0) stopLoss = AjusteNivelStopArriba(precioAsk,stopLoss);   
   }
   
   stopLoss = round(stopLoss/tickSize) * tickSize;
   return stopLoss;   
}

double CalcularTakeProfit(string pEntrySignal, int pTPPuntosFijos)
{
   double takeProfit = 0.0;
   double precioAsk  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double precioBid  = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double tickSize   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   
   if(pEntrySignal == "LARGO")
   {
      if(pTPPuntosFijos > 0){
         takeProfit = precioBid + (pTPPuntosFijos * _Point);}
      
      if(takeProfit > 0) takeProfit = AjusteNivelStopArriba(precioBid,takeProfit);   
   
   }
   if(pEntrySignal == "CORTO")
   {
      if(pTPPuntosFijos > 0){
         takeProfit = precioAsk - (pTPPuntosFijos * _Point);}
      
      if(takeProfit > 0) takeProfit = AjusteNivelStopDebajo(precioAsk,takeProfit);      
   }
   
   takeProfit = round(takeProfit/tickSize) * tickSize;
   return takeProfit;   
}

void TrailingStopLoss(ulong pNumeroMagico, int pTSLPuntosFijos)
{
   //Declaración e inicialización de los objetos solicitud y resultado
   MqlTradeRequest solicitud  = {};
   MqlTradeResult resultado   = {};
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      //Reset de los valores de los objetos solicitud y resultado
      ZeroMemory(solicitud);
      ZeroMemory(resultado);
      
      ulong posicionTicket = PositionGetTicket(i);
      PositionSelectByTicket(posicionTicket);
      
      ulong posicionMagico = PositionGetInteger(POSITION_MAGIC);
      ulong posicionTipo = PositionGetInteger(POSITION_TYPE);
      double stopLossActual = PositionGetDouble(POSITION_SL);
      double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double stopLossNuevo;
      
      if(posicionMagico == pNumeroMagico && posicionTipo == POSITION_TYPE_BUY)
      {
         double precioBid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         stopLossNuevo = precioBid - (pTSLPuntosFijos * _Point);
         stopLossNuevo = AjusteNivelStopDebajo(precioBid,stopLossNuevo);
         stopLossNuevo = round(stopLossNuevo/tickSize) * tickSize;
         
         if(stopLossNuevo > stopLossActual)
         {
            solicitud.action = TRADE_ACTION_SLTP;
            solicitud.position = posicionTicket;
            solicitud.comment = "TSL. " + _Symbol + " | " + string(pNumeroMagico);
            solicitud.sl = stopLossNuevo;
            solicitud.tp = PositionGetDouble(POSITION_TP);
            
            bool sent = OrderSend(solicitud,resultado);
            if(!sent) Print("OrderSend TSL error: ", GetLastError());
         }
      }
      else if(posicionMagico == pNumeroMagico && posicionTipo == POSITION_TYPE_SELL)
      {
         double precioAsk = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         stopLossNuevo = precioAsk + (pTSLPuntosFijos * _Point);
         stopLossNuevo = AjusteNivelStopArriba(precioAsk,stopLossNuevo);         
         stopLossNuevo = round(stopLossNuevo/tickSize) * tickSize;
         
         if(stopLossNuevo < stopLossActual)
         {
            solicitud.action = TRADE_ACTION_SLTP;
            solicitud.position = posicionTicket;
            solicitud.comment = "TSL. " + _Symbol + " | " + string(pNumeroMagico);
            solicitud.sl = stopLossNuevo;
            solicitud.tp = PositionGetDouble(POSITION_TP);
            
            bool sent = OrderSend(solicitud,resultado);
            if(!sent) Print("OrderSend TSL error: ", GetLastError());
         }      
      }      
   }      
}

void BreakEven(ulong pNumeroMagico, int pBEPuntosFijos)
{
   //Declaración e inicialización de los objetos solicitud y resultado
   MqlTradeRequest solicitud  = {};
   MqlTradeResult resultado   = {};
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      //Reset de los valores de los objetos solicitud y resultado
      ZeroMemory(solicitud);
      ZeroMemory(resultado);
      
      ulong posicionTicket = PositionGetTicket(i);
      PositionSelectByTicket(posicionTicket);
      
      ulong posicionMagico = PositionGetInteger(POSITION_MAGIC);
      ulong posicionTipo = PositionGetInteger(POSITION_TYPE);
      double stopLossActual = PositionGetDouble(POSITION_SL);
      double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double precioApertura = PositionGetDouble(POSITION_PRICE_OPEN);
      double stopLossNuevo = round(precioApertura/tickSize) * tickSize;
      
      if(posicionMagico == pNumeroMagico && posicionTipo == POSITION_TYPE_BUY)
      {
         double precioBid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double BEDistancia = precioApertura + (pBEPuntosFijos * _Point);
         
         if(stopLossNuevo > stopLossActual && precioBid > BEDistancia)
         {
            solicitud.action = TRADE_ACTION_SLTP;
            solicitud.position = posicionTicket;
            solicitud.comment = "BE. " + _Symbol + " | " + string(pNumeroMagico);
            solicitud.sl = stopLossNuevo;
            solicitud.tp = PositionGetDouble(POSITION_TP);
            
            bool sent = OrderSend(solicitud,resultado);
            if(!sent) Print("OrderSend BE error: ", GetLastError());
         }
      }
      else if(posicionMagico == pNumeroMagico && posicionTipo == POSITION_TYPE_SELL)
      {
         double precioAsk = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double BEDistancia = precioApertura - (pBEPuntosFijos * _Point);
        
         if(stopLossNuevo < stopLossActual && precioAsk < BEDistancia)
         {
            solicitud.action = TRADE_ACTION_SLTP;
            solicitud.position = posicionTicket;
            solicitud.comment = "BE. " + _Symbol + " | " + string(pNumeroMagico);
            solicitud.sl = stopLossNuevo;
            solicitud.tp = PositionGetDouble(POSITION_TP);
            
            bool sent = OrderSend(solicitud,resultado);
            if(!sent) Print("OrderSend BE error: ", GetLastError());
         }      
      }      
   }      
}

//Ajuste de niveles de stops
double AjusteNivelStopArriba(double pPrecioActual,double pPrecioParaAjustar,int pPuntosAdicionales = 10)
{
   double precioAjustado = pPrecioParaAjustar;
   
   long nivelesStop = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   
   if(nivelesStop > 0)
   {
      double nivelesStopPrecio = nivelesStop * _Point;
      nivelesStopPrecio = pPrecioActual + nivelesStopPrecio;
      
      double puntosAdicionales = pPuntosAdicionales * _Point;
      
      if(precioAjustado <= nivelesStopPrecio + puntosAdicionales)
      {
         precioAjustado = nivelesStopPrecio + puntosAdicionales;
         Print("Precio ajustado por encima del nivel de stops a " + string(precioAjustado));
      }
   }
   
   return precioAjustado;
}

//Ajuste de niveles de stops
double AjusteNivelStopDebajo(double pPrecioActual,double pPrecioParaAjustar,int pPuntosAdicionales = 10)
{
   double precioAjustado = pPrecioParaAjustar;
   
   long nivelesStop = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   
   if(nivelesStop > 0)
   {
      double nivelesStopPrecio = nivelesStop * _Point;
      nivelesStopPrecio = pPrecioActual - nivelesStopPrecio;
      
      double puntosAdicionales = pPuntosAdicionales * _Point;
      
      if(precioAjustado >= nivelesStopPrecio - puntosAdicionales)
      {
         precioAjustado = nivelesStopPrecio - puntosAdicionales;
         Print("Precio ajustado por debajo del nivel de stops a " + string(precioAjustado));
      }
   }
   
   return precioAjustado;
}

//+------------------------------------------------------------------+
//| V2.0 NEW FUNCTIONS                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Update all indicator values                                       |
//+------------------------------------------------------------------+
void UpdateAllIndicators()
{
   double bufRSI[1], bufADX[1], bufATR[1], bufFastMA[1], bufMedMA[1], bufSlowMA[1];
   
   // RSI
   CopyBuffer(RSI_Handle, 0, 0, 1, bufRSI);
   g_RSI = bufRSI[0];
   
   // ADX (main line is buffer 0)
   CopyBuffer(ADX_Handle, 0, 0, 1, bufADX);
   g_ADX = bufADX[0];
   
   // ATR
   CopyBuffer(ATR_Handle, 0, 0, 1, bufATR);
   g_ATR = bufATR[0];
   
   // Fast MA
   CopyBuffer(FastMA_Handle, 0, 0, 1, bufFastMA);
   g_FastMA = bufFastMA[0];
   
   // Medium MA (main signal MA)
   CopyBuffer(ManejadorMA, 0, 0, 1, bufMedMA);
   g_MediumMA = bufMedMA[0];
   
   // Slow MA (EMA200 trend filter)
   CopyBuffer(SlowMA_Handle, 0, 0, 1, bufSlowMA);
   g_SlowMA = bufSlowMA[0];
}

//+------------------------------------------------------------------+
//| Enhanced Dashboard Display                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Trend Status
   string trendStatus = "NEUTRAL";
   string trendEmoji = "⚪";
   
   if(g_FastMA > g_MediumMA && g_MediumMA > g_SlowMA)
   {
      trendStatus = "BULLISH";
      trendEmoji = "📈";
   }
   else if(g_FastMA < g_MediumMA && g_MediumMA < g_SlowMA)
   {
      trendStatus = "BEARISH";
      trendEmoji = "📉";
   }
   
   // ADX Status
   string adxStatus = (g_ADX >= ADX_Threshold) ? "✅ STRONG" : "⚠️ WEAK";
   
   // RSI Status
   string rsiStatus = "NEUTRAL";
   if(g_RSI < 30) rsiStatus = "🔵 OVERSOLD";
   else if(g_RSI > 70) rsiStatus = "🔴 OVERBOUGHT";
   else if(g_RSI < 50) rsiStatus = "🟢 DISCOUNT";
   else rsiStatus = "🟡 PREMIUM";
   
   // Build dashboard
   string text = "";
   text += "╔══════════════════════════════════╗\n";
   text += "║  📊 MEDIA MÓVIL PRO v2.0        ║\n";
   text += "╠══════════════════════════════════╣\n";
   text += "║ Price: " + DoubleToString(bid, _Digits) + "\n";
   text += "╠══════════════════════════════════╣\n";
   text += "║ " + trendEmoji + " Trend: " + trendStatus + "\n";
   text += "║ Fast MA(" + string(FastMA_Period) + "): " + DoubleToString(g_FastMA, _Digits) + "\n";
   text += "║ Med MA(" + string(PeriodoMA) + "): " + DoubleToString(g_MediumMA, _Digits) + "\n";
   text += "║ Slow MA(" + string(SlowMA_Period) + "): " + DoubleToString(g_SlowMA, _Digits) + "\n";
   text += "╠══════════════════════════════════╣\n";
   text += "║ ADX: " + DoubleToString(g_ADX, 1) + " " + adxStatus + "\n";
   text += "║ RSI: " + DoubleToString(g_RSI, 1) + " " + rsiStatus + "\n";
   text += "║ ATR: " + DoubleToString(g_ATR, _Digits) + "\n";
   text += "╠══════════════════════════════════╣\n";
   text += "║ Filters: ";
   text += UseADXFilter ? "ADX✓ " : "";
   text += UseRSIFilter ? "RSI✓ " : "";
   text += UseTripleMA ? "3MA✓ " : "";
   text += UseATRStops ? "ATR✓" : "";
   text += "\n";
   text += "╚══════════════════════════════════╝\n";
   
   Comment(text);
}

//+------------------------------------------------------------------+
//| Calculate ATR-based Stop Loss                                     |
//+------------------------------------------------------------------+
double CalcularStopLossATR(string pEntrySignal, double pATR, double pMultiplier)
{
   double stopLoss = 0.0;
   double precioAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double precioBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double slDistance = pATR * pMultiplier;
   
   if(pEntrySignal == "LARGO")
   {
      stopLoss = precioBid - slDistance;
      if(stopLoss > 0) stopLoss = AjusteNivelStopDebajo(precioBid, stopLoss);
   }
   else if(pEntrySignal == "CORTO")
   {
      stopLoss = precioAsk + slDistance;
      if(stopLoss > 0) stopLoss = AjusteNivelStopArriba(precioAsk, stopLoss);
   }
   
   stopLoss = round(stopLoss / tickSize) * tickSize;
   return stopLoss;
}

//+------------------------------------------------------------------+
//| Calculate ATR-based Take Profit                                   |
//+------------------------------------------------------------------+
double CalcularTakeProfitATR(string pEntrySignal, double pATR, double pMultiplier)
{
   double takeProfit = 0.0;
   double precioAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double precioBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double tpDistance = pATR * pMultiplier;
   
   if(pEntrySignal == "LARGO")
   {
      takeProfit = precioBid + tpDistance;
      if(takeProfit > 0) takeProfit = AjusteNivelStopArriba(precioBid, takeProfit);
   }
   else if(pEntrySignal == "CORTO")
   {
      takeProfit = precioAsk - tpDistance;
      if(takeProfit > 0) takeProfit = AjusteNivelStopDebajo(precioAsk, takeProfit);
   }
   
   takeProfit = round(takeProfit / tickSize) * tickSize;
   return takeProfit;
}
