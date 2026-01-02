"""
============================================================================
Vectorbt Optimizer v1.0 - Walk-Forward Backtesting
============================================================================
Quantitative backtesting and parameter optimization using vectorbt.

This module is for RESEARCH ONLY - not integrated into live trading.
Used for:
- Walk-forward validation
- Parameter robustness testing
- Strategy optimization

NOT for:
- Real-time signal generation
- Live trading decisions
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Optional
from loguru import logger
from datetime import datetime, timedelta

try:
    import vectorbt as vbt
    VBT_AVAILABLE = True
except ImportError:
    VBT_AVAILABLE = False
    logger.warning("vectorbt not installed. Run: pip install vectorbt")


class VectorbtOptimizer:
    """
    Walk-forward optimization and backtesting using vectorbt.
    For research and parameter validation only.
    """
    
    def __init__(self, config: Dict = None):
        """
        Initialize optimizer.
        
        Args:
            config: Optional configuration dict
        """
        self.config = config or {}
        self._check_vectorbt()
    
    def _check_vectorbt(self):
        """Check if vectorbt is available."""
        if not VBT_AVAILABLE:
            raise ImportError("vectorbt is required. Install with: pip install vectorbt")
    
    def run_simple_backtest(
        self,
        df: pd.DataFrame,
        entries: pd.Series,
        exits: pd.Series,
        initial_capital: float = 10000,
        fees: float = 0.0001,
        slippage: float = 0.0001
    ) -> Dict:
        """
        Run a simple backtest with entry/exit signals.
        
        Args:
            df: OHLCV DataFrame with DatetimeIndex
            entries: Boolean Series of entry signals
            exits: Boolean Series of exit signals
            initial_capital: Starting capital
            fees: Trading fees (fraction)
            slippage: Slippage (fraction)
        
        Returns:
            Dict with backtest metrics
        """
        if not VBT_AVAILABLE:
            return {'error': 'vectorbt not available'}
        
        # Create portfolio
        portfolio = vbt.Portfolio.from_signals(
            close=df['close'],
            entries=entries,
            exits=exits,
            init_cash=initial_capital,
            fees=fees,
            slippage=slippage,
            freq='1H'
        )
        
        return self._extract_metrics(portfolio)
    
    def _extract_metrics(self, portfolio) -> Dict:
        """Extract performance metrics from portfolio."""
        stats = portfolio.stats()
        
        return {
            'total_return': float(stats.get('Total Return [%]', 0)),
            'max_drawdown': float(stats.get('Max Drawdown [%]', 0)),
            'sharpe_ratio': float(stats.get('Sharpe Ratio', 0)),
            'sortino_ratio': float(stats.get('Sortino Ratio', 0)),
            'calmar_ratio': float(stats.get('Calmar Ratio', 0)),
            'win_rate': float(stats.get('Win Rate [%]', 0)),
            'profit_factor': float(stats.get('Profit Factor', 0)),
            'total_trades': int(stats.get('Total Trades', 0)),
            'avg_winning_trade': float(stats.get('Avg Winning Trade [%]', 0)),
            'avg_losing_trade': float(stats.get('Avg Losing Trade [%]', 0)),
            'expectancy': float(stats.get('Expectancy', 0))
        }
    
    def walk_forward_optimize(
        self,
        df: pd.DataFrame,
        signal_generator,
        param_grid: Dict[str, List],
        in_sample_pct: float = 0.7,
        n_splits: int = 5,
        optimization_metric: str = 'sharpe_ratio'
    ) -> Dict:
        """
        Walk-forward optimization with parameter grid.
        
        Args:
            df: OHLCV DataFrame
            signal_generator: Function(df, **params) -> (entries, exits)
            param_grid: Dict of parameter names to lists of values
            in_sample_pct: Percentage of each window for in-sample
            n_splits: Number of walk-forward splits
            optimization_metric: Metric to optimize
        
        Returns:
            Dict with optimization results
        """
        if not VBT_AVAILABLE:
            return {'error': 'vectorbt not available'}
        
        total_bars = len(df)
        window_size = total_bars // n_splits
        
        results = []
        
        for split_idx in range(n_splits):
            start_idx = split_idx * window_size
            end_idx = start_idx + window_size if split_idx < n_splits - 1 else total_bars
            
            window_data = df.iloc[start_idx:end_idx]
            in_sample_size = int(len(window_data) * in_sample_pct)
            
            in_sample = window_data.iloc[:in_sample_size]
            out_sample = window_data.iloc[in_sample_size:]
            
            if len(out_sample) < 10:
                continue
            
            # Grid search on in-sample
            best_params = None
            best_metric = float('-inf')
            
            param_names = list(param_grid.keys())
            param_values = list(param_grid.values())
            
            # Generate all combinations
            from itertools import product
            for combo in product(*param_values):
                params = dict(zip(param_names, combo))
                
                try:
                    entries, exits = signal_generator(in_sample, **params)
                    metrics = self.run_simple_backtest(in_sample, entries, exits)
                    
                    if metrics.get(optimization_metric, 0) > best_metric:
                        best_metric = metrics[optimization_metric]
                        best_params = params
                except Exception as e:
                    logger.debug(f"Param combo failed: {params}, error: {e}")
                    continue
            
            if best_params is None:
                continue
            
            # Test on out-of-sample
            try:
                entries, exits = signal_generator(out_sample, **best_params)
                oos_metrics = self.run_simple_backtest(out_sample, entries, exits)
                
                results.append({
                    'split': split_idx,
                    'best_params': best_params,
                    'in_sample_metric': best_metric,
                    'out_sample_metrics': oos_metrics
                })
            except Exception as e:
                logger.error(f"Out-of-sample test failed: {e}")
        
        return {
            'splits': results,
            'n_splits': n_splits,
            'optimization_metric': optimization_metric,
            'avg_oos_return': np.mean([r['out_sample_metrics']['total_return'] for r in results]) if results else 0,
            'avg_oos_sharpe': np.mean([r['out_sample_metrics']['sharpe_ratio'] for r in results]) if results else 0
        }
    
    def parameter_robustness_test(
        self,
        df: pd.DataFrame,
        signal_generator,
        base_params: Dict,
        param_to_test: str,
        test_range: List,
        metric: str = 'sharpe_ratio'
    ) -> Dict:
        """
        Test parameter robustness by varying one parameter.
        
        Args:
            df: OHLCV DataFrame
            signal_generator: Signal generation function
            base_params: Base parameter set
            param_to_test: Which parameter to vary
            test_range: Values to test
            metric: Performance metric to track
        
        Returns:
            Dict with robustness analysis
        """
        if not VBT_AVAILABLE:
            return {'error': 'vectorbt not available'}
        
        results = []
        
        for value in test_range:
            params = base_params.copy()
            params[param_to_test] = value
            
            try:
                entries, exits = signal_generator(df, **params)
                metrics = self.run_simple_backtest(df, entries, exits)
                
                results.append({
                    'value': value,
                    'metric': metrics.get(metric, 0),
                    'full_metrics': metrics
                })
            except Exception as e:
                logger.debug(f"Robustness test failed for {param_to_test}={value}: {e}")
        
        if not results:
            return {'error': 'All tests failed'}
        
        metrics_values = [r['metric'] for r in results]
        
        return {
            'param': param_to_test,
            'test_range': test_range,
            'results': results,
            'mean': float(np.mean(metrics_values)),
            'std': float(np.std(metrics_values)),
            'cv': float(np.std(metrics_values) / np.mean(metrics_values)) if np.mean(metrics_values) != 0 else float('inf'),
            'is_robust': float(np.std(metrics_values) / np.mean(metrics_values)) < 0.3 if np.mean(metrics_values) != 0 else False
        }


# Example usage for testing
def example_signal_generator(df: pd.DataFrame, fast_ema: int = 10, slow_ema: int = 30) -> Tuple[pd.Series, pd.Series]:
    """Example signal generator for testing."""
    fast = df['close'].ewm(span=fast_ema).mean()
    slow = df['close'].ewm(span=slow_ema).mean()
    
    entries = (fast > slow) & (fast.shift(1) <= slow.shift(1))
    exits = (fast < slow) & (fast.shift(1) >= slow.shift(1))
    
    return entries, exits
