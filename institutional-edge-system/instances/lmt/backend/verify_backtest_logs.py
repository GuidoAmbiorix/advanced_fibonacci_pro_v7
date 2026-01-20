import sys
import os
import asyncio
from datetime import datetime

# Add app to path
sys.path.append(os.getcwd())

from app.backtesting.engine import BacktestEngine
from app.backtesting.models import BacktestConfig

def test_backtest_logs():
    # Configure with very low risk to trigger warning
    config = BacktestConfig(
        symbol="XAUUSD",
        timeframe="M5",
        start_date=datetime(2024, 10, 1),
        end_date=datetime(2024, 10, 4),
        initial_balance=1000,
        risk_percent=0.001, # Trigger warning
        min_confluence_score=3,
        enable_institutional_strategy=True
    )
    
    engine = BacktestEngine(config)
    
    # We can't easily run full backtest without data, but we can check if engine init logs warning
    # Actually, let's try to run it. It might fail data loading but we'll see logs.
    print("Running backtest engine...")
    try:
        engine.run()
    except Exception as e:
        print(f"Run finished/failed (expected without data/MT5): {e}")

if __name__ == "__main__":
    test_backtest_logs()
