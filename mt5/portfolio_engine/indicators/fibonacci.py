"""
Fibonacci Indicator
Calculates swing points, Fibonacci levels, and golden zone detection.
"""

import pandas as pd
import numpy as np
from typing import Tuple, Optional, Dict


def find_swing_points(
    df: pd.DataFrame,
    lookback: int = 20,
    high_col: str = 'high',
    low_col: str = 'low'
) -> Tuple[float, float, int, int]:
    """
    Find swing high and swing low within lookback period.
    
    Returns:
        (swing_high, swing_low, high_bar_index, low_bar_index)
        Bar indices are relative (0 = current, higher = older)
    """
    if len(df) < lookback:
        return None, None, -1, -1
    
    # Get last 'lookback' bars (excluding current bar at index 0)
    recent = df.tail(lookback + 1).iloc[:-1]  # Exclude current bar
    
    swing_high = recent[high_col].max()
    swing_low = recent[low_col].min()
    
    # Find bar indices (relative to current)
    high_idx = recent[high_col].idxmax()
    low_idx = recent[low_col].idxmin()
    
    # Convert to relative bar index
    high_bar = len(df) - 1 - df.index.get_loc(high_idx)
    low_bar = len(df) - 1 - df.index.get_loc(low_idx)
    
    return swing_high, swing_low, high_bar, low_bar


def find_swing_points_simple(
    highs: np.ndarray,
    lows: np.ndarray,
    lookback: int = 20
) -> Tuple[float, float, int, int]:
    """
    Simplified swing point finder using numpy arrays.
    
    Args:
        highs: Array of high prices
        lows: Array of low prices
        lookback: Number of bars to look back
        
    Returns:
        (swing_high, swing_low, high_bar_index, low_bar_index)
    """
    if len(highs) < lookback + 1:
        return np.nan, np.nan, -1, -1
    
    # Look at last N bars, excluding current (index -1)
    recent_highs = highs[-(lookback + 1):-1]
    recent_lows = lows[-(lookback + 1):-1]
    
    swing_high = np.max(recent_highs)
    swing_low = np.min(recent_lows)
    
    # Bar index (1 = previous bar, higher = older)
    high_bar = lookback - np.argmax(recent_highs[::-1])
    low_bar = lookback - np.argmin(recent_lows[::-1])
    
    return swing_high, swing_low, high_bar, low_bar


def calculate_fib_levels(
    swing_high: float,
    swing_low: float,
    levels: list = [0.236, 0.382, 0.5, 0.618, 0.786]
) -> Dict[float, float]:
    """
    Calculate Fibonacci retracement levels.
    
    Returns:
        Dictionary mapping level (0.618) to price
    """
    swing_range = swing_high - swing_low
    
    if swing_range <= 0:
        return {}
    
    fib_levels = {}
    for level in levels:
        # For uptrend (retracement from high)
        fib_levels[level] = swing_high - (swing_range * level)
    
    return fib_levels


def get_golden_zone(
    swing_high: float,
    swing_low: float,
    level_low: float = 0.618,
    level_high: float = 0.786
) -> Tuple[float, float]:
    """
    Get the golden zone boundaries.
    
    For BUY (uptrend retracement):
        Zone is between 61.8% and 78.6% from high
        
    Returns:
        (zone_top, zone_bottom)
    """
    swing_range = swing_high - swing_low
    
    # For discount zone (buying dips in uptrend)
    zone_top = swing_high - (swing_range * level_low)     # 61.8% level
    zone_bottom = swing_high - (swing_range * level_high) # 78.6% level
    
    return zone_top, zone_bottom


def is_in_golden_zone(
    price: float,
    swing_high: float,
    swing_low: float,
    level_low: float = 0.618,
    level_high: float = 0.786,
    tolerance_atr: float = 0.0,
    atr: float = 0.0
) -> bool:
    """
    Check if price is within the Fibonacci golden zone.
    
    Args:
        price: Current price
        swing_high: Swing high price
        swing_low: Swing low price
        level_low: Lower Fib level (default 0.618)
        level_high: Upper Fib level (default 0.786)
        tolerance_atr: Tolerance multiplier for ATR
        atr: Current ATR value
        
    Returns:
        True if price is in the golden zone
    """
    zone_top, zone_bottom = get_golden_zone(swing_high, swing_low, level_low, level_high)
    
    tolerance = atr * tolerance_atr
    
    return (price <= zone_top + tolerance) and (price >= zone_bottom - tolerance)


def is_valid_structure(
    high_bar: int,
    low_bar: int,
    direction: int
) -> bool:
    """
    Check if swing structure is valid for the given direction.
    
    For BUY: Low should be OLDER than high (low came first, then rally, now retracing)
             low_bar > high_bar means low is further back in time
             
    For SELL: High should be OLDER than low
             high_bar > low_bar means high is further back in time
             
    Args:
        high_bar: Bar index of swing high (higher = older)
        low_bar: Bar index of swing low (higher = older)
        direction: 1 for BUY, -1 for SELL
        
    Returns:
        True if structure is valid for direction
    """
    if direction == 1:  # BUY
        # Low should be older (higher bar index) than high
        return low_bar > high_bar
    else:  # SELL
        # High should be older (higher bar index) than low
        return high_bar > low_bar


def check_displacement(
    closes: np.ndarray,
    opens: np.ndarray,
    atr: float,
    direction: int,
    min_atr_mult: float = 1.2,
    lookback: int = 5
) -> bool:
    """
    Check if there was a displacement (strong impulse) candle recently.
    
    Args:
        closes: Array of close prices
        opens: Array of open prices
        atr: Current ATR
        direction: 1 for bullish, -1 for bearish
        min_atr_mult: Minimum body size in ATR multiples
        lookback: How many bars to look back
        
    Returns:
        True if displacement found
    """
    if len(closes) < lookback + 2:
        return False
    
    # Look at bars from index -lookback-1 to -2 (excluding current and previous)
    for i in range(2, lookback + 2):
        if i >= len(closes):
            break
            
        body = abs(closes[-i] - opens[-i])
        is_bullish = closes[-i] > opens[-i]
        
        if body >= atr * min_atr_mult:
            if direction == 1 and is_bullish:
                return True
            if direction == -1 and not is_bullish:
                return True
    
    return False
