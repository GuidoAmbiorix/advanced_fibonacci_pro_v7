
import socket
import sys
import os
import pandas as pd
import numpy as np
from datetime import datetime
import logging
# Configure basic logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add project root to path
sys.path.append(os.getcwd())

# Mock loguru before importing app
from unittest.mock import MagicMock
mock_logger = MagicMock()
sys.modules["loguru"] = MagicMock()
sys.modules["loguru"].logger = mock_logger

try:
    from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine, MarketRegime
except ImportError:
    # Fallback to direct import if running from root relative path issues
    sys.path.append(os.path.join(os.getcwd(), 'institutional-edge-system', 'backend'))
    from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine, MarketRegime

def create_mock_df(timestamp_str, close_price=1.1000):
    """Create a basic mock DataFrame with required columns"""
    data = {
        'time': [pd.to_datetime(timestamp_str)],
        'open': [close_price],
        'high': [close_price + 0.0010],
        'low': [close_price - 0.0010],
        'close': [close_price],
        'volume': [1000],
        'ema_20': [close_price - 0.0005], # Bullish trend
        'ema_50': [close_price - 0.0010],
        'ema_200': [close_price - 0.0020],
        'rsi': [40], # Oversold-ish
        'atr': [0.0010],
        'adx': [30],
        'macd_histogram': [0.0001],
        'volume_ratio': [2.5],
        'stoch_k': [15],
        'stoch_d': [10],
        'bb_upper': [close_price + 0.0020],
        'bb_lower': [close_price - 0.0020],
        'bb_middle': [close_price],
    }
    # Create 100 rows to satisfy length checks, but only last one matters for signal
    df = pd.DataFrame(data)
    df = pd.concat([df]*100, ignore_index=True)
    # Update time for the last row
    df.iloc[-1, df.columns.get_loc('time')] = pd.to_datetime(timestamp_str)
    return df

def test_funding_rules():
    print("=== Testing Funding Rules ===")
    
    config = {
        'symbol': 'EURUSD',
        'initial_balance': 100000.0,
        'max_drawdown_limit': 0.10, # 10%
        'daily_loss_limit': 0.05,   # 5%
        'risk_reward_ratio': 2.0    # 1:2 R/R
    }
    
    engine = AdaptiveMultiStrategyEngine(config)
    
    # 1. Test Schedule (Valid Time)
    # Mon-Fri, 01:00 - 12:00
    valid_time = "2023-10-27 10:00:00" # Friday
    df_valid = create_mock_df(valid_time)
    
    allowed, reason = engine._check_funding_rules(pd.to_datetime(valid_time))
    if allowed:
        print(f"✅ PASS: Valid time {valid_time} accepted.")
    else:
        print(f"❌ FAIL: Valid time {valid_time} rejected. Reason: {reason}")
        
    # 2. Test Schedule (Invalid Time - Afternoon)
    invalid_time_afternoon = "2023-10-27 14:00:00"
    allowed, reason = engine._check_funding_rules(pd.to_datetime(invalid_time_afternoon))
    if not allowed and "Outside Trading Hours" in reason:
        print(f"✅ PASS: Invalid time {invalid_time_afternoon} correctly rejected.")
    else:
        print(f"❌ FAIL: Invalid time {invalid_time_afternoon} NOT rejected properly. Result: {allowed}, Reason: {reason}")

    # 3. Test Schedule (Invalid Time - Weekend)
    invalid_time_weekend = "2023-10-28 10:00:00" # Saturday
    allowed, reason = engine._check_funding_rules(pd.to_datetime(invalid_time_weekend))
    if not allowed and "Weekend" in reason:
        print(f"✅ PASS: Weekend time {invalid_time_weekend} correctly rejected.")
    else:
        print(f"❌ FAIL: Weekend time {invalid_time_weekend} NOT rejected. Result: {allowed}, Reason: {reason}")
        
    # 4. Test Daily Loss Limit
    # Simulate loss: Start day 100k, Current 94k (6% loss)
    engine.update_account_metrics(balance=94000, equity=94000, start_of_day_balance=100000)
    allowed, reason = engine._check_funding_rules(pd.to_datetime(valid_time))
    if not allowed and "DAILY LOSS" in reason:
        print(f"✅ PASS: Daily Loss limit (>5%) correctly triggered.")
    else:
        print(f"❌ FAIL: Daily Loss limit NOT triggered. Result: {allowed}, Reason: {reason}")

    # Reset metrics
    engine.update_account_metrics(balance=100000, equity=100000, start_of_day_balance=100000)
    
    # 5. Test Max Drawdown Limit
    # Simulate total loss: Initial 100k, Current 89k (11% loss)
    engine.update_account_metrics(balance=89000, equity=89000, start_of_day_balance=95000)
    allowed, reason = engine._check_funding_rules(pd.to_datetime(valid_time))
    if not allowed and "MAX DRAWDOWN" in reason:
        print(f"✅ PASS: Max Drawdown limit (>10%) correctly triggered.")
    else:
        print(f"❌ FAIL: Max Drawdown limit NOT triggered. Result: {allowed}, Reason: {reason}")

def test_dynamic_rr():
    print("\n=== Testing Dynamic R/R ===")
    config = {
        'symbol': 'EURUSD',
        'risk_reward_ratio': 3.0, # 1:3 R/R
        'sl_atr_multiplier': 1.0
    }
    engine = AdaptiveMultiStrategyEngine(config)
    
    # We will test _trend_following_signal logic indirectly by simulating conditions that trigger a buy
    # or simpler, checking the R/R calculation in the method source logic
    # But for a script, checking attributes is easier if we can't easily force a signal without complex data setup.
    
    # Verify attribute is set
    if engine.tp_ratio == 3.0:
        print(f"✅ PASS: Engine tp_ratio initialized to {engine.tp_ratio} (Target: 3.0)")
    else:
        print(f"❌ FAIL: Engine tp_ratio mismatch: {engine.tp_ratio}")

if __name__ == "__main__":
    test_funding_rules()
    test_dynamic_rr()
