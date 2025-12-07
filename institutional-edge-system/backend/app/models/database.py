"""
============================================================================
Database Models - SQLAlchemy
============================================================================
"""

from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, JSON, Text, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()


class User(Base):
    """User model for authentication"""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    is_admin = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    bot_configs = relationship("BotConfig", back_populates="user")
    trades = relationship("Trade", back_populates="user")


class BotConfig(Base):
    """Bot configuration per user"""
    __tablename__ = "bot_configs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)

    # MT5 Configuration
    mt5_login = Column(String)
    mt5_server = Column(String)
    mt5_password_encrypted = Column(String)  # Encrypted

    # Trading Parameters
    symbol = Column(String, default="EURUSD")
    symbol_type = Column(String, default="forex")  # "forex" or "crypto"
    timeframe = Column(String, default="H1")
    risk_percent = Column(Float, default=2.0)
    min_confluence_score = Column(Integer, default=6)
    max_trades = Column(Integer, default=3)

    # Smart Money Settings
    swing_length = Column(Integer, default=10)
    ob_lookback = Column(Integer, default=50)
    fvg_min_size = Column(Float, default=0.3)
    vp_lookback = Column(Integer, default=100)

    # Strategy Selection (NEW)
    use_adx_filter = Column(Boolean, default=True)
    enable_vwap_strategy = Column(Boolean, default=True)
    enable_stoch_strategy = Column(Boolean, default=True)
    enable_institutional_strategy = Column(Boolean, default=True)
    enable_fibonacci_strategy = Column(Boolean, default=True)

    # Trade Management Settings
    be_trigger = Column(Float, default=1.0)  # R-multiple to move to BE
    trailing_sl = Column(Boolean, default=False)
    trailing_step = Column(Float, default=1.0)  # R-multiple for trailing step
    trailing_distance = Column(Float, default=1.5)  # R-multiple distance for TSL
    tsl_mode = Column(String, default="FIXED") # FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
    tsl_activation_r = Column(Float, default=0.0) # Profit R required to activate TSL
    tsl_atr_period = Column(Integer, default=14)
    tsl_atr_multiplier = Column(Float, default=1.5)
    
    # Chandelier Exit settings
    tsl_chandelier_period = Column(Integer, default=22)
    tsl_chandelier_mult = Column(Float, default=3.0)
    
    # Swing-based settings
    tsl_swing_lookback = Column(Integer, default=10)
    tsl_swing_buffer_atr = Column(Float, default=0.5)
    
    # Parabolic SAR settings  
    tsl_psar_af_start = Column(Float, default=0.02)
    tsl_psar_af_increment = Column(Float, default=0.02)
    tsl_psar_af_max = Column(Float, default=0.20)
    
    partial_tp_on = Column(Boolean, default=False)
    partial_tp_amount = Column(Float, default=0.5)  # 0.5 = 50%

    # Risk & Filters
    max_spread = Column(Float, default=2.0)  # Max spread in pips
    trading_hours_start = Column(String, default="00:00")
    trading_hours_end = Column(String, default="23:59")
    daily_loss_limit_percent = Column(Float, default=3.0)
    cooldown_minutes = Column(Integer, default=15)  # Cooldown between trades

    # Bot Status
    is_active = Column(Boolean, default=False)
    last_signal_time = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="bot_configs")
    risk_profile = relationship("RiskProfile", uselist=False, back_populates="bot_config", cascade="all, delete-orphan")


class RiskProfile(Base):
    """Advanced Risk Management Settings"""
    __tablename__ = "risk_profiles"

    id = Column(Integer, primary_key=True, index=True)
    bot_config_id = Column(Integer, ForeignKey("bot_configs.id"), nullable=False, unique=True)
    
    # Dynamic Risk
    volatility_adjustment = Column(Boolean, default=True)  # Reduce risk if ATR > 1.5x
    dd_protection = Column(Boolean, default=True)  # Halve risk if DD > 5%
    
    # Prop Firm Rules
    max_daily_loss = Column(Float, default=3.0)
    max_total_dd = Column(Float, default=10.0)
    profit_target = Column(Float, default=10.0)
    
    # State
    current_risk_per_trade = Column(Float, default=1.0)
    is_halted = Column(Boolean, default=False)
    halt_reason = Column(String, nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    bot_config = relationship("BotConfig", back_populates="risk_profile")


class Trade(Base):
    """Trade execution record"""
    __tablename__ = "trades"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    # Trade Details
    ticket = Column(Integer, unique=True, nullable=True)  # MT5 ticket
    symbol = Column(String, nullable=False)
    trade_type = Column(String, nullable=False)  # "BUY" or "SELL"

    # Prices
    entry_price = Column(Float, nullable=False)
    stop_loss = Column(Float, nullable=True)
    take_profit_1 = Column(Float, nullable=True)
    take_profit_2 = Column(Float, nullable=True)
    take_profit_3 = Column(Float, nullable=True)
    exit_price = Column(Float, nullable=True)

    # Volume & Risk
    volume = Column(Float, nullable=False)
    risk_percent = Column(Float, nullable=False)

    # Confluence Data
    confluence_score = Column(Integer, nullable=False)
    score_breakdown = Column(JSON, nullable=True)

    # Status
    status = Column(String, default="OPEN")  # OPEN, CLOSED, CANCELLED
    is_partially_closed = Column(Boolean, default=False)
    profit_loss = Column(Float, default=0.0)

    # Timestamps
    opened_at = Column(DateTime, default=datetime.utcnow)
    closed_at = Column(DateTime, nullable=True)

    # Relationships
    user = relationship("User", back_populates="trades")


class Signal(Base):
    """Trading signal history"""
    __tablename__ = "signals"

    id = Column(Integer, primary_key=True, index=True)

    # Signal Data
    symbol = Column(String, nullable=False)
    timeframe = Column(String, nullable=False)
    signal_type = Column(String, nullable=False)  # "BUY" or "SELL"

    # Prices
    price = Column(Float, nullable=False)
    stop_loss = Column(Float, nullable=False)
    take_profit = Column(Float, nullable=False)

    # Confluence
    confluence_score = Column(Integer, nullable=False)
    score_breakdown = Column(JSON, nullable=True)

    # AI Predictions
    ai_confidence = Column(Float, default=0.0)  # 0-100 confidence score
    ai_recommendation = Column(String, default="UNCERTAIN")  # STRONG_TAKE, TAKE, CAUTIOUS, SKIP, STRONG_SKIP

    # Market Context
    trend = Column(String, nullable=False)  # "BULLISH" or "BEARISH"
    poc_level = Column(Float, nullable=True)
    zone = Column(String, nullable=True)  # "PREMIUM" or "DISCOUNT"

    # Status
    status = Column(String, default="CREATED")  # CREATED, PENDING, ACTIVE, EXPIRED, CANCELLED, CLOSED
    was_executed = Column(Boolean, default=False)
    trade_id = Column(Integer, ForeignKey("trades.id"), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)


class PerformanceMetrics(Base):
    """Daily performance metrics"""
    __tablename__ = "performance_metrics"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    date = Column(DateTime, nullable=False)

    # Metrics
    total_trades = Column(Integer, default=0)
    winning_trades = Column(Integer, default=0)
    losing_trades = Column(Integer, default=0)
    win_rate = Column(Float, default=0.0)

    total_profit = Column(Float, default=0.0)
    total_loss = Column(Float, default=0.0)
    net_profit = Column(Float, default=0.0)

    largest_win = Column(Float, default=0.0)
    largest_loss = Column(Float, default=0.0)

    average_win = Column(Float, default=0.0)
    average_loss = Column(Float, default=0.0)
    profit_factor = Column(Float, default=0.0)

    created_at = Column(DateTime, default=datetime.utcnow)


class MarketRegime(Base):
    """Market Regime Detection History"""
    __tablename__ = "market_regimes"

    id = Column(Integer, primary_key=True, index=True)
    symbol = Column(String, nullable=False, index=True)
    timeframe = Column(String, nullable=False)
    
    regime_type = Column(String, nullable=False)  # TRENDING, RANGING, VOLATILE
    trend_direction = Column(String, nullable=True) # BULLISH, BEARISH, NEUTRAL
    volatility_level = Column(String, default="NORMAL") # LOW, NORMAL, HIGH, EXTREME
    
    details = Column(JSON, nullable=True)  # ADX, ATR values, etc.
    
    created_at = Column(DateTime, default=datetime.utcnow)


class NewsEvent(Base):
    """Economic Calendar Events"""
    __tablename__ = "news_events"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    country = Column(String, nullable=False)
    currency = Column(String, nullable=False)
    impact = Column(String, nullable=False)  # LOW, MEDIUM, HIGH
    
    forecast = Column(String, nullable=True)
    previous = Column(String, nullable=True)
    actual = Column(String, nullable=True)
    
    date = Column(DateTime, nullable=False, index=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)


class ExecutionLog(Base):
    """Detailed Execution Logs for Debugging & Audit"""
    __tablename__ = "execution_logs"

    id = Column(Integer, primary_key=True, index=True)
    trade_id = Column(Integer, ForeignKey("trades.id"), nullable=True)
    symbol = Column(String, nullable=False)
    action = Column(String, nullable=False) # OPEN, CLOSE, MODIFY, ERROR
    
    message = Column(String, nullable=False)
    details = Column(JSON, nullable=True)
    
    timestamp = Column(DateTime, default=datetime.utcnow)





class BacktestSession(Base):
    """Backtest Execution Session"""
    __tablename__ = "backtest_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True) # Optional for now
    
    # Configuration
    symbol = Column(String, nullable=False)
    timeframe = Column(String, nullable=False)
    start_date = Column(DateTime, nullable=False)
    end_date = Column(DateTime, nullable=False)
    initial_balance = Column(Float, nullable=False)
    strategy_config = Column(JSON, nullable=True) # Full config used
    
    # Results
    final_balance = Column(Float, nullable=True)
    total_trades = Column(Integer, default=0)
    win_rate = Column(Float, default=0.0)
    profit_factor = Column(Float, default=0.0)
    max_drawdown = Column(Float, default=0.0)
    net_profit = Column(Float, default=0.0)
    
    status = Column(String, default="RUNNING") # RUNNING, COMPLETED, FAILED
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    trades = relationship("BacktestTrade", back_populates="session", cascade="all, delete-orphan")


class BacktestTrade(Base):
    """Individual Trade in a Backtest"""
    __tablename__ = "backtest_trades"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("backtest_sessions.id"), nullable=False)
    
    symbol = Column(String, nullable=False)
    trade_type = Column(String, nullable=False) # BUY, SELL
    
    entry_time = Column(DateTime, nullable=False)
    exit_time = Column(DateTime, nullable=True)
    
    entry_price = Column(Float, nullable=False)
    exit_price = Column(Float, nullable=True)
    
    stop_loss = Column(Float, nullable=True)
    take_profit = Column(Float, nullable=True)
    
    volume = Column(Float, default=0.0)
    profit = Column(Float, default=0.0)
    balance_after = Column(Float, default=0.0) # Balance after this trade
    
    confluence_score = Column(Integer, default=0)
    
    session = relationship("BacktestSession", back_populates="trades")


