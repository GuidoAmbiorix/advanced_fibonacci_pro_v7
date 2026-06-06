//+------------------------------------------------------------------+
//|                                            MFECalibration.mqh   |
//|  Module 4: MFE/MAE Calibration                                  |
//|  Queries avg MFE_R per regime from DB every 24h.                |
//|  Returns a multiplier (0.70–1.30) to scale escalator firstR.    |
//|                                                                  |
//|  Usage:                                                          |
//|    CMFECalibration mfeCalib;                                     |
//|    mfeCalib.Init(&dbManager);                                    |
//|    mfeCalib.Update();           // call on day reset             |
//|    double m = mfeCalib.GetCalibrationMultiplier(regime);         |
//|    g_escCfg.firstR *= m;                                         |
//+------------------------------------------------------------------+
#ifndef MFE_CALIBRATION_MQH
#define MFE_CALIBRATION_MQH

#include "../DatabaseManager.mqh"
#include "../MarketRegime.mqh"

#define MFEC_UPDATE_INTERVAL  86400  // 24 h
#define MFEC_REFERENCE_MFE_R  2.0   // expected avg MFE in R for a well-run trade
#define MFEC_MIN_MULT         0.70
#define MFEC_MAX_MULT         1.30
// SL calibration: target SL = avgMAE_R * SL_SAFETY_BUFFER
// e.g. avgMAE=0.5, buffer=1.5 → ideal SL = 0.75R of current → mult=0.75
#define MFEC_SL_SAFETY_BUFFER 1.5
#define MFEC_SL_MIN_MULT      0.70
#define MFEC_SL_MAX_MULT      1.20

class CMFECalibration
{
private:
   CDatabaseManager* m_db;
   datetime          m_lastUpdate;
   double            m_mult[8];     // MFE → firstR multiplier, indexed by MARKET_REGIME
   double            m_slMult[8];   // MAE → SL distance multiplier, indexed by MARKET_REGIME

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
   CMFECalibration() : m_db(NULL), m_lastUpdate(0)
   {
      ArrayInitialize(m_mult,   1.0);
      ArrayInitialize(m_slMult, 1.0);
   }

   void Init(CDatabaseManager* db)
   {
      m_db = db;
   }

   //+------------------------------------------------------------------+
   //| Query DB for avg MFE_R per regime and update multipliers.        |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(m_db == NULL) return;
      datetime now = TimeCurrent();
      if(now - m_lastUpdate < MFEC_UPDATE_INTERVAL) return;
      m_lastUpdate = now;

      MARKET_REGIME regimes[] = {
         REGIME_TREND_STRONG, REGIME_TREND_WEAK, REGIME_RANGING,
         REGIME_VOLATILE, REGIME_SQUEEZE
      };

      for(int i = 0; i < ArraySize(regimes); i++)
      {
         string label = RegimeToStr(regimes[i]);
         double avgMFE = 0;

         // MFE → firstR calibration
         if(m_db.GetMFEStats(label, avgMFE) && avgMFE > 0.1)
         {
            double raw  = avgMFE / MFEC_REFERENCE_MFE_R;
            double mult = MathMax(MFEC_MIN_MULT, MathMin(MFEC_MAX_MULT, raw));
            m_mult[RegimeIndex(regimes[i])] = mult;
            PrintFormat("[MFECalib] %s: avgMFE_R=%.2f → firstR mult=%.2f", label, avgMFE, mult);
         }
         else
            m_mult[RegimeIndex(regimes[i])] = 1.0;

         // MAE → SL calibration
         // Ideal SL = avgMAE_R * SAFETY_BUFFER (1.5x) as fraction of current SL (1.0R base)
         // mult < 1.0 = tighten SL (trades rarely go far against)
         // mult > 1.0 = widen SL (trades need more room before recovering)
         double avgMAE = 0;
         if(m_db.GetMAEStats(label, avgMAE) && avgMAE > 0.05)
         {
            double slMult = MathMax(MFEC_SL_MIN_MULT, MathMin(MFEC_SL_MAX_MULT,
                                    avgMAE * MFEC_SL_SAFETY_BUFFER));
            m_slMult[RegimeIndex(regimes[i])] = slMult;
            PrintFormat("[MFECalib] %s: avgMAE_R=%.2f → SL mult=%.2f", label, avgMAE, slMult);
         }
         else
            m_slMult[RegimeIndex(regimes[i])] = 1.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Get calibration multiplier for escalator firstR.                 |
   //+------------------------------------------------------------------+
   double GetCalibrationMultiplier(MARKET_REGIME regime)
   {
      return m_mult[RegimeIndex(regime)];
   }

   //+------------------------------------------------------------------+
   //| Get SL distance multiplier from MAE history.                     |
   //| Apply to slDist at entry: slDist *= mfeCalib.GetSLMultiplier()   |
   //+------------------------------------------------------------------+
   double GetSLMultiplier(MARKET_REGIME regime)
   {
      return m_slMult[RegimeIndex(regime)];
   }
};

#endif
