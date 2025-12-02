"""
Example Backtest Script
Run a backtest on EURUSD H1 data
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
    """Run example backtest"""

    # Configure logger
    logger.add(
        "logs/backtest_{time}.log",
        rotation="1 day",
        retention="7 days",
        level="INFO"
    )

    logger.info("="*70)
    logger.info("INSTITUTIONAL EDGE PRO - BACKTEST")
    logger.info("="*70)

    # Configure backtest
    config = BacktestConfig(
        # Account
        initial_balance=10000.0,

        # Symbol & Timeframe
        symbol="EURUSD",
        timeframe="H1",

        # Date range (3 years)
        start_date=datetime(2021, 1, 1),
        end_date=datetime(2023, 12, 31),

        # Strategy parameters
        min_confluence_score=7,  # Conservative: 7/10
        risk_percent=1.0,  # 1% risk per trade
        max_trades=1,  # One trade at a time

        # Trading engine config
        swing_length=10,
        ob_lookback=50,
        fvg_min_size=0.3,
        vp_lookback=100,

        # Execution costs
        slippage_pips=1.0,  # 1 pip slippage
        commission_per_lot=7.0,  # $7 per lot roundtrip

        # Advanced (disabled for now)
        enable_trailing_stop=False,
        enable_partial_tp=False,
    )

    # Create engine
    engine = BacktestEngine(config)

    # Run backtest
    logger.info("Starting backtest...")
    results = engine.run()

    # Generate report
    logger.info("Generating report...")
    report_files = engine.generate_report(
        results,
        output_dir="reports",
        report_name=f"backtest_{config.symbol}_{config.timeframe}"
    )

    logger.info("Report files generated:")
    for name, path in report_files.items():
        logger.info(f"  - {name}: {path}")

    # Print summary
    from app.backtesting.metrics import MetricsCalculator
    print(MetricsCalculator.generate_summary_text(results.metrics))

    # Final verdict
    m = results.metrics
    is_passing = (
        m.total_trades >= 50 and
        m.win_rate >= 45.0 and
        m.profit_factor >= 1.5 and
        m.max_drawdown_percent < 15.0 and
        m.average_rr >= 2.0
    )

    print("\n" + "="*64)
    if is_passing:
        print("✅ STRATEGY VALIDATED - Ready for demo trading")
    else:
        print("❌ STRATEGY NEEDS IMPROVEMENT - Do NOT trade live")
    print("="*64 + "\n")

    # Shutdown
    engine.data_loader.shutdown()


if __name__ == "__main__":
    main()
