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
    logger.info("ADAPTIVE MULTI-STRATEGY ENGINE - BACKTEST")
    logger.info("Forex Fury + Waka Waka | Professional Grade")
    logger.info("="*70)

    # Configure backtest
    config = BacktestConfig(
        # Account
        initial_balance=10.0,  # $10 challenge

        # Symbol & Timeframe
        symbol="EURUSD",
        timeframe="H4",  # H4 - Probado y funciona

        # Date range (2 years for statistical significance)
        start_date=datetime(2022, 1, 1),
        end_date=datetime(2023, 12, 31),

        # Strategy parameters - 30% RIESGO
        min_confluence_score=7,
        risk_percent=30.0,  # 30% riesgo = $3 por trade con $10
        max_trades=1,

        # Breakout + Liquidity engine config
        swing_length=10,  # Swing detection period
        ob_lookback=50,  # Not used (legacy)
        fvg_min_size=0.3,  # Not used (legacy)
        vp_lookback=100,  # Not used (legacy)

        # Execution costs
        slippage_pips=1.0,  # 1 pip slippage
        commission_per_lot=7.0,  # $7 per lot roundtrip

        # Advanced
        enable_trailing_stop=True,  # Breakeven at 1R, lock profit at 2R+
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
