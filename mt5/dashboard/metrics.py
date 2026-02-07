# Performance Metrics Module
# Comprehensive trading performance analysis

import numpy as np
import pandas as pd

class PerformanceMetrics:
    """Advanced trading performance metrics calculation."""

    @staticmethod
    def calculate_all(returns, initial_capital=10000):
        """
        Calculate comprehensive metrics from returns array.

        Args:
            returns: List or array of trade returns (in R multiples or %)
            initial_capital: Starting capital for equity curve

        Returns:
            Dictionary of all calculated metrics
        """
        if len(returns) == 0:
            return None

        returns_array = np.array(returns)
        equity_curve = initial_capital * (1 + np.cumsum(returns_array) / 100)

        metrics = {}

        # === Risk-Adjusted Returns ===
        mean_return = np.mean(returns_array)
        std_return = np.std(returns_array)

        metrics['sharpe_ratio'] = mean_return / (std_return + 1e-6)

        # Sortino (downside deviation only)
        downside_returns = returns_array[returns_array < 0]
        downside_std = np.std(downside_returns) if len(downside_returns) > 0 else 1e-6
        metrics['sortino_ratio'] = mean_return / downside_std

        # Drawdown calculations
        running_max = np.maximum.accumulate(equity_curve)
        drawdown = (running_max - equity_curve) / running_max
        max_dd = np.max(drawdown) if len(drawdown) > 0 else 1e-6

        # Calmar (return / max DD)
        total_return = (equity_curve[-1] - initial_capital) / initial_capital
        metrics['calmar_ratio'] = total_return / max_dd if max_dd > 0 else 0

        # === Win/Loss Metrics ===
        wins = returns_array[returns_array > 0]
        losses = returns_array[returns_array < 0]

        metrics['win_rate'] = len(wins) / len(returns_array) if len(returns_array) > 0 else 0
        metrics['avg_win'] = np.mean(wins) if len(wins) > 0 else 0
        metrics['avg_loss'] = np.mean(losses) if len(losses) > 0 else 0
        metrics['win_loss_ratio'] = abs(metrics['avg_win'] / metrics['avg_loss']) if metrics['avg_loss'] != 0 else 0

        # === Drawdown Metrics ===
        metrics['max_drawdown'] = max_dd
        metrics['avg_drawdown'] = np.mean(drawdown) if len(drawdown) > 0 else 0
        metrics['recovery_factor'] = total_return / max_dd if max_dd > 0 else 0

        # === Consistency Metrics ===
        gross_profit = np.sum(wins) if len(wins) > 0 else 0
        gross_loss = abs(np.sum(losses)) if len(losses) > 0 else 0
        metrics['profit_factor'] = gross_profit / (gross_loss + 1e-6)
        metrics['expectancy'] = mean_return

        # === Trade Distribution ===
        metrics['total_trades'] = len(returns_array)
        metrics['winning_trades'] = len(wins)
        metrics['losing_trades'] = len(losses)
        metrics['total_return_pct'] = total_return * 100
        metrics['final_equity'] = equity_curve[-1]

        # Consecutive streaks
        metrics['max_consecutive_wins'] = PerformanceMetrics._max_streak(returns_array, positive=True)
        metrics['max_consecutive_losses'] = PerformanceMetrics._max_streak(returns_array, positive=False)

        # === Additional Metrics ===
        # R-expectancy (average R outcome)
        metrics['r_expectancy'] = mean_return

        # System quality number (SQN)
        if len(returns_array) > 1:
            metrics['sqn'] = (mean_return / (std_return + 1e-6)) * np.sqrt(len(returns_array))
        else:
            metrics['sqn'] = 0

        # Reward to Risk Ratio
        metrics['reward_to_risk'] = abs(total_return / max_dd) if max_dd > 0 else 0

        return metrics

    @staticmethod
    def _max_streak(returns, positive=True):
        """Calculate maximum consecutive winning or losing streak."""
        max_streak = 0
        current_streak = 0

        for r in returns:
            if (positive and r > 0) or (not positive and r < 0):
                current_streak += 1
                max_streak = max(max_streak, current_streak)
            else:
                current_streak = 0

        return max_streak

    @staticmethod
    def calculate_equity_curve(returns, initial_capital=10000):
        """Generate equity curve from returns."""
        returns_array = np.array(returns)
        cumulative_returns = np.cumsum(returns_array) / 100
        equity = initial_capital * (1 + cumulative_returns)
        return equity

    @staticmethod
    def calculate_drawdown_series(equity_curve):
        """Calculate drawdown series from equity curve."""
        running_max = np.maximum.accumulate(equity_curve)
        drawdown = (running_max - equity_curve) / running_max
        return drawdown

    @staticmethod
    def format_metrics_report(metrics):
        """Format metrics dictionary into readable report."""
        if not metrics:
            return "No metrics available"

        report = []
        report.append("=" * 50)
        report.append("PERFORMANCE METRICS REPORT")
        report.append("=" * 50)
        report.append("")

        report.append("Risk-Adjusted Returns:")
        report.append(f"  Sharpe Ratio:      {metrics.get('sharpe_ratio', 0):.3f}")
        report.append(f"  Sortino Ratio:     {metrics.get('sortino_ratio', 0):.3f}")
        report.append(f"  Calmar Ratio:      {metrics.get('calmar_ratio', 0):.3f}")
        report.append(f"  SQN:               {metrics.get('sqn', 0):.2f}")
        report.append("")

        report.append("Win/Loss Statistics:")
        report.append(f"  Win Rate:          {metrics.get('win_rate', 0)*100:.1f}%")
        report.append(f"  Avg Win:           {metrics.get('avg_win', 0):.3f}R")
        report.append(f"  Avg Loss:          {metrics.get('avg_loss', 0):.3f}R")
        report.append(f"  Win/Loss Ratio:    {metrics.get('win_loss_ratio', 0):.2f}")
        report.append(f"  Profit Factor:     {metrics.get('profit_factor', 0):.2f}")
        report.append("")

        report.append("Drawdown Analysis:")
        report.append(f"  Max Drawdown:      {metrics.get('max_drawdown', 0)*100:.2f}%")
        report.append(f"  Avg Drawdown:      {metrics.get('avg_drawdown', 0)*100:.2f}%")
        report.append(f"  Recovery Factor:   {metrics.get('recovery_factor', 0):.2f}")
        report.append("")

        report.append("Trade Distribution:")
        report.append(f"  Total Trades:      {metrics.get('total_trades', 0)}")
        report.append(f"  Winning Trades:    {metrics.get('winning_trades', 0)}")
        report.append(f"  Losing Trades:     {metrics.get('losing_trades', 0)}")
        report.append(f"  Max Win Streak:    {metrics.get('max_consecutive_wins', 0)}")
        report.append(f"  Max Loss Streak:   {metrics.get('max_consecutive_losses', 0)}")
        report.append("")

        report.append("Overall Performance:")
        report.append(f"  Total Return:      {metrics.get('total_return_pct', 0):.2f}%")
        report.append(f"  Expectancy:        {metrics.get('expectancy', 0):.3f}R")
        report.append(f"  Final Equity:      ${metrics.get('final_equity', 0):.2f}")
        report.append("")
        report.append("=" * 50)

        return "\n".join(report)


class MultiObjectiveMetrics:
    """Calculate metrics for multi-objective optimization."""

    @staticmethod
    def calculate_objectives(returns, equity_curve=None):
        """
        Calculate all optimization objectives.

        Returns tuple: (sharpe, win_rate, max_dd, profit_factor)
        """
        if len(returns) == 0:
            return (0, 0, 0, 0)

        returns_array = np.array(returns)

        # Objective 1: Sharpe Ratio
        mean_ret = np.mean(returns_array)
        std_ret = np.std(returns_array) + 1e-6
        sharpe = mean_ret / std_ret

        # Objective 2: Win Rate
        wins = sum(1 for r in returns_array if r > 0)
        win_rate = wins / len(returns_array)

        # Objective 3: Max Drawdown
        if equity_curve is None:
            equity_curve = PerformanceMetrics.calculate_equity_curve(returns)

        running_max = np.maximum.accumulate(equity_curve)
        drawdown = (running_max - equity_curve) / running_max
        max_dd = np.max(drawdown) if len(drawdown) > 0 else 0

        # Objective 4: Profit Factor
        gross_profit = sum(r for r in returns_array if r > 0)
        gross_loss = abs(sum(r for r in returns_array if r < 0))
        profit_factor = gross_profit / (gross_loss + 1e-6)

        return (sharpe, win_rate, max_dd, profit_factor)

    @staticmethod
    def composite_score(sharpe, win_rate, max_dd, profit_factor, weights=None):
        """
        Calculate composite score from multiple objectives.

        Default weights: [0.4, 0.3, 0.2, 0.1] for sharpe, win_rate, -max_dd, profit_factor
        """
        if weights is None:
            weights = [0.4, 0.3, 0.2, 0.1]

        # Normalize objectives (simple normalization)
        norm_sharpe = min(sharpe / 3.0, 1.0) if sharpe > 0 else 0  # Cap at 3.0
        norm_win_rate = win_rate  # Already 0-1
        norm_dd = 1.0 - min(max_dd * 2, 1.0)  # Invert and cap at 50%
        norm_pf = min(profit_factor / 3.0, 1.0) if profit_factor > 0 else 0  # Cap at 3.0

        composite = (
            weights[0] * norm_sharpe +
            weights[1] * norm_win_rate +
            weights[2] * norm_dd +
            weights[3] * norm_pf
        )

        return composite
