-- V3 Trading System - PostgreSQL Initialization Script
-- Creates tables for historical data storage and ML training

-- Create schema
CREATE SCHEMA IF NOT EXISTS trading;

-- ==================== Market Data Tables ====================

-- OHLCV Data
CREATE TABLE IF NOT EXISTS trading.market_data (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    open DECIMAL(18, 8) NOT NULL,
    high DECIMAL(18, 8) NOT NULL,
    low DECIMAL(18, 8) NOT NULL,
    close DECIMAL(18, 8) NOT NULL,
    volume DECIMAL(18, 4) NOT NULL,
    spread DECIMAL(18, 8) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(symbol, timeframe, timestamp)
);

CREATE INDEX idx_market_data_symbol_time ON trading.market_data(symbol, timeframe, timestamp DESC);
CREATE INDEX idx_market_data_timestamp ON trading.market_data(timestamp DESC);

-- ==================== Trade History ====================

CREATE TABLE IF NOT EXISTS trading.trades (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    direction VARCHAR(10) NOT NULL,  -- BUY, SELL
    entry_time TIMESTAMP NOT NULL,
    entry_price DECIMAL(18, 8) NOT NULL,
    exit_time TIMESTAMP,
    exit_price DECIMAL(18, 8),
    lot_size DECIMAL(10, 4) NOT NULL,
    stop_loss DECIMAL(18, 8),
    take_profit DECIMAL(18, 8),
    profit_loss DECIMAL(18, 4),
    r_multiple DECIMAL(10, 4),
    confluence_score DECIMAL(10, 4),
    regime VARCHAR(50),
    sentiment_score DECIMAL(10, 4),
    orderflow_score DECIMAL(10, 4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_trades_symbol ON trading.trades(symbol);
CREATE INDEX idx_trades_entry_time ON trading.trades(entry_time DESC);

-- ==================== AI/ML Model Data ====================

-- Sentiment Scores
CREATE TABLE IF NOT EXISTS trading.sentiment_scores (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    positive DECIMAL(10, 8) NOT NULL,
    negative DECIMAL(10, 8) NOT NULL,
    neutral DECIMAL(10, 8) NOT NULL,
    composite DECIMAL(10, 8) NOT NULL,
    confidence DECIMAL(10, 8) NOT NULL,
    source TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(symbol, timestamp)
);

CREATE INDEX idx_sentiment_symbol_time ON trading.sentiment_scores(symbol, timestamp DESC);

-- Regime Detections
CREATE TABLE IF NOT EXISTS trading.regime_detections (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    regime VARCHAR(50) NOT NULL,
    confidence DECIMAL(10, 8) NOT NULL,
    probabilities JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(symbol, timeframe, timestamp)
);

CREATE INDEX idx_regime_symbol_time ON trading.regime_detections(symbol, timeframe, timestamp DESC);

-- Order Flow Data
CREATE TABLE IF NOT EXISTS trading.orderflow_data (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    buy_volume DECIMAL(18, 4) NOT NULL,
    sell_volume DECIMAL(18, 4) NOT NULL,
    imbalance DECIMAL(10, 8) NOT NULL,
    large_order_detected BOOLEAN DEFAULT FALSE,
    direction SMALLINT DEFAULT 0,
    confidence DECIMAL(10, 8),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_orderflow_symbol_time ON trading.orderflow_data(symbol, timestamp DESC);

-- ==================== Performance Metrics ====================

CREATE TABLE IF NOT EXISTS trading.daily_performance (
    id BIGSERIAL PRIMARY KEY,
    date DATE NOT NULL UNIQUE,
    total_trades INT DEFAULT 0,
    winning_trades INT DEFAULT 0,
    losing_trades INT DEFAULT 0,
    win_rate DECIMAL(10, 4),
    total_profit DECIMAL(18, 4) DEFAULT 0,
    total_r_multiple DECIMAL(18, 4) DEFAULT 0,
    max_drawdown DECIMAL(18, 4),
    sharpe_ratio DECIMAL(10, 4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_daily_performance_date ON trading.daily_performance(date DESC);

-- ==================== ML Model Metadata ====================

CREATE TABLE IF NOT EXISTS trading.ml_models (
    id BIGSERIAL PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    model_type VARCHAR(50) NOT NULL,  -- FINBERT, HMM, DRL, etc.
    version VARCHAR(20) NOT NULL,
    accuracy DECIMAL(10, 8),
    trained_on TIMESTAMP,
    deployed_on TIMESTAMP,
    status VARCHAR(20) DEFAULT 'training',  -- training, deployed, archived
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==================== News & Events ====================

CREATE TABLE IF NOT EXISTS trading.news_events (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL,
    headline TEXT NOT NULL,
    source VARCHAR(100),
    full_text TEXT,
    affected_symbols VARCHAR(200)[],
    sentiment_score DECIMAL(10, 8),
    impact_level VARCHAR(20),  -- LOW, MEDIUM, HIGH
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_news_timestamp ON trading.news_events(timestamp DESC);
CREATE INDEX idx_news_symbols ON trading.news_events USING GIN(affected_symbols);

-- ==================== System Logs ====================

CREATE TABLE IF NOT EXISTS trading.system_logs (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    level VARCHAR(20) NOT NULL,  -- INFO, WARNING, ERROR, CRITICAL
    service VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB
);

CREATE INDEX idx_logs_timestamp ON trading.system_logs(timestamp DESC);
CREATE INDEX idx_logs_level ON trading.system_logs(level);

-- ==================== Views ====================

-- Recent Performance Summary
CREATE OR REPLACE VIEW trading.v_recent_performance AS
SELECT
    DATE_TRUNC('day', entry_time) as trade_date,
    COUNT(*) as total_trades,
    SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as wins,
    SUM(CASE WHEN profit_loss <= 0 THEN 1 ELSE 0 END) as losses,
    ROUND(AVG(CASE WHEN profit_loss > 0 THEN 1.0 ELSE 0.0 END) * 100, 2) as win_rate,
    SUM(r_multiple) as total_r,
    AVG(r_multiple) as avg_r,
    MAX(r_multiple) as best_trade,
    MIN(r_multiple) as worst_trade
FROM trading.trades
WHERE exit_time IS NOT NULL
GROUP BY DATE_TRUNC('day', entry_time)
ORDER BY trade_date DESC;

-- Symbol Performance
CREATE OR REPLACE VIEW trading.v_symbol_performance AS
SELECT
    symbol,
    COUNT(*) as total_trades,
    SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as wins,
    ROUND(AVG(CASE WHEN profit_loss > 0 THEN 1.0 ELSE 0.0 END) * 100, 2) as win_rate,
    SUM(r_multiple) as total_r,
    AVG(r_multiple) as avg_r,
    AVG(confluence_score) as avg_confluence
FROM trading.trades
WHERE exit_time IS NOT NULL
GROUP BY symbol
ORDER BY total_r DESC;

-- ==================== Grants ====================

GRANT ALL ON SCHEMA trading TO v3_trader;
GRANT ALL ON ALL TABLES IN SCHEMA trading TO v3_trader;
GRANT ALL ON ALL SEQUENCES IN SCHEMA trading TO v3_trader;
