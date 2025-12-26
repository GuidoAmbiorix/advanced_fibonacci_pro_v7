import pandas as pd
import numpy as np
import logging
from datetime import datetime, timedelta
from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine

import sys
from loguru import logger

# Enable Loguru to stderr
logger.remove()
logger.add(sys.stderr, level="DEBUG")

from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine

def create_mock_df(displacement=False):
    """Create a DF that mimics a Bullish Sweep Setup"""
    dates = pd.date_range(start='2024-01-01', periods=100, freq='1h')
    
    # Base price path
    prices = [100.0] * 100
    highs = [100.0] * 100
    lows = [100.0] * 100
    opens = [100.0] * 100
    closes = [100.0] * 100
    volume = [1000] * 100
    
    # 1. Swing High/Low setup (Bars 0-98)
    # Make a Swing Low at 95.0 within lookback (20 bars)
    lows[90] = 95.0
    highs[90] = 105.0
    
    # 2. Sweep Candle (Index 98 - Current-1)
    # Must dip below 95.0 and close above
    opens[98] = 96.0
    lows[98] = 94.0 # SWEEP of 95.0
    highs[98] = 97.0
    closes[98] = 96.5 
    
    # 3. Current Candle (Index 99)
    # If displacement=True, make it a BIG BULLISH candle
    opens[99] = 96.5
    lows[99] = 94.5 # SWEEP of 95.0 (Must be < 95.0)
    if displacement:
        highs[99] = 100.0
        closes[99] = 99.5 # Big body (5.0) -> Close > Swing Low (95.0) check OK
        volume[99] = 5000 # Spike
    else:
        highs[99] = 97.0
        closes[99] = 96.8 # Close > 95.0 OK
        volume[99] = 1000 # Normal
        
    df = pd.DataFrame({
        'time': dates,
        'open': opens,
        'high': highs,
        'low': lows,
        'close': closes,
        'volume': volume,
        'tick_volume': volume,
        'spread': 0,
        'atr': 0.5 # Mock ATR (0.5/100 = 0.005, safe for < 0.009 filter)
    })
    
    # Add indicators required by engine (ATR, Volume Ratio, etc defined inside, 
    # but engine expects some pre-calc if we call _liquidity_sweep_signal directly?
    # No, helper functions calc them.
    # checking requirements: _ensure_indicators
    
    return df

def test_brain_logic():
    print("--- Phase 3 Verification: The Brain ---")
    
    config = {
        'symbol': 'EURUSD', 
        'timeframe': 'M15',
        'enable_strategy_3_29_162': False
    }
    engine = AdaptiveMultiStrategyEngine(config)
    
    # Mock mocks
    engine.news_filter.should_block_trade = lambda current_time=None: False
    engine._is_valid_session = lambda t: True
    engine._is_kill_zone = lambda t: True
    engine._check_higher_tf_trend = lambda df: "BULLISH" # Align trend
    engine._detect_market_structure_shift = lambda df, d: True # Force MSS
    
    # Case 1: NO DISPLACEMENT
    print("\n[TEST 1] Testing Sweep WITHOUT Displacement...")
    df_weak = create_mock_df(displacement=False)
    # Run indicators
    df_weak = engine._ensure_indicators(df_weak)
    
    # We need to manually inject CVD to be rising/positive for the signal to reach the Scorer
    # The signal logic checks CVD first.
    # Let's mock _calculate_cvd to return rising series
    mock_cvd = pd.Series(np.linspace(0, 100, 100), index=df_weak.index)
    engine._calculate_cvd = lambda df: mock_cvd
    
    signal_weak = engine._liquidity_sweep_signal(df_weak, df_weak) # Pass df as HTF for simplicity
    
    if signal_weak:
        print(f"❌ FAILED: Weak signal accepted! Score: {signal_weak.score}")
    else:
        print("✅ PASSED: Weak signal REJECTED by Brain (Score too low)")
        
    # Case 2: WITH DISPLACEMENT
    print("\n[TEST 2] Testing Sweep WITH Displacement...")
    df_strong = create_mock_df(displacement=True)
    df_strong = engine._ensure_indicators(df_strong)
    
    signal_strong = engine._liquidity_sweep_signal(df_strong, df_strong)
    
    if signal_strong:
        print(f"✅ PASSED: Strong signal ACCEPTED! Score: {signal_strong.score}")
        print(f"   Reason: {signal_strong.metadata.get('brain_reason')}")
    else:
        print("❌ FAILED: Strong signal rejected unexpectedly.")

if __name__ == "__main__":
    test_brain_logic()
