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
    logger.info("M1 Execution + M5 Confirmation | Scalping Mode")
    logger.info("="*70)

    # Configure backtest
    config = BacktestConfig(
        # Account
        initial_balance=10.0,  # $10 challenge

        # Symbol & Timeframe - SCALPING MODE
        symbol="EURUSD",
        timeframe="M1",  # M1 - Scalping rápido
        confirmation_timeframe="M5",  # Confirmación en 5 minutos

        # Date range (1 month for M1 testing - ~43,200 bars)
        start_date=datetime(2024, 10, 1),
        end_date=datetime(2024, 10, 31),

        # Strategy parameters - 30% RIESGO
        min_confluence_score=7,
        risk_percent=30.0,  # 30% riesgo = $3 por trade con $10
        max_trades=1,

        # Breakout + Liquidity engine config
        swing_length=10,  # Swing detection period
        ob_lookback=50,  # Not used (legacy)
        fvg_min_size=0.3,  # Not used (legacy)
        vp_lookback=100,  # Not used (legacy)

        # Execution costs (tighter for M1 scalping)
        slippage_pips=0.5,  # 0.5 pip slippage for faster fills
        commission_per_lot=7.0,  # $7 per lot roundtrip

        # Advanced - Enable scalping mode
        enable_trailing_stop=True,  # Breakeven at 1R, lock profit at 2R+
        partial_tp_on=False,
        scalping_mode=True,  # Enable for M1
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
