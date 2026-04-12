"""
============================================================================
Pydantic Schemas for API Request/Response Validation
============================================================================
"""

from pydantic import BaseModel, EmailStr, Field
from typing import Optional, List, Dict, Any
from datetime import datetime


# ============================================================================
# USER SCHEMAS
# ============================================================================

class UserCreate(BaseModel):
    email: EmailStr
    username: str
    password: str


class UserLogin(BaseModel):
    username: str
    password: str


class SystemInfoSchema(BaseModel):
    max_drawdown: float
    max_daily_loss: float
    symbol_suffix: str
    symbol_prefix: str
    account_type: str
    instance_role: str


class UserResponse(BaseModel):
    id: int
    email: str
    username: str
    is_active: bool
    is_admin: bool
    created_at: datetime

    class Config:
        from_attributes = True


class Token(BaseModel):
    access_token: str
    token_type: str
    user_id: Optional[int] = None
    username: Optional[str] = None


# ============================================================================
# BOT CONFIG SCHEMAS
# ============================================================================

class BotConfigCreate(BaseModel):
    user_id: int
    name: str
    mt5_login: Optional[str] = None
    mt5_server: Optional[str] = None
    mt5_password: Optional[str] = None
    symbol: str = "EURUSD"
    symbol_type: str = "forex"
    timeframe: str = "H1"
    risk_percent: float = Field(default=2.0, ge=0.5, le=5.0)
    min_confluence_score: int = Field(default=6, ge=3, le=10)
    max_trades: int = Field(default=3, ge=1, le=10)
    swing_length: int = Field(default=10, ge=5, le=20)
    ob_lookback: int = Field(default=50, ge=10, le=100)
    fvg_min_size: float = Field(default=0.3, ge=0.1, le=2.0)
    vp_lookback: int = Field(default=100, ge=20, le=500)
    use_adx_filter: bool = True
    enable_vwap_strategy: bool = True
    enable_stoch_strategy: bool = True
    enable_institutional_strategy: bool = True
    enable_fibonacci_strategy: bool = True
    rsi_period: int = Field(default=14, ge=2, le=50)
    rsi_overbought: int = Field(default=70, ge=50, le=95)
    rsi_oversold: int = Field(default=30, ge=5, le=50)
    be_trigger: float = Field(default=1.0, ge=0.5, le=5.0)
    trailing_sl: bool = False
    trailing_step: float = Field(default=1.0, ge=0.5, le=5.0)
    trailing_distance: float = Field(default=1.5, ge=0.5, le=5.0)
    tsl_mode: str = "FIXED"
    tsl_activation_r: float = Field(default=0.0, ge=0.0, le=10.0)
    tsl_atr_period: int = Field(default=14, ge=1, le=50)
    tsl_atr_multiplier: float = Field(default=1.5, ge=0.1, le=5.0)
    tsl_chandelier_period: Optional[int] = Field(default=22, ge=1, le=50)
    tsl_chandelier_mult: Optional[float] = Field(default=3.0, ge=0.1, le=10.0)
    tsl_swing_lookback: Optional[int] = Field(default=10, ge=2, le=50)
    tsl_swing_buffer_atr: Optional[float] = Field(default=0.5, ge=0.1, le=5.0)
    tsl_psar_af_start: Optional[float] = Field(default=0.02, ge=0.001, le=0.5)
    tsl_psar_af_increment: Optional[float] = Field(default=0.02, ge=0.001, le=0.5)
    tsl_psar_af_max: Optional[float] = Field(default=0.20, ge=0.01, le=1.0)
    partial_tp_on: bool = False
    partial_tp_amount: float = Field(default=0.5, ge=0.1, le=1.0)
    max_spread: float = Field(default=2.0, ge=0.1, le=10.0)
    trading_hours_start: str = "00:00"
    trading_hours_end: str = "23:59"
    daily_loss_limit_percent: float = Field(default=3.0, ge=0.5, le=10.0)


class BotConfigUpdate(BaseModel):
    name: Optional[str] = None
    symbol: Optional[str] = None
    timeframe: Optional[str] = None
    risk_percent: Optional[float] = Field(default=None, ge=0.5, le=5.0)
    min_confluence_score: Optional[int] = Field(default=None, ge=3, le=10)
    max_trades: Optional[int] = Field(default=None, ge=1, le=10)
    use_adx_filter: Optional[bool] = None
    enable_vwap_strategy: Optional[bool] = None
    enable_stoch_strategy: Optional[bool] = None
    enable_institutional_strategy: Optional[bool] = None
    enable_fibonacci_strategy: Optional[bool] = None
    rsi_period: Optional[int] = Field(default=None, ge=2, le=50)
    rsi_overbought: Optional[int] = Field(default=None, ge=50, le=95)
    rsi_oversold: Optional[int] = Field(default=None, ge=5, le=50)
    be_trigger: Optional[float] = Field(default=None, ge=0.5, le=5.0)
    trailing_sl: Optional[bool] = None
    trailing_step: Optional[float] = Field(default=None, ge=0.5, le=5.0)
    trailing_distance: Optional[float] = Field(default=None, ge=0.5, le=5.0)
    tsl_mode: Optional[str] = None
    tsl_activation_r: Optional[float] = Field(default=None, ge=0.0, le=10.0)
    tsl_atr_period: Optional[int] = Field(default=None, ge=1, le=50)
    tsl_atr_multiplier: Optional[float] = Field(default=None, ge=0.1, le=5.0)
    tsl_chandelier_period: Optional[int] = Field(default=None, ge=1, le=50)
    tsl_chandelier_mult: Optional[float] = Field(default=None, ge=0.1, le=10.0)
    tsl_swing_lookback: Optional[int] = Field(default=None, ge=2, le=50)
    tsl_swing_buffer_atr: Optional[float] = Field(default=None, ge=0.1, le=5.0)
    tsl_psar_af_start: Optional[float] = Field(default=None, ge=0.001, le=0.5)
    tsl_psar_af_increment: Optional[float] = Field(default=None, ge=0.001, le=0.5)
    tsl_psar_af_max: Optional[float] = Field(default=None, ge=0.01, le=1.0)
    partial_tp_on: Optional[bool] = None
    partial_tp_amount: Optional[float] = Field(default=None, ge=0.1, le=1.0)
    max_spread: Optional[float] = Field(default=None, ge=0.1, le=10.0)
    trading_hours_start: Optional[str] = None
    trading_hours_end: Optional[str] = None
    daily_loss_limit_percent: Optional[float] = Field(default=None, ge=0.5, le=10.0)
    is_active: Optional[bool] = None


class BotConfigResponse(BaseModel):
    id: int
    user_id: int
    name: str
    symbol: str
    timeframe: str
    risk_percent: float
    min_confluence_score: int
    max_trades: int
    use_adx_filter: bool
    enable_vwap_strategy: bool
    enable_stoch_strategy: bool
    enable_institutional_strategy: bool
    enable_fibonacci_strategy: bool
    rsi_period: int
    rsi_overbought: int
    rsi_oversold: int
    be_trigger: float
    trailing_sl: bool
    trailing_step: float
    trailing_distance: float
    tsl_mode: str
    tsl_activation_r: float
    tsl_atr_period: int
    tsl_atr_multiplier: float
    partial_tp_on: bool
    partial_tp_amount: float
    max_spread: float
    trading_hours_start: str
    trading_hours_end: str
    daily_loss_limit_percent: float
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class RiskProfile(BaseModel):
    id: int
    bot_config_id: int
    max_daily_loss: float
    max_total_dd: float
    profit_target: float
    current_risk_per_trade: float
    is_halted: bool
    halt_reason: Optional[str] = None
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# TRADING SIGNAL SCHEMAS
# ============================================================================

class SignalResponse(BaseModel):
    signal_type: str  # "BUY" or "SELL"
    entry_price: float
    stop_loss: float
    take_profit_1: float
    take_profit_2: float
    take_profit_3: float
    confluence_score: int
    score_breakdown: Dict[str, int]
    timestamp: datetime
    symbol: str
    timeframe: str
    risk_reward_ratio: float
    fib_level: Optional[str] = None
    fib_zone: Optional[str] = None


class AnalysisResponse(BaseModel):
    timestamp: datetime
    current_price: float
    trend: str
    active_order_blocks: int
    active_fvgs: int
    poc_level: Optional[float]
    vah_level: Optional[float]
    val_level: Optional[float]
    bull_confluence_score: int
    bear_confluence_score: int
    bull_score_breakdown: Dict[str, int]
    bear_score_breakdown: Dict[str, int]
    signals: List[SignalResponse]
    premium_discount: Dict[str, Any]


class OHLCVResponse(BaseModel):
    symbol: str
    timeframe: str
    data: List[Dict[str, Any]]  # List of {time, open, high, low, close, volume}


# ============================================================================
# TRADE SCHEMAS
# ============================================================================

class TradeCreate(BaseModel):
    symbol: str
    trade_type: str  # "BUY" or "SELL"
    entry_price: Optional[float] = None  # Optional - will be filled by MT5 execution
    stop_loss: float
    take_profit_1: Optional[float] = None
    take_profit_2: Optional[float] = None
    take_profit_3: Optional[float] = None
    volume: float
    risk_percent: float
    confluence_score: int
    score_breakdown: Optional[Dict] = None


class TradeResponse(BaseModel):
    id: int
    ticket: Optional[int]
    symbol: str
    trade_type: str
    entry_price: float
    stop_loss: Optional[float]
    take_profit_1: Optional[float]
    exit_price: Optional[float]
    volume: float
    confluence_score: int
    status: str
    is_partially_closed: bool
    profit_loss: float
    opened_at: datetime
    closed_at: Optional[datetime]

    class Config:
        from_attributes = True


# ============================================================================
# BOT CONTROL SCHEMAS
# ============================================================================

class BotStartRequest(BaseModel):
    bot_config_id: int


class BotStopRequest(BaseModel):
    bot_config_id: int


class BotStatusResponse(BaseModel):
    bot_config_id: int
    is_active: bool
    is_running: bool
    symbol: str
    timeframe: str
    current_price: Optional[float]
    open_positions: int
    total_trades_today: int
    pnl_today: float
    last_signal_time: Optional[datetime]


# ============================================================================
# ACCOUNT INFO SCHEMAS
# ============================================================================

class AccountInfoResponse(BaseModel):
    login: int
    balance: float
    equity: float
    margin: float
    margin_free: float
    profit: float
    currency: str
    leverage: int


# ============================================================================
# PERFORMANCE METRICS SCHEMAS
# ============================================================================

class PerformanceMetricsResponse(BaseModel):
    date: datetime
    total_trades: int
    winning_trades: int
    losing_trades: int
    win_rate: float
    net_profit: float
    profit_factor: float
    largest_win: float
    largest_loss: float

    class Config:
        from_attributes = True


# ============================================================================
# WEBSOCKET SCHEMAS
# ============================================================================

class WebSocketMessage(BaseModel):
    type: str  # "price_update", "signal", "trade_update", "error"
    data: Dict
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ============================================================================
# TRADINGVIEW INTEGRATION - PHASE 3: USER ANNOTATIONS
# ============================================================================

class AnnotationCoordinates(BaseModel):
    """Coordinates for different annotation types"""
    high: Optional[float] = None
    low: Optional[float] = None
    startTime: Optional[int] = None  # Unix timestamp
    endTime: Optional[int] = None    # Unix timestamp
    # For trend lines
    x1: Optional[float] = None
    y1: Optional[float] = None
    x2: Optional[float] = None
    y2: Optional[float] = None


class AnnotationCreate(BaseModel):
    slot_id: int
    annotation_type: str  # 'horizontal_zone', 'trend_line', 'fibonacci', 'order_block'
    coordinates: Dict[str, Any]
    label: Optional[str] = None
    color: str = '#3B82F6'
    opacity: int = Field(default=30, ge=0, le=100)
    notes: Optional[str] = None
    trade_action: str = 'NEUTRAL'  # 'NEUTRAL', 'BUY_ONLY', 'SELL_ONLY', 'NO_TRADE'
    zone_type: Optional[str] = None  # 'DEMAND', 'SUPPLY', 'ORDER_BLOCK', 'FVG', 'CUSTOM'


class AnnotationUpdate(BaseModel):
    label: Optional[str] = None
    color: Optional[str] = None
    opacity: Optional[int] = Field(default=None, ge=0, le=100)
    notes: Optional[str] = None
    trade_action: Optional[str] = None
    zone_type: Optional[str] = None
    coordinates: Optional[Dict[str, Any]] = None


class AnnotationResponse(BaseModel):
    id: int
    slot_id: int
    annotation_type: str
    coordinates: Dict[str, Any]
    label: Optional[str]
    color: str
    opacity: int
    notes: Optional[str]
    trade_action: str
    zone_type: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TemplateCreate(BaseModel):
    template_name: str
    description: Optional[str] = None
    annotations: List[Dict[str, Any]]  # Array of annotation objects
    is_public: bool = False


class TemplateResponse(BaseModel):
    id: int
    user_id: Optional[int]
    template_name: str
    description: Optional[str]
    annotations: List[Dict[str, Any]]
    is_public: bool
    use_count: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# TRADINGVIEW INTEGRATION - PHASE 4: MULTI-SLOT GRID VIEW
# ============================================================================

class GridConfigCreate(BaseModel):
    name: str = 'My Grid'
    layout: str  # '2x2', '3x3', '4x4', '2x3'
    slot_ids: List[int]
    show_stats: bool = True
    show_signals: bool = True
    auto_refresh_interval: int = Field(default=5, ge=1, le=60)


class GridConfigUpdate(BaseModel):
    name: Optional[str] = None
    layout: Optional[str] = None
    slot_ids: Optional[List[int]] = None
    show_stats: Optional[bool] = None
    show_signals: Optional[bool] = None
    auto_refresh_interval: Optional[int] = Field(default=None, ge=1, le=60)
    is_default: Optional[bool] = None


class GridConfigResponse(BaseModel):
    id: int
    user_id: Optional[int]
    name: str
    layout: str
    slot_ids: List[int]
    show_stats: bool
    show_signals: bool
    auto_refresh_interval: int
    is_default: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SlotQuickStats(BaseModel):
    """Quick statistics for mini slot cards in grid view"""
    slot_id: int
    symbol: str
    timeframe: str
    status: str  # 'ACTIVE', 'PAUSED', 'ERROR'
    latest_price: Optional[float] = None
    daily_pnl: float = 0.0
    total_trades: int = 0
    active_signal: Optional[Dict[str, Any]] = None


# ============================================================================
# TRADINGVIEW INTEGRATION - PHASE 5: ADVANCED VISUALIZATIONS
# ============================================================================

class HeatmapBinData(BaseModel):
    """Single price bin in heatmap"""
    price_low: float
    price_high: float
    price_range: str  # "1.2100-1.2120"
    entry_count: int
    buy_count: int
    sell_count: int
    total_pnl: float
    win_count: int
    loss_count: int
    win_rate: float
    avg_pnl: float


class HeatmapResponse(BaseModel):
    """Complete heatmap data for a backtest session"""
    session_id: int
    bins: List[HeatmapBinData]
    bin_size: int
    total_entries: int
    most_active_zone: HeatmapBinData
    best_win_rate_zone: HeatmapBinData


class ComparisonCreate(BaseModel):
    name: str
    description: Optional[str] = None
    session_ids: List[int]  # IDs of backtest sessions to compare
    notes: Optional[str] = None


class ComparisonMetric(BaseModel):
    """Single metric comparison between strategies"""
    metric_name: str
    strategy_a_value: float
    strategy_b_value: float
    difference: float
    winner: str  # 'A', 'B', or 'TIE'


class ComparisonResponse(BaseModel):
    id: int
    name: str
    description: Optional[str]
    session_ids: List[int]
    metrics: List[ComparisonMetric]
    notes: Optional[str]
    insights: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class EquityCurvePoint(BaseModel):
    """Single point in equity curve"""
    time: int  # Unix timestamp
    balance: float
    drawdown_percent: float


class BacktestPlaybackData(BaseModel):
    """Complete data for backtest playback visualization"""
    session_id: int
    symbol: str
    timeframe: str
    start_date: datetime
    end_date: datetime
    initial_balance: float

    # Candle data
    candles: List[Dict[str, Any]]  # OHLCV data

    # Equity curve
    equity_curve: List[EquityCurvePoint]

    # Trades with timing
    trades: List[Dict[str, Any]]

    # Live metrics during playback
    metrics: Dict[str, Any]


class TradeDistribution(BaseModel):
    """Trade distribution statistics"""
    by_hour: Dict[int, Dict[str, int]]  # Hour -> {wins, losses}
    by_day: Dict[str, Dict[str, int]]   # Day name -> {wins, losses}
    pnl_histogram: List[Dict[str, Any]] # [{range: "-100 to -50", count: 5}, ...]
