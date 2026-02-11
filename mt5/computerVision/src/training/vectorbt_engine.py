
import vectorbt as vbt
import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple, Union
import logging

logger = logging.getLogger(__name__)

class VectorBTEngine:
    """
    High-performance backtesting engine using VectorBT.
    """
    
    def __init__(self, fees: float = 0.0001, slippage: float = 0.0001):
        self.fees = fees
        self.slippage = slippage
        
    def run_fast_backtest(
        self,
        prices: pd.Series,
        entries: pd.Series,
        exits: pd.Series,
        sl_stop: Optional[float] = None,
        tp_stop: Optional[float] = None,
        freq: str = '1T'
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
            
            # Calculate metrics
            metrics = {
                'total_return': pf.total_return(),
                'benchmark_return': pf.benchmark_returns().sum(),
                'sharpe_ratio': pf.sharpe_ratio(risk_free=0.0),
                'sortino_ratio': pf.sortino_ratio(risk_free=0.0),
                'max_drawdown': pf.max_drawdown(),
                'win_rate': pf.win_rate(),
                'profit_factor': pf.profit_factor(),
                'total_trades': pf.total_trades(),
                'expectancy': pf.expectancy()
            }
            
            # Handle potential NaNs
            return {k: (0.0 if pd.isna(v) or np.isinf(v) else float(v)) for k, v in metrics.items()}
            
        except Exception as e:
            logger.error(f"VectorBT backtest failed: {e}")
            return {
                'total_return': 0.0,
                'sharpe_ratio': 0.0,
                'max_drawdown': 0.0,
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
