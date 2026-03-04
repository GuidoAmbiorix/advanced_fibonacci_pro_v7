//+------------------------------------------------------------------+
//|                                            UniversalConfig.mqh   |
//|                                 Universal Engine - Phase 2       |
//|                   Unified configuration preset system            |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7"
#property version   "1.00"
#property strict

#include "..\Core\SymbolTypeDetector.mqh"

//+------------------------------------------------------------------+
//| Symbol Configuration Preset Structure                            |
//+------------------------------------------------------------------+
struct SymbolPreset {
   // Confluence Requirements
   int minConfluenceEntry;

   // Risk Management
   double riskBase;
   double maxRisk;

   // News Filter
   int newsMinutesBefore;
   int newsMinutesAfter;

   // Trailing Stop Parameters
   double beThreshold_R;
   double trailStart_R;
   double trailATR_Mult;
   double trailDecayRate;
   double trailMinMult;

   // Spread Filtering
   double maxSpreadUSD;      // For metals (in USD)
   int maxSpreadPoints;      // For forex/others (in points)

   // Session Optimization
   bool useSessionOptimizer;
   bool skipAsianSession;

   // Partial Close
   double partialClosePercent;
   double partialCloseAt_R;
};

//+------------------------------------------------------------------+
//| Universal Configuration Class                                    |
//+------------------------------------------------------------------+
class CUniversalConfig {
private:
   SymbolPreset m_presets[6]; // One for each ENUM_SYMBOL_TYPE

   //+------------------------------------------------------------------+
   //| Initialize all presets with values from Symbol/Metals engines    |
   //+------------------------------------------------------------------+
   void InitializePresets() {
      // ============================================================
      // FOREX PRESET (from Symbol_Engine.mq5)
      // ============================================================
      m_presets[SYMBOL_TYPE_FOREX].minConfluenceEntry = 4;
      m_presets[SYMBOL_TYPE_FOREX].riskBase = 0.25;
      m_presets[SYMBOL_TYPE_FOREX].maxRisk = 0.75;
      m_presets[SYMBOL_TYPE_FOREX].newsMinutesBefore = 30;
      m_presets[SYMBOL_TYPE_FOREX].newsMinutesAfter = 30;
      m_presets[SYMBOL_TYPE_FOREX].beThreshold_R = 0.6;
      m_presets[SYMBOL_TYPE_FOREX].trailStart_R = 1.2;
      m_presets[SYMBOL_TYPE_FOREX].trailATR_Mult = 1.8;
      m_presets[SYMBOL_TYPE_FOREX].trailDecayRate = 0.95;
      m_presets[SYMBOL_TYPE_FOREX].trailMinMult = 1.0;
      m_presets[SYMBOL_TYPE_FOREX].maxSpreadUSD = 0.0;     // Not used for forex
      m_presets[SYMBOL_TYPE_FOREX].maxSpreadPoints = 20;   // 2.0 pips typical
      m_presets[SYMBOL_TYPE_FOREX].useSessionOptimizer = false;
      m_presets[SYMBOL_TYPE_FOREX].skipAsianSession = false;
      m_presets[SYMBOL_TYPE_FOREX].partialClosePercent = 30.0;
      m_presets[SYMBOL_TYPE_FOREX].partialCloseAt_R = 1.5;

      // ============================================================
      // METALS PRESET (from Metals_Engine.mq5)
      // ============================================================
      m_presets[SYMBOL_TYPE_METALS].minConfluenceEntry = 12;
      m_presets[SYMBOL_TYPE_METALS].riskBase = 0.20;
      m_presets[SYMBOL_TYPE_METALS].maxRisk = 0.60;
      m_presets[SYMBOL_TYPE_METALS].newsMinutesBefore = 60;
      m_presets[SYMBOL_TYPE_METALS].newsMinutesAfter = 60;
      m_presets[SYMBOL_TYPE_METALS].beThreshold_R = 0.5;
      m_presets[SYMBOL_TYPE_METALS].trailStart_R = 1.0;
      m_presets[SYMBOL_TYPE_METALS].trailATR_Mult = 2.0;
      m_presets[SYMBOL_TYPE_METALS].trailDecayRate = 0.92;
      m_presets[SYMBOL_TYPE_METALS].trailMinMult = 0.8;
      m_presets[SYMBOL_TYPE_METALS].maxSpreadUSD = 1.0;
      m_presets[SYMBOL_TYPE_METALS].maxSpreadPoints = 0;   // Not used for metals
      m_presets[SYMBOL_TYPE_METALS].useSessionOptimizer = true;
      m_presets[SYMBOL_TYPE_METALS].skipAsianSession = true;
      m_presets[SYMBOL_TYPE_METALS].partialClosePercent = 40.0;
      m_presets[SYMBOL_TYPE_METALS].partialCloseAt_R = 1.3;

      // ============================================================
      // INDICES PRESET (conservative baseline)
      // ============================================================
      m_presets[SYMBOL_TYPE_INDICES].minConfluenceEntry = 8;
      m_presets[SYMBOL_TYPE_INDICES].riskBase = 0.20;
      m_presets[SYMBOL_TYPE_INDICES].maxRisk = 0.60;
      m_presets[SYMBOL_TYPE_INDICES].newsMinutesBefore = 45;
      m_presets[SYMBOL_TYPE_INDICES].newsMinutesAfter = 45;
      m_presets[SYMBOL_TYPE_INDICES].beThreshold_R = 0.5;
      m_presets[SYMBOL_TYPE_INDICES].trailStart_R = 1.2;
      m_presets[SYMBOL_TYPE_INDICES].trailATR_Mult = 2.0;
      m_presets[SYMBOL_TYPE_INDICES].trailDecayRate = 0.93;
      m_presets[SYMBOL_TYPE_INDICES].trailMinMult = 0.9;
      m_presets[SYMBOL_TYPE_INDICES].maxSpreadUSD = 0.0;
      m_presets[SYMBOL_TYPE_INDICES].maxSpreadPoints = 50;
      m_presets[SYMBOL_TYPE_INDICES].useSessionOptimizer = false;
      m_presets[SYMBOL_TYPE_INDICES].skipAsianSession = false;
      m_presets[SYMBOL_TYPE_INDICES].partialClosePercent = 35.0;
      m_presets[SYMBOL_TYPE_INDICES].partialCloseAt_R = 1.4;

      // ============================================================
      // CRYPTO PRESET (high volatility settings)
      // ============================================================
      m_presets[SYMBOL_TYPE_CRYPTO].minConfluenceEntry = 6;
      m_presets[SYMBOL_TYPE_CRYPTO].riskBase = 0.15;
      m_presets[SYMBOL_TYPE_CRYPTO].maxRisk = 0.50;
      m_presets[SYMBOL_TYPE_CRYPTO].newsMinutesBefore = 15;
      m_presets[SYMBOL_TYPE_CRYPTO].newsMinutesAfter = 15;
      m_presets[SYMBOL_TYPE_CRYPTO].beThreshold_R = 0.4;
      m_presets[SYMBOL_TYPE_CRYPTO].trailStart_R = 0.8;
      m_presets[SYMBOL_TYPE_CRYPTO].trailATR_Mult = 2.5;
      m_presets[SYMBOL_TYPE_CRYPTO].trailDecayRate = 0.90;
      m_presets[SYMBOL_TYPE_CRYPTO].trailMinMult = 1.2;
      m_presets[SYMBOL_TYPE_CRYPTO].maxSpreadUSD = 0.0;
      m_presets[SYMBOL_TYPE_CRYPTO].maxSpreadPoints = 100;
      m_presets[SYMBOL_TYPE_CRYPTO].useSessionOptimizer = false;
      m_presets[SYMBOL_TYPE_CRYPTO].skipAsianSession = false;
      m_presets[SYMBOL_TYPE_CRYPTO].partialClosePercent = 50.0;
      m_presets[SYMBOL_TYPE_CRYPTO].partialCloseAt_R = 1.0;

      // ============================================================
      // COMMODITIES PRESET (similar to metals)
      // ============================================================
      m_presets[SYMBOL_TYPE_COMMODITIES].minConfluenceEntry = 10;
      m_presets[SYMBOL_TYPE_COMMODITIES].riskBase = 0.20;
      m_presets[SYMBOL_TYPE_COMMODITIES].maxRisk = 0.60;
      m_presets[SYMBOL_TYPE_COMMODITIES].newsMinutesBefore = 45;
      m_presets[SYMBOL_TYPE_COMMODITIES].newsMinutesAfter = 45;
      m_presets[SYMBOL_TYPE_COMMODITIES].beThreshold_R = 0.5;
      m_presets[SYMBOL_TYPE_COMMODITIES].trailStart_R = 1.1;
      m_presets[SYMBOL_TYPE_COMMODITIES].trailATR_Mult = 2.0;
      m_presets[SYMBOL_TYPE_COMMODITIES].trailDecayRate = 0.92;
      m_presets[SYMBOL_TYPE_COMMODITIES].trailMinMult = 0.9;
      m_presets[SYMBOL_TYPE_COMMODITIES].maxSpreadUSD = 0.8;
      m_presets[SYMBOL_TYPE_COMMODITIES].maxSpreadPoints = 0;
      m_presets[SYMBOL_TYPE_COMMODITIES].useSessionOptimizer = true;
      m_presets[SYMBOL_TYPE_COMMODITIES].skipAsianSession = false;
      m_presets[SYMBOL_TYPE_COMMODITIES].partialClosePercent = 35.0;
      m_presets[SYMBOL_TYPE_COMMODITIES].partialCloseAt_R = 1.3;

      // ============================================================
      // UNKNOWN PRESET (fallback to forex settings)
      // ============================================================
      m_presets[SYMBOL_TYPE_UNKNOWN] = m_presets[SYMBOL_TYPE_FOREX];
   }

public:
   //+------------------------------------------------------------------+
   //| Initialize configuration system                                  |
   //+------------------------------------------------------------------+
   bool Init() {
      InitializePresets();
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get preset for specific symbol type                              |
   //+------------------------------------------------------------------+
   SymbolPreset GetPreset(ENUM_SYMBOL_TYPE type) {
      if(type >= 0 && type < ArraySize(m_presets))
         return m_presets[type];

      // Fallback to forex if invalid type
      Print("WARNING: Invalid symbol type, using FOREX preset");
      return m_presets[SYMBOL_TYPE_FOREX];
   }

   //+------------------------------------------------------------------+
   //| Print preset configuration for debugging                         |
   //+------------------------------------------------------------------+
   void PrintPreset(ENUM_SYMBOL_TYPE type) {
      SymbolPreset preset = GetPreset(type);

      Print("====== PRESET CONFIGURATION ======");
      Print("Min Confluence: ", preset.minConfluenceEntry);
      Print("Risk Base: ", preset.riskBase, "%");
      Print("Max Risk: ", preset.maxRisk, "%");
      Print("News Filter: ", preset.newsMinutesBefore, " min before / ",
            preset.newsMinutesAfter, " min after");
      Print("BE Threshold: ", preset.beThreshold_R, "R");
      Print("Trail Start: ", preset.trailStart_R, "R");
      Print("Trail ATR Mult: ", preset.trailATR_Mult);
      Print("Session Optimizer: ", preset.useSessionOptimizer ? "ON" : "OFF");
      if(preset.maxSpreadUSD > 0)
         Print("Max Spread: $", preset.maxSpreadUSD);
      else
         Print("Max Spread: ", preset.maxSpreadPoints, " points");
      Print("==================================");
   }
};
//+------------------------------------------------------------------+
