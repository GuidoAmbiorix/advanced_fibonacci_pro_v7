import pandas as pd
import numpy as np
import sys
from loguru import logger
from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine
from app.core.strategy_models import AdaptiveSignal, StrategyType, MarketRegime

# Enable Loguru to stderr
logger.remove()
logger.add(sys.stderr, level="DEBUG")

def test_smart_recovery():
    print("--- Phase 4 Verification: Smart Recovery (Fibonacci) ---")
    
    config = {
        'symbol': 'EURUSD', 
        'timeframe': 'H1',
        'enable_grid_recovery': True
    }
    engine = AdaptiveMultiStrategyEngine(config)
    
    # 1. Create Mock Data: Uptrend from 1.1000 to 1.1100
    dates = pd.date_range(start='2024-01-01', periods=100, freq='1h')
    closes = [1.1050] * 100
    lows = [1.1040] * 100
    highs = [1.1060] * 100
    
    # Set Anchor Low at index 50 (50 bars ago)
    lows[50] = 1.1000 # Anchor Low
    
    # Current Price (Entry) at index 99
    closes[99] = 1.1100 # Entry Price
    
    # Create DF
    df = pd.DataFrame({
        'time': dates,
        'open': closes,
        'high': highs,
        'low': lows,
        'close': closes,
        'volume': [1000]*100,
        'tick_volume': [1000]*100,
        'spread': 0,
        'atr': 0.0010,
        'rsi': 50.0 # Safe neutral RSI
    })
    
    # 2. Simulate a Signal
    signal = AdaptiveSignal(
        symbol='EURUSD',
        timeframe='H1',
        entry_price=1.1100,
        stop_loss=1.0900,
        take_profit=1.1200,
        direction="BUY", # We want to buy dip
        strategy_type=StrategyType.TREND_FOLLOWING,
        market_regime=MarketRegime.TRENDING,
        score=8.5,
        confidence=0.9
    )
    
    # 3. Call _wrap_signal to trigger wiring
    # We need to pass df so it can calculate levels
    # Ensure indicators are present (required by _calculate_market_condition_score called inside _wrap_signal)
    df = engine._ensure_indicators(df)
    
    # Use BREAKOUT_MOMENTUM to bypass Global RSI Check (we want to test wiring, not filters)
    result = engine._wrap_signal(signal, MarketRegime.TRENDING, StrategyType.BREAKOUT_MOMENTUM, df)
    
    # 4. Verify Grid Levels
    signal_out = result['signals'][0]
    levels = signal_out.grid_levels
    
    print(f"\nSignal Entry: {signal_out.entry_price}")
    print(f"Grid Levels Generated: {len(levels)}")
    
    range_height = 1.1100 - 1.1000 # 0.0100
    expected_618 = 1.1100 - (range_height * 0.618) # 1.10382
    expected_786 = 1.1100 - (range_height * 0.786) # 1.10214
    
    if len(levels) >= 2:
        l1 = levels[0]
        l2 = levels[1]
        
        print(f"Level 1 (Target: {expected_618:.5f}): {l1.price:.5f} [{l1.metadata}]")
        print(f"Level 2 (Target: {expected_786:.5f}): {l2.price:.5f} [{l2.metadata}]")
        
        # Check accuracy (allow small float error)
        if abs(l1.price - expected_618) < 0.0001 and abs(l2.price - expected_786) < 0.0001:
            print("R SUCCES: Smart Levels match Fibonacci calculations perfectly.")
        else:
            print("❌ FAILED: Levels do not match expected Fibonacci values.")
    else:
        print("❌ FAILED: No grid levels generated.")

if __name__ == "__main__":
    test_smart_recovery()
