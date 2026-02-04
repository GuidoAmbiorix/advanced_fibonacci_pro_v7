"""
Database Reader for MT5 Portfolio Governor
Provides read-only access to the SQLite database written by MT5
"""

import sqlite3
import os
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Any
import pandas as pd
from contextlib import contextmanager


class DatabaseReader:
    """Read-only access to MT5 Portfolio Governor database"""

    def __init__(self, db_path: Optional[str] = None):
        """
        Initialize database reader

        Args:
            db_path: Path to SQLite database file. If None, uses environment variable DB_PATH
        """
        self.db_path = db_path or os.environ.get(
            'DB_PATH',
            '/mt5_data/.wine/drive_c/users/Public/Documents/MetaQuotes/Terminal/Common/Files/PortfolioGovernor.sqlite'
        )
        self._test_connection()

    def _test_connection(self):
        """Test database connection on initialization"""
        try:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
                tables = cursor.fetchall()
                print(f"Connected to database. Found tables: {[t[0] for t in tables]}")
        except Exception as e:
            print(f"Warning: Could not connect to database at {self.db_path}: {e}")

    @contextmanager
    def _get_connection(self):
        """Context manager for database connections with read-only mode"""
        conn = None
        try:
            # Open in read-only mode to avoid locking issues
            conn = sqlite3.connect(f'file:{self.db_path}?mode=ro', uri=True, timeout=5.0)
            conn.row_factory = sqlite3.Row
            yield conn
        except sqlite3.OperationalError as e:
            if "locked" in str(e).lower():
                print("Database is locked by MT5, retrying...")
                # Retry once after brief delay
                import time
                time.sleep(0.5)
                conn = sqlite3.connect(f'file:{self.db_path}?mode=ro', uri=True, timeout=5.0)
                conn.row_factory = sqlite3.Row
                yield conn
            else:
                raise
        finally:
            if conn:
                conn.close()

    def get_account_summary(self) -> Dict[str, Any]:
        """
        Get current account summary from GovernorState table

        Returns:
            Dict with balance, equity, margin_used, margin_free, last_update
        """
        try:
            with self._get_connection() as conn:
                cursor = conn.cursor()

                # Get account state values
                state_keys = ['balance', 'equity', 'margin_used', 'margin_free']
                summary = {}

                for key in state_keys:
                    cursor.execute(
                        "SELECT value_num, updated_at FROM GovernorState WHERE key = ?",
                        (key,)
                    )
                    row = cursor.fetchone()
                    if row:
                        summary[key] = row['value_num']
                        summary['last_update'] = row['updated_at']
                    else:
                        summary[key] = 0.0

                # Calculate floating P/L from open positions
                cursor.execute("""
                    SELECT SUM(profit) as floating_pl
                    FROM Trades
                    WHERE close_time IS NULL OR close_time = 0
                """)
                row = cursor.fetchone()
                summary['floating_pl'] = row['floating_pl'] if row and row['floating_pl'] else 0.0

                # If we don't have equity from state, calculate it
                if summary.get('equity', 0) == 0:
                    summary['equity'] = summary.get('balance', 0) + summary['floating_pl']

                return summary

        except Exception as e:
            print(f"Error getting account summary: {e}")
            return {
                'balance': 0.0,
                'equity': 0.0,
                'margin_used': 0.0,
                'margin_free': 0.0,
                'floating_pl': 0.0,
                'last_update': None
            }

    def get_open_positions(self) -> pd.DataFrame:
        """
        Get all open positions

        Returns:
            DataFrame with open position details
        """
        try:
            with self._get_connection() as conn:
                query = """
                    SELECT
                        ticket,
                        symbol,
                        type,
                        lots,
                        entry_price,
                        sl,
                        tp,
                        entry_time,
                        profit,
                        commission,
                        swap,
                        strategy,
                        confluence_score,
                        regime,
                        killzone,
                        mfe,
                        mae
                    FROM Trades
                    WHERE close_time IS NULL OR close_time = 0
                    ORDER BY entry_time DESC
                """
                df = pd.read_sql_query(query, conn)

                # Convert entry_time to datetime
                if not df.empty and 'entry_time' in df.columns:
                    df['entry_time'] = pd.to_datetime(df['entry_time'], unit='s', errors='coerce')

                return df

        except Exception as e:
            print(f"Error getting open positions: {e}")
            return pd.DataFrame()

    def get_trade_history(self, days: int = 7) -> pd.DataFrame:
        """
        Get closed trades from the last N days

        Args:
            days: Number of days to look back (0 = all history)

        Returns:
            DataFrame with trade history
        """
        try:
            with self._get_connection() as conn:
                if days > 0:
                    cutoff_time = int((datetime.now() - timedelta(days=days)).timestamp())
                    query = f"""
                        SELECT
                            ticket,
                            symbol,
                            type,
                            lots,
                            entry_price,
                            close_price,
                            entry_time,
                            close_time,
                            profit,
                            commission,
                            swap,
                            strategy,
                            confluence_score,
                            regime,
                            killzone,
                            exit_reason,
                            mfe,
                            mae
                        FROM Trades
                        WHERE close_time IS NOT NULL AND close_time > 0 AND close_time >= {cutoff_time}
                        ORDER BY close_time DESC
                    """
                else:
                    query = """
                        SELECT
                            ticket,
                            symbol,
                            type,
                            lots,
                            entry_price,
                            close_price,
                            entry_time,
                            close_time,
                            profit,
                            commission,
                            swap,
                            strategy,
                            confluence_score,
                            regime,
                            killzone,
                            exit_reason,
                            mfe,
                            mae
                        FROM Trades
                        WHERE close_time IS NOT NULL AND close_time > 0
                        ORDER BY close_time DESC
                    """

                df = pd.read_sql_query(query, conn)

                # Convert timestamps to datetime
                if not df.empty:
                    if 'entry_time' in df.columns:
                        df['entry_time'] = pd.to_datetime(df['entry_time'], unit='s', errors='coerce')
                    if 'close_time' in df.columns:
                        df['close_time'] = pd.to_datetime(df['close_time'], unit='s', errors='coerce')

                return df

        except Exception as e:
            print(f"Error getting trade history: {e}")
            return pd.DataFrame()

    def get_symbol_metrics(self) -> pd.DataFrame:
        """
        Get performance metrics per symbol

        Returns:
            DataFrame with symbol-level statistics
        """
        try:
            with self._get_connection() as conn:
                query = """
                    SELECT
                        symbol,
                        COUNT(*) as total_trades,
                        SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as wins,
                        SUM(CASE WHEN profit <= 0 THEN 1 ELSE 0 END) as losses,
                        SUM(profit) as total_profit,
                        AVG(profit) as avg_profit,
                        MAX(profit) as best_trade,
                        MIN(profit) as worst_trade,
                        AVG(CASE WHEN profit > 0 THEN profit END) as avg_win,
                        AVG(CASE WHEN profit <= 0 THEN profit END) as avg_loss
                    FROM Trades
                    WHERE close_time IS NOT NULL AND close_time > 0
                    GROUP BY symbol
                    ORDER BY total_profit DESC
                """
                df = pd.read_sql_query(query, conn)

                # Calculate win rate and profit factor
                if not df.empty:
                    df['win_rate'] = (df['wins'] / df['total_trades'] * 100).round(2)

                    # Profit factor = gross profit / gross loss
                    gross_wins = df['wins'] * df['avg_win'].fillna(0)
                    gross_losses = df['losses'] * df['avg_loss'].fillna(0).abs()
                    df['profit_factor'] = (gross_wins / gross_losses.replace(0, 1)).round(2)

                return df

        except Exception as e:
            print(f"Error getting symbol metrics: {e}")
            return pd.DataFrame()

    def get_recent_signals(self, hours: int = 24) -> pd.DataFrame:
        """
        Get recent trading signals

        Args:
            hours: Number of hours to look back

        Returns:
            DataFrame with recent signals
        """
        try:
            with self._get_connection() as conn:
                cutoff_time = int((datetime.now() - timedelta(hours=hours)).timestamp())
                query = f"""
                    SELECT
                        time,
                        symbol,
                        direction,
                        score,
                        rank,
                        allowed,
                        smc_score,
                        fib_score,
                        rejection_reason
                    FROM Signals
                    WHERE time >= {cutoff_time}
                    ORDER BY time DESC
                    LIMIT 100
                """
                df = pd.read_sql_query(query, conn)

                # Convert time to datetime
                if not df.empty and 'time' in df.columns:
                    df['time'] = pd.to_datetime(df['time'], unit='s', errors='coerce')

                return df

        except Exception as e:
            print(f"Error getting recent signals: {e}")
            return pd.DataFrame()

    def get_daily_pl(self) -> float:
        """
        Calculate today's profit/loss

        Returns:
            Total P/L for today
        """
        try:
            with self._get_connection() as conn:
                today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
                cutoff_time = int(today_start.timestamp())

                cursor = conn.cursor()
                cursor.execute("""
                    SELECT SUM(profit) as daily_pl
                    FROM Trades
                    WHERE close_time >= ?
                """, (cutoff_time,))

                row = cursor.fetchone()
                return row['daily_pl'] if row and row['daily_pl'] else 0.0

        except Exception as e:
            print(f"Error getting daily P/L: {e}")
            return 0.0

    def get_total_pl(self) -> float:
        """
        Calculate total lifetime profit/loss

        Returns:
            Total P/L across all closed trades
        """
        try:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT SUM(profit) as total_pl
                    FROM Trades
                    WHERE close_time IS NOT NULL AND close_time > 0
                """)

                row = cursor.fetchone()
                return row['total_pl'] if row and row['total_pl'] else 0.0

        except Exception as e:
            print(f"Error getting total P/L: {e}")
            return 0.0

    def get_equity_curve(self, days: int = 30) -> pd.DataFrame:
        """
        Get equity curve data for charting

        Args:
            days: Number of days to include

        Returns:
            DataFrame with timestamp and cumulative profit
        """
        try:
            with self._get_connection() as conn:
                cutoff_time = int((datetime.now() - timedelta(days=days)).timestamp())
                query = f"""
                    SELECT
                        close_time as time,
                        profit
                    FROM Trades
                    WHERE close_time IS NOT NULL AND close_time > 0 AND close_time >= {cutoff_time}
                    ORDER BY close_time ASC
                """
                df = pd.read_sql_query(query, conn)

                if not df.empty:
                    df['time'] = pd.to_datetime(df['time'], unit='s', errors='coerce')
                    df['cumulative_pl'] = df['profit'].cumsum()

                return df

        except Exception as e:
            print(f"Error getting equity curve: {e}")
            return pd.DataFrame()
