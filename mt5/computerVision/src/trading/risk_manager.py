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
            
        # Check if we already have a position for this symbol
        # We only want ONE open trade per symbol at a time
        for pos in open_positions:
            if pos['symbol'] == symbol:
                return False, f"Position already open for {symbol}"
        
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
    
    def calculate_sl_tp(self, symbol: str, entry_price: float, direction: str, bridge_url: str = "http://10.0.0.4:5000") -> tuple[float, float]:
        """
        Calculate stop loss and take profit levels respecting broker minimums.
        
        Args:
            symbol: Trading symbol
            entry_price: Entry price
            direction: 'BUY' or 'SELL'
            bridge_url: MT5 Bridge URL
            
        Returns:
            (stop_loss, take_profit) tuple
        """
        import requests
        
        # Query broker's minimum stop level from MT5
        try:
            response = requests.get(f"{bridge_url}/symbols/{symbol}/info", timeout=5)
            if response.status_code == 200:
                symbol_info = response.json()
                stops_level = symbol_info['stops_level']  # Minimum distance in points
                point = symbol_info['point']  # Point size
                
                # Convert stops_level from points to price distance
                # Add 50% safety margin to avoid rejection
                broker_min_distance = stops_level * point * 1.5
                
                self.logger.info(f"{symbol} minimum stop level: {stops_level} points = {broker_min_distance:.5f} price distance")
            else:
                # Fallback to default if query fails
                self.logger.warning(f"Could not query stop level for {symbol}, using default 0")
                broker_min_distance = 0.0
        except Exception as e:
            self.logger.error(f"Error querying symbol info: {e}")
            broker_min_distance = 0.0
        
        # Calculate config-based distance
        pip_value = 0.0001 if 'JPY' not in symbol else 0.01
        config_sl_distance = self.config['trade']['stop_loss_pips'] * pip_value
        
        # Use the larger of the two to be safe
        min_sl_distance = max(broker_min_distance, config_sl_distance)
        
        # For TP, use max of (broker_min * 2) or (config_tp_pips * pip_value)
        config_tp_distance = self.config['trade']['take_profit_pips'] * pip_value
        min_tp_distance = max(broker_min_distance * 2, config_tp_distance)
        
        # Calculate SL/TP using the distances
        if direction == 'BUY':
            sl = entry_price - min_sl_distance
            tp = entry_price + min_tp_distance
        else:  # SELL
            sl = entry_price + min_sl_distance
            tp = entry_price - min_tp_distance
        
        # Round to appropriate decimal places
        digits = 5 if 'JPY' not in symbol else 3
        sl = round(sl, digits)
        tp = round(tp, digits)
        
        self.logger.info(f"Calculated SL/TP for {symbol}: SL={sl}, TP={tp} (distance={min_sl_distance:.5f})")
        return sl, tp
