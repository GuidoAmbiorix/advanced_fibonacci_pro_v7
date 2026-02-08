"""
Portfolio-Level Optimizer

Optimizes parameters across multiple symbols simultaneously,
maximizing portfolio-wide performance metrics instead of individual pairs.

Key Features:
- Correlation-aware optimization
- Multi-symbol backtesting in parallel
- Portfolio Sharpe as primary objective
- Diversification bonus
- Cross-pair parameter stability
- Constrained parameter space (frozen/tunable/forbidden)
"""

import optuna
import pandas as pd
import numpy as np
import time
from typing import Dict, List, Tuple
import logging

from database_manager import DatabaseManager
from optimizer_config_v2 import (
    FROZEN_PARAMS,
    TUNABLE_PARAMS,
    FORBIDDEN_PARAMS,
    PORTFOLIO_SETTINGS,
    get_all_params,
    validate_param_set,
)
from portfolio_metrics import PortfolioMetrics, PortfolioObjective, format_portfolio_report
from backtester.confluence_engine import ConfluenceEngine
from backtester.technical_indicators import TechnicalIndicators

logger = logging.getLogger("PortfolioOptimizer")


class PortfolioLevelOptimizer:
    """
    Portfolio-level parameter optimizer.

    Optimizes parameters across all symbols simultaneously,
    focusing on portfolio-wide performance.
    """

    def __init__(self, db_manager: DatabaseManager, timeframe: int = 15):
        """
        Initialize portfolio optimizer.

        Args:
            db_manager: Database manager instance
            timeframe: Trading timeframe in minutes
        """
        self.db = db_manager
        self.timeframe = timeframe

        # Portfolio settings
        self.settings = PORTFOLIO_SETTINGS
        self.symbols = self.settings['symbols']

        # Objective calculator
        self.portfolio_objective = PortfolioObjective(
            weights=self.settings['objective_weights'],
            penalties=self.settings['penalty_weights']
        )

        # Cache for market data
        self.market_data_cache = {}

    def load_market_data(self, force_reload: bool = False) -> Dict[str, pd.DataFrame]:
        """
        Load market data for all symbols.

        Args:
            force_reload: Force reload even if cached

        Returns:
            Dict of {symbol: DataFrame}
        """
        if self.market_data_cache and not force_reload:
            return self.market_data_cache

        logger.info(f"Loading market data for {len(self.symbols)} symbols...")

        data_limit = self.settings['data_limit']
        market_data = {}

        for symbol in self.symbols:
            df = self.db.get_market_data(symbol, self.timeframe, limit=data_limit)
            if not df.empty and len(df) >= 100:
                market_data[symbol] = df
                logger.info(f"  {symbol}: {len(df)} bars")
            else:
                logger.warning(f"  {symbol}: Insufficient data, skipping")

        self.market_data_cache = market_data
        logger.info(f"Loaded {len(market_data)} symbols successfully")

        return market_data

    def suggest_parameters(self, trial: optuna.Trial) -> Dict:
        """
        Suggest parameters for a trial.

        Only suggests TUNABLE parameters. FROZEN and FORBIDDEN are hard-coded.

        Args:
            trial: Optuna trial object

        Returns:
            Complete parameter dictionary
        """
        # Start with frozen + forbidden params
        params = get_all_params()

        # Suggest tunable params
        for param_name, config in TUNABLE_PARAMS.items():
            if config["type"] == "int":
                value = trial.suggest_int(
                    param_name,
                    config["low"],
                    config["high"],
                    step=config.get("step", 1)
                )
            else:
                value = trial.suggest_float(
                    param_name,
                    config["low"],
                    config["high"],
                    step=config.get("step", None)
                )

            params[param_name] = value

        # Enforce constraints (e.g., fib_level_low <= fib_level_high)
        if params['fib_level_low'] > params['fib_level_high']:
            params['fib_level_low'], params['fib_level_high'] = params['fib_level_high'], params['fib_level_low']

        if params['min_tp_r'] > params['fixed_tp_r']:
            params['min_tp_r'] = params['fixed_tp_r']

        # Validate
        is_valid, issues = validate_param_set(params)
        if not is_valid:
            logger.warning(f"Parameter validation issues: {issues}")

        return params

    def backtest_symbol(self, symbol: str, df: pd.DataFrame, params: Dict) -> Dict:
        """
        Run backtest for a single symbol.

        Args:
            symbol: Trading symbol
            df: Market data DataFrame
            params: Parameter dictionary

        Returns:
            Dictionary with backtest results
        """
        # Calculate indicators
        df = TechnicalIndicators.calculate_all_indicators(df.copy(), params)

        # Calculate confluence scores
        confluence = ConfluenceEngine(params)
        df['buy_score'] = confluence.calculate_confluence_score(df, 1, params)
        df['sell_score'] = confluence.calculate_confluence_score(df, -1, params)

        # Generate signals
        min_score = params.get('min_confluence_entry', 15.0)
        df['signal'] = 0
        df.loc[df['buy_score'] >= min_score, 'signal'] = 1
        df.loc[df['sell_score'] >= min_score, 'signal'] = -1

        # Simulate trades
        trades = []
        equity = 10000
        equity_curve = [equity]

        risk_base = params.get('risk_base', 0.5)
        fixed_tp_r = params.get('fixed_tp_r', 3.0)
        trail_start_r = params.get('trail_start_r', 1.5)
        trail_atr_mult = params.get('trail_atr_mult', 2.0)

        # Get warmup period
        rsi_period = params.get('rsi_period', 14)
        ema_period = params.get('ema_period', 200)
        start_idx = max(rsi_period, ema_period) + 20

        for i in range(start_idx, len(df)):
            if df['signal'].iloc[i] == 0:
                continue

            entry_price = df['close'].iloc[i]
            direction = df['signal'].iloc[i]
            atr = df['atr'].iloc[i]

            if np.isnan(atr) or atr == 0:
                continue

            sl_dist = atr * 1.5
            tp_dist = sl_dist * fixed_tp_r

            trail_active_price = entry_price + (sl_dist * trail_start_r) if direction == 1 else entry_price - (sl_dist * trail_start_r)
            current_sl = entry_price - sl_dist if direction == 1 else entry_price + sl_dist

            outcome = 0

            # Look ahead for exit
            for j in range(1, 100):
                if i + j >= len(df):
                    break

                bar = df.iloc[i + j]
                high = bar['high']
                low = bar['low']

                if direction == 1:
                    if low <= current_sl:
                        outcome = -1
                        break
                    if high >= entry_price + tp_dist:
                        outcome = 1
                        break
                    if high >= trail_active_price:
                        new_sl = high - (atr * trail_atr_mult)
                        if new_sl > current_sl:
                            current_sl = new_sl
                else:
                    if high >= current_sl:
                        outcome = -1
                        break
                    if low <= entry_price - tp_dist:
                        outcome = 1
                        break
                    if low <= trail_active_price:
                        new_sl = low + (atr * trail_atr_mult)
                        if new_sl < current_sl:
                            current_sl = new_sl

            # Record trade result
            if outcome == 1:
                r_result = fixed_tp_r
            elif outcome == -1:
                exit_price = current_sl
                dist = (exit_price - entry_price) * direction
                r_result = dist / sl_dist
            else:
                continue  # No exit, skip

            amount = (risk_base / 100.0) * equity * r_result
            equity += amount
            trades.append(r_result)
            equity_curve.append(equity)

        # Calculate metrics
        if len(trades) < 2:
            return {
                'symbol': symbol,
                'n_trades': len(trades),
                'sharpe': -10.0,  # Heavy penalty
                'returns': np.array([]),
                'max_drawdown': 1.0,
                'equity_curve': equity_curve,
            }

        returns = np.array(trades)
        sharpe = np.mean(returns) / (np.std(returns) + 1e-6)

        # Calculate max drawdown
        equity_array = np.array(equity_curve)
        running_max = np.maximum.accumulate(equity_array)
        drawdown = (equity_array - running_max) / running_max
        max_drawdown = abs(np.min(drawdown)) if len(drawdown) > 0 else 0.0

        return {
            'symbol': symbol,
            'n_trades': len(trades),
            'sharpe': sharpe,
            'returns': returns,
            'max_drawdown': max_drawdown,
            'equity_curve': equity_curve,
        }

    def portfolio_objective_function(self, trial: optuna.Trial) -> float:
        """
        Portfolio-level objective function.

        Runs backtests on all symbols and calculates portfolio metrics.

        Args:
            trial: Optuna trial

        Returns:
            Objective value (higher is better)
        """
        # Suggest parameters (only tunable ones)
        params = self.suggest_parameters(trial)

        # Load market data
        market_data = self.load_market_data()

        if not market_data:
            logger.error("No market data available")
            return -100.0

        # Run backtests on all symbols
        symbol_results = {}

        for symbol, df in market_data.items():
            try:
                result = self.backtest_symbol(symbol, df, params)
                symbol_results[symbol] = result
            except Exception as e:
                logger.error(f"Backtest failed for {symbol}: {e}")
                symbol_results[symbol] = {
                    'symbol': symbol,
                    'n_trades': 0,
                    'sharpe': -10.0,
                    'returns': np.array([]),
                    'max_drawdown': 1.0,
                }

        # Calculate portfolio metrics
        portfolio_metrics = PortfolioMetrics.calculate_portfolio_metrics(symbol_results)

        # Calculate penalties
        penalties = self.portfolio_objective.calculate_penalties(
            symbol_results,
            portfolio_metrics,
            min_trades_per_symbol=self.settings['min_trades_per_symbol'],
            max_drawdown=0.25,
            max_correlation=self.settings['max_allowed_correlation']
        )

        # Calculate objective
        objective = self.portfolio_objective.calculate_objective(portfolio_metrics, penalties)

        # Log trial info
        logger.info(
            f"Trial {trial.number}: "
            f"Portfolio Sharpe={portfolio_metrics['portfolio_sharpe']:.3f}, "
            f"Avg Corr={portfolio_metrics['avg_correlation']:.3f}, "
            f"Div Ratio={portfolio_metrics['diversification_ratio']:.3f}, "
            f"Objective={objective:.3f}"
        )

        return objective

    def run_portfolio_optimization(self, n_trials: int = None) -> Dict:
        """
        Run portfolio-level optimization.

        Args:
            n_trials: Number of trials (uses setting if None)

        Returns:
            Dictionary with optimization results
        """
        if n_trials is None:
            n_trials = self.settings['n_trials']

        logger.info("=" * 70)
        logger.info("STARTING PORTFOLIO-LEVEL OPTIMIZATION")
        logger.info("=" * 70)
        logger.info(f"Symbols: {', '.join(self.symbols)}")
        logger.info(f"Timeframe: {self.timeframe}min")
        logger.info(f"Trials: {n_trials}")
        logger.info(f"Tunable params: {len(TUNABLE_PARAMS)}")
        logger.info(f"Frozen params: {len(FROZEN_PARAMS)}")
        logger.info("=" * 70)

        start_time = time.time()

        # Create Optuna study
        study = optuna.create_study(
            direction="maximize",
            sampler=optuna.samplers.TPESampler(seed=42),
            pruner=optuna.pruners.MedianPruner(n_warmup_steps=10)
        )

        # Run optimization
        study.optimize(
            self.portfolio_objective_function,
            n_trials=n_trials,
            n_jobs=self.settings.get('n_jobs', 1),
            timeout=self.settings.get('timeout', None),
        )

        # Get best trial
        best_trial = study.best_trial
        best_params = best_trial.params

        # Reconstruct full params (frozen + forbidden + tunable)
        full_params = get_all_params()
        full_params.update(best_params)

        # Run final backtest with best params
        market_data = self.load_market_data()
        final_results = {}

        for symbol, df in market_data.items():
            result = self.backtest_symbol(symbol, df, full_params)
            final_results[symbol] = result

        # Calculate final portfolio metrics
        final_metrics = PortfolioMetrics.calculate_portfolio_metrics(final_results)

        # Generate report
        report = format_portfolio_report(final_metrics, final_results)
        print("\n" + report)

        elapsed_time = time.time() - start_time

        logger.info("=" * 70)
        logger.info(f"OPTIMIZATION COMPLETE in {elapsed_time:.1f}s")
        logger.info(f"Best Portfolio Sharpe: {final_metrics['portfolio_sharpe']:.3f}")
        logger.info(f"Best Objective Value: {best_trial.value:.3f}")
        logger.info("=" * 70)

        return {
            'best_params': full_params,
            'best_objective': best_trial.value,
            'portfolio_metrics': final_metrics,
            'symbol_results': final_results,
            'study': study,
            'elapsed_time': elapsed_time,
            'n_trials': n_trials,
        }

    def save_portfolio_results(self, results: Dict) -> bool:
        """
        Save portfolio optimization results to database for all symbols.

        Args:
            results: Results from run_portfolio_optimization()

        Returns:
            True if all saves successful
        """
        best_params = results['best_params']
        symbol_results = results['symbol_results']

        success_count = 0
        fail_count = 0

        # Get valid database columns
        current_configs = self.db.load_configs()
        if current_configs.empty:
            logger.error("Could not load database configs")
            return False

        valid_columns = set(current_configs.columns.tolist())

        # Filter params to only include valid columns
        filtered_params = {k: v for k, v in best_params.items() if k in valid_columns}

        logger.info(f"Saving portfolio results to database for {len(symbol_results)} symbols...")

        for symbol in symbol_results.keys():
            try:
                # Load existing config
                row = current_configs[current_configs['symbol'] == symbol]
                if row.empty:
                    logger.warning(f"Symbol {symbol} not in database, skipping")
                    continue

                config = row.to_dict('records')[0]

                # Update with optimized params
                config.update(filtered_params)

                # Save
                if self.db.save_config(config):
                    if self.db.verify_config_sync(symbol, filtered_params):
                        logger.info(f"✅ {symbol} saved and verified")
                        success_count += 1
                    else:
                        logger.error(f"❌ {symbol} verification failed")
                        fail_count += 1
                else:
                    logger.error(f"❌ {symbol} save failed")
                    fail_count += 1

            except Exception as e:
                logger.error(f"Error saving {symbol}: {e}")
                fail_count += 1

        logger.info(f"Save complete: {success_count} successful, {fail_count} failed")

        return fail_count == 0
