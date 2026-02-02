# Portfolio Governor v7.1 - Quick Reference Guide

**H1 Enhanced System - Module Reference**

---

## 📋 TABLE OF CONTENTS

1. [Core Parameters](#core-parameters)
2. [Confluence Scoring](#confluence-scoring)
3. [Module Usage](#module-usage)
4. [Dashboard Interpretation](#dashboard-interpretation)
5. [Common Operations](#common-operations)
6. [Troubleshooting](#troubleshooting)

---

## 🎯 CORE PARAMETERS (H1 Optimized)

### SMC Parameters (SMCConfig.mqh)
```cpp
CFG_SMC_SWING_LOOKBACK = 45;      // Swing detection
CFG_SMC_OB_LOOKBACK = 90;         // Order block validity
CFG_SMC_MIN_IMPULSE_ATR = 2.5;    // Minimum impulse size
CFG_SMC_MIN_FVG_ATR = 0.8;        // Minimum FVG size
CFG_SMC_LIQ_LOOKBACK = 35;        // Liquidity sweep detection
```

### Exit Parameters (ExitStrategyConfig.mqh)
```cpp
CFG_TRAIL_START_R = 2.5;          // Start trailing at 2.5R
CFG_TRAIL_ATR_MULT = 1.5;         // Trail distance
CFG_PARTIAL_TP_R = 2.0;           // Partial TP at 2R
CFG_BE_THRESHOLD_R = 2.2;         // Break-even at 2.2R
```

### Stop Loss & Take Profit (Signal_SMC_Pro.mqh)
```cpp
SL ATR Multiple: 2.2              // 2.2 × ATR
TP R-Multiple: 3.5                // 3.5R target
```

---

## 📊 CONFLUENCE SCORING (22 Points Max)

### Score Breakdown
| Component | Points | Description |
|-----------|--------|-------------|
| **Core SMC** | 5.0 | Structure (1.0) + OB (1.5) + FVG (1.0) + Liq (1.5) |
| **Advanced ICT** | 5.5 | Breakers (2.0) + Macros (1.5) + Power of 3 (2.0) |
| **Volume** | 2.5 | POC (1.0) + VA (0.5) + VWAP (0.5) + VolBreak (0.5) |
| **MTF** | 2.0 | D1/H4/H1 alignment |
| **Currency** | 1.5 | Pair strength differential |
| **Fibonacci** | 1.5 | Clusters, OTE zones |
| **Regime** | 1.0 | ML confidence |

### Entry Thresholds
- **Elite:** ≥12 pts (54%) → 100% size, 2.0 ATR SL
- **Strong:** ≥9 pts (41%) → 80% size, 2.3 ATR SL
- **Good:** ≥7 pts (32%) → 60% size, 2.5 ATR SL
- **Weak:** <7 pts → Skip trade

---

## 🔧 MODULE USAGE

### VolumeAnalysis.mqh
```cpp
CVolumeAnalysis volume;
volume.Init(symbol, PERIOD_H1, 100, 100);

// Get confluence score
double volScore = volume.GetConfluenceScore(direction); // 0-2.5

// Get individual components
double poc = volume.GetPOC();
double vah = volume.GetVAH();
double val = volume.GetVAL();
double vwap = volume.GetVWAP();
bool breakout = volume.IsVolumeBreakout();
```

**Interpretation:**
- POC near price (+1.0): High-volume support/resistance
- VAL/VAH near price (+0.5): Value area edges
- VWAP reversion (+0.5): Mean reversion setup
- Volume breakout (+0.5): Momentum confirmation

---

### CurrencyStrength.mqh
```cpp
CCurrencyStrength cs;
cs.Init(PERIOD_H1, 24);

// Get pair strength
double pairStrength = cs.GetPairStrength(symbol);
double score = cs.GetConfluenceScore(symbol, direction);

// Get strongest/weakest
string strongest = cs.GetStrongestCurrency();
string weakest = cs.GetWeakestCurrency();
```

**Interpretation:**
- Pair strength >50: Very strong alignment (+1.5)
- Pair strength 30-50: Moderate alignment (+1.0)
- Pair strength 15-30: Weak alignment (+0.5)
- Pair strength <15: No alignment (0)

**Best Pairs:** Strongest vs Weakest currencies

---

### CorrelationMatrix.mqh
```cpp
CCorrelationMatrix corr;
corr.Init(PERIOD_H1, 50, 0.7);

// Check correlation before trade
string existingSymbols[] = {"EURUSD", "GBPUSD"};
bool safe = !corr.ShouldBlockTrade("AUDUSD", existingSymbols);

// Get adjusted size
double adjustedSize = corr.GetCorrelationAdjustedSize("AUDUSD",
                                                       existingSymbols,
                                                       1.0);
```

**Interpretation:**
- Correlation >0.7: BLOCK trade
- Correlation 0.5-0.7: 75% size
- Correlation <0.5: Full size

---

### SMC_BreakerBlocks.mqh
```cpp
CBreakerBlocks breakers;
breakers.Init(symbol, PERIOD_H1, 50, 2.5);

// Get breaker score
double breakerScore = breakers.GetBreakerScore(direction);

// Check if price at breaker
double breakerHigh, breakerLow;
bool atBreaker = breakers.IsPriceAtBreaker(direction,
                                           breakerHigh,
                                           breakerLow);
```

**Interpretation:**
- Active breaker at price: +2.0 points (strong)
- No breaker: 0 points

---

### ICT_MacroWindows.mqh
```cpp
CICTMacroWindows macros;
macros.Init(symbol, true); // true = use DST

// Get current window
ENUM_MACRO_WINDOW window = macros.GetCurrentMacroWindow();
double score = macros.GetMacroScore();
bool isSilverBullet = macros.IsInSilverBullet();
```

**Windows (EST):**
- **Silver Bullet (13:30-16:00):** +1.5 pts ⭐ BEST
- **NY AM (08:00-11:00):** +1.0 pt
- **London (02:00-05:00):** +0.8 pt
- **Outside windows:** 0 pts

---

### ICT_PowerOf3.mqh
```cpp
CICTPowerOf3 po3;
po3.Init(symbol, PERIOD_H1, 30);

// Get phase
ENUM_PO3_PHASE phase = po3.DetectPhase();
double score = po3.GetPhaseScore();
bool shouldTrade = po3.ShouldTrade();
```

**Phases:**
- **Distribution (Expansion):** +2.0 pts → TRADE ✅
- **Manipulation (False move):** -1.0 pt → AVOID ❌
- **Accumulation/Unknown:** 0 pts → NEUTRAL

---

### DivergenceDetector.mqh
```cpp
CDivergenceDetector div;
div.Init(symbol, PERIOD_H1, 50);

// Get divergence score
double divScore = div.GetDivergenceScore(direction);

// Get specific divergences
ENUM_DIVERGENCE_TYPE rsiDiv = div.DetectRSIDivergence();
ENUM_DIVERGENCE_TYPE macdDiv = div.DetectMACDDivergence();
```

**Types:**
- **Regular (Reversal):** +1.5 pts
- **Hidden (Continuation):** +1.0 pt
- **None:** 0 pts

---

### WyckoffAnalysis.mqh
```cpp
CWyckoffAnalysis wyckoff;
wyckoff.Init(symbol, PERIOD_H1, 50);

// Get phase
ENUM_WYCKOFF_PHASE phase = wyckoff.DetectPhase();
double score = wyckoff.GetWyckoffScore(direction);

// Check for breakouts
bool breakout = wyckoff.IsBreakoutFromAccumulation();
bool breakdown = wyckoff.IsBreakdownFromDistribution();
```

**Phases:**
- **Accumulation → Breakout:** +1.5 pts (bullish)
- **Distribution → Breakdown:** +1.5 pts (bearish)
- **Markup/Markdown continuation:** +1.0 pt
- **Other:** 0 pts

---

### MLRegimeDetector.mqh (k-Means)
```cpp
CMLRegimeDetector ml;
ml.Init();

// Train on historical data (once)
ml.TrainOnHistoricalData(symbol, PERIOD_H1);

// Detect regime
RegimePrediction pred = ml.DetectRegime(symbol);
MARKET_REGIME regime = pred.regime;
double confidence = pred.confidence;
```

**Regimes:**
- **MR_TRENDING_HIGH_VOL:** High ADX + High ATR
- **MR_TRENDING_LOW_VOL:** High ADX + Low ATR
- **MR_RANGING_HIGH_VOL:** Low ADX + High ATR (choppy)
- **MR_RANGING_LOW_VOL:** Low ADX + Low ATR

---

### AdvancedExitLogic.mqh
```cpp
CAdvancedExitLogic exitLogic;
exitLogic.Init(symbol, PERIOD_H1);

// Evaluate exit
ExitDecision decision = exitLogic.EvaluateExit(ticket,
                                               positionDirection,
                                               entryPrice,
                                               entryTime);

if(decision.shouldExit) {
    Print("Exit: ", decision.description);
    // Close position
}
```

**Exit Reasons:**
1. Take Profit (target hit)
2. Stop Loss (SL hit)
3. Trailing Stop
4. **Opposing Signal** (strong opposite candle)
5. **HTF Reversal** (D1/H4 structure break)
6. **Session End** (Friday close)
7. **News Approaching** (NFP/FOMC)
8. **Time Limit** (72 bars max on H1)

---

## 📈 DASHBOARD INTERPRETATION

### Volume Section
```
=== VOLUME ANALYSIS ===
POC: 1.09450
VAH: 1.09520
VAL: 1.09380
VWAP: 1.09485
Volume Breakout: YES
Score: +2.5/2.5
```
**Interpretation:** Strong volume confluence, price at POC with breakout

---

### Currency Strength Section
```
=== CURRENCY STRENGTH ===
EURUSD Pair Strength: +45.3
EUR Strength: +32.1
USD Strength: -13.2
Score: +1.0/1.5
```
**Interpretation:** EUR stronger than USD, moderate bullish alignment

---

### Correlation Section
```
=== CORRELATION MATRIX ===
EURUSD vs GBPUSD: 0.85 [HIGH]
EURUSD vs AUDUSD: 0.62 [OK]
Portfolio Concentration: 0.73%
```
**Interpretation:** High correlation with GBPUSD, would block new GBPUSD trade

---

### Macro Windows Section
```
=== ICT MACRO WINDOWS ===
ACTIVE: Silver Bullet (13:30-16:00 EST)
Score: +1.5 points
```
**Interpretation:** Prime trading window, highest probability

---

### Power of 3 Section
```
=== POWER OF 3 ===
Phase: Distribution (Expansion) - TRADE
Direction: BULLISH
Score: +2.0 points
```
**Interpretation:** Expansion phase detected, safe to trade

---

### Ensemble Section
```
=== ENSEMBLE VOTING ===
Bullish Votes: 4
Bearish Votes: 0
Neutral Votes: 1
Weighted Confidence: 82.5%
Agreement: Strong Agreement
Final Signal: BUY
```
**Interpretation:** Strong consensus across all models

---

## 🛠️ COMMON OPERATIONS

### Check Overall Confluence
```cpp
// In Signal_SMC_Pro::GetSignal()
double buyScore = CalculateScore(symbol, 1);
double sellScore = CalculateScore(symbol, -1);

if(buyScore >= 9.0) return 1;  // Strong buy
if(sellScore >= 9.0) return -1; // Strong sell
return 0; // No trade
```

### Get Detailed Breakdown
```cpp
string breakdown = signal.GetScoreBreakdown(symbol, direction);
Print(breakdown);
```

### Check Correlation Safety
```cpp
string existingSymbols[];
// ... populate with current positions ...

bool safe = signal.CheckCorrelationSafety(newSymbol, existingSymbols);
if(!safe) {
    Print("Trade blocked: High correlation");
    return;
}
```

### Adjust Position Size
```cpp
double baseSize = 1.0;
double adjustedSize = signal.GetCorrelationAdjustedSize(newSymbol,
                                                        existingSymbols,
                                                        baseSize);
Print("Position size adjusted to: ", adjustedSize);
```

---

## 🔍 TROUBLESHOOTING

### Low Confluence Scores
**Problem:** Scores consistently below threshold (9.0)
**Solutions:**
1. Check if in Silver Bullet window (+1.5 pts)
2. Verify Power of 3 is in Distribution (+2.0 pts)
3. Ensure MTF alignment (D1/H4/H1) (+2.0 pts)
4. Check Volume Profile POC confluence (+1.0 pt)
5. Verify currency strength alignment (+1.5 pts)

### High Correlation Blocking Trades
**Problem:** Too many trades blocked by correlation
**Solutions:**
1. Increase correlation threshold to 0.75 or 0.8
2. Expand symbol universe (more diverse pairs)
3. Use correlation-adjusted sizing instead of blocking
4. Review existing positions for closure

### No Breaker Blocks Detected
**Problem:** Breaker score always 0
**Solutions:**
1. Increase lookback period (50 → 80)
2. Reduce minimum impulse ATR (2.5 → 2.0)
3. Check if enough order blocks forming
4. Verify price action has failed OBs

### Power of 3 Always "Unknown"
**Problem:** Phase detection not working
**Solutions:**
1. Increase lookback period (30 → 50)
2. Check ATR calculation (may be too small)
3. Verify volume data availability
4. Reduce range/volume thresholds

### Divergence Not Detected
**Problem:** Divergence score always 0
**Solutions:**
1. Increase lookback period (50 → 80)
2. Reduce swing detection sensitivity
3. Check RSI/MACD indicators loading
4. Verify price swing points are identified

---

## 📞 SUPPORT REFERENCE

### Critical Files
- Main Signal: `Include/Signals/Signal_SMC_Pro.mqh`
- SMC Config: `Include/Config/SMCConfig.mqh`
- Exit Config: `Include/Config/ExitStrategyConfig.mqh`

### Key Constants
```cpp
// Thresholds
ELITE_THRESHOLD = 12.0    // 54% of max
STRONG_THRESHOLD = 9.0    // 41% of max
GOOD_THRESHOLD = 7.0      // 32% of max

// Correlation
CORRELATION_THRESHOLD = 0.7

// H1 Parameters
MAX_HOLD_BARS_H1 = 72     // 3 days
SL_ATR_MULT_H1 = 2.2
TP_R_MULT_H1 = 3.5
```

### Debug Mode
Enable detailed logging:
```cpp
#define DEBUG_MODE true

if(DEBUG_MODE) {
    Print("Score breakdown: ", breakdown);
    Print("Volume score: ", volScore);
    Print("Currency score: ", csScore);
    Print("Breaker score: ", breakerScore);
    // ... etc
}
```

---

## 📚 RELATED DOCUMENTS

- `COMPLETE_IMPLEMENTATION_SUMMARY.md` - Full technical documentation
- `PHASE_1_2_IMPLEMENTATION_SUMMARY.md` - Phase 1-2 details
- `README.md` - Project overview

---

**Version:** v7.1-H1-Complete
**Last Updated:** 2026-02-01
**Author:** Claude Sonnet 4.5 + Guido Ambiorix
