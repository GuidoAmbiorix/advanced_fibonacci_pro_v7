"""
Metrics Calculator
Calculate comprehensive performance metrics from backtest trades
"""

import numpy as np
import pandas as pd
from typing import List, Dict
from datetime import datetime
from loguru import logger

from app.backtesting.models import BacktestTrade, BacktestMetrics


class MetricsCalculator:
    """Calculate comprehensive trading performance metrics"""

    @staticmethod
    def calculate_all(trades: List[BacktestTrade], initial_balance: float = 10000.0) -> BacktestMetrics:
        """
        Calculate all metrics from list of closed trades

        Args:
            trades: List of closed trades
            initial_balance: Starting balance

        Returns:
            BacktestMetrics object with all calculated metrics
        """
        metrics = BacktestMetrics()

        if not trades or len(trades) == 0:
            logger.warning("No trades to calculate metrics")
            return metrics

        # Filter only closed trades
        closed_trades = [t for t in trades if t.status == "CLOSED"]

        if not closed_trades:
            logger.warning("No closed trades to calculate metrics")
            return metrics

        # Basic counts
        metrics.total_trades = len(closed_trades)
        metrics.winning_trades = sum(1 for t in closed_trades if t.pnl > 0)
        metrics.losing_trades = sum(1 for t in closed_trades if t.pnl < 0)
        metrics.break_even_trades = sum(1 for t in closed_trades if t.pnl == 0)

        # Win/Loss rates
        if metrics.total_trades > 0:
            metrics.win_rate = (metrics.winning_trades / metrics.total_trades) * 100
            metrics.loss_rate = (metrics.losing_trades / metrics.total_trades) * 100

        # P&L calculations
        wins = [t.pnl for t in closed_trades if t.pnl > 0]
        losses = [t.pnl for t in closed_trades if t.pnl < 0]

        metrics.total_profit = sum(wins) if wins else 0
        metrics.total_loss = abs(sum(losses)) if losses else 0
        metrics.net_profit = sum(t.pnl for t in closed_trades)

        # Profit factor
        if metrics.total_loss > 0:
            metrics.profit_factor = metrics.total_profit / metrics.total_loss
        else:
            # avoiding float('inf') for JSON serialization
            metrics.profit_factor = 999.0 if metrics.total_profit > 0 else 0

        # Averages
        if wins:
            metrics.average_win = np.mean(wins)
        if losses:
            metrics.average_loss = abs(np.mean(losses))

        # Average R:R
        if metrics.average_loss > 0:
            metrics.average_rr = metrics.average_win / metrics.average_loss

        # Alternative: R multiples
        r_multiples = [t.return_r for t in closed_trades if hasattr(t, 'return_r')]
        if r_multiples:
            avg_r = np.mean(r_multiples)
            metrics.average_rr = max(metrics.average_rr, avg_r)

        # Expectancy
        if metrics.total_trades > 0:
            metrics.expectancy = (
                (metrics.win_rate / 100 * metrics.average_win) -
                (metrics.loss_rate / 100 * metrics.average_loss)
            )

            # Expectancy in R
            if r_multiples:
                metrics.expectancy_r = np.mean(r_multiples)

        # Drawdown
        equity_curve = MetricsCalculator._calculate_equity_curve(closed_trades, initial_balance)
        dd_info = MetricsCalculator._calculate_drawdown(equity_curve)
        metrics.max_drawdown = dd_info['max_dd']
        metrics.max_drawdown_percent = dd_info['max_dd_percent']

        # Consecutive wins/losses
        streaks = MetricsCalculator._calculate_streaks(closed_trades)
        metrics.max_consecutive_wins = streaks['max_wins']
        metrics.max_consecutive_losses = streaks['max_losses']

        # Risk-adjusted metrics
        returns = [t.pnl for t in closed_trades]
        if len(returns) > 1:
            metrics.sharpe_ratio = MetricsCalculator._calculate_sharpe(returns)
            metrics.sortino_ratio = MetricsCalculator._calculate_sortino(returns)
            
        # Kelly Criterion
        if metrics.average_loss > 0:
            win_prob = metrics.win_rate / 100
            loss_prob = metrics.loss_rate / 100
            r_ratio = metrics.average_win / metrics.average_loss
            
            # Kelly = W - (1-W)/R
            if r_ratio > 0:
                metrics.kelly_fraction = win_prob - (loss_prob / r_ratio)
                metrics.half_kelly = metrics.kelly_fraction / 2
                
                # Check for "gambler's ruin" (negative expectancy) which breaks Kelly
                if metrics.expectancy <= 0:
                     metrics.kelly_fraction = 0.0
                     metrics.half_kelly = 0.0

        # Calmar ratio
        if metrics.max_drawdown > 0:
            annualized_return = MetricsCalculator._annualize_return(
                metrics.net_profit,
                initial_balance,
                closed_trades
            )
            metrics.calmar_ratio = annualized_return / metrics.max_drawdown_percent

        # Recovery factor
        if metrics.max_drawdown > 0:
            metrics.recovery_factor = metrics.net_profit / metrics.max_drawdown

        # Payoff ratio
        if metrics.average_loss > 0:
            metrics.payoff_ratio = metrics.average_win / metrics.average_loss

        # Best/Worst/Median
        all_pnls = [t.pnl for t in closed_trades]
        metrics.best_trade = max(all_pnls)
        metrics.worst_trade = min(all_pnls)
        metrics.median_trade = np.median(all_pnls)

        # Time metrics
        durations = []
        for t in closed_trades:
            if t.exit_time and t.entry_time:
                duration = (t.exit_time - t.entry_time).total_seconds() / 3600
                durations.append(duration)

        if durations:
            metrics.avg_trade_duration_hours = np.mean(durations)

        # Trades per month
        if closed_trades:
            date_range = (closed_trades[-1].exit_time - closed_trades[0].entry_time).days
            if date_range > 0:
                months = date_range / 30
                metrics.total_trades_per_month = metrics.total_trades / months

        logger.info(f"Calculated metrics for {metrics.total_trades} trades")
        return metrics

    @staticmethod
    def _calculate_equity_curve(trades: List[BacktestTrade], initial_balance: float) -> List[Dict]:
        """Calculate equity curve from trades"""
        equity_curve = [{'time': None, 'balance': initial_balance, 'equity': initial_balance}]

        current_balance = initial_balance

        for trade in sorted(trades, key=lambda t: t.exit_time if t.exit_time else t.entry_time):
            if trade.status == "CLOSED":
                current_balance += trade.pnl
                equity_curve.append({
                    'time': trade.exit_time,
                    'balance': current_balance,
                    'equity': current_balance
                })

        return equity_curve

    @staticmethod
    def _calculate_drawdown(equity_curve: List[Dict]) -> Dict:
        """Calculate maximum drawdown"""
        if len(equity_curve) < 2:
            return {'max_dd': 0, 'max_dd_percent': 0}

        balances = [point['balance'] for point in equity_curve]

        max_dd = 0
        max_dd_percent = 0
        peak = balances[0]

        for balance in balances:
            if balance > peak:
                peak = balance

            dd = peak - balance
            dd_percent = (dd / peak * 100) if peak > 0 else 0

            if dd > max_dd:
                max_dd = dd
                max_dd_percent = dd_percent

        return {
            'max_dd': max_dd,
            'max_dd_percent': max_dd_percent
        }

    @staticmethod
    def _calculate_streaks(trades: List[BacktestTrade]) -> Dict:
        """Calculate max consecutive wins and losses"""
        if not trades:
            return {'max_wins': 0, 'max_losses': 0}

        max_wins = 0
        max_losses = 0
        current_wins = 0
        current_losses = 0

        for trade in sorted(trades, key=lambda t: t.exit_time if t.exit_time else t.entry_time):
            if trade.pnl > 0:
                current_wins += 1
                current_losses = 0
                max_wins = max(max_wins, current_wins)
            elif trade.pnl < 0:
                current_losses += 1
                current_wins = 0
                max_losses = max(max_losses, current_losses)
            else:  # Break even
                current_wins = 0
                current_losses = 0

        return {
            'max_wins': max_wins,
            'max_losses': max_losses
        }

    @staticmethod
    def _calculate_sharpe(returns: List[float], risk_free_rate: float = 0.0) -> float:
        """
        Calculate Sharpe Ratio

        Sharpe = (Mean Return - Risk Free Rate) / Std Dev of Returns
        """
        if len(returns) < 2:
            return 0.0

        returns_array = np.array(returns)
        mean_return = np.mean(returns_array)
        std_return = np.std(returns_array, ddof=1)

        if std_return == 0:
            return 0.0

        sharpe = (mean_return - risk_free_rate) / std_return

        # Annualize (assuming daily returns, adjust if needed)
        # For per-trade returns, multiply by sqrt(number of trades per year)
        # Simplified: use as-is for per-trade Sharpe

        return sharpe

    @staticmethod
    def _calculate_sortino(returns: List[float], target_return: float = 0.0) -> float:
        """
        Calculate Sortino Ratio

        Like Sharpe but only considers downside volatility
        """
        if len(returns) < 2:
            return 0.0

        returns_array = np.array(returns)
        mean_return = np.mean(returns_array)

        # Downside deviation (only negative returns)
        downside_returns = returns_array[returns_array < target_return]

        if len(downside_returns) == 0:
            return float('inf') if mean_return > target_return else 0.0

        downside_std = np.std(downside_returns, ddof=1)

        if downside_std == 0:
            return 0.0

        sortino = (mean_return - target_return) / downside_std

        return sortino

    @staticmethod
    def _annualize_return(net_profit: float, initial_balance: float, trades: List[BacktestTrade]) -> float:
        """Calculate annualized return percentage"""
        if not trades or initial_balance == 0:
            return 0.0

        # Calculate total days
        first_trade = min(trades, key=lambda t: t.entry_time)
        last_trade = max(trades, key=lambda t: t.exit_time if t.exit_time else t.entry_time)

        total_days = (last_trade.exit_time - first_trade.entry_time).days

        if total_days == 0:
            return 0.0

        # Total return
        total_return = (net_profit / initial_balance) * 100

        # Annualize
        years = total_days / 365.25
        if years > 0:
            annualized = total_return / years
        else:
            annualized = total_return

        return annualized

    @staticmethod
    def generate_summary_text(metrics: BacktestMetrics) -> str:
        """Generate text summary of metrics"""
        summary = f"""
╔══════════════════════════════════════════════════════════════╗
║              BACKTEST PERFORMANCE SUMMARY                    ║
╚══════════════════════════════════════════════════════════════╝

📊 BASIC STATISTICS
────────────────────────────────────────────────────────────────
Total Trades:           {metrics.total_trades}
Winning Trades:         {metrics.winning_trades} ({metrics.win_rate:.2f}%)
Losing Trades:          {metrics.losing_trades} ({metrics.loss_rate:.2f}%)
Break-Even Trades:      {metrics.break_even_trades}

💰 PROFIT & LOSS
────────────────────────────────────────────────────────────────
Total Profit:           ${metrics.total_profit:.2f}
Total Loss:             ${metrics.total_loss:.2f}
Net Profit:             ${metrics.net_profit:.2f}
Profit Factor:          {metrics.profit_factor:.2f}

📈 AVERAGES
────────────────────────────────────────────────────────────────
Average Win:            ${metrics.average_win:.2f}
Average Loss:           ${metrics.average_loss:.2f}
Average R:R:            {metrics.average_rr:.2f}
Expectancy (per trade): ${metrics.expectancy:.2f}
Expectancy (R):         {metrics.expectancy_r:.2f}R

📉 RISK METRICS
────────────────────────────────────────────────────────────────
Max Drawdown:           ${metrics.max_drawdown:.2f} ({metrics.max_drawdown_percent:.2f}%)
Max Consecutive Wins:   {metrics.max_consecutive_wins}
Max Consecutive Losses: {metrics.max_consecutive_losses}

🎯 RISK-ADJUSTED RETURNS
────────────────────────────────────────────────────────────────
Sharpe Ratio:           {metrics.sharpe_ratio:.2f}
Sortino Ratio:          {metrics.sortino_ratio:.2f}
Calmar Ratio:           {metrics.calmar_ratio:.2f}
Recovery Factor:        {metrics.recovery_factor:.2f}

📊 DISTRIBUTION
────────────────────────────────────────────────────────────────
Best Trade:             ${metrics.best_trade:.2f}
Worst Trade:            ${metrics.worst_trade:.2f}
Median Trade:           ${metrics.median_trade:.2f}

⏱️  TIME METRICS
────────────────────────────────────────────────────────────────
Avg Trade Duration:     {metrics.avg_trade_duration_hours:.1f} hours
Trades Per Month:       {metrics.total_trades_per_month:.1f}

╔══════════════════════════════════════════════════════════════╗
║  VERDICT: {"✅ PASS" if MetricsCalculator._is_passing(metrics) else "❌ FAIL"}                                           ║
╚══════════════════════════════════════════════════════════════╝
        """
        return summary

    @staticmethod
    def _is_passing(metrics: BacktestMetrics) -> bool:
        """Check if metrics meet minimum criteria"""
        criteria = [
            metrics.total_trades >= 50,
            metrics.win_rate >= 45.0,
            metrics.profit_factor >= 1.5,
            metrics.max_drawdown_percent < 15.0,
            metrics.average_rr >= 2.0,
            metrics.expectancy > 0,
        ]

        return all(criteria)

    @staticmethod
    def get_trade_breakdown(trades: List[BacktestTrade]) -> pd.DataFrame:
        """Convert trades to DataFrame for analysis"""
        if not trades:
            return pd.DataFrame()

        data = []
        for t in trades:
            if t.status == "CLOSED":
                data.append({
                    'entry_time': t.entry_time,
                    'exit_time': t.exit_time,
                    'symbol': t.symbol,
                    'type': t.signal_type,
                    'entry_price': t.entry_price,
                    'exit_price': t.exit_price,
                    'exit_reason': t.exit_reason,
                    'volume': t.volume,
                    'pnl': t.pnl,
                    'pnl_pips': t.pnl_pips,
                    'return_r': t.return_r,
                    'confluence_score': t.confluence_score,
                    'duration_hours': (t.exit_time - t.entry_time).total_seconds() / 3600,
                })

        return pd.DataFrame(data)
