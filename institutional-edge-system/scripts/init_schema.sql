
-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR UNIQUE NOT NULL,
    username VARCHAR UNIQUE NOT NULL,
    hashed_password VARCHAR NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create bot_configs table
CREATE TABLE IF NOT EXISTS bot_configs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    name VARCHAR NOT NULL,
    mt5_login VARCHAR,
    mt5_server VARCHAR,
    symbol VARCHAR DEFAULT 'EURUSD',
    timeframe VARCHAR DEFAULT 'H1',
    risk_percent FLOAT DEFAULT 2.0,
    min_confluence_score INTEGER DEFAULT 6,
    max_trades INTEGER DEFAULT 3,
    is_active BOOLEAN DEFAULT FALSE,
    last_signal_time TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create trades table
CREATE TABLE IF NOT EXISTS trades (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    ticket INTEGER UNIQUE,
    symbol VARCHAR NOT NULL,
    trade_type VARCHAR NOT NULL,
    entry_price FLOAT NOT NULL,
    stop_loss FLOAT,
    take_profit_1 FLOAT,
    take_profit_2 FLOAT,
    take_profit_3 FLOAT,
    exit_price FLOAT,
    volume FLOAT NOT NULL,
    risk_percent FLOAT NOT NULL,
    confluence_score INTEGER NOT NULL,
    score_breakdown JSONB,
    status VARCHAR DEFAULT 'OPEN',
    profit_loss FLOAT DEFAULT 0.0,
    opened_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP
);

-- Create signals table
CREATE TABLE IF NOT EXISTS signals (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR NOT NULL,
    timeframe VARCHAR NOT NULL,
    signal_type VARCHAR NOT NULL,
    price FLOAT NOT NULL,
    stop_loss FLOAT NOT NULL,
    take_profit FLOAT NOT NULL,
    confluence_score INTEGER NOT NULL,
    score_breakdown JSONB,
    trend VARCHAR NOT NULL,
    poc_level FLOAT,
    was_executed BOOLEAN DEFAULT FALSE,
    trade_id INTEGER REFERENCES trades(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_trades_user_id ON trades(user_id);
CREATE INDEX IF NOT EXISTS idx_trades_status ON trades(status);
CREATE INDEX IF NOT EXISTS idx_signals_created_at ON signals(created_at);
