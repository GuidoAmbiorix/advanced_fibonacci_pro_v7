import json
import os
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
import pandas as pd
import numpy as np
import psycopg2
import psycopg2.extras
from psycopg2 import pool


def convert_numpy_types(value):
    """Convert NumPy types to native Python types."""
    if isinstance(value, (np.integer, np.int64, np.int32)):
        return int(value)
    elif isinstance(value, (np.floating, np.float64, np.float32)):
        return float(value)
    elif isinstance(value, np.bool_):
        return bool(value)
    elif isinstance(value, np.ndarray):
        return value.tolist()
    return value


class PostgresConnection:
    """Context manager for PostgreSQL connections with RealDictCursor."""

    def __init__(self, conn, release_func):
        self._conn = conn
        self._release_func = release_func
        self._cursor = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self._cursor:
            self._cursor.close()
        if exc_type:
            self._conn.rollback()
        else:
            self._conn.commit()
        self._release_func(self._conn)

    def cursor(self):
        self._cursor = self._conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        return self._cursor

    def execute(self, query, params=None):
        cursor = self.cursor()
        cursor.execute(query, params or ())
        return cursor

    def executemany(self, query, params_list):
        cursor = self.cursor()
        psycopg2.extras.execute_batch(cursor, query, params_list)
        return cursor

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()


class DatabaseManager:
    """Manages all database operations for the CV Trading Agent."""

    def __init__(self, db_url: str = None):
        """
        Initialize database manager with PostgreSQL.

        Args:
            db_url: PostgreSQL connection URL (defaults to DATABASE_URL env var)
        """
        self.db_url = db_url or os.environ.get('DATABASE_URL')
        if not self.db_url:
            raise ValueError("DATABASE_URL environment variable is required")

        self._init_postgres_pool()
        self._ensure_db_exists()

    def _init_postgres_pool(self):
        """Initialize PostgreSQL connection pool."""
        try:
            self._pg_pool = psycopg2.pool.ThreadedConnectionPool(
                minconn=2,
                maxconn=10,
                dsn=self.db_url
            )
            print(f"[OK] PostgreSQL connection pool initialized")
        except Exception as e:
            raise ConnectionError(f"Failed to initialize PostgreSQL pool: {e}")

    def _ensure_db_exists(self):
        """Verify PostgreSQL connection works."""
        try:
            conn = self._get_pg_connection()
            self._release_pg_connection(conn)
            print("[OK] PostgreSQL database connection verified")
        except Exception as e:
            raise ConnectionError(f"PostgreSQL connection failed: {e}")

    def _get_pg_connection(self):
        """Get a PostgreSQL connection from the pool."""
        if not self._pg_pool:
            raise ConnectionError("PostgreSQL pool not initialized")
        return self._pg_pool.getconn()

    def _release_pg_connection(self, conn):
        """Return a PostgreSQL connection to the pool."""
        if self._pg_pool and conn:
            self._pg_pool.putconn(conn)

    def close(self):
        """Close all connections and cleanup resources."""
        if self._pg_pool:
            self._pg_pool.closeall()
            print("[OK] PostgreSQL connection pool closed")

    def __del__(self):
        """Cleanup on deletion."""
        try:
            self.close()
        except:
            pass

    def get_connection(self):
        """
        Get PostgreSQL connection from pool.

        Returns:
            Connection context manager with RealDictCursor
        """
        conn = self._get_pg_connection()
        return PostgresConnection(conn, self._release_pg_connection)

    # ==================== Market Data ====================

    def insert_market_data(self, symbol: str, timeframe: str, bars: pd.DataFrame):
        """
        Insert market data bars using bulk insert for better performance.

        Args:
            symbol: Trading symbol
            timeframe: Timeframe (e.g., 'H1', 'M15')
            bars: DataFrame with columns: timestamp, open, high, low, close, tick_volume, spread, real_volume
        """
        if bars.empty:
            return

        with self.get_connection() as conn:
            try:
                # Prepare data for bulk insert
                data = []
                for _, row in bars.iterrows():
                    # Convert timestamp to string
                    timestamp_str = row['timestamp'].isoformat() if hasattr(row['timestamp'], 'isoformat') else str(row['timestamp'])

                    data.append((
                        symbol, timeframe, timestamp_str, row['open'], row['high'],
                        row['low'], row['close'], row.get('tick_volume'),
                        row.get('spread'), row.get('real_volume')
                    ))

                query = """
                    INSERT INTO market_data
                    (symbol, timeframe, timestamp, open, high, low, close, tick_volume, spread, real_volume)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (symbol, timeframe, timestamp)
                    DO UPDATE SET
                        open = EXCLUDED.open,
                        high = EXCLUDED.high,
                        low = EXCLUDED.low,
                        close = EXCLUDED.close,
                        tick_volume = EXCLUDED.tick_volume,
                        spread = EXCLUDED.spread,
                        real_volume = EXCLUDED.real_volume
                """

                # Use executemany for bulk insert (much faster and reduces lock time)
                conn.executemany(query, data)

                conn.commit()
            except Exception as e:
                conn.rollback()
                raise Exception(f"Failed to insert market data for {symbol} {timeframe}: {e}")

    def get_market_data(self, symbol: str, timeframe: str, limit: int = 1000) -> pd.DataFrame:
        """
        Retrieve market data.

        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            limit: Number of bars to retrieve

        Returns:
            DataFrame with market data
        """
        query = """
            SELECT timestamp, open, high, low, close, tick_volume, spread, real_volume
            FROM market_data
            WHERE symbol = %s AND timeframe = %s
            ORDER BY timestamp DESC
            LIMIT %s
        """
        params = (symbol, timeframe, limit)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            rows = cursor.fetchall()
            df = pd.DataFrame(rows, columns=['timestamp', 'open', 'high', 'low', 'close', 'tick_volume', 'spread', 'real_volume'])

            if not df.empty:
                df['timestamp'] = pd.to_datetime(df['timestamp'])
                df = df.sort_values('timestamp').reset_index(drop=True)
            return df

    # ==================== Models ====================

    def insert_model(self, name: str, version: str, model_type: str,
                    hyperparameters: Dict = None, file_path: str = None,
                    training_accuracy: float = None, validation_accuracy: float = None,
                    parameters: Dict = None) -> int:
        """Insert new model record."""
        # Support both 'hyperparameters' and 'parameters' for compatibility
        params = hyperparameters or parameters or {}

        query = """
            INSERT INTO models (name, version, model_type, hyperparameters, file_path,
                               training_accuracy, validation_accuracy)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """
        # Convert dict to JSON for JSONB column
        query_params = (name, version, model_type, psycopg2.extras.Json(params), file_path,
                       training_accuracy, validation_accuracy)

        with self.get_connection() as conn:
            cursor = conn.execute(query, query_params)
            result = cursor.fetchone()
            conn.commit()
            return result['id']

    def save_model(self, **kwargs):
        """Alias for insert_model for compatibility."""
        return self.insert_model(**kwargs)

    def set_active_model(self, model_id: int):
        """Set a model as active (deactivate all others)."""
        with self.get_connection() as conn:
            conn.execute("UPDATE models SET is_active = FALSE")
            conn.execute("UPDATE models SET is_active = TRUE WHERE id = %s", (model_id,))
            conn.commit()

    def get_model(self, model_id: int) -> Optional[Dict]:
        """Get model by ID."""
        query = "SELECT * FROM models WHERE id = %s"
        params = (model_id,)

        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    def get_active_model(self) -> Optional[Dict]:
        """Get the currently active model."""
        query = "SELECT * FROM models WHERE is_active = TRUE LIMIT 1"
        params = ()

        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    # ==================== Predictions ====================

    def insert_prediction(self, model_id: int, symbol: str, prediction_direction: str,
                         confidence: float, window_start: datetime, window_end: datetime,
                         prediction_horizon: int) -> int:
        """Insert prediction record."""
        # Convert datetime objects to ISO format strings
        timestamp_str = datetime.now().isoformat()
        window_start_str = window_start.isoformat() if hasattr(window_start, 'isoformat') else str(window_start)
        window_end_str = window_end.isoformat() if hasattr(window_end, 'isoformat') else str(window_end)

        # Convert NumPy types to Python native types
        confidence = convert_numpy_types(confidence)
        prediction_horizon = convert_numpy_types(prediction_horizon)

        query = """
            INSERT INTO predictions (model_id, symbol, timestamp, prediction_direction,
                                    confidence, window_start, window_end, prediction_horizon)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """
        params = (model_id, symbol, timestamp_str, prediction_direction, confidence,
                 window_start_str, window_end_str, prediction_horizon)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            result = cursor.fetchone()
            conn.commit()
            return result['id']

    def get_latest_prediction(self, symbol: str, model_id: int = None) -> Optional[Dict]:
        """Get the most recent prediction for a symbol, optionally filtered by model."""
        with self.get_connection() as conn:
            if model_id:
                query = """
                    SELECT * FROM predictions
                    WHERE symbol = %s AND model_id = %s
                    ORDER BY timestamp DESC
                    LIMIT 1
                """
                params = (symbol, model_id)
            else:
                query = """
                    SELECT * FROM predictions
                    WHERE symbol = %s
                    ORDER BY timestamp DESC
                    LIMIT 1
                """
                params = (symbol,)

            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    # ==================== Positions ====================

    def insert_position(self, mt5_ticket: int, symbol: str, position_type: str,
                       volume: float, open_price: float, open_time: datetime,
                       stop_loss: float = None, take_profit: float = None,
                       prediction_id: int = None) -> int:
        """Insert new position."""
        # Convert NumPy types to Python native types
        volume = convert_numpy_types(volume)
        open_price = convert_numpy_types(open_price)
        stop_loss = convert_numpy_types(stop_loss) if stop_loss is not None else None
        take_profit = convert_numpy_types(take_profit) if take_profit is not None else None

        query = """
            INSERT INTO positions (mt5_ticket, symbol, position_type, volume, open_price,
                                  open_time, stop_loss, take_profit, prediction_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """
        params = (mt5_ticket, symbol, position_type, volume, open_price, open_time,
                 stop_loss, take_profit, prediction_id)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            result = cursor.fetchone()
            conn.commit()
            return result['id']

    def get_open_positions(self) -> List[Dict]:
        """Get all open positions."""
        query = "SELECT * FROM positions WHERE status = 'OPEN'"
        with self.get_connection() as conn:
            rows = conn.execute(query).fetchall()
            return [dict(row) for row in rows]

    def close_position(self, position_id: int):
        """Mark position as closed."""
        query = "UPDATE positions SET status = 'CLOSED' WHERE id = %s"
        params = (position_id,)
        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()

    # ==================== Trades ====================

    def insert_trade(self, position_id: int, mt5_ticket: int, symbol: str, trade_type: str,
                    volume: float, open_price: float, close_price: float,
                    open_time: datetime, close_time: datetime, profit: float,
                    commission: float = 0, swap: float = 0, prediction_id: int = None,
                    entry_reason: str = None, exit_reason: str = None) -> int:
        """Insert completed trade."""
        # Convert NumPy types to Python native types
        volume = convert_numpy_types(volume)
        open_price = convert_numpy_types(open_price)
        close_price = convert_numpy_types(close_price)
        profit = convert_numpy_types(profit)
        commission = convert_numpy_types(commission)
        swap = convert_numpy_types(swap)

        query = """
            INSERT INTO trades (position_id, mt5_ticket, symbol, trade_type, volume,
                               open_price, close_price, open_time, close_time, profit,
                               commission, swap, prediction_id, entry_reason, exit_reason)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """
        params = (position_id, mt5_ticket, symbol, trade_type, volume, open_price, close_price,
                 open_time, close_time, profit, commission, swap, prediction_id,
                 entry_reason, exit_reason)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            result = cursor.fetchone()
            conn.commit()
            return result['id']

    def get_trades(self, limit: int = 100) -> List[Dict]:
        """Get recent trades."""
        query = """
            SELECT * FROM trades
            ORDER BY close_time DESC
            LIMIT %s
        """
        params = (limit,)
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def get_daily_pnl(self) -> float:
        """Get today's total P&L."""
        with self.get_connection() as conn:
            query = """
                SELECT COALESCE(SUM(profit + commission + swap), 0) as daily_pnl
                FROM trades
                WHERE DATE(close_time) = CURRENT_DATE
            """
            row = conn.execute(query).fetchone()
            return row['daily_pnl'] if row else 0.0

    # ==================== Configuration ====================

    def get_config(self, key: str, default: str = None) -> Optional[str]:
        """Get configuration value with optional default."""
        query = "SELECT value FROM trading_config WHERE key = %s"
        params = (key,)
        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return row['value'] if row else default

    def set_config(self, key: str, value: str):
        """Set configuration value."""
        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO trading_config (key, value, updated_at)
                VALUES (%s, %s, %s)
                ON CONFLICT (key)
                DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at
            """, (key, value, datetime.now()))
            conn.commit()

    def get_all_config(self) -> Dict[str, str]:
        """Get all configuration as dictionary."""
        with self.get_connection() as conn:
            rows = conn.execute("SELECT key, value FROM trading_config").fetchall()
            return {row['key']: row['value'] for row in rows}

    # ==================== Logging ====================

    def log(self, level: str, component: str, message: str, details: Dict = None):
        """Insert system log."""
        query = """
            INSERT INTO system_logs (level, component, message, details)
            VALUES (%s, %s, %s, %s)
        """
        # Convert dict to JSON for JSONB column
        params = (level, component, message, psycopg2.extras.Json(details) if details else None)

        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()

    def get_logs(self, level: str = None, component: str = None, limit: int = 100) -> List[Dict]:
        """Get system logs with optional filtering."""
        query = "SELECT * FROM system_logs WHERE 1=1"
        params = []

        if level:
            query += " AND level = %s"
            params.append(level)
        if component:
            query += " AND component = %s"
            params.append(component)

        query += " ORDER BY created_at DESC LIMIT %s"
        params.append(limit)

        with self.get_connection() as conn:
            rows = conn.execute(query, tuple(params)).fetchall()
            return [dict(row) for row in rows]

    # ==================== Portfolio Management ====================

    def create_portfolio(self, name: str, initial_capital: float, description: str = None) -> int:
        """Create a new portfolio."""
        query = """
            INSERT INTO portfolios (name, initial_capital, current_capital, description)
            VALUES (%s, %s, %s, %s)
            RETURNING id
        """
        params = (name, initial_capital, initial_capital, description)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            result = cursor.fetchone()
            conn.commit()
            return result['id']

    def get_portfolios(self) -> List[Dict]:
        """Get all portfolios."""
        with self.get_connection() as conn:
            rows = conn.execute("SELECT * FROM portfolios ORDER BY created_at DESC").fetchall()
            return [dict(row) for row in rows]

    def get_portfolio(self, portfolio_id: int) -> Optional[Dict]:
        """Get specific portfolio."""
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM portfolios WHERE id = %s", (portfolio_id,)).fetchone()
            return dict(row) if row else None

    def create_strategy(self, name: str, type: str, model_id: int = None, config: Dict = None) -> int:
        """Create a new trading strategy."""
        query = """
            INSERT INTO strategies (name, type, model_id, config)
            VALUES (%s, %s, %s, %s)
            RETURNING id
        """
        # Convert dict to JSON for JSONB column
        params = (name, type, model_id, psycopg2.extras.Json(config) if config else None)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            result = cursor.fetchone()
            conn.commit()
            return result['id']

    def get_strategies(self) -> List[Dict]:
        """Get all strategies."""
        with self.get_connection() as conn:
            rows = conn.execute("""
                SELECT s.*, m.name as model_name
                FROM strategies s
                LEFT JOIN models m ON s.model_id = m.id
                ORDER BY s.created_at DESC
            """).fetchall()
            return [dict(row) for row in rows]

    def set_allocation(self, portfolio_id: int, strategy_id: int, symbol: str, weight: float):
        """Set allocation for a strategy/symbol pair in a portfolio."""
        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO portfolio_allocations (portfolio_id, strategy_id, symbol, weight)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (portfolio_id, strategy_id, symbol)
                DO UPDATE SET weight = EXCLUDED.weight, updated_at = CURRENT_TIMESTAMP
            """, (portfolio_id, strategy_id, symbol, weight))
            conn.commit()

    def get_allocations(self, portfolio_id: int) -> List[Dict]:
        """Get allocations for a portfolio."""
        query = """
            SELECT a.*, s.name as strategy_name, s.type as strategy_type, s.model_id
            FROM portfolio_allocations a
            JOIN strategies s ON a.strategy_id = s.id
            WHERE a.portfolio_id = %s AND a.is_active = TRUE
            ORDER BY a.weight DESC
        """
        params = (portfolio_id,)
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def update_portfolio_performance(self, portfolio_id: int, total_equity: float, daily_pnl: float, drawdown: float):
        """Record daily portfolio performance."""
        date_str = datetime.now().date().isoformat()
        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO portfolio_performance (portfolio_id, date, total_equity, daily_pnl, drawdown)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (portfolio_id, date)
                DO UPDATE SET total_equity = EXCLUDED.total_equity,
                              daily_pnl = EXCLUDED.daily_pnl,
                              drawdown = EXCLUDED.drawdown
            """, (portfolio_id, date_str, total_equity, daily_pnl, drawdown))
            conn.commit()

    def get_portfolio_performance(self, portfolio_id: int, days: int = 30) -> List[Dict]:
        """Get performance history for a portfolio."""
        query = """
            SELECT * FROM portfolio_performance
            WHERE portfolio_id = %s
            ORDER BY date ASC
            LIMIT %s
        """
        params = (portfolio_id, days)
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    # ==================== Killzone Management ====================

    def get_killzone_windows(self, active_only: bool = True) -> List[Dict]:
        """Get all killzone windows."""
        with self.get_connection() as conn:
            query = "SELECT * FROM killzone_windows"
            if active_only:
                query += " WHERE is_active = TRUE"
            query += " ORDER BY priority DESC, start_time ASC"

            rows = conn.execute(query).fetchall()
            return [dict(row) for row in rows]

    def add_killzone_window(self, name: str, start_time: str, end_time: str,
                           days_of_week: str, timezone: str = 'America/New_York',
                           priority: str = 'medium') -> int:
        """Add a new killzone window."""
        query = """
            INSERT INTO killzone_windows (name, start_time, end_time, days_of_week, timezone, priority)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING id
        """
        params = (name, start_time, end_time, days_of_week, timezone, priority)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            result = cursor.fetchone()
            conn.commit()
            return result['id']

    def update_killzone_window(self, killzone_id: int, **kwargs):
        """Update a killzone window."""
        allowed_fields = ['name', 'start_time', 'end_time', 'days_of_week', 'timezone', 'priority', 'is_active']
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}

        if not updates:
            return

        set_clause = ', '.join([f"{k} = %s" for k in updates.keys()])
        values = list(updates.values()) + [killzone_id]

        query = f"""
            UPDATE killzone_windows
            SET {set_clause}, updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
        """
        params = tuple(values)

        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()

    def delete_killzone_window(self, killzone_id: int):
        """Delete a killzone window."""
        query = "DELETE FROM killzone_windows WHERE id = %s"
        params = (killzone_id,)
        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()

    def sync_open_positions(self, open_tickets: List[int]):
        """
        Sync open positions with MT5.
        Mark positions as closed if they are in our DB (active) but NOT in the open_tickets list.
        """
        import logging
        logger = logging.getLogger(__name__)

        with self.get_connection() as conn:
            if not open_tickets:
                # If no open positions, close ALL active positions in DB
                # First check how many will be affected
                count_query = "SELECT COUNT(*) as cnt FROM positions WHERE status = 'OPEN' AND mt5_ticket > 0"
                count = conn.execute(count_query).fetchone()['cnt']

                if count > 0:
                    logger.info(f"🔄 Syncing: Closing {count} open position(s) in DB (MT5 has 0 open)")

                query = """
                    UPDATE positions
                    SET exit_time = CURRENT_TIMESTAMP,
                        exit_price = 0,
                        profit = 0,
                        status = 'CLOSED_SYNC'
                    WHERE status = 'OPEN'
                    AND mt5_ticket > 0
                """
                conn.execute(query)
            else:
                # Find positions that are 'active' (status='OPEN') in DB but NOT in open_tickets
                placeholders = ','.join(['%s'] * len(open_tickets))

                # Check which positions will be closed
                check_query = f"""
                    SELECT mt5_ticket, symbol FROM positions
                    WHERE mt5_ticket NOT IN ({placeholders})
                    AND status = 'OPEN'
                    AND mt5_ticket > 0
                """
                to_close = conn.execute(check_query, open_tickets).fetchall()

                if to_close:
                    tickets = [row['mt5_ticket'] for row in to_close]
                    logger.info(f"🔄 Syncing: Closing {len(to_close)} position(s) in DB: {tickets} (MT5 has {len(open_tickets)} open)")

                query = f"""
                    UPDATE positions
                    SET exit_time = CURRENT_TIMESTAMP,
                        exit_price = 0,
                        profit = 0,
                        status = 'CLOSED_SYNC'
                    WHERE mt5_ticket NOT IN ({placeholders})
                    AND status = 'OPEN'
                    AND mt5_ticket > 0
                """
                params = tuple(open_tickets)
                conn.execute(query, params)

            conn.commit()

    # ==================== Position Tracking ====================

    def update_position_metadata(self, mt5_ticket: int, **kwargs):
        """Update position metadata for exit strategies."""
        allowed_fields = ['breakeven_set', 'partial_taken', 'partial_volume', 'trailing_active']
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}

        if not updates:
            return

        set_clause = ', '.join([f"{k} = %s" for k in updates.keys()])
        values = list(updates.values()) + [mt5_ticket]

        query = f"""
            UPDATE positions
            SET {set_clause}
            WHERE mt5_ticket = %s
        """
        params = tuple(values)

        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()

    def get_position_metadata(self, mt5_ticket: int) -> Optional[Dict]:
        """Get position metadata."""
        query = """
            SELECT breakeven_set, partial_taken, partial_volume, trailing_active
            FROM positions
            WHERE mt5_ticket = %s
        """
        params = (mt5_ticket,)
        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    # ==================== Signal Confirmation System ====================

    def get_pending_signals(self, limit: int = 50) -> List[Dict]:
        """Get pending signals awaiting validation."""
        query = """
            SELECT * FROM signal_confirmations
            WHERE status = 'PENDING'
            AND confirmation_window_end > CURRENT_TIMESTAMP
            ORDER BY signal_generated_at ASC
            LIMIT %s
        """
        params = (limit,)

        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def get_confirmed_signals_ready_to_trade(self, limit: int = 10) -> List[Dict]:
        """Get confirmed signals ready for execution."""
        query = """
            SELECT sc.*, p.symbol, p.prediction_direction, p.confidence
            FROM signal_confirmations sc
            JOIN predictions p ON sc.prediction_id = p.id
            WHERE sc.status = 'CONFIRMED'
            AND sc.executed_at IS NULL
            AND sc.confirmation_window_end > CURRENT_TIMESTAMP
            ORDER BY sc.confirmation_score DESC, sc.confirmed_at ASC
            LIMIT %s
        """
        params = (limit,)

        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def get_signal_by_id(self, signal_id: int) -> Optional[Dict]:
        """Get signal confirmation by ID."""
        query = "SELECT * FROM signal_confirmations WHERE id = %s"
        params = (signal_id,)
        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    def get_recent_signals(self, hours: int = 24, status: str = None) -> List[Dict]:
        """Get recent signals for monitoring."""
        from datetime import datetime, timedelta
        time_window = datetime.now() - timedelta(hours=hours)

        with self.get_connection() as conn:
            if status:
                query = """
                    SELECT * FROM signal_confirmations
                    WHERE signal_generated_at > %s
                    AND status = %s
                    ORDER BY signal_generated_at DESC
                """
                params = (time_window, status)
            else:
                query = """
                    SELECT * FROM signal_confirmations
                    WHERE signal_generated_at > %s
                    ORDER BY signal_generated_at DESC
                """
                params = (time_window,)

            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def get_active_cooldowns(self) -> List[Dict]:
        """Get all active cooldowns."""
        query = """
            SELECT * FROM trade_cooldowns
            WHERE cooldown_end_time > CURRENT_TIMESTAMP
            ORDER BY cooldown_end_time ASC
        """

        with self.get_connection() as conn:
            rows = conn.execute(query).fetchall()
            return [dict(row) for row in rows]

    def get_signal_stats_summary(self, hours: int = 24) -> Dict:
        """Get signal confirmation statistics."""
        from datetime import datetime, timedelta
        time_window = datetime.now() - timedelta(hours=hours)

        with self.get_connection() as conn:
            query = """
                SELECT
                    status,
                    COUNT(*) as count,
                    AVG(confirmation_score) as avg_score
                FROM signal_confirmations
                WHERE signal_generated_at > %s
                GROUP BY status
            """
            params = (time_window,)
            rows = conn.execute(query, params).fetchall()

            stats = {}
            total = 0
            for row in rows:
                stats[row['status']] = {
                    'count': row['count'],
                    'avg_score': round(row['avg_score'], 1) if row['avg_score'] else 0
                }
                total += row['count']

            stats['total'] = total
            return stats
