//+------------------------------------------------------------------+
//|                                        KillzoneIntelligence.mqh |
//|  Module 6: Killzone-Aware Threshold Intelligence                 |
//|  Queries DB WR per (regime, killzone) combo and returns a        |
//|  threshold modifier to raise/lower minEntry per session.         |
//|                                                                  |
//|  Logic:                                                          |
//|    WR < 45% → +2 to minEntry  (weak session, be more selective) |
//|    WR 45-55% → +1             (below average)                   |
//|    WR 55-65% → 0              (neutral — no change)             |
//|    WR > 65%  → -1             (strong session — slight relief)  |
//|                                                                  |
//|  Also runs a daily GateLog digest: prints which gate blocks      |
//|  most per regime — calibration feedback.                         |
//|                                                                  |
//|  Usage:                                                          |
//|    CKillzoneIntelligence kzIntel;                                |
//|    kzIntel.Init(&dbManager);                                     |
//|    kzIntel.Update();          // once per day                    |
//|    int mod = kzIntel.GetThresholdModifier(regime, killzone);     |
//|    minEntry += mod;                                              |
//+------------------------------------------------------------------+
#ifndef KILLZONE_INTELLIGENCE_MQH
#define KILLZONE_INTELLIGENCE_MQH

#include "../DatabaseManager.mqh"
#include "../MarketRegime.mqh"
#include "../KillzoneConfig.mqh"

#define KZI_UPDATE_INTERVAL  86400   // 24 h
#define KZI_MIN_TRADES       8       // min trades for a (regime, kz) combo to be used

class CKillzoneIntelligence
{
private:
   CDatabaseManager* m_db;
   datetime          m_lastUpdate;

   // Matrix: modifier[regimeIdx][kzIdx] — filled on Update()
   // Regimes: 0=TREND_STRONG, 1=TREND_WEAK, 2=RANGING, 3=VOLATILE, 4=CRISIS, 5=CHOPPY, 6=SQUEEZE, 7=UNKNOWN
   // KZ: 0=NONE, 1=ASIAN, 2=LONDON_OPEN, 3=NY, 4=LONDON_CLOSE
   int m_modifier[8][5];

   int RegimeIdx(MARKET_REGIME r)
   {
      switch(r)
      {
         case REGIME_TREND_STRONG: return 0;
         case REGIME_TREND_WEAK:   return 1;
         case REGIME_RANGING:      return 2;
         case REGIME_VOLATILE:     return 3;
         case REGIME_CRISIS:       return 4;
         case REGIME_CHOPPY:       return 5;
         case REGIME_SQUEEZE:      return 6;
         default:                  return 7;
      }
   }

   int KZIdx(ENUM_KILLZONE kz)
   {
      switch(kz)
      {
         case KILLZONE_ASIAN:        return 1;
         case KILLZONE_LONDON_OPEN:  return 2;
         case KILLZONE_NY:           return 3;
         case KILLZONE_LONDON_CLOSE: return 4;
         default:                    return 0;
      }
   }

   string RegimeToStr(MARKET_REGIME r)
   {
      switch(r)
      {
         case REGIME_TREND_STRONG: return "TREND_STRONG";
         case REGIME_TREND_WEAK:   return "TREND_WEAK";
         case REGIME_RANGING:      return "RANGING";
         case REGIME_VOLATILE:     return "VOLATILE";
         case REGIME_CRISIS:       return "CRISIS";
         case REGIME_CHOPPY:       return "CHOPPY";
         case REGIME_SQUEEZE:      return "SQUEEZE";
         default:                  return "UNKNOWN";
      }
   }

   string KZToStr(ENUM_KILLZONE kz)
   {
      switch(kz)
      {
         case KILLZONE_ASIAN:        return "Asian";
         case KILLZONE_LONDON_OPEN:  return "London Open";
         case KILLZONE_NY:           return "NY";
         case KILLZONE_LONDON_CLOSE: return "London Close";
         default:                    return "NONE";
      }
   }

   int WRToModifier(double wr)
   {
      if(wr < 0.45) return  2;   // weak — tighten
      if(wr < 0.55) return  1;   // below average
      if(wr < 0.65) return  0;   // neutral
      return                -1;  // strong — slight relief
   }

public:
   CKillzoneIntelligence() : m_db(NULL), m_lastUpdate(0)
   {
      ArrayInitialize(m_modifier, 0);
   }

   void Init(CDatabaseManager* db) { m_db = db; }

   //+------------------------------------------------------------------+
   //| Query DB for all regime+killzone WR combos.                      |
   //| Also prints GateLog digest (top blocking gate per regime).       |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(m_db == NULL) return;
      datetime now = TimeCurrent();
      if(now - m_lastUpdate < KZI_UPDATE_INTERVAL) return;
      m_lastUpdate = now;

      MARKET_REGIME regimes[] = {
         REGIME_TREND_STRONG, REGIME_TREND_WEAK, REGIME_RANGING,
         REGIME_VOLATILE, REGIME_SQUEEZE
      };
      ENUM_KILLZONE kzones[] = {
         KILLZONE_ASIAN, KILLZONE_LONDON_OPEN, KILLZONE_NY, KILLZONE_LONDON_CLOSE
      };

      // ── 1. Killzone WR matrix ─────────────────────────────────────
      for(int ri = 0; ri < ArraySize(regimes); ri++)
      {
         string rlabel = RegimeToStr(regimes[ri]);
         for(int ki = 0; ki < ArraySize(kzones); ki++)
         {
            string klabel = KZToStr(kzones[ki]);
            double wr = 0; int cnt = 0;
            if(m_db.GetKillzoneWR(rlabel, klabel, KZI_MIN_TRADES, wr, cnt))
            {
               int mod = WRToModifier(wr);
               m_modifier[RegimeIdx(regimes[ri])][KZIdx(kzones[ki])] = mod;
               if(mod != 0)
                  PrintFormat("[KZIntel] %s + %s: WR=%.1f%% (n=%d) → threshold %+d",
                              rlabel, klabel, wr * 100.0, cnt, mod);
            }
         }
      }

      // ── 2. GateLog digest — top blocking gate per regime ──────────
      PrintFormat("[GateDigest] ─── Daily Gate Block Summary ───");
      for(int ri = 0; ri < ArraySize(regimes); ri++)
      {
         string rlabel = RegimeToStr(regimes[ri]);
         string topGate = ""; double blockPct = 0;
         if(m_db.GetTopGateBlock(rlabel, topGate, blockPct))
            PrintFormat("[GateDigest] %s: top block = '%s' (%.1f%% of all rejections)",
                        rlabel, topGate, blockPct);
      }
   }

   //+------------------------------------------------------------------+
   //| Get threshold modifier for a (regime, killzone) combination.     |
   //| Returns 0 if no data (neutral — no change to minEntry).          |
   //+------------------------------------------------------------------+
   int GetThresholdModifier(MARKET_REGIME regime, ENUM_KILLZONE kz)
   {
      return m_modifier[RegimeIdx(regime)][KZIdx(kz)];
   }
};

#endif
