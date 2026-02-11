import numpy as np
import pandas as pd
from typing import Optional

def triple_barrier_labels(
    prices: pd.Series,
    volatility: pd.Series,
    time_horizon_bars: int = 24,
    pt_sl: list = [2, 1],
    min_ret: float = 0.0,
    vertical_barrier: bool = True
) -> pd.Series:
    """
    Implements the Triple Barrier Method for labeling.
    
    Args:
        prices: Series of close prices
        volatility: Series of volatility (e.g. ATR or rolling std)
        time_horizon_bars: Max bars to hold the trade (vertical barrier)
        pt_sl: List of [Profit Take multiplier, Stop Loss multiplier]
        min_ret: Minimum target return required to run the barrier search
        vertical_barrier: Whether to enable the vertical barrier
        
    Returns:
        pd.Series of labels:
            1: Profit Take hit
            -1: Stop Loss hit
            0: Vertical Barrier hit (or neither hit)
    """
    
    # Pre-compute barrier levels
    upper_barrier = volatility * pt_sl[0]
    lower_barrier = volatility * pt_sl[1]
    
    # Initialize labels
    out_labels = pd.Series(index=prices.index, data=0)
    
    # Compute barrier touches (vectorized where possible, but loop often needed for path dependency)
    # For speed, we can use a rolling window approach or pure numpy
    
    # Converting to numpy for speed
    price_values = prices.values
    upper_vals = upper_barrier.values
    lower_vals = lower_barrier.values
    
    n_samples = len(price_values)
    
    # This loop is the bottleneck - optimized with numpy logic where possible
    # But for exact path dependency (which hits first), iteration is safest
    for i in range(n_samples - time_horizon_bars):
        current_price = price_values[i]
        
        # Define the horizon window
        end_idx = min(i + time_horizon_bars, n_samples)
        window_prices = price_values[i+1 : end_idx]
        
        # Calculate returns relative to entry
        returns = (window_prices - current_price) / current_price
        
        # Get barriers for this timestamp
        ub = upper_vals[i]
        lb = -lower_vals[i] # Stop loss is negative return
        
        # minimal return filter
        if ub < min_ret:
            continue
            
        # Check touches
        # First index where return >= ub
        pt_hit_indices = np.where(returns >= ub)[0]
        # First index where return <= lb
        sl_hit_indices = np.where(returns <= lb)[0]
        
        first_pt = pt_hit_indices[0] if len(pt_hit_indices) > 0 else end_idx + 1 # +1 to be > horizon
        first_sl = sl_hit_indices[0] if len(sl_hit_indices) > 0 else end_idx + 1
        
        if first_pt == end_idx + 1 and first_sl == end_idx + 1:
            # Neither hit
            label = 0
        elif first_pt < first_sl:
            # PT hit first
            label = 1
        elif first_sl < first_pt:
            # SL hit first
            label = -1
        else:
            # Should not happen if strictly <
            label = 0
            
        out_labels.iloc[i] = label
        
    return out_labels
