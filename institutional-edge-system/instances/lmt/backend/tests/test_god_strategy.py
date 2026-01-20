import sys
import os
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# Add backend to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from app.core.trading_engine import TradingEngine
from app.core.config import settings

def create_mock_data(length=200):
    """Create mock OHLCV data with a perfect bullish setup"""
    dates = pd.date_range(end=datetime.now(), periods=length, freq='1h')
    
    # Create an uptrend
    close = np.linspace(1.0, 1.1, length)
    
    # Add some noise
    noise = np.random.normal(0, 0.001, length)
    close += noise
    
    # Ensure EMA50 > EMA200 (uptrend)
    # We'll just make the price rise steadily so EMAs align naturally
    
    df = pd.DataFrame({
        'time': dates,
        'open': close - 0.001,
        'high': close + 0.002,
        'low': close - 0.002,
        'close': close,
        'volume': np.random.randint(100, 1000, length)
    })
    
    # Force OBV rise in last few bars
    df.iloc[-1, df.columns.get_loc('volume')] = 5000
    df.iloc[-2, df.columns.get_loc('volume')] = 4000
    df.iloc[-3, df.columns.get_loc('volume')] = 3000
    
    return df

def test_god_strategy():
    print("Testing God Combination Strategy...")
    
    config = {
        'symbol': 'TEST',
        'timeframe': 'H1',
        'EMA_FAST': 10, # Shorten for test
        'EMA_SLOW': 20,
        'min_confluence_score': 0 # We just want to see if logic runs
    }
    
    engine = TradingEngine(config)
    df = create_mock_data(300)
    
    try:
        result = engine.analyze(df)
        print("Analysis successful!")
        print(f"Signals generated: {len(result['signals'])}")
        
        if result['signals']:
            print("Signal details:", result['signals'][0])
            
        print("Indicators calculated:")
        print(f"EMA50 present: {'ema50' in df.columns}")
        print(f"MACD present: {'macd' in df.columns}")
        print(f"OBV present: {'obv' in df.columns}")
        
    except Exception as e:
        print(f"Analysis failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_god_strategy()
