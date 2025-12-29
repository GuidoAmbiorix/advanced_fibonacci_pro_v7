"""
Data Models for Backtesting
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, List, Dict


@dataclass
class BacktestTrade:
    """Represents a trade in backtest"""
    entry_time: datetime
    entry_price: float
    signal_type: str  # "BUY" or "SELL"
    volume: float
    stop_loss: float
    take_profit: float
    initial_stop_loss: Optional[float] = None  # Original SL for R calculation

    # Filled on exit
    exit_time: Optional[datetime] = None
    exit_price: Optional[float] = None
    exit_reason: str = ""  # "SL", "TP", "MANUAL"

    # P&L
    pnl: float = 0.0
    pnl_pips: float = 0.0
    pnl_pips: float = 0.0
    return_r: float = 0.0  # Return in R multiples
    balance_after: float = 0.0  # Balance after this trade

    # Trade details
    ticket: int = 0
    symbol: str = "EURUSD"
    confluence_score: int = 0
    commission: float = 0.0
    slippage_pips: float = 0.0
    risk_percent: float = 1.0  # Risk % used for this trade (for portfolio tracking)

    # Partial TP (NEW - for 80%+ WR scalping)
    partial_tp_taken: bool = False  # Has fast TP1 been taken?
    partial_tp_pnl: float = 0.0  # PnL from partial close
    original_volume: float = 0.0  # Original volume before partial close

    # Status
    status: str = "OPEN"  # "OPEN", "CLOSED"

    def __post_init__(self):
        """Calculate initial values"""
        if self.ticket == 0:
            self.ticket = id(self)  # Use object id as ticket

        # Store initial SL if not set
        if self.initial_stop_loss is None:
            self.initial_stop_loss = self.stop_loss

    def close(self, exit_time: datetime, exit_price: float, exit_reason: str, pip_size: float = 0.0001, pip_value: float = 10.0):
        """Close the trade and calculate P&L"""
        self.exit_time = exit_time
        self.exit_price = exit_price
        self.exit_reason = exit_reason
        self.status = "CLOSED"

        # Calculate P&L
        if self.signal_type == "BUY":
            price_diff = exit_price - self.entry_price
        else:  # SELL
            price_diff = self.entry_price - exit_price

        # P&L in pips
        self.pnl_pips = price_diff / pip_size if pip_size > 0 else 0

        # P&L in currency
        # Formula: (Price Diff / Pip Size) * Pip Value * Volume
        self.pnl = self.pnl_pips * pip_value * self.volume
        
        # Add partial TP PnL if it was taken (50% closed at +0.5R)
        if self.partial_tp_taken and self.partial_tp_pnl > 0:
            self.pnl += self.partial_tp_pnl

        # Subtract commission
        self.pnl -= self.commission

        # Calculate R multiple (use INITIAL SL for accurate R calculation)
        initial_sl_distance = abs(self.entry_price - self.initial_stop_loss)
        if initial_sl_distance > 0:
            self.return_r = price_diff / initial_sl_distance

    def update_open_pnl(self, current_price: float):
        """Update P&L for open position"""
        if self.status != "OPEN":
            return

        if self.signal_type == "BUY":
            price_diff = current_price - self.entry_price
        else:
            price_diff = self.entry_price - current_price

        self.pnl_pips = price_diff / 0.0001
        self.pnl = self.volume * 100000 * price_diff


@dataclass
class BacktestMetrics:
    """Performance metrics from backtest"""

    # Basic stats
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    break_even_trades: int = 0

    # Win/Loss
    win_rate: float = 0.0
    loss_rate: float = 0.0

    # P&L
    total_profit: float = 0.0
    total_loss: float = 0.0
    net_profit: float = 0.0
    profit_factor: float = 0.0

    # Average
    average_win: float = 0.0
    average_loss: float = 0.0
    average_rr: float = 0.0

    # Drawdown
    max_drawdown: float = 0.0
    max_drawdown_percent: float = 0.0
    max_consecutive_wins: int = 0
    max_consecutive_losses: int = 0

    # Risk-adjusted
    sharpe_ratio: float = 0.0
    sortino_ratio: float = 0.0
    calmar_ratio: float = 0.0

    # Expectancy
    expectancy: float = 0.0  # Per trade in $
    expectancy_r: float = 0.0  # Per trade in R multiples

    # Distribution
    best_trade: float = 0.0
    worst_trade: float = 0.0
    median_trade: float = 0.0

    # Time
    avg_trade_duration_hours: float = 0.0
    total_trades_per_month: float = 0.0

    # Additional
    recovery_factor: float = 0.0  # Net profit / max DD
    payoff_ratio: float = 0.0  # Avg win / Avg loss

    # =========================================================================
    # ENHANCED QUANTITATIVE METRICS (from Dr. Chan's book)
    # =========================================================================
    
    # CAGR - Compound Annual Growth Rate
    cagr: float = 0.0  # Annual compounded return percentage
    
    # Omega Ratio - Probability-weighted ratio of gains vs losses
    omega_ratio: float = 0.0  # Higher is better. > 1 = profitable
    
    # Max Drawdown Duration (critical for risk management)
    max_drawdown_duration_days: float = 0.0  # How long in max DD
    avg_drawdown_duration_days: float = 0.0  # Average DD recovery time
    
    # Kelly Criterion optimal fraction
    kelly_fraction: float = 0.0  # Optimal f* based on trade history
    half_kelly: float = 0.0  # Recommended conservative Kelly
    
    # Mar Ratio (similar to Calmar but uses max DD $)
    mar_ratio: float = 0.0  
    
    # Ulcer Index (measures downside volatility)
    ulcer_index: float = 0.0
    
    # Tail Ratio (measures tail risk)
    tail_ratio: float = 0.0  # 95th percentile / 5th percentile



@dataclass
class SlotConfig:
    """Configuration for a single slot in multi-slot backtesting - FULL INDEPENDENCE"""
    slot_number: int = 1  # 1, 2, 3, 4
    enabled: bool = True
    
    # Symbol & Direction
    symbol: str = "GBPJPY"
    direction_filter: str = "BOTH"  # BOTH, BUY_ONLY, SELL_ONLY
    
    # Timeframe (per-slot)
    timeframe: str = "M5"
    confirmation_timeframe: Optional[str] = None
    
    # Risk & TP/SL
    risk_percent: float = 1.0
    tp_ratio: float = 1.5
    sl_atr_multiplier: float = 1.5
    
    # Strategies
    use_adx_filter: bool = False
    enable_vwap_strategy: bool = True
    enable_stoch_strategy: bool = True
    enable_institutional_strategy: bool = True
    enable_fibonacci_strategy: bool = True
    
    # RSI
    rsi_period: int = 14
    rsi_overbought: int = 70
    rsi_oversold: int = 30
    
    # Trailing Stop Loss
    enable_trailing_stop: bool = True
    tsl_mode: str = "TIERED"  # OFF, ATR, TIERED
    tsl_activation_r: float = 0.0
    
    # Partial Take Profit
    partial_tp_on: bool = True
    partial_tp_amount: float = 1.0
    
    # Scalping Settings
    max_trade_duration_hours: float = 0.0
    min_confluence_score: int = 7
    
    # MT5 Tracking
    magic_number: Optional[int] = None
    
    # Institutional Bias
    use_daily_bias: bool = False


@dataclass
class BacktestConfig:
    """Configuration for backtest"""

    # Account
    initial_balance: float = 10000.0

    # Symbol & Timeframe
    symbol: str = "EURUSD"
    timeframe: str = "H1"  # Execution timeframe (M1, M5, M15, H1, H4, D1)
    confirmation_timeframe: str = "H4"  # HTF for trend confirmation (should be higher than timeframe)

    # Strategy parameters
    min_confluence_score: int = 7
    risk_percent: float = 1.0
    max_trades: int = 1
    direction_filter: str = "BOTH"  # "BOTH", "BUY_ONLY", "SELL_ONLY"
    use_daily_bias: bool = False

    # Engine Config
    engine_type: str = "ADAPTIVE"
    engine_config: Dict = field(default_factory=dict)

    # Trading engine config
    swing_length: int = 10
    ob_lookback: int = 50
    fvg_min_size: float = 0.3
    vp_lookback: int = 100

    # Execution
    slippage_pips: float = 1.0
    commission_per_lot: float = 7.0  # $7 per lot roundtrip

    # Time period
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None

    # Advanced
    enable_trailing_stop: bool = False
    partial_tp_on: bool = False
    partial_tp_amount: float = 0.5
    scalping_mode: bool = False  # Enable high frequency scalping
    use_compounding: bool = False  # False = use initial_balance for sizing (realistic), True = use current balance (exponential growth)
    
    # Scalping TP/SL Configuration (for faster trades)
    tp_ratio: float = 1.5  # Take Profit as multiple of risk (1.5 = 1.5R). Use 1.0 for scalping
    sl_atr_multiplier: float = 1.5  # SL distance = ATR * multiplier. Use 1.0 for tighter stops
    max_trade_duration_hours: float = 0.0  # Force close after X hours. 0 = disabled. Use 0.5-2 for scalping
    
    use_adx_filter: bool = True  # Enable ADX Trend Filter
    enable_vwap_strategy: bool = True  # Enable VWAP Scalping
    enable_stoch_strategy: bool = True  # Enable Stochastic Momentum
    enable_institutional_strategy: bool = True  # Enable Liquidity Sweeps & Order Flow
    enable_fibonacci_strategy: bool = True  # Enable Fibonacci Golden Zone Scalping
    enable_strategy_3_29_162: bool = True  # Enable SQ Strategy 3.29.162
    
    # RSI Settings
    rsi_period: int = 14
    rsi_overbought: int = 70
    rsi_oversold: int = 30
    
    # Trailing Stop Loss Settings
    tsl_mode: str = "TIERED"  # FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
    tsl_activation_r: float = 0.0  # R-profit required to activate trailing
    
    # Advanced TSL Parameters
    tsl_atr_period: int = 14
    tsl_atr_multiplier: float = 1.5
    tsl_chandelier_period: int = 22
    tsl_chandelier_mult: float = 3.0
    tsl_swing_lookback: int = 10
    tsl_swing_buffer_atr: float = 0.5
    tsl_psar_af_start: float = 0.02
    tsl_psar_af_increment: float = 0.02
    tsl_psar_af_max: float = 0.20
    
    # Drawdown Protection
    max_drawdown_percent: float = 15.0  # Stop trading if drawdown exceeds 15%
    
    # PORTFOLIO MULTI-SLOT CONFIGURATION (NEW)
    slots: List[SlotConfig] = field(default_factory=list)  # List of slot configs
    max_portfolio_risk_percent: float = 4.0  # Max combined risk across all slots
    max_positions_per_symbol: int = 2  # Limit concurrent positions per symbol


@dataclass
class BacktestResults:
    """Complete results from backtest run"""

    config: BacktestConfig
    metrics: BacktestMetrics
    trades: List[BacktestTrade] = field(default_factory=list)
    equity_curve: List[Dict] = field(default_factory=list)

    # Metadata
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    total_bars: int = 0
    execution_time_seconds: float = 0.0

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON export"""
        return {
            'config': self.config.__dict__,
            'metrics': self.metrics.__dict__,
            'trades_count': len(self.trades),
            'start_date': self.start_date.isoformat() if self.start_date else None,
            'end_date': self.end_date.isoformat() if self.end_date else None,
            'total_bars': self.total_bars,
            'execution_time': self.execution_time_seconds
        }
