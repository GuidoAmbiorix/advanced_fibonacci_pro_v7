"""
Exit Strategy Manager - Advanced trade exit logic
"""
import logging
from datetime import datetime, timedelta
from typing import Optional, Dict
import requests

class ExitManager:
    """Manages advanced exit strategies for open positions."""
    
    def __init__(self, config: dict, bridge_url: str):
        self.config = config
        self.bridge_url = bridge_url
        self.logger = logging.getLogger(__name__)
        self.exit_config = config.get('exit_strategies', {})
        
        if self.exit_config:
            self.logger.info("Exit strategies initialized")
        
    def check_exit_conditions(self, position: Dict, current_price: float, 
                              atr: float) -> tuple[bool, str, Optional[Dict]]:
        """
        Check if any exit condition is met for a position.
        
        Args:
            position: Position dict with entry_price, sl, tp, open_time, etc.
            current_price: Current market price
            atr: Current ATR value for the symbol
            
        Returns:
            (should_exit, reason, modification) tuple
            - should_exit: True if position should be closed/modified
            - reason: Exit reason for logging
            - modification: Dict with new SL/TP if trailing, None if closing
        """
        # 1. Check Breakeven Stop
        breakeven_result = self._check_breakeven(position, current_price)
        if breakeven_result:
            return True, "Moving to breakeven", breakeven_result
        
        # 2. Check Partial Profit Taking
        partial_result = self._check_partial_profit(position, current_price)
        if partial_result:
            return True, "Taking partial profit", partial_result
        
        # 3. Check Trailing Stop (ATR-based)
        trailing_result = self._check_trailing_stop(position, current_price, atr)
        if trailing_result:
            return True, "Trailing stop update", trailing_result
        
        # 4. Check Time-Based Exit
        time_exit = self._check_time_exit(position)
        if time_exit:
            return True, "Time-based exit", None
        
        # 5. Check Killzone Exit (close if killzone ends)
        killzone_exit = self._check_killzone_exit(position)
        if killzone_exit:
            return True, "Killzone ended", None
        
        return False, "", None
    
    def _check_breakeven(self, position: Dict, current_price: float) -> Optional[Dict]:
        """Move stop to breakeven after reaching 1:1 R:R."""
        if not self.exit_config.get('breakeven_enabled', True):
            return None
        
        # Check if already at breakeven
        if position.get('breakeven_set', False):
            return None
        
        entry_price = position['entry_price']
        direction = position['direction']
        initial_risk = abs(entry_price - position['sl'])
        
        # Calculate profit in pips
        if direction == 'BUY':
            profit = current_price - entry_price
        else:  # SELL
            profit = entry_price - current_price
        
        # Move to breakeven after 1:1 R:R
        breakeven_ratio = self.exit_config.get('breakeven_ratio', 1.0)
        if profit >= (initial_risk * breakeven_ratio):
            # Add small buffer (2 pips) to avoid spread issues
            buffer = 0.0002 if 'JPY' not in position['symbol'] else 0.02
            
            new_sl = entry_price + buffer if direction == 'BUY' else entry_price - buffer
            
            self.logger.info(f"Moving {position['symbol']} to breakeven (profit: {profit:.5f})")
            return {
                'action': 'modify',
                'new_sl': new_sl,
                'new_tp': position['tp'],  # Keep TP unchanged
                'breakeven_set': True
            }
        
        return None
    
    def _check_partial_profit(self, position: Dict, current_price: float) -> Optional[Dict]:
        """Take partial profit at first target."""
        if not self.exit_config.get('partial_profit_enabled', False):
            return None
        
        # Check if already took partial
        if position.get('partial_taken', False):
            return None
        
        entry_price = position['entry_price']
        direction = position['direction']
        tp = position['tp']
        
        # Calculate first target (e.g., 50% of full TP)
        partial_ratio = self.exit_config.get('partial_profit_ratio', 0.5)
        
        if direction == 'BUY':
            first_target = entry_price + ((tp - entry_price) * partial_ratio)
            if current_price >= first_target:
                # Close 50% of position
                close_percent = self.exit_config.get('partial_close_percent', 0.5)
                
                self.logger.info(f"Taking {close_percent*100}% profit on {position['symbol']}")
                return {
                    'action': 'partial_close',
                    'close_percent': close_percent,
                    'partial_taken': True
                }
        else:  # SELL
            first_target = entry_price - ((entry_price - tp) * partial_ratio)
            if current_price <= first_target:
                close_percent = self.exit_config.get('partial_close_percent', 0.5)
                
                self.logger.info(f"Taking {close_percent*100}% profit on {position['symbol']}")
                return {
                    'action': 'partial_close',
                    'close_percent': close_percent,
                    'partial_taken': True
                }
        
        return None
    
    def _check_trailing_stop(self, position: Dict, current_price: float, 
                            atr: float) -> Optional[Dict]:
        """ATR-based trailing stop."""
        if not self.exit_config.get('trailing_stop_enabled', True):
            return None
        
        # Only trail after breakeven is set
        if not position.get('breakeven_set', False):
            return None
        
        direction = position['direction']
        current_sl = position['sl']
        
        # ATR multiplier for trailing (1.5-2x ATR is common for M5)
        atr_multiplier = self.exit_config.get('atr_multiplier', 1.5)
        trail_distance = atr * atr_multiplier
        
        if direction == 'BUY':
            # New SL = Current Price - (ATR * multiplier)
            new_sl = current_price - trail_distance
            
            # Only move SL up, never down
            if new_sl > current_sl:
                self.logger.info(f"Trailing stop up: {current_sl:.5f} -> {new_sl:.5f}")
                return {
                    'action': 'modify',
                    'new_sl': new_sl,
                    'new_tp': position['tp']
                }
        else:  # SELL
            # New SL = Current Price + (ATR * multiplier)
            new_sl = current_price + trail_distance
            
            # Only move SL down, never up
            if new_sl < current_sl:
                self.logger.info(f"Trailing stop down: {current_sl:.5f} -> {new_sl:.5f}")
                return {
                    'action': 'modify',
                    'new_sl': new_sl,
                    'new_tp': position['tp']
                }
        
        return None
    
    def _check_time_exit(self, position: Dict) -> bool:
        """Exit if position held too long (avoid overnight exposure)."""
        if not self.exit_config.get('time_exit_enabled', False):
            return False
        
        max_hold_minutes = self.exit_config.get('max_hold_minutes', 240)  # 4 hours default
        
        # Handle different time formats
        open_time_str = position.get('open_time', '')
        if not open_time_str:
            return False
            
        try:
            # Try ISO format first
            open_time = datetime.fromisoformat(open_time_str)
        except ValueError:
            # Try other common formats
            try:
                open_time = datetime.strptime(open_time_str, "%Y-%m-%d %H:%M:%S")
            except ValueError:
                self.logger.warning(f"Could not parse open_time: {open_time_str}")
                return False
        
        hold_duration = datetime.now() - open_time
        
        if hold_duration > timedelta(minutes=max_hold_minutes):
            self.logger.info(f"Time exit: held for {hold_duration.total_seconds()/60:.1f} minutes")
            return True
        
        return False
    
    def _check_killzone_exit(self, position: Dict) -> bool:
        """Close position if killzone ends (optional)."""
        if not self.exit_config.get('close_on_killzone_end', False):
            return False
        
        # This would integrate with KillzoneManager
        # For now, return False (keep positions open)
        return False
    
    def get_atr(self, symbol: str, timeframe: str = 'M5', period: int = 14) -> float:
        """Fetch ATR from bridge or calculate from recent bars."""
        try:
            # Option 1: If bridge provides ATR
            response = requests.get(
                f"{self.bridge_url}/indicators/atr",
                params={'symbol': symbol, 'timeframe': timeframe, 'period': period},
                timeout=5
            )
            if response.status_code == 200:
                return response.json()['atr']
        except Exception as e:
            self.logger.debug(f"Could not fetch ATR from bridge: {e}")
        
        # Option 2: Fallback to fixed pip value
        # For EURUSD on M5, typical ATR is ~0.0008-0.0015
        return 0.0010  # 10 pips fallback
