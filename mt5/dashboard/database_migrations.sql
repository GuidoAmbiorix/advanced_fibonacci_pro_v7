-- ============================================================================
-- DATABASE MAXIMIZATION - ANALYTICS TABLES MIGRATION
-- ============================================================================
-- This migration adds 14 new analytics tables to maximize database usage
-- Created: 2026-02-08
-- Author: Claude Code
-- ============================================================================

-- ============================================================================
-- PHASE 1: CORE ANALYTICS TABLES
-- ============================================================================

-- TABLE: DailyPerformance
-- Purpose: Daily performance snapshots for equity curve and metrics tracking
CREATE TABLE IF NOT EXISTS DailyPerformance (
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

CREATE INDEX IF NOT EXISTS idx_daily_perf_date ON DailyPerformance(date);

-- TABLE: SymbolPerformance
-- Purpose: Per-symbol performance tracking and comparison
CREATE TABLE IF NOT EXISTS SymbolPerformance (
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
    sortino_ratio REAL,
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

CREATE INDEX IF NOT EXISTS idx_symbol_perf ON SymbolPerformance(symbol, date);

-- TABLE: RegimePerformance
-- Purpose: Track how strategy performs in different market conditions
CREATE TABLE IF NOT EXISTS RegimePerformance (
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

CREATE INDEX IF NOT EXISTS idx_regime_perf ON RegimePerformance(symbol, regime, period);

-- TABLE: KillzonePerformance
-- Purpose: Track performance by trading session
CREATE TABLE IF NOT EXISTS KillzonePerformance (
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

CREATE INDEX IF NOT EXISTS idx_killzone_perf ON KillzonePerformance(symbol, killzone, period);

-- ============================================================================
-- PHASE 2: ADVANCED ANALYTICS
-- ============================================================================

-- TABLE: CorrelationMatrix
-- Purpose: Historical correlation tracking for diversification monitoring
CREATE TABLE IF NOT EXISTS CorrelationMatrix (
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

CREATE INDEX IF NOT EXISTS idx_correlation ON CorrelationMatrix(timestamp, symbol_a, symbol_b);

-- TABLE: DrawdownHistory
-- Purpose: Track all drawdown periods for recovery analysis
CREATE TABLE IF NOT EXISTS DrawdownHistory (
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

CREATE INDEX IF NOT EXISTS idx_drawdown ON DrawdownHistory(start_time, status);

-- TABLE: ParameterImportance
-- Purpose: Track which parameters actually matter for performance
CREATE TABLE IF NOT EXISTS ParameterImportance (
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

CREATE INDEX IF NOT EXISTS idx_param_importance ON ParameterImportance(optimization_run_id, rank);

-- TABLE: TradePatterns
-- Purpose: Cluster similar trades to find winning patterns
CREATE TABLE IF NOT EXISTS TradePatterns (
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

CREATE INDEX IF NOT EXISTS idx_patterns ON TradePatterns(pattern_name);

-- ============================================================================
-- PHASE 3: ALERTS & MONITORING
-- ============================================================================

-- TABLE: PerformanceAlerts
-- Purpose: Automated alert system for degradation/issues
CREATE TABLE IF NOT EXISTS PerformanceAlerts (
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

CREATE INDEX IF NOT EXISTS idx_alerts ON PerformanceAlerts(timestamp, acknowledged, resolved);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON PerformanceAlerts(severity, acknowledged);

-- TABLE: OptimizationSchedule
-- Purpose: Track when each symbol should be re-optimized
CREATE TABLE IF NOT EXISTS OptimizationSchedule (
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

CREATE INDEX IF NOT EXISTS idx_opt_schedule ON OptimizationSchedule(priority_score DESC, needs_reoptimization);

-- ============================================================================
-- PHASE 4: MACHINE LEARNING & PREDICTIONS
-- ============================================================================

-- TABLE: MarketConditions
-- Purpose: Store market state features for pattern recognition
CREATE TABLE IF NOT EXISTS MarketConditions (
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

CREATE INDEX IF NOT EXISTS idx_market_conditions ON MarketConditions(timestamp, symbol);

-- TABLE: PredictedPerformance
-- Purpose: ML predictions for next-day expected performance
CREATE TABLE IF NOT EXISTS PredictedPerformance (
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

CREATE INDEX IF NOT EXISTS idx_predictions ON PredictedPerformance(prediction_date, symbol);

-- ============================================================================
-- PHASE 5: PORTFOLIO-LEVEL ANALYTICS
-- ============================================================================

-- TABLE: PortfolioMetrics
-- Purpose: Daily portfolio-wide statistics
CREATE TABLE IF NOT EXISTS PortfolioMetrics (
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

CREATE INDEX IF NOT EXISTS idx_portfolio_metrics ON PortfolioMetrics(date);

-- TABLE: SymbolCorrelationHistory
-- Purpose: Track how symbol relationships change over time
CREATE TABLE IF NOT EXISTS SymbolCorrelationHistory (
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

CREATE INDEX IF NOT EXISTS idx_corr_history ON SymbolCorrelationHistory(week, symbol_a, symbol_b);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Total new tables: 14
-- Phase 1: 4 tables (Core Analytics)
-- Phase 2: 4 tables (Advanced Analytics)
-- Phase 3: 2 tables (Alerts & Monitoring)
-- Phase 4: 2 tables (ML & Predictions)
-- Phase 5: 2 tables (Portfolio-Level)
-- ============================================================================
