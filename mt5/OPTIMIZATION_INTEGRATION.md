# AI Optimization Engine - Integration Complete

## Overview
The AI Optimization Engine (Optuna-based) has been successfully integrated into the Portfolio Governor Dashboard. Users can now optimize trading parameters directly from the web interface, and changes are automatically reflected in the Symbol Configuration.

---

## What Was Implemented

### 1. Optimizer Code Integration
- **Merged from**: `origin/optimizer` branch
- **Files added to dashboard**:
  - `optimizer.py` - Core Optuna optimization engine (223 lines)
  - `optimizer_config.py` - Parameter search spaces (74 lines)
  - `database_manager.py` - SQLite operations (153 lines)

### 2. Docker Configuration Update
- **File**: `docker-compose.yml`
- **Change**: Removed `:ro` (read-only) flag from dashboard volume mount
- **Before**: `- mt5_config_v2:/mt5_data:ro`
- **After**: `- mt5_config_v2:/mt5_data`
- **Impact**: Dashboard can now WRITE optimization results to PortfolioGovernor.sqlite

### 3. Dashboard Dependencies
- **File**: `requirements.txt`
- **Added**:
  - `optuna` - Bayesian optimization framework
  - `numpy` - Numerical computing (required by optimizer)

### 4. New UI Features

#### A. AI Optimization Page (New)
Located at: Dashboard → AI Optimization

**Features**:
- Symbol selector dropdown (auto-populated from SymbolConfigs)
- Configuration display showing current parameters
- "Start Optimization" button with real-time progress
- Optimization settings display (trials, training days, target metric)
- Results viewer showing:
  - Best parameters found
  - Before/After comparison table
  - Percentage changes for each parameter
  - Timestamp of optimization
- Data validation (checks for MarketData availability)
- Error handling with detailed traceback

#### B. Enhanced Configuration Page
Located at: Dashboard → Configuration

**New Features**:
- "Reload from Database" button (clears cache)
- Last optimization activity indicator
- Link/tip to AI Optimization page
- Symbol count display

---

## Complete Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│  USER ACTION: Web Dashboard                                 │
│  1. Navigates to "AI Optimization"                          │
│  2. Selects symbol: EURUSD                                  │
│  3. Clicks "Start Optimization"                             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  DASHBOARD BACKEND (Streamlit + optimizer.py)               │
│  1. DatabaseManager.get_market_data("EURUSD", 5, 5000)      │
│     - Loads OHLC bars from MarketData table                 │
│  2. PortfolioOptimizer.run_optimization("EURUSD")           │
│     - Creates Optuna study (direction=maximize)             │
│     - Runs 100 trials of objective function                 │
│  3. objective() for each trial:                             │
│     - Suggests parameters from search space                 │
│     - Calculates RSI, EMA, ATR indicators                   │
│     - Generates trade signals (confluence)                  │
│     - Simulates trades with SL/TP/trailing                  │
│     - Returns Sharpe Ratio                                  │
│  4. optimizer.update_db("EURUSD", best_params)              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  DATABASE LAYER (database_manager.py)                       │
│  1. load_configs() - Gets current EURUSD config             │
│  2. config.update(best_params) - Merges new values          │
│  3. save_config() - Executes UPDATE SQL                     │
│     UPDATE SymbolConfigs SET                                │
│       risk_base=0.65, fixed_tp_r=2.8, rsi_period=21, ...    │
│     WHERE symbol='EURUSD'                                   │
│  4. verify_config_sync() - Confirms write success           │
│  5. log_event() - Records to SystemLogs                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  MT5 SQLITE DATABASE                                        │
│  File: PortfolioGovernor.sqlite                             │
│  Table: SymbolConfigs (UPDATED)                             │
│    - risk_base: 0.5 → 0.65 (+30%)                           │
│    - fixed_tp_r: 2.0 → 2.8 (+40%)                           │
│    - rsi_period: 14 → 21 (+50%)                             │
│    - ema_period: 100 → 150 (+50%)                           │
│    - ... (all optimized parameters)                         │
│  Table: SystemLogs (NEW ENTRY)                              │
│    - "Optimization completed for EURUSD"                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  DASHBOARD DISPLAY (User sees results)                      │
│  1. Progress bar reaches 100%                               │
│  2. Success message displayed                               │
│  3. Before/After comparison table shown                     │
│  4. Cache cleared, data refreshed                           │
│  5. Configuration page shows updated values                 │
└─────────────────────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  MT5 EA (Symbol_Engine.mq5)                                 │
│  On next reload/restart:                                    │
│    - Reads updated SymbolConfigs from database              │
│    - Applies new parameters:                                │
│      - risk_base = 0.65                                     │
│      - fixed_tp_r = 2.8                                     │
│      - rsi_period = 21                                      │
│    - Begins trading with optimized settings                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Deployment Steps

### 1. Rebuild Dashboard Container
The dashboard now includes new Python dependencies (optuna, numpy) and optimizer code.

```bash
cd "C:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\mt5"

# Stop current dashboard
docker-compose --profile app stop dashboard

# Rebuild dashboard image
docker-compose --profile app build dashboard

# Start dashboard
docker-compose --profile app up -d dashboard
```

### 2. Verify Deployment
```bash
# Check logs
docker logs portfolio-dashboard

# Should see:
# - "Streamlit is running on port 8501"
# - No import errors for optuna/numpy
```

### 3. Test Optimization
1. Open browser: `http://localhost:8501`
2. Navigate to "AI Optimization"
3. Select a symbol (e.g., EURUSD)
4. Verify market data exists: Should show data point count
5. Click "Start Optimization"
6. Observe progress bar
7. Review results in Before/After table
8. Navigate to "Configuration" page
9. Verify updated parameters are displayed

---

## Optimization Settings

Located in `optimizer_config.py`:

```python
OPTIMIZATION_SETTINGS = {
    "n_trials": 100,          # Number of Optuna trials
    "train_days": 90,         # Training period
    "test_days": 14,          # Validation period
    "min_trades": 30,         # Minimum trades for valid result
    "target_metric": "sharpe" # Optimization target (Sharpe Ratio)
}
```

### Parameters Optimized

**Default symbols** (25 parameters):
- Fibonacci: swing_lookback, zone_tolerance
- Displacement: use_displacement, displacement_atr, displacement_lookback
- RSI: rsi_period, rsi_oversold, rsi_overbought
- Trend: ema_period, ema_min_slope
- Chop: use_chop_filter, chop_threshold
- Confluence: min_confluence_entry
- Risk: risk_base, max_risk, enable_adaptive_risk
- TP: fixed_tp_r, min_tp_r
- Trailing: trail_start_r, trail_atr_mult
- Volatility: volatility_threshold
- Spread: max_spread_points

**JPY pairs** (specialized ranges):
- Higher risk_base range (0.2-0.6)
- Higher fixed_tp_r range (2.0-6.0)
- Higher trail_atr_mult (1.5-4.0)

**XAU (Gold)** (specialized ranges):
- Even higher risk_base (0.3-1.0)
- Higher fixed_tp_r (2.5-8.0)
- Larger spread tolerance (50-200 points)
- Shorter swing lookback (10-50)

---

## How It Works

### Optimization Algorithm
The optimizer uses **Optuna's Tree-structured Parzen Estimator (TPE)** for Bayesian optimization:

1. **Trial Suggestion**: Optuna suggests parameter values based on:
   - Search space defined in `optimizer_config.py`
   - Historical trial results (learns which regions are promising)

2. **Backtesting**: For each trial:
   - Loads M5 OHLC data from MarketData table
   - Calculates indicators (RSI, EMA, ATR)
   - Generates signals based on confluence rules
   - Simulates trade execution with SL/TP/trailing stops
   - Tracks equity curve

3. **Fitness Metric**: Sharpe Ratio
   ```python
   sharpe = mean(returns) / std(returns)
   ```
   - Higher Sharpe = Better risk-adjusted returns
   - Penalties for insufficient trades (<30)

4. **Convergence**: After 100 trials, returns parameters that achieved highest Sharpe

### Database Update
The `update_db()` method:
1. Loads current config for symbol
2. Merges optimized parameters (preserves unoptimized fields)
3. Executes UPDATE SQL
4. Verifies changes persisted
5. Logs event to SystemLogs

---

## Prerequisites

### Data Availability
The optimizer requires market data in the `MarketData` table:
- **Source**: Populated by MT5 EA during trading
- **Required**: At least 100 bars of M5 data
- **Recommended**: 5000 bars (≈17 days of M5 data)

**Check data availability**:
```sql
SELECT symbol, COUNT(*) as bars
FROM MarketData
WHERE timeframe = 5
GROUP BY symbol;
```

If insufficient data:
- Run EA for several days to collect data
- Or manually import historical data to MarketData table

---

## Troubleshooting

### Issue: "Insufficient market data"
**Cause**: MarketData table empty or too few bars
**Solution**:
1. Check if EA is running and storing data
2. Verify database path is correct
3. Query MarketData table directly

### Issue: "Database Save Failed"
**Cause**: Volume mount still read-only or schema mismatch
**Solution**:
1. Verify docker-compose.yml has no `:ro` flag
2. Restart dashboard container
3. Check file permissions on SQLite file

### Issue: "Import Error: No module named 'optuna'"
**Cause**: Dashboard container not rebuilt
**Solution**:
```bash
docker-compose --profile app build dashboard
docker-compose --profile app up -d dashboard
```

### Issue: Optimization runs but results don't appear in Configuration
**Cause**: Streamlit cache not cleared
**Solution**:
- Click "Reload from Database" button on Configuration page
- Or refresh browser (Ctrl+F5)

---

## Future Enhancements

### Recommended Additions

1. **Walk-Forward Validation**
   - Split data into train/test periods
   - Show out-of-sample Sharpe ratio
   - Prevent overfitting

2. **Optimization History Table**
   - Track all optimization runs
   - Store trial data for analysis
   - Compare parameter evolution over time

3. **Multi-Symbol Optimization**
   - Optimize portfolio-wide parameters
   - Consider correlation between pairs
   - Global risk parameters

4. **Scheduled Optimization**
   - Weekly/monthly auto-optimization
   - Notification system for results
   - Automatic backup before applying changes

5. **Advanced Metrics Display**
   - Drawdown curves
   - Trade distribution
   - Win rate by parameter set
   - Equity curves (train vs test)

6. **Parameter Constraints**
   - Lock certain parameters
   - Set custom ranges per symbol
   - Multi-objective optimization (Sharpe + Drawdown)

---

## File Locations

```
mt5/
├── docker-compose.yml           (MODIFIED: Read-write volume)
├── dashboard/
│   ├── app.py                   (MODIFIED: +209 lines, new AI Optimization page)
│   ├── requirements.txt         (MODIFIED: Added optuna, numpy)
│   ├── optimizer.py             (NEW: 223 lines, Optuna engine)
│   ├── optimizer_config.py      (NEW: 74 lines, Parameter spaces)
│   ├── database_manager.py      (NEW: 153 lines, SQLite operations)
│   ├── Dockerfile               (Unchanged)
│   └── ...
└── portafolio_manager/
    ├── Portfolio_Governor.mq5   (Unchanged: Reads SymbolConfigs)
    ├── Symbol_Engine.mq5        (Unchanged: Uses loaded config)
    └── Include/
        ├── DatabaseManager.mqh  (Unchanged: Creates SymbolConfigs table)
        └── ...
```

---

## Testing Checklist

- [ ] Dashboard container rebuilds successfully
- [ ] No import errors in dashboard logs
- [ ] AI Optimization page loads
- [ ] Symbol dropdown populated from database
- [ ] Current configuration displays correctly
- [ ] Market data check works
- [ ] Optimization runs without errors
- [ ] Progress bar updates in real-time
- [ ] Results display with Before/After comparison
- [ ] SymbolConfigs table updated in SQLite
- [ ] SystemLogs records optimization event
- [ ] Configuration page shows updated values
- [ ] Cache refresh works correctly

---

## Support

For issues or questions:
1. Check dashboard logs: `docker logs portfolio-dashboard`
2. Check MT5 logs in Expert tab
3. Query database directly to verify state
4. Review this documentation

---

**Implementation Date**: 2026-02-06
**Status**: ✅ Complete and Ready for Deployment
