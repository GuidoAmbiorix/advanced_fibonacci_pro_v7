"""
ATR Indicator
Average True Range for volatility measurement and chop detection.
"""

import pandas as pd
import numpy as np
from typing import Tuple


def calculate_atr(
    df: pd.DataFrame,
    period: int = 14,
    high_col: str = 'high',
    low_col: str = 'low',
    close_col: str = 'close'
) -> pd.Series:
    """
    Calculate Average True Range.
    
    Args:
        df: DataFrame with OHLC data
        period: ATR period (default 14)
        
    Returns:
        Series of ATR values
    """
    high = df[high_col]
    low = df[low_col]
    close = df[close_col].shift(1)
    
    # True Range components
    tr1 = high - low
    tr2 = abs(high - close)
    tr3 = abs(low - close)
    
    # True Range is the maximum
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    
    # ATR is smoothed True Range (Wilder's smoothing)
    atr = tr.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    
    return atr


def calculate_atr_numpy(
    highs: np.ndarray,
    lows: np.ndarray,
    closes: np.ndarray,
    period: int = 14
) -> np.ndarray:
    """
    Calculate ATR using numpy (faster for backtesting).
    
    Args:
        highs: Array of high prices
        lows: Array of low prices
        closes: Array of close prices
        period: ATR period
        
    Returns:
        Array of ATR values
    """
    n = len(highs)
    tr = np.zeros(n)
    
    # First TR is just high - low
    tr[0] = highs[0] - lows[0]
    
    # Calculate True Range for each bar
    for i in range(1, n):
        hl = highs[i] - lows[i]
        hc = abs(highs[i] - closes[i-1])
        lc = abs(lows[i] - closes[i-1])
        tr[i] = max(hl, hc, lc)
    
    # Calculate ATR using Wilder's smoothing
    atr = np.zeros(n)
    atr[period-1] = np.mean(tr[:period])
    
    for i in range(period, n):
        atr[i] = (atr[i-1] * (period - 1) + tr[i]) / period
    
    # Set initial values to NaN
    atr[:period-1] = np.nan
    
    return atr


def calculate_atr_ma(
    atr: np.ndarray,
    period: int = 20
) -> np.ndarray:
    """
    Calculate moving average of ATR for chop detection.
    
    Args:
        atr: Array of ATR values
        period: MA period
        
    Returns:
        Array of ATR MA values
    """
    atr_ma = np.zeros(len(atr))
    
    for i in range(period - 1, len(atr)):
        if not np.isnan(atr[i-period+1:i+1]).any():
            atr_ma[i] = np.mean(atr[i-period+1:i+1])
        else:
            atr_ma[i] = np.nan
    
    atr_ma[:period-1] = np.nan
    
    return atr_ma


def is_choppy(
    atr: float,
    atr_ma: float,
    threshold: float = 0.75
) -> bool:
    """
    Check if market is in choppy/low volatility state.
    
    When ATR < ATR_MA * threshold, volatility is contracting
    which often leads to ranging/choppy conditions.
    
    Args:
        atr: Current ATR value
        atr_ma: ATR moving average
        threshold: Threshold ratio (default 0.75)
        
    Returns:
        True if market is choppy
    """
    if np.isnan(atr) or np.isnan(atr_ma) or atr_ma == 0:
        return True  # Assume choppy if we can't calculate
    
    return atr < (atr_ma * threshold)


def get_range_efficiency(
    open_price: float,
    close_price: float,
    high: float,
    low: float
) -> float:
    """
    Calculate range efficiency (body / range).
    
    High efficiency = directional move
    Low efficiency = doji/spinning top/indecision
    
    Args:
        open_price: Open price
        close_price: Close price
        high: High price
        low: Low price
        
    Returns:
        Efficiency ratio (0 to 1)
    """
    body = abs(close_price - open_price)
    range_ = high - low
    
    if range_ == 0:
        return 0
    
    return body / range_


def is_directional_candle(
    open_price: float,
    close_price: float,
    high: float,
    low: float,
    min_efficiency: float = 0.4
) -> Tuple[bool, int]:
    """
    Check if candle is directional (not a doji/spinning top).
    
    Returns:
        (is_directional, direction) where direction is 1 or -1
    """
    efficiency = get_range_efficiency(open_price, close_price, high, low)
    is_directional = efficiency >= min_efficiency
    
    direction = 1 if close_price > open_price else -1
    
    return is_directional, direction


def get_volatility_state(
    atr: float,
    atr_ma: float
) -> str:
    """
    Classify current volatility state.
    
    Returns:
        'EXPANDING', 'CONTRACTING', or 'NORMAL'
    """
    if np.isnan(atr) or np.isnan(atr_ma) or atr_ma == 0:
        return 'NORMAL'
    
    ratio = atr / atr_ma
    
    if ratio > 1.2:
        return 'EXPANDING'
    elif ratio < 0.8:
        return 'CONTRACTING'
    else:
        return 'NORMAL'


def calculate_stop_loss(
    price: float,
    atr: float,
    direction: int,
    multiplier: float = 1.0,
    min_pips: int = 10,
    max_pips: int = 100,
    pip_value: float = 0.0001
) -> float:
    """
    Calculate stop loss level using ATR.
    
    Args:
        price: Entry price
        atr: Current ATR
        direction: 1 for BUY, -1 for SELL
        multiplier: ATR multiplier
        min_pips: Minimum SL in pips
        max_pips: Maximum SL in pips
        pip_value: Value of one pip
        
    Returns:
        Stop loss price
    """
    sl_distance = atr * multiplier
    
    # Apply min/max constraints
    min_distance = min_pips * pip_value
    max_distance = max_pips * pip_value
    
    sl_distance = max(sl_distance, min_distance)
    sl_distance = min(sl_distance, max_distance)
    
    if direction == 1:
        return price - sl_distance
    else:
        return price + sl_distance
