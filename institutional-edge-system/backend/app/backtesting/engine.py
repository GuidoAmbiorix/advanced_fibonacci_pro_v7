"""
Backtesting Engine
Main orchestrator for running strategy backtests
"""

import pandas as pd
from datetime import datetime
from typing import Optional, List
from loguru import logger
import time

from app.backtesting.models import (
    BacktestConfig,
    BacktestResults,
    BacktestTrade,
    BacktestMetrics
)
from app.backtesting.data_loader import DataLoader
from app.backtesting.simulator import OrderSimulator
from app.backtesting.metrics import MetricsCalculator
from app.backtesting.reporter import ReportGenerator

from app.core.trading_engine import TradingEngine


class BacktestEngine:
    """
    Main backtesting engine

    Orchestrates:
    1. Data loading
    2. Strategy execution
    3. Order simulation
    4. Metrics calculation
    5. Report generation
    """

    def __init__(self, config: BacktestConfig):
        """
        Initialize backtest engine

        Args:
            config: Backtest configuration
        """
        self.config = config
        self.data_loader = DataLoader()
        self.simulator = OrderSimulator(
            slippage_pips=config.slippage_pips,
            commission_per_lot=config.commission_per_lot
        )

        # Trading state
        self.open_trades: List[BacktestTrade] = []
        self.closed_trades: List[BacktestTrade] = []
        self.equity_curve: List[dict] = []
        self.current_balance = config.initial_balance

        # Trading engine
        self.trading_engine = self._init_trading_engine()

        logger.info(f"BacktestEngine initialized - {config.symbol} {config.timeframe}")

    def _init_trading_engine(self) -> TradingEngine:
        """Initialize the trading engine with config"""
        engine_config = {
            'symbol': self.config.symbol,
            'timeframe': self.config.timeframe,
            'swing_length': self.config.swing_length,
            'ob_lookback': self.config.ob_lookback,
            'fvg_min_size': self.config.fvg_min_size,
            'min_confluence_score': self.config.min_confluence_score,
            'vp_lookback': self.config.vp_lookback,
        }

        return TradingEngine(engine_config)

    def run(
        self,
        data: Optional[pd.DataFrame] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> BacktestResults:
        """
        Run backtest

        Args:
            data: Historical data (if not provided, will load from config)
            start_date: Override start date
            end_date: Override end date

        Returns:
            BacktestResults with all metrics and trades
        """
        start_time = time.time()

        logger.info("="*60)
        logger.info("STARTING BACKTEST")
        logger.info("="*60)

        # Load data if not provided
        if data is None:
            data = self._load_data(start_date, end_date)
            if data is None:
                logger.error("Failed to load data")
                return self._create_empty_results()

        logger.info(f"Backtesting on {len(data)} bars")

        # Initialize equity curve
        self.equity_curve.append({
            'time': data.iloc[0]['time'] if len(data) > 0 else None,
            'balance': self.current_balance,
            'equity': self.current_balance
        })

        # Main backtest loop
        for i in range(len(data)):
            current_bar = data.iloc[i]

            # Update open positions
            self._update_open_positions(current_bar)

            # Check if can open new trades
            if len(self.open_trades) >= self.config.max_trades:
                continue

            # Need enough historical data for analysis
            if i < 100:  # Need at least 100 bars for indicators
                continue

            # Get historical window for analysis
            lookback_window = min(500, i)  # Use up to 500 bars
            historical_data = data.iloc[max(0, i - lookback_window):i + 1].copy()

            # Run strategy analysis
            try:
                analysis = self.trading_engine.analyze(historical_data, df_higher_tf=None)

                if 'error' in analysis:
                    continue

                # Process signals
                for signal in analysis.get('signals', []):
                    # Check confluence score
                    if signal.get('confluence_score', 0) < self.config.min_confluence_score:
                        continue

                    # Check if can open (max trades)
                    if len(self.open_trades) >= self.config.max_trades:
                        break

                    # Execute entry
                    trade = self.simulator.execute_entry(
                        signal=signal.__dict__ if hasattr(signal, '__dict__') else signal,
                        current_bar=current_bar,
                        account_balance=self.current_balance,
                        risk_percent=self.config.risk_percent
                    )

                    if trade:
                        self.open_trades.append(trade)
                        logger.debug(
                            f"[{current_bar['time']}] Opened {trade.signal_type} "
                            f"@ {trade.entry_price:.5f}, Score: {trade.confluence_score}/10"
                        )

            except Exception as e:
                logger.error(f"Error analyzing bar {i}: {e}")
                continue

            # Track equity
            current_equity = self._calculate_current_equity(current_bar)
            self.equity_curve.append({
                'time': current_bar['time'],
                'balance': self.current_balance,
                'equity': current_equity
            })

            # Progress logging (every 1000 bars)
            if (i + 1) % 1000 == 0:
                logger.info(f"Processed {i+1}/{len(data)} bars...")

        # Force close any remaining open trades
        if self.open_trades and len(data) > 0:
            last_bar = data.iloc[-1]
            for trade in self.open_trades:
                self.simulator.force_close(trade, last_bar, "END_OF_DATA")
                self.closed_trades.append(trade)
                self.current_balance += trade.pnl

        # Calculate metrics
        logger.info("Calculating performance metrics...")
        metrics = MetricsCalculator.calculate_all(
            self.closed_trades,
            self.config.initial_balance
        )

        # Create results
        results = BacktestResults(
            config=self.config,
            metrics=metrics,
            trades=self.closed_trades,
            equity_curve=self.equity_curve,
            start_date=data.iloc[0]['time'] if len(data) > 0 else None,
            end_date=data.iloc[-1]['time'] if len(data) > 0 else None,
            total_bars=len(data),
            execution_time_seconds=time.time() - start_time
        )

        # Log summary
        self._log_summary(results)

        logger.info("="*60)
        logger.info("BACKTEST COMPLETE")
        logger.info("="*60)

        return results

    def _load_data(
        self,
        start_date: Optional[datetime],
        end_date: Optional[datetime]
    ) -> Optional[pd.DataFrame]:
        """Load historical data"""
        start = start_date or self.config.start_date
        end = end_date or self.config.end_date

        if not start or not end:
            logger.error("Start and end dates required")
            return None

        logger.info(f"Loading data: {start} to {end}")

        return self.data_loader.load_and_validate(
            symbol=self.config.symbol,
            timeframe=self.config.timeframe,
            start_date=start,
            end_date=end,
            source='mt5'  # Will try MT5 first, add CSV fallback later
        )

    def _update_open_positions(self, current_bar: pd.Series):
        """Update all open positions and check for exits"""
        for trade in self.open_trades[:]:  # Copy list to allow removal
            status = self.simulator.update_position(trade, current_bar)

            if status.startswith("CLOSED"):
                # Trade closed
                self.open_trades.remove(trade)
                self.closed_trades.append(trade)

                # Update balance
                self.current_balance += trade.pnl

                # Log
                win_loss = "WIN" if trade.pnl > 0 else "LOSS"
                logger.debug(
                    f"[{current_bar['time']}] {win_loss}: {trade.signal_type} closed "
                    f"@ {trade.exit_price:.5f}, P&L: ${trade.pnl:.2f} ({trade.return_r:.2f}R)"
                )

    def _calculate_current_equity(self, current_bar: pd.Series) -> float:
        """Calculate current equity including open trades"""
        equity = self.current_balance

        for trade in self.open_trades:
            trade.update_open_pnl(current_bar['close'])
            equity += trade.pnl

        return equity

    def _create_empty_results(self) -> BacktestResults:
        """Create empty results in case of error"""
        return BacktestResults(
            config=self.config,
            metrics=BacktestMetrics(),
            trades=[],
            equity_curve=[],
        )

    def _log_summary(self, results: BacktestResults):
        """Log quick summary"""
        m = results.metrics

        logger.info("")
        logger.info("📊 BACKTEST SUMMARY")
        logger.info("-" * 60)
        logger.info(f"Total Trades:     {m.total_trades}")
        logger.info(f"Win Rate:         {m.win_rate:.2f}%")
        logger.info(f"Profit Factor:    {m.profit_factor:.2f}")
        logger.info(f"Net Profit:       ${m.net_profit:.2f}")
        logger.info(f"Max Drawdown:     {m.max_drawdown_percent:.2f}%")
        logger.info(f"Avg R:R:          {m.average_rr:.2f}")
        logger.info(f"Expectancy:       ${m.expectancy:.2f}")
        logger.info(f"Sharpe Ratio:     {m.sharpe_ratio:.2f}")
        logger.info("-" * 60)

        # Verdict
        is_passing = (
            m.total_trades >= 50 and
            m.win_rate >= 45.0 and
            m.profit_factor >= 1.5 and
            m.max_drawdown_percent < 15.0 and
            m.average_rr >= 2.0
        )

        verdict = "✅ PASS" if is_passing else "❌ FAIL"
        logger.info(f"VERDICT: {verdict}")
        logger.info("")

    def generate_report(
        self,
        results: BacktestResults,
        output_dir: str = "reports",
        report_name: str = "backtest"
    ) -> dict:
        """
        Generate full report with charts

        Args:
            results: Backtest results
            output_dir: Output directory
            report_name: Base name for files

        Returns:
            Dict of generated file paths
        """
        reporter = ReportGenerator(output_dir)
        return reporter.generate_full_report(results, report_name)
