//+------------------------------------------------------------------+
//|                                              ConfluenceGates.mqh |
//|  Mandatory entry gates per market regime.                        |
//|  These are NON-NEGOTIABLE conditions. If any gate fails the      |
//|  confluence score is set to 0 and no entry is made, regardless  |
//|  of how many enrichment points the setup accumulates.            |
//|                                                                  |
//|  Architecture: two-layer system                                  |
//|    Layer 1 — Gates (this file):  structural quality filter       |
//|    Layer 2 — Enrichment score:   timing + context confirmation   |
//|                                                                  |
//|  Gates by regime:                                                |
//|    TREND_STRONG : EMA200 align + Structure + Displacement        |
//|    TREND_WEAK   : EMA200 align + (CHoCH OR OB OR FVG)           |
//|    RANGING      : RSI at extreme + (OB OR FVG)                   |
//|    VOLATILE     : Displacement + Liquidity Sweep                 |
//|    SQUEEZE      : Compression ≥3 bars + Displacement + (CHoCH/OB)|
//|    CHOPPY       : BLOCKED always                                 |
//|    CRISIS       : BLOCKED always                                 |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_GATES_MQH
#define CONFLUENCE_GATES_MQH

struct GateResult
{
   bool   passed;         // false → score = 0, no entry
   string blockedBy;      // which gate failed (for logging)
   int    gatesPassed;    // how many gates cleared
   int    gatesRequired;  // total gates for this regime
};

//+------------------------------------------------------------------+
//| Check mandatory gates for the current regime.                    |
//| Call this at the START of CalculateConfluenceScore().            |
//| Returns passed=false → return 0 immediately.                     |
//+------------------------------------------------------------------+
GateResult CheckMandatoryGates(
   int           direction,        // 1=Buy, -1=Sell
   MARKET_REGIME regime,
   double        currentPrice,
   double        ema200,           // g_EMA
   double        atr,              // g_ATR
   double        rsi,              // g_RSI
   double        rsiOversold,      // InpRSI_Oversold
   double        rsiOverbought,    // InpRSI_Overbought
   bool          hasDisplacement,  // CheckDisplacement(direction)
   double        obScore,          // smcOrderBlocks.GetConfluenceScore(direction)
   double        fvgScore,         // smcFVG.GetConfluenceScore(direction)
   double        liqScore,         // smcLiquidity.GetConfluenceScore(direction)
   double        chochScore,       // breakerBlocks.GetBreakerScore(direction, atr)
   int           swingHighBar,     // iHighest result (most recent)
   int           swingLowBar,      // iLowest result (most recent)
   bool          isInCompression,  // g_regimeEngine.IsInCompression()
   int           compressionBars   // g_regimeEngine.GetCompressionBars()
)
{
   GateResult r;
   r.passed       = false;
   r.blockedBy    = "";
   r.gatesPassed  = 0;
   r.gatesRequired = 0;

   switch(regime)
   {
      //────────────────────────────────────────────────────────────
      // TREND STRONG: full institutional alignment required
      //────────────────────────────────────────────────────────────
      case REGIME_TREND_STRONG:
      {
         r.gatesRequired = 3;

         // Gate 1: EMA 200 price alignment (price on the right side of the trend)
         bool emaAligned = (direction == 1) ? (currentPrice > ema200)
                                            : (currentPrice < ema200);
         if(!emaAligned)
         {
            r.blockedBy = StringFormat("[GATE] TREND_STRONG: EMA200 misaligned — price=%.5f EMA=%.5f dir=%s",
                                        currentPrice, ema200, (direction==1?"BUY":"SELL"));
            return r;
         }
         r.gatesPassed++;

         // Gate 2: Market structure aligned (most recent swing in direction of trade)
         // Buy: most recent swing is a high (highBar < lowBar = last structure was a high → uptrend)
         // Sell: most recent swing is a low  (lowBar < highBar = last structure was a low → downtrend)
         bool structOK = (direction == 1) ? (swingHighBar < swingLowBar)
                                          : (swingLowBar  < swingHighBar);
         if(!structOK)
         {
            r.blockedBy = StringFormat("[GATE] TREND_STRONG: Structure misaligned — swingH=%d swingL=%d dir=%s",
                                        swingHighBar, swingLowBar, (direction==1?"BUY":"SELL"));
            return r;
         }
         r.gatesPassed++;

         // Gate 3: Institutional displacement confirmed
         if(!hasDisplacement)
         {
            r.blockedBy = "[GATE] TREND_STRONG: No institutional displacement — waiting for impulse bar";
            return r;
         }
         r.gatesPassed++;

         r.passed = true;
         break;
      }

      //────────────────────────────────────────────────────────────
      // TREND WEAK: EMA alignment + at least one SMC signal
      //────────────────────────────────────────────────────────────
      case REGIME_TREND_WEAK:
      {
         r.gatesRequired = 2;

         // Gate 1: EMA 200 price alignment
         bool emaAligned = (direction == 1) ? (currentPrice > ema200)
                                            : (currentPrice < ema200);
         if(!emaAligned)
         {
            r.blockedBy = StringFormat("[GATE] TREND_WEAK: EMA200 misaligned — price=%.5f EMA=%.5f dir=%s",
                                        currentPrice, ema200, (direction==1?"BUY":"SELL"));
            return r;
         }
         r.gatesPassed++;

         // Gate 2: At least one SMC signal present (CHoCH, Order Block, or FVG)
         bool hasSMC = (chochScore > 0.0 || obScore > 0.0 || fvgScore > 0.0);
         if(!hasSMC)
         {
            r.blockedBy = "[GATE] TREND_WEAK: No SMC signal — need CHoCH, OB, or FVG for entry";
            return r;
         }
         r.gatesPassed++;

         r.passed = true;
         break;
      }

      //────────────────────────────────────────────────────────────
      // RANGING: RSI at extreme + price at institutional zone
      //────────────────────────────────────────────────────────────
      case REGIME_RANGING:
      {
         r.gatesRequired = 2;

         // Gate 1: RSI at oversold/overbought extreme
         bool rsiExtreme = (direction == 1) ? (rsi <= rsiOversold)
                                            : (rsi >= rsiOverbought);
         if(!rsiExtreme)
         {
            r.blockedBy = StringFormat("[GATE] RANGING: RSI not at extreme — RSI=%.1f (need %s %.1f)",
                                        rsi,
                                        (direction==1 ? "<=" : ">="),
                                        (direction==1 ? (double)rsiOversold : (double)rsiOverbought));
            return r;
         }
         r.gatesPassed++;

         // Gate 2: Price at institutional zone (Order Block or Fair Value Gap)
         bool atZone = (obScore > 0.0 || fvgScore > 0.0);
         if(!atZone)
         {
            r.blockedBy = "[GATE] RANGING: No OB/FVG — price not at institutional zone (mean reversion needs anchor)";
            return r;
         }
         r.gatesPassed++;

         r.passed = true;
         break;
      }

      //────────────────────────────────────────────────────────────
      // VOLATILE: displacement + liquidity sweep (confirmed spike)
      //────────────────────────────────────────────────────────────
      case REGIME_VOLATILE:
      {
         r.gatesRequired = 2;

         // Gate 1: Displacement (institutional move already happened)
         if(!hasDisplacement)
         {
            r.blockedBy = "[GATE] VOLATILE: No displacement — spike entry requires institutional impulse bar";
            return r;
         }
         r.gatesPassed++;

         // Gate 2: Liquidity sweep confirmed (stops taken before the move)
         if(liqScore <= 0.0)
         {
            r.blockedBy = "[GATE] VOLATILE: No liquidity sweep — spike without stop hunt = low probability";
            return r;
         }
         r.gatesPassed++;

         r.passed = true;
         break;
      }

      //────────────────────────────────────────────────────────────
      // SQUEEZE: compression confirmed + expansion starting + direction
      //────────────────────────────────────────────────────────────
      case REGIME_SQUEEZE:
      {
         r.gatesRequired = 3;

         // Gate 1: Active compression (≥ 3 bars in squeeze)
         if(!isInCompression || compressionBars < 3)
         {
            r.blockedBy = StringFormat("[GATE] SQUEEZE: Compression insufficient — bars=%d (need ≥3)",
                                        compressionBars);
            return r;
         }
         r.gatesPassed++;

         // Gate 2: Displacement starting (expansion bar closed — squeeze breaking)
         if(!hasDisplacement)
         {
            r.blockedBy = "[GATE] SQUEEZE: No expansion bar yet — wait for breakout candle";
            return r;
         }
         r.gatesPassed++;

         // Gate 3: Directional SMC confirmation (CHoCH or OB shows which way)
         bool dirConfirmed = (chochScore > 0.0 || obScore > 0.0);
         if(!dirConfirmed)
         {
            r.blockedBy = "[GATE] SQUEEZE: No CHoCH/OB direction — breakout direction unclear";
            return r;
         }
         r.gatesPassed++;

         r.passed = true;
         break;
      }

      //────────────────────────────────────────────────────────────
      // CHOPPY / CRISIS: always blocked
      //────────────────────────────────────────────────────────────
      case REGIME_CHOPPY:
         r.gatesRequired = -1;
         r.blockedBy = "[GATE] CHOPPY: Random walk detected (ADX<13 + ER<0.20) — no institutional footprint";
         return r;

      case REGIME_CRISIS:
         r.gatesRequired = -1;
         r.blockedBy = "[GATE] CRISIS: Extreme volatility — all entries blocked";
         return r;

      default:
         r.blockedBy = "[GATE] UNKNOWN regime — blocked by default";
         return r;
   }

   return r;
}

#endif
