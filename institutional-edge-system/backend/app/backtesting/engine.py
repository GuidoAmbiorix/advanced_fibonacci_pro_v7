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

from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine
from app.services.risk_manager import AdaptiveRiskManager
from app.services.portfolio_manager import PortfolioManager, Position


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
            commission_per_lot=config.commission_per_lot,
            enable_trailing_stop=config.enable_trailing_stop,
            min_hold_hours=4.0  # Minimum 4-hour hold time
        )

        # Trading state
        self.open_trades: List[BacktestTrade] = []
        self.closed_trades: List[BacktestTrade] = []
        self.equity_curve: List[dict] = []
        self.current_balance = config.initial_balance
        self.peak_balance = config.initial_balance  # Track for drawdown

        # Trading engine
        self.trading_engine = self._init_trading_engine()

        # Risk Management (same as live trading)
        self.risk_manager = AdaptiveRiskManager(base_risk_percent=config.risk_percent)
        self.portfolio_manager = PortfolioManager(max_portfolio_risk=100.0)  # Allow aggressive testing

        logger.info(f"BacktestEngine initialized - {config.symbol} {config.timeframe}")
        logger.info("✅ Using AdaptiveRiskManager + PortfolioManager (same as live trading)")

    def _init_trading_engine(self) -> AdaptiveMultiStrategyEngine:
        """Initialize the Adaptive Multi-Strategy engine"""
        engine_config = {
            'symbol': self.config.symbol,
            'timeframe': self.config.timeframe,
            'initial_balance': self.config.initial_balance,
            'max_risk_per_trade': 50.0,  # Max 50% risk (for aggressive testing)
            'enable_grid_recovery': True,  # Waka Waka style
            'grid_levels': 3,  # 3 recovery levels
        }

        return AdaptiveMultiStrategyEngine(engine_config)

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

        # Load H4 data for higher timeframe filter
        h4_data = None
        try:
            logger.info("Loading H4 data for higher timeframe filter...")
            h4_data = self.data_loader.load_and_validate(
                symbol=self.config.symbol,
                timeframe='H4',
                start_date=start_date or self.config.start_date,
                end_date=end_date or self.config.end_date,
                source='mt5'
            )
            if h4_data is not None:
                logger.info(f"Loaded {len(h4_data)} H4 bars for trend filtering")
            else:
                logger.warning("H4 data not available - will trade without HTF filter")
        except Exception as e:
            logger.warning(f"Could not load H4 data: {e} - continuing without HTF filter")

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
            # Reset index to avoid index errors in trading engine
            historical_data = historical_data.reset_index(drop=True)

            # Get H4 data up to current time (for trend filter)
            h4_historical = None
            if h4_data is not None:
                current_time = current_bar['time']
                # Get H4 bars up to current H1 bar time
                h4_mask = h4_data['time'] <= current_time
                h4_historical = h4_data[h4_mask].copy()
                if len(h4_historical) > 0:
                    h4_historical = h4_historical.reset_index(drop=True)

            # Run strategy analysis
            try:
                analysis = self.trading_engine.analyze(historical_data, df_higher_tf=h4_historical)

                if 'error' in analysis:
                    continue

                # Process signals from Adaptive Multi-Strategy Engine
                for signal in analysis.get('signals', []):
                    # AdaptiveSignal has .score and .confidence attributes
                    if hasattr(signal, 'score'):
                        score = signal.score
                        confidence = getattr(signal, 'confidence', 1.0)
                    else:
                        continue

                    # Filter by minimum score
                    # Note: Each strategy has fixed scores (Trend=8, Range=7, Breakout=9)
                    if score < self.config.min_confluence_score:
                        logger.debug(f"Signal rejected: score {score} < {self.config.min_confluence_score}")
                        continue

                    # Additional filter: confidence threshold (LOW for debugging)
                    if confidence < 0.1:  # Very low threshold for debugging
                        logger.debug(f"Signal rejected: low confidence {confidence:.2f}")
                        continue

                    # Check if can open (max trades)
                    if len(self.open_trades) >= self.config.max_trades:
                        break

                    # Convert BreakoutSignal to dict for simulator
                    signal_dict = {
                        'symbol': self.config.symbol,
                        'signal_type': signal.direction,  # "BUY" or "SELL"
                        'entry_price': signal.entry_price,
                        'stop_loss': signal.stop_loss,
                        'take_profit_1': signal.take_profit,
                        'confluence_score': signal.score,
                    }

                    # PROFESSIONAL RISK MANAGEMENT (same as live trading)

                    # STEP 1: Portfolio Manager - Check portfolio-level risk
                    # Update portfolio with current open positions
                    self.portfolio_manager.positions.clear()
                    for open_trade in self.open_trades:
                        self.portfolio_manager.positions.append(Position(
                            symbol=open_trade.symbol,
                            volume=open_trade.volume,
                            risk_percent=open_trade.risk_percent if hasattr(open_trade, 'risk_percent') else self.config.risk_percent
                        ))

                    # Check if can open new position
                    can_open, reason = self.portfolio_manager.can_open_position(
                        symbol=signal_dict.get('symbol', self.config.symbol),
                        proposed_risk=self.config.risk_percent,
                        account_balance=self.current_balance
                    )

                    if not can_open:
                        logger.debug(f"Portfolio Manager blocked trade: {reason}")
                        continue

                    # STEP 2: Adaptive Risk Manager - Calculate dynamic risk
                    # Update peak balance
                    if self.current_balance > self.peak_balance:
                        self.peak_balance = self.current_balance

                    # Calculate current drawdown
                    current_equity = self._calculate_current_equity(current_bar)
                    current_dd = ((self.peak_balance - current_equity) / self.peak_balance * 100) if self.peak_balance > 0 else 0.0

                    # Get consecutive losses
                    consecutive_losses = self._count_consecutive_losses()

                    # Calculate adaptive risk
                    adaptive_risk_percent, risk_reason = self.risk_manager.calculate_risk_percent(
                        market_regime="NORMAL",
                        consecutive_losses=consecutive_losses,
                        current_volatility_percentile=50,
                        current_drawdown=current_dd
                    )

                    if adaptive_risk_percent == 0:
                        logger.warning(f"🛑 CIRCUIT BREAKER: {risk_reason}")
                        break  # Stop opening new trades

                    # Execute entry with adaptive risk
                    trade = self.simulator.execute_entry(
                        signal=signal_dict,
                        current_bar=current_bar,
                        account_balance=self.current_balance,
                        risk_percent=adaptive_risk_percent  # Use adaptive risk
                    )

                    if trade:
                        self.open_trades.append(trade)
                        logger.debug(
                            f"[{current_bar['time']}] Opened {trade.signal_type} "
                            f"@ {trade.entry_price:.5f}, Score: {trade.confluence_score}/10"
                        )

            except Exception as e:
                import traceback
                logger.error(f"Error analyzing bar {i}: {e}")
                logger.debug(f"Full traceback: {traceback.format_exc()}")
                continue

            # Track equity
            current_equity = self._calculate_current_equity(current_bar)
            self.equity_curve.append({
                'time': current_bar['time'],
                'balance': self.current_balance,
                'equity': current_equity
            })

            # Progress logging (every 500 bars for better visibility)
            if (i + 1) % 500 == 0:
                progress_pct = ((i + 1) / len(data)) * 100
                elapsed = time.time() - start_time
                bars_per_sec = (i + 1) / elapsed if elapsed > 0 else 0
                eta_seconds = (len(data) - (i + 1)) / bars_per_sec if bars_per_sec > 0 else 0
                eta_minutes = eta_seconds / 60

                logger.info(
                    f"Progress: {i+1}/{len(data)} bars ({progress_pct:.1f}%) | "
                    f"Trades: {len(self.closed_trades)} | "
                    f"Balance: ${self.current_balance:.2f} | "
                    f"Speed: {bars_per_sec:.1f} bars/sec | "
                    f"ETA: {eta_minutes:.1f} min"
                )

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

    def _count_consecutive_losses(self) -> int:
        """
        Count consecutive losing trades from most recent
        Used by AdaptiveRiskManager
        """
        if not self.closed_trades:
            return 0

        consecutive = 0
        # Iterate backwards through closed trades
        for trade in reversed(self.closed_trades):
            if trade.pnl < 0:  # Loss
                consecutive += 1
            else:  # Win or breakeven
                break

        return consecutive

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
