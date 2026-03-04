//+------------------------------------------------------------------+
//|                                       SymbolConfigManager.mqh    |
//|              Multi-Symbol Engine - Configuration Management      |
//|          Loads optimal presets for each symbol type              |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7 - Multi-Symbol Engine"
#property version   "1.00"
#property strict

#include "..\Core\SymbolTypeDetector.mqh"
#include "..\Config\UniversalConfig.mqh"

//+------------------------------------------------------------------+
//| Symbol Configuration Manager Class                               |
//| Leverages existing UniversalConfig to get presets per symbol     |
//+------------------------------------------------------------------+
class CSymbolConfigManager {
private:
   CUniversalConfig m_universalConfig;

public:
   //+------------------------------------------------------------------+
   //| Initialize configuration system                                  |
   //+------------------------------------------------------------------+
   bool Init() {
      Print("Initializing Symbol Config Manager...");

      if(!m_universalConfig.Init()) {
         Print("ERROR: UniversalConfig initialization failed");
         return false;
      }

      Print("✅ Symbol Config Manager initialized");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get preset for specific symbol                                   |
   //+------------------------------------------------------------------+
   SymbolPreset GetPresetForSymbol(string symbol) {
      // Detect symbol type
      CSymbolTypeDetector detector;
      detector.Init(symbol);

      ENUM_SYMBOL_TYPE type = detector.GetType();

      // Get preset from UniversalConfig
      SymbolPreset preset = m_universalConfig.GetPreset(type);

      Print(symbol, ": Type=", detector.GetTypeString(),
            " MinConf=", preset.minConfluenceEntry,
            " Risk=", preset.riskBase, "%",
            " SessionOpt=", preset.useSessionOptimizer ? "ON" : "OFF");

      return preset;
   }

   //+------------------------------------------------------------------+
   //| Apply manual overrides to preset                                 |
   //+------------------------------------------------------------------+
   void ApplyOverrides(SymbolPreset &preset, double riskOverride, int confluenceOverride) {
      if(riskOverride > 0) {
         Print("  Override: Risk ", preset.riskBase, "% → ", riskOverride, "%");
         preset.riskBase = riskOverride;
      }

      if(confluenceOverride > 0) {
         Print("  Override: MinConfluence ", preset.minConfluenceEntry, " → ", confluenceOverride);
         preset.minConfluenceEntry = confluenceOverride;
      }
   }

   //+------------------------------------------------------------------+
   //| Print preset configuration for debugging                         |
   //+------------------------------------------------------------------+
   void PrintPreset(string symbol, SymbolPreset &preset) {
      Print("====== PRESET FOR ", symbol, " ======");
      Print("Symbol Type: ", EnumToString(preset.minConfluenceEntry));  // Placeholder - type not stored in preset
      Print("Min Confluence: ", preset.minConfluenceEntry);
      Print("Risk Base: ", preset.riskBase, "%");
      Print("Max Risk: ", preset.maxRisk, "%");
      Print("News Filter: ", preset.newsMinutesBefore, " min before / ",
            preset.newsMinutesAfter, " min after");
      Print("BE Threshold: ", preset.beThreshold_R, "R");
      Print("Trail Start: ", preset.trailStart_R, "R");
      Print("Trail ATR Mult: ", preset.trailATR_Mult);
      Print("Trail Decay: ", preset.trailDecayRate);
      Print("Trail Min Mult: ", preset.trailMinMult);
      Print("Session Optimizer: ", preset.useSessionOptimizer ? "ENABLED" : "DISABLED");
      Print("Skip Asian: ", preset.skipAsianSession ? "YES" : "NO");
      Print("Max Spread: ", preset.maxSpreadUSD > 0 ? DoubleToString(preset.maxSpreadUSD,2) + " USD" :
                                                        IntegerToString(preset.maxSpreadPoints) + " points");
      Print("Partial Close: ", preset.partialClosePercent, "% @ ", preset.partialCloseAt_R, "R");
      Print("=====================================");
   }

   //+------------------------------------------------------------------+
   //| Validate preset values                                           |
   //+------------------------------------------------------------------+
   bool ValidatePreset(SymbolPreset &preset) {
      bool valid = true;

      if(preset.minConfluenceEntry < 0 || preset.minConfluenceEntry > 30) {
         Print("WARNING: Invalid minConfluenceEntry: ", preset.minConfluenceEntry);
         valid = false;
      }

      if(preset.riskBase < 0.01 || preset.riskBase > 5.0) {
         Print("WARNING: Invalid riskBase: ", preset.riskBase, "%");
         valid = false;
      }

      if(preset.maxRisk < preset.riskBase) {
         Print("WARNING: maxRisk < riskBase (", preset.maxRisk, "% < ", preset.riskBase, "%)");
         valid = false;
      }

      if(preset.beThreshold_R < 0 || preset.beThreshold_R > 5.0) {
         Print("WARNING: Invalid beThreshold_R: ", preset.beThreshold_R);
         valid = false;
      }

      if(preset.trailStart_R < 0 || preset.trailStart_R > 10.0) {
         Print("WARNING: Invalid trailStart_R: ", preset.trailStart_R);
         valid = false;
      }

      return valid;
   }

   //+------------------------------------------------------------------+
   //| Get all available symbol types                                   |
   //+------------------------------------------------------------------+
   void GetAvailableTypes(ENUM_SYMBOL_TYPE &types[]) {
      ArrayResize(types, 5);
      types[0] = SYMBOL_TYPE_FOREX;
      types[1] = SYMBOL_TYPE_METALS;
      types[2] = SYMBOL_TYPE_INDICES;
      types[3] = SYMBOL_TYPE_CRYPTO;
      types[4] = SYMBOL_TYPE_COMMODITIES;
   }

   //+------------------------------------------------------------------+
   //| Print all available presets                                      |
   //+------------------------------------------------------------------+
   void PrintAllPresets() {
      Print("========================================");
      Print("  AVAILABLE SYMBOL PRESETS");
      Print("========================================");

      ENUM_SYMBOL_TYPE types[];
      GetAvailableTypes(types);

      for(int i = 0; i < ArraySize(types); i++) {
         SymbolPreset preset = m_universalConfig.GetPreset(types[i]);

         Print("--- ", EnumToString(types[i]), " ---");
         Print("  Min Confluence: ", preset.minConfluenceEntry);
         Print("  Risk Base: ", preset.riskBase, "%");
         Print("  Max Risk: ", preset.maxRisk, "%");
         Print("  BE Threshold: ", preset.beThreshold_R, "R");
         Print("  Trail Start: ", preset.trailStart_R, "R");
         Print("  Session Optimizer: ", preset.useSessionOptimizer ? "ON" : "OFF");
         Print("");
      }

      Print("========================================");
   }
};
//+------------------------------------------------------------------+
