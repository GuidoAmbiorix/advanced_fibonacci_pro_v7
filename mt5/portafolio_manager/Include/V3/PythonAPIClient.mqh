/**
 * @file PythonAPIClient.mqh
 * @brief V3 Python Microservices API Client for MT5
 * @version 3.0.0-alpha
 * @date 2026-01-29
 *
 * Handles HTTP communication between MT5 and Python FastAPI services
 */

#property copyright "V3 Trading System"
#property version   "3.00"
#property strict

// ==================== Data Structures ====================

enum ENUM_ML_REGIME
{
   REGIME_LOW_VOL_BULL,      // Low volatility uptrend
   REGIME_LOW_VOL_BEAR,      // Low volatility downtrend
   REGIME_HIGH_VOL_BULL,     // High volatility uptrend
   REGIME_HIGH_VOL_BEAR,     // High volatility downtrend
   REGIME_SIDEWAYS_TIGHT,    // Tight range
   REGIME_SIDEWAYS_WIDE,     // Wide range
   REGIME_BREAKOUT,          // Breakout
   REGIME_CRISIS             // Flash crash / extreme volatility
};

struct SentimentScore
{
   string   symbol;
   double   positive;        // 0.0-1.0
   double   negative;        // 0.0-1.0
   double   neutral;         // 0.0-1.0
   double   composite;       // -1.0 to +1.0
   double   confidence;      // 0.0-1.0
   datetime timestamp;
};

struct RegimeDetection
{
   string         symbol;
   ENUM_ML_REGIME regime;
   double         probabilities[8];  // One for each regime
   double         confidence;
   datetime       timestamp;
};

struct OrderFlowAnalysis
{
   string   symbol;
   double   buyVolume;
   double   sellVolume;
   double   imbalance;       // -1.0 to +1.0
   bool     largeOrderDetected;
   int      direction;       // 0=neutral, 1=buy, -1=sell
   double   confidence;
   datetime timestamp;
};

struct PortfolioAction
{
   string   symbols[];
   double   riskPerSymbol[];
   double   confluenceThreshold[];
   bool     allowTrading[];
   double   confidence;
   datetime timestamp;
};

// ==================== API Client Class ====================

class CPythonAPIClient
{
private:
   string      m_apiUrl;            // API base URL
   string      m_apiKey;            // Optional API key
   int         m_timeout;           // Request timeout (ms)
   bool        m_connected;         // Connection status
   datetime    m_lastHealthCheck;

   // Cache for responses (reduce API calls)
   SentimentScore     m_sentimentCache[];
   RegimeDetection    m_regimeCache[];
   OrderFlowAnalysis  m_orderFlowCache[];

public:
   /**
    * Constructor
    */
   CPythonAPIClient() : m_apiUrl("http://localhost:8000"),
                        m_apiKey(""),
                        m_timeout(5000),
                        m_connected(false),
                        m_lastHealthCheck(0)
   {
   }

   /**
    * Initialize API client
    */
   bool Init(string apiUrl = "http://localhost:8000", string apiKey = "")
   {
      m_apiUrl = apiUrl;
      m_apiKey = apiKey;

      // Test connection
      if(!HealthCheck())
      {
         Print("❌ V3 API: Failed to connect to ", m_apiUrl);
         return false;
      }

      m_connected = true;
      Print("✅ V3 API: Connected to ", m_apiUrl);
      return true;
   }

   /**
    * Health check
    */
   bool HealthCheck()
   {
      // Only check every 60 seconds
      if(TimeCurrent() - m_lastHealthCheck < 60)
         return m_connected;

      string url = m_apiUrl + "/health";
      string headers = "Content-Type: application/json\r\n";

      char post[], result[];
      string resultHeaders;

      int res = WebRequest(
         "GET",
         url,
         headers,
         m_timeout,
         post,
         result,
         resultHeaders
      );

      m_lastHealthCheck = TimeCurrent();

      if(res == 200)
      {
         m_connected = true;
         return true;
      }

      Print("⚠️ V3 API: Health check failed (code: ", res, ")");
      m_connected = false;
      return false;
   }

   /**
    * Get sentiment analysis
    */
   bool GetSentiment(string symbol, SentimentScore &score)
   {
      if(!m_connected && !HealthCheck())
         return false;

      // Check cache (5-minute TTL)
      for(int i = 0; i < ArraySize(m_sentimentCache); i++)
      {
         if(m_sentimentCache[i].symbol == symbol &&
            TimeCurrent() - m_sentimentCache[i].timestamp < 300)
         {
            score = m_sentimentCache[i];
            return true;
         }
      }

      // Build request
      string url = m_apiUrl + "/sentiment";
      string requestBody = StringFormat(
         "{\"symbol\":\"%s\",\"source\":\"auto\"}",
         symbol
      );

      string response;
      if(!PostRequest(url, requestBody, response))
         return false;

      // Parse JSON response
      if(!ParseSentimentResponse(response, score))
         return false;

      // Update cache
      int cacheIdx = ArraySize(m_sentimentCache);
      ArrayResize(m_sentimentCache, cacheIdx + 1);
      m_sentimentCache[cacheIdx] = score;

      return true;
   }

   /**
    * Get regime detection
    */
   bool GetRegime(string symbol, RegimeDetection &regime, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
   {
      if(!m_connected && !HealthCheck())
         return false;

      // Check cache (4-hour TTL)
      for(int i = 0; i < ArraySize(m_regimeCache); i++)
      {
         if(m_regimeCache[i].symbol == symbol &&
            TimeCurrent() - m_regimeCache[i].timestamp < 14400)
         {
            regime = m_regimeCache[i];
            return true;
         }
      }

      // Build request
      string url = m_apiUrl + "/regime";
      string tf = EnumToString(timeframe);
      string requestBody = StringFormat(
         "{\"symbol\":\"%s\",\"timeframe\":\"%s\"}",
         symbol, tf
      );

      string response;
      if(!PostRequest(url, requestBody, response))
         return false;

      // Parse JSON response
      if(!ParseRegimeResponse(response, regime))
         return false;

      // Update cache
      int cacheIdx = ArraySize(m_regimeCache);
      ArrayResize(m_regimeCache, cacheIdx + 1);
      m_regimeCache[cacheIdx] = regime;

      return true;
   }

   /**
    * Get order flow analysis
    */
   bool GetOrderFlow(string symbol, OrderFlowAnalysis &orderFlow)
   {
      if(!m_connected && !HealthCheck())
         return false;

      // Check cache (1-minute TTL)
      for(int i = 0; i < ArraySize(m_orderFlowCache); i++)
      {
         if(m_orderFlowCache[i].symbol == symbol &&
            TimeCurrent() - m_orderFlowCache[i].timestamp < 60)
         {
            orderFlow = m_orderFlowCache[i];
            return true;
         }
      }

      // Build request
      string url = m_apiUrl + "/orderflow?symbol=" + symbol;

      string response;
      if(!GetRequest(url, response))
         return false;

      // Parse JSON response
      if(!ParseOrderFlowResponse(response, orderFlow))
         return false;

      // Update cache
      int cacheIdx = ArraySize(m_orderFlowCache);
      ArrayResize(m_orderFlowCache, cacheIdx + 1);
      m_orderFlowCache[cacheIdx] = orderFlow;

      return true;
   }

private:
   /**
    * Generic POST request
    */
   bool PostRequest(string url, string requestBody, string &response)
   {
      char post[], result[];
      StringToCharArray(requestBody, post, 0, StringLen(requestBody));

      string headers = "Content-Type: application/json\r\n";
      if(StringLen(m_apiKey) > 0)
         headers += "Authorization: Bearer " + m_apiKey + "\r\n";

      string resultHeaders;

      int res = WebRequest(
         "POST",
         url,
         headers,
         m_timeout,
         post,
         result,
         resultHeaders
      );

      if(res != 200)
      {
         Print("❌ V3 API: POST failed (code: ", res, ", url: ", url, ")");
         return false;
      }

      response = CharArrayToString(result);
      return true;
   }

   /**
    * Generic GET request
    */
   bool GetRequest(string url, string &response)
   {
      char post[], result[];

      string headers = "Content-Type: application/json\r\n";
      if(StringLen(m_apiKey) > 0)
         headers += "Authorization: Bearer " + m_apiKey + "\r\n";

      string resultHeaders;

      int res = WebRequest(
         "GET",
         url,
         headers,
         m_timeout,
         post,
         result,
         resultHeaders
      );

      if(res != 200)
      {
         Print("❌ V3 API: GET failed (code: ", res, ", url: ", url, ")");
         return false;
      }

      response = CharArrayToString(result);
      return true;
   }

   /**
    * Parse sentiment JSON response
    */
   bool ParseSentimentResponse(string json, SentimentScore &score)
   {
      // Simple JSON parsing (in production, use proper JSON library)
      score.symbol = ExtractJsonString(json, "symbol");
      score.positive = ExtractJsonDouble(json, "positive");
      score.negative = ExtractJsonDouble(json, "negative");
      score.neutral = ExtractJsonDouble(json, "neutral");
      score.composite = ExtractJsonDouble(json, "composite");
      score.confidence = ExtractJsonDouble(json, "confidence");
      score.timestamp = TimeCurrent();

      return true;
   }

   /**
    * Parse regime JSON response
    */
   bool ParseRegimeResponse(string json, RegimeDetection &regime)
   {
      regime.symbol = ExtractJsonString(json, "symbol");
      string regimeStr = ExtractJsonString(json, "regime");
      regime.regime = StringToRegimeEnum(regimeStr);
      regime.confidence = ExtractJsonDouble(json, "confidence");
      regime.timestamp = TimeCurrent();

      // Parse probabilities (simplified)
      for(int i = 0; i < 8; i++)
         regime.probabilities[i] = 0.0;

      return true;
   }

   /**
    * Parse order flow JSON response
    */
   bool ParseOrderFlowResponse(string json, OrderFlowAnalysis &orderFlow)
   {
      orderFlow.symbol = ExtractJsonString(json, "symbol");
      orderFlow.buyVolume = ExtractJsonDouble(json, "buy_volume");
      orderFlow.sellVolume = ExtractJsonDouble(json, "sell_volume");
      orderFlow.imbalance = ExtractJsonDouble(json, "imbalance");
      orderFlow.largeOrderDetected = ExtractJsonBool(json, "large_order_detected");
      orderFlow.direction = (int)ExtractJsonDouble(json, "direction");
      orderFlow.confidence = ExtractJsonDouble(json, "confidence");
      orderFlow.timestamp = TimeCurrent();

      return true;
   }

   /**
    * Helper: Extract string value from JSON
    */
   string ExtractJsonString(string json, string key)
   {
      string search = "\"" + key + "\":\"";
      int start = StringFind(json, search);
      if(start == -1) return "";

      start += StringLen(search);
      int end = StringFind(json, "\"", start);
      if(end == -1) return "";

      return StringSubstr(json, start, end - start);
   }

   /**
    * Helper: Extract double value from JSON
    */
   double ExtractJsonDouble(string json, string key)
   {
      string search = "\"" + key + "\":";
      int start = StringFind(json, search);
      if(start == -1) return 0.0;

      start += StringLen(search);
      int end = StringFind(json, ",", start);
      if(end == -1) end = StringFind(json, "}", start);
      if(end == -1) return 0.0;

      string valueStr = StringSubstr(json, start, end - start);
      StringTrimLeft(valueStr);
      StringTrimRight(valueStr);

      return StringToDouble(valueStr);
   }

   /**
    * Helper: Extract bool value from JSON
    */
   bool ExtractJsonBool(string json, string key)
   {
      string value = ExtractJsonString(json, key);
      return (value == "true" || value == "True");
   }

   /**
    * Helper: Convert string to regime enum
    */
   ENUM_ML_REGIME StringToRegimeEnum(string str)
   {
      if(str == "REGIME_LOW_VOL_BULL") return REGIME_LOW_VOL_BULL;
      if(str == "REGIME_LOW_VOL_BEAR") return REGIME_LOW_VOL_BEAR;
      if(str == "REGIME_HIGH_VOL_BULL") return REGIME_HIGH_VOL_BULL;
      if(str == "REGIME_HIGH_VOL_BEAR") return REGIME_HIGH_VOL_BEAR;
      if(str == "REGIME_SIDEWAYS_TIGHT") return REGIME_SIDEWAYS_TIGHT;
      if(str == "REGIME_SIDEWAYS_WIDE") return REGIME_SIDEWAYS_WIDE;
      if(str == "REGIME_BREAKOUT") return REGIME_BREAKOUT;
      if(str == "REGIME_CRISIS") return REGIME_CRISIS;

      return REGIME_LOW_VOL_BULL;  // Default
   }
};
