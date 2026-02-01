//+------------------------------------------------------------------+
//|                                      Fibonacci_Advanced.mqh       |
//|          Institutional Fibonacci: Clusters, OTE, Extensions       |
//|                                  Copyright 2026, Guido Ambiorix  |
//+------------------------------------------------------------------+
#ifndef FIBONACCI_ADVANCED_MQH
#define FIBONACCI_ADVANCED_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

//+------------------------------------------------------------------+
//| Fibonacci Level                                                   |
//+------------------------------------------------------------------+
struct FibLevel
{
   double price;
   double ratio;     // 0.382, 0.618, etc.
   int    swingIndex; // Which swing this came from
};

//+------------------------------------------------------------------+
//| Fibonacci Cluster                                                 |
//+------------------------------------------------------------------+
struct FibCluster
{
   double priceLevel;
   int    convergenceCount;  // How many Fib levels converge here
   double minPrice;
   double maxPrice;
   bool   isOTE;             // Is this in OTE zone (0.62-0.79)?
};

//+------------------------------------------------------------------+
//| Swing Data                                                        |
//+------------------------------------------------------------------+
struct FibSwing
{
   double high;
   double low;
   int    highBar;
   int    lowBar;
};

//+------------------------------------------------------------------+
//| ADVANCED FIBONACCI ANALYZER                                        |
//+------------------------------------------------------------------+
class CFibonacciAdvanced
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_swingLookback;
   int               m_maxSwings;
   double            m_clusterTolerance;  // ATR multiple for clustering
   
   int               m_hATR;
   double            m_currentATR;
   
   // Standard Fibonacci ratios
   double            m_fibRatios[7];
   
   // Detected swings
   FibSwing          m_swings[];
   int               m_swingCount;
   
   // Detected clusters
   FibCluster        m_clusters[];
   int               m_clusterCount;

public:
   CFibonacciAdvanced() : m_swingLookback(100), m_maxSwings(5),
                          m_clusterTolerance(0.5), m_hATR(INVALID_HANDLE),
                          m_swingCount(0), m_clusterCount(0)
   {
      // Initialize Fibonacci ratios
      m_fibRatios[0] = 0.236;
      m_fibRatios[1] = 0.382;
      m_fibRatios[2] = 0.500;
      m_fibRatios[3] = 0.618;  // Golden ratio
      m_fibRatios[4] = 0.786;
      m_fibRatios[5] = 0.886;  // Deep retracement
      m_fibRatios[6] = 1.000;  // Full retracement
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int swingLookback = 100,
             int maxSwings = 5)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_swingLookback = swingLookback;
      m_maxSwings = maxSwings;
      
      m_hATR = iATR(m_symbol, m_timeframe, 14);
      if(m_hATR == INVALID_HANDLE) return false;
      
      Update();
      
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update - Scan swings and calculate clusters                      |
   //+------------------------------------------------------------------+
   void Update()
   {
      // Update ATR
      double atrBuf[1];
      if(CopyBuffer(m_hATR, 0, 1, 1, atrBuf) != 1) return;
      m_currentATR = atrBuf[0];
      
      // Detect major swings
      DetectSwings();
      
      // Calculate Fibonacci levels for all swings
      CalculateClusters();
   }

   //+------------------------------------------------------------------+
   //| Get Confluence Score                                             |
   //+------------------------------------------------------------------+
   double GetConfluenceScore(int direction)
   {
      double score = 0;
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      
      // Find best cluster near current price
      FibCluster bestCluster;
      bestCluster.priceLevel = 0;
      bestCluster.convergenceCount = 0;
      bestCluster.minPrice = 0;
      bestCluster.maxPrice = 0;
      bestCluster.isOTE = false;
      
      bool found = false;
      int maxConvergence = 0;
      
      for(int i = 0; i < m_clusterCount; i++)
      {
         // Price must be within cluster zone
         if(currentPrice >= m_clusters[i].minPrice && 
            currentPrice <= m_clusters[i].maxPrice)
         {
            if(m_clusters[i].convergenceCount > maxConvergence)
            {
               maxConvergence = m_clusters[i].convergenceCount;
               bestCluster = m_clusters[i];
               found = true;
            }
         }
      }
      
      if(!found) return 0;
      
      // Score based on cluster quality
      if(bestCluster.convergenceCount >= 3 && bestCluster.isOTE)
      {
         score = 3.0;  // ELITE: 3+ levels in OTE zone
      }
      else if(bestCluster.convergenceCount >= 3)
      {
         score = 2.0;  // STRONG: 3+ levels clustered
      }
      else if(bestCluster.isOTE)
      {
         score = 2.0;  // STRONG: Price in OTE zone
      }
      else if(bestCluster.convergenceCount >= 2)
      {
         score = 1.0;  // GOOD: 2 levels aligned
      }
      else
      {
         score = 0.5;  // WEAK: Single Fib level
      }
      
      return score;
   }

   //+------------------------------------------------------------------+
   //| Get Fibonacci Extensions for TP Targets                          |
   //+------------------------------------------------------------------+
   bool GetExtensionTargets(int direction, double &targets[])
   {
      if(m_swingCount == 0) return false;
      
      // Use most recent swing
      FibSwing swing = m_swings[0];
      double range = swing.high - swing.low;
      
      ArrayResize(targets, 5);
      
      if(direction == 1)  // Buy - project from swing low
      {
         targets[0] = swing.high + (range * 0.272);  // 1.272 extension
         targets[1] = swing.high + (range * 0.414);  // 1.414 extension
         targets[2] = swing.high + (range * 0.618);  // 1.618 extension (Golden)
         targets[3] = swing.high + (range * 1.000);  // 2.0 extension
         targets[4] = swing.high + (range * 1.618);  // 2.618 extension
      }
      else  // Sell - project from swing high
      {
         targets[0] = swing.low - (range * 0.272);   // 1.272 extension
         targets[1] = swing.low - (range * 0.414);   // 1.414 extension
         targets[2] = swing.low - (range * 0.618);   // 1.618 extension (Golden)
         targets[3] = swing.low - (range * 1.000);   // 2.0 extension
         targets[4] = swing.low - (range * 1.618);   // 2.618 extension
      }
      
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Best Cluster                                                 |
   //+------------------------------------------------------------------+
   bool GetBestCluster(FibCluster &cluster)
   {
      if(m_clusterCount == 0) return false;
      
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      int bestIdx = -1;
      int maxConvergence = 0;
      double minDistance = 999999;
      
      for(int i = 0; i < m_clusterCount; i++)
      {
         double distance = MathAbs(currentPrice - m_clusters[i].priceLevel);
         
         // Prioritize: convergence count, then proximity
         if(m_clusters[i].convergenceCount > maxConvergence ||
            (m_clusters[i].convergenceCount == maxConvergence && distance < minDistance))
         {
            maxConvergence = m_clusters[i].convergenceCount;
            minDistance = distance;
            bestIdx = i;
         }
      }
      
      if(bestIdx >= 0)
      {
         cluster = m_clusters[bestIdx];
         return true;
      }
      
      return false;
   }

private:
   //+------------------------------------------------------------------+
   //| Detect Major Swings                                              |
   //+------------------------------------------------------------------+
   void DetectSwings()
   {
      ArrayResize(m_swings, 0);
      m_swingCount = 0;
      
      int miniLookback = m_swingLookback / m_maxSwings;
      
      for(int s = 0; s < m_maxSwings; s++)
      {
         int startBar = s * miniLookback + 5;
         int length = miniLookback;
         
         if(startBar + length > m_swingLookback) break;
         
         int highBar = iHighest(m_symbol, m_timeframe, MODE_HIGH, length, startBar);
         int lowBar = iLowest(m_symbol, m_timeframe, MODE_LOW, length, startBar);
         
         if(highBar >= 0 && lowBar >= 0)
         {
            FibSwing swing;
            swing.high = iHigh(m_symbol, m_timeframe, highBar);
            swing.low = iLow(m_symbol, m_timeframe, lowBar);
            swing.highBar = highBar;
            swing.lowBar = lowBar;
            
            // Ensure swing has meaningful range
            if(swing.high - swing.low >= m_currentATR * 1.5)
            {
               ArrayResize(m_swings, m_swingCount + 1);
               m_swings[m_swingCount++] = swing;
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Fibonacci Clusters                                     |
   //+------------------------------------------------------------------+
   void CalculateClusters()
   {
      ArrayResize(m_clusters, 0);
      m_clusterCount = 0;
      
      if(m_swingCount == 0) return;
      
      // Collect all Fib levels from all swings
      FibLevel allLevels[];
      int levelCount = 0;
      
      for(int s = 0; s < m_swingCount; s++)
      {
         double range = m_swings[s].high - m_swings[s].low;
         
         // Calculate retracement levels
         for(int r = 0; r < 7; r++)
         {
            double ratio = m_fibRatios[r];
            double level = m_swings[s].high - (range * ratio);
            
            ArrayResize(allLevels, levelCount + 1);
            allLevels[levelCount].price = level;
            allLevels[levelCount].ratio = ratio;
            allLevels[levelCount].swingIndex = s;
            levelCount++;
         }
      }
      
      // Find clusters (levels within tolerance of each other)
      bool processed[];
      ArrayResize(processed, levelCount);
      ArrayInitialize(processed, false);
      
      double tolerance = m_currentATR * m_clusterTolerance;
      
      for(int i = 0; i < levelCount; i++)
      {
         if(processed[i]) continue;
         
         FibCluster cluster;
         cluster.priceLevel = allLevels[i].price;
         cluster.minPrice = allLevels[i].price - tolerance;
         cluster.maxPrice = allLevels[i].price + tolerance;
         cluster.convergenceCount = 1;
         cluster.isOTE = (allLevels[i].ratio >= 0.62 && allLevels[i].ratio <= 0.79);
         
         double priceSum = allLevels[i].price;
         processed[i] = true;
         
         // Find nearby levels
         for(int j = i + 1; j < levelCount; j++)
         {
            if(processed[j]) continue;
            
            if(MathAbs(allLevels[j].price - allLevels[i].price) <= tolerance)
            {
               cluster.convergenceCount++;
               priceSum += allLevels[j].price;
               processed[j] = true;
               
               // Check if any level is in OTE
               if(allLevels[j].ratio >= 0.62 && allLevels[j].ratio <= 0.79)
                  cluster.isOTE = true;
            }
         }
         
         // Average price of cluster
         cluster.priceLevel = priceSum / cluster.convergenceCount;
         cluster.minPrice = cluster.priceLevel - tolerance;
         cluster.maxPrice = cluster.priceLevel + tolerance;
         
         // Only keep clusters with 2+ convergence
         if(cluster.convergenceCount >= 2)
         {
            ArrayResize(m_clusters, m_clusterCount + 1);
            m_clusters[m_clusterCount++] = cluster;
         }
      }
      
      // Sort clusters by convergence count (best first)
      SortClustersByQuality();
   }

   //+------------------------------------------------------------------+
   //| Sort Clusters by Quality                                         |
   //+------------------------------------------------------------------+
   void SortClustersByQuality()
   {
      for(int i = 0; i < m_clusterCount - 1; i++)
      {
         for(int j = i + 1; j < m_clusterCount; j++)
         {
            int score1 = m_clusters[i].convergenceCount * 10 + (m_clusters[i].isOTE ? 5 : 0);
            int score2 = m_clusters[j].convergenceCount * 10 + (m_clusters[j].isOTE ? 5 : 0);
            
            if(score2 > score1)
            {
               FibCluster temp = m_clusters[i];
               m_clusters[i] = m_clusters[j];
               m_clusters[j] = temp;
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| String Representation                                            |
   //+------------------------------------------------------------------+
   string ToString()
   {
      return "Fib: " + IntegerToString(m_swingCount) + " swings, " +
             IntegerToString(m_clusterCount) + " clusters";
   }
};

#endif
