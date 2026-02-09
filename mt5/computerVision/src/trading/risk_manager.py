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
        # NEW: Check killzone first
        if hasattr(self, 'killzone_manager'):
            allowed, reason = self.killzone_manager.is_trading_allowed()
            if not allowed:
                return False, f"Outside trading hours: {reason}"
        
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
    
    def calculate_position_size_risk_based(self, symbol: str, entry_price: float, 
                                           stop_loss: float, account_balance: float) -> float:
        """
        Calculate position size based on risk percentage and SL distance.
        
        Formula:
        Risk Amount = Account Balance × Risk %
        Position Size = Risk Amount / (SL Distance × Contract Size)
        
        Args:
            symbol: Trading symbol
            entry_price: Entry price
            stop_loss: Stop loss price
            account_balance: Account balance
            
        Returns:
            Lot size
        """
        # Get risk percentage from config
        risk_pct = float(self.config.get('risk_per_trade_pct', 1.0))
        risk_amount = account_balance * (risk_pct / 100)
        
        # Calculate SL distance
        sl_distance = abs(entry_price - stop_loss)
        
        if sl_distance == 0:
            self.logger.warning(f"SL distance is 0, using default lot size")
            return float(self.config['trade']['default_lot_size'])
        
        # Contract size (standard lot = 100,000 for forex)
        # For XAUUSD (Gold), it's typically 100 oz
        if 'XAU' in symbol or 'GOLD' in symbol:
            contract_size = 100
        else:
            contract_size = 100000  # Standard forex lot
        
        # Calculate position size
        # Risk Amount / (SL Distance × Contract Size) = Lots
        lot_size = risk_amount / (sl_distance * contract_size)
        
        # Round to 2 decimal places and enforce minimum
        lot_size = max(0.01, round(lot_size, 2))
        
        self.logger.info(f"Risk-based position size: {lot_size} lots (Risk: ${risk_amount:.2f}, SL Distance: {sl_distance:.5f})")
        
        return lot_size
    
    def calculate_position_size(self, symbol: str, account_balance: float, 
                               entry_price: float = None, stop_loss: float = None) -> float:
        """
        Calculate position size based on configured method.
        
        Methods:
        - risk_based: Calculate based on risk % and SL distance
        - fixed_lot: Use fixed lot size from config
        
        Args:
            symbol: Trading symbol
            account_balance: Account balance
            entry_price: Entry price (required for risk_based)
            stop_loss: Stop loss price (required for risk_based)
            
        Returns:
            Lot size
        """
        # Get position sizing method from config
        method = self.config.get('position_sizing_method', 'risk_based')
        
        # Debug logging
        self.logger.info(f"Position sizing - Method: {method}, Entry: {entry_price}, SL: {stop_loss}, Balance: {account_balance}")
        
        if method == 'risk_based':
            if entry_price is None:
                self.logger.warning(f"⚠️ Risk-based sizing failed: entry_price is None, falling back to fixed lot")
            elif stop_loss is None:
                self.logger.warning(f"⚠️ Risk-based sizing failed: stop_loss is None, falling back to fixed lot")
            elif entry_price is not None and stop_loss is not None:
                self.logger.info(f"✅ Using risk-based position sizing")
                return self.calculate_position_size_risk_based(symbol, entry_price, stop_loss, account_balance)
        
        # Fallback to fixed lot size
        lot_size = float(self.config['trade']['default_lot_size'])
        self.logger.warning(f"⚠️ Using fallback fixed lot size: {lot_size} lots (method={method})")
        return lot_size
    
    def calculate_sl_tp(self, symbol: str, entry_price: float, direction: str, 
                       timeframe: str = 'H1', bridge_url: str = "http://10.0.0.4:5000") -> tuple[float, float]:
        """
        Calculate stop loss and take profit levels dynamically based on ATR.
        No more hardcoded pips - adapts to any timeframe!
        
        Args:
            symbol: Trading symbol
            entry_price: Entry price
            direction: 'BUY' or 'SELL'
            timeframe: Timeframe for ATR calculation (M5, H1, H4, D1)
            bridge_url: MT5 Bridge URL
            
        Returns:
            (stop_loss, take_profit) tuple
        """
        import requests
        from src.database import DatabaseManager
        
        # Get database instance for config
        db = DatabaseManager()
        
        # Query broker's minimum stop level from MT5
        broker_min_distance = 0.0
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
                self.logger.warning(f"Could not query stop level for {symbol}, using default 0")
        except Exception as e:
            self.logger.error(f"Error querying symbol info: {e}")
        
        # Get ATR for dynamic SL/TP calculation
        try:
            response = requests.get(
                f"{bridge_url}/indicators/atr",
                params={'symbol': symbol, 'timeframe': timeframe, 'period': 14},
                timeout=5
            )
            if response.status_code == 200:
                atr = response.json().get('atr', 0.0)
                self.logger.info(f"{symbol} {timeframe} ATR: {atr:.5f}")
            else:
                # Fallback ATR values by timeframe
                atr_fallbacks = {
                    'M5': 0.0010,   # 10 pips
                    'M15': 0.0020,  # 20 pips
                    'M30': 0.0030,  # 30 pips
                    'H1': 0.0050,   # 50 pips
                    'H4': 0.0100,   # 100 pips
                    'D1': 0.0200    # 200 pips
                }
                atr = atr_fallbacks.get(timeframe, 0.0050)
                self.logger.warning(f"Could not fetch ATR, using fallback: {atr:.5f} for {timeframe}")
        except Exception as e:
            # Fallback based on timeframe
            atr_fallbacks = {
                'M5': 0.0010, 'M15': 0.0020, 'M30': 0.0030,
                'H1': 0.0050, 'H4': 0.0100, 'D1': 0.0200
            }
            atr = atr_fallbacks.get(timeframe, 0.0050)
            self.logger.warning(f"Error fetching ATR: {e}, using fallback: {atr:.5f}")
        
        # Get ATR multiplier from database (not config.yaml!)
        atr_multiplier = float(db.get_config('atr_multiplier', '1.0'))
        
        # Calculate SL distance: ATR × multiplier
        # H1 with 1.0x: 50 pips × 1.0 = 50 pips
        # M5 with 1.5x: 10 pips × 1.5 = 15 pips
        config_sl_distance = atr * atr_multiplier
        
        # Use the larger of broker minimum or ATR-based distance
        min_sl_distance = max(broker_min_distance, config_sl_distance)
        
        # TP distance: 2x SL for 1:2 R:R ratio
        min_tp_distance = max(broker_min_distance * 2, config_sl_distance * 2)
        
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
        
        self.logger.info(f"Calculated SL/TP for {symbol} {timeframe}: SL={sl}, TP={tp} (ATR={atr:.5f}, multiplier={atr_multiplier}, distance={min_sl_distance:.5f})")
        return sl, tp
