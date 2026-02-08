"""
Analytics Engine - Data Aggregation & Metrics Calculation
===========================================================
This module calculates and populates all analytics tables from raw trade data.

Functions organized by phase:
- Phase 1: Core Analytics (Daily, Symbol, Regime, Killzone)
- Phase 2: Advanced Analytics (Correlation, Drawdown, Parameters, Patterns)
- Phase 3: Portfolio Analytics
"""

import sqlite3
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
import json
from scipy import stats


class AnalyticsEngine:
    def __init__(self, db_path: str):
        self.db_path = db_path

    def get_connection(self):
        """Get database connection"""
        return sqlite3.connect(self.db_path, check_same_thread=False)

    # =========================================================================
    # PHASE 1: CORE ANALYTICS
    # =========================================================================

    def populate_daily_performance(self, date: str):
        """
        Calculate and store daily performance metrics.

        Args:
            date: 'YYYY-MM-DD' format
        """
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            # Get date range (entire day)
            date_obj = datetime.strptime(date, '%Y-%m-%d')
            start_ts = int(date_obj.timestamp())
            end_ts = start_ts + 86400  # +24 hours

            # Get all closed trades for this day
            df_trades = pd.read_sql("""
                SELECT * FROM Trades
                WHERE close_time >= ? AND close_time < ?
                AND close_time IS NOT NULL AND close_time > 0
            """, conn, params=(start_ts, end_ts))

            if df_trades.empty:
                print(f"No trades on {date}, skipping")
                return

            # Calculate metrics
            total_trades = len(df_trades)
            wins = (df_trades['profit'] > 0).sum()
            losses = (df_trades['profit'] <= 0).sum()
            win_rate = (wins / total_trades * 100) if total_trades > 0 else 0

            # P&L
            daily_pnl = df_trades['profit'].sum()
            avg_win = df_trades[df_trades['profit'] > 0]['profit'].mean() if wins > 0 else 0
            avg_loss = df_trades[df_trades['profit'] <= 0]['profit'].mean() if losses > 0 else 0
            largest_win = df_trades['profit'].max()
            largest_loss = df_trades['profit'].min()

            # Profit factor
            total_wins = df_trades[df_trades['profit'] > 0]['profit'].sum()
            total_losses = abs(df_trades[df_trades['profit'] <= 0]['profit'].sum())
            profit_factor = (total_wins / total_losses) if total_losses > 0 else 0

            # Expectancy (avg R)
            avg_r = df_trades['profit'].mean() if total_trades > 0 else 0

            # Duration
            df_trades['duration'] = (df_trades['close_time'] - df_trades['entry_time']) / 60
            avg_duration = df_trades['duration'].mean()

            # Commission & Swap
            total_commission = df_trades['commission'].sum()
            total_swap = df_trades['swap'].sum()

            # Symbol breakdown
            symbol_pnl = df_trades.groupby('symbol')['profit'].sum().to_dict()
            symbol_pnl_json = json.dumps(symbol_pnl)

            # Regime distribution
            regime_dist = df_trades['regime'].value_counts(normalize=True).to_dict()
            regime_dist = {k: round(v * 100, 1) for k, v in regime_dist.items()}
            regime_distribution_json = json.dumps(regime_dist)
            dominant_regime = df_trades['regime'].mode()[0] if not df_trades['regime'].mode().empty else 'UNKNOWN'

            # Get balance history (cumulative)
            cumulative_pnl = self._get_cumulative_pnl(end_ts, conn)

            # Insert into DailyPerformance
            cursor.execute("""
                INSERT OR REPLACE INTO DailyPerformance (
                    date, day_of_week, daily_pnl, total_trades, wins, losses,
                    win_rate, profit_factor, avg_win, avg_loss, largest_win, largest_loss,
                    expectancy, avg_trade_duration_minutes, total_commission, total_swap,
                    symbol_pnl_json, dominant_regime, regime_distribution_json,
                    cumulative_pnl, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                date, date_obj.strftime('%A'), daily_pnl, total_trades, wins, losses,
                win_rate, profit_factor, avg_win, avg_loss, largest_win, largest_loss,
                avg_r, avg_duration, total_commission, total_swap,
                symbol_pnl_json, dominant_regime, regime_distribution_json,
                cumulative_pnl, int(datetime.now().timestamp())
            ))

            conn.commit()
            print(f"✅ DailyPerformance populated for {date}: {total_trades} trades, P&L: ${daily_pnl:.2f}")

        except Exception as e:
            print(f"❌ Error populating DailyPerformance for {date}: {e}")
            conn.rollback()
        finally:
            conn.close()

    def populate_symbol_performance(self, date: str):
        """Calculate per-symbol performance for a given date"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            date_obj = datetime.strptime(date, '%Y-%m-%d')
            start_ts = int(date_obj.timestamp())
            end_ts = start_ts + 86400

            # Get all symbols
            symbols = pd.read_sql("SELECT DISTINCT symbol FROM SymbolConfigs", conn)['symbol'].tolist()

            for symbol in symbols:
                # Trades for this symbol
                df_trades = pd.read_sql("""
                    SELECT * FROM Trades
                    WHERE symbol = ? AND close_time >= ? AND close_time < ?
                    AND close_time IS NOT NULL AND close_time > 0
                """, conn, params=(symbol, start_ts, end_ts))

                # Signals for this symbol
                df_signals = pd.read_sql("""
                    SELECT * FROM Signals
                    WHERE symbol = ? AND time >= ? AND time < ?
                """, conn, params=(symbol, start_ts, end_ts))

                if df_trades.empty:
                    continue

                # Calculate metrics
                total_trades = len(df_trades)
                wins = (df_trades['profit'] > 0).sum()
                losses = total_trades - wins
                win_rate = (wins / total_trades * 100) if total_trades > 0 else 0

                total_pnl = df_trades['profit'].sum()
                avg_pnl = total_pnl / total_trades if total_trades > 0 else 0
                largest_win = df_trades['profit'].max()
                largest_loss = df_trades['profit'].min()

                total_wins_amt = df_trades[df_trades['profit'] > 0]['profit'].sum()
                total_losses_amt = abs(df_trades[df_trades['profit'] <= 0]['profit'].sum())
                profit_factor = (total_wins_amt / total_losses_amt) if total_losses_amt > 0 else 0

                # Quality metrics
                avg_confluence = df_trades['confluence_score'].mean()
                avg_mfe = df_trades['mfe'].mean()
                avg_mae = df_trades['mae'].mean()

                # Duration
                df_trades['duration'] = (df_trades['close_time'] - df_trades['entry_time']) / 60
                avg_duration = df_trades['duration'].mean()

                # Signals
                total_signals = len(df_signals)
                signals_allowed = (df_signals['allowed'] == 1).sum() if total_signals > 0 else 0
                rejection_rate = ((total_signals - signals_allowed) / total_signals * 100) if total_signals > 0 else 0

                # Insert
                cursor.execute("""
                    INSERT OR REPLACE INTO SymbolPerformance (
                        symbol, date, total_trades, wins, losses, win_rate,
                        total_pnl, avg_pnl_per_trade, largest_win, largest_loss,
                        profit_factor, avg_confluence_score, avg_mfe, avg_mae,
                        avg_duration_minutes, total_signals_generated, total_signals_allowed,
                        rejection_rate, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    symbol, date, total_trades, wins, losses, win_rate,
                    total_pnl, avg_pnl, largest_win, largest_loss,
                    profit_factor, avg_confluence, avg_mfe, avg_mae,
                    avg_duration, total_signals, signals_allowed, rejection_rate,
                    int(datetime.now().timestamp())
                ))

            conn.commit()
            print(f"✅ SymbolPerformance populated for {date}: {len(symbols)} symbols")

        except Exception as e:
            print(f"❌ Error populating SymbolPerformance: {e}")
            conn.rollback()
        finally:
            conn.close()

    def populate_regime_performance(self, period: str):
        """Calculate regime performance for a period (date or week)"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            # Determine if period is daily or weekly
            if '-W' in period:  # Weekly: 'YYYY-Www'
                # Parse ISO week
                year, week = period.split('-W')
                date_obj = datetime.strptime(f'{year}-W{week}-1', '%Y-W%W-%w')
                start_ts = int(date_obj.timestamp())
                end_ts = start_ts + (7 * 86400)
            else:  # Daily: 'YYYY-MM-DD'
                date_obj = datetime.strptime(period, '%Y-%m-%d')
                start_ts = int(date_obj.timestamp())
                end_ts = start_ts + 86400

            symbols = pd.read_sql("SELECT DISTINCT symbol FROM SymbolConfigs", conn)['symbol'].tolist()
            regimes = ['TREND', 'RANGE', 'VOLATILE', 'UNKNOWN']

            for symbol in symbols:
                for regime in regimes:
                    df_trades = pd.read_sql("""
                        SELECT * FROM Trades
                        WHERE symbol = ? AND regime = ?
                        AND close_time >= ? AND close_time < ?
                        AND close_time IS NOT NULL AND close_time > 0
                    """, conn, params=(symbol, regime, start_ts, end_ts))

                    if df_trades.empty:
                        continue

                    total_trades = len(df_trades)
                    wins = (df_trades['profit'] > 0).sum()
                    losses = total_trades - wins
                    win_rate = (wins / total_trades * 100) if total_trades > 0 else 0

                    total_pnl = df_trades['profit'].sum()
                    avg_pnl = total_pnl / total_trades

                    total_wins_amt = df_trades[df_trades['profit'] > 0]['profit'].sum()
                    total_losses_amt = abs(df_trades[df_trades['profit'] <= 0]['profit'].sum())
                    profit_factor = (total_wins_amt / total_losses_amt) if total_losses_amt > 0 else 0

                    avg_confluence = df_trades['confluence_score'].mean()
                    avg_mfe = df_trades['mfe'].mean()
                    avg_mae = df_trades['mae'].mean()

                    cursor.execute("""
                        INSERT OR REPLACE INTO RegimePerformance (
                            symbol, regime, period, total_trades, wins, losses,
                            win_rate, total_pnl, avg_pnl_per_trade, profit_factor,
                            avg_confluence_score, avg_mfe, avg_mae, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        symbol, regime, period, total_trades, wins, losses,
                        win_rate, total_pnl, avg_pnl, profit_factor,
                        avg_confluence, avg_mfe, avg_mae,
                        int(datetime.now().timestamp())
                    ))

            conn.commit()
            print(f"✅ RegimePerformance populated for {period}")

        except Exception as e:
            print(f"❌ Error populating RegimePerformance: {e}")
            conn.rollback()
        finally:
            conn.close()

    def populate_killzone_performance(self, period: str):
        """Calculate killzone performance"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            # Parse period
            if '-W' in period:
                year, week = period.split('-W')
                date_obj = datetime.strptime(f'{year}-W{week}-1', '%Y-W%W-%w')
                start_ts = int(date_obj.timestamp())
                end_ts = start_ts + (7 * 86400)
            else:
                date_obj = datetime.strptime(period, '%Y-%m-%d')
                start_ts = int(date_obj.timestamp())
                end_ts = start_ts + 86400

            symbols = pd.read_sql("SELECT DISTINCT symbol FROM SymbolConfigs", conn)['symbol'].tolist()
            killzones = ['Asian', 'London Open', 'NY', 'London Close', 'NONE']

            for symbol in symbols:
                for killzone in killzones:
                    df_trades = pd.read_sql("""
                        SELECT * FROM Trades
                        WHERE symbol = ? AND killzone = ?
                        AND close_time >= ? AND close_time < ?
                        AND close_time IS NOT NULL AND close_time > 0
                    """, conn, params=(symbol, killzone, start_ts, end_ts))

                    if df_trades.empty:
                        continue

                    total_trades = len(df_trades)
                    wins = (df_trades['profit'] > 0).sum()
                    losses = total_trades - wins
                    win_rate = (wins / total_trades * 100) if total_trades > 0 else 0

                    total_pnl = df_trades['profit'].sum()
                    avg_pnl = total_pnl / total_trades

                    total_wins_amt = df_trades[df_trades['profit'] > 0]['profit'].sum()
                    total_losses_amt = abs(df_trades[df_trades['profit'] <= 0]['profit'].sum())
                    profit_factor = (total_wins_amt / total_losses_amt) if total_losses_amt > 0 else 0

                    avg_confluence = df_trades['confluence_score'].mean()

                    cursor.execute("""
                        INSERT OR REPLACE INTO KillzonePerformance (
                            symbol, killzone, period, total_trades, wins, losses,
                            win_rate, total_pnl, avg_pnl_per_trade, profit_factor,
                            avg_confluence_score, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        symbol, killzone, period, total_trades, wins, losses,
                        win_rate, total_pnl, avg_pnl, profit_factor,
                        avg_confluence, int(datetime.now().timestamp())
                    ))

            conn.commit()
            print(f"✅ KillzonePerformance populated for {period}")

        except Exception as e:
            print(f"❌ Error populating KillzonePerformance: {e}")
            conn.rollback()
        finally:
            conn.close()

    # =========================================================================
    # PHASE 2: ADVANCED ANALYTICS
    # =========================================================================

    def calculate_correlation_matrix(self, period_days: int = 30):
        """Calculate pairwise correlations between symbols"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            # Get all symbols
            symbols = pd.read_sql("SELECT DISTINCT symbol FROM SymbolConfigs", conn)['symbol'].tolist()

            # Get recent trades
            lookback_ts = int((datetime.now() - timedelta(days=period_days)).timestamp())

            # Build returns matrix
            returns_dict = {}
            for symbol in symbols:
                df = pd.read_sql("""
                    SELECT close_time, profit FROM Trades
                    WHERE symbol = ? AND close_time > ?
                    AND close_time IS NOT NULL AND close_time > 0
                    ORDER BY close_time
                """, conn, params=(symbol, lookback_ts))

                if len(df) > 5:  # Need minimum trades
                    returns_dict[symbol] = df.set_index('close_time')['profit']

            if len(returns_dict) < 2:
                print("Not enough symbols with trades for correlation")
                return

            # Align data and calculate correlations
            timestamp_now = int(datetime.now().timestamp())

            for i, symbol_a in enumerate(symbols):
                for symbol_b in symbols[i+1:]:
                    if symbol_a not in returns_dict or symbol_b not in returns_dict:
                        continue

                    # Align time series
                    merged = pd.concat([returns_dict[symbol_a], returns_dict[symbol_b]], axis=1, join='inner')
                    merged.columns = ['a', 'b']

                    if len(merged) < 5:
                        continue

                    # Calculate Pearson correlation
                    corr, p_value = stats.pearsonr(merged['a'], merged['b'])

                    cursor.execute("""
                        INSERT INTO CorrelationMatrix (
                            timestamp, period_days, symbol_a, symbol_b,
                            correlation, p_value, sample_size, calculation_method
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        timestamp_now, period_days, symbol_a, symbol_b,
                        corr, p_value, len(merged), 'pearson'
                    ))

            conn.commit()
            print(f"✅ CorrelationMatrix calculated for {period_days} days")

        except Exception as e:
            print(f"❌ Error calculating CorrelationMatrix: {e}")
            conn.rollback()
        finally:
            conn.close()

    def track_drawdowns(self):
        """Track drawdown periods"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            # Get all trades ordered by time
            df_trades = pd.read_sql("""
                SELECT close_time, profit FROM Trades
                WHERE close_time IS NOT NULL AND close_time > 0
                ORDER BY close_time
            """, conn)

            if df_trades.empty:
                return

            # Calculate cumulative balance
            df_trades['cumulative'] = df_trades['profit'].cumsum()
            df_trades['peak'] = df_trades['cumulative'].cummax()
            df_trades['drawdown'] = df_trades['cumulative'] - df_trades['peak']
            df_trades['drawdown_pct'] = (df_trades['drawdown'] / df_trades['peak'] * 100).fillna(0)

            # Find drawdown periods (when DD starts and ends)
            in_dd = False
            dd_start_idx = None

            for idx, row in df_trades.iterrows():
                if row['drawdown'] < 0 and not in_dd:
                    # Drawdown started
                    in_dd = True
                    dd_start_idx = idx
                    peak_balance = row['peak']

                elif row['drawdown'] == 0 and in_dd:
                    # Drawdown recovered
                    in_dd = False
                    dd_segment = df_trades.loc[dd_start_idx:idx]

                    trough_balance = dd_segment['cumulative'].min()
                    dd_amount = peak_balance - trough_balance
                    dd_pct = (dd_amount / peak_balance * 100) if peak_balance > 0 else 0

                    start_time = int(dd_segment.iloc[0]['close_time'])
                    end_time = int(dd_segment.iloc[-1]['close_time'])
                    duration_days = (end_time - start_time) / 86400

                    cursor.execute("""
                        INSERT INTO DrawdownHistory (
                            start_time, end_time, peak_balance, trough_balance,
                            drawdown_amount, drawdown_pct, duration_days,
                            trades_during_dd, recovery_time, status
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        start_time, end_time, peak_balance, trough_balance,
                        dd_amount, dd_pct, duration_days,
                        len(dd_segment), end_time, 'recovered'
                    ))

            # Check if currently in drawdown
            if in_dd:
                dd_segment = df_trades.loc[dd_start_idx:]
                trough_balance = dd_segment['cumulative'].min()
                dd_amount = peak_balance - trough_balance
                dd_pct = (dd_amount / peak_balance * 100) if peak_balance > 0 else 0
                start_time = int(dd_segment.iloc[0]['close_time'])

                cursor.execute("""
                    INSERT OR REPLACE INTO DrawdownHistory (
                        start_time, peak_balance, trough_balance,
                        drawdown_amount, drawdown_pct, trades_during_dd, status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    start_time, peak_balance, trough_balance,
                    dd_amount, dd_pct, len(dd_segment), 'ongoing'
                ))

            conn.commit()
            print(f"✅ DrawdownHistory updated")

        except Exception as e:
            print(f"❌ Error tracking drawdowns: {e}")
            conn.rollback()
        finally:
            conn.close()

    # =========================================================================
    # PHASE 3: PORTFOLIO ANALYTICS
    # =========================================================================

    def populate_portfolio_metrics(self, date: str):
        """Calculate portfolio-level metrics"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            date_obj = datetime.strptime(date, '%Y-%m-%d')
            start_ts = int(date_obj.timestamp())
            end_ts = start_ts + 86400

            # Get all trades for the day
            df_trades = pd.read_sql("""
                SELECT * FROM Trades
                WHERE close_time >= ? AND close_time < ?
                AND close_time IS NOT NULL AND close_time > 0
            """, conn, params=(start_ts, end_ts))

            if df_trades.empty:
                return

            # Portfolio P&L
            total_pnl = df_trades['profit'].sum()

            # Diversification
            symbol_pnls = df_trades.groupby('symbol')['profit'].sum()
            total_symbols_traded = len(symbol_pnls)
            concentration_risk = (symbol_pnls.abs().max() / symbol_pnls.abs().sum() * 100) if len(symbol_pnls) > 0 else 0

            # Avg confluence
            avg_confluence = df_trades['confluence_score'].mean()

            # Efficiency
            total_commission = df_trades['commission'].sum()
            total_swap = df_trades['swap'].sum()

            cursor.execute("""
                INSERT OR REPLACE INTO PortfolioMetrics (
                    date, total_pnl, total_symbols_traded, concentration_risk,
                    avg_confluence_across_trades, total_commission, total_swap,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                date, total_pnl, total_symbols_traded, concentration_risk,
                avg_confluence, total_commission, total_swap,
                int(datetime.now().timestamp())
            ))

            conn.commit()
            print(f"✅ PortfolioMetrics populated for {date}")

        except Exception as e:
            print(f"❌ Error populating PortfolioMetrics: {e}")
            conn.rollback()
        finally:
            conn.close()

    # =========================================================================
    # HELPER FUNCTIONS
    # =========================================================================

    def _get_cumulative_pnl(self, until_timestamp: int, conn) -> float:
        """Get cumulative P&L up to a timestamp"""
        result = pd.read_sql("""
            SELECT SUM(profit) as cumulative
            FROM Trades
            WHERE close_time <= ? AND close_time IS NOT NULL
        """, conn, params=(until_timestamp,))

        return result['cumulative'].iloc[0] if not result.empty else 0.0

    def run_daily_aggregation(self, date: str = None):
        """Run all daily aggregations for a date"""
        if date is None:
            # Yesterday
            date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

        print(f"\n🔄 Running daily aggregation for {date}...")
        self.populate_daily_performance(date)
        self.populate_symbol_performance(date)
        self.populate_regime_performance(date)
        self.populate_killzone_performance(date)
        self.populate_portfolio_metrics(date)
        print(f"✅ Daily aggregation complete for {date}\n")

    def run_weekly_aggregation(self, week: str = None):
        """Run all weekly aggregations"""
        if week is None:
            # Last week
            date = datetime.now() - timedelta(days=7)
            week = date.strftime('%Y-W%U')

        print(f"\n🔄 Running weekly aggregation for {week}...")
        self.populate_regime_performance(week)
        self.populate_killzone_performance(week)
        self.calculate_correlation_matrix(30)
        print(f"✅ Weekly aggregation complete for {week}\n")

    def backfill_analytics(self, days: int = 30):
        """Backfill analytics for the last N days"""
        print(f"\n🔄 Backfilling analytics for last {days} days...")

        for i in range(days):
            date = (datetime.now() - timedelta(days=i+1)).strftime('%Y-%m-%d')
            try:
                self.run_daily_aggregation(date)
            except Exception as e:
                print(f"❌ Error backfilling {date}: {e}")

        print(f"✅ Backfill complete\n")


if __name__ == "__main__":
    # Test the analytics engine
    import os
    db_path = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")

    engine = AnalyticsEngine(db_path)

    print("=" * 70)
    print("ANALYTICS ENGINE - TEST RUN")
    print("=" * 70)

    # Backfill last 7 days
    engine.backfill_analytics(days=7)
