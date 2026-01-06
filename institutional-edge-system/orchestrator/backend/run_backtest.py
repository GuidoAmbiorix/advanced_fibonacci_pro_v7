"""
Example Backtest Script
Run a backtest on EURUSD H1 data
"""

import sys
from pathlib import Path
from datetime import datetime
from typing import List

# Add app to path
sys.path.insert(0, str(Path(__file__).parent))

from app.backtesting.engine import BacktestEngine
from app.backtesting.models import BacktestConfig, SimulatedSlaveConfig
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
    logger.info("ADAPTIVE MULTI-STRATEGY ENGINE - MULTI-ACCOUNT BACKTEST")
    logger.info("M1 Execution + M5 Confirmation | Scalping Mode")
    logger.info("="*70)
    
    # --- MULTI-ACCOUNT SIMULATION CONFIG ---
    slaves = [
        SimulatedSlaveConfig(
            name="Aggressive_Clone",
            initial_balance=5000,
            mode="MULTIPLIER",
            risk_multiplier=2.0  # Double risk
        ),
        SimulatedSlaveConfig(
            name="Conservative_Clone",
            initial_balance=25000,
            mode="RISK_PERCENT",
            max_risk_percent=0.5  # Fixed 0.5% risk
        ),
        SimulatedSlaveConfig(
            name="Inverse_Trader",
            initial_balance=10000,
            mode="MULTIPLIER",
            risk_multiplier=1.0,
            reverse_copy=True,
            slippage_pips=1.0 # Extra slippage
        )
    ]

    # Configure backtest
    config = BacktestConfig(
        # Account
        initial_balance=10000.0,
        
        # Copy Trading Simulation
        slave_configs=slaves,

        # Symbol & Timeframe - SCALPING MODE
        symbol="EURUSD",
        timeframe="M1",  # M1 - Scalping rápido
        confirmation_timeframe="M5",  # Confirmación en 5 minutos

        # Date range (1 month for M1 testing - ~43,200 bars)
        start_date=datetime(2024, 10, 1),
        end_date=datetime(2024, 10, 31),

        # Strategy parameters - 30% RIESGO
        min_confluence_score=7,
        risk_percent=5.0,  # 5% for master to allow slaves to scale
        max_trades=1,

        # Execution costs (tighter for M1 scalping)
        slippage_pips=0.5,  # 0.5 pip slippage for faster fills
        commission_per_lot=7.0,  # $7 per lot roundtrip

        # Advanced - Enable scalping mode
        enable_trailing_stop=True,  # Breakeven at 1R, lock profit at 2R+
        partial_tp_on=False,
        scalping_mode=True,  # Enable for M1
    )

    # Create engine
    try:
        engine = BacktestEngine(config)
    except Exception as e:
        logger.error(f"Failed to initialize engine: {e}")
        return

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
    print("\n" + "="*64)
    print("MASTER ACCOUNT PERFORMANCE")
    print("="*64)
    print(MetricsCalculator.generate_summary_text(results.metrics))
    
    # Print Slave Results
    if results.slave_results:
        print("\n" + "="*64)
        print("COPY TRADING SIMULATION RESULTS")
        print("="*64)
        for slave_name, slave_res in results.slave_results.items():
            print(f"\n👥 SLAVE: {slave_name}")
            print("-" * 30)
            print(f"Total Trades:  {slave_res.metrics.total_trades}")
            print(f"Net Profit:    ${slave_res.metrics.net_profit:.2f}")
            print(f"Win Rate:      {slave_res.metrics.win_rate:.2f}%")
            print(f"Max Drawdown:  {slave_res.metrics.max_drawdown_percent:.2f}%")
            print(f"Profit Factor: {slave_res.metrics.profit_factor:.2f}")

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
