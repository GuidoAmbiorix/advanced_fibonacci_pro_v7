# 🚀 Database Maximization Plan - Portfolio Governor

## 📊 Current State Analysis

### What We HAVE:
✅ **9 Tables** with comprehensive data capture:
- **Trades** - Full trade lifecycle (entry, exit, P&L, MFE/MAE)
- **Signals** - Every signal generated (even rejected ones)
- **SymbolConfigs** - 84 parameters per symbol
- **GovernorState** - System state persistence
- **SystemLogs** - Audit trail
- **MarketData** - OHLCV bars for backtesting
- **OptimizationRuns** - Optimization history
- **SymbolConfigsBackup** - Config snapshots
- **ABTests** - A/B testing framework

### What We're MISSING:
❌ **No aggregated analytics** - Everything calculated on-demand
❌ **No performance tracking tables** - Can't see equity curve over time
❌ **No correlation tracking** - Don't know when pairs were correlated
❌ **No regime performance** - Can't see which regime is profitable
❌ **No risk metrics history** - Only current drawdown stored
❌ **No parameter importance** - Don't know which params matter most
❌ **No trade clustering** - Can't group similar trades
❌ **No alert/notification system** - No proactive warnings

---

## 🎯 PHASE 1: Core Analytics Tables (Week 1)

### **NEW TABLE: DailyPerformance**
**Purpose:** Daily performance snapshots for equity curve and metrics tracking

```sql
CREATE TABLE DailyPerformance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,              -- 'YYYY-MM-DD'
    day_of_week TEXT,                       -- 'Monday', 'Tuesday', etc.

    -- P&L Metrics
    starting_balance REAL,
    ending_balance REAL,
    daily_pnl REAL,
    daily_pnl_pct REAL,
    cumulative_pnl REAL,

    -- Trade Statistics
    total_trades INTEGER,
    wins INTEGER,
    losses INTEGER,
    win_rate REAL,
    profit_factor REAL,                     -- Total wins / Total losses
    avg_win REAL,
    avg_loss REAL,
    largest_win REAL,
    largest_loss REAL,

    -- Risk Metrics
    max_drawdown_pct REAL,
    max_drawdown_amount REAL,
    current_drawdown REAL,
    sharpe_ratio REAL,                      -- Rolling 30-day
    sortino_ratio REAL,                     -- Downside deviation

    -- Position Metrics
    avg_open_positions REAL,
    max_open_positions INTEGER,
    total_exposure REAL,                    -- Total lot size

    -- Efficiency Metrics
    expectancy REAL,                        -- Avg R per trade
    avg_trade_duration_minutes INTEGER,
    total_commission REAL,
    total_swap REAL,

    -- Symbol Breakdown (JSON)
    symbol_pnl_json TEXT,                   -- {'EURUSD': 120.5, 'GBPUSD': -45.2, ...}

    -- Regime Context
    dominant_regime TEXT,                   -- Most common regime that day
    regime_distribution_json TEXT,          -- {'TREND': 60%, 'RANGE': 40%}

    -- Created timestamp
    created_at INTEGER NOT NULL
);

CREATE INDEX idx_daily_perf_date ON DailyPerformance(date);
```

**Impact:**
- ✅ Can plot equity curve instantly
- ✅ Track performance degradation over time
- ✅ Identify best/worst days of week
- ✅ Calculate rolling Sharpe/Sortino
- ✅ Monitor if optimization is helping

**Auto-Population:**
Run daily at midnight (or on-demand):
```python
def populate_daily_performance(date):
    # Aggregate from Trades table
    # Calculate all metrics
    # Insert into DailyPerformance
```

---

### **NEW TABLE: SymbolPerformance**
**Purpose:** Per-symbol performance tracking and comparison

```sql
CREATE TABLE SymbolPerformance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    date TEXT NOT NULL,                     -- 'YYYY-MM-DD'

    -- Trade Statistics
    total_trades INTEGER,
    wins INTEGER,
    losses INTEGER,
    win_rate REAL,

    -- P&L
    total_pnl REAL,
    avg_pnl_per_trade REAL,
    largest_win REAL,
    largest_loss REAL,
    profit_factor REAL,

    -- Risk-Adjusted
    sharpe_ratio REAL,
    max_drawdown REAL,
    expectancy REAL,                        -- Avg R per trade

    -- Quality Metrics
    avg_confluence_score REAL,              -- Average entry quality
    avg_mfe REAL,                           -- Average max favorable excursion
    avg_mae REAL,                           -- Average max adverse excursion

    -- Efficiency
    avg_duration_minutes INTEGER,
    avg_commission REAL,
    avg_swap REAL,

    -- Context
    total_signals_generated INTEGER,        -- From Signals table
    total_signals_allowed INTEGER,
    rejection_rate REAL,                    -- %

    -- Updated timestamp
    updated_at INTEGER NOT NULL,

    UNIQUE(symbol, date)
);

CREATE INDEX idx_symbol_perf ON SymbolPerformance(symbol, date);
```

**Impact:**
- ✅ Compare symbol performance side-by-side
- ✅ Identify underperforming symbols
- ✅ Track if certain pairs need re-optimization
- ✅ Visualize symbol contribution to portfolio

---

### **NEW TABLE: RegimePerformance**
**Purpose:** Track how strategy performs in different market conditions

```sql
CREATE TABLE RegimePerformance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    regime TEXT NOT NULL,                   -- TREND, RANGE, VOLATILE, UNKNOWN
    period TEXT NOT NULL,                   -- 'YYYY-MM-DD' or 'YYYY-Www' for weekly

    -- Trade Stats
    total_trades INTEGER,
    wins INTEGER,
    losses INTEGER,
    win_rate REAL,

    -- P&L
    total_pnl REAL,
    avg_pnl_per_trade REAL,
    profit_factor REAL,

    -- Entry Quality
    avg_confluence_score REAL,
    avg_mfe REAL,
    avg_mae REAL,

    -- Context
    bars_in_regime INTEGER,                 -- How long regime lasted
    regime_stability REAL,                  -- % of time in same regime

    updated_at INTEGER NOT NULL,

    UNIQUE(symbol, regime, period)
);

CREATE INDEX idx_regime_perf ON RegimePerformance(symbol, regime, period);
```

**Impact:**
- ✅ Know which regimes are profitable vs unprofitable
- ✅ Disable trading in bad regimes
- ✅ Optimize for specific regime types
- ✅ Understand market context better

**Use Case:**
```
If RegimePerformance shows:
  - TREND regime: Win rate 75%, Sharpe 1.2
  - RANGE regime: Win rate 45%, Sharpe 0.3

Then: Disable trading in RANGE regime or optimize separately
```

---

### **NEW TABLE: KillzonePerformance**
**Purpose:** Track performance by trading session

```sql
CREATE TABLE KillzonePerformance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    killzone TEXT NOT NULL,                 -- Asian, London Open, NY, London Close, NONE
    period TEXT NOT NULL,                   -- 'YYYY-MM-DD' or weekly

    -- Trade Stats
    total_trades INTEGER,
    wins INTEGER,
    losses INTEGER,
    win_rate REAL,

    -- P&L
    total_pnl REAL,
    avg_pnl_per_trade REAL,
    profit_factor REAL,

    -- Quality
    avg_confluence_score REAL,
    avg_spread REAL,

    updated_at INTEGER NOT NULL,

    UNIQUE(symbol, killzone, period)
);

CREATE INDEX idx_killzone_perf ON KillzonePerformance(symbol, killzone, period);
```

**Impact:**
- ✅ Identify best trading sessions
- ✅ Disable underperforming killzones
- ✅ Optimize spread costs by session

---

## 🎯 PHASE 2: Advanced Analytics (Week 2)

### **NEW TABLE: CorrelationMatrix**
**Purpose:** Historical correlation tracking for diversification monitoring

```sql
CREATE TABLE CorrelationMatrix (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,             -- When correlation was calculated
    period_days INTEGER DEFAULT 30,         -- Lookback period

    -- Pair correlations (all combinations)
    symbol_a TEXT NOT NULL,
    symbol_b TEXT NOT NULL,
    correlation REAL,                       -- -1.0 to 1.0

    -- Statistical significance
    p_value REAL,                           -- Is correlation significant?
    sample_size INTEGER,                    -- Number of data points

    -- Context
    calculation_method TEXT,                -- 'pearson', 'spearman'

    UNIQUE(timestamp, symbol_a, symbol_b, period_days)
);

CREATE INDEX idx_correlation ON CorrelationMatrix(timestamp, symbol_a, symbol_b);
```

**Impact:**
- ✅ Track when symbols become too correlated
- ✅ Alert when diversification breaks down
- ✅ Optimize portfolio composition over time

**Use Case:**
```
If CorrelationMatrix shows EURUSD + GBPUSD correlation > 0.85 for 7 days:
  → Governor rejects trades to maintain diversification
  → Dashboard shows alert
```

---

### **NEW TABLE: DrawdownHistory**
**Purpose:** Track all drawdown periods for recovery analysis

```sql
CREATE TABLE DrawdownHistory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Drawdown Period
    start_time INTEGER NOT NULL,            -- When DD started
    end_time INTEGER,                       -- When DD recovered (NULL if ongoing)

    -- Depth
    peak_balance REAL,                      -- Balance at peak
    trough_balance REAL,                    -- Balance at lowest point
    drawdown_amount REAL,
    drawdown_pct REAL,

    -- Duration
    duration_days INTEGER,
    bars_to_recovery INTEGER,              -- How many trades to recover

    -- Context
    trades_during_dd INTEGER,
    consecutive_losses INTEGER,
    regime_during_dd TEXT,                 -- Dominant regime

    -- Recovery
    recovery_time INTEGER,                 -- When back to peak
    recovery_duration_days INTEGER,

    status TEXT DEFAULT 'ongoing'          -- 'ongoing', 'recovered'
);

CREATE INDEX idx_drawdown ON DrawdownHistory(start_time, status);
```

**Impact:**
- ✅ Identify average drawdown recovery time
- ✅ Set realistic expectations
- ✅ Alert when DD exceeds historical max
- ✅ Track if optimization reduces DD depth

---

### **NEW TABLE: ParameterImportance**
**Purpose:** Track which parameters actually matter for performance

```sql
CREATE TABLE ParameterImportance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    optimization_run_id INTEGER,            -- FK to OptimizationRuns

    parameter_name TEXT NOT NULL,
    importance_score REAL,                  -- 0.0 to 1.0 (from Optuna feature importance)
    rank INTEGER,                           -- 1 = most important

    -- Sensitivity
    value_range_min REAL,
    value_range_max REAL,
    optimal_value REAL,

    -- Impact
    sharpe_sensitivity REAL,                -- How much Sharpe changes with this param

    created_at INTEGER NOT NULL,

    FOREIGN KEY (optimization_run_id) REFERENCES OptimizationRuns(id)
);

CREATE INDEX idx_param_importance ON ParameterImportance(optimization_run_id, rank);
```

**Impact:**
- ✅ Focus optimization on important parameters
- ✅ Lock unimportant params to reduce overfitting
- ✅ Understand what drives performance

**Use Case:**
```
If ParameterImportance shows:
  1. risk_base (importance: 0.85)
  2. min_confluence_entry (importance: 0.72)
  3. swing_lookback (importance: 0.15)  ← Lock this next time

Then: Only optimize top 5 important params
```

---

### **NEW TABLE: TradePatterns**
**Purpose:** Cluster similar trades to find winning patterns

```sql
CREATE TABLE TradePatterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    pattern_name TEXT NOT NULL,             -- 'High Confluence Trends', 'London Open Pullbacks', etc.
    description TEXT,

    -- Pattern Characteristics
    min_confluence REAL,
    max_confluence REAL,
    regime TEXT,
    killzone TEXT,
    direction INTEGER,                      -- 1=BUY, -1=SELL, 0=Both

    -- Performance
    total_trades INTEGER,
    win_rate REAL,
    avg_pnl REAL,
    profit_factor REAL,
    sharpe_ratio REAL,

    -- Quality
    avg_mfe REAL,
    avg_mae REAL,

    -- Last Updated
    last_recalculated INTEGER,

    UNIQUE(pattern_name)
);

CREATE INDEX idx_patterns ON TradePatterns(pattern_name);
```

**Impact:**
- ✅ Identify high-probability setups
- ✅ Focus on winning patterns
- ✅ Filter out losing patterns

---

## 🎯 PHASE 3: Alerts & Monitoring (Week 3)

### **NEW TABLE: PerformanceAlerts**
**Purpose:** Automated alert system for degradation/issues

```sql
CREATE TABLE PerformanceAlerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    timestamp INTEGER NOT NULL,
    alert_type TEXT NOT NULL,               -- 'DEGRADATION', 'DRAWDOWN', 'CORRELATION', 'LOW_SHARPE', etc.
    severity TEXT NOT NULL,                 -- 'INFO', 'WARNING', 'CRITICAL'

    -- Alert Details
    title TEXT NOT NULL,
    message TEXT NOT NULL,

    -- Context
    symbol TEXT,                            -- NULL if portfolio-wide
    metric_name TEXT,                       -- What metric triggered alert
    current_value REAL,
    threshold_value REAL,

    -- Status
    acknowledged INTEGER DEFAULT 0,         -- User acknowledged
    resolved INTEGER DEFAULT 0,             -- Issue resolved
    resolved_at INTEGER,

    -- Actions
    suggested_action TEXT                   -- 'Re-optimize EURUSD', 'Reduce risk', etc.
);

CREATE INDEX idx_alerts ON PerformanceAlerts(timestamp, acknowledged, resolved);
```

**Alert Rules (Auto-triggered):**
```python
# Run every hour
def check_alerts():
    # 1. Sharpe Degradation
    if current_sharpe < last_optimization_sharpe * 0.7:
        create_alert('DEGRADATION', 'WARNING',
                    'Sharpe dropped 30% since optimization')

    # 2. Drawdown Threshold
    if current_dd > max_historical_dd * 1.2:
        create_alert('DRAWDOWN', 'CRITICAL',
                    'Drawdown exceeds historical max by 20%')

    # 3. Correlation Spike
    if avg_correlation > 0.75:
        create_alert('CORRELATION', 'WARNING',
                    'Portfolio correlation above 0.75')

    # 4. Win Rate Drop
    if rolling_7day_winrate < 40%:
        create_alert('LOW_WINRATE', 'WARNING',
                    '7-day win rate below 40%')

    # 5. Symbol Underperformance
    for symbol in symbols:
        if symbol_sharpe < 0.3 and trades > 10:
            create_alert('SYMBOL_WEAK', 'INFO',
                        f'{symbol} Sharpe < 0.3, consider re-optimization')
```

**Impact:**
- ✅ Proactive issue detection
- ✅ Know when to re-optimize
- ✅ Prevent large losses
- ✅ Dashboard shows alerts prominently

---

### **NEW TABLE: OptimizationSchedule**
**Purpose:** Track when each symbol should be re-optimized

```sql
CREATE TABLE OptimizationSchedule (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    symbol TEXT NOT NULL UNIQUE,

    -- Last Optimization
    last_optimization_time INTEGER,
    last_optimization_sharpe REAL,

    -- Current Performance
    current_sharpe REAL,
    current_winrate REAL,
    degradation_pct REAL,                   -- % drop from last optimization

    -- Scheduling
    next_scheduled_optimization INTEGER,    -- Unix timestamp
    optimization_frequency_days INTEGER DEFAULT 30,

    -- Priority
    needs_reoptimization INTEGER DEFAULT 0, -- Flag: 1 = urgent
    priority_score REAL,                    -- Higher = more urgent

    -- Reasons
    degradation_reason TEXT,                -- 'Sharpe drop', 'Drawdown spike', etc.

    updated_at INTEGER NOT NULL
);

CREATE INDEX idx_opt_schedule ON OptimizationSchedule(priority_score DESC, needs_reoptimization);
```

**Auto-Update Logic:**
```python
# Run daily
def update_optimization_schedule():
    for symbol in symbols:
        current_sharpe = calculate_sharpe(symbol, days=30)
        last_opt_sharpe = get_last_optimization_sharpe(symbol)

        degradation = (last_opt_sharpe - current_sharpe) / last_opt_sharpe

        priority_score = (
            degradation * 0.5 +                     # 50% weight on degradation
            (1 - current_sharpe) * 0.3 +            # 30% on low Sharpe
            (days_since_last_opt / 365) * 0.2       # 20% on staleness
        )

        if degradation > 0.3 or current_sharpe < 0.5:
            needs_reoptimization = 1

        update_schedule(symbol, priority_score, needs_reoptimization)
```

**Impact:**
- ✅ Never miss re-optimization window
- ✅ Prioritize which symbols to optimize first
- ✅ Automated maintenance schedule

---

## 🎯 PHASE 4: Machine Learning & Predictions (Week 4)

### **NEW TABLE: MarketConditions**
**Purpose:** Store market state features for pattern recognition

```sql
CREATE TABLE MarketConditions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    timestamp INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    timeframe INTEGER NOT NULL,             -- Minutes

    -- Price Action
    atr REAL,
    atr_percentile REAL,                    -- Where is ATR vs 90-day range
    trend_strength REAL,                    -- ADX or slope
    chop_index REAL,

    -- Regime
    regime TEXT,
    regime_duration_bars INTEGER,          -- How long in this regime

    -- Volatility
    realized_volatility REAL,
    implied_volatility REAL,               -- If available from options
    volatility_rank REAL,                  -- Percentile

    -- Momentum
    rsi REAL,
    momentum REAL,

    -- Structure
    recent_swing_count INTEGER,            -- Swings in last 50 bars
    fvg_count INTEGER,                     -- Fair value gaps

    -- Session
    killzone TEXT,
    time_of_day TEXT,                      -- 'Morning', 'Afternoon', 'Evening'

    UNIQUE(timestamp, symbol, timeframe)
);

CREATE INDEX idx_market_conditions ON MarketConditions(timestamp, symbol);
```

**Use Case:**
Train ML model to predict:
- Which market conditions lead to winning trades
- When to increase/decrease position size
- When to pause trading

---

### **NEW TABLE: PredictedPerformance**
**Purpose:** ML predictions for next-day expected performance

```sql
CREATE TABLE PredictedPerformance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    prediction_date TEXT NOT NULL,          -- 'YYYY-MM-DD'
    symbol TEXT NOT NULL,

    -- Predictions
    predicted_sharpe REAL,
    predicted_winrate REAL,
    predicted_pnl REAL,
    confidence_score REAL,                  -- 0.0 to 1.0

    -- Recommendation
    recommended_action TEXT,                -- 'TRADE', 'REDUCE_SIZE', 'PAUSE'
    recommended_risk_multiplier REAL,       -- 0.5 = half size, 1.0 = normal, 1.5 = increase

    -- Model Info
    model_version TEXT,
    features_used TEXT,                     -- JSON list of features

    -- Actual Results (filled next day)
    actual_sharpe REAL,
    actual_winrate REAL,
    actual_pnl REAL,
    prediction_error REAL,

    created_at INTEGER NOT NULL,

    UNIQUE(prediction_date, symbol)
);

CREATE INDEX idx_predictions ON PredictedPerformance(prediction_date, symbol);
```

**Impact:**
- ✅ Adaptive risk sizing based on conditions
- ✅ Pause trading in predicted bad conditions
- ✅ Increase size in high-confidence setups

---

## 🎯 PHASE 5: Portfolio-Level Analytics (Week 5)

### **NEW TABLE: PortfolioMetrics**
**Purpose:** Daily portfolio-wide statistics

```sql
CREATE TABLE PortfolioMetrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    date TEXT NOT NULL UNIQUE,              -- 'YYYY-MM-DD'

    -- Portfolio P&L
    total_pnl REAL,
    portfolio_value REAL,
    daily_return_pct REAL,

    -- Risk Metrics
    portfolio_sharpe REAL,
    portfolio_sortino REAL,
    max_drawdown REAL,
    current_drawdown REAL,

    -- Diversification
    avg_correlation REAL,                   -- Average pairwise correlation
    diversification_ratio REAL,             -- Portfolio volatility / sum of individual vols
    concentration_risk REAL,                -- % of P&L from top symbol

    -- Position Metrics
    total_open_positions INTEGER,
    total_symbols_traded INTEGER,
    avg_position_size_pct REAL,

    -- Efficiency
    total_commission REAL,
    total_swap REAL,
    slippage_estimate REAL,

    -- Quality
    avg_confluence_across_trades REAL,

    created_at INTEGER NOT NULL
);

CREATE INDEX idx_portfolio_metrics ON PortfolioMetrics(date);
```

**Impact:**
- ✅ Track true portfolio performance (not just sum of symbols)
- ✅ Monitor diversification quality
- ✅ Identify concentration risk

---

### **NEW TABLE: SymbolCorrelationHistory**
**Purpose:** Track how symbol relationships change over time

```sql
CREATE TABLE SymbolCorrelationHistory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    week TEXT NOT NULL,                     -- 'YYYY-Www' (ISO week)

    symbol_a TEXT NOT NULL,
    symbol_b TEXT NOT NULL,

    -- Correlation Stats
    correlation REAL,
    rolling_30d_correlation REAL,
    correlation_stability REAL,             -- Stdev of correlation

    -- Trade Overlap
    simultaneous_trades INTEGER,            -- How many trades overlapped
    simultaneous_wins INTEGER,
    simultaneous_losses INTEGER,

    -- Risk Impact
    combined_exposure REAL,                 -- Max combined lot size
    combined_risk_pct REAL,

    created_at INTEGER NOT NULL,

    UNIQUE(week, symbol_a, symbol_b)
);

CREATE INDEX idx_corr_history ON SymbolCorrelationHistory(week, symbol_a, symbol_b);
```

**Impact:**
- ✅ Visualize correlation trends
- ✅ Alert when correlation regime changes
- ✅ Adjust Governor correlation filter dynamically

---

## 📊 Summary of New Tables

| Phase | Tables | Purpose | Impact |
|-------|--------|---------|--------|
| **1** | DailyPerformance<br>SymbolPerformance<br>RegimePerformance<br>KillzonePerformance | Core analytics | Equity curve, symbol comparison, regime analysis |
| **2** | CorrelationMatrix<br>DrawdownHistory<br>ParameterImportance<br>TradePatterns | Advanced analytics | Diversification tracking, DD analysis, parameter tuning |
| **3** | PerformanceAlerts<br>OptimizationSchedule | Monitoring | Proactive alerts, automated maintenance |
| **4** | MarketConditions<br>PredictedPerformance | ML/Predictions | Adaptive risk, predictive trading |
| **5** | PortfolioMetrics<br>SymbolCorrelationHistory | Portfolio-level | True portfolio analytics, correlation trends |

---

## 🔧 Implementation Priority

### **MUST HAVE (Implement First):**
1. **DailyPerformance** - Critical for equity curve and tracking
2. **SymbolPerformance** - Essential for symbol comparison
3. **PerformanceAlerts** - Proactive issue detection
4. **OptimizationSchedule** - Automated maintenance

### **SHOULD HAVE (Implement Second):**
5. **RegimePerformance** - Understand market context
6. **KillzonePerformance** - Session optimization
7. **PortfolioMetrics** - True portfolio view
8. **DrawdownHistory** - Risk management

### **NICE TO HAVE (Implement Later):**
9. **CorrelationMatrix** - Advanced diversification
10. **ParameterImportance** - Optimization refinement
11. **TradePatterns** - Pattern recognition
12. **SymbolCorrelationHistory** - Trend analysis

### **FUTURE (ML/Advanced):**
13. **MarketConditions** - ML features
14. **PredictedPerformance** - Predictions

---

## 💡 Automation Scripts Needed

### **1. Daily Aggregation Job**
```python
# Run at midnight every day
def daily_aggregation():
    populate_daily_performance(yesterday)
    populate_symbol_performance(yesterday)
    populate_portfolio_metrics(yesterday)
    update_optimization_schedule()
    check_performance_alerts()
```

### **2. Weekly Aggregation Job**
```python
# Run Sunday night
def weekly_aggregation():
    populate_regime_performance(last_week)
    populate_killzone_performance(last_week)
    update_correlation_matrix()
    calculate_trade_patterns()
```

### **3. On-Trade-Close Hook**
```python
# Run every time a trade closes
def on_trade_close(trade):
    update_drawdown_history(trade)
    check_if_new_pattern(trade)
    update_market_conditions(trade.symbol)
```

---

## 🎯 Expected Outcomes

After implementing all tables:

1. **Dashboard becomes 10x more powerful:**
   - Live equity curve
   - Performance heatmaps by symbol/regime/session
   - Proactive alerts
   - ML-based recommendations

2. **Optimization becomes smarter:**
   - Know which params matter
   - Optimize only what needs it
   - Track param importance over time

3. **Risk management improves:**
   - Drawdown prediction
   - Correlation alerts
   - Adaptive position sizing

4. **Strategy evolves:**
   - Identify winning patterns
   - Filter out losing setups
   - Trade only in favorable conditions

5. **Maintenance becomes automated:**
   - Auto-schedule re-optimization
   - Alert before issues become critical
   - Self-tuning portfolio

---

## 📈 Database Size Estimates

After 1 year of trading (10 symbols, ~5 trades/day/symbol):

| Table | Rows | Size | Growth |
|-------|------|------|--------|
| Trades | ~18,000 | 5 MB | Linear |
| Signals | ~100,000 | 15 MB | Linear |
| DailyPerformance | 365 | 150 KB | Linear |
| SymbolPerformance | 3,650 | 1.5 MB | Linear |
| CorrelationMatrix | 16,425 | 2 MB | Linear |
| PerformanceAlerts | ~500 | 200 KB | Slow |
| **TOTAL** | ~138,000 | **~24 MB** | Manageable |

**Conclusion:** Database remains small and fast even after 1 year. Archive old data yearly if needed.

---

## ✅ Next Steps

1. Review this plan
2. Prioritize which tables to implement first
3. Create migration SQL scripts
4. Build auto-population functions
5. Update dashboard to display new analytics
6. Test on historical data
7. Deploy to production

**Result:** A world-class trading system database that rivals hedge fund infrastructure! 🚀
