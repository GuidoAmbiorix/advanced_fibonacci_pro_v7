"""
============================================================================
INSTITUTIONAL EDGE PRO - Real-Time Risk Controls
============================================================================
Circuit breakers, kill switches, and real-time risk monitoring
"""

from datetime import datetime, date
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, field
from loguru import logger
import threading


@dataclass
class DailyStats:
    """Daily trading statistics"""
    date: date
    starting_balance: float
    trades_count: int = 0
    wins: int = 0
    losses: int = 0
    consecutive_losses: int = 0
    realized_pnl: float = 0.0
    max_drawdown_pct: float = 0.0
    lowest_equity: float = field(default=0.0)
    peak_daily_profit_pct: float = 0.0  # Track highest profit % reached today
    
    def __post_init__(self):
        if self.lowest_equity == 0:
            self.lowest_equity = self.starting_balance


class RiskControls:
    """
    Real-time risk control system with circuit breakers.
    
    Features:
    - Kill switch (emergency stop)
    - Daily loss limit
    - Consecutive loss breaker
    - Maximum drawdown protection
    - Correlation checks
    """
    
    def __init__(self, config: Dict):
        """
        Initialize risk controls.
        
        Args:
            config: Risk configuration with:
                - max_daily_loss_pct: Max daily loss as % of balance (e.g., 2.0)
                - max_consecutive_losses: Stop after N consecutive losses (e.g., 3)
                - max_drawdown_pct: Max total drawdown % from peak (e.g., 5.0)
                - correlated_pairs: List of correlated pair groups
                - max_positions_per_group: Max positions in correlated group
        """
        self.config = config
        self.max_daily_loss_pct = config.get('max_daily_loss_pct', 2.0)
        self.max_consecutive_losses = config.get('max_consecutive_losses', 3)
        self.max_drawdown_pct = config.get('max_drawdown_pct', 5.0)
        self.max_positions_per_group = config.get('max_positions_per_group', 1)
        
        # Daily Profit Cap (Winning Lock)
        self.max_daily_profit_pct = config.get('max_daily_profit_pct', 3.0)
        self.profit_cap_mode = config.get('max_daily_profit_mode', 'TRAILING')  # HARD or TRAILING
        self.trailing_profit_lock_pct = config.get('trailing_profit_lock_pct', 0.5)  # Lock 50% of peak
        
        # Correlated pairs (default groups)
        self.correlated_pairs = config.get('correlated_pairs', [
            ['EURUSD', 'GBPUSD', 'AUDUSD', 'NZDUSD'],  # USD pairs
            ['EURJPY', 'GBPJPY', 'AUDJPY', 'USDJPY'],  # JPY pairs
            ['XAUUSD', 'XAGUSD'],  # Metals
        ])
        
        # State
        self._kill_switch_active = False
        self._kill_switch_lock = threading.Lock()
        self._daily_stats: Dict[str, DailyStats] = {}  # Keyed by account ID
        self._open_positions: Dict[str, List[str]] = {}  # account_id -> [symbols]
        
        logger.info(f"Risk Controls initialized: Daily Loss {self.max_daily_loss_pct}%, "
                   f"Max Consecutive Losses {self.max_consecutive_losses}, "
                   f"Max Drawdown {self.max_drawdown_pct}%, "
                   f"Daily Profit Cap +{self.max_daily_profit_pct}% ({self.profit_cap_mode})")
    
    # ==================== KILL SWITCH ====================
    
    def activate_kill_switch(self, reason: str = "Manual activation"):
        """Activate emergency kill switch - stops all trading immediately"""
        with self._kill_switch_lock:
            self._kill_switch_active = True
            logger.critical(f"🚨 KILL SWITCH ACTIVATED: {reason}")
    
    def deactivate_kill_switch(self):
        """Deactivate kill switch - resume trading"""
        with self._kill_switch_lock:
            self._kill_switch_active = False
            logger.info("✅ Kill switch deactivated - trading resumed")
    
    def is_kill_switch_active(self) -> bool:
        """Check if kill switch is active"""
        with self._kill_switch_lock:
            return self._kill_switch_active
    
    # ==================== DAILY STATS ====================
    
    def _get_or_create_daily_stats(self, account_id: str, starting_balance: float) -> DailyStats:
        """Get or create daily stats for an account"""
        today = date.today()
        key = f"{account_id}_{today}"
        
        if key not in self._daily_stats:
            self._daily_stats[key] = DailyStats(
                date=today,
                starting_balance=starting_balance
            )
        return self._daily_stats[key]
    
    def record_trade_result(self, account_id: str, pnl: float, starting_balance: float):
        """
        Record a trade result for risk tracking.
        
        Args:
            account_id: Account identifier
            pnl: Profit/loss of the trade
            starting_balance: Account balance at start of day
        """
        stats = self._get_or_create_daily_stats(account_id, starting_balance)
        stats.trades_count += 1
        stats.realized_pnl += pnl
        
        if pnl > 0:
            stats.wins += 1
            stats.consecutive_losses = 0
        else:
            stats.losses += 1
            stats.consecutive_losses += 1
        
        # Update drawdown
        current_balance = starting_balance + stats.realized_pnl
        if current_balance < stats.lowest_equity:
            stats.lowest_equity = current_balance
            stats.max_drawdown_pct = ((starting_balance - stats.lowest_equity) / starting_balance) * 100
        
        # Update peak daily profit (for trailing profit lock)
        current_profit_pct = (stats.realized_pnl / starting_balance) * 100
        if current_profit_pct > stats.peak_daily_profit_pct:
            stats.peak_daily_profit_pct = current_profit_pct
        
        logger.info(f"Trade recorded: PnL ${pnl:.2f}, Daily PnL ${stats.realized_pnl:.2f}, "
                   f"Peak Profit +{stats.peak_daily_profit_pct:.2f}%, "
                   f"Consecutive Losses: {stats.consecutive_losses}")
    
    def update_equity(self, account_id: str, current_equity: float, starting_balance: float):
        """Update current equity for drawdown tracking"""
        stats = self._get_or_create_daily_stats(account_id, starting_balance)
        
        if current_equity < stats.lowest_equity:
            stats.lowest_equity = current_equity
            stats.max_drawdown_pct = ((starting_balance - stats.lowest_equity) / starting_balance) * 100
    
    # ==================== TRADE CHECKS ====================
    
    def can_open_trade(
        self,
        account_id: str,
        symbol: str,
        current_balance: float,
        starting_balance: float,
        current_equity: float
    ) -> Tuple[bool, str]:
        """
        Check if a new trade can be opened.
        
        Returns:
            Tuple of (allowed: bool, reason: str)
        """
        # 1. Kill switch check
        if self.is_kill_switch_active():
            return False, "Kill switch is active"
        
        stats = self._get_or_create_daily_stats(account_id, starting_balance)
        
        # 2. Daily loss limit check
        daily_loss_pct = (stats.realized_pnl / starting_balance) * 100
        if daily_loss_pct < -self.max_daily_loss_pct:
            return False, f"Daily loss limit breached: {daily_loss_pct:.2f}% (Max: -{self.max_daily_loss_pct}%)"
        
        # 3. Consecutive losses check
        if stats.consecutive_losses >= self.max_consecutive_losses:
            return False, f"Consecutive loss limit reached: {stats.consecutive_losses} (Max: {self.max_consecutive_losses})"
        
        # 4. Max drawdown check
        current_dd = ((starting_balance - current_equity) / starting_balance) * 100
        if current_dd > self.max_drawdown_pct:
            return False, f"Max drawdown breached: {current_dd:.2f}% (Max: {self.max_drawdown_pct}%)"
        
        # 5. Correlation check
        open_symbols = self._open_positions.get(account_id, [])
        for group in self.correlated_pairs:
            if symbol in group:
                correlated_open = sum(1 for s in open_symbols if s in group)
                if correlated_open >= self.max_positions_per_group:
                    return False, f"Correlation limit: {correlated_open} positions in group {group}"
        
        # 6. Daily Profit Cap check (HARD mode)
        daily_profit_pct = (stats.realized_pnl / starting_balance) * 100
        if daily_profit_pct >= self.max_daily_profit_pct:
            return False, f"🎯 Daily profit target reached: +{daily_profit_pct:.2f}% (Cap: +{self.max_daily_profit_pct}%)"
        
        # 7. Trailing Profit Lock check (TRAILING mode)
        if self.profit_cap_mode == "TRAILING" and stats.peak_daily_profit_pct > 0:
            min_locked_pct = stats.peak_daily_profit_pct * self.trailing_profit_lock_pct
            if daily_profit_pct < min_locked_pct and stats.peak_daily_profit_pct >= self.max_daily_profit_pct * 0.5:
                return False, f"🔒 Trailing profit lock: Peak +{stats.peak_daily_profit_pct:.2f}%, now +{daily_profit_pct:.2f}% < Min +{min_locked_pct:.2f}%"
        
        return True, "All checks passed"
    
    def register_position_opened(self, account_id: str, symbol: str):
        """Register that a position was opened"""
        if account_id not in self._open_positions:
            self._open_positions[account_id] = []
        self._open_positions[account_id].append(symbol)
    
    def register_position_closed(self, account_id: str, symbol: str, pnl: float, starting_balance: float):
        """Register that a position was closed"""
        if account_id in self._open_positions and symbol in self._open_positions[account_id]:
            self._open_positions[account_id].remove(symbol)
        
        self.record_trade_result(account_id, pnl, starting_balance)
    
    # ==================== STATUS ====================
    
    def get_status(self, account_id: str, starting_balance: float) -> Dict:
        """Get current risk status for an account"""
        stats = self._get_or_create_daily_stats(account_id, starting_balance)
        
        return {
            "kill_switch_active": self.is_kill_switch_active(),
            "daily_pnl": stats.realized_pnl,
            "daily_pnl_pct": (stats.realized_pnl / starting_balance) * 100,
            "peak_daily_profit_pct": stats.peak_daily_profit_pct,
            "trades_today": stats.trades_count,
            "wins": stats.wins,
            "losses": stats.losses,
            "consecutive_losses": stats.consecutive_losses,
            "max_drawdown_pct": stats.max_drawdown_pct,
            "open_positions": self._open_positions.get(account_id, []),
            "limits": {
                "max_daily_loss_pct": self.max_daily_loss_pct,
                "max_consecutive_losses": self.max_consecutive_losses,
                "max_drawdown_pct": self.max_drawdown_pct,
                "max_daily_profit_pct": self.max_daily_profit_pct,
                "profit_cap_mode": self.profit_cap_mode,
            }
        }
    
    def reset_daily_stats(self, account_id: str):
        """Reset daily stats (called at start of new trading day)"""
        today = date.today()
        key = f"{account_id}_{today}"
        if key in self._daily_stats:
            del self._daily_stats[key]
        logger.info(f"Daily stats reset for account {account_id}")


# Global instance
_risk_controls: Optional[RiskControls] = None


def get_risk_controls(config: Optional[Dict] = None) -> RiskControls:
    """Get or create global risk controls instance"""
    global _risk_controls
    if _risk_controls is None:
        _risk_controls = RiskControls(config or {})
    return _risk_controls
