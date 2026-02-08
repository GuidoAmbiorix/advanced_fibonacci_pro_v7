"""
Risk Manager - Enforces trading risk rules
"""

import logging
from typing import Dict, Optional

class RiskManager:
    """Manages risk rules for automated trading."""
    
    def __init__(self, config: Dict, db):
        """
        Initialize risk manager.
        
        Args:
            config: Risk configuration dictionary
            db: DatabaseManager instance
        """
        self.config = config
        self.db = db
        self.logger = logging.getLogger(__name__)
    
    def can_open_position(self, symbol: str, confidence: float, account_balance: float) -> tuple[bool, str]:
        """
        Check if a new position can be opened.
        
        Returns:
            (can_open, reason) tuple
        """
        # Check confidence threshold
        min_confidence = self.config['risk']['min_confidence']
        if confidence < min_confidence:
            return False, f"Confidence {confidence:.2%} below minimum {min_confidence:.2%}"
        
        # Check max positions
        open_positions = self.db.get_open_positions()
        max_positions = self.config['risk']['max_positions']
        if len(open_positions) >= max_positions:
            return False, f"Max positions ({max_positions}) reached"
        
        # Check daily loss limit
        daily_pnl = self.db.get_daily_pnl()
        max_daily_loss = account_balance * (self.config['risk']['max_daily_loss_pct'] / 100)
        if daily_pnl < -max_daily_loss:
            return False, f"Daily loss limit reached: {daily_pnl:.2f} < -{max_daily_loss:.2f}"
        
        return True, "OK"
    
    def calculate_position_size(self, symbol: str, account_balance: float) -> float:
        """
        Calculate position size based on account balance.
        
        Returns:
            Lot size
        """
        position_size_pct = self.config['risk']['position_size_pct']
        risk_amount = account_balance * (position_size_pct / 100)
        
        # Simple calculation: use default lot size
        # In production, you'd calculate based on stop loss distance
        lot_size = self.config['trade']['default_lot_size']
        
        self.logger.info(f"Calculated position size: {lot_size} lots (risk: ${risk_amount:.2f})")
        return lot_size
    
    def calculate_sl_tp(self, symbol: str, entry_price: float, direction: str) -> tuple[float, float]:
        """
        Calculate stop loss and take profit levels.
        
        Args:
            symbol: Trading symbol
            entry_price: Entry price
            direction: 'BUY' or 'SELL'
            
        Returns:
            (stop_loss, take_profit) tuple
        """
        # Simple pip-based calculation (assumes 5-digit broker for forex)
        pip_value = 0.0001 if 'JPY' not in symbol else 0.01
        
        sl_pips = self.config['trade']['stop_loss_pips']
        tp_pips = self.config['trade']['take_profit_pips']
        
        if direction == 'BUY':
            sl = entry_price - (sl_pips * pip_value)
            tp = entry_price + (tp_pips * pip_value)
        else:  # SELL
            sl = entry_price + (sl_pips * pip_value)
            tp = entry_price - (tp_pips * pip_value)
        
        return round(sl, 5), round(tp, 5)
