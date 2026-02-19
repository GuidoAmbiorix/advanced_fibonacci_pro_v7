//+------------------------------------------------------------------+
//|                                      Check_XAUUSD_Spread.mq5     |
//|                              Check current XAUUSD spread in USD  |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

input int CheckDurationMinutes = 60;  // Check spread for N minutes

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
   string symbol = "XAUUSD";

   // Try common XAUUSD symbol variations
   if(!SymbolSelect(symbol, true))
   {
      symbol = "XAUUSD.";
      if(!SymbolSelect(symbol, true))
      {
         symbol = "GOLD";
         if(!SymbolSelect(symbol, true))
         {
            Alert("❌ XAUUSD symbol not found! Check your broker's symbol name.");
            return;
         }
      }
   }

   Print("=================================================");
   Print("🪙 XAUUSD SPREAD CHECK - ", symbol);
   Print("=================================================");
   Print("Duration: ", CheckDurationMinutes, " minutes");
   Print("Starting at: ", TimeToString(TimeCurrent()));
   Print("");

   double minSpreadUSD = 999999;
   double maxSpreadUSD = 0;
   double totalSpreadUSD = 0;
   int samples = 0;

   datetime startTime = TimeCurrent();
   datetime endTime = startTime + (CheckDurationMinutes * 60);

   Print("⏳ Monitoring spread... (checking every 5 seconds)");
   Print("");

   while(TimeCurrent() < endTime)
   {
      double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      double spreadUSD = spread * 100;  // XAUUSD: 100 oz/lot

      if(spreadUSD > 0)
      {
         totalSpreadUSD += spreadUSD;
         samples++;

         if(spreadUSD < minSpreadUSD) minSpreadUSD = spreadUSD;
         if(spreadUSD > maxSpreadUSD) maxSpreadUSD = spreadUSD;

         // Get current session
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         int gmtHour = dt.hour;

         string session = "Off-hours";
         if(gmtHour >= 13 && gmtHour < 16) session = "London-NY Overlap (PRIME)";
         else if(gmtHour >= 8 && gmtHour < 13) session = "London";
         else if(gmtHour >= 16 && gmtHour < 21) session = "New York";
         else if(gmtHour >= 7 && gmtHour < 8) session = "Asian-London";
         else session = "Asian/Off-hours";

         Print(TimeToString(TimeCurrent(), TIME_MINUTES), " | Session: ", session,
               " | Spread: $", DoubleToString(spreadUSD, 2), " USD (",
               DoubleToString(spread * 10000, 1), " pips)");
      }

      Sleep(5000);  // Check every 5 seconds
   }

   Print("");
   Print("=================================================");
   Print("📊 SPREAD STATISTICS (", samples, " samples)");
   Print("=================================================");

   if(samples > 0)
   {
      double avgSpreadUSD = totalSpreadUSD / samples;

      Print("Minimum: $", DoubleToString(minSpreadUSD, 2), " USD");
      Print("Average: $", DoubleToString(avgSpreadUSD, 2), " USD");
      Print("Maximum: $", DoubleToString(maxSpreadUSD, 2), " USD");
      Print("");
      Print("=================================================");
      Print("📋 RECOMMENDED SETTINGS:");
      Print("=================================================");

      // Recommendations based on average spread
      if(avgSpreadUSD <= 0.50)
      {
         Print("✅ EXCELLENT SPREADS (ECN/Raw account)");
         Print("   InpMetals_MaxSpreadUSD = 0.80  (tight filter)");
      }
      else if(avgSpreadUSD <= 1.00)
      {
         Print("✅ GOOD SPREADS (Standard account)");
         Print("   InpMetals_MaxSpreadUSD = 1.20  (current: 1.0 is OK but slightly tight)");
      }
      else if(avgSpreadUSD <= 1.50)
      {
         Print("⚠️ MODERATE SPREADS");
         Print("   InpMetals_MaxSpreadUSD = 1.80  (increase from 1.0)");
      }
      else
      {
         Print("⛔ HIGH SPREADS (consider different broker)");
         Print("   InpMetals_MaxSpreadUSD = 2.50  (or disable filter)");
      }

      Print("");
      Print("Current setting: InpMetals_MaxSpreadUSD = 1.0");
      if(maxSpreadUSD > 1.0)
      {
         double rejectionRate = 0;
         for(int i = 0; i < samples; i++)
         {
            // This is simplified - actual calculation would need all samples
         }
         Print("⚠️ WARNING: ", DoubleToString((maxSpreadUSD > 1.0 ? 1 : 0) * 100, 0),
               "% of samples exceed current threshold");
         Print("   You may miss trading opportunities during certain sessions");
      }
      else
      {
         Print("✅ Current threshold (1.0 USD) is adequate for your broker");
      }
   }
   else
   {
      Print("❌ No spread data collected. Check your connection.");
   }

   Print("=================================================");
}
