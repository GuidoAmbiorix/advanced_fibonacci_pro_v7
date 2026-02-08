# 🚀 Portfolio-Level Optimizer - Complete Guide

## What Was Built (Option C)

You now have a **correlation-aware, multi-symbol, portfolio-level optimizer** that optimizes for **total portfolio performance**, not individual pairs.

---

## 🎯 The Problem We Solved

**Before (Single-Symbol Optimization):**
- Optuna optimized 75 parameters per symbol
- Allowed to redesign strategy (turn SMC on/off, disable filters, etc.)
- Result: Perfect on training data, collapse on test data
- OOS degradation > 0.5 (overfitting)

**After (Portfolio-Level Optimization):**
- Optuna optimizes **12 parameters** across **all symbols**
- Strategy architecture is **frozen** (can't be changed)
- Optimizes for **portfolio Sharpe**, not individual pair Sharpe
- Includes **diversification bonus** and **correlation penalty**
- Result: Robust, stable parameters that work across multiple markets

---

## 📁 New Files Created

### 1. `optimizer_config_v2.py` - 3-Tier Parameter System
Classifies parameters into:
- **FROZEN** (32 params) - Strategy architecture, never optimized
- **TUNABLE** (12 params) - Execution parameters, optimized
- **FORBIDDEN** (31 params) - Risk/exits, use fixed defaults

### 2. `portfolio_metrics.py` - Portfolio Performance Calculations
- Portfolio Sharpe ratio
- Correlation matrix & average correlation
- Diversification ratio
- Worst-case symbol performance
- Portfolio-level objective function with penalties

### 3. `portfolio_optimizer.py` - Main Optimizer Class
- `PortfolioLevelOptimizer` class
- Multi-symbol backtesting
- Correlation-aware optimization
- Penalty system for constraints
- Database sync for all symbols

### 4. `test_portfolio_optimizer.py` - Test Suite
- Parameter classification test
- Quick optimization (5 trials, 3 symbols)
- Full optimization (100 trials, all symbols)

---

## 🔒 The 3-Tier Parameter System

### FROZEN Parameters (Strategy DNA - Never Touch)
These define **WHAT** the strategy is:
```python
use_smc: 1                    # SMC is core
use_mtf: 1                    # MTF confirmation required
use_displacement: 1           # Displacement detection
use_chop_filter: 1           # Chop filter prevents bad trades
use_trend_filter: 1          # Trend alignment required
use_news_filter: 1           # News filter
use_killzone_filter: 1       # Trade specific killzones
enable_london_open_kz: 1     # London killzone
enable_ny_kz: 1              # NY killzone
enable_asian_kz: 0           # No Asian session
```

### TUNABLE Parameters (Optimization - Only 12!)
These control **HOW** the strategy executes:
```python
swing_lookback: 30-80        # Swing detection period
zone_tolerance: 0.08-0.15    # Fibonacci zone width
fib_level_low: 0.38-0.70     # Lower Fib level
fib_level_high: 0.65-0.88    # Upper Fib level
atr_period: 12-18            # ATR calculation
chop_threshold: 0.4-0.7      # Chop filter sensitivity
min_confluence_entry: 12-22  # Entry threshold
risk_base: 0.3-0.7           # Base risk %
fixed_tp_r: 2.0-4.0          # Take profit R
min_tp_r: 1.5-2.5            # Minimum TP
trail_start_r: 1.0-2.0       # Trail activation
trail_atr_mult: 1.5-2.5      # Trail distance
```

### FORBIDDEN Parameters (Never Optimize)
These break the strategy if optimized:
```python
use_kelly: 0                 # No Kelly during optimization
enable_adaptive_risk: 0      # No adaptive risk
enable_learning: 0           # No learning during optimization
use_partial_tp: 0           # Fixed TP logic
rsi_period: 14              # Standard RSI
ema_period: 200             # Standard EMA
```

---

## 📊 Portfolio Objective Function

The optimizer maximizes this composite objective:

```python
Objective =
    0.50 × Portfolio_Sharpe          # Main driver
  + 0.20 × Diversification_Ratio     # Bonus for diversity
  + 0.15 × Worst_Symbol_Sharpe       # Robustness check
  - 0.15 × Average_Correlation       # Penalty for correlation
  - Penalties                         # Constraint violations
```

### Penalties Applied:
- **Insufficient trades**: 0.5 per missing trade below minimum
- **Excessive drawdown**: 3.0 × (DD - 0.25) if DD > 25%
- **High correlation**: 2.0 × (Corr - 0.75) if avg > 75%
- **Parameter instability**: Variance tracking across top trials

---

## 🚀 How to Use It

### Option 1: Quick Test (5 trials, 3 symbols, ~2 minutes)
```bash
docker compose exec dashboard python3 test_portfolio_optimizer.py
```

This will:
1. Show parameter classification
2. Run 5 trial optimization on EURUSD, GBPUSD, USDJPY
3. Display results (no database save)

### Option 2: Full Optimization (100 trials, all symbols, ~30 minutes)
```bash
docker compose exec dashboard python3 test_portfolio_optimizer.py
# Select "yes" when prompted for full optimization
```

This will:
1. Optimize all 10 symbols simultaneously
2. Run 100 Optuna trials
3. Save best parameters to database for **all symbols**
4. Verify database sync

### Option 3: Custom Python Script
```python
from database_manager import DatabaseManager
from portfolio_optimizer import PortfolioLevelOptimizer

# Initialize
db = DatabaseManager()
optimizer = PortfolioLevelOptimizer(db, timeframe=15)

# Customize symbols if needed
optimizer.symbols = ['EURUSD', 'GBPUSD', 'USDJPY']  # Or use default (all 10)

# Run optimization
results = optimizer.run_portfolio_optimization(n_trials=50)

# View results
print(f"Portfolio Sharpe: {results['portfolio_metrics']['portfolio_sharpe']:.3f}")
print(f"Avg Correlation: {results['portfolio_metrics']['avg_correlation']:.3f}")
print(f"Diversification: {results['portfolio_metrics']['diversification_ratio']:.3f}")

# Save to database (all symbols get same optimized params)
optimizer.save_portfolio_results(results)
```

---

## 📈 Expected Results

### Good Result Example:
```
Portfolio Metrics:
  Portfolio Sharpe:        0.75
  Avg Correlation:         0.45
  Diversification Ratio:   2.80
  Worst Symbol Sharpe:     0.40
  Avg Symbol Sharpe:       0.68

Individual Symbols:
  EURUSD:  Sharpe=0.75, Trades=18, MaxDD=12.5%
  GBPUSD:  Sharpe=0.68, Trades=15, MaxDD=15.2%
  USDJPY:  Sharpe=0.62, Trades=20, MaxDD=11.8%
  AUDUSD:  Sharpe=0.71, Trades=16, MaxDD=13.4%
  ...
```

**What This Means:**
- Portfolio Sharpe > 0.6 = Good
- Avg Correlation < 0.6 = Well diversified
- Div Ratio > 2.0 = Strong diversification
- Worst > 0.3 = All symbols viable (no dead weight)

### Bad Result (Overfitting) Example:
```
Portfolio Metrics:
  Portfolio Sharpe:        0.35
  Avg Correlation:         0.85
  Diversification Ratio:   1.20
  Worst Symbol Sharpe:    -0.50
  Avg Symbol Sharpe:       0.42

Individual Symbols:
  EURUSD:  Sharpe=0.85, Trades=5, MaxDD=35.2%
  GBPUSD:  Sharpe=-0.50, Trades=3, MaxDD=45.8%
  ...
```

**Red Flags:**
- Portfolio Sharpe < 0.5 = Weak
- Avg Correlation > 0.7 = Over-correlated
- Div Ratio < 1.5 = Poor diversification
- Worst < 0 = Strategy fails on some symbols
- Low trade counts = Overfitted

---

## 🎯 What Happens Next

After optimization completes:

### 1. Review Results
Check the portfolio report printed to console. Look for:
- Portfolio Sharpe > 0.6
- Avg Correlation < 0.6
- All symbols have Sharpe > 0.3
- Trade counts > 10 per symbol

### 2. Save to Database
If results look good, the optimizer will save parameters to **all symbols**.

The same optimized parameters are applied to all symbols because:
- They were optimized for **portfolio performance**
- Parameters are execution-focused (ATR periods, Fib levels, etc.)
- Strategy logic is frozen (SMC, MTF, filters unchanged)

### 3. Restart MT5 EA
```bash
docker compose restart mt5
```

The EA will load the new parameters and start trading with:
- Same strategy logic (SMC, MTF, killzones)
- Optimized execution (Fib zones, ATR, confluence threshold)
- Portfolio-optimized settings

### 4. Monitor Performance
Track these metrics over 1-2 weeks:
- Live portfolio Sharpe vs backtest
- Correlation between live pairs
- Any parameter degradation (OOS test)

---

## 🔧 Customization Options

### Change Symbol Universe
Edit `optimizer_config_v2.py`:
```python
PORTFOLIO_SETTINGS = {
    "symbols": [
        "EURUSD", "GBPUSD", "USDJPY",  # Add/remove symbols
        "XAUUSD"  # Include gold if desired
    ],
    ...
}
```

### Adjust Objective Weights
```python
PORTFOLIO_SETTINGS = {
    "objective_weights": {
        "portfolio_sharpe": 0.60,       # Increase focus on Sharpe
        "diversification_ratio": 0.10,  # Reduce div bonus
        "worst_symbol_sharpe": 0.20,    # Increase robustness weight
        "avg_correlation": -0.10,       # Reduce corr penalty
    },
    ...
}
```

### Modify Tunable Parameter Ranges
Edit `optimizer_config_v2.py`:
```python
TUNABLE_PARAMS = {
    "swing_lookback": {"type": "int", "low": 40, "high": 60, "step": 5},  # Tighter range
    "risk_base": {"type": "float", "low": 0.4, "high": 0.6, "step": 0.05},  # More conservative
    ...
}
```

### Change Frozen Parameters
```python
FROZEN_PARAMS = {
    "use_smc": 1,           # Keep SMC
    "enable_asian_kz": 1,   # Enable Asian session
    ...
}
```

---

## 💡 Best Practices

### DO:
✅ Start with quick test (5 trials) to verify everything works
✅ Review parameter classification before optimizing
✅ Check portfolio metrics, not just Sharpe
✅ Verify diversification ratio > 2.0
✅ Ensure all symbols have positive Sharpe
✅ Save results only if metrics look good
✅ Monitor live performance vs backtest

### DON'T:
❌ Don't optimize architecture params (use_smc, use_mtf, etc.)
❌ Don't add more tunable params (keep ≤ 12)
❌ Don't ignore correlation warnings
❌ Don't save results if worst symbol Sharpe < 0
❌ Don't expect perfect match between backtest and live
❌ Don't optimize too frequently (monthly max)

---

## 🐛 Troubleshooting

### "No market data available"
- Check database connection
- Verify symbols exist in SymbolConfigs table
- Ensure sufficient bars (>100) per symbol

### "Database save failed"
- Check column filtering is working
- Verify database isn't locked
- Review logs for SQL errors

### "All symbols have negative Sharpe"
- Parameter ranges might be too restrictive
- Check if frozen params are appropriate
- Verify market data quality

### "High correlation warning"
- Normal for some currency pairs (e.g., EURUSD + GBPUSD)
- Consider removing one from optimization
- Or adjust correlation penalty weight

### "Optimization very slow"
- Reduce number of symbols for testing
- Use fewer trials (50 instead of 100)
- Check if MTF analysis is enabled (expensive)

---

## 📊 Performance Expectations

### Realistic Targets (After Optimization):
- **Portfolio Sharpe**: 0.6 - 1.2
- **Avg Correlation**: 0.3 - 0.6
- **Diversification Ratio**: 2.0 - 3.5
- **Worst Symbol Sharpe**: 0.3 - 0.8
- **OOS Degradation**: < 0.4

### Live vs Backtest Degradation:
Expect 15-30% degradation from backtest to live due to:
- Slippage (1-2 pips)
- Spread variations
- Execution delays
- Market regime changes

If live Sharpe = 0.7 and backtest = 1.0, that's **normal and acceptable**.

---

## 🎉 Summary

You now have:
1. ✅ 3-tier parameter classification (frozen/tunable/forbidden)
2. ✅ Portfolio-level optimization (12 tunable params only)
3. ✅ Correlation-aware objective function
4. ✅ Diversification bonus system
5. ✅ Penalty system for constraints
6. ✅ Multi-symbol database sync
7. ✅ Comprehensive test suite

**This is a proper quant-grade portfolio optimizer!** 🚀

Next step: Run the test and see your results!
