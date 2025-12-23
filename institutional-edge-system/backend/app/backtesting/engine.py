"""
Backtesting Engine
Main orchestrator for running strategy backtests
"""

import pandas as pd
from datetime import datetime
from typing import Optional, List
from loguru import logger
import time
import asyncio
from app.services.discord_service import DiscordService

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
from app.core.strategy_factory import StrategyFactory
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
        self.data_loader = DataLoader()  # Restored: needed for loading data
        
        # Determine min hold time based on mode
        # Scalping: 15 min (0.25h), Swing: 4 hours
        min_hold = 0.25 if config.scalping_mode else 4.0
        
        self.simulator = OrderSimulator(
            slippage_pips=config.slippage_pips,
            commission_per_lot=config.commission_per_lot,
            enable_trailing_stop=config.enable_trailing_stop,
            min_hold_hours=min_hold,  # Dynamic based on mode
            tsl_mode=config.tsl_mode,
            tsl_activation_r=config.tsl_activation_r,
            partial_tp_on=config.partial_tp_on,
            partial_tp_amount=config.partial_tp_amount,
            max_trade_duration_hours=config.max_trade_duration_hours
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
        self.discord = DiscordService()

    def _init_trading_engine(self) -> AdaptiveMultiStrategyEngine:
        """Initialize the Adaptive Multi-Strategy engine"""
        engine_config = {
            'symbol': self.config.symbol,
            'timeframe': self.config.timeframe,
            'initial_balance': self.config.initial_balance,
            'max_risk_per_trade': 50.0,  # Max 50% risk (for aggressive testing)
            'enable_grid_recovery': True,  # Waka Waka style
            'grid_levels': 3,  # 3 recovery levels
            'scalping_mode': self.config.scalping_mode,
            'min_confluence_score': self.config.min_confluence_score,
            'use_adx_filter': self.config.use_adx_filter,
            'enable_vwap_strategy': self.config.enable_vwap_strategy,
            'enable_stoch_strategy': self.config.enable_stoch_strategy,
            'enable_institutional_strategy': self.config.enable_institutional_strategy,
            'enable_fibonacci_strategy': self.config.enable_fibonacci_strategy,
            'enable_strategy_3_29_162': self.config.enable_strategy_3_29_162,
            
            # RSI Settings
            'rsi_period': self.config.rsi_period,
            'rsi_overbought': self.config.rsi_overbought,
            'rsi_oversold': self.config.rsi_oversold,
            
            # Scalping SL/TP Configuration (NEW)
            'sl_atr_multiplier': self.config.sl_atr_multiplier,
            'tp_ratio': self.config.tp_ratio,
        }

        return StrategyFactory.create_strategy(engine_config)

    def run(
        self,
        data: Optional[pd.DataFrame] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        on_progress = None, # Callback(progress_pct, stats_dict)
        on_trade = None     # Callback(trade_dict)
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

        # Load higher timeframe data for trend confirmation filter
        htf_data = None
        htf_name = self.config.confirmation_timeframe
        try:
            logger.info(f"Loading {htf_name} data for higher timeframe filter...")
            htf_data = self.data_loader.load_and_validate(
                symbol=self.config.symbol,
                timeframe=htf_name,
                start_date=start_date or self.config.start_date,
                end_date=end_date or self.config.end_date,
                source='mt5'
            )
            if htf_data is not None:
                logger.info(f"Loaded {len(htf_data)} {htf_name} bars for trend filtering")
            else:
                logger.warning(f"{htf_name} data not available - will trade without HTF filter")
        except Exception as e:
            logger.warning(f"Could not load {htf_name} data: {e} - continuing without HTF filter")

        # Store callbacks for use in other methods
        self.on_trade_callback = on_trade
        self.on_progress_callback = on_progress

        # Initialize equity curve
        self.equity_curve.append({
            'time': data.iloc[0]['time'] if len(data) > 0 else None,
            'balance': self.current_balance,
            'equity': self.current_balance
        })

        # Main backtest loop
        peak_equity = self.current_balance  # Track highest equity
        trading_halted_dd = False  # Drawdown circuit breaker flag
        
        for i in range(len(data)):
            current_bar = data.iloc[i]

            # Update open positions
            self._update_open_positions(current_bar)
            
            # Track peak equity and current drawdown
            if self.current_balance > peak_equity:
                peak_equity = self.current_balance
            
            current_drawdown_pct = ((peak_equity - self.current_balance) / peak_equity * 100) if peak_equity > 0 else 0
            
            # DRAWDOWN CIRCUIT BREAKER - Halt trading when limit reached
            if not trading_halted_dd and self.config.max_drawdown_percent > 0:
                if current_drawdown_pct >= self.config.max_drawdown_percent:
                    trading_halted_dd = True
                    logger.warning(f"⛔ DRAWDOWN BREAKER: {current_drawdown_pct:.1f}% >= {self.config.max_drawdown_percent}% limit - Trading stopped!")
            
            # Skip new trades if halted by drawdown
            if trading_halted_dd:
                continue

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

            # Get HTF data up to current time (for trend filter)
            htf_historical = None
            if htf_data is not None:
                current_time = current_bar['time']
                # Get HTF bars up to current execution bar time
                htf_mask = htf_data['time'] <= current_time
                htf_historical = htf_data[htf_mask].copy()
                if len(htf_historical) > 0:
                    htf_historical = htf_historical.reset_index(drop=True)

            # Run strategy analysis
            try:
                analysis = self.trading_engine.analyze(historical_data, df_higher_tf=htf_historical)

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

                    # Filter: Min Volume Check (Debug for low trade counts)
                    # We can't easily check volume here without calling risk manager, but we can check if risk is tiny
                    if self.config.risk_percent < 0.01:
                         logger.warning(f"⚠️ Very low risk percent ({self.config.risk_percent}%) might result in 0 volume trades!")


                    # Additional filter: confidence threshold (LOW for debugging)
                    if confidence < 0.1:  # Very low threshold for debugging
                        logger.debug(f"Signal rejected: low confidence {confidence:.2f}")
                        continue
                    
                    # DIRECTION FILTER: BUY_ONLY / SELL_ONLY
                    if self.config.direction_filter == "BUY_ONLY" and signal.direction != "BUY":
                        logger.debug(f"Signal rejected: SELL signal blocked by BUY_ONLY filter")
                        continue
                    if self.config.direction_filter == "SELL_ONLY" and signal.direction != "SELL":
                        logger.debug(f"Signal rejected: BUY signal blocked by SELL_ONLY filter")
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

                    # STEP 2: Risk Manager - Calculate risk (consecutive losses only)
                    # Update peak balance
                    if self.current_balance > self.peak_balance:
                        self.peak_balance = self.current_balance

                    # Calculate current drawdown
                    current_equity = self._calculate_current_equity(current_bar)
                    current_dd = ((self.peak_balance - current_equity) / self.peak_balance * 100) if self.peak_balance > 0 else 0.0

                    # Get consecutive losses (DAILY RESET - only counts today's losses)
                    current_trading_date = current_bar['time'].date() if hasattr(current_bar['time'], 'date') else None
                    consecutive_losses = self._count_consecutive_losses(current_date=current_trading_date)

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
                    # Use initial_balance for position sizing unless compounding is enabled
                    sizing_balance = self.current_balance if self.config.use_compounding else self.config.initial_balance
                    trade = self.simulator.execute_entry(
                        signal=signal_dict,
                        current_bar=current_bar,
                        account_balance=sizing_balance,
                        risk_percent=adaptive_risk_percent  # Use adaptive risk
                    )
                    
                    if trade is None:
                         logger.warning(f"⚠️ Trade rejected by simulator (likely 0 volume). Check Risk % or Balance.")


                    if trade:
                        self.open_trades.append(trade)
                        logger.debug(
                            f"[{current_bar['time']}] Opened {trade.signal_type} "
                            f"@ {trade.entry_price:.5f}, Score: {trade.confluence_score}/10"
                        )
                        
                        # Emit trade event
                        if on_trade:
                            try:
                                on_trade({
                                    'type': 'OPEN',
                                    'symbol': trade.symbol,
                                    'trade_type': trade.signal_type,
                                    'price': trade.entry_price,
                                    'time': str(current_bar['time']),
                                    'volume': trade.volume
                                })
                            except Exception as e:
                                logger.error(f"Error in on_trade callback: {e}")

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
                
                # Emit progress event
                if on_progress:
                    try:
                        on_progress(progress_pct, {
                            'balance': self.current_balance,
                            'equity': current_equity,
                            'trades': len(self.closed_trades),
                            'current_time': str(current_bar['time'])
                        })
                    except Exception as e:
                        logger.error(f"Error in on_progress callback: {e}")

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

        # Send final progress update (100%)
        if self.on_progress_callback:
            try:
                self.on_progress_callback(100.0, {
                    'balance': self.current_balance,
                    'equity': self.current_balance,
                    'trades': len(self.closed_trades),
                    'current_time': "COMPLETE"
                })
            except Exception as e:
                logger.error(f"Error in on_progress callback (100%): {e}")

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
                trade.balance_after = self.current_balance

                # Emit trade close event
                if hasattr(self, 'on_trade_callback') and self.on_trade_callback:
                    try:
                        self.on_trade_callback({
                            'type': 'CLOSE',
                            'symbol': trade.symbol,
                            'trade_type': trade.signal_type,
                            'price': trade.exit_price,
                            'entry_price': trade.entry_price,
                            'entry_time': str(trade.entry_time),  # NEW: for duration calculation
                            'exit_time': str(trade.exit_time),    # NEW: for duration calculation
                            'time': str(current_bar['time']),
                            'pnl': trade.pnl,
                            'return_r': trade.return_r,
                            'balance': self.current_balance
                        })
                    except Exception as e:
                        logger.error(f"Error in on_trade callback (CLOSE): {e}")


    def _calculate_current_equity(self, current_bar: pd.Series) -> float:
        """Calculate current equity including open trades"""
        equity = self.current_balance

        for trade in self.open_trades:
            trade.update_open_pnl(current_bar['close'])
            equity += trade.pnl

        return equity

    def _count_consecutive_losses(self, current_date=None) -> int:
        """
        Count consecutive losing trades from most recent ON THE SAME DAY
        Resets at midnight - used by AdaptiveRiskManager for daily loss limits
        """
        if not self.closed_trades:
            return 0

        consecutive = 0
        # Iterate backwards through closed trades
        for trade in reversed(self.closed_trades):
            # Only count trades from the same calendar day
            if current_date and trade.exit_time:
                trade_date = trade.exit_time.date() if hasattr(trade.exit_time, 'date') else None
                if trade_date and trade_date != current_date:
                    break  # Stop counting when we hit a different day
            
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
        
        if not is_passing:
             logger.info("Failure Reasons:")
             if m.total_trades < 50: logger.info(f" - Not enough trades: {m.total_trades} < 50")
             if m.win_rate < 45.0: logger.info(f" - Win rate too low: {m.win_rate:.1f}% < 45.0%")
             if m.profit_factor < 1.5: logger.info(f" - Profit Factor too low: {m.profit_factor:.2f} < 1.5")
             if m.max_drawdown_percent >= 15.0: logger.info(f" - Drawdown too high: {m.max_drawdown_percent:.2f}% >= 15.0%")
             if m.average_rr < 2.0: logger.info(f" - Avg R:R too low: {m.average_rr:.2f} < 2.0")
            
        logger.info("")

        # Send Discord Alert
        try:
            asyncio.run(self.discord.send_backtest_summary(m))
        except Exception as e:
            # If loop is already running (e.g. inside another async context), we might need a different approach
            # But BacktestEngine.run is typically blocking/sync.
            logger.warning(f"Could not send Discord alert: {e}")

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
