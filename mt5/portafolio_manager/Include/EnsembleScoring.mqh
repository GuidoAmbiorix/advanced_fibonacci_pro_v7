//+------------------------------------------------------------------+
//|                                          EnsembleScoring.mqh     |
//|                       Ensemble Model Scoring System               |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Model Vote Structure                                             |
//+------------------------------------------------------------------+
struct ModelVote
{
   int      signal;      // 1 = buy, -1 = sell, 0 = neutral
   double   confidence;  // 0-1.0
   double   weight;      // Model weight in ensemble
};

//+------------------------------------------------------------------+
//| Ensemble Decision                                                |
//+------------------------------------------------------------------+
struct EnsembleDecision
{
   int      finalSignal;
   double   confidence;
   string   agreementLevel;
   int      bullishVotes;
   int      bearishVotes;
   int      neutralVotes;
};

//+------------------------------------------------------------------+
//| Ensemble Scoring Class                                           |
//+------------------------------------------------------------------+
class CEnsembleScoring
{
private:
   // Model weights (total = 100%)
   double   m_weightSMC;           // 30% - Pure SMC model
   double   m_weightVolume;        // 25% - Volume-weighted model
   double   m_weightDivergence;    // 15% - Divergence-focused
   double   m_weightWyckoff;       // 15% - Wyckoff-based
   double   m_weightTrend;         // 15% - Trend-following

   // Minimum confidence threshold
   double   m_minConfidence;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CEnsembleScoring()
   {
      m_weightSMC = 0.30;
      m_weightVolume = 0.25;
      m_weightDivergence = 0.15;
      m_weightWyckoff = 0.15;
      m_weightTrend = 0.15;
      m_minConfidence = 0.60;  // 60% minimum ensemble confidence
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init(double weightSMC = 0.30, double weightVolume = 0.25,
            double weightDivergence = 0.15, double weightWyckoff = 0.15,
            double weightTrend = 0.15)
   {
      m_weightSMC = weightSMC;
      m_weightVolume = weightVolume;
      m_weightDivergence = weightDivergence;
      m_weightWyckoff = weightWyckoff;
      m_weightTrend = weightTrend;

      // Normalize weights to 100%
      double total = m_weightSMC + m_weightVolume + m_weightDivergence +
                     m_weightWyckoff + m_weightTrend;

      if(total > 0)
      {
         m_weightSMC /= total;
         m_weightVolume /= total;
         m_weightDivergence /= total;
         m_weightWyckoff /= total;
         m_weightTrend /= total;
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Ensemble Decision                                     |
   //+------------------------------------------------------------------+
   EnsembleDecision CalculateEnsemble(double smcScore, double volumeScore,
                                      double divergenceScore, double wyckoffScore,
                                      double trendScore, int direction)
   {
      EnsembleDecision decision;
      decision.bullishVotes = 0;
      decision.bearishVotes = 0;
      decision.neutralVotes = 0;

      // Model 1: Pure SMC Model
      ModelVote smcVote = GetSMCVote(smcScore, direction);

      // Model 2: Volume-Weighted Model
      ModelVote volumeVote = GetVolumeVote(volumeScore, direction);

      // Model 3: Divergence-Focused Model
      ModelVote divVote = GetDivergenceVote(divergenceScore, direction);

      // Model 4: Wyckoff-Based Model
      ModelVote wyckoffVote = GetWyckoffVote(wyckoffScore, direction);

      // Model 5: Trend-Following Model
      ModelVote trendVote = GetTrendVote(trendScore, direction);

      // Count votes
      if(smcVote.signal == 1) decision.bullishVotes++;
      else if(smcVote.signal == -1) decision.bearishVotes++;
      else decision.neutralVotes++;

      if(volumeVote.signal == 1) decision.bullishVotes++;
      else if(volumeVote.signal == -1) decision.bearishVotes++;
      else decision.neutralVotes++;

      if(divVote.signal == 1) decision.bullishVotes++;
      else if(divVote.signal == -1) decision.bearishVotes++;
      else decision.neutralVotes++;

      if(wyckoffVote.signal == 1) decision.bullishVotes++;
      else if(wyckoffVote.signal == -1) decision.bearishVotes++;
      else decision.neutralVotes++;

      if(trendVote.signal == 1) decision.bullishVotes++;
      else if(trendVote.signal == -1) decision.bearishVotes++;
      else decision.neutralVotes++;

      // Weighted voting
      double weightedBull = 0;
      double weightedBear = 0;

      if(smcVote.signal == 1) weightedBull += m_weightSMC * smcVote.confidence;
      else if(smcVote.signal == -1) weightedBear += m_weightSMC * smcVote.confidence;

      if(volumeVote.signal == 1) weightedBull += m_weightVolume * volumeVote.confidence;
      else if(volumeVote.signal == -1) weightedBear += m_weightVolume * volumeVote.confidence;

      if(divVote.signal == 1) weightedBull += m_weightDivergence * divVote.confidence;
      else if(divVote.signal == -1) weightedBear += m_weightDivergence * divVote.confidence;

      if(wyckoffVote.signal == 1) weightedBull += m_weightWyckoff * wyckoffVote.confidence;
      else if(wyckoffVote.signal == -1) weightedBear += m_weightWyckoff * wyckoffVote.confidence;

      if(trendVote.signal == 1) weightedBull += m_weightTrend * trendVote.confidence;
      else if(trendVote.signal == -1) weightedBear += m_weightTrend * trendVote.confidence;

      // Final decision
      if(weightedBull > weightedBear && weightedBull >= m_minConfidence)
      {
         decision.finalSignal = 1;
         decision.confidence = weightedBull;
      }
      else if(weightedBear > weightedBull && weightedBear >= m_minConfidence)
      {
         decision.finalSignal = -1;
         decision.confidence = weightedBear;
      }
      else
      {
         decision.finalSignal = 0;
         decision.confidence = MathMax(weightedBull, weightedBear);
      }

      // Agreement level
      int totalVotes = decision.bullishVotes + decision.bearishVotes + decision.neutralVotes;
      double agreement = (double)MathMax(decision.bullishVotes, decision.bearishVotes) / totalVotes;

      if(agreement >= 0.8)
         decision.agreementLevel = "Strong Agreement";
      else if(agreement >= 0.6)
         decision.agreementLevel = "Moderate Agreement";
      else
         decision.agreementLevel = "Weak Agreement";

      return decision;
   }

   //+------------------------------------------------------------------+
   //| Get SMC Model Vote                                              |
   //+------------------------------------------------------------------+
   ModelVote GetSMCVote(double smcScore, int direction)
   {
      ModelVote vote;
      vote.weight = m_weightSMC;

      // SMC model: Structure + OB + FVG + Liquidity (max 5.0)
      if(smcScore >= 4.0) // Strong SMC confluence
      {
         vote.signal = direction;
         vote.confidence = MathMin(smcScore / 5.0, 1.0);
      }
      else if(smcScore >= 3.0) // Moderate SMC
      {
         vote.signal = direction;
         vote.confidence = 0.6;
      }
      else
      {
         vote.signal = 0; // Neutral
         vote.confidence = 0.5;
      }

      return vote;
   }

   //+------------------------------------------------------------------+
   //| Get Volume Model Vote                                           |
   //+------------------------------------------------------------------+
   ModelVote GetVolumeVote(double volumeScore, int direction)
   {
      ModelVote vote;
      vote.weight = m_weightVolume;

      // Volume model: POC + VAH/VAL + VWAP + Breakout (max 2.5)
      if(volumeScore >= 2.0) // Strong volume confluence
      {
         vote.signal = direction;
         vote.confidence = MathMin(volumeScore / 2.5, 1.0);
      }
      else if(volumeScore >= 1.5) // Moderate volume
      {
         vote.signal = direction;
         vote.confidence = 0.7;
      }
      else
      {
         vote.signal = 0; // Neutral
         vote.confidence = 0.5;
      }

      return vote;
   }

   //+------------------------------------------------------------------+
   //| Get Divergence Model Vote                                       |
   //+------------------------------------------------------------------+
   ModelVote GetDivergenceVote(double divergenceScore, int direction)
   {
      ModelVote vote;
      vote.weight = m_weightDivergence;

      // Divergence model: Regular + Hidden (max 1.5)
      if(divergenceScore >= 1.5) // Regular divergence detected
      {
         vote.signal = direction;
         vote.confidence = 0.9;
      }
      else if(divergenceScore >= 1.0) // Hidden divergence
      {
         vote.signal = direction;
         vote.confidence = 0.7;
      }
      else
      {
         vote.signal = 0; // Neutral
         vote.confidence = 0.5;
      }

      return vote;
   }

   //+------------------------------------------------------------------+
   //| Get Wyckoff Model Vote                                          |
   //+------------------------------------------------------------------+
   ModelVote GetWyckoffVote(double wyckoffScore, int direction)
   {
      ModelVote vote;
      vote.weight = m_weightWyckoff;

      // Wyckoff model: Breakout from accumulation/distribution (max 1.5)
      if(wyckoffScore >= 1.5) // Breakout from accumulation/distribution
      {
         vote.signal = direction;
         vote.confidence = 0.9;
      }
      else if(wyckoffScore >= 1.0) // Continuation in markup/markdown
      {
         vote.signal = direction;
         vote.confidence = 0.7;
      }
      else
      {
         vote.signal = 0; // Neutral
         vote.confidence = 0.5;
      }

      return vote;
   }

   //+------------------------------------------------------------------+
   //| Get Trend Model Vote                                            |
   //+------------------------------------------------------------------+
   ModelVote GetTrendVote(double trendScore, int direction)
   {
      ModelVote vote;
      vote.weight = m_weightTrend;

      // Trend model: MTF alignment (max 2.0)
      if(trendScore >= 2.0) // Full MTF alignment
      {
         vote.signal = direction;
         vote.confidence = 1.0;
      }
      else if(trendScore >= 1.5) // Partial MTF
      {
         vote.signal = direction;
         vote.confidence = 0.7;
      }
      else
      {
         vote.signal = 0; // Neutral
         vote.confidence = 0.5;
      }

      return vote;
   }

   //+------------------------------------------------------------------+
   //| Get Ensemble Report                                             |
   //+------------------------------------------------------------------+
   string GetEnsembleReport(EnsembleDecision &decision)
   {
      string report = "=== ENSEMBLE VOTING ===\n";

      report += StringFormat("Bullish Votes: %d\n", decision.bullishVotes);
      report += StringFormat("Bearish Votes: %d\n", decision.bearishVotes);
      report += StringFormat("Neutral Votes: %d\n", decision.neutralVotes);

      report += "\nWeighted Confidence: " + DoubleToString(decision.confidence * 100, 1) + "%\n";
      report += "Agreement: " + decision.agreementLevel + "\n";

      report += "\nFinal Signal: ";
      if(decision.finalSignal == 1)
         report += "BUY";
      else if(decision.finalSignal == -1)
         report += "SELL";
      else
         report += "NEUTRAL";

      return report;
   }

   //+------------------------------------------------------------------+
   //| Getters/Setters                                                  |
   //+------------------------------------------------------------------+
   void SetMinConfidence(double minConf) { m_minConfidence = minConf; }
   double GetMinConfidence() { return m_minConfidence; }
};
