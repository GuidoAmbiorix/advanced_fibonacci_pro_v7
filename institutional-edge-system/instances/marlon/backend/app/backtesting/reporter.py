"""
Report Generator
Create visual and text reports from backtest results
"""

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
from loguru import logger

from app.backtesting.models import BacktestTrade, BacktestMetrics, BacktestResults
from app.backtesting.metrics import MetricsCalculator


class ReportGenerator:
    """Generate comprehensive backtest reports"""

    def __init__(self, output_dir: str = "reports"):
        """
        Initialize report generator

        Args:
            output_dir: Directory to save reports
        """
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Set matplotlib style
        plt.style.use('seaborn-v0_8-darkgrid')

        logger.info(f"ReportGenerator initialized - Output: {self.output_dir}")

    def generate_full_report(
        self,
        results: BacktestResults,
        save_name: str = "backtest_report"
    ) -> Dict[str, str]:
        """
        Generate complete report with all charts and text

        Args:
            results: Backtest results
            save_name: Base name for saved files

        Returns:
            Dict of generated file paths
        """
        logger.info(f"Generating full report: {save_name}")

        generated_files = {}

        # 1. Equity curve
        equity_chart = self.plot_equity_curve(
            results.equity_curve,
            results.trades,
            save_path=self.output_dir / f"{save_name}_equity.png"
        )
        if equity_chart:
            generated_files['equity_curve'] = equity_chart

        # 2. Trade distribution
        dist_chart = self.plot_trade_distribution(
            results.trades,
            save_path=self.output_dir / f"{save_name}_distribution.png"
        )
        if dist_chart:
            generated_files['distribution'] = dist_chart

        # 3. Monthly returns
        monthly_chart = self.plot_monthly_returns(
            results.trades,
            save_path=self.output_dir / f"{save_name}_monthly.png"
        )
        if monthly_chart:
            generated_files['monthly_returns'] = monthly_chart

        # 4. Drawdown chart
        dd_chart = self.plot_drawdown(
            results.equity_curve,
            save_path=self.output_dir / f"{save_name}_drawdown.png"
        )
        if dd_chart:
            generated_files['drawdown'] = dd_chart

        # 5. Text summary
        summary_path = self.save_text_summary(
            results,
            save_path=self.output_dir / f"{save_name}_summary.txt"
        )
        if summary_path:
            generated_files['summary'] = summary_path

        # 6. Trade log CSV
        csv_path = self.save_trade_log(
            results.trades,
            save_path=self.output_dir / f"{save_name}_trades.csv"
        )
        if csv_path:
            generated_files['trade_log'] = csv_path

        logger.info(f"Report generated: {len(generated_files)} files created")
        return generated_files

    def plot_equity_curve(
        self,
        equity_curve: List[Dict],
        trades: List[BacktestTrade],
        save_path: Optional[Path] = None
    ) -> Optional[str]:
        """Plot equity curve with trade markers"""
        try:
            if not equity_curve or len(equity_curve) < 2:
                logger.warning("Insufficient data for equity curve")
                return None

            fig, ax = plt.subplots(figsize=(14, 7))

            # Extract data
            times = [point['time'] for point in equity_curve if point['time']]
            balances = [point['balance'] for point in equity_curve if point['time']]

            # Plot equity curve
            ax.plot(times, balances, linewidth=2, label='Equity', color='#2E86AB')

            # Mark winning and losing trades
            wins = [t for t in trades if t.status == "CLOSED" and t.pnl > 0]
            losses = [t for t in trades if t.status == "CLOSED" and t.pnl < 0]

            if wins:
                win_times = [t.exit_time for t in wins]
                win_balances = [self._get_balance_at_time(equity_curve, t.exit_time) for t in wins]
                ax.scatter(win_times, win_balances, color='green', marker='^', s=50, alpha=0.6, label='Wins')

            if losses:
                loss_times = [t.exit_time for t in losses]
                loss_balances = [self._get_balance_at_time(equity_curve, t.exit_time) for t in losses]
                ax.scatter(loss_times, loss_balances, color='red', marker='v', s=50, alpha=0.6, label='Losses')

            # Formatting
            ax.set_title('Equity Curve', fontsize=16, fontweight='bold')
            ax.set_xlabel('Date', fontsize=12)
            ax.set_ylabel('Balance ($)', fontsize=12)
            ax.legend(loc='best')
            ax.grid(True, alpha=0.3)

            # Format x-axis dates
            ax.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d'))
            ax.xaxis.set_major_locator(mdates.AutoDateLocator())
            plt.xticks(rotation=45)

            plt.tight_layout()

            if save_path:
                plt.savefig(save_path, dpi=300, bbox_inches='tight')
                logger.info(f"Equity curve saved: {save_path}")
                plt.close()
                return str(save_path)

            plt.show()
            return None

        except Exception as e:
            logger.error(f"Error plotting equity curve: {e}")
            return None

    def plot_trade_distribution(
        self,
        trades: List[BacktestTrade],
        save_path: Optional[Path] = None
    ) -> Optional[str]:
        """Plot P&L distribution histogram"""
        try:
            closed_trades = [t for t in trades if t.status == "CLOSED"]
            if not closed_trades:
                return None

            pnls = [t.pnl for t in closed_trades]

            fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

            # Histogram of P&L
            ax1.hist(pnls, bins=30, color='#A23B72', alpha=0.7, edgecolor='black')
            ax1.axvline(0, color='red', linestyle='--', linewidth=2, label='Break-even')
            ax1.set_title('P&L Distribution', fontsize=14, fontweight='bold')
            ax1.set_xlabel('Profit/Loss ($)', fontsize=11)
            ax1.set_ylabel('Frequency', fontsize=11)
            ax1.legend()
            ax1.grid(True, alpha=0.3)

            # Cumulative P&L
            cumulative = pd.Series(pnls).cumsum()
            ax2.plot(range(len(cumulative)), cumulative, linewidth=2, color='#2E86AB')
            ax2.axhline(0, color='red', linestyle='--', linewidth=1)
            ax2.set_title('Cumulative P&L', fontsize=14, fontweight='bold')
            ax2.set_xlabel('Trade Number', fontsize=11)
            ax2.set_ylabel('Cumulative P&L ($)', fontsize=11)
            ax2.grid(True, alpha=0.3)

            plt.tight_layout()

            if save_path:
                plt.savefig(save_path, dpi=300, bbox_inches='tight')
                logger.info(f"Distribution chart saved: {save_path}")
                plt.close()
                return str(save_path)

            plt.show()
            return None

        except Exception as e:
            logger.error(f"Error plotting distribution: {e}")
            return None

    def plot_monthly_returns(
        self,
        trades: List[BacktestTrade],
        save_path: Optional[Path] = None
    ) -> Optional[str]:
        """Plot monthly returns bar chart"""
        try:
            closed_trades = [t for t in trades if t.status == "CLOSED"]
            if not closed_trades:
                return None

            # Group by month
            df = pd.DataFrame([{
                'date': t.exit_time,
                'pnl': t.pnl
            } for t in closed_trades])

            df['month'] = pd.to_datetime(df['date']).dt.to_period('M')
            monthly = df.groupby('month')['pnl'].sum()

            fig, ax = plt.subplots(figsize=(14, 6))

            # Color bars based on positive/negative
            colors = ['green' if x > 0 else 'red' for x in monthly.values]
            ax.bar(range(len(monthly)), monthly.values, color=colors, alpha=0.7, edgecolor='black')

            # Formatting
            ax.axhline(0, color='black', linewidth=1)
            ax.set_title('Monthly Returns', fontsize=14, fontweight='bold')
            ax.set_xlabel('Month', fontsize=11)
            ax.set_ylabel('P&L ($)', fontsize=11)
            ax.set_xticks(range(len(monthly)))
            ax.set_xticklabels([str(m) for m in monthly.index], rotation=45)
            ax.grid(True, alpha=0.3, axis='y')

            plt.tight_layout()

            if save_path:
                plt.savefig(save_path, dpi=300, bbox_inches='tight')
                logger.info(f"Monthly returns saved: {save_path}")
                plt.close()
                return str(save_path)

            plt.show()
            return None

        except Exception as e:
            logger.error(f"Error plotting monthly returns: {e}")
            return None

    def plot_drawdown(
        self,
        equity_curve: List[Dict],
        save_path: Optional[Path] = None
    ) -> Optional[str]:
        """Plot drawdown over time"""
        try:
            if not equity_curve or len(equity_curve) < 2:
                return None

            times = [point['time'] for point in equity_curve if point['time']]
            balances = [point['balance'] for point in equity_curve if point['time']]

            # Calculate drawdown
            peak = balances[0]
            drawdowns = []

            for balance in balances:
                if balance > peak:
                    peak = balance
                dd_percent = ((peak - balance) / peak) * 100 if peak > 0 else 0
                drawdowns.append(dd_percent)

            fig, ax = plt.subplots(figsize=(14, 6))

            ax.fill_between(times, drawdowns, 0, color='red', alpha=0.3)
            ax.plot(times, drawdowns, color='darkred', linewidth=2)

            ax.set_title('Drawdown Over Time', fontsize=14, fontweight='bold')
            ax.set_xlabel('Date', fontsize=11)
            ax.set_ylabel('Drawdown (%)', fontsize=11)
            ax.grid(True, alpha=0.3)

            # Format dates
            ax.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d'))
            plt.xticks(rotation=45)

            plt.tight_layout()

            if save_path:
                plt.savefig(save_path, dpi=300, bbox_inches='tight')
                logger.info(f"Drawdown chart saved: {save_path}")
                plt.close()
                return str(save_path)

            plt.show()
            return None

        except Exception as e:
            logger.error(f"Error plotting drawdown: {e}")
            return None

    def save_text_summary(
        self,
        results: BacktestResults,
        save_path: Optional[Path] = None
    ) -> Optional[str]:
        """Save text summary to file"""
        try:
            summary = MetricsCalculator.generate_summary_text(results.metrics)

            # Add config info
            header = f"""
{'='*64}
BACKTEST CONFIGURATION
{'='*64}

Symbol:              {results.config.symbol}
Timeframe:           {results.config.timeframe}
Period:              {results.start_date.strftime('%Y-%m-%d') if results.start_date else 'N/A'} to {results.end_date.strftime('%Y-%m-%d') if results.end_date else 'N/A'}
Initial Balance:     ${results.config.initial_balance:,.2f}
Risk per Trade:      {results.config.risk_percent}%
Min Confluence:      {results.config.min_confluence_score}/10

Total Bars Analyzed: {results.total_bars}
Execution Time:      {results.execution_time_seconds:.2f} seconds

"""

            full_text = header + summary

            if save_path:
                save_path.write_text(full_text)
                logger.info(f"Summary saved: {save_path}")
                return str(save_path)

            print(full_text)
            return None

        except Exception as e:
            logger.error(f"Error saving summary: {e}")
            return None

    def save_trade_log(
        self,
        trades: List[BacktestTrade],
        save_path: Optional[Path] = None
    ) -> Optional[str]:
        """Save trade log as CSV"""
        try:
            df = MetricsCalculator.get_trade_breakdown(trades)

            if df.empty:
                return None

            if save_path:
                df.to_csv(save_path, index=False)
                logger.info(f"Trade log saved: {save_path} ({len(df)} trades)")
                return str(save_path)

            return None

        except Exception as e:
            logger.error(f"Error saving trade log: {e}")
            return None

    def _get_balance_at_time(self, equity_curve: List[Dict], target_time: datetime) -> float:
        """Get balance at specific time from equity curve"""
        for point in equity_curve:
            if point['time'] and point['time'] >= target_time:
                return point['balance']

        # Return last balance if not found
        return equity_curve[-1]['balance'] if equity_curve else 0
