-- Computer Vision Trading Agent Database Schema

-- Market Data Table
CREATE TABLE IF NOT EXISTS market_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    timeframe TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    open REAL NOT NULL,
    high REAL NOT NULL,
    low REAL NOT NULL,
    close REAL NOT NULL,
    tick_volume INTEGER,
    spread INTEGER,
    real_volume INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(symbol, timeframe, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_market_data_symbol_time ON market_data(symbol, timeframe, timestamp DESC);

-- Models Table
CREATE TABLE IF NOT EXISTS models (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    model_type TEXT NOT NULL, -- 'MLP', 'CNN', etc.
    hyperparameters TEXT, -- JSON string
    file_path TEXT NOT NULL,
    training_accuracy REAL,
    validation_accuracy REAL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 0,
    UNIQUE(name, version)
);

-- Training Runs Table
CREATE TABLE IF NOT EXISTS training_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    model_id INTEGER NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME,
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
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    model_id INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    prediction_direction TEXT NOT NULL, -- 'UP', 'DOWN'
    confidence REAL NOT NULL,
    window_start DATETIME NOT NULL,
    window_end DATETIME NOT NULL,
    prediction_horizon INTEGER NOT NULL, -- number of periods ahead
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (model_id) REFERENCES models(id)
);

CREATE INDEX IF NOT EXISTS idx_predictions_symbol_time ON predictions(symbol, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_predictions_model ON predictions(model_id);

-- Positions Table (Open positions)
CREATE TABLE IF NOT EXISTS positions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mt5_ticket INTEGER UNIQUE NOT NULL,
    symbol TEXT NOT NULL,
    position_type TEXT NOT NULL, -- 'BUY', 'SELL'
    volume REAL NOT NULL,
    open_price REAL NOT NULL,
    open_time DATETIME NOT NULL,
    stop_loss REAL,
    take_profit REAL,
    prediction_id INTEGER,
    status TEXT NOT NULL DEFAULT 'OPEN', -- 'OPEN', 'CLOSED'
    -- Exit strategy tracking
    breakeven_set BOOLEAN DEFAULT 0,
    partial_taken BOOLEAN DEFAULT 0,
    partial_volume REAL DEFAULT 0,
    trailing_active BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (prediction_id) REFERENCES predictions(id)
);

CREATE INDEX IF NOT EXISTS idx_positions_status ON positions(status);
CREATE INDEX IF NOT EXISTS idx_positions_symbol ON positions(symbol);

-- Killzone Windows Table
CREATE TABLE IF NOT EXISTS killzone_windows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    start_time TEXT NOT NULL, -- HH:MM format
    end_time TEXT NOT NULL, -- HH:MM format
    days_of_week TEXT NOT NULL, -- Comma-separated: "1,2,3,4,5" for Mon-Fri
    timezone TEXT NOT NULL DEFAULT 'America/New_York',
    priority TEXT DEFAULT 'medium', -- 'high', 'medium', 'low'
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_killzone_active ON killzone_windows(is_active);

-- Insert default killzone windows (GMT+2 timezone for FundingPips)
INSERT OR IGNORE INTO killzone_windows (name, start_time, end_time, days_of_week, timezone, priority) VALUES
    -- Asian Session
    ('Tokyo Open', '03:00', '07:00', '0,1,2,3,4', 'Europe/Athens', 'medium'),
    ('Tokyo Close', '10:00', '12:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    -- European Session
    ('London Open', '10:00', '12:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    ('London Mid-Session', '12:00', '14:00', '0,1,2,3,4', 'Europe/Athens', 'medium'),
    ('London-NY Overlap', '14:00', '17:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    ('London Close', '17:00', '19:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    -- American Session
    ('NY Open', '14:00', '17:00', '0,1,2,3,4', 'Europe/Athens', 'high'),
    ('NY Mid-Session', '17:00', '20:00', '0,1,2,3,4', 'Europe/Athens', 'medium'),
    ('NY Close', '20:00', '22:00', '0,1,2,3,4', 'Europe/Athens', 'high');

-- Trades Table (Completed trades)
CREATE TABLE IF NOT EXISTS trades (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    position_id INTEGER NOT NULL,
    mt5_ticket INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    trade_type TEXT NOT NULL, -- 'BUY', 'SELL'
    volume REAL NOT NULL,
    open_price REAL NOT NULL,
    close_price REAL NOT NULL,
    open_time DATETIME NOT NULL,
    close_time DATETIME NOT NULL,
    profit REAL NOT NULL,
    commission REAL DEFAULT 0,
    swap REAL DEFAULT 0,
    prediction_id INTEGER,
    entry_reason TEXT, -- 'ML_SIGNAL', 'MANUAL', etc.
    exit_reason TEXT, -- 'TP_HIT', 'SL_HIT', 'ML_SIGNAL', 'MANUAL', etc.
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (position_id) REFERENCES positions(id),
    FOREIGN KEY (prediction_id) REFERENCES predictions(id)
);

CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades(symbol);
CREATE INDEX IF NOT EXISTS idx_trades_close_time ON trades(close_time DESC);
CREATE INDEX IF NOT EXISTS idx_trades_prediction ON trades(prediction_id);

-- Trading Configuration Table
CREATE TABLE IF NOT EXISTS trading_config (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL,
    description TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert default configuration
INSERT OR IGNORE INTO trading_config (key, value, description) VALUES
    ('auto_trading_enabled', 'false', 'Enable/disable automated trading'),
    ('max_positions', '3', 'Maximum concurrent positions'),
    ('max_daily_loss_pct', '5.0', 'Maximum daily loss percentage'),
    ('min_confidence', '0.70', 'Minimum prediction confidence to trade'),
    ('default_lot_size', '0.01', 'Default lot size for trades'),
    ('stop_loss_pips', '50', 'Stop loss in pips'),
    ('take_profit_pips', '100', 'Take profit in pips');

-- System Logs Table
CREATE TABLE IF NOT EXISTS system_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    level TEXT NOT NULL, -- 'INFO', 'WARNING', 'ERROR'
    component TEXT NOT NULL, -- 'BRIDGE', 'TRADER', 'ML_ENGINE', 'DASHBOARD'
    message TEXT NOT NULL,
    details TEXT, -- JSON string with additional details
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_logs_level_time ON system_logs(level, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_component ON system_logs(component);

-- ==================== Portfolio Management ====================

-- Portfolios Table
CREATE TABLE IF NOT EXISTS portfolios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    initial_capital REAL NOT NULL,
    current_capital REAL NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Strategies Table
CREATE TABLE IF NOT EXISTS strategies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL, -- 'ML_MODEL', 'RULE_BASED'
    model_id INTEGER, -- Link to models table if type is ML_MODEL
    config TEXT, -- JSON configuration for rule-based strategies
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (model_id) REFERENCES models(id)
);

-- Portfolio Allocations Table
CREATE TABLE IF NOT EXISTS portfolio_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    portfolio_id INTEGER NOT NULL,
    strategy_id INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    weight REAL NOT NULL, -- 0.0 to 1.0 (allocation percentage)
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (portfolio_id) REFERENCES portfolios(id),
    FOREIGN KEY (strategy_id) REFERENCES strategies(id),
    UNIQUE(portfolio_id, strategy_id, symbol)
);

-- Portfolio Performance Table
CREATE TABLE IF NOT EXISTS portfolio_performance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    portfolio_id INTEGER NOT NULL,
    date DATETIME NOT NULL,
    total_equity REAL NOT NULL,
    daily_pnl REAL NOT NULL,
    drawdown REAL NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (portfolio_id) REFERENCES portfolios(id),
    UNIQUE(portfolio_id, date)
);

CREATE INDEX IF NOT EXISTS idx_performance_portfolio_date ON portfolio_performance(portfolio_id, date DESC);
