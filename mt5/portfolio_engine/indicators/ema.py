"""
EMA Indicator
Exponential Moving Average with slope analysis for trend detection.
"""

import pandas as pd
import numpy as np
from typing import Tuple


def calculate_ema(
    prices: pd.Series,
    period: int = 200
) -> pd.Series:
    """
    Calculate Exponential Moving Average.
    
    Args:
        prices: Series of close prices
        period: EMA period (default 200)
        
    Returns:
        Series of EMA values
    """
    return prices.ewm(span=period, adjust=False).mean()


def calculate_ema_numpy(
    closes: np.ndarray,
    period: int = 200
) -> np.ndarray:
    """
    Calculate EMA using numpy (faster for backtesting).
    
    Args:
        closes: Array of close prices
        period: EMA period
        
    Returns:
        Array of EMA values
    """
    ema = np.zeros(len(closes))
    multiplier = 2 / (period + 1)
    
    # Initialize with SMA
    ema[period-1] = np.mean(closes[:period])
    
    # Calculate EMA
    for i in range(period, len(closes)):
        ema[i] = (closes[i] * multiplier) + (ema[i-1] * (1 - multiplier))
    
    # Fill initial values with NaN
    ema[:period-1] = np.nan
    
    return ema


def calculate_ema_slope(
    ema: np.ndarray,
    lookback: int = 1
) -> np.ndarray:
    """
    Calculate EMA slope (rate of change).
    
    Args:
        ema: Array of EMA values
        lookback: Bars to look back for slope calculation
        
    Returns:
        Array of slope values (EMA[now] - EMA[lookback bars ago])
    """
    slope = np.zeros(len(ema))
    
    for i in range(lookback, len(ema)):
        if not np.isnan(ema[i]) and not np.isnan(ema[i - lookback]):
            slope[i] = ema[i] - ema[i - lookback]
        else:
            slope[i] = np.nan
    
    slope[:lookback] = np.nan
    return slope


def is_trending(
    slope: float,
    atr: float,
    min_slope_atr: float = 0.1
) -> Tuple[bool, int]:
    """
    Check if EMA shows a strong trend.
    
    Args:
        slope: Current EMA slope
        atr: Current ATR
        min_slope_atr: Minimum slope as multiple of ATR
        
    Returns:
        (is_trending, direction) where direction is 1 (up), -1 (down), or 0
    """
    if np.isnan(slope) or np.isnan(atr) or atr == 0:
        return False, 0
    
    min_slope = atr * min_slope_atr
    
    if slope > min_slope:
        return True, 1
    elif slope < -min_slope:
        return True, -1
    else:
        return False, 0


def is_trend_valid(
    price: float,
    ema: float,
    slope: float,
    atr: float,
    direction: int,
    min_slope_atr: float = 0.1
) -> bool:
    """
    Validate trend for a given direction.
    
    For BUY: Price above EMA + EMA rising + slope strong enough
    For SELL: Price below EMA + EMA falling + slope strong enough
    
    Args:
        price: Current price
        ema: Current EMA value
        slope: Current EMA slope
        atr: Current ATR
        direction: 1 for BUY, -1 for SELL
        min_slope_atr: Minimum slope as ATR multiple
        
    Returns:
        True if trend is valid for direction
    """
    if any(np.isnan([price, ema, slope, atr])):
        return False
    
    min_slope = atr * min_slope_atr
    
    if direction == 1:  # BUY
        price_ok = price > ema
        slope_ok = slope > min_slope
        return price_ok and slope_ok
        
    else:  # SELL
        price_ok = price < ema
        slope_ok = slope < -min_slope
        return price_ok and slope_ok


def get_trend_strength(
    slope: float,
    atr: float
) -> str:
    """
    Classify trend strength.
    
    Returns:
        'STRONG', 'MODERATE', 'WEAK', or 'FLAT'
    """
    if np.isnan(slope) or np.isnan(atr) or atr == 0:
        return 'FLAT'
    
    slope_atr_ratio = abs(slope) / atr
    
    if slope_atr_ratio >= 0.3:
        return 'STRONG'
    elif slope_atr_ratio >= 0.15:
        return 'MODERATE'
    elif slope_atr_ratio >= 0.05:
        return 'WEAK'
    else:
        return 'FLAT'


def multi_ema(
    closes: np.ndarray,
    periods: list = [20, 50, 100, 200]
) -> dict:
    """
    Calculate multiple EMAs at once.
    
    Args:
        closes: Array of close prices
        periods: List of EMA periods
        
    Returns:
        Dictionary of {period: ema_array}
    """
    result = {}
    for period in periods:
        result[period] = calculate_ema_numpy(closes, period)
    return result


def ema_ribbon_state(
    ema_short: float,
    ema_mid: float,
    ema_long: float
) -> str:
    """
    Determine EMA ribbon state (e.g., 20, 50, 200).
    
    Returns:
        'BULLISH', 'BEARISH', or 'MIXED'
    """
    if any(np.isnan([ema_short, ema_mid, ema_long])):
        return 'MIXED'
    
    if ema_short > ema_mid > ema_long:
        return 'BULLISH'
    elif ema_short < ema_mid < ema_long:
        return 'BEARISH'
    else:
        return 'MIXED'
