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

    def close(self, exit_time: datetime, exit_price: float, exit_reason: str):
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

        # P&L in pips (for EURUSD, 1 pip = 0.0001)
        self.pnl_pips = price_diff / 0.0001

        # P&L in currency (Forex: lots * 100,000 * price_diff)
        # Use current volume (may be 50% if partial TP was taken)
        self.pnl = self.volume * 100000 * price_diff
        
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


@dataclass
class BacktestConfig:
    """Configuration for backtest"""

    # Account
    initial_balance: float = 10000.0

    # Symbol
    symbol: str = "EURUSD"
    timeframe: str = "H1"

    # Strategy parameters
    min_confluence_score: int = 7
    risk_percent: float = 1.0
    max_trades: int = 1

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
    enable_vwap_strategy: bool = True  # Enable VWAP Scalping
    enable_stoch_strategy: bool = True  # Enable Stochastic Momentum
    enable_institutional_strategy: bool = True  # Enable Liquidity Sweeps & Order Flow
    
    # Trailing Stop Loss Settings
    tsl_mode: str = "TIERED"  # FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
    tsl_activation_r: float = 0.0  # R-profit required to activate trailing


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
