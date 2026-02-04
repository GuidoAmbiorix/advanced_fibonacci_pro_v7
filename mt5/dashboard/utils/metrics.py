"""
Metrics Calculator for MT5 Portfolio Dashboard
Calculates derived metrics from trade data
"""

import pandas as pd
from typing import Dict, Any, Tuple
from datetime import datetime


def calculate_win_rate(trades_df: pd.DataFrame) -> float:
    """Calculate win rate percentage"""
    if trades_df.empty:
        return 0.0

    winning_trades = len(trades_df[trades_df['profit'] > 0])
    total_trades = len(trades_df)

    return (winning_trades / total_trades * 100) if total_trades > 0 else 0.0


def calculate_profit_factor(trades_df: pd.DataFrame) -> float:
    """Calculate profit factor (gross profit / gross loss)"""
    if trades_df.empty:
        return 0.0

    gross_profit = trades_df[trades_df['profit'] > 0]['profit'].sum()
    gross_loss = abs(trades_df[trades_df['profit'] <= 0]['profit'].sum())

    return (gross_profit / gross_loss) if gross_loss != 0 else float('inf') if gross_profit > 0 else 0.0


def calculate_average_win_loss(trades_df: pd.DataFrame) -> Tuple[float, float]:
    """Calculate average win and average loss"""
    if trades_df.empty:
        return 0.0, 0.0

    winning_trades = trades_df[trades_df['profit'] > 0]['profit']
    losing_trades = trades_df[trades_df['profit'] <= 0]['profit']

    avg_win = winning_trades.mean() if len(winning_trades) > 0 else 0.0
    avg_loss = losing_trades.mean() if len(losing_trades) > 0 else 0.0

    return avg_win, avg_loss


def calculate_expectancy(trades_df: pd.DataFrame) -> float:
    """
    Calculate expectancy (average profit per trade)
    Formula: (Win Rate × Avg Win) - (Loss Rate × |Avg Loss|)
    """
    if trades_df.empty:
        return 0.0

    win_rate = calculate_win_rate(trades_df) / 100
    loss_rate = 1 - win_rate

    avg_win, avg_loss = calculate_average_win_loss(trades_df)

    return (win_rate * avg_win) - (loss_rate * abs(avg_loss))


def calculate_drawdown_metrics(equity_curve_df: pd.DataFrame, current_balance: float) -> Dict[str, float]:
    """
    Calculate drawdown metrics from equity curve

    Args:
        equity_curve_df: DataFrame with 'cumulative_pl' column
        current_balance: Current account balance

    Returns:
        Dict with current_drawdown, max_drawdown, max_drawdown_pct
    """
    if equity_curve_df.empty or 'cumulative_pl' not in equity_curve_df.columns:
        return {
            'current_drawdown': 0.0,
            'max_drawdown': 0.0,
            'max_drawdown_pct': 0.0,
            'peak_equity': current_balance
        }

    # Add balance to get equity values
    equity_curve_df = equity_curve_df.copy()
    equity_curve_df['equity'] = current_balance + equity_curve_df['cumulative_pl']

    # Calculate running maximum
    equity_curve_df['peak'] = equity_curve_df['equity'].cummax()

    # Calculate drawdown at each point
    equity_curve_df['drawdown'] = equity_curve_df['peak'] - equity_curve_df['equity']
    equity_curve_df['drawdown_pct'] = (equity_curve_df['drawdown'] / equity_curve_df['peak'] * 100)

    # Get metrics
    peak_equity = equity_curve_df['peak'].max()
    current_equity = equity_curve_df['equity'].iloc[-1] if len(equity_curve_df) > 0 else current_balance
    current_drawdown = peak_equity - current_equity
    current_drawdown_pct = (current_drawdown / peak_equity * 100) if peak_equity > 0 else 0.0

    max_drawdown = equity_curve_df['drawdown'].max()
    max_drawdown_pct = equity_curve_df['drawdown_pct'].max()

    return {
        'current_drawdown': current_drawdown,
        'current_drawdown_pct': current_drawdown_pct,
        'max_drawdown': max_drawdown,
        'max_drawdown_pct': max_drawdown_pct,
        'peak_equity': peak_equity
    }


def calculate_risk_exposure(positions_df: pd.DataFrame) -> Dict[str, Any]:
    """
    Calculate current risk exposure metrics

    Args:
        positions_df: DataFrame with open positions

    Returns:
        Dict with exposure metrics
    """
    if positions_df.empty:
        return {
            'total_positions': 0,
            'total_lots': 0.0,
            'total_exposure': 0.0,
            'long_positions': 0,
            'short_positions': 0,
            'positions_by_symbol': {}
        }

    total_positions = len(positions_df)
    total_lots = positions_df['lots'].sum()

    # Calculate exposure (lots × entry_price)
    if 'entry_price' in positions_df.columns and 'lots' in positions_df.columns:
        positions_df = positions_df.copy()
        positions_df['exposure'] = positions_df['lots'] * positions_df['entry_price']
        total_exposure = positions_df['exposure'].sum()
    else:
        total_exposure = 0.0

    # Count by direction (assuming 0=BUY, 1=SELL)
    long_positions = len(positions_df[positions_df['type'] == 0]) if 'type' in positions_df.columns else 0
    short_positions = len(positions_df[positions_df['type'] == 1]) if 'type' in positions_df.columns else 0

    # Count by symbol
    positions_by_symbol = positions_df['symbol'].value_counts().to_dict() if 'symbol' in positions_df.columns else {}

    return {
        'total_positions': total_positions,
        'total_lots': round(total_lots, 2),
        'total_exposure': round(total_exposure, 2),
        'long_positions': long_positions,
        'short_positions': short_positions,
        'positions_by_symbol': positions_by_symbol
    }


def calculate_sharpe_ratio(trades_df: pd.DataFrame, risk_free_rate: float = 0.02) -> float:
    """
    Calculate Sharpe ratio (annualized)

    Args:
        trades_df: DataFrame with trades and 'profit' column
        risk_free_rate: Annual risk-free rate (default 2%)

    Returns:
        Sharpe ratio
    """
    if trades_df.empty or 'profit' not in trades_df.columns:
        return 0.0

    returns = trades_df['profit']

    if len(returns) < 2:
        return 0.0

    mean_return = returns.mean()
    std_return = returns.std()

    if std_return == 0:
        return 0.0

    # Annualize (assuming daily trades - adjust multiplier as needed)
    sharpe = (mean_return - (risk_free_rate / 252)) / std_return * (252 ** 0.5)

    return sharpe


def calculate_recovery_factor(total_profit: float, max_drawdown: float) -> float:
    """
    Calculate recovery factor (total profit / max drawdown)

    Args:
        total_profit: Total profit
        max_drawdown: Maximum drawdown

    Returns:
        Recovery factor
    """
    if max_drawdown == 0:
        return float('inf') if total_profit > 0 else 0.0

    return total_profit / max_drawdown


def calculate_consecutive_wins_losses(trades_df: pd.DataFrame) -> Dict[str, int]:
    """
    Calculate maximum consecutive wins and losses

    Args:
        trades_df: DataFrame with trades sorted by time

    Returns:
        Dict with max_consecutive_wins and max_consecutive_losses
    """
    if trades_df.empty or 'profit' not in trades_df.columns:
        return {
            'max_consecutive_wins': 0,
            'max_consecutive_losses': 0,
            'current_streak': 0
        }

    trades_df = trades_df.sort_values('close_time')
    is_win = (trades_df['profit'] > 0).astype(int)

    max_wins = 0
    max_losses = 0
    current_wins = 0
    current_losses = 0

    for win in is_win:
        if win:
            current_wins += 1
            current_losses = 0
            max_wins = max(max_wins, current_wins)
        else:
            current_losses += 1
            current_wins = 0
            max_losses = max(max_losses, current_losses)

    # Current streak
    last_win = is_win.iloc[-1] if len(is_win) > 0 else 0
    current_streak = current_wins if last_win else -current_losses

    return {
        'max_consecutive_wins': max_wins,
        'max_consecutive_losses': max_losses,
        'current_streak': current_streak
    }


def format_currency(value: float, decimals: int = 2) -> str:
    """Format value as currency with color"""
    return f"${value:,.{decimals}f}"


def format_percentage(value: float, decimals: int = 2) -> str:
    """Format value as percentage"""
    return f"{value:.{decimals}f}%"


def get_performance_summary(trades_df: pd.DataFrame, account_summary: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get comprehensive performance summary

    Args:
        trades_df: DataFrame with closed trades
        account_summary: Dict with current account state

    Returns:
        Dict with all performance metrics
    """
    if trades_df.empty:
        return {
            'total_trades': 0,
            'win_rate': 0.0,
            'profit_factor': 0.0,
            'avg_win': 0.0,
            'avg_loss': 0.0,
            'expectancy': 0.0,
            'best_trade': 0.0,
            'worst_trade': 0.0,
            'total_profit': 0.0
        }

    avg_win, avg_loss = calculate_average_win_loss(trades_df)
    consecutive = calculate_consecutive_wins_losses(trades_df)

    return {
        'total_trades': len(trades_df),
        'win_rate': calculate_win_rate(trades_df),
        'profit_factor': calculate_profit_factor(trades_df),
        'avg_win': avg_win,
        'avg_loss': avg_loss,
        'expectancy': calculate_expectancy(trades_df),
        'best_trade': trades_df['profit'].max(),
        'worst_trade': trades_df['profit'].min(),
        'total_profit': trades_df['profit'].sum(),
        'sharpe_ratio': calculate_sharpe_ratio(trades_df),
        'max_consecutive_wins': consecutive['max_consecutive_wins'],
        'max_consecutive_losses': consecutive['max_consecutive_losses'],
        'current_streak': consecutive['current_streak']
    }
