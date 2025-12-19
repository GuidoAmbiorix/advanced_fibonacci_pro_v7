"""
Test Script for RSI/MFI Enhancement Verification
Target: Q4 2025 (Choppy Market)
"""

import sys
from pathlib import Path
from datetime import datetime

# Add app to path
sys.path.insert(0, str(Path(__file__).parent))

from app.backtesting.engine import BacktestEngine
from app.backtesting.models import BacktestConfig
from loguru import logger

def main():
    # Configure logger
    logger.add("logs/test_rsi_mfi_{time}.log", rotation="1 day", level="INFO")

    logger.info("="*70)
    logger.info("RSI/MFI ENHANCEMENT VERIFICATION")
    logger.info("Target: Q4 2025 (Whipsaw Period)")
    logger.info("="*70)

    # Configure backtest with User's Settings
    config = BacktestConfig(
        initial_balance=1000.0,
        symbol="EURUSD",
        timeframe="M15",
        
        # Q4 2025 Whipsaw Period
        start_date=datetime(2025, 10, 1),
        end_date=datetime(2025, 10, 12),

        # Strategy Config
        scalping_mode=True,
        enable_institutional_strategy=True,
        enable_vwap_strategy=True,
        enable_stoch_strategy=True,
        # enable_fibonacci_strategy=True, # Assuming this field exists or will be defaulted

        # Risk
        risk_percent=2.0,
        max_trades=1,

        # Execution
        slippage_pips=1.0,
        commission_per_lot=7.0,

        # Management
        enable_trailing_stop=True,
        tsl_mode="TIERED",
        tsl_activation_r=0.0,
        partial_tp_on=True,
        partial_tp_amount=0.5
    )

    # Create engine
    engine = BacktestEngine(config)

    # Run backtest
    logger.info("Starting backtest...")
    results = engine.run()

    # Print summary
    from app.backtesting.metrics import MetricsCalculator
    print(MetricsCalculator.generate_summary_text(results.metrics))

if __name__ == "__main__":
    main()
