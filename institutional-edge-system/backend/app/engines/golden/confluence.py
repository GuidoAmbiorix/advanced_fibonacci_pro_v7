import pandas as pd
from typing import Dict

class ConfluenceSystem:
    """
    Confirmation Module.
    Validates trade zones using Volume, VWAP, and Momentum.
    Uses a Boolean Pass/Fail logic rather than weighted generic scores.
    """
    
    def __init__(self, config: Dict):
        self.require_vwap = config.get('require_vwap', True)
        self.require_rsi_not_extreme = config.get('require_rsi_not_extreme', True)
        self.min_volume_percentile = config.get('min_volume_percentile', 50)

    def check_entry_conditions(self, df: pd.DataFrame, trend_direction: str) -> bool:
        """
        Verify if secondary indicators confirm the structural setup.
        Returns True if SAFE to enter.
        """
        if df is None or len(df) < 50:
            return False
            
        current = df.iloc[-1]
        
        # 1. VWAP Check (Trend Alignment)
        if self.require_vwap and 'vwap' in df.columns:
            if trend_direction == 'BUY' and current.close < current.vwap:
                return False # Failed VWAP check
            if trend_direction == 'SELL' and current.close > current.vwap:
                return False
                
        # 2. RSI Check (Avoid Extremes)
        if self.require_rsi_not_extreme and 'rsi' in df.columns:
            if trend_direction == 'BUY' and current.rsi > 70:
                return False # Too hot to buy
            if trend_direction == 'SELL' and current.rsi < 30:
                return False # Too low to sell
                
        # 3. Volume Check (Participation)
        # Check if current volume is above average (relative volume)
        if 'tick_volume' in df.columns or 'volume' in df.columns:
            vol_col = 'tick_volume' if 'tick_volume' in df.columns else 'volume'
            current_vol = current[vol_col]
            avg_vol = df[vol_col].rolling(20).mean().iloc[-1]
            
            if current_vol < avg_vol * (self.min_volume_percentile / 100.0):
                # Optional: Strict volume filter? 
                # For now, let's say we prefer higher volume but don't hard block unless very low
                # If strictly below 50% of average, maybe block
                if current_vol < avg_vol * 0.5:
                     return False
                     
        return True
