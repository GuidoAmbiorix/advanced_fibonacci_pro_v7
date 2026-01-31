//+------------------------------------------------------------------+
//|                                             PatternMemory.mqh    |
//|                    Confluence Pattern Performance Database        |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#ifndef PATTERN_MEMORY_MQH
#define PATTERN_MEMORY_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include "../KillzoneConfig.mqh"
#include "../MarketRegime.mqh"

//+------------------------------------------------------------------+
//| PATTERN STATISTICS STRUCTURE                                      |
//+------------------------------------------------------------------+
struct PatternStats
{
   string   signature;           // Pattern signature (e.g., "TREND+FIB+OB")
   int      tradeCount;
   int      wins;
   int      losses;
   double   winRate;
   double   avgRWin;
   double   avgRLoss;
   double   avgR;
   double   expectancy;
   double   profitFactor;

   // Context where pattern works best
   ENUM_KILLZONE bestKillzone;
   MARKET_REGIME bestRegime;
   double   bestKillzoneWR;      // Win rate in best killzone

   datetime lastUpdated;

   // Initialize
   PatternStats() : signature(""), tradeCount(0), wins(0), losses(0),
                    winRate(0), avgRWin(0), avgRLoss(0), avgR(0),
                    expectancy(0), profitFactor(0),
                    bestKillzone(KILLZONE_NONE), bestRegime(REGIME_UNKNOWN),
                    bestKillzoneWR(0), lastUpdated(0) {}
};

//+------------------------------------------------------------------+
//| CONFLUENCE FACTORS STRUCTURE                                      |
//+------------------------------------------------------------------+
struct ConfluenceFactors
{
   bool     trendAligned;        // EMA trend filter
   bool     structureBreak;      // SMC structure break
   bool     fibZone;             // In Fibonacci zone
   bool     rsiMomentum;         // RSI confirmation
   bool     orderBlock;          // Near order block
   bool     fvg;                 // Fair value gap present
   bool     liquiditySweep;      // Liquidity swept
   bool     killzoneActive;      // In active killzone
   bool     mtfAligned;          // MTF alignment

   // Context
   ENUM_KILLZONE killzone;
   MARKET_REGIME regime;
   double   confluenceScore;

   // Initialize
   ConfluenceFactors() : trendAligned(false), structureBreak(false),
                         fibZone(false), rsiMomentum(false), orderBlock(false),
                         fvg(false), liquiditySweep(false), killzoneActive(false),
                         mtfAligned(false), killzone(KILLZONE_NONE),
                         regime(REGIME_UNKNOWN), confluenceScore(0) {}
};

//+------------------------------------------------------------------+
//| PATTERN MEMORY CLASS                                              |
//| Responsibility: Track which confluence patterns work best        |
//+------------------------------------------------------------------+
class CPatternMemory
{
private:
   string         m_symbol;
   string         m_dataFile;
   PatternStats   m_patterns[];
   int            m_patternCount;
   int            m_maxPatterns;         // Max patterns to store
   int            m_minSampleSize;       // Min trades to consider pattern
   bool           m_persistenceEnabled;
   datetime       m_lastSave;

public:
   CPatternMemory() : m_symbol(""), m_patternCount(0), m_maxPatterns(100),
                      m_minSampleSize(10), m_persistenceEnabled(false),
                      m_lastSave(0) {}

   //+------------------------------------------------------------------+
   //| Initialize Pattern Memory                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, bool enablePersistence = true, int minSampleSize = 10)
   {
      m_symbol = symbol;
      m_persistenceEnabled = enablePersistence;
      m_minSampleSize = minSampleSize;

      if(m_persistenceEnabled)
      {
         m_dataFile = "SymbolEngine_Patterns_" + m_symbol + ".dat";

         // Try to load existing patterns
         if(!LoadFromFile())
         {
            Print("PatternMemory: Starting fresh (no saved patterns)");
         }
         else
         {
            Print("PatternMemory: Loaded ", m_patternCount, " patterns");
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Deinitialize - save data on exit                                 |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      if(m_persistenceEnabled)
         SaveToFile();
   }

   //+------------------------------------------------------------------+
   //| Record Pattern Outcome                                           |
   //+------------------------------------------------------------------+
   void RecordPattern(ConfluenceFactors &factors, double profitR)
   {
      // Generate pattern signature
      string signature = GenerateSignature(factors);

      // Find or create pattern
      int idx = FindPatternIndex(signature);

      if(idx < 0)
      {
         // Create new pattern
         idx = m_patternCount;

         // Check if we need to make space
         if(m_patternCount >= m_maxPatterns)
         {
            // Remove weakest pattern
            RemoveWeakestPattern();
            idx = m_patternCount;
         }

         ArrayResize(m_patterns, m_patternCount + 1);
         m_patterns[idx].signature = signature;
         m_patternCount++;
      }

      // Update statistics
      m_patterns[idx].tradeCount++;

      if(profitR > 0)
      {
         m_patterns[idx].wins++;
         m_patterns[idx].avgRWin += profitR;
      }
      else
      {
         m_patterns[idx].losses++;
         m_patterns[idx].avgRLoss += MathAbs(profitR);
      }

      m_patterns[idx].avgR += profitR;
      m_patterns[idx].lastUpdated = TimeCurrent();

      // Finalize calculations
      FinalizePatternStats(m_patterns[idx]);

      // Track best killzone/regime for this pattern
      UpdateBestContext(idx, factors.killzone, factors.regime, profitR);

      // Auto-save periodically (every 10 new patterns)
      if((TimeCurrent() - m_lastSave) > 600)  // Every 10 minutes
      {
         SaveToFile();
         m_lastSave = TimeCurrent();
      }
   }

   //+------------------------------------------------------------------+
   //| Get Pattern Statistics                                           |
   //+------------------------------------------------------------------+
   bool GetPatternStats(string signature, PatternStats &stats)
   {
      int idx = FindPatternIndex(signature);

      if(idx < 0) return false;

      stats = m_patterns[idx];
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Pattern Stats by Factors                                     |
   //+------------------------------------------------------------------+
   bool GetStatsByFactors(ConfluenceFactors &factors, PatternStats &stats)
   {
      string signature = GenerateSignature(factors);
      return GetPatternStats(signature, stats);
   }

   //+------------------------------------------------------------------+
   //| Get Top Patterns (by expectancy)                                 |
   //+------------------------------------------------------------------+
   int GetTopPatterns(PatternStats &output[], int limit = 10)
   {
      // Copy patterns with sufficient sample size
      PatternStats validPatterns[];
      int validCount = 0;

      for(int i = 0; i < m_patternCount; i++)
      {
         if(m_patterns[i].tradeCount >= m_minSampleSize)
         {
            ArrayResize(validPatterns, validCount + 1);
            validPatterns[validCount] = m_patterns[i];
            validCount++;
         }
      }

      if(validCount == 0) return 0;

      // Sort by expectancy (descending)
      for(int i = 0; i < validCount - 1; i++)
      {
         for(int j = i + 1; j < validCount; j++)
         {
            if(validPatterns[j].expectancy > validPatterns[i].expectancy)
            {
               PatternStats temp = validPatterns[i];
               validPatterns[i] = validPatterns[j];
               validPatterns[j] = temp;
            }
         }
      }

      // Return top N
      int returnCount = MathMin(limit, validCount);
      ArrayResize(output, returnCount);

      for(int i = 0; i < returnCount; i++)
         output[i] = validPatterns[i];

      return returnCount;
   }

   //+------------------------------------------------------------------+
   //| Get Pattern Expectancy                                           |
   //+------------------------------------------------------------------+
   double GetPatternExpectancy(ConfluenceFactors &factors)
   {
      string signature = GenerateSignature(factors);
      int idx = FindPatternIndex(signature);

      if(idx < 0) return 0;
      if(m_patterns[idx].tradeCount < m_minSampleSize) return 0;

      return m_patterns[idx].expectancy;
   }

   //+------------------------------------------------------------------+
   //| Check if pattern is high probability                             |
   //+------------------------------------------------------------------+
   bool IsHighProbabilityPattern(ConfluenceFactors &factors, double minWR = 0.65, double minExpectancy = 0.5)
   {
      string signature = GenerateSignature(factors);
      int idx = FindPatternIndex(signature);

      if(idx < 0) return false;
      if(m_patterns[idx].tradeCount < m_minSampleSize) return false;

      return (m_patterns[idx].winRate >= minWR &&
              m_patterns[idx].expectancy >= minExpectancy);
   }

   //+------------------------------------------------------------------+
   //| Get Pattern Count                                                |
   //+------------------------------------------------------------------+
   int GetPatternCount() { return m_patternCount; }

   //+------------------------------------------------------------------+
   //| Get Total Trades Tracked                                         |
   //+------------------------------------------------------------------+
   int GetTotalTrades()
   {
      int total = 0;
      for(int i = 0; i < m_patternCount; i++)
         total += m_patterns[i].tradeCount;
      return total;
   }

private:
   //+------------------------------------------------------------------+
   //| Generate Pattern Signature                                       |
   //+------------------------------------------------------------------+
   string GenerateSignature(ConfluenceFactors &factors)
   {
      string sig = "";

      if(factors.trendAligned) sig += "TREND+";
      if(factors.structureBreak) sig += "STRUCT+";
      if(factors.fibZone) sig += "FIB+";
      if(factors.rsiMomentum) sig += "RSI+";
      if(factors.orderBlock) sig += "OB+";
      if(factors.fvg) sig += "FVG+";
      if(factors.liquiditySweep) sig += "LIQ+";
      if(factors.killzoneActive) sig += "KZ+";
      if(factors.mtfAligned) sig += "MTF+";

      // Remove trailing '+'
      if(StringLen(sig) > 0)
         sig = StringSubstr(sig, 0, StringLen(sig) - 1);

      return sig;
   }

   //+------------------------------------------------------------------+
   //| Find Pattern Index                                               |
   //+------------------------------------------------------------------+
   int FindPatternIndex(string signature)
   {
      for(int i = 0; i < m_patternCount; i++)
      {
         if(m_patterns[i].signature == signature)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Finalize Pattern Statistics                                      |
   //+------------------------------------------------------------------+
   void FinalizePatternStats(PatternStats &pattern)
   {
      if(pattern.tradeCount == 0) return;

      // Calculate averages
      pattern.winRate = (double)pattern.wins / pattern.tradeCount;
      pattern.avgR = pattern.avgR / pattern.tradeCount;

      if(pattern.wins > 0)
         pattern.avgRWin = pattern.avgRWin / pattern.wins;

      if(pattern.losses > 0)
         pattern.avgRLoss = pattern.avgRLoss / pattern.losses;

      // Calculate expectancy
      double lossRate = 1.0 - pattern.winRate;
      pattern.expectancy = (pattern.winRate * pattern.avgRWin) -
                          (lossRate * pattern.avgRLoss);

      // Calculate profit factor
      double grossProfit = pattern.wins * pattern.avgRWin;
      double grossLoss = pattern.losses * pattern.avgRLoss;

      if(grossLoss > 0)
         pattern.profitFactor = grossProfit / grossLoss;
      else
         pattern.profitFactor = (grossProfit > 0) ? 999 : 0;
   }

   //+------------------------------------------------------------------+
   //| Update Best Context for Pattern                                  |
   //+------------------------------------------------------------------+
   void UpdateBestContext(int idx, ENUM_KILLZONE killzone, MARKET_REGIME mktRegime, double profitR)
   {
      // Simple tracking: just note the context, real analysis in PerformanceAnalyzer
      // This is a placeholder for future enhancement
      if(m_patterns[idx].bestKillzone == KILLZONE_NONE)
         m_patterns[idx].bestKillzone = killzone;

      if(m_patterns[idx].bestRegime == REGIME_UNKNOWN)
         m_patterns[idx].bestRegime = mktRegime;
   }

   //+------------------------------------------------------------------+
   //| Remove Weakest Pattern                                           |
   //+------------------------------------------------------------------+
   void RemoveWeakestPattern()
   {
      if(m_patternCount == 0) return;

      // Find pattern with worst expectancy and fewest trades
      int worstIdx = 0;
      double worstScore = m_patterns[0].expectancy + (m_patterns[0].tradeCount * 0.01);

      for(int i = 1; i < m_patternCount; i++)
      {
         double score = m_patterns[i].expectancy + (m_patterns[i].tradeCount * 0.01);
         if(score < worstScore)
         {
            worstScore = score;
            worstIdx = i;
         }
      }

      // Remove pattern
      for(int i = worstIdx; i < m_patternCount - 1; i++)
         m_patterns[i] = m_patterns[i + 1];

      ArrayResize(m_patterns, m_patternCount - 1);
      m_patternCount--;
   }

   //+------------------------------------------------------------------+
   //| Save patterns to file                                            |
   //+------------------------------------------------------------------+
   bool SaveToFile()
   {
      if(!m_persistenceEnabled) return false;

      int fileHandle = FileOpen(m_dataFile, FILE_WRITE|FILE_BIN|FILE_COMMON);

      if(fileHandle == INVALID_HANDLE)
      {
         Print("PatternMemory ERROR: Cannot save to file");
         return false;
      }

      // Write version
      int version = 1;
      FileWriteInteger(fileHandle, version);

      // Write symbol
      FileWriteString(fileHandle, m_symbol);

      // Write pattern count
      FileWriteInteger(fileHandle, m_patternCount);

      // Write each pattern
      for(int i = 0; i < m_patternCount; i++)
      {
         FileWriteString(fileHandle, m_patterns[i].signature);
         FileWriteInteger(fileHandle, m_patterns[i].tradeCount);
         FileWriteInteger(fileHandle, m_patterns[i].wins);
         FileWriteInteger(fileHandle, m_patterns[i].losses);
         FileWriteDouble(fileHandle, m_patterns[i].winRate);
         FileWriteDouble(fileHandle, m_patterns[i].avgRWin);
         FileWriteDouble(fileHandle, m_patterns[i].avgRLoss);
         FileWriteDouble(fileHandle, m_patterns[i].avgR);
         FileWriteDouble(fileHandle, m_patterns[i].expectancy);
         FileWriteDouble(fileHandle, m_patterns[i].profitFactor);
         FileWriteInteger(fileHandle, (int)m_patterns[i].bestKillzone);
         FileWriteInteger(fileHandle, (int)m_patterns[i].bestRegime);
         FileWriteDouble(fileHandle, m_patterns[i].bestKillzoneWR);
         FileWriteLong(fileHandle, m_patterns[i].lastUpdated);
      }

      // Write timestamp
      FileWriteLong(fileHandle, TimeCurrent());

      FileClose(fileHandle);

      Print("PatternMemory: Saved ", m_patternCount, " patterns to file");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Load patterns from file                                          |
   //+------------------------------------------------------------------+
   bool LoadFromFile()
   {
      if(!m_persistenceEnabled) return false;
      if(!FileIsExist(m_dataFile, FILE_COMMON)) return false;

      int fileHandle = FileOpen(m_dataFile, FILE_READ|FILE_BIN|FILE_COMMON);

      if(fileHandle == INVALID_HANDLE)
      {
         Print("PatternMemory WARNING: Cannot load from file");
         return false;
      }

      // Read version
      int version = FileReadInteger(fileHandle);

      if(version != 1)
      {
         Print("PatternMemory WARNING: Unsupported or corrupted file version: ", version);
         Print("PatternMemory: Deleting corrupted file and resetting data...");
         FileClose(fileHandle);

         // Delete corrupted file
         string filename = "PatternMemory_" + m_symbol + ".dat";
         if(FileDelete(filename, FILE_COMMON))
         {
            Print("PatternMemory: Corrupted file deleted successfully");
         }

         // Reset
         m_patternCount = 0;
         ArrayResize(m_patterns, 0);

         return false;
      }

      // Read symbol (verify it matches)
      string savedSymbol = FileReadString(fileHandle);
      if(savedSymbol != m_symbol)
      {
         Print("PatternMemory WARNING: Symbol mismatch or corrupted file (saved:", savedSymbol, " current:", m_symbol, ")");
         Print("PatternMemory: Deleting corrupted file and resetting data...");
         FileClose(fileHandle);

         // Delete corrupted file
         string filename = "PatternMemory_" + m_symbol + ".dat";
         if(FileDelete(filename, FILE_COMMON))
         {
            Print("PatternMemory: Corrupted file deleted successfully");
         }

         // Reset
         m_patternCount = 0;
         ArrayResize(m_patterns, 0);

         return false;
      }

      // Read pattern count
      m_patternCount = FileReadInteger(fileHandle);

      if(m_patternCount > 0)
      {
         ArrayResize(m_patterns, m_patternCount);

         // Read each pattern
         for(int i = 0; i < m_patternCount; i++)
         {
            m_patterns[i].signature = FileReadString(fileHandle);
            m_patterns[i].tradeCount = FileReadInteger(fileHandle);
            m_patterns[i].wins = FileReadInteger(fileHandle);
            m_patterns[i].losses = FileReadInteger(fileHandle);
            m_patterns[i].winRate = FileReadDouble(fileHandle);
            m_patterns[i].avgRWin = FileReadDouble(fileHandle);
            m_patterns[i].avgRLoss = FileReadDouble(fileHandle);
            m_patterns[i].avgR = FileReadDouble(fileHandle);
            m_patterns[i].expectancy = FileReadDouble(fileHandle);
            m_patterns[i].profitFactor = FileReadDouble(fileHandle);
            m_patterns[i].bestKillzone = (ENUM_KILLZONE)FileReadInteger(fileHandle);
            m_patterns[i].bestRegime = (MARKET_REGIME)FileReadInteger(fileHandle);
            m_patterns[i].bestKillzoneWR = FileReadDouble(fileHandle);
            m_patterns[i].lastUpdated = (datetime)FileReadLong(fileHandle);
         }
      }

      // Read timestamp (for info)
      datetime savedTime = (datetime)FileReadLong(fileHandle);

      FileClose(fileHandle);

      Print("PatternMemory: Loaded data from ", TimeToString(savedTime, TIME_DATE));
      return true;
   }
};

#endif
