//+------------------------------------------------------------------+
//|                                       Seed_Pattern_Database.mq5  |
//|                    Inyecta patrones institucionales en la memoria |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "Include/Memory/PatternMemory.mqh"

void OnStart()
{
   CPatternMemory memory;
   if(!memory.Init(_Symbol, true, 5)) // Init con persistencia
   {
      Print("Error inicializando PatternMemory");
      return;
   }

   // Definición de las 12 Firmas Institucionales (Confluencias)
   // S1: TREND+STRUCT+OB+FVG+MTF
   InjectPattern(memory, true, true, false, false, true, true, false, false, true, 2.5);
   // S2: STRUCT+LIQ+OB+MTF
   InjectPattern(memory, false, true, false, false, true, false, true, false, true, 3.0);
   // S3: TREND+FIB+OB+KZ
   InjectPattern(memory, true, false, true, false, true, false, false, true, false, 2.0);
   // S4: STRUCT+FVG+RSI+MTF
   InjectPattern(memory, false, true, false, true, false, true, false, false, true, 1.8);
   // S5: STRUCT+LIQ+FVG+KZ
   InjectPattern(memory, false, true, false, false, false, true, true, true, false, 2.2);
   // S6: TREND+OB+LIQ+MTF
   InjectPattern(memory, true, false, false, false, true, false, true, false, true, 2.4);
   // S7: STRUCT+FIB+FVG+KZ
   InjectPattern(memory, false, true, true, false, false, true, false, true, false, 2.1);
   // S8: TREND+RSI+STRUCT+MTF
   InjectPattern(memory, true, true, false, true, false, false, false, false, true, 1.9);
   // S9: STRUCT+OB+KZ+MTF
   InjectPattern(memory, false, true, false, false, true, false, false, true, true, 2.6);
   // S10: TREND+LIQ+FVG+FIB
   InjectPattern(memory, true, false, true, false, false, true, true, false, false, 2.3);
   // S11: STRUCT+RSI+OB+MTF
   InjectPattern(memory, false, true, false, true, true, false, false, false, true, 2.0);
   // S12: TREND+STRUCT+FIB+FVG
   InjectPattern(memory, true, true, true, false, false, true, false, false, false, 1.7);

   Print("Inyección de 240 patrones completada.");
}

void InjectPattern(CPatternMemory &mem, bool trend, bool struc, bool fib, bool rsi, 
                   bool ob, bool fvg, bool liq, bool kz, bool mtf, double r)
{
   ConfluenceFactors factors;
   factors.trendAligned = trend;
   factors.structureBreak = struc;
   factors.fibZone = fib;
   factors.rsiMomentum = rsi;
   factors.orderBlock = ob;
   factors.fvg = fvg;
   factors.liquiditySweep = liq;
   factors.killzoneActive = kz;
   factors.mtfAligned = mtf;

   for(int i=0; i<20; i++)
   {
      mem.RecordPattern(factors, r);
   }
}
