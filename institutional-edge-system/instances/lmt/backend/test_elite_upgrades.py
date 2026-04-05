import pandas as pd
import numpy as np
from datetime import datetime
from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine
from app.core.news_filter import NewsFilter

def test_elite_upgrades():
    print("--- Testing NewsFilter ---")
    nf = NewsFilter()
    # Test safe check with current time
    is_imminent = nf.should_block_trade(current_time=datetime.now())
    print(f"News Filter Block Trade (Live): {is_imminent}")
    
    print("\n--- Testing Engine & Indicators ---")
    config = {
        'symbol': 'EURUSD',
        'timeframe': 'H1',
        'initial_balance': 10000
    }
    engine = AdaptiveMultiStrategyEngine(config)
    
    # Create Dummy Data
    dates = pd.date_range(start='2024-01-01', periods=100, freq='1h')
    df = pd.DataFrame({
        'time': dates,
        'open': np.random.randn(100).cumsum() + 100,
        'high': np.random.randn(100).cumsum() + 105,
        'low': np.random.randn(100).cumsum() + 95,
        'close': np.random.randn(100).cumsum() + 100,
        'tick_volume': np.random.randint(100, 1000, 100),
        'volume': np.random.randint(100, 1000, 100),
        'spread': 10
    })
    
    # Run Indicators
    print("Calculating indicators (including KER/RVOL)...")
    df = engine._ensure_indicators(df)
    
    if 'ker' in df.columns:
        print(f"R KER Calculated. Last value: {df['ker'].iloc[-1]:.4f}")
    else:
        print("❌ KER Missing")
        
    if 'rvol' in df.columns:
        print(f"R RVOL Calculated. Last value: {df['rvol'].iloc[-1]:.4f}")
    else:
        print("❌ RVOL Missing")
        
    # Check Governance
    print("\n--- Testing Governance Logic ---")
    # Mocking news filter to return TRUE for blocking
    original_should_block = engine.news_filter.should_block_trade
    engine.news_filter.should_block_trade = lambda current_time=None: True
    
    allowed, reason = engine._check_funding_rules(datetime.now())
    if not allowed and "NEWS FILTER" in reason:
        print("R Governance correctly blocked trade due to News Filter")
    else:
        print(f"❌ Governance FAILED to block trade. Result: {allowed}, Reason: {reason}")
    
    # Reset mock
    engine.news_filter.should_block_trade = original_should_block

if __name__ == "__main__":
    test_elite_upgrades()
