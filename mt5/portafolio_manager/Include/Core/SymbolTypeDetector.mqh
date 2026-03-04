//+------------------------------------------------------------------+
//|                                          SymbolTypeDetector.mqh |
//|                                 Universal Engine - Phase 1       |
//|                          Auto-detection of symbol type           |
//+------------------------------------------------------------------+
#property copyright "Advanced Fibonacci Pro v7"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Symbol Type Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_SYMBOL_TYPE {
   SYMBOL_TYPE_FOREX,         // Currency pairs (EURUSD, GBPJPY, etc.)
   SYMBOL_TYPE_METALS,        // Precious metals (XAUUSD, XAGUSD, GOLD, SILVER)
   SYMBOL_TYPE_INDICES,       // Stock indices (NAS100, US30, SP500, etc.)
   SYMBOL_TYPE_CRYPTO,        // Cryptocurrencies (BTCUSD, ETHUSD, etc.)
   SYMBOL_TYPE_COMMODITIES,   // Commodities (WTI, BRENT, etc.)
   SYMBOL_TYPE_UNKNOWN        // Unknown or unsupported type
};

//+------------------------------------------------------------------+
//| Symbol Type Detector Class                                       |
//+------------------------------------------------------------------+
class CSymbolTypeDetector {
private:
   string m_symbol;
   ENUM_SYMBOL_TYPE m_type;

   //+------------------------------------------------------------------+
   //| Check if source contains any pattern from array                  |
   //+------------------------------------------------------------------+
   bool ContainsAny(string source, string &patterns[]) {
      for(int i = 0; i < ArraySize(patterns); i++) {
         if(StringFind(source, patterns[i]) >= 0)
            return true;
      }
      return false;
   }

public:
   //+------------------------------------------------------------------+
   //| Initialize detector with symbol                                  |
   //+------------------------------------------------------------------+
   bool Init(string symbol) {
      m_symbol = symbol;
      StringToUpper(m_symbol);
      m_type = DetectType();

      if(m_type == SYMBOL_TYPE_UNKNOWN) {
         Print("WARNING: Symbol type could not be determined for ", symbol);
         Print("WARNING: Defaulting to FOREX type");
         m_type = SYMBOL_TYPE_FOREX;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Detect symbol type based on name patterns                        |
   //+------------------------------------------------------------------+
   ENUM_SYMBOL_TYPE DetectType() {
      // Metals: XAU, XAG, GOLD, SILVER
      string metals[] = {"XAU", "XAG", "GOLD", "SILVER"};
      if(ContainsAny(m_symbol, metals))
         return SYMBOL_TYPE_METALS;

      // Indices: NAS, US30, SP500, USTEC, DAX, FTSE, etc.
      string indices[] = {"NAS", "US30", "US100", "SP500", "SPX", "USTEC",
                          "DAX", "FTSE", "DJ30", "NDX", "CAC", "NIK",
                          "STOXX", "ASX", "HSI"};
      if(ContainsAny(m_symbol, indices))
         return SYMBOL_TYPE_INDICES;

      // Crypto: BTC, ETH, XRP, LTC, etc.
      string crypto[] = {"BTC", "ETH", "XRP", "LTC", "BCH", "ADA",
                        "DOT", "LINK", "BNB", "DOGE", "SHIB"};
      if(ContainsAny(m_symbol, crypto))
         return SYMBOL_TYPE_CRYPTO;

      // Commodities: Oil, Gas, etc.
      string commodities[] = {"WTI", "BRENT", "OIL", "GAS", "NGAS"};
      if(ContainsAny(m_symbol, commodities))
         return SYMBOL_TYPE_COMMODITIES;

      // Forex: Major currencies
      string currencies[] = {"USD", "EUR", "GBP", "JPY", "CHF",
                            "AUD", "NZD", "CAD"};
      if(ContainsAny(m_symbol, currencies))
         return SYMBOL_TYPE_FOREX;

      return SYMBOL_TYPE_UNKNOWN;
   }

   //+------------------------------------------------------------------+
   //| Get detected symbol type                                         |
   //+------------------------------------------------------------------+
   ENUM_SYMBOL_TYPE GetType() const {
      return m_type;
   }

   //+------------------------------------------------------------------+
   //| Type check helpers                                               |
   //+------------------------------------------------------------------+
   bool IsMetals() const {
      return m_type == SYMBOL_TYPE_METALS;
   }

   bool IsForex() const {
      return m_type == SYMBOL_TYPE_FOREX;
   }

   bool IsIndices() const {
      return m_type == SYMBOL_TYPE_INDICES;
   }

   bool IsCrypto() const {
      return m_type == SYMBOL_TYPE_CRYPTO;
   }

   bool IsCommodities() const {
      return m_type == SYMBOL_TYPE_COMMODITIES;
   }

   //+------------------------------------------------------------------+
   //| Get type as string for logging                                   |
   //+------------------------------------------------------------------+
   string GetTypeString() const {
      switch(m_type) {
         case SYMBOL_TYPE_FOREX:       return "FOREX";
         case SYMBOL_TYPE_METALS:      return "METALS";
         case SYMBOL_TYPE_INDICES:     return "INDICES";
         case SYMBOL_TYPE_CRYPTO:      return "CRYPTO";
         case SYMBOL_TYPE_COMMODITIES: return "COMMODITIES";
         case SYMBOL_TYPE_UNKNOWN:     return "UNKNOWN";
         default:                      return "INVALID";
      }
   }
};
//+------------------------------------------------------------------+
