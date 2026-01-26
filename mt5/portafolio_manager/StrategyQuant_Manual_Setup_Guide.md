# StrategyQuant X - Manual Configuration Guide
## EURUSD Scalping with Fibonacci, Elliott Waves, RSI, MACD

**Target:** Generate 10,000 scalping strategies for EURUSD portfolio integration with MT5 Symbol_Engine

---

## STEP 1: CREATE NEW BUILD TASK

1. Open **StrategyQuant X**
2. Click **Builder** → **New Build Task**
3. Task Name: `EURUSD_Fib_Elliott_Scalping`

---

## STEP 2: DATA SETTINGS

### Market Data
1. Go to **Data** tab
2. **Symbol:** EURUSD
3. **Data Source:** Your broker (or Dukascopy/TrueFX for quality data)
4. **Main Timeframe:** M5
5. **Additional Timeframes:** M15 (check)
6. **Date Range:** 2023-01-01 to 2026-01-25 (minimum 3 years)

### Trading Costs
1. **Spread:** 1.5 pips (adjust to your broker)
2. **Commission:** 0 (or your broker's value)
3. **Slippage:** 0.5 pips
4. **Initial Capital:** 10000 USD

---

## STEP 3: WHAT TO BUILD - BUILDING BLOCKS

### A. Entry Indicators (Max 3-4 per strategy)

Go to **What to build** → **Entry Rules** → **Building Blocks**

#### Priority 1: FIBONACCI & ELLIOTT (Custom Indicators)
1. **Enable Custom Indicators:** YES
2. Add these if available in your SQ:
   - **Fibonacci Retracement** (levels: 38.2, 50.0, 61.8, 78.6)
   - **ZigZag** (for swing detection, depth: 12, deviation: 5, backstep: 3)
   - **Elliott Wave Oscillator** (if available)

#### Priority 2: TREND & MOMENTUM
Enable these indicators:
- ✅ **RSI** (period: 7-21)
- ✅ **MACD** (Fast: 8-12, Slow: 21-26, Signal: 7-9)
- ✅ **EMA** (period: 20, 50, 200)
- ✅ **ADX** (period: 14)
- ✅ **Stochastic** (K: 5-14, D: 3-5)

#### Priority 3: VOLATILITY & SUPPORT
- ✅ **ATR** (period: 14)
- ✅ **Bollinger Bands** (period: 20, deviation: 2.0)
- ✅ **Price Patterns** (if available: Pin Bar, Engulfing, Inside Bar)

### B. Exit Blocks

#### Stop Loss
1. **Type:** Multiple (check all)
   - ✅ Fixed (10-30 pips)
   - ✅ ATR-based (multiplier: 1.0-2.5)
   - ✅ Fibonacci-based (if available)

#### Take Profit
1. **Type:** Multiple
   - ✅ Fixed (15-60 pips)
   - ✅ ATR-based (multiplier: 1.5-4.0)
   - ✅ Risk-Reward ratio (1.5-3.0)

#### Trailing Stop
1. **Enable:** YES
2. **Start at profit:** 15-25 pips
3. **Trail distance:** 8-15 pips
4. **ATR-based:** YES (multiplier: 1.0-2.0)

#### Time-based Exit
1. **Enable:** YES
2. **Max trade duration:** 120 minutes (scalping)

---

## STEP 4: FILTERS & CONDITIONS

### Time Filters
Go to **Filters** → **Time Filters**

1. **Session Filter:** ENABLE
   - ✅ London Open: 07:00-11:00 UTC
   - ✅ New York: 13:00-17:00 UTC
   - ✅ Overlap: 13:00-16:00 UTC (highest priority)
   - ❌ Asian Session: DISABLE

2. **Day of Week Filter:** ENABLE
   - ✅ Monday: YES
   - ✅ Tuesday: YES
   - ✅ Wednesday: YES
   - ✅ Thursday: YES
   - ❌ Friday: NO (avoid weekend gaps)
   - ❌ Sunday: NO

3. **News Filter:** ENABLE (if available)
   - Avoid trading: 30 min before/after High Impact news
   - Currencies: USD, EUR

### Advanced Filters

1. **Spread Filter:** ENABLE
   - Max spread: 3.5 pips

2. **Volatility Filter:** ENABLE
   - Min ATR: 8 pips
   - Max ATR: 50 pips

3. **Choppiness Filter:** ENABLE (if available)
   - Avoid choppy markets

---

## STEP 5: POSITION SIZING & RISK

Go to **Position Sizing** tab

1. **Method:** Fixed Lots
2. **Fixed Lots:** 0.01
3. **Risk per trade:** 0.25% (sync with Symbol_Engine)
4. **Max positions:** 1
5. **Pyramiding:** DISABLE (Symbol_Engine handles add-ons)
6. **Martingale:** DISABLE

---

## STEP 6: RANKING & OPTIMIZATION

### Primary Ranking Metric
1. **Main metric:** Profit Factor
2. **Weight:** 40%

### Secondary Metrics (in order)
1. **Win Rate:** 25% weight (min: 50%)
2. **Max Drawdown:** 20% weight (max: 15%)
3. **Sharpe Ratio:** 10% weight (min: 0.80)
4. **Recovery Factor:** 5% weight (min: 2.0)

### Minimum Requirements
Set these filters in **Results Filter**:
```
Profit Factor >= 1.50
Win Rate >= 50%
Max Drawdown <= 15%
Total Trades >= 200
Avg Trade >= 2 pips
Max Consecutive Losses <= 6
Risk-Reward >= 1.3
```

---

## STEP 7: ROBUSTNESS TESTS

### Walk-Forward Analysis
1. **Enable:** YES
2. **Type:** Anchored
3. **In-Sample:** 70%
4. **Out-of-Sample:** 30%
5. **Number of periods:** 10
6. **Pass criteria:**
   - OOS Performance >= 80% of IS
   - OOS Profit Factor >= 1.30
   - OOS Win Rate >= 45%

### Monte Carlo Simulation
1. **Enable:** YES
2. **Runs:** 1000
3. **Pass rate:** 90%
4. **Max DD variation:** 20%
5. **Confidence level:** 95%

### Stress Test (if available)
1. **Spread multiplier:** 2.0x
2. **Slippage multiplier:** 2.0x
3. **Min pass rate:** 70%

---

## STEP 8: GENERATION SETTINGS

Go to **Builder Settings**

1. **Strategies to generate:** 10000
2. **Max runtime:** 720 minutes (12 hours)
3. **Generation method:** Random
4. **Optimization engine:** Genetic Algorithm
5. **CPU cores:** MAX (use all available)
6. **Parallel tasks:** MAX

---

## STEP 9: EXPORT SETTINGS

Go to **Code Generation** → **MetaTrader 5**

1. **Platform:** MetaTrader 5
2. **Template:** Standard MT5
3. **Include Money Management:** NO (Symbol_Engine handles it)
4. **Include Comments:** YES
5. **Compact code:** YES
6. **Optimization friendly:** YES

### Magic Numbers
1. **Starting Magic Number:** 100001
2. **Auto-increment:** YES
3. **Max strategies:** 100 (range 100001-100100)

### Comment Prefix
1. **Prefix:** `SQ_FibElliott_`

---

## STEP 10: SAVE AS TEMPLATE

After configuring everything:

1. Click **Save Template** (floppy disk icon)
2. Name: `EURUSD_Fib_Elliott_Scalping_Template`
3. This creates a `.sq4` file you can reuse

---

## STEP 11: START BUILDING

1. Click **Start Building** (green play button)
2. Monitor progress in **Build Queue**
3. Wait for completion (approx 12 hours for 10,000 strategies)

---

## STEP 12: FILTER & VALIDATE RESULTS

After building completes:

1. Go to **Results** tab
2. Apply filters:
   ```
   Profit Factor > 1.50
   Win Rate > 50%
   Max DD < 15%
   Trades > 200
   ```
3. Sort by: **Custom Ranking** (best first)
4. Select top 20 strategies
5. Run **Monte Carlo** on selected (if not done during build)
6. Run **Walk-Forward** on selected
7. Keep only strategies that PASS both tests

---

## STEP 13: PORTFOLIO OPTIMIZATION

1. Select 5-10 best strategies
2. Go to **Portfolio** → **Optimize Portfolio**
3. Settings:
   - **Max correlation:** 0.65
   - **Max portfolio DD:** 20%
   - **Min portfolio PF:** 2.0
   - **Target Sharpe:** 1.5
4. Run optimization
5. Select final 3-5 strategies for live trading

---

## STEP 14: EXPORT TO MT5

For each selected strategy:

1. Right-click → **Generate Code** → **MetaTrader 5**
2. Save to: `C:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\mt5\portafolio_manager\Experts\`
3. File naming: `SQ_FibElliott_001.mq5`, `SQ_FibElliott_002.mq5`, etc.
4. Each will have unique Magic Number (100001, 100002, etc.)

---

## STEP 15: INTEGRATION WITH SYMBOL_ENGINE

Each exported strategy runs alongside Symbol_Engine:

1. **Open separate MT5 chart** for each strategy
2. **Same symbol:** EURUSD
3. **Timeframe:** M5 or M15 (as generated)
4. **Magic Numbers:** Different (100001, 100002, etc.)
5. **Risk per trade:** 0.25% (will be scaled by Portfolio Governor)
6. **Max positions:** 1 per strategy

### Portfolio Configuration
```
Total strategies: 3-5
Total risk: 0.25% × 3 = 0.75% max (within InpMaxRisk)
Governor coordinates all via PortfolioGlobals.mqh
Each strategy independent but coordinated
```

---

## FIBONACCI SPECIFIC CONFIGURATION (Advanced)

If StrategyQuant has Fibonacci custom indicator:

### Fibonacci Retracement Settings
- **Swing detection:** ZigZag indicator
- **Lookback:** 20-50 bars
- **Levels to trade:**
  - Buy: 38.2%, 50.0%, 61.8% (retracement from high)
  - Sell: 38.2%, 50.0%, 61.8% (retracement from low)
- **Zone tolerance:** ±5 pips
- **Confluence bonus:** If price at Fib level AND other indicator signal

### Fibonacci Extension Settings (for TP)
- **TP Levels:** 100%, 127.2%, 161.8%, 261.8%
- **Use for:** Take Profit placement

### Elliott Wave Settings (if available)
- **Wave detection:** Fractal-based or ZigZag
- **Min wave size:** 15 pips (EURUSD)
- **Entry on:** Wave 3, Wave 5, Wave C
- **Validation:** Require Fibonacci alignment
  - Wave 2 retraces 50-61.8% of Wave 1
  - Wave 4 retraces 38.2-50% of Wave 3
  - Wave 5 extends to 100-161.8% of Wave 1

---

## CHECKLIST BEFORE STARTING

✅ EURUSD data downloaded (3 years minimum)
✅ Spread set to realistic value (1.5 pips)
✅ All indicators enabled (RSI, MACD, EMA, ATR, etc.)
✅ Fibonacci/ZigZag indicators available
✅ Time filters configured (London/NY sessions only)
✅ Stop Loss: 10-30 pips
✅ Take Profit: 15-60 pips
✅ Trailing stop enabled
✅ Time exit: 120 min
✅ Position sizing: Fixed 0.01 lots
✅ Ranking: Profit Factor primary
✅ Filters: PF>=1.5, WR>=50%, DD<=15%, Trades>=200
✅ Walk-Forward enabled (70/30 split)
✅ Monte Carlo enabled (1000 runs)
✅ Export: MT5, Magic 100001+, No MM
✅ Generate: 10000 strategies

---

## EXPECTED RESULTS

After 12 hours of generation:
- **Generated:** ~10,000 strategies
- **Passing initial filters:** ~500-1000
- **Passing Walk-Forward:** ~100-200
- **Passing Monte Carlo:** ~50-100
- **Final portfolio selection:** 3-5 strategies

---

## VALIDATION BEFORE LIVE

1. **Demo test:** 30 days minimum
2. **Monitor correlation:** Between strategies
3. **Check drawdown:** Portfolio should be < 20%
4. **Verify with Symbol_Engine:** No conflicts
5. **Test Governor allocation:** Risk scaling works correctly

---

## NOTES

- **Save your work frequently** (StrategyQuant can crash on long builds)
- **Export results to CSV** for analysis in Excel/Python
- **Keep build logs** for future reference
- **Test on demo first** - ALWAYS!
- **Monitor live performance** and re-optimize every 3 months

---

## FIBONACCI WORKAROUND (if not available as indicator)

If StrategyQuant doesn't have built-in Fibonacci:

1. Use **ZigZag indicator** for swing detection
2. Use **Support/Resistance levels** as proxy for Fib levels
3. Combine with **Price Patterns** near S/R
4. Use **Bollinger Bands** middle band as proxy for 50% retracement
5. Manual coding: Export strategy and add Fibonacci logic in MQL5

---

## TROUBLESHOOTING

**Problem:** "Not enough data"
**Solution:** Download more historical data or reduce date range

**Problem:** "No strategies pass filters"
**Solution:** Relax filters (reduce PF to 1.3, WR to 45%, DD to 20%)

**Problem:** "Build too slow"
**Solution:** Reduce strategies to 5000, reduce timeframes, use faster PC

**Problem:** "Strategies too correlated"
**Solution:** Increase building block diversity, add more random variation

---

Good luck! 🚀
