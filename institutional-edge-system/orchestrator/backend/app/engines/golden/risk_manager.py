import pandas as pd
from typing import Dict, Tuple

class RiskManager:
    """
    Professional Money Management Module.
    - ATR-based Stop Loss
    - Volatility-adjusted Position Sizing
    - Tiered Profit Targets
    """
    
    def __init__(self, config: Dict):
        self.atr_sl_multiplier = config.get('atr_sl_multiplier', 1.5)
        self.risk_percent = config.get('risk_percent', 1.0)
        self.max_sl_pips = config.get('max_sl_pips', 50)
        
        # Tiered Profits
        self.tp1_ratio = config.get('tp1_ratio', 1.5) # e.g. 1.5R
        self.tp2_ratio = config.get('tp2_ratio', 3.0) # e.g. 3.0R
        self.tp1_volume_pct = config.get('tp1_volume_pct', 0.5) # Close 50%
        
        # Trailing Stop Settings
        self.enable_trailing_stop = config.get('enable_trailing_stop', False)
        self.tsl_mode = config.get('tsl_mode', 'ATR')
        self.tsl_activation_r = config.get('tsl_activation_r', 0.0)
        self.tsl_atr_multiplier = config.get('tsl_atr_multiplier', 1.5)
        
    def calculate_entry_params(self, 
                             entry_price: float, 
                             structure_invalid_level: float, 
                             atr: float, 
                             account_balance: float) -> Dict:
        """
        Calculate Stop Loss, Take Profits, and Position Size.
        """
        
        # 1. Determine Stop Loss
        # Primary: Structure Invalidation (Hard stop)
        # Secondary: ATR Buffer
        
        dist_to_structure = abs(entry_price - structure_invalid_level)
        min_atr_dist = atr * self.atr_sl_multiplier
        
        # Use the larger distance to be safe, or logic based on config
        sl_distance = max(dist_to_structure, min_atr_dist)
        
        if entry_price > structure_invalid_level: # LONG
            stop_loss = entry_price - sl_distance
        else: # SHORT
            stop_loss = entry_price + sl_distance
            
        # 2. Position Sizing
        # Risk Amount = Balance * (Risk% / 100)
        # Position Value = Risk Amount / (SL Distance / Price) -> simplified
        # Real calc needs pip value, but here is logic:
        
        risk_amount = account_balance * (self.risk_percent / 100.0)
        
        # This returns abstract size, trading.py converts to lots using MT5
        
        return {
            'stop_loss': stop_loss,
            'sl_distance': sl_distance,
            'risk_amount': risk_amount,
            'tp1': entry_price + (sl_distance * self.tp1_ratio) * (1 if entry_price > stop_loss else -1),
            'tp2': entry_price + (sl_distance * self.tp2_ratio) * (1 if entry_price > stop_loss else -1),
            'tp1_volume_pct': self.tp1_volume_pct,
            # Pass TSL params to signal
            'enable_trailing_stop': self.enable_trailing_stop,
            'tsl_mode': self.tsl_mode,
            'tsl_activation_r': self.tsl_activation_r,
            'tsl_atr_multiplier': self.tsl_atr_multiplier
        }
