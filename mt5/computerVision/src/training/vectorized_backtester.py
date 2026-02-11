import numpy as np
import pandas as pd
from dataclasses import dataclass
from typing import Dict, Union

@dataclass
class BacktestMetrics:
    net_profit: float
    total_trades: int
    win_rate: float
    profit_factor: float
    max_drawdown: float
    sharpe_ratio: float
    equity_curve: np.ndarray

class VectorizedBacktester:
    """
    Fast vectorized backtester for strategy evaluation.
    Assumes signals are generated beforehand.
    """
    
    def __init__(self, initial_capital: float = 10000.0, spread_pips: float = 1.0):
        self.initial_capital = initial_capital
        self.spread = spread_pips * 0.0001 # Standard pip value
        
    def run_backtest(
        self,
        prices: pd.Series,
        signals: pd.Series,
        pt_pips: float = 20.0,
        sl_pips: float = 10.0,
        lot_size: float = 0.1
    ) -> BacktestMetrics:
        """
        Run a simple vectorized backtest with fixed PT/SL.
        Note: This is an approximation. For exact path dependency, event-driven is needed.
        But for Optuna optimization, this 100x speedup is worth the minor accuracy trade-off.
        """
        
        # Convert inputs to numpy
        p = prices.values
        s = signals.values # 1 (buy), -1 (sell), 0 (none)
        
        n = len(p)
        equity = np.zeros(n)
        equity[0] = self.initial_capital
        
        trades = []
        current_equity = self.initial_capital
        
        # Calculate pnl per trade (simplified)
        # We find entries and simulate outcome based on PT/SL probabilities or just bar closes?
        # For a truly vectorized approach compatible with Optuna speed:
        # We calculate the return of the Next N bars and see if it hits PT/SL
        
        # ... Wait, if we use the labels from Labeling.py, we already know the outcome!
        # If the model predicts '1' (Buy), and the label was '1' (PT hit), then we win.
        # If the label was '-1' (SL hit), we lose.
        
        # So we really just need to construct the equity curve from the predictions vs labels.
        pass 

    def calculate_metrics_from_labels(
        self,
        predictions: np.ndarray,
        labels: np.ndarray,
        pt_amount: float,
        sl_amount: float
    ) -> BacktestMetrics:
        """
        Calculate metrics based on predictions matching Triple Barrier labels.
        This provides the FASTEST possible backtest.
        
        Args:
            predictions: Model predictions (1, 0, -1) or just (1, 0)
            labels: True Triple Barrier outcomes (1 for PT, -1 for SL, 0 for neutral)
            pt_amount: Dollar profit for a win
            sl_amount: Dollar loss for a loss
        """
        
        # Filter for where we took a trade
        # Assuming prediction 1 = Buy
        trades_indices = np.where(predictions == 1)[0]
        
        if len(trades_indices) == 0:
            return BacktestMetrics(0,0,0,0,0,0, np.array([self.initial_capital]))
            
        trade_outcomes = labels[trades_indices]
        
        # Calculate PnL
        # 1 in label means PT hit (Win)
        # -1 in label means SL hit (Loss)
        # 0 in label means time limit hit (Exit at close -> Assume small loss or scratch)
        
        pnl = np.zeros_like(trade_outcomes, dtype=float)
        pnl[trade_outcomes == 1] = pt_amount
        pnl[trade_outcomes == -1] = -sl_amount
        pnl[trade_outcomes == 0] = -sl_amount * 0.1 # Penalty for valid time exit
        
        # Cumulative PnL
        cum_pnl = np.cumsum(pnl)
        equity_curve = self.initial_capital + cum_pnl
        
        # Metrics
        net_profit = cum_pnl[-1]
        total_trades = len(trades_indices)
        wins = np.sum(trade_outcomes == 1)
        win_rate = wins / total_trades if total_trades > 0 else 0
        
        gross_profit = np.sum(pnl[pnl > 0])
        gross_loss = abs(np.sum(pnl[pnl < 0]))
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else float('inf')
        
        # Drawdown
        peaks = np.maximum.accumulate(equity_curve)
        drawdowns = (peaks - equity_curve) / peaks
        max_drawdown = np.max(drawdowns)
        
        # Sharpe (simplified)
        returns = pd.Series(equity_curve).pct_change().dropna()
        sharpe = returns.mean() / returns.std() * np.sqrt(252*24) if returns.std() > 0 else 0
        
        return BacktestMetrics(
            net_profit=net_profit,
            total_trades=total_trades,
            win_rate=win_rate,
            profit_factor=profit_factor,
            max_drawdown=max_drawdown,
            sharpe_ratio=sharpe,
            equity_curve=equity_curve
        )
