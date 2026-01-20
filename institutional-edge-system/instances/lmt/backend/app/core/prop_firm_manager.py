"""
============================================================================
Prop Firm Risk Manager - FundedPips Rules
============================================================================
Enforces prop firm drawdown limits across the trading portfolio.
"""

from datetime import datetime, date
from typing import Tuple, Optional
from loguru import logger


class PropFirmManager:
    """
    Manages prop firm risk rules across the entire trading portfolio.
    
    FundedPips Rules:
    - Max Drawdown: 8% from starting balance
    - Max Daily Drawdown: 3% from daily starting balance
    """
    
    def __init__(
        self,
        max_drawdown_percent: float = 8.0,
        max_daily_dd_percent: float = 3.0,
        starting_balance: float = 0.0
    ):
        self.max_drawdown_percent = max_drawdown_percent
        self.max_daily_dd_percent = max_daily_dd_percent
        self.starting_balance = starting_balance
        self.daily_starting_balance = starting_balance
        self.last_reset_date: Optional[date] = None
        self.is_breached = False
        self.breach_reason = ""
        
    def update_starting_balance(self, balance: float):
        """Set the starting balance for DD calculations."""
        self.starting_balance = balance
        self.daily_starting_balance = balance
        self.last_reset_date = date.today()
        logger.info(f"PropFirm: Starting balance set to ${balance:,.2f}")
        
    def reset_daily_balance(self, current_balance: float):
        """Reset daily starting balance (call at start of each trading day)."""
        today = date.today()
        if self.last_reset_date != today:
            self.daily_starting_balance = current_balance
            self.last_reset_date = today
            logger.info(f"PropFirm: Daily balance reset to ${current_balance:,.2f}")
    
    def check_can_trade(self, current_balance: float) -> Tuple[bool, str]:
        """
        Check if trading is allowed based on prop firm rules.
        
        Args:
            current_balance: Current account balance
            
        Returns:
            Tuple of (can_trade, reason_message)
        """
        # Reset daily balance if new day
        self.reset_daily_balance(current_balance)
        
        # If already breached, stay breached
        if self.is_breached:
            return False, f"🛑 TRADING HALTED: {self.breach_reason}"
        
        # Calculate total drawdown
        if self.starting_balance > 0:
            total_dd = (self.starting_balance - current_balance) / self.starting_balance * 100
        else:
            total_dd = 0
            
        # Calculate daily drawdown
        if self.daily_starting_balance > 0:
            daily_dd = (self.daily_starting_balance - current_balance) / self.daily_starting_balance * 100
        else:
            daily_dd = 0
        
        # Check total drawdown limit
        if total_dd >= self.max_drawdown_percent:
            self.is_breached = True
            self.breach_reason = f"Max DD {self.max_drawdown_percent}% breached (current: {total_dd:.2f}%)"
            logger.error(f"🛑 PropFirm BREACH: {self.breach_reason}")
            return False, f"🛑 {self.breach_reason}"
        
        # Check daily drawdown limit
        if daily_dd >= self.max_daily_dd_percent:
            self.is_breached = True
            self.breach_reason = f"Daily DD {self.max_daily_dd_percent}% breached (current: {daily_dd:.2f}%)"
            logger.error(f"🛑 PropFirm BREACH: {self.breach_reason}")
            return False, f"🛑 {self.breach_reason}"
        
        return True, "OK"
    
    def get_risk_status(self, current_balance: float) -> dict:
        """
        Get current risk status for UI display.
        
        Returns:
            Dict with DD percentages and limits
        """
        self.reset_daily_balance(current_balance)
        
        if self.starting_balance > 0:
            total_dd = (self.starting_balance - current_balance) / self.starting_balance * 100
        else:
            total_dd = 0
            
        if self.daily_starting_balance > 0:
            daily_dd = (self.daily_starting_balance - current_balance) / self.daily_starting_balance * 100
        else:
            daily_dd = 0
            
        return {
            "total_dd_percent": round(max(0, total_dd), 2),
            "max_dd_percent": self.max_drawdown_percent,
            "daily_dd_percent": round(max(0, daily_dd), 2),
            "max_daily_dd_percent": self.max_daily_dd_percent,
            "starting_balance": self.starting_balance,
            "daily_starting_balance": self.daily_starting_balance,
            "current_balance": current_balance,
            "is_breached": self.is_breached,
            "breach_reason": self.breach_reason
        }
    
    def reset_breach(self):
        """
        Reset breach status (use with caution - only for account reset).
        """
        self.is_breached = False
        self.breach_reason = ""
        logger.warning("PropFirm: Breach status manually reset")
