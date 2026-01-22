import pandas as pd
import numpy as np
from typing import Dict, Tuple
from datetime import datetime

class PerformanceAnalytics:
    def __init__(self, trades_df: pd.DataFrame):
        """
        Advanced performance analytics for MT5 trading bot.

        Args:
            trades_df: DataFrame with trade history including profit, commission, swap
        """
        self.trades_df = trades_df.copy()
        if not self.trades_df.empty:
            self.trades_df['total_profit'] = (
                self.trades_df['profit'] +
                self.trades_df['commission'] +
                self.trades_df['swap']
            )
            self.trades_df = self.trades_df.sort_values('exit_time')

    def calculate_equity_curve(self, initial_balance: float = 10000) -> pd.DataFrame:
        """
        Calculate equity curve over time.

        Returns:
            DataFrame with columns: timestamp, equity, drawdown, drawdown_pct
        """
        if self.trades_df.empty:
            return pd.DataFrame()

        equity_data = []
        running_equity = initial_balance
        peak_equity = initial_balance

        for _, trade in self.trades_df.iterrows():
            running_equity += trade['total_profit']
            peak_equity = max(peak_equity, running_equity)

            drawdown = peak_equity - running_equity
            drawdown_pct = (drawdown / peak_equity * 100) if peak_equity > 0 else 0

            equity_data.append({
                'timestamp': trade['exit_time'],
                'equity': running_equity,
                'peak_equity': peak_equity,
                'drawdown': drawdown,
                'drawdown_pct': drawdown_pct
            })

        return pd.DataFrame(equity_data)

    def calculate_sharpe_ratio(self, risk_free_rate: float = 0.02) -> float:
        """
        Calculate Sharpe Ratio (annualized).

        Args:
            risk_free_rate: Annual risk-free rate (default 2%)

        Returns:
            Sharpe ratio value
        """
        if self.trades_df.empty or len(self.trades_df) < 2:
            return 0.0

        returns = self.trades_df['total_profit'].values

        if returns.std() == 0:
            return 0.0

        # Annualize assuming 252 trading days
        mean_return = returns.mean() * 252
        std_return = returns.std() * np.sqrt(252)

        sharpe = (mean_return - risk_free_rate) / std_return
        return sharpe

    def calculate_max_drawdown(self) -> Dict[str, float]:
        """
        Calculate maximum drawdown and related metrics.

        Returns:
            Dict with max_drawdown, max_drawdown_pct, recovery_time
        """
        equity_curve = self.calculate_equity_curve()

        if equity_curve.empty:
            return {
                'max_drawdown': 0.0,
                'max_drawdown_pct': 0.0,
                'current_drawdown': 0.0,
                'current_drawdown_pct': 0.0
            }

        max_dd = equity_curve['drawdown'].max()
        max_dd_pct = equity_curve['drawdown_pct'].max()

        current_dd = equity_curve.iloc[-1]['drawdown']
        current_dd_pct = equity_curve.iloc[-1]['drawdown_pct']

        return {
            'max_drawdown': max_dd,
            'max_drawdown_pct': max_dd_pct,
            'current_drawdown': current_dd,
            'current_drawdown_pct': current_dd_pct
        }

    def calculate_win_loss_streaks(self) -> Dict[str, int]:
        """
        Calculate longest winning and losing streaks.

        Returns:
            Dict with longest_win_streak and longest_loss_streak
        """
        if self.trades_df.empty:
            return {'longest_win_streak': 0, 'longest_loss_streak': 0, 'current_streak': 0}

        is_win = self.trades_df['total_profit'] > 0

        # Calculate streaks
        streaks = []
        current_streak = 1

        for i in range(1, len(is_win)):
            if is_win.iloc[i] == is_win.iloc[i-1]:
                current_streak += 1
            else:
                streaks.append((is_win.iloc[i-1], current_streak))
                current_streak = 1

        streaks.append((is_win.iloc[-1], current_streak))

        win_streaks = [s[1] for s in streaks if s[0]]
        loss_streaks = [s[1] for s in streaks if not s[0]]

        return {
            'longest_win_streak': max(win_streaks) if win_streaks else 0,
            'longest_loss_streak': max(loss_streaks) if loss_streaks else 0,
            'current_streak': streaks[-1][1] if streaks else 0,
            'current_streak_type': 'WIN' if streaks[-1][0] else 'LOSS' if streaks else 'NONE'
        }

    def calculate_profit_distribution(self) -> pd.DataFrame:
        """
        Calculate profit distribution buckets for visualization.

        Returns:
            DataFrame with profit ranges and counts
        """
        if self.trades_df.empty:
            return pd.DataFrame()

        bins = [-np.inf, -500, -200, -100, -50, 0, 50, 100, 200, 500, np.inf]
        labels = ['<-500', '-500:-200', '-200:-100', '-100:-50', '-50:0',
                  '0:50', '50:100', '100:200', '200:500', '>500']

        self.trades_df['profit_bucket'] = pd.cut(
            self.trades_df['total_profit'],
            bins=bins,
            labels=labels
        )

        distribution = self.trades_df.groupby('profit_bucket', observed=True).size().reset_index(name='count')
        return distribution

    def analyze_by_symbol(self) -> pd.DataFrame:
        """
        Analyze performance by trading symbol.

        Returns:
            DataFrame with symbol-level statistics
        """
        if self.trades_df.empty:
            return pd.DataFrame()

        symbol_stats = self.trades_df.groupby('symbol').agg({
            'ticket': 'count',
            'total_profit': ['sum', 'mean', 'std'],
            'duration_minutes': 'mean'
        }).round(2)

        symbol_stats.columns = ['trades', 'total_pnl', 'avg_pnl', 'std_pnl', 'avg_duration']

        # Calculate win rate per symbol
        win_rate = self.trades_df.groupby('symbol').apply(
            lambda x: (x[x['total_profit'] > 0].shape[0] / x.shape[0] * 100)
        ).round(1)

        symbol_stats['win_rate'] = win_rate
        symbol_stats = symbol_stats.reset_index()
        symbol_stats = symbol_stats.sort_values('total_pnl', ascending=False)

        return symbol_stats

    def analyze_by_time(self) -> Dict[str, pd.DataFrame]:
        """
        Analyze performance by time periods (hour, day of week).

        Returns:
            Dict with 'by_hour' and 'by_day' DataFrames
        """
        if self.trades_df.empty:
            return {'by_hour': pd.DataFrame(), 'by_day': pd.DataFrame()}

        df = self.trades_df.copy()
        df['hour'] = df['entry_time'].dt.hour
        df['day_of_week'] = df['entry_time'].dt.day_name()

        # By hour
        hour_stats = df.groupby('hour').agg({
            'ticket': 'count',
            'total_profit': ['sum', 'mean']
        }).round(2)
        hour_stats.columns = ['trades', 'total_pnl', 'avg_pnl']
        hour_stats = hour_stats.reset_index()

        # By day
        day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        day_stats = df.groupby('day_of_week').agg({
            'ticket': 'count',
            'total_profit': ['sum', 'mean']
        }).round(2)
        day_stats.columns = ['trades', 'total_pnl', 'avg_pnl']
        day_stats = day_stats.reset_index()
        day_stats['day_of_week'] = pd.Categorical(
            day_stats['day_of_week'],
            categories=day_order,
            ordered=True
        )
        day_stats = day_stats.sort_values('day_of_week')

        return {
            'by_hour': hour_stats,
            'by_day': day_stats
        }

    def get_summary_stats(self) -> Dict:
        """
        Get comprehensive summary statistics.

        Returns:
            Dict with all key metrics
        """
        if self.trades_df.empty:
            return {}

        total_trades = len(self.trades_df)
        winning_trades = self.trades_df[self.trades_df['total_profit'] > 0]
        losing_trades = self.trades_df[self.trades_df['total_profit'] <= 0]

        gross_profit = winning_trades['total_profit'].sum()
        gross_loss = abs(losing_trades['total_profit'].sum())
        net_profit = self.trades_df['total_profit'].sum()

        profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else float('inf')
        win_rate = (len(winning_trades) / total_trades * 100) if total_trades > 0 else 0

        avg_win = winning_trades['total_profit'].mean() if len(winning_trades) > 0 else 0
        avg_loss = losing_trades['total_profit'].mean() if len(losing_trades) > 0 else 0

        expectancy = (win_rate/100 * avg_win) + ((1 - win_rate/100) * avg_loss)

        dd_stats = self.calculate_max_drawdown()
        streaks = self.calculate_win_loss_streaks()

        return {
            'total_trades': total_trades,
            'winning_trades': len(winning_trades),
            'losing_trades': len(losing_trades),
            'win_rate': round(win_rate, 2),
            'net_profit': round(net_profit, 2),
            'gross_profit': round(gross_profit, 2),
            'gross_loss': round(gross_loss, 2),
            'profit_factor': round(profit_factor, 2),
            'avg_win': round(avg_win, 2),
            'avg_loss': round(avg_loss, 2),
            'expectancy': round(expectancy, 2),
            'sharpe_ratio': round(self.calculate_sharpe_ratio(), 2),
            'max_drawdown': round(dd_stats['max_drawdown'], 2),
            'max_drawdown_pct': round(dd_stats['max_drawdown_pct'], 2),
            'current_drawdown': round(dd_stats['current_drawdown'], 2),
            'current_drawdown_pct': round(dd_stats['current_drawdown_pct'], 2),
            'longest_win_streak': streaks['longest_win_streak'],
            'longest_loss_streak': streaks['longest_loss_streak'],
            'current_streak': streaks['current_streak'],
            'current_streak_type': streaks['current_streak_type']
        }
