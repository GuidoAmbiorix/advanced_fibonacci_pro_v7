//+------------------------------------------------------------------+
//|                                          ScoreIntelligence.mqh  |
//|  Module 3: Score Intelligence                                    |
//|  Queries DB every 24h to find the score bucket (per regime)     |
//|  where WR >= 55%. Adjusts minEntry up or down within ±4 pts.    |
//|                                                                  |
//|  Usage:                                                          |
//|    CScoreIntelligence scoreIntel;                                |
//|    scoreIntel.Init(&dbManager, InpMinConfluenceEntry);           |
//|    scoreIntel.Update();          // call on day reset            |
//|    int adj = scoreIntel.GetAdjustedMinScore(g_currentRegime);   |
//+------------------------------------------------------------------+
#ifndef SCORE_INTELLIGENCE_MQH
#define SCORE_INTELLIGENCE_MQH

#include "../DatabaseManager.mqh"
#include "../MarketRegime.mqh"

#define SI_UPDATE_INTERVAL  86400   // 24 h in seconds
#define SI_MIN_TRADES       10      // min trades per bucket before adjusting
#define SI_MAX_DELTA        4.0     // max ± adjustment from base

class CScoreIntelligence
{
private:
   CDatabaseManager* m_db;
   int               m_baseMin;
   datetime          m_lastUpdate;
   double            m_adjMin[8];   // indexed by MARKET_REGIME

   int RegimeIndex(MARKET_REGIME r)
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

public:
   CScoreIntelligence() : m_db(NULL), m_baseMin(4), m_lastUpdate(0)
   {
      ArrayInitialize(m_adjMin, 0);
   }

   void Init(CDatabaseManager* db, int baseMin)
   {
      m_db      = db;
      m_baseMin = baseMin;
      for(int i = 0; i < 8; i++) m_adjMin[i] = baseMin;
   }

   //+------------------------------------------------------------------+
   //| Refresh DB-calibrated minimums once per day.                     |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(m_db == NULL) return;
      datetime now = TimeCurrent();
      if(now - m_lastUpdate < SI_UPDATE_INTERVAL) return;
      m_lastUpdate = now;

      MARKET_REGIME regimes[] = {
         REGIME_TREND_STRONG, REGIME_TREND_WEAK, REGIME_RANGING,
         REGIME_VOLATILE, REGIME_SQUEEZE
      };

      for(int i = 0; i < ArraySize(regimes); i++)
      {
         string label = RegimeToStr(regimes[i]);
         double minScore = 0, wr = 0;

         if(m_db.GetScoreStats(label, SI_MIN_TRADES, minScore, wr))
         {
            double adjusted = MathMax((double)m_baseMin - SI_MAX_DELTA,
                              MathMin((double)m_baseMin + SI_MAX_DELTA, minScore));
            m_adjMin[RegimeIndex(regimes[i])] = adjusted;
            PrintFormat("[ScoreIntel] %s: bucket=%.0f WR=%.1f%% → adjMin=%.0f",
                        label, minScore, wr * 100.0, adjusted);
         }
         else
            m_adjMin[RegimeIndex(regimes[i])] = m_baseMin;
      }
   }

   //+------------------------------------------------------------------+
   //| Get DB-calibrated minimum confluence for a regime.               |
   //+------------------------------------------------------------------+
   int GetAdjustedMinScore(MARKET_REGIME regime)
   {
      double v = m_adjMin[RegimeIndex(regime)];
      return (v > 0) ? (int)MathRound(v) : m_baseMin;
   }
};

#endif
