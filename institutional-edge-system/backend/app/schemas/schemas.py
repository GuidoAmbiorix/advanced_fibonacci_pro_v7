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
    be_trigger: float = Field(default=1.0, ge=0.5, le=5.0)
    trailing_sl: bool = False
    trailing_step: float = Field(default=1.0, ge=0.5, le=5.0)
    trailing_distance: float = Field(default=1.5, ge=0.5, le=5.0)
    tsl_mode: str = "FIXED"
    tsl_activation_r: float = Field(default=0.0, ge=0.0, le=10.0)
    tsl_atr_period: int = Field(default=14, ge=1, le=50)
    tsl_atr_multiplier: float = Field(default=1.5, ge=0.1, le=5.0)
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
    be_trigger: Optional[float] = Field(default=None, ge=0.5, le=5.0)
    trailing_sl: Optional[bool] = None
    trailing_step: Optional[float] = Field(default=None, ge=0.5, le=5.0)
    trailing_distance: Optional[float] = Field(default=None, ge=0.5, le=5.0)
    tsl_mode: Optional[str] = None
    tsl_activation_r: Optional[float] = Field(default=None, ge=0.0, le=10.0)
    tsl_atr_period: Optional[int] = Field(default=None, ge=1, le=50)
    tsl_atr_multiplier: Optional[float] = Field(default=None, ge=0.1, le=5.0)
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
