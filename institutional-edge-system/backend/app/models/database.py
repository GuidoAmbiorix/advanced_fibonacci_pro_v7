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

    # Trade Management Settings
    be_trigger = Column(Float, default=1.0)  # R-multiple to move to BE
    trailing_sl = Column(Boolean, default=False)
    trailing_step = Column(Float, default=1.0)  # R-multiple for trailing step
    partial_tp_on = Column(Boolean, default=False)
    partial_tp_amount = Column(Float, default=0.5)  # 0.5 = 50%

    # Bot Status
    is_active = Column(Boolean, default=False)
    last_signal_time = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="bot_configs")


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
