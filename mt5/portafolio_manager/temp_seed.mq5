
//+------------------------------------------------------------------+
//| SEED DEFAULT CONFIGURATIONS (If DB is empty)                      |
//+------------------------------------------------------------------+
void SeedDefaultConfigs()
{
   Print("🌱 Seeding Database with Default Configurations...");
   
   string defaultSymbols[] = {"EURUSD", "GBPUSD", "AUDUSD", "USDCAD", "USDJPY", "EURJPY", "AUDJPY", "XAUUSD"};
   
   for(int i=0; i<ArraySize(defaultSymbols); i++)
   {
       SymbolConfig cfg; // Uses default constructor for base values
       
       cfg.symbol = defaultSymbols[i];
       cfg.magicNumber = InpMagicBase + i;
       
       // Customize per symbol group
       if(StringFind(cfg.symbol, "JPY") >= 0)
       {
           cfg.trailATR_Mult = 2.0; // Wider stops for JPY
           cfg.volatilityThreshold = 4.0;
       }
       else if(StringFind(cfg.symbol, "XAU") >= 0)
       {
           cfg.trailATR_Mult = 2.5; // Gold needs room
           cfg.riskBase = 0.5;          // Higher risk for Gold
           cfg.volatilityThreshold = 5.0;
           cfg.maxSpreadPoints = 100;
       }
       
       if(dbManager.SaveSymbolConfig(cfg))
       {
           Print("✅ Seeded default config for ", cfg.symbol);
       }
       else
       {
           Print("❌ Failed to seed config for ", cfg.symbol);
       }
   }
   
   Print("🌱 Seeding Complete.");
}
