"""
Risk Manager Service
Centralized risk control for the Institutional Edge System.
Implements Global Kill Switch, Frequency Guard, and Equity Curve Protection.
"""

import asyncio
from typing import Tuple, List, Deque, Optional, Dict
from datetime import datetime, timedelta
from collections import deque
from loguru import logger
from app.core.config import settings

# Global Singleton Instance
risk_manager = None

class RiskManager:
    """
    Centralized Risk Management System (Institutional Grade)
    
    Features:
    - Global Kill Switch (Manual & Automatic)
    - Trade Frequency Guard (Anti-Span)
    - Equity Curve Guard (Anti-Crash)
    - Max Daily Loss Circuit Breaker
    - Discord Alerting Integration
    """

    def __init__(self):
        # Configuration
        self.max_daily_loss_pct = settings.MAX_DAILY_LOSS_PERCENT
        self.max_drawdown_pct = settings.MAX_DRAWDOWN_PERCENT
        self.max_trades_per_hour = settings.RISK_MAX_TRADES_PER_HOUR
        self.equity_guard_pct = settings.RISK_EQUITY_GUARD_TRIGGER_PERCENT

        # State - Kill Switch
        self.kill_switch_active: bool = False
        self.kill_switch_reason: str = ""
        self.kill_switch_timestamp: Optional[datetime] = None

        # State - Metrics
        self.initial_balance: float = 0.0
        self.current_equity: float = 0.0
        self.starting_equity_of_day: float = 0.0 # Reset daily
        self.last_day_reset: int = datetime.utcnow().day

        # State - History
        # Track trade timestamps for frequency guard
        self.trade_timestamps: Deque[datetime] = deque(maxlen=self.max_trades_per_hour * 2)
        
        # Track equity history for curve slope detection (last 60 checks ~ 1 hour if checked minutely)
        self.equity_history: Deque[Tuple[datetime, float]] = deque(maxlen=60) 

        # Socket
        self.sio = None

        logger.info(f"🛡️ RiskManager initialized | Max DD: {self.max_drawdown_pct}% | Max Daily: {self.max_daily_loss_pct}%")

    def set_socket(self, sio_instance):
        """Set Socket.IO instance for real-time updates"""
        self.sio = sio_instance

    async def emit_state(self):
        """Broadcast current risk state to all clients"""
        if not self.sio: return
        
        state = {
            "kill_switch": self.kill_switch_active,
            "kill_switch_reason": self.kill_switch_reason,
            "max_dd_percent": self.max_drawdown_pct,
            "max_daily_loss_percent": self.max_daily_loss_pct,
            "current_dd_percent": ((self.initial_balance - self.current_equity) / self.initial_balance * 100) if self.initial_balance > 0 else 0,
            "daily_loss_percent": ((self.starting_equity_of_day - self.current_equity) / self.starting_equity_of_day * 100) if self.starting_equity_of_day > 0 else 0,
            "trades_this_hour": len([t for t in self.trade_timestamps if t > datetime.utcnow() - timedelta(hours=1)])
        }
        await self.sio.emit('risk_update', state)

    async def initialize(self, mt5_connector):
        """Initialize with account data"""
        if mt5_connector and mt5_connector.connected:
            acc = mt5_connector.get_account_info()
            if acc:
                self.initial_balance = acc.get('balance', 0.0)
                self.current_equity = acc.get('equity', 0.0)
                self.starting_equity_of_day = self.current_equity
                logger.info(f"🛡️ RiskManager Synced: Balance=${self.initial_balance}, Equity=${self.current_equity}")

    def trigger_kill_switch(self, reason: str, source: str = "SYSTEM"):
        """Activates the Global Kill Switch"""
        if self.kill_switch_active:
            return # Already active

        self.kill_switch_active = True
        self.kill_switch_reason = reason
        self.kill_switch_timestamp = datetime.utcnow()
        
        logger.critical(f"💀 GLOBAL KILL SWITCH TRIGGERED by {source}: {reason}")
        
        # Async alert
        asyncio.create_task(self._send_alert(
            title="💀 KILL SWITCH ACTIVATED",
            message=f"Trading Halted Permanently.\n**Reason:** {reason}\n**Source:** {source}",
            level="CRITICAL"
        ))
        asyncio.create_task(self.emit_state())

    def reset_kill_switch(self, source: str = "ADMIN"):
        """Deactivates the Kill Switch"""
        self.kill_switch_active = False
        self.kill_switch_reason = ""
        self.kill_switch_timestamp = None
        logger.warning(f"🛡️ Kill Switch RESET by {source}. Trading Resumed.")
        
        asyncio.create_task(self._send_alert(
            title="🛡️ Kill Switch Reset",
            message=f"System operations resumed by {source}.",
            level="SUCCESS"
        ))
        asyncio.create_task(self.emit_state())

    def check_trade_allowed(self, symbol: str, volume: float) -> Tuple[bool, str]:
        """
        Master Gatekeeper: Can we open this trade?
        """
        # 0. Global Kill Switch
        if self.kill_switch_active:
            return False, f"KILL SWITCH ACTIVE: {self.kill_switch_reason}"

        # 1. Update Metrics (ensure fresh data)
        self._check_daily_reset()

        # 2. Frequency Guard
        if self._check_frequency_violation():
            return False, f"Frequency Guard: >{self.max_trades_per_hour} trades/hr"

        # 3. Max Drawdown (Total)
        current_dd_pct = ((self.initial_balance - self.current_equity) / self.initial_balance) * 100
        if current_dd_pct >= self.max_drawdown_pct:
            self.trigger_kill_switch(f"Max Drawdown Exceeded ({current_dd_pct:.2f}% > {self.max_drawdown_pct}%)")
            return False, "Max Drawdown Exceeded"

        # 4. Max Daily Loss
        daily_loss_pct = ((self.starting_equity_of_day - self.current_equity) / self.starting_equity_of_day) * 100
        if daily_loss_pct >= self.max_daily_loss_pct:
            return False, f"Daily Loss Limit Hit ({daily_loss_pct:.2f}% >= {self.max_daily_loss_pct}%)"

        return True, "OK"

    def record_trade(self, symbol: str, volume: float):
        """Call this AFTER a trade is successfully opened"""
        self.trade_timestamps.append(datetime.utcnow())
        logger.info(f"🛡️ Trade recorded: {symbol} {volume} lots")

    def update_metrics(self, current_equity: float, current_balance: float):
        """Update internal state with latest account data (call periodically)"""
        self.current_equity = current_equity
        # Only update initial balance if it increases (profit lock-in) or purely purely tracking logic?
        # Standard: Initial balance is deposit. High Water Mark is better for DD.
        # For now, keep simple: Current Equity vs Initial Balance logic.
        
        # Add to history for Curve Guard
        now = datetime.utcnow()
        self.equity_history.append((now, current_equity))
        
        # Check Equity Curve Guard
        self._check_equity_curve_guard()
        
        # Periodic state emit (throttle if needed, but safe for now)
        asyncio.create_task(self.emit_state())

    def _check_daily_reset(self):
        """Reset daily metrics at 00:00 UTC"""
        today = datetime.utcnow().day
        if today != self.last_day_reset:
            logger.info(f"🔄 RiskManager: Daily Reset (Day {self.last_day_reset} -> {today})")
            self.starting_equity_of_day = self.current_equity
            self.last_day_reset = today

    def _check_frequency_violation(self) -> bool:
        """Check if too many trades in last hour"""
        if len(self.trade_timestamps) < self.max_trades_per_hour:
            return False
            
        now = datetime.utcnow()
        one_hour_ago = now - timedelta(hours=1)
        
        # Count trades since 1 hour ago
        recent_trades = sum(1 for t in self.trade_timestamps if t > one_hour_ago)
        
        if recent_trades >= self.max_trades_per_hour:
            logger.warning(f"⚠️ High Risk: {recent_trades} trades in last hour (Max: {self.max_trades_per_hour})")
            return True
            
        return False

    def _check_equity_curve_guard(self):
        """
        Detect sharp equity drops (Crash Protection)
        If Equity drops > X% in last hour, Kill Switch.
        """
        if len(self.equity_history) < 5:
            return

        now = datetime.utcnow()
        one_hour_ago = now - timedelta(hours=1)
        
        # Get oldest reading within 1 hour
        oldest_val = None
        for t, equity in self.equity_history:
            if t > one_hour_ago:
                oldest_val = equity
                break
        
        if oldest_val is None:
            return

        # Calculate Drop
        drop_pct = ((oldest_val - self.current_equity) / oldest_val) * 100
        
        if drop_pct >= self.equity_guard_pct:
            msg = f"📉 Equity Crash Detected: -{drop_pct:.2f}% in <1 hour"
            self.trigger_kill_switch(msg, source="EQUITY_GUARD")

    async def _send_alert(self, title, message, level):
        try:
            from app.services.alert_service import alert_service
            await alert_service.send_alert(title, message, level)
        except Exception as e:
            logger.error(f"Failed to send risk alert: {e}")

# Initialize Global Instance
risk_manager = RiskManager()
