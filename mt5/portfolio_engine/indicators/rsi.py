"""
RSI Indicator
Calculates Relative Strength Index and generates signals.
"""

import pandas as pd
import numpy as np
from typing import Tuple, Optional


def calculate_rsi(
    prices: pd.Series,
    period: int = 14
) -> pd.Series:
    """
    Calculate RSI (Relative Strength Index).
    
    Args:
        prices: Series of close prices
        period: RSI period (default 14)
        
    Returns:
        Series of RSI values
    """
    # Calculate price changes
    delta = prices.diff()
    
    # Separate gains and losses
    gains = delta.where(delta > 0, 0.0)
    losses = (-delta).where(delta < 0, 0.0)
    
    # Calculate average gains and losses using Wilder's smoothing
    avg_gain = gains.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    avg_loss = losses.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    
    # Calculate RS and RSI
    rs = avg_gain / avg_loss
    rsi = 100 - (100 / (1 + rs))
    
    return rsi


def calculate_rsi_numpy(
    closes: np.ndarray,
    period: int = 14
) -> np.ndarray:
    """
    Calculate RSI using numpy arrays (faster for backtesting).
    
    Args:
        closes: Array of close prices
        period: RSI period
        
    Returns:
        Array of RSI values
    """
    deltas = np.diff(closes)
    
    gains = np.where(deltas > 0, deltas, 0)
    losses = np.where(deltas < 0, -deltas, 0)
    
    # Wilder's smoothing
    alpha = 1 / period
    
    avg_gain = np.zeros(len(deltas))
    avg_loss = np.zeros(len(deltas))
    
    # Initialize with SMA
    avg_gain[period-1] = np.mean(gains[:period])
    avg_loss[period-1] = np.mean(losses[:period])
    
    # EMA smoothing
    for i in range(period, len(deltas)):
        avg_gain[i] = (avg_gain[i-1] * (period - 1) + gains[i]) / period
        avg_loss[i] = (avg_loss[i-1] * (period - 1) + losses[i]) / period
    
    # Calculate RSI
    rs = np.where(avg_loss != 0, avg_gain / avg_loss, 100)
    rsi = 100 - (100 / (1 + rs))
    
    # Prepend NaN to match original length
    return np.concatenate([[np.nan], rsi])


def get_rsi_signal(
    rsi_current: float,
    rsi_prev: float,
    direction: int,
    oversold: int = 45,
    overbought: int = 55,
    require_momentum: bool = True
) -> bool:
    """
    Check RSI confirmation for a trade direction.
    
    For BUY: RSI should be below oversold and rising
    For SELL: RSI should be above overbought and falling
    
    Args:
        rsi_current: Current RSI value
        rsi_prev: Previous RSI value
        direction: 1 for BUY, -1 for SELL
        oversold: Oversold threshold
        overbought: Overbought threshold
        require_momentum: Require RSI to be moving in trade direction
        
    Returns:
        True if RSI confirms the trade direction
    """
    if np.isnan(rsi_current) or np.isnan(rsi_prev):
        return False
    
    if direction == 1:  # BUY
        # RSI should be below oversold (or just touched it)
        level_ok = rsi_current <= oversold
        
        # RSI should be rising (momentum)
        momentum_ok = not require_momentum or (rsi_current > rsi_prev)
        
        return level_ok and momentum_ok
        
    else:  # SELL
        # RSI should be above overbought
        level_ok = rsi_current >= overbought
        
        # RSI should be falling
        momentum_ok = not require_momentum or (rsi_current < rsi_prev)
        
        return level_ok and momentum_ok


def get_rsi_zone(
    rsi: float,
    oversold: int = 30,
    overbought: int = 70
) -> str:
    """
    Get RSI zone description.
    
    Returns:
        'OVERSOLD', 'OVERBOUGHT', or 'NEUTRAL'
    """
    if rsi <= oversold:
        return 'OVERSOLD'
    elif rsi >= overbought:
        return 'OVERBOUGHT'
    else:
        return 'NEUTRAL'


def rsi_divergence(
    prices: np.ndarray,
    rsi: np.ndarray,
    lookback: int = 10
) -> Tuple[bool, bool]:
    """
    Detect RSI divergence (bullish or bearish).
    
    Bullish divergence: Price makes lower low, RSI makes higher low
    Bearish divergence: Price makes higher high, RSI makes lower high
    
    Args:
        prices: Array of close prices
        rsi: Array of RSI values
        lookback: Bars to look back for divergence
        
    Returns:
        (bullish_divergence, bearish_divergence)
    """
    if len(prices) < lookback or len(rsi) < lookback:
        return False, False
    
    recent_prices = prices[-lookback:]
    recent_rsi = rsi[-lookback:]
    
    # Find local extremes
    price_low_idx = np.argmin(recent_prices)
    price_high_idx = np.argmax(recent_prices)
    
    # Current values
    current_price = prices[-1]
    current_rsi = rsi[-1]
    
    # Check for bullish divergence
    bullish = False
    if current_price < recent_prices[price_low_idx]:
        # Price made lower low
        if current_rsi > recent_rsi[price_low_idx]:
            # RSI made higher low = bullish divergence
            bullish = True
    
    # Check for bearish divergence
    bearish = False
    if current_price > recent_prices[price_high_idx]:
        # Price made higher high
        if current_rsi < recent_rsi[price_high_idx]:
            # RSI made lower high = bearish divergence
            bearish = True
    
    return bullish, bearish
