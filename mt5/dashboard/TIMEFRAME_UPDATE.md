# ⏰ Timeframe-Aware Optimization - Critical Update

## 🎯 Issue Fixed

**Previously:** The optimizer was hardcoded to use M5 data for ALL optimizations, regardless of the actual trading timeframe.

**Problem:** Parameters optimized for M5 don't work on H1, H4, or D1!

**Now Fixed:** ✅ Full timeframe awareness throughout the system

---

## 🔧 Changes Made

### 1. **optimizer_config.py** - Timeframe Configuration

Added comprehensive timeframe support:

```python
TIMEFRAMES = {
    "M1": 1,
    "M5": 5,
    "M15": 15,
    "M30": 30,
    "H1": 60,
    "H4": 240,
    "D1": 1440,
    "W1": 10080
}

# Different data limits per timeframe
TIMEFRAME_DATA_LIMITS = {
    1: 10000,      # M1: 10000 bars
    5: 5000,       # M5: 5000 bars ≈ 17 days
    15: 3000,      # M15: 3000 bars ≈ 31 days
    30: 2000,      # M30: 2000 bars ≈ 42 days
    60: 1500,      # H1: 1500 bars ≈ 62 days
    240: 1000,     # H4: 1000 bars ≈ 166 days
    1440: 500,     # D1: 500 bars ≈ 1.4 years
    10080: 200     # W1: 200 bars ≈ 3.8 years
}

# Minimum trades required per timeframe
TIMEFRAME_MIN_TRADES = {
    1: 50,         # M1: Expect many trades
    5: 40,         # M5: Expect many trades
    15: 30,        # M15: Moderate trades
    30: 25,        # M30: Moderate trades
    60: 20,        # H1: Fewer trades
    240: 15,       # H4: Few trades
    1440: 10,      # D1: Very few trades
    10080: 5       # W1: Minimal trades
}
```

### 2. **optimizer.py** - Timeframe-Aware Optimizer

#### PortfolioOptimizer Class:
```python
# Now accepts timeframe parameter
optimizer = PortfolioOptimizer(db_manager, timeframe=15)  # M15

# Automatically:
- Uses correct data limit for timeframe
- Adjusts minimum trade requirements
- Labels optimization runs with timeframe
- Loads appropriate amount of historical data
```

#### WalkForwardOptimizer Class:
```python
# Also timeframe-aware
wf_optimizer = WalkForwardOptimizer(db_manager, timeframe=60)  # H1
```

#### Key Changes:
- `__init__(self, db_manager, timeframe=None)` - Accepts timeframe
- `self.tf_settings = get_timeframe_settings(self.timeframe)` - Gets TF config
- `min_trades = self.tf_settings['min_trades']` - Uses TF-specific minimums
- Mode saved as `single_M15`, `multi_objective_H1`, etc.

### 3. **app.py** - UI Timeframe Selector

#### New Timeframe Dropdown:
```python
timeframe_options = {
    "M1 (1-Minute)": 1,
    "M5 (5-Minute)": 5,
    "M15 (15-Minute) ⭐ Recommended": 15,
    "M30 (30-Minute)": 30,
    "H1 (1-Hour)": 60,
    "H4 (4-Hour)": 240,
    "D1 (Daily)": 1440
}
```

#### Added Educational Expander:
- Explains why timeframe matters
- Shows parameter differences per TF
- Data requirement breakdown
- Recommendations

---

## 📊 How It Works Now

### Example: Optimizing for M15

```python
from database_manager import DatabaseManager
from optimizer import PortfolioOptimizer

db = DatabaseManager("PortfolioGovernor.sqlite")

# Specify timeframe
optimizer = PortfolioOptimizer(db, timeframe=15)  # M15

# Run optimization
results = optimizer.run_optimization("EURUSD")

# Output:
# 🚀 Starting Optimization for EURUSD on M15...
#    Timeframe: M15
#    Data points: 3000
#    Min trades required: 30
```

### Example: Optimizing for H1

```python
# Different timeframe
optimizer = PortfolioOptimizer(db, timeframe=60)  # H1

results = optimizer.run_optimization("GBPUSD")

# Output:
# 🚀 Starting Optimization for GBPUSD on H1...
#    Timeframe: H1
#    Data points: 1500
#    Min trades required: 20
```

---

## 🎯 Why This Matters

### Parameters Are NOT Timeframe-Agnostic!

#### Example: RSI Period

**M5 Optimization:**
- Optimal RSI period: 7-10
- Price changes rapidly
- Need quick response

**H1 Optimization:**
- Optimal RSI period: 14-21
- Price changes slowly
- Need smoother signal

**Result:** M5's RSI=7 on H1 = too noisy! ❌

#### Example: EMA Period

**M15 Optimization:**
- Optimal EMA: 50-100
- Filters noise, captures trend

**D1 Optimization:**
- Optimal EMA: 200+
- Much longer lookback needed

**Result:** M15's EMA=50 on D1 = too reactive! ❌

#### Example: Stop Loss Distance

**M5 Optimization:**
- Optimal SL: 1.5 ATR
- Tight stops work on M5

**H4 Optimization:**
- Optimal SL: 2.5-3.0 ATR
- Need wider stops for volatility

**Result:** M5's SL on H4 = stopped out constantly! ❌

---

## 🔍 Optimization History Tracking

Now tracks timeframe in mode field:

| Run ID | Symbol | Mode | Sharpe | OOS Risk |
|--------|--------|------|--------|----------|
| 1 | EURUSD | single_M15 | 2.34 | LOW |
| 2 | GBPUSD | single_H1 | 1.87 | LOW |
| 3 | XAUUSD | multi_objective_M5 | 3.12 | MEDIUM |
| 4 | USDJPY | single_D1 | 1.45 | HIGH |

This allows you to:
- Compare M15 vs H1 optimization results
- Track which timeframe works best per symbol
- Ensure you're using correct parameters

---

## ✅ Verification Checklist

Before running optimization, verify:

1. ✅ **Timeframe selected matches your trading**
   - If you trade on M15 charts → Select M15
   - If you trade on H1 charts → Select H1

2. ✅ **Sufficient data available**
   - Check "Data points loaded" in console
   - M15 needs 3000 bars ≈ 31 days
   - H1 needs 1500 bars ≈ 62 days

3. ✅ **Min trades achieved**
   - M15 needs 30+ trades for valid backtest
   - H1 needs 20+ trades
   - D1 needs 10+ trades

4. ✅ **OOS validation shows good generalization**
   - OOS degradation < 0.5
   - Overfitting risk = LOW or MEDIUM

---

## 📝 Usage Guide

### In UI (Dashboard):

1. Navigate to **AI Optimization** page
2. Select your **Symbol** (e.g., EURUSD)
3. Select your **Timeframe** (e.g., M15 ⭐ Recommended)
4. Read the "Understanding Timeframe Selection" expander
5. Click **🚀 Start Optimization**

### In Code:

```python
# Single symbol, specific timeframe
optimizer = PortfolioOptimizer(db, timeframe=15)
results = optimizer.run_optimization("EURUSD")

# Multi-objective, different timeframe
optimizer_h1 = PortfolioOptimizer(db, timeframe=60)
results = optimizer_h1.run_multi_objective_optimization("GBPUSD")

# Walk-forward, any timeframe
wf_optimizer = WalkForwardOptimizer(db, timeframe=240)  # H4
wf_results = wf_optimizer.run_walk_forward("XAUUSD")
```

---

## 🎯 Recommendations by Timeframe

### M5 (5-Minute) - Scalping
**Best for:** EURUSD, GBPUSD (low spread pairs)
**Parameters to focus on:**
- Tight stops (1.5-2.0 ATR)
- Quick exits
- Lower RSI periods (7-10)
- Shorter EMA (20-50)

### M15 (15-Minute) - Day Trading ⭐ RECOMMENDED
**Best for:** Most major pairs
**Parameters to focus on:**
- Balanced parameters
- Standard indicators (RSI=14, EMA=100)
- Good R:R ratios (2-4R)

### H1 (1-Hour) - Swing Trading
**Best for:** All pairs, especially volatile ones (XAU, JPY pairs)
**Parameters to focus on:**
- Wider stops (2.5-3.0 ATR)
- Longer lookbacks
- Higher RSI periods (14-21)
- Longer EMA (100-200)

### H4/D1 (4-Hour/Daily) - Position Trading
**Best for:** Major pairs, commodities
**Parameters to focus on:**
- Very wide stops (3.0+ ATR)
- Long-term indicators
- Patience required
- Large EMA (200+)

---

## ⚠️ Common Mistakes to Avoid

### ❌ Mistake 1: Using M5 Parameters on H1
**Problem:** Too tight stops, too many trades, constant whipsaws
**Solution:** Optimize specifically for H1

### ❌ Mistake 2: Using D1 Parameters on M15
**Problem:** Stops too wide, misses opportunities, under-trades
**Solution:** Optimize specifically for M15

### ❌ Mistake 3: Not Enough Data for Timeframe
**Problem:** Optimizer can't find good parameters, overfits
**Solution:** Ensure MarketData table has sufficient history
- M15: Need 31+ days
- H1: Need 62+ days
- D1: Need 1.4+ years

### ❌ Mistake 4: Comparing Across Timeframes Directly
**Problem:** "My M5 Sharpe is 3.2 but H1 Sharpe is 1.8, M5 must be better!"
**Reality:** Lower timeframes naturally have more trades = higher Sharpe potential
**Solution:** Compare within same timeframe only

---

## 🚀 Next Steps

1. **Determine your trading timeframe**
   - How often can you monitor trades?
   - What's your risk tolerance?
   - How many trades do you want per day?

2. **Ensure sufficient data**
   - Run EA for adequate time to collect data
   - Check MarketData table has enough bars

3. **Run timeframe-specific optimization**
   - Select correct timeframe in UI
   - Review OOS validation results
   - Check parameter importance

4. **Test on demo account**
   - Deploy optimized parameters to EA
   - Monitor for 1-2 weeks
   - Compare live results to backtest

5. **Iterate if needed**
   - If too many trades → Move to higher TF
   - If too few trades → Move to lower TF
   - Re-optimize as needed

---

## 📞 Support

If you encounter issues:
1. Check timeframe data availability in MarketData table
2. Verify minimum trade count achieved
3. Review OOS validation metrics
4. Check Optimization History page for trends

---

**Updated:** 2026-02-07
**Version:** 3.1.0 - Timeframe-Aware Optimization
**Status:** ✅ Production Ready

---

*This update ensures parameters are optimized for YOUR actual trading timeframe, dramatically improving real-world performance.*
