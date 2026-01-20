"""
Portfolio Governor
Central brain for multi-symbol portfolio risk management.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple, Any
from datetime import datetime
import yaml

from .metrics import calculate_profit_factor, calculate_max_drawdown
from .correlation import CorrelationManager
from .exposure import ExposureTracker


@dataclass
class Trade:
    """Completed trade record."""
    symbol: str
    direction: int
    entry_price: float
    exit_price: float
    entry_time: datetime
    exit_time: datetime
    profit: float
    profit_r: float
    risk_percent: float


@dataclass
class PortfolioState:
    """Current portfolio state."""
    equity: float
    peak_equity: float
    current_dd: float
    total_exposure: float
    rolling_pf: float
    risk_multiplier: float
    trading_enabled: bool
    positions_count: int
    group_exposures: Dict[str, float] = field(default_factory=dict)


class PortfolioGovernor:
    """
    Central portfolio risk management brain.
    
    Responsibilities:
    - Track total exposure across symbols
    - Calculate and respond to drawdown
    - Calculate rolling profit factor
    - Manage correlation group limits
    - Approve or deny trade requests
    """
    
    def __init__(self, config_path: str = 'config/portfolio.yaml'):
        """
        Initialize governor with configuration.
        
        Args:
            config_path: Path to portfolio configuration YAML
        """
        self.config = self._load_config(config_path)
        
        # Initialize managers
        self.correlation = CorrelationManager()
        self.exposure = ExposureTracker()
        
        # State
        self.equity = 10000.0  # Default starting equity
        self.peak_equity = 10000.0
        self.trades: List[Trade] = []
        self.current_state: Optional[PortfolioState] = None
        
        # Load config values
        self._load_settings()
    
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from YAML."""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            return self._default_config()
    
    def _default_config(self) -> Dict[str, Any]:
        """Default configuration if file not found."""
        return {
            'portfolio': {
                'max_total_exposure': 2.0,
                'max_symbol_exposure': 0.6,
                'max_group_exposure': 1.0,
                'max_positions': 6,
                'max_positions_per_symbol': 3,
            },
            'drawdown': {
                'normal': 3.0,
                'reduced': 5.0,
                'pause': 8.0,
                'reduced_multiplier': 0.5,
            },
            'profit_factor': {
                'rolling_trades': 30,
                'excellent': 2.5,
                'normal': 1.8,
                'reduced': 1.2,
                'pause': 1.0,
                'reduced_multiplier': 0.7,
                'minimum_trades': 20,
            },
        }
    
    def _load_settings(self):
        """Load settings from config."""
        p = self.config.get('portfolio', {})
        self.max_total_exposure = p.get('max_total_exposure', 2.0)
        self.max_symbol_exposure = p.get('max_symbol_exposure', 0.6)
        self.max_group_exposure = p.get('max_group_exposure', 1.0)
        self.max_positions = p.get('max_positions', 6)
        self.max_positions_per_symbol = p.get('max_positions_per_symbol', 3)
        
        d = self.config.get('drawdown', {})
        self.dd_normal = d.get('normal', 3.0)
        self.dd_reduced = d.get('reduced', 5.0)
        self.dd_pause = d.get('pause', 8.0)
        self.dd_reduced_mult = d.get('reduced_multiplier', 0.5)
        
        pf = self.config.get('profit_factor', {})
        self.pf_rolling_trades = pf.get('rolling_trades', 30)
        self.pf_excellent = pf.get('excellent', 2.5)
        self.pf_normal = pf.get('normal', 1.8)
        self.pf_reduced = pf.get('reduced', 1.2)
        self.pf_pause = pf.get('pause', 1.0)
        self.pf_reduced_mult = pf.get('reduced_multiplier', 0.7)
        self.pf_min_trades = pf.get('minimum_trades', 20)
    
    def set_equity(self, equity: float):
        """Update current equity."""
        self.equity = equity
        if equity > self.peak_equity:
            self.peak_equity = equity
    
    def get_current_dd(self) -> float:
        """Calculate current drawdown percentage."""
        if self.peak_equity <= 0:
            return 0
        return ((self.peak_equity - self.equity) / self.peak_equity) * 100
    
    def get_rolling_pf(self) -> float:
        """Calculate rolling profit factor from last N trades."""
        if len(self.trades) < self.pf_min_trades:
            return 2.0  # Assume good until proven otherwise
        
        recent_trades = self.trades[-self.pf_rolling_trades:]
        return calculate_profit_factor(recent_trades)
    
    def get_risk_multiplier(self) -> float:
        """
        Calculate risk multiplier based on DD and PF.
        
        Returns value between 0 and 1 (or slightly above 1 for excellent PF).
        """
        multiplier = 1.0
        
        # DD-based adjustment
        dd = self.get_current_dd()
        if dd >= self.dd_reduced:
            multiplier = min(multiplier, self.dd_reduced_mult)
        elif dd >= self.dd_normal:
            # Linear interpolation
            ratio = (dd - self.dd_normal) / (self.dd_reduced - self.dd_normal)
            multiplier = min(multiplier, 1.0 - (ratio * 0.25))
        
        # PF-based adjustment
        pf = self.get_rolling_pf()
        if len(self.trades) >= self.pf_min_trades:
            if pf < self.pf_reduced:
                multiplier = min(multiplier, 0.4)
            elif pf < self.pf_normal:
                multiplier = min(multiplier, self.pf_reduced_mult)
            elif pf >= self.pf_excellent:
                multiplier = min(multiplier * 1.1, 1.2)  # Slight boost
        
        return max(0.1, multiplier)  # Never go below 10%
    
    def is_trading_enabled(self) -> bool:
        """Check if trading is allowed based on DD and PF."""
        dd = self.get_current_dd()
        if dd >= self.dd_pause:
            return False
        
        pf = self.get_rolling_pf()
        if len(self.trades) >= self.pf_min_trades and pf < self.pf_pause:
            return False
        
        return True
    
    def can_open_trade(
        self,
        symbol: str,
        requested_risk: float,
        symbol_position_count: int = 0
    ) -> Tuple[bool, float, str]:
        """
        Check if a trade can be opened and with how much risk.
        
        Args:
            symbol: Symbol to trade
            requested_risk: Requested risk percentage
            symbol_position_count: Current positions for this symbol
            
        Returns:
            (allowed, approved_risk, reason)
        """
        # Check if trading enabled
        if not self.is_trading_enabled():
            dd = self.get_current_dd()
            return False, 0, f"Trading paused (DD: {dd:.1f}%)"
        
        # Check position limits
        total_positions = self.exposure.get_total_positions()
        if total_positions >= self.max_positions:
            return False, 0, f"Max positions reached ({self.max_positions})"
        
        if symbol_position_count >= self.max_positions_per_symbol:
            return False, 0, f"Max positions for {symbol} ({self.max_positions_per_symbol})"
        
        # Calculate scaled risk
        risk_mult = self.get_risk_multiplier()
        scaled_risk = requested_risk * risk_mult
        
        # Check total exposure
        current_exposure = self.exposure.get_total_exposure()
        if current_exposure + scaled_risk > self.max_total_exposure:
            available = self.max_total_exposure - current_exposure
            if available < 0.05:  # Minimum viable risk
                return False, 0, f"Portfolio exposure limit ({self.max_total_exposure}%)"
            scaled_risk = min(scaled_risk, available)
        
        # Check symbol exposure
        symbol_exposure = self.exposure.get_symbol_exposure(symbol)
        if symbol_exposure + scaled_risk > self.max_symbol_exposure:
            available = self.max_symbol_exposure - symbol_exposure
            if available < 0.05:
                return False, 0, f"Symbol exposure limit ({self.max_symbol_exposure}%)"
            scaled_risk = min(scaled_risk, available)
        
        # Check group exposure
        group = self.correlation.get_group(symbol)
        group_exposure = self.exposure.get_group_exposure(group)
        if group_exposure + scaled_risk > self.max_group_exposure:
            available = self.max_group_exposure - group_exposure
            if available < 0.05:
                return False, 0, f"Group {group} exposure limit ({self.max_group_exposure}%)"
            scaled_risk = min(scaled_risk, available)
        
        return True, scaled_risk, "OK"
    
    def record_trade(self, trade: Trade):
        """Record a completed trade for PF calculation."""
        self.trades.append(trade)
    
    def update_state(self) -> PortfolioState:
        """Update and return current portfolio state."""
        self.current_state = PortfolioState(
            equity=self.equity,
            peak_equity=self.peak_equity,
            current_dd=self.get_current_dd(),
            total_exposure=self.exposure.get_total_exposure(),
            rolling_pf=self.get_rolling_pf(),
            risk_multiplier=self.get_risk_multiplier(),
            trading_enabled=self.is_trading_enabled(),
            positions_count=self.exposure.get_total_positions(),
            group_exposures=self.exposure.get_all_group_exposures(),
        )
        return self.current_state
    
    def get_status_summary(self) -> str:
        """Get human-readable status summary."""
        state = self.update_state()
        
        status = "🟢 ACTIVE" if state.trading_enabled else "🔴 PAUSED"
        dd_icon = "🟢" if state.current_dd < self.dd_normal else ("🟡" if state.current_dd < self.dd_pause else "🔴")
        pf_icon = "🟢" if state.rolling_pf >= self.pf_normal else ("🟡" if state.rolling_pf >= self.pf_pause else "🔴")
        
        return f"""
═══════════════════════════════════════
  🧠 PORTFOLIO GOVERNOR
═══════════════════════════════════════
Status: {status}
Equity: ${state.equity:,.2f}
{dd_icon} DD: {state.current_dd:.2f}% (Pause: {self.dd_pause}%)
{pf_icon} PF: {state.rolling_pf:.2f} (Last {min(len(self.trades), self.pf_rolling_trades)} trades)
───────────────────────────────────────
📊 Exposure: {state.total_exposure:.2f}% / {self.max_total_exposure}%
⚖️ Risk Mult: {state.risk_multiplier * 100:.0f}%
📈 Positions: {state.positions_count} / {self.max_positions}
═══════════════════════════════════════
"""
