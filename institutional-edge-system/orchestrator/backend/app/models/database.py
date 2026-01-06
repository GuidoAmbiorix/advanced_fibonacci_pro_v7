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

# Many-to-Many Association Table
from sqlalchemy import Table
bot_config_accounts = Table(
    'bot_config_accounts', Base.metadata,
    Column('bot_config_id', Integer, ForeignKey('bot_configs.id')),
    Column('mt5_account_id', Integer, ForeignKey('mt5_accounts.id'))
)


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
    mt5_accounts = relationship("MT5Account", back_populates="user")


class MT5Account(Base):
    """MT5 trading account with prop firm rules"""
    __tablename__ = "mt5_accounts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    
    # Account identification
    name = Column(String, nullable=False)  # "FundedPips Demo", "HFM Live"
    login = Column(String, nullable=False)  # MT5 login number
    password_encrypted = Column(String, nullable=False)  # Fernet encrypted
    server = Column(String, nullable=False)  # "HFMarketsGlobal-Demo"
    
    # MT5 symbol configuration
    symbol_prefix = Column(String, default="")  # "#" for HFM crypto
    symbol_suffix = Column(String, default="")  # "m" for some brokers
    
    # Terminal Path (NEW for Multi-Account)
    terminal_path = Column(String, nullable=True) # Path to specific terminal64.exe folder
    
    # Account type
    account_type = Column(String, default="demo")  # "demo" | "live" | "prop"
    
    # FundedPips Prop Firm Rules
    max_drawdown_percent = Column(Float, default=8.0)   # 8% max total DD
    max_daily_dd_percent = Column(Float, default=3.0)   # 3% max daily DD
    starting_balance = Column(Float, default=0.0)       # Track from start
    daily_starting_balance = Column(Float, default=0.0) # Reset daily
    
    # Status
    is_active = Column(Boolean, default=False)  # Only ONE active at a time
    created_at = Column(DateTime, default=datetime.utcnow)
    last_connected = Column(DateTime, nullable=True)
    
    # Relationship
    # Relationship
    user = relationship("User", back_populates="mt5_accounts")
    bot_configs = relationship("BotConfig", secondary=bot_config_accounts, back_populates="accounts")


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

    # Trading Parameters - GOLD WINNING CONFIG
    symbol = Column(String, default="XAUUSD")  # Gold - best performer
    symbol_type = Column(String, default="forex")  # "forex" or "crypto"
    timeframe = Column(String, default="M5")  # M5 for Gold scalping
    risk_percent = Column(Float, default=0.001)  # 0.001% for Gold (critical)
    min_confluence_score = Column(Integer, default=5)  # Lower for more signals
    max_trades = Column(Integer, default=3)
    
    # Copy Trading Filters (NEW)
    excluded_symbols = Column(JSON, default=[]) # List of symbols to exclude (e.g. ["XAUUSD"])

    # Smart Money Settings
    swing_length = Column(Integer, default=10)
    ob_lookback = Column(Integer, default=50)
    fvg_min_size = Column(Float, default=0.3)
    vp_lookback = Column(Integer, default=100)

    # Strategy Selection - ALL ON for Gold
    use_adx_filter = Column(Boolean, default=False)  # OFF for Gold winning
    enable_vwap_strategy = Column(Boolean, default=True)
    enable_stoch_strategy = Column(Boolean, default=True)
    enable_institutional_strategy = Column(Boolean, default=True)
    enable_fibonacci_strategy = Column(Boolean, default=True)

    # RSI Settings (NEW)
    rsi_period = Column(Integer, default=14)
    rsi_overbought = Column(Integer, default=70)
    rsi_oversold = Column(Integer, default=30)

    # Trade Management Settings - GOLD WINNING
    be_trigger = Column(Float, default=1.0)  # R-multiple to move to BE
    trailing_sl = Column(Boolean, default=True)  # ON for Gold
    trailing_step = Column(Float, default=1.0)  # R-multiple for trailing step
    trailing_distance = Column(Float, default=1.5)  # R-multiple distance for TSL
    tsl_mode = Column(String, default="ATR")  # ATR recommended for Gold
    tsl_activation_r = Column(Float, default=0.0)  # Immediate activation
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
    # Partial TP - GOLD WINNING (100%)
    partial_tp_on = Column(Boolean, default=True)  # ON for Gold
    partial_tp_amount = Column(Float, default=1.0)  # 100% = full close at TP
    
    # Scalping Speed Settings - GOLD WINNING
    tp_ratio = Column(Float, default=2.0)  # Take Profit as R multiple (2.0 = 2R)
    sl_atr_multiplier = Column(Float, default=1.0)  # SL distance = ATR * multiplier
    max_trade_duration_hours = Column(Float, default=0.0)  # 0 = no limit

    # Risk & Filters
    max_spread = Column(Float, default=2.0)  # Max spread in pips
    trading_hours_start = Column(String, default="00:00")
    trading_hours_end = Column(String, default="23:59")
    daily_loss_limit_percent = Column(Float, default=3.0)
    cooldown_minutes = Column(Integer, default=15)  # Cooldown between trades

    # Bot Status
    is_active = Column(Boolean, default=False)
    last_signal_time = Column(DateTime, nullable=True)
    
    # Engine Configuration
    engine_type = Column(String, default="ADAPTIVE")
    engine_config = Column(JSON, default={})
    
    # Portfolio Synergy Settings (NEW)
    max_portfolio_risk_percent = Column(Float, default=4.0)  # Max combined risk across all slots
    max_positions_per_symbol = Column(Integer, default=2)    # Limit concurrent positions per symbol

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="bot_configs")
    risk_profile = relationship("RiskProfile", uselist=False, back_populates="bot_config", cascade="all, delete-orphan")
    slots = relationship("BotSlot", back_populates="bot_config", cascade="all, delete-orphan")
    accounts = relationship("MT5Account", secondary=bot_config_accounts, back_populates="bot_configs")


class BotSlot(Base):
    """Individual slot in a portfolio bot - each with independent configuration"""
    __tablename__ = "bot_slots"

    id = Column(Integer, primary_key=True, index=True)
    bot_config_id = Column(Integer, ForeignKey("bot_configs.id", ondelete="CASCADE"), nullable=False)
    enabled = Column(Boolean, default=True)
    
    # Symbol & Direction
    symbol = Column(String, nullable=False, default="EURJPY")
    direction_filter = Column(String, default="BOTH")  # BOTH, BUY_ONLY, SELL_ONLY
    
    # Engine Selection
    engine_type = Column(String, default="ADAPTIVE") # ADAPTIVE, GOLDEN
    engine_config = Column(JSON, default={}) # Flexible config for new engines
    
    # Timeframe (per-slot)
    timeframe = Column(String, default="M5")
    confirmation_timeframe = Column(String, nullable=True) # e.g. "H1", "H4"
    use_daily_bias = Column(Boolean, default=False) # Strict D1 Bias Filterif null
    
    # Session Control (Institutional) - v3.0 Killzones
    trading_session = Column(String, default="BOTH_KZ")  # LONDON_KZ, NY_KZ, OVERLAP_KZ, BOTH_KZ, ALL
    session_mode = Column(String, default="BOTH_KZ")  # Killzone mode for data-driven trading
    session_start_utc = Column(String, default="07:00")  # London Killzone start
    session_end_utc = Column(String, default="15:00")    # NY Killzone end
    session_end_action = Column(String, default="HOLD") # CLOSE, HOLD, DISABLE_NEW
    
    # Risk & TP/SL (v3.0: SL ATR 1.4)
    risk_percent = Column(Float, default=0.5)  # Conservative for Gold
    tp_ratio = Column(Float, default=2.0)      # 2R target
    sl_atr_multiplier = Column(Float, default=1.4)  # v3.0: Slightly tighter
    
    # MACD Parameters (v3.0: 6/18/9 for noise reduction)
    macd_fast = Column(Integer, default=6)
    macd_slow = Column(Integer, default=18)
    macd_signal = Column(Integer, default=9)
    
    # Strategies
    use_adx_filter = Column(Boolean, default=False)
    enable_vwap_strategy = Column(Boolean, default=True)
    enable_stoch_strategy = Column(Boolean, default=True)
    enable_institutional_strategy = Column(Boolean, default=True)
    enable_fibonacci_strategy = Column(Boolean, default=True)
    use_h1_trend_filter = Column(Boolean, default=False)
    
    # Stochastic & VWAP Specifics
    stoch_k_period = Column(Integer, default=14)
    stoch_d_period = Column(Integer, default=3)
    vwap_use_trend_filter = Column(Boolean, default=True) # Set False for Range
    
    # RSI
    rsi_period = Column(Integer, default=14)
    rsi_overbought = Column(Integer, default=70)
    rsi_oversold = Column(Integer, default=30)
    
    # ZigZag Structure (v3.0)
    zigzag_lookback = Column(Integer, default=12)
    
    # SMC v4.0 - Smart Money Concepts (UI Configurable)
    enable_order_blocks = Column(Boolean, default=True)
    ob_lookback = Column(Integer, default=20)
    enable_liquidity_sweep = Column(Boolean, default=True)
    sweep_lookback = Column(Integer, default=10)
    enable_fvg = Column(Boolean, default=True)
    fvg_min_size_atr = Column(Float, default=0.5)
    
    # Trailing Stop Loss (per-slot)
    enable_trailing_stop = Column(Boolean, default=True)
    tsl_mode = Column(String, default="TIERED")  # OFF, ATR, TIERED
    tsl_activation_r = Column(Float, default=0.0)
    
    # Partial Take Profit
    partial_tp_on = Column(Boolean, default=True)
    partial_tp_amount = Column(Float, default=1.0)
    
    # Scalping Settings
    max_trade_duration_hours = Column(Float, default=0.0)  # 0 = no limit
    min_confluence_score = Column(Integer, default=7)
    
    # MT5 Tracking
    magic_number = Column(Integer, unique=True, nullable=True)

    # TradingView Integration - Phase 3 & 4
    respect_user_zones = Column(Boolean, default=True)  # Respect user-drawn zones during trading
    daily_pnl = Column(Float, default=0.0)  # Quick stat for grid view
    last_signal_time = Column(DateTime, nullable=True)  # Quick stat for grid view
    last_trade_time = Column(DateTime, nullable=True)  # Quick stat for grid view

    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    bot_config = relationship("BotConfig", back_populates="slots")


class RiskProfile(Base):
    """Risk Management Settings"""
    __tablename__ = "risk_profiles"

    id = Column(Integer, primary_key=True, index=True)
    bot_config_id = Column(Integer, ForeignKey("bot_configs.id"), nullable=False, unique=True)
    
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

    # TradingView Integration - Phase 5 (Advanced Metrics)
    avg_trade_duration_hours = Column(Float, nullable=True)
    largest_win = Column(Float, nullable=True)
    largest_loss = Column(Float, nullable=True)
    consecutive_wins = Column(Integer, default=0)
    consecutive_losses = Column(Integer, default=0)

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


# ============================================================================
# TRADINGVIEW INTEGRATION - PHASE 3: USER ANNOTATIONS
# ============================================================================

class UserAnnotation(Base):
    """User-drawn zones, lines, and shapes on charts"""
    __tablename__ = "user_annotations"

    id = Column(Integer, primary_key=True, index=True)
    slot_id = Column(Integer, ForeignKey("bot_slots.id", ondelete="CASCADE"), nullable=False, index=True)

    # Annotation Type
    annotation_type = Column(String, nullable=False)  # 'horizontal_zone', 'trend_line', 'fibonacci', 'order_block'

    # Coordinates (stored as JSON for flexibility)
    coordinates = Column(JSON, nullable=False)
    # Example: {"high": 1.2150, "low": 1.2100, "startTime": 1234567890, "endTime": 1234567900}

    # Visual Properties
    label = Column(String(100), nullable=True)
    color = Column(String(20), default='#3B82F6')
    opacity = Column(Integer, default=30)  # 0-100
    notes = Column(Text, nullable=True)

    # Trading Behavior
    trade_action = Column(String(20), default='NEUTRAL')  # 'NEUTRAL', 'BUY_ONLY', 'SELL_ONLY', 'NO_TRADE'
    zone_type = Column(String(50), nullable=True)  # 'DEMAND', 'SUPPLY', 'ORDER_BLOCK', 'FVG', 'CUSTOM'

    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class AnnotationTemplate(Base):
    """Saved templates of annotation sets for reuse"""
    __tablename__ = "annotation_templates"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)  # Optional: for multi-user support

    template_name = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)

    # Template Data (array of annotations)
    annotations = Column(JSON, nullable=False)
    # Example: [{"type": "horizontal_zone", "coordinates": {...}, "properties": {...}}, ...]

    # Sharing
    is_public = Column(Boolean, default=False)  # Share with other users?
    use_count = Column(Integer, default=0)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# ============================================================================
# TRADINGVIEW INTEGRATION - PHASE 4: MULTI-SLOT GRID VIEW
# ============================================================================

class GridConfiguration(Base):
    """Saved grid layout configurations for multi-slot monitoring"""
    __tablename__ = "grid_configurations"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)

    name = Column(String(100), default='My Grid')

    # Grid Layout
    layout = Column(String(10), nullable=False)  # '2x2', '3x3', '4x4', '2x3'

    # Selected Slots (array of slot IDs)
    slot_ids = Column(JSON, nullable=False)
    # Example: [1, 2, 3, 4]

    # Display Settings
    show_stats = Column(Boolean, default=True)
    show_signals = Column(Boolean, default=True)
    auto_refresh_interval = Column(Integer, default=5)  # seconds

    # Metadata
    is_default = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# ============================================================================
# TRADINGVIEW INTEGRATION - PHASE 5: ADVANCED VISUALIZATIONS
# ============================================================================

class BacktestHeatmapData(Base):
    """Entry zone heatmap statistics for backtest analysis"""
    __tablename__ = "backtest_heatmap_data"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("backtest_sessions.id", ondelete="CASCADE"), nullable=False, index=True)

    # Price Bin
    price_low = Column(Float, nullable=False)
    price_high = Column(Float, nullable=False)
    bin_size = Column(Integer, nullable=False)  # in pips or points

    # Entry Statistics
    entry_count = Column(Integer, default=0)
    buy_count = Column(Integer, default=0)
    sell_count = Column(Integer, default=0)

    # Performance in This Zone
    total_pnl = Column(Float, default=0.0)
    win_count = Column(Integer, default=0)
    loss_count = Column(Integer, default=0)
    win_rate = Column(Float, default=0.0)
    avg_pnl = Column(Float, default=0.0)

    created_at = Column(DateTime, default=datetime.utcnow)


class StrategyComparison(Base):
    """Strategy comparison records for side-by-side analysis"""
    __tablename__ = "strategy_comparisons"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)

    # Sessions being compared (array of IDs)
    session_ids = Column(JSON, nullable=False)
    # Example: [123, 456]

    # Comparison Notes
    notes = Column(Text, nullable=True)
    insights = Column(Text, nullable=True)  # AI-generated or user-written insights

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)



# ============================================================================
# COPY TRADING SYSTEM MODELS
# ============================================================================

class CopyGroup(Base):
    """
    Defines a Master-Slave relationship group.
    One Master account can have multiple Slaves via CopyConfig.
    """
    __tablename__ = "copy_groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    description = Column(String, nullable=True)
    
    # The Master Account (Source of Signals)
    master_account_id = Column(Integer, ForeignKey("mt5_accounts.id"), nullable=False)
    
    # Group Settings
    is_active = Column(Boolean, default=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    master_account = relationship("MT5Account", foreign_keys=[master_account_id])
    slaves = relationship("CopyConfig", back_populates="group", cascade="all, delete-orphan")


class CopyConfig(Base):
    """
    Configuration for a specific Slave account inside a CopyGroup.
    Determines how the slave copies the master's trades.
    """
    __tablename__ = "copy_configs"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, ForeignKey("copy_groups.id"), nullable=False)
    
    # The Slave Account (Receiver of Signals)
    slave_account_id = Column(Integer, ForeignKey("mt5_accounts.id"), nullable=False)
    
    # Risk Management
    mode = Column(String, default="MULTIPLIER") # MULTIPLIER, FIXED_LOT, RISK_PERCENT
    risk_multiplier = Column(Float, default=1.0) # 1.0 = same risk as master
    fixed_lot_size = Column(Float, default=0.01) # If mode is FIXED_LOT
    max_risk_percent = Column(Float, default=5.0) # Safety cap
    
    # Filters
    include_symbols = Column(JSON, default=[]) # Empty = All
    exclude_symbols = Column(JSON, default=[])
    
    # Execution Modifiers
    slippage_tolerance_pips = Column(Float, default=3.0)
    reverse_copy = Column(Boolean, default=False) # For inverse trading
    
    # Status
    is_active = Column(Boolean, default=True)
    is_suspended = Column(Boolean, default=False) # Temp suspension due to drawdown etc.
    
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    group = relationship("CopyGroup", back_populates="slaves")
    slave_account = relationship("MT5Account", foreign_keys=[slave_account_id])
