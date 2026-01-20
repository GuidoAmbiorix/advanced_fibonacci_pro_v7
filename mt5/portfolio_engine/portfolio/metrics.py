"""
Portfolio Metrics
Functions for calculating performance metrics.
"""

from typing import List, Any
import numpy as np


def calculate_profit_factor(trades: List[Any]) -> float:
    """
    Calculate Profit Factor from trades.
    
    PF = Gross Profit / Gross Loss
    
    Args:
        trades: List of Trade objects with 'profit' attribute
        
    Returns:
        Profit Factor (>1 is profitable)
    """
    if not trades:
        return 1.0
    
    gross_profit = sum(t.profit for t in trades if t.profit > 0)
    gross_loss = abs(sum(t.profit for t in trades if t.profit < 0))
    
    if gross_loss == 0:
        return 10.0 if gross_profit > 0 else 1.0
    
    return gross_profit / gross_loss


def calculate_max_drawdown(equity_curve: np.ndarray) -> float:
    """
    Calculate Maximum Drawdown percentage.
    
    Args:
        equity_curve: Array of equity values over time
        
    Returns:
        Max DD as percentage (e.g., 15.5 for 15.5%)
    """
    if len(equity_curve) == 0:
        return 0
    
    peak = equity_curve[0]
    max_dd = 0
    
    for equity in equity_curve:
        if equity > peak:
            peak = equity
        
        dd = (peak - equity) / peak * 100
        max_dd = max(max_dd, dd)
    
    return max_dd


def calculate_sharpe_ratio(
    returns: np.ndarray,
    risk_free_rate: float = 0.0,
    periods_per_year: int = 252
) -> float:
    """
    Calculate Sharpe Ratio.
    
    Args:
        returns: Array of period returns (e.g., daily % returns)
        risk_free_rate: Annual risk-free rate
        periods_per_year: Number of periods per year (252 for daily)
        
    Returns:
        Annualized Sharpe Ratio
    """
    if len(returns) == 0 or np.std(returns) == 0:
        return 0
    
    excess_returns = returns - (risk_free_rate / periods_per_year)
    return np.mean(excess_returns) / np.std(returns) * np.sqrt(periods_per_year)


def calculate_expectancy(trades: List[Any]) -> float:
    """
    Calculate Expectancy in R terms.
    
    Expectancy = (Win% × Avg Win R) - (Loss% × Avg Loss R)
    
    Args:
        trades: List of Trade objects with 'profit_r' attribute
        
    Returns:
        Expectancy in R (positive = profitable)
    """
    if not trades:
        return 0
    
    wins = [t.profit_r for t in trades if t.profit_r > 0]
    losses = [abs(t.profit_r) for t in trades if t.profit_r <= 0]
    
    total = len(trades)
    win_rate = len(wins) / total if total > 0 else 0
    loss_rate = len(losses) / total if total > 0 else 0
    
    avg_win = np.mean(wins) if wins else 0
    avg_loss = np.mean(losses) if losses else 0
    
    return (win_rate * avg_win) - (loss_rate * avg_loss)


def calculate_win_rate(trades: List[Any]) -> float:
    """Calculate win rate percentage."""
    if not trades:
        return 0
    
    wins = sum(1 for t in trades if t.profit > 0)
    return (wins / len(trades)) * 100


def calculate_average_rr(trades: List[Any]) -> float:
    """Calculate average risk-reward ratio."""
    if not trades:
        return 0
    
    return np.mean([t.profit_r for t in trades])


def calculate_largest_win(trades: List[Any]) -> float:
    """Get largest winning trade in R."""
    if not trades:
        return 0
    
    wins = [t.profit_r for t in trades if t.profit_r > 0]
    return max(wins) if wins else 0


def calculate_largest_loss(trades: List[Any]) -> float:
    """Get largest losing trade in R."""
    if not trades:
        return 0
    
    losses = [abs(t.profit_r) for t in trades if t.profit_r < 0]
    return max(losses) if losses else 0


def calculate_consecutive_losses(trades: List[Any]) -> int:
    """Calculate maximum consecutive losing trades."""
    if not trades:
        return 0
    
    max_streak = 0
    current_streak = 0
    
    for trade in trades:
        if trade.profit < 0:
            current_streak += 1
            max_streak = max(max_streak, current_streak)
        else:
            current_streak = 0
    
    return max_streak


def calculate_recovery_factor(
    net_profit: float,
    max_drawdown: float
) -> float:
    """
    Calculate Recovery Factor.
    
    RF = Net Profit / Max Drawdown (in money terms)
    Higher is better.
    """
    if max_drawdown == 0:
        return 0
    
    return net_profit / max_drawdown


def generate_performance_report(trades: List[Any], equity_curve: np.ndarray) -> dict:
    """
    Generate comprehensive performance report.
    
    Returns:
        Dictionary with all key metrics
    """
    if not trades:
        return {'status': 'No trades'}
    
    returns = np.diff(equity_curve) / equity_curve[:-1] if len(equity_curve) > 1 else np.array([])
    
    return {
        'total_trades': len(trades),
        'profit_factor': calculate_profit_factor(trades),
        'max_drawdown': calculate_max_drawdown(equity_curve),
        'sharpe_ratio': calculate_sharpe_ratio(returns),
        'expectancy_r': calculate_expectancy(trades),
        'win_rate': calculate_win_rate(trades),
        'average_rr': calculate_average_rr(trades),
        'largest_win_r': calculate_largest_win(trades),
        'largest_loss_r': calculate_largest_loss(trades),
        'max_consecutive_losses': calculate_consecutive_losses(trades),
        'net_profit': equity_curve[-1] - equity_curve[0] if len(equity_curve) > 0 else 0,
    }
