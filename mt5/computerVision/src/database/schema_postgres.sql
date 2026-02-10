-- Computer Vision Trading Agent Database Schema - PostgreSQL

-- Market Data Table
CREATE TABLE IF NOT EXISTS market_data (
    id SERIAL PRIMARY KEY,
    symbol TEXT NOT NULL,
    timeframe TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    open REAL NOT NULL,
    high REAL NOT NULL,
    low REAL NOT NULL,
    close REAL NOT NULL,
    tick_volume INTEGER,
    spread INTEGER,
    real_volume INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(symbol, timeframe, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_market_data_symbol_time ON market_data(symbol, timeframe, timestamp DESC);

-- Models Table
CREATE TABLE IF NOT EXISTS models (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    model_type TEXT NOT NULL, -- 'MLP', 'CNN', etc.
    hyperparameters JSONB, -- JSON data
    file_path TEXT NOT NULL,
    training_accuracy REAL,
    validation_accuracy REAL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT FALSE,
    UNIQUE(name, version)
);

-- Training Runs Table
CREATE TABLE IF NOT EXISTS training_runs (
    id SERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    status TEXT NOT NULL, -- 'running', 'completed', 'failed'
    num_samples INTEGER,
    num_epochs INTEGER,
    final_loss REAL,
    final_accuracy REAL,
    notes TEXT,
    FOREIGN KEY (model_id) REFERENCES models(id)
);

CREATE INDEX IF NOT EXISTS idx_training_runs_model ON training_runs(model_id);

-- Predictions Table
CREATE TABLE IF NOT EXISTS predictions (
    id SERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    prediction_direction TEXT NOT NULL, -- 'UP', 'DOWN'
    confidence REAL NOT NULL,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    prediction_horizon INTEGER NOT NULL, -- number of periods ahead
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (model_id) REFERENCES models(id)
);

CREATE INDEX IF NOT EXISTS idx_predictions_symbol_time ON predictions(symbol, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_predictions_model ON predictions(model_id);

-- Positions Table (Open positions)
CREATE TABLE IF NOT EXISTS positions (
    id SERIAL PRIMARY KEY,
    mt5_ticket INTEGER UNIQUE NOT NULL,
    symbol TEXT NOT NULL,
    position_type TEXT NOT NULL, -- 'BUY', 'SELL'
    volume REAL NOT NULL,
    open_price REAL NOT NULL,
    open_time TIMESTAMP NOT NULL,
    stop_loss REAL,
    take_profit REAL,
    prediction_id INTEGER,
    status TEXT NOT NULL DEFAULT 'OPEN', -- 'OPEN', 'CLOSED'
    -- Exit strategy tracking
    breakeven_set BOOLEAN DEFAULT FALSE,
    partial_taken BOOLEAN DEFAULT FALSE,
    partial_volume REAL DEFAULT 0,
    trailing_active BOOLEAN DEFAULT FALSE,
    -- Exit results
    exit_time TIMESTAMP,
    exit_price REAL,
    profit REAL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (prediction_id) REFERENCES predictions(id)
);

CREATE INDEX IF NOT EXISTS idx_positions_status ON positions(status);
CREATE INDEX IF NOT EXISTS idx_positions_symbol ON positions(symbol);

-- Killzone Windows Table
CREATE TABLE IF NOT EXISTS killzone_windows (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    start_time TEXT NOT NULL, -- HH:MM format
    end_time TEXT NOT NULL, -- HH:MM format
    days_of_week TEXT NOT NULL, -- Comma-separated: "1,2,3,4,5" for Mon-Fri
    timezone TEXT NOT NULL DEFAULT 'America/New_York',
    priority TEXT DEFAULT 'medium', -- 'high', 'medium', 'low'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_killzone_name ON killzone_windows(name);
CREATE INDEX IF NOT EXISTS idx_killzone_active ON killzone_windows(is_active);

-- Insert default killzone windows (GMT+2 timezone for FundingPips)
INSERT INTO killzone_windows (name, start_time, end_time, days_of_week, timezone, priority) VALUES
    -- Asian Session
    ('Tokyo Open', '03:00', '07:00', '0,1,2,3,4', 'Europe/Athens', 'medium'),
    ('Tokyo Close / London Open', '10:00', '12:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    -- European Session
    ('London Mid-Session', '12:00', '14:00', '0,1,2,3,4', 'Europe/Athens', 'medium'),
    ('London-NY Overlap', '14:00', '17:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    ('London Close', '17:00', '19:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    -- American Session
    ('NY Mid-Session', '17:00', '20:00', '0,1,2,3,4', 'Europe/Athens', 'medium'),
    ('NY Close', '20:00', '22:00', '0,1,2,3,4', 'Europe/Athens', 'high')
ON CONFLICT (name) DO NOTHING;

-- Trades Table (Completed trades)
CREATE TABLE IF NOT EXISTS trades (
    id SERIAL PRIMARY KEY,
    position_id INTEGER NOT NULL,
    mt5_ticket INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    trade_type TEXT NOT NULL, -- 'BUY', 'SELL'
    volume REAL NOT NULL,
    open_price REAL NOT NULL,
    close_price REAL NOT NULL,
    open_time TIMESTAMP NOT NULL,
    close_time TIMESTAMP NOT NULL,
    profit REAL NOT NULL,
    commission REAL DEFAULT 0,
    swap REAL DEFAULT 0,
    prediction_id INTEGER,
    entry_reason TEXT, -- 'ML_SIGNAL', 'MANUAL', etc.
    exit_reason TEXT, -- 'TP_HIT', 'SL_HIT', 'ML_SIGNAL', 'MANUAL', etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (position_id) REFERENCES positions(id),
    FOREIGN KEY (prediction_id) REFERENCES predictions(id)
);

CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades(symbol);
CREATE INDEX IF NOT EXISTS idx_trades_close_time ON trades(close_time DESC);
CREATE INDEX IF NOT EXISTS idx_trades_prediction ON trades(prediction_id);

-- Trading Configuration Table
CREATE TABLE IF NOT EXISTS trading_config (
    id SERIAL PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default configuration
INSERT INTO trading_config (key, value, description) VALUES
    ('auto_trading_enabled', 'false', 'Enable/disable automated trading'),
    ('max_positions', '3', 'Maximum concurrent positions'),
    ('max_daily_loss_pct', '5.0', 'Maximum daily loss percentage'),
    ('min_confidence', '0.70', 'Minimum prediction confidence to trade'),
    ('default_lot_size', '0.01', 'Default lot size for trades'),
    ('stop_loss_pips', '50', 'Stop loss in pips'),
    ('take_profit_pips', '100', 'Take profit in pips')
ON CONFLICT (key) DO NOTHING;

-- System Logs Table
CREATE TABLE IF NOT EXISTS system_logs (
    id SERIAL PRIMARY KEY,
    level TEXT NOT NULL, -- 'INFO', 'WARNING', 'ERROR'
    component TEXT NOT NULL, -- 'BRIDGE', 'TRADER', 'ML_ENGINE', 'DASHBOARD'
    message TEXT NOT NULL,
    details JSONB, -- JSON data with additional details
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_logs_level_time ON system_logs(level, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_component ON system_logs(component);

-- ==================== Portfolio Management ====================

-- Portfolios Table
CREATE TABLE IF NOT EXISTS portfolios (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    initial_capital REAL NOT NULL,
    current_capital REAL NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Strategies Table
CREATE TABLE IF NOT EXISTS strategies (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL, -- 'ML_MODEL', 'RULE_BASED'
    model_id INTEGER, -- Link to models table if type is ML_MODEL
    config JSONB, -- JSON configuration for rule-based strategies
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (model_id) REFERENCES models(id)
);

-- Portfolio Allocations Table
CREATE TABLE IF NOT EXISTS portfolio_allocations (
    id SERIAL PRIMARY KEY,
    portfolio_id INTEGER NOT NULL,
    strategy_id INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    weight REAL NOT NULL, -- 0.0 to 1.0 (allocation percentage)
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (portfolio_id) REFERENCES portfolios(id),
    FOREIGN KEY (strategy_id) REFERENCES strategies(id),
    UNIQUE(portfolio_id, strategy_id, symbol)
);

-- Portfolio Performance Table
CREATE TABLE IF NOT EXISTS portfolio_performance (
    id SERIAL PRIMARY KEY,
    portfolio_id INTEGER NOT NULL,
    date DATE NOT NULL,
    total_equity REAL NOT NULL,
    daily_pnl REAL NOT NULL,
    drawdown REAL NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (portfolio_id) REFERENCES portfolios(id),
    UNIQUE(portfolio_id, date)
);

CREATE INDEX IF NOT EXISTS idx_performance_portfolio_date ON portfolio_performance(portfolio_id, date DESC);

-- ==================== Signal Confirmation System ====================

-- Signal Confirmations Table (tracks signal validation lifecycle)
CREATE TABLE IF NOT EXISTS signal_confirmations (
    id SERIAL PRIMARY KEY,
    prediction_id INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    direction TEXT NOT NULL, -- 'BUY', 'SELL'
    initial_confidence REAL NOT NULL,

    -- Confirmation tracking
    status TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'CONFIRMED', 'REJECTED', 'EXPIRED', 'EXECUTED'
    confirmation_score REAL DEFAULT 0,

    -- Signal validation metrics
    mtf_alignment INTEGER DEFAULT 0, -- -1 (against), 0 (neutral), 1 (aligned)
    mtf_score REAL DEFAULT 0,
    momentum_score REAL DEFAULT 0,
    volume_score REAL DEFAULT 0,
    trend_score REAL DEFAULT 0,
    fibonacci_score REAL DEFAULT 0,
    smc_score REAL DEFAULT 0,
    volume_confirmed BOOLEAN DEFAULT FALSE,
    trend_confirmed BOOLEAN DEFAULT FALSE,
    fibonacci_details JSONB, -- JSON with Fib analysis details
    smc_details JSONB, -- JSON with SMC analysis details

    -- Timing
    signal_generated_at TIMESTAMP NOT NULL,
    confirmation_window_end TIMESTAMP NOT NULL,
    confirmed_at TIMESTAMP,
    executed_at TIMESTAMP,

    -- Rejection tracking
    rejection_reason TEXT,
    validation_details JSONB, -- JSON with detailed validation breakdown

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (prediction_id) REFERENCES predictions(id)
);

CREATE INDEX IF NOT EXISTS idx_signal_confirmations_status ON signal_confirmations(status, symbol);
CREATE INDEX IF NOT EXISTS idx_signal_confirmations_symbol_time ON signal_confirmations(symbol, signal_generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_signal_confirmations_pending ON signal_confirmations(status) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_signal_confirmations_fib_score ON signal_confirmations(fibonacci_score);
CREATE INDEX IF NOT EXISTS idx_signal_confirmations_smc_score ON signal_confirmations(smc_score);

-- Trade Cooldowns Table (prevents overtrading)
CREATE TABLE IF NOT EXISTS trade_cooldowns (
    id SERIAL PRIMARY KEY,
    symbol TEXT NOT NULL,
    last_trade_time TIMESTAMP NOT NULL,
    cooldown_end_time TIMESTAMP NOT NULL,
    reason TEXT, -- 'TRADE_EXECUTED', 'STOP_LOSS', 'RAPID_SIGNALS'
    trade_direction TEXT, -- 'BUY', 'SELL' from last trade
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cooldown_symbol ON trade_cooldowns(symbol);
CREATE INDEX IF NOT EXISTS idx_cooldown_end_time ON trade_cooldowns(cooldown_end_time);
