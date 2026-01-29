/**
 * @file MultiAgentEnsemble.mqh
 * @brief V3 Multi-Agent Ensemble System
 * @version 3.0.0-alpha
 *
 * Coordinates multiple specialized agents for trading decisions
 */

#property copyright "V3 Trading System"
#property version   "3.00"
#property strict

#include "PythonAPIClient.mqh"

// ==================== Agent Types ====================

enum ENUM_AGENT_TYPE
{
   AGENT_TECHNICAL,       // SMC + Technical Confluence
   AGENT_SENTIMENT,       // FinBERT News Sentiment
   AGENT_REGIME,          // HMM Regime Detection
   AGENT_ORDERFLOW,       // Market Microstructure
   AGENT_DRL,             // Deep RL Portfolio Optimizer
   AGENT_TRADITIONAL      // V2 Adaptive System
};

// ==================== Structures ====================

struct AgentVote
{
   ENUM_AGENT_TYPE type;
   int      direction;           // 0=skip, 1=buy, -1=sell
   double   confidence;          // 0.0-1.0
   double   weight;              // Performance-based weight
   string   reason;              // Plain English explanation
};

struct EnsembleDecision
{
   int      finalDirection;      // 0=skip, 1=buy, -1=sell
   double   totalConfidence;     // Weighted confidence
   double   confluenceScore;     // Effective confluence
   AgentVote votes[];            // Individual agent votes
   string   explanation;         // Human-readable explanation
};

struct AgentPerformance
{
   ENUM_AGENT_TYPE type;
   int      totalVotes;
   int      correctVotes;
   double   winRate;
   double   sharpeContribution;
   double   weight;              // Calculated from performance
};

// ==================== Multi-Agent Ensemble Class ====================

class CMultiAgentEnsemble
{
private:
   CPythonAPIClient   m_api;

   // Agent performance tracking
   AgentPerformance   m_performance[];

   // Thresholds
   double   m_minTotalConfidence;     // Minimum weighted confidence to trade
   double   m_ensembleThreshold;      // Minimum number of agreeing agents

   // Performance history
   datetime m_lastPerformanceUpdate;

public:
   /**
    * Constructor
    */
   CMultiAgentEnsemble() : m_minTotalConfidence(3.0),
                           m_ensembleThreshold(0.6),
                           m_lastPerformanceUpdate(0)
   {
      InitializePerformance();
   }

   /**
    * Initialize agent performance tracking
    */
   void InitializePerformance()
   {
      ArrayResize(m_performance, 6);

      for(int i = 0; i < 6; i++)
      {
         m_performance[i].type = (ENUM_AGENT_TYPE)i;
         m_performance[i].totalVotes = 0;
         m_performance[i].correctVotes = 0;
         m_performance[i].winRate = 0.5;
         m_performance[i].sharpeContribution = 1.0;
         m_performance[i].weight = 1.0;  // Equal weights initially
      }
   }

   /**
    * Connect to Python API
    */
   bool Init(string apiUrl = "http://localhost:8000")
   {
      return m_api.Init(apiUrl);
   }

   /**
    * Get ensemble trading decision
    */
   bool GetDecision(string symbol, int direction, double baseConfluence, EnsembleDecision &decision)
   {
      ArrayResize(decision.votes, 0);

      // AGENT 1: Technical Analysis (SMC + Confluence)
      AgentVote technicalVote;
      GetTechnicalVote(symbol, direction, baseConfluence, technicalVote);
      AddVote(decision.votes, technicalVote);

      // AGENT 2: Sentiment Analysis (FinBERT)
      AgentVote sentimentVote;
      GetSentimentVote(symbol, direction, sentimentVote);
      AddVote(decision.votes, sentimentVote);

      // AGENT 3: Regime Detection (HMM)
      AgentVote regimeVote;
      GetRegimeVote(symbol, direction, regimeVote);
      AddVote(decision.votes, regimeVote);

      // AGENT 4: Order Flow Analysis
      AgentVote orderFlowVote;
      GetOrderFlowVote(symbol, direction, orderFlowVote);
      AddVote(decision.votes, orderFlowVote);

      // AGENT 5: DRL Portfolio Optimizer
      AgentVote drlVote;
      GetDRLVote(symbol, direction, drlVote);
      AddVote(decision.votes, drlVote);

      // AGENT 6: Traditional V2 Logic (fallback)
      AgentVote traditionalVote;
      GetTraditionalVote(symbol, direction, baseConfluence, traditionalVote);
      AddVote(decision.votes, traditionalVote);

      // Calculate ensemble decision
      CalculateEnsembleDecision(decision);

      // Generate explanation
      GenerateExplanation(decision);

      return (decision.totalConfidence >= m_minTotalConfidence);
   }

   /**
    * Update agent performance after trade result
    */
   void UpdatePerformance(ENUM_AGENT_TYPE agentType, bool wasCorrect)
   {
      for(int i = 0; i < ArraySize(m_performance); i++)
      {
         if(m_performance[i].type == agentType)
         {
            m_performance[i].totalVotes++;
            if(wasCorrect)
               m_performance[i].correctVotes++;

            // Recalculate win rate
            if(m_performance[i].totalVotes > 0)
               m_performance[i].winRate = (double)m_performance[i].correctVotes / m_performance[i].totalVotes;

            // Recalculate weight (every 10 votes)
            if(m_performance[i].totalVotes % 10 == 0)
               RecalculateWeights();

            break;
         }
      }
   }

private:
   /**
    * Get technical analysis vote
    */
   void GetTechnicalVote(string symbol, int direction, double baseConfluence, AgentVote &vote)
   {
      vote.type = AGENT_TECHNICAL;
      vote.direction = (baseConfluence >= 5.0) ? direction : 0;
      vote.confidence = MathMin(baseConfluence / 10.0, 1.0);
      vote.weight = GetAgentWeight(AGENT_TECHNICAL);
      vote.reason = StringFormat("Technical confluence: %.1f/10", baseConfluence);
   }

   /**
    * Get sentiment vote
    */
   void GetSentimentVote(string symbol, int direction, AgentVote &vote)
   {
      SentimentScore score;
      bool success = m_api.GetSentiment(symbol, score);

      vote.type = AGENT_SENTIMENT;
      vote.weight = GetAgentWeight(AGENT_SENTIMENT);

      if(!success || score.confidence < 0.5)
      {
         vote.direction = 0;
         vote.confidence = 0.0;
         vote.reason = "Sentiment unavailable";
         return;
      }

      // Check if sentiment agrees with direction
      if((direction == 1 && score.composite > 0.3) ||
         (direction == -1 && score.composite < -0.3))
      {
         vote.direction = direction;
         vote.confidence = score.confidence;
         vote.reason = StringFormat("Sentiment %.2f (confidence: %.2f)", score.composite, score.confidence);
      }
      else if((direction == 1 && score.composite < -0.3) ||
              (direction == -1 && score.composite > 0.3))
      {
         vote.direction = 0;  // Against sentiment
         vote.confidence = 0.5;
         vote.reason = StringFormat("Counter-sentiment (%.2f)", score.composite);
      }
      else
      {
         vote.direction = 0;  // Neutral
         vote.confidence = 0.3;
         vote.reason = "Neutral sentiment";
      }
   }

   /**
    * Get regime vote
    */
   void GetRegimeVote(string symbol, int direction, AgentVote &vote)
   {
      RegimeDetection regime;
      bool success = m_api.GetRegime(symbol, regime);

      vote.type = AGENT_REGIME;
      vote.weight = GetAgentWeight(AGENT_REGIME);

      if(!success)
      {
         vote.direction = 0;
         vote.confidence = 0.0;
         vote.reason = "Regime unavailable";
         return;
      }

      // Check if regime is favorable
      bool favorableForBuy = (regime.regime == REGIME_LOW_VOL_BULL || regime.regime == REGIME_HIGH_VOL_BULL);
      bool favorableForSell = (regime.regime == REGIME_LOW_VOL_BEAR || regime.regime == REGIME_HIGH_VOL_BEAR);
      bool crisis = (regime.regime == REGIME_CRISIS);

      if(crisis)
      {
         vote.direction = 0;
         vote.confidence = 1.0;
         vote.reason = "Crisis regime - no trading";
      }
      else if((direction == 1 && favorableForBuy) || (direction == -1 && favorableForSell))
      {
         vote.direction = direction;
         vote.confidence = regime.confidence;
         vote.reason = StringFormat("Regime: %s", EnumToString(regime.regime));
      }
      else
      {
         vote.direction = 0;
         vote.confidence = regime.confidence * 0.5;
         vote.reason = StringFormat("Adverse regime: %s", EnumToString(regime.regime));
      }
   }

   /**
    * Get order flow vote
    */
   void GetOrderFlowVote(string symbol, int direction, AgentVote &vote)
   {
      OrderFlowAnalysis flow;
      bool success = m_api.GetOrderFlow(symbol, flow);

      vote.type = AGENT_ORDERFLOW;
      vote.weight = GetAgentWeight(AGENT_ORDERFLOW);

      if(!success)
      {
         vote.direction = 0;
         vote.confidence = 0.0;
         vote.reason = "Order flow unavailable";
         return;
      }

      // Check if order flow agrees
      if((direction == 1 && flow.imbalance > 0.3) ||
         (direction == -1 && flow.imbalance < -0.3))
      {
         vote.direction = direction;
         vote.confidence = flow.confidence;
         vote.reason = StringFormat("Order flow: %.2f imbalance", flow.imbalance);
      }
      else if((direction == 1 && flow.imbalance < -0.3) ||
              (direction == -1 && flow.imbalance > 0.3))
      {
         vote.direction = 0;
         vote.confidence = 0.6;
         vote.reason = "Counter-flow detected";
      }
      else
      {
         vote.direction = 0;
         vote.confidence = 0.3;
         vote.reason = "Neutral order flow";
      }
   }

   /**
    * Get DRL vote
    */
   void GetDRLVote(string symbol, int direction, AgentVote &vote)
   {
      vote.type = AGENT_DRL;
      vote.direction = direction;  // DRL adjusts risk, not direction
      vote.confidence = 0.5;  // Placeholder
      vote.weight = GetAgentWeight(AGENT_DRL);
      vote.reason = "DRL portfolio allocation";
   }

   /**
    * Get traditional vote (V2 adaptive logic)
    */
   void GetTraditionalVote(string symbol, int direction, double baseConfluence, AgentVote &vote)
   {
      vote.type = AGENT_TRADITIONAL;
      vote.direction = (baseConfluence >= 6.0) ? direction : 0;
      vote.confidence = MathMin((baseConfluence - 4.0) / 4.0, 1.0);
      vote.weight = GetAgentWeight(AGENT_TRADITIONAL);
      vote.reason = StringFormat("V2 adaptive (C=%.1f)", baseConfluence);
   }

   /**
    * Add vote to array
    */
   void AddVote(AgentVote &votes[], AgentVote &vote)
   {
      int size = ArraySize(votes);
      ArrayResize(votes, size + 1);
      votes[size] = vote;
   }

   /**
    * Calculate final ensemble decision
    */
   void CalculateEnsembleDecision(EnsembleDecision &decision)
   {
      double totalWeightedBuy = 0.0;
      double totalWeightedSell = 0.0;
      double totalWeight = 0.0;

      for(int i = 0; i < ArraySize(decision.votes); i++)
      {
         AgentVote vote = decision.votes[i];
         double weightedConfidence = vote.confidence * vote.weight;

         if(vote.direction == 1)
            totalWeightedBuy += weightedConfidence;
         else if(vote.direction == -1)
            totalWeightedSell += weightedConfidence;

         totalWeight += vote.weight;
      }

      // Determine direction
      if(totalWeightedBuy > totalWeightedSell && totalWeightedBuy > m_minTotalConfidence)
      {
         decision.finalDirection = 1;
         decision.totalConfidence = totalWeightedBuy;
      }
      else if(totalWeightedSell > totalWeightedBuy && totalWeightedSell > m_minTotalConfidence)
      {
         decision.finalDirection = -1;
         decision.totalConfidence = totalWeightedSell;
      }
      else
      {
         decision.finalDirection = 0;
         decision.totalConfidence = MathMax(totalWeightedBuy, totalWeightedSell);
      }

      // Convert to effective confluence (for compatibility with existing system)
      decision.confluenceScore = decision.totalConfidence * 2.0;  // Scale to ~6.0 range
   }

   /**
    * Generate human-readable explanation
    */
   void GenerateExplanation(EnsembleDecision &decision)
   {
      string explanation = "ENSEMBLE DECISION:\n";
      explanation += StringFormat("Direction: %s | Confidence: %.2f\n\n",
                                  decision.finalDirection == 1 ? "BUY" : (decision.finalDirection == -1 ? "SELL" : "SKIP"),
                                  decision.totalConfidence);

      explanation += "Agent Votes:\n";
      for(int i = 0; i < ArraySize(decision.votes); i++)
      {
         AgentVote vote = decision.votes[i];
         string dirStr = vote.direction == 1 ? "BUY" : (vote.direction == -1 ? "SELL" : "SKIP");
         explanation += StringFormat("- %s: %s (%.2f × %.1f = %.2f) - %s\n",
                                     EnumToString(vote.type),
                                     dirStr,
                                     vote.confidence,
                                     vote.weight,
                                     vote.confidence * vote.weight,
                                     vote.reason);
      }

      decision.explanation = explanation;
   }

   /**
    * Get agent weight by type
    */
   double GetAgentWeight(ENUM_AGENT_TYPE type)
   {
      for(int i = 0; i < ArraySize(m_performance); i++)
      {
         if(m_performance[i].type == type)
            return m_performance[i].weight;
      }
      return 1.0;
   }

   /**
    * Recalculate agent weights based on performance
    */
   void Recalculate Weights()
   {
      for(int i = 0; i < ArraySize(m_performance); i++)
      {
         if(m_performance[i].totalVotes < 10)
            continue;  // Not enough data

         // Weight = (Win Rate × 2 + Sharpe) / 3
         double weight = (m_performance[i].winRate * 2.0 + m_performance[i].sharpeContribution) / 3.0;

         // Clamp to 0.5-2.0
         m_performance[i].weight = MathMax(0.5, MathMin(2.0, weight));
      }

      Print("🔄 ENSEMBLE: Agent weights recalculated");
   }
};
