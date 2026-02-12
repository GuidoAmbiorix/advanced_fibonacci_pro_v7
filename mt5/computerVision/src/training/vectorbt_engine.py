
import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple, Union
import logging

try:
    import vectorbt as vbt
    VECTORBT_AVAILABLE = True
except ImportError:
    VECTORBT_AVAILABLE = False
    print("⚠️ VectorBT not available - backtesting features will be limited")

logger = logging.getLogger(__name__)

class VectorBTEngine:
    """
    High-performance backtesting engine using VectorBT.
    """
    
    def __init__(self, fees: float = 0.0003, slippage: float = 0.0002):
        # More realistic fees for retail forex trading
        # Fees: 0.03% (includes spread + commission)
        # Slippage: 0.02% (market orders on H1)
        self.fees = fees
        self.slippage = slippage
        
    def run_fast_backtest(
        self,
        prices: pd.Series,
        entries: pd.Series,
        exits: pd.Series,
        sl_stop: Optional[float] = None,
        tp_stop: Optional[float] = None,
        freq: str = '1min'
    ) -> Dict[str, float]:
        """
        Run a fast vectorized backtest.

        Args:
            prices: Close prices
            entries: Boolean series for entries
            exits: Boolean series for exits
            sl_stop: Stop Loss percentage (e.g. 0.01 for 1%)
            tp_stop: Take Profit percentage
            freq: Time frequency string

        Returns:
            Dictionary of metrics
        """
        if not VECTORBT_AVAILABLE:
            logger.warning("VectorBT not available - returning dummy metrics")
            return {
                'total_return': 0.0,
                'benchmark_return': 0.0,
                'sharpe_ratio': 0.0,
                'sortino_ratio': 0.0,
                'max_drawdown': 0.0,
                'win_rate': 0.0,
                'profit_factor': 0.0,
                'total_trades': 0.0,
                'expectancy': 0.0
            }

        try:
            # Create portfolio
            pf = vbt.Portfolio.from_signals(
                prices,
                entries,
                exits,
                sl_stop=sl_stop,
                tp_stop=tp_stop,
                fees=self.fees,
                slippage=self.slippage,
                freq=freq,
                init_cash=10000.0
            )

            # Get stats - convert to dict if it's a Series
            stats = pf.stats()
            if hasattr(stats, 'to_dict'):
                stats = stats.to_dict()

            # Debug: Print available stats keys
            print(f"VectorBT stats keys: {list(stats.keys())[:10]}")  # Print first 10 keys

            # Calculate metrics from stats - try different possible key names
            metrics = {
                'total_return': float(stats.get('Total Return [%]', stats.get('total_return', 0))) / 100 if 'Total Return [%]' in stats else float(stats.get('total_return', 0)),
                'sharpe_ratio': float(stats.get('Sharpe Ratio', stats.get('sharpe_ratio', 0))),
                'sortino_ratio': float(stats.get('Sortino Ratio', stats.get('sortino_ratio', 0))),
                'max_drawdown': abs(float(stats.get('Max Drawdown [%]', stats.get('max_drawdown', 0))) / 100) if 'Max Drawdown [%]' in stats else abs(float(stats.get('max_drawdown', 0))),
                'win_rate': float(stats.get('Win Rate [%]', stats.get('win_rate', 0))) / 100 if 'Win Rate [%]' in stats else float(stats.get('win_rate', 0)),
                'profit_factor': float(stats.get('Profit Factor', stats.get('profit_factor', 0))),
                'total_trades': int(stats.get('Total Trades', stats.get('total_trades', 0))),
                'expectancy': float(stats.get('Expectancy', stats.get('expectancy', 0)))
            }

            print(f"Extracted metrics: PF={metrics['profit_factor']:.2f}, Sharpe={metrics['sharpe_ratio']:.2f}, Trades={metrics['total_trades']}")

            # Handle potential NaNs
            return {k: (0.0 if pd.isna(v) or np.isinf(v) else float(v)) for k, v in metrics.items()}

        except Exception as e:
            import traceback
            logger.error(f"VectorBT backtest failed: {e}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            print(f"VectorBT backtest failed: {e}")
            print(f"Traceback: {traceback.format_exc()}")
            return {
                'total_return': 0.0,
                'sharpe_ratio': 0.0,
                'max_drawdown': 0.0,
                'profit_factor': 0.0,
                'total_trades': 0,
                'win_rate': 0.0,
                'expectancy': 0.0,
                'error': 1.0
            }

    def grid_search(
        self,
        prices: pd.Series,
        param_grid: Dict[str, List[float]],
        strategy_func
    ):
        """
        Example stub for future grid search implementation.
        strategy_func would produce entries/exits based on params.
        """
        pass
