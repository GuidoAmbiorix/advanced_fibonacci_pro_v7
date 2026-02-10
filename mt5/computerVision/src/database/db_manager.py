import sqlite3
import json
import os
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
import pandas as pd

# PostgreSQL support (optional)
try:
    import psycopg2
    import psycopg2.extras
    from psycopg2 import pool
    POSTGRES_AVAILABLE = True
except ImportError:
    POSTGRES_AVAILABLE = False


class PostgresConnectionWrapper:
    """
    Wrapper for PostgreSQL connection to provide context manager and cursor with dict-like access.
    Makes PostgreSQL connections compatible with SQLite usage patterns.
    """

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
        """Get cursor with RealDictCursor for dict-like row access."""
        self._cursor = self._conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        return self._cursor

    def _convert_query(self, query: str) -> str:
        """Convert SQLite-style query to PostgreSQL."""
        if not isinstance(query, str):
            return query
            
        # Replace ? with %s for compatibility with SQLite code
        if '?' in query:
            query = query.replace('?', '%s')
            
        # Replace common SQLite-specific functions
        query = query.replace("datetime('now')", "CURRENT_TIMESTAMP")
        query = query.replace("datetime('NOW')", "CURRENT_TIMESTAMP")
        query = query.replace("DATE('now')", "CURRENT_DATE")
        query = query.replace("DATE('NOW')", "CURRENT_DATE")
        
        return query

    def execute(self, query, params=None):
        """Execute a query and return cursor."""
        query = self._convert_query(query)
        cursor = self.cursor()
        cursor.execute(query, params or ())
        return cursor

    def executemany(self, query, params_list):
        """Execute a query multiple times with different parameters."""
        query = self._convert_query(query)
        cursor = self.cursor()
        # Use execute_batch for better performance
        psycopg2.extras.execute_batch(cursor, query, params_list)
        return cursor

    def executescript(self, script):
        """Execute a SQL script (multiple statements)."""
        # Script might contain multiple statements that need conversion
        # This is basic and might not handle all complex cases, but covers most
        script = self._convert_query(script)
        cursor = self.cursor()
        cursor.execute(script)
        return cursor

    def commit(self):
        """Commit transaction."""
        self._conn.commit()

    def rollback(self):
        """Rollback transaction."""
        self._conn.rollback()

    def close(self):
        """Close connection and return to pool."""
        if self._cursor:
            self._cursor.close()
        self._release_func(self._conn)


class DatabaseManager:
    """Manages all database operations for the CV Trading Agent."""

    def __init__(self, db_path: str = None, db_url: str = None):
        """
        Initialize database manager.

        Args:
            db_path: Path to SQLite database file (for sqlite mode)
            db_url: PostgreSQL connection URL (for postgresql mode)
        """
        # Determine database type from environment or default to SQLite
        self.db_type = os.environ.get('DATABASE_TYPE', 'sqlite').lower()

        if self.db_type == 'postgresql':
            if not POSTGRES_AVAILABLE:
                raise ImportError("psycopg2 is required for PostgreSQL support. Install with: pip install psycopg2-binary")

            self.db_url = db_url or os.environ.get('DATABASE_URL')
            if not self.db_url:
                raise ValueError("DATABASE_URL environment variable is required for PostgreSQL mode")

            self._init_postgres_pool()
            self.db_path = None
        else:
            # SQLite mode
            if db_path is None:
                # Resolve path relative to this file: src/database/db_manager.py -> project_root/data/cv_agent.db
                root_dir = Path(__file__).parent.parent.parent
                self.db_path = str(root_dir / "data" / "cv_agent.db")
            else:
                self.db_path = db_path

            self.db_url = None
            self._pg_pool = None

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
        """Create database and tables if they don't exist."""
        if self.db_type == 'postgresql':
            # PostgreSQL: schema is loaded via docker-entrypoint-initdb.d or manually
            # Just verify connection works
            try:
                conn = self._get_pg_connection()
                conn.close()
                print("[OK] PostgreSQL database connection verified")
            except Exception as e:
                print(f"[WARNING] PostgreSQL connection check failed: {e}")
        else:
            # SQLite: create database file and tables
            Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)

            # Check if database needs to be created
            db_exists = Path(self.db_path).exists()

            # Read schema file
            schema_path = Path(__file__).parent / "schema.sql"
            with open(schema_path, 'r') as f:
                schema_sql = f.read()

            # Execute schema
            with self.get_connection() as conn:
                # Set journal mode ONCE when creating new database
                if not db_exists:
                    is_docker = os.path.exists('/.dockerenv') or os.environ.get('DOCKER_CONTAINER') == 'true'
                    if is_docker:
                        # DELETE mode for Docker (compatible with volume mounts)
                        conn.execute("PRAGMA journal_mode=DELETE")
                    else:
                        # WAL mode for native execution (better concurrency)
                        conn.execute("PRAGMA journal_mode=WAL")

                conn.executescript(schema_sql)
                conn.commit()

    def check_database_integrity(self) -> bool:
        """
        Check database integrity and return True if database is healthy.

        Returns:
            bool: True if database passes integrity check
        """
        try:
            with self.get_connection() as conn:
                result = conn.execute("PRAGMA integrity_check").fetchone()
                is_ok = result[0] == 'ok'

                if is_ok:
                    print("[OK] Database integrity check: PASSED")
                else:
                    print(f"[ERROR] Database integrity check: FAILED - {result[0]}")

                return is_ok
        except Exception as e:
            print(f"[ERROR] Database integrity check error: {e}")
            return False

    def vacuum_database(self):
        """
        Optimize database by reclaiming unused space and defragmenting.
        Should be run periodically to maintain database health.
        """
        try:
            with self.get_connection() as conn:
                conn.execute("VACUUM")
                print("[OK] Database vacuumed successfully")
        except Exception as e:
            print(f"[ERROR] Failed to vacuum database: {e}")
    
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
        if self.db_type == 'postgresql' and self._pg_pool:
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
        Get database connection with proper settings.

        Returns:
            - SQLite connection with Row factory (for sqlite mode)
            - PostgreSQL connection with RealDictCursor (for postgresql mode)

        Note: Use this in a context manager to ensure proper cleanup.
        """
        if self.db_type == 'postgresql':
            return PostgresConnectionWrapper(self._get_pg_connection(), self._release_pg_connection)
        else:
            conn = sqlite3.connect(
                self.db_path,
                timeout=30.0,  # Wait up to 30 seconds if database is locked
                check_same_thread=False,  # Allow connection across threads (safe with context manager)
                isolation_level='DEFERRED'  # Better for concurrent reads
            )
            conn.row_factory = sqlite3.Row

            # Configure SQLite for reliability
            try:
                conn.execute("PRAGMA foreign_keys=ON")  # Enforce foreign key constraints
                conn.execute("PRAGMA busy_timeout=30000")  # 30 second busy timeout

                # Only set synchronous mode (don't change journal_mode on existing database)
                is_docker = os.path.exists('/.dockerenv') or os.environ.get('DOCKER_CONTAINER') == 'true'

                if is_docker:
                    conn.execute("PRAGMA synchronous=FULL")  # Extra safety for mounted volumes
                else:
                    conn.execute("PRAGMA synchronous=NORMAL")  # Balanced performance
            except sqlite3.OperationalError:
                # If we can't set PRAGMAs (read-only filesystem), that's OK
                pass

            return conn

    def _convert_query_to_postgres(self, query: str, params: tuple) -> tuple:
        """
        Convert SQLite query syntax to PostgreSQL.

        Changes:
        - ? placeholders to $1, $2, $3...
        - INSERT OR REPLACE to INSERT ... ON CONFLICT
        - INSERT OR IGNORE to INSERT ... ON CONFLICT DO NOTHING
        - DATE('now') to CURRENT_DATE
        - datetime('now') to CURRENT_TIMESTAMP
        - CURRENT_TIMESTAMP already compatible

        Returns:
            (converted_query, params)
        """
        if self.db_type != 'postgresql':
            return query, params

        # Replace ? with %s for psycopg2
        query = query.replace('?', '%s')

        # Replace SQLite date/time functions
        query = query.replace("DATE('now')", "CURRENT_DATE")
        query = query.replace("datetime('now')", "CURRENT_TIMESTAMP")

        return query, params
    
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

                # Different query syntax for SQLite vs PostgreSQL
                if self.db_type == 'postgresql':
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
                else:
                    query = """
                        INSERT OR REPLACE INTO market_data
                        (symbol, timeframe, timestamp, open, high, low, close, tick_volume, spread, real_volume)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            WHERE symbol = ? AND timeframe = ?
            ORDER BY timestamp DESC
            LIMIT ?
        """
        params = (symbol, timeframe, limit)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            if self.db_type == 'postgresql':
                # For PostgreSQL, we need to use a different approach
                cursor = conn.execute(query, params)
                rows = cursor.fetchall()
                df = pd.DataFrame(rows, columns=['timestamp', 'open', 'high', 'low', 'close', 'tick_volume', 'spread', 'real_volume'])
            else:
                df = pd.read_sql_query(query, conn._conn if hasattr(conn, '_conn') else conn, params=params)

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

        # For PostgreSQL, store as JSONB; for SQLite, store as JSON string
        params_value = params if self.db_type == 'postgresql' else json.dumps(params)

        query = """
            INSERT INTO models (name, version, model_type, hyperparameters, file_path,
                               training_accuracy, validation_accuracy)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        query_params = (name, version, model_type, params_value, file_path,
                       training_accuracy, validation_accuracy)
        query, query_params = self._convert_query_to_postgres(query, query_params)

        with self.get_connection() as conn:
            cursor = conn.execute(query, query_params)
            conn.commit()
            # Get last inserted ID
            if self.db_type == 'postgresql':
                cursor.execute("SELECT lastval() as last_id")
                return cursor.fetchone()['last_id']
            else:
                return cursor.lastrowid
    
    def save_model(self, **kwargs):
        """Alias for insert_model for compatibility."""
        return self.insert_model(**kwargs)
    
    def set_active_model(self, model_id: int):
        """Set a model as active (deactivate all others)."""
        with self.get_connection() as conn:
            if self.db_type == 'postgresql':
                conn.execute("UPDATE models SET is_active = FALSE")
                conn.execute("UPDATE models SET is_active = TRUE WHERE id = %s", (model_id,))
            else:
                conn.execute("UPDATE models SET is_active = 0")
                conn.execute("UPDATE models SET is_active = 1 WHERE id = ?", (model_id,))
            conn.commit()
    
    def get_model(self, model_id: int) -> Optional[Dict]:
        """Get model by ID."""
        query = "SELECT * FROM models WHERE id = ?"
        params = (model_id,)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None
    
    def get_active_model(self) -> Optional[Dict]:
        """Get the currently active model."""
        if self.db_type == 'postgresql':
            query = "SELECT * FROM models WHERE is_active = TRUE LIMIT 1"
            params = ()
        else:
            query = "SELECT * FROM models WHERE is_active = 1 LIMIT 1"
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

        query = """
            INSERT INTO predictions (model_id, symbol, timestamp, prediction_direction,
                                    confidence, window_start, window_end, prediction_horizon)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        params = (model_id, symbol, timestamp_str, prediction_direction, confidence,
                 window_start_str, window_end_str, prediction_horizon)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            conn.commit()

            # Get last inserted ID
            if self.db_type == 'postgresql':
                cursor.execute("SELECT lastval() as last_id")
                return cursor.fetchone()['last_id']
            else:
                return cursor.lastrowid
    
    def get_latest_prediction(self, symbol: str, model_id: int = None) -> Optional[Dict]:
        """Get the most recent prediction for a symbol, optionally filtered by model."""
        with self.get_connection() as conn:
            if model_id:
                query = """
                    SELECT * FROM predictions 
                    WHERE symbol = ? AND model_id = ?
                    ORDER BY timestamp DESC 
                    LIMIT 1
                """
                params = (symbol, model_id)
            else:
                query = """
                    SELECT * FROM predictions 
                    WHERE symbol = ? 
                    ORDER BY timestamp DESC 
                    LIMIT 1
                """
                params = (symbol,)
            
            query, params = self._convert_query_to_postgres(query, params)
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None
    
    # ==================== Positions ====================
    
    def insert_position(self, mt5_ticket: int, symbol: str, position_type: str,
                       volume: float, open_price: float, open_time: datetime,
                       stop_loss: float = None, take_profit: float = None,
                       prediction_id: int = None) -> int:
        """Insert new position."""
        query = """
            INSERT INTO positions (mt5_ticket, symbol, position_type, volume, open_price,
                                  open_time, stop_loss, take_profit, prediction_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        params = (mt5_ticket, symbol, position_type, volume, open_price, open_time,
                 stop_loss, take_profit, prediction_id)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            conn.commit()

            # Get last inserted ID
            if self.db_type == 'postgresql':
                cursor.execute("SELECT lastval() as last_id")
                return cursor.fetchone()['last_id']
            else:
                return cursor.lastrowid
    
    def get_open_positions(self) -> List[Dict]:
        """Get all open positions."""
        query = "SELECT * FROM positions WHERE status = 'OPEN'"
        query, params = self._convert_query_to_postgres(query, ())
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]
    
    def close_position(self, position_id: int):
        """Mark position as closed."""
        query = "UPDATE positions SET status = 'CLOSED' WHERE id = ?"
        params = (position_id,)
        query, params = self._convert_query_to_postgres(query, params)
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
        query = """
            INSERT INTO trades (position_id, mt5_ticket, symbol, trade_type, volume,
                               open_price, close_price, open_time, close_time, profit,
                               commission, swap, prediction_id, entry_reason, exit_reason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        params = (position_id, mt5_ticket, symbol, trade_type, volume, open_price, close_price,
                 open_time, close_time, profit, commission, swap, prediction_id,
                 entry_reason, exit_reason)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            conn.commit()

            # Get last inserted ID
            if self.db_type == 'postgresql':
                cursor.execute("SELECT lastval() as last_id")
                return cursor.fetchone()['last_id']
            else:
                return cursor.lastrowid
    
    def get_trades(self, limit: int = 100) -> List[Dict]:
        """Get recent trades."""
        query = """
            SELECT * FROM trades 
            ORDER BY close_time DESC 
            LIMIT ?
        """
        params = (limit,)
        query, params = self._convert_query_to_postgres(query, params)
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]
    
    def get_daily_pnl(self) -> float:
        """Get today's total P&L."""
        with self.get_connection() as conn:
            if self.db_type == 'postgresql':
                query = """
                    SELECT COALESCE(SUM(profit + commission + swap), 0) as daily_pnl
                    FROM trades
                    WHERE DATE(close_time) = CURRENT_DATE
                """
            else:
                query = """
                    SELECT COALESCE(SUM(profit + commission + swap), 0) as daily_pnl
                    FROM trades
                    WHERE DATE(close_time) = DATE('now')
                """
            row = conn.execute(query).fetchone()
            return row['daily_pnl'] if row else 0.0
    
    # ==================== Configuration ====================
    
    def get_config(self, key: str, default: str = None) -> Optional[str]:
        """Get configuration value with optional default."""
        query = "SELECT value FROM trading_config WHERE key = ?"
        params = (key,)
        query, params = self._convert_query_to_postgres(query, params)
        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return row['value'] if row else default
    
    def set_config(self, key: str, value: str):
        """Set configuration value."""
        with self.get_connection() as conn:
            if self.db_type == 'postgresql':
                conn.execute("""
                    INSERT INTO trading_config (key, value, updated_at)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (key)
                    DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at
                """, (key, value, datetime.now()))
            else:
                conn.execute("""
                    INSERT OR REPLACE INTO trading_config (key, value, updated_at)
                    VALUES (?, ?, ?)
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
        # For PostgreSQL, store details as JSONB; for SQLite, store as JSON string
        details_value = details if self.db_type == 'postgresql' else (json.dumps(details) if details else None)

        query = """
            INSERT INTO system_logs (level, component, message, details)
            VALUES (?, ?, ?, ?)
        """
        params = (level, component, message, details_value)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()
    
    def get_logs(self, level: str = None, component: str = None, limit: int = 100) -> List[Dict]:
        """Get system logs with optional filtering."""
        query = "SELECT * FROM system_logs WHERE 1=1"
        params = []
        
        if level:
            query += " AND level = ?"
            params.append(level)
        if component:
            query += " AND component = ?"
            params.append(component)
        
        query += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)
        
        query, params = self._convert_query_to_postgres(query, tuple(params))
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]
            
    # ==================== Portfolio Management ====================
    
    def create_portfolio(self, name: str, initial_capital: float, description: str = None) -> int:
        """Create a new portfolio."""
        query = """
            INSERT INTO portfolios (name, initial_capital, current_capital, description)
            VALUES (?, ?, ?, ?)
        """
        params = (name, initial_capital, initial_capital, description)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            conn.commit()

            # Get last inserted ID
            if self.db_type == 'postgresql':
                cursor.execute("SELECT lastval()")
                return cursor.fetchone()[0]
            else:
                return cursor.lastrowid
            
    def get_portfolios(self) -> List[Dict]:
        """Get all portfolios."""
        with self.get_connection() as conn:
            rows = conn.execute("SELECT * FROM portfolios ORDER BY created_at DESC").fetchall()
            return [dict(row) for row in rows]
            
    def get_portfolio(self, portfolio_id: int) -> Optional[Dict]:
        """Get specific portfolio."""
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM portfolios WHERE id = ?", (portfolio_id,)).fetchone()
            return dict(row) if row else None
            
    def create_strategy(self, name: str, type: str, model_id: int = None, config: Dict = None) -> int:
        """Create a new trading strategy."""
        # For PostgreSQL, store config as JSONB; for SQLite, store as JSON string
        config_value = config if self.db_type == 'postgresql' else (json.dumps(config) if config else None)

        query = """
            INSERT INTO strategies (name, type, model_id, config)
            VALUES (?, ?, ?, ?)
        """
        params = (name, type, model_id, config_value)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            conn.commit()

            # Get last inserted ID
            if self.db_type == 'postgresql':
                cursor.execute("SELECT lastval()")
                return cursor.fetchone()[0]
            else:
                return cursor.lastrowid
            
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
            if self.db_type == 'postgresql':
                conn.execute("""
                    INSERT INTO portfolio_allocations (portfolio_id, strategy_id, symbol, weight)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (portfolio_id, strategy_id, symbol)
                    DO UPDATE SET weight = EXCLUDED.weight, updated_at = CURRENT_TIMESTAMP
                """, (portfolio_id, strategy_id, symbol, weight))
            else:
                conn.execute("""
                    INSERT OR REPLACE INTO portfolio_allocations (portfolio_id, strategy_id, symbol, weight)
                    VALUES (?, ?, ?, ?)
                """, (portfolio_id, strategy_id, symbol, weight))
            conn.commit()
            
    def get_allocations(self, portfolio_id: int) -> List[Dict]:
        """Get allocations for a portfolio."""
        query = """
            SELECT a.*, s.name as strategy_name, s.type as strategy_type, s.model_id
            FROM portfolio_allocations a
            JOIN strategies s ON a.strategy_id = s.id
            WHERE a.portfolio_id = ? AND a.is_active = 1
            ORDER BY a.weight DESC
        """
        params = (portfolio_id,)
        query, params = self._convert_query_to_postgres(query, params)
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]
            
    def update_portfolio_performance(self, portfolio_id: int, total_equity: float, daily_pnl: float, drawdown: float):
        """Record daily portfolio performance."""
        date_str = datetime.now().date().isoformat()
        with self.get_connection() as conn:
            if self.db_type == 'postgresql':
                conn.execute("""
                    INSERT INTO portfolio_performance (portfolio_id, date, total_equity, daily_pnl, drawdown)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (portfolio_id, date)
                    DO UPDATE SET total_equity = EXCLUDED.total_equity,
                                  daily_pnl = EXCLUDED.daily_pnl,
                                  drawdown = EXCLUDED.drawdown
                """, (portfolio_id, date_str, total_equity, daily_pnl, drawdown))
            else:
                conn.execute("""
                    INSERT OR REPLACE INTO portfolio_performance (portfolio_id, date, total_equity, daily_pnl, drawdown)
                    VALUES (?, ?, ?, ?, ?)
                """, (portfolio_id, date_str, total_equity, daily_pnl, drawdown))
            conn.commit()
            
    def get_portfolio_performance(self, portfolio_id: int, days: int = 30) -> List[Dict]:
        """Get performance history for a portfolio."""
        query = """
            SELECT * FROM portfolio_performance 
            WHERE portfolio_id = ? 
            ORDER BY date ASC 
            LIMIT ?
        """
        params = (portfolio_id, days)
        query, params = self._convert_query_to_postgres(query, params)
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]
    
    # ==================== Killzone Management ====================
    
    def get_killzone_windows(self, active_only: bool = True) -> List[Dict]:
        """Get all killzone windows."""
        with self.get_connection() as conn:
            query = "SELECT * FROM killzone_windows"
            if active_only:
                query += " WHERE is_active = 1"
            query += " ORDER BY priority DESC, start_time ASC"
            
            rows = conn.execute(query).fetchall()
            return [dict(row) for row in rows]
    
    def add_killzone_window(self, name: str, start_time: str, end_time: str,
                           days_of_week: str, timezone: str = 'America/New_York',
                           priority: str = 'medium') -> int:
        """Add a new killzone window."""
        query = """
            INSERT INTO killzone_windows (name, start_time, end_time, days_of_week, timezone, priority)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        params = (name, start_time, end_time, days_of_week, timezone, priority)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            cursor = conn.execute(query, params)
            conn.commit()

            # Get last inserted ID
            if self.db_type == 'postgresql':
                cursor.execute("SELECT lastval()")
                return cursor.fetchone()[0]
            else:
                return cursor.lastrowid
    
    def update_killzone_window(self, killzone_id: int, **kwargs):
        """Update a killzone window."""
        allowed_fields = ['name', 'start_time', 'end_time', 'days_of_week', 'timezone', 'priority', 'is_active']
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        
        if not updates:
            return
        
        set_clause = ', '.join([f"{k} = ?" for k in updates.keys()])
        values = list(updates.values()) + [killzone_id]
        
        query = f"""
            UPDATE killzone_windows 
            SET {set_clause}, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        """
        params = tuple(values)
        query, params = self._convert_query_to_postgres(query, params)
        
        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()
    
    def delete_killzone_window(self, killzone_id: int):
        """Delete a killzone window."""
        query = "DELETE FROM killzone_windows WHERE id = ?"
        params = (killzone_id,)
        query, params = self._convert_query_to_postgres(query, params)
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
                placeholders = ','.join(['?'] * len(open_tickets))

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
                query, params = self._convert_query_to_postgres(query, params)
                conn.execute(query, params)

            conn.commit()
    
    # ==================== Position Tracking ====================
    
    def update_position_metadata(self, mt5_ticket: int, **kwargs):
        """Update position metadata for exit strategies."""
        allowed_fields = ['breakeven_set', 'partial_taken', 'partial_volume', 'trailing_active']
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        
        if not updates:
            return
        
        set_clause = ', '.join([f"{k} = ?" for k in updates.keys()])
        values = list(updates.values()) + [mt5_ticket]
        
        query = f"""
            UPDATE positions 
            SET {set_clause}
            WHERE mt5_ticket = ?
        """
        params = tuple(values)
        query, params = self._convert_query_to_postgres(query, params)
        
        with self.get_connection() as conn:
            conn.execute(query, params)
            conn.commit()
    
    def get_position_metadata(self, mt5_ticket: int) -> Optional[Dict]:
        """Get position metadata."""
        query = """
            SELECT breakeven_set, partial_taken, partial_volume, trailing_active
            FROM positions
            WHERE mt5_ticket = ?
        """
        params = (mt5_ticket,)
        query, params = self._convert_query_to_postgres(query, params)
        with self.get_connection() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    # ==================== Signal Confirmation System ====================

    def get_pending_signals(self, limit: int = 50) -> List[Dict]:
        """Get pending signals awaiting validation."""
        query = """
            SELECT * FROM signal_confirmations
            WHERE status = 'PENDING'
            AND confirmation_window_end > datetime('now')
            ORDER BY signal_generated_at ASC
            LIMIT ?
        """
        params = (limit,)
        query, params = self._convert_query_to_postgres(query, params)

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
            AND sc.confirmation_window_end > datetime('now')
            ORDER BY sc.confirmation_score DESC, sc.confirmed_at ASC
            LIMIT ?
        """
        params = (limit,)
        query, params = self._convert_query_to_postgres(query, params)

        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def get_signal_by_id(self, signal_id: int) -> Optional[Dict]:
        """Get signal confirmation by ID."""
        query = "SELECT * FROM signal_confirmations WHERE id = ?"
        params = (signal_id,)
        query, params = self._convert_query_to_postgres(query, params)
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
                    WHERE signal_generated_at > ?
                    AND status = ?
                    ORDER BY signal_generated_at DESC
                """
                params = (time_window, status)
            else:
                query = """
                    SELECT * FROM signal_confirmations
                    WHERE signal_generated_at > ?
                    ORDER BY signal_generated_at DESC
                """
                params = (time_window,)
            
            query, params = self._convert_query_to_postgres(query, params)
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def get_active_cooldowns(self) -> List[Dict]:
        """Get all active cooldowns."""
        query = """
            SELECT * FROM trade_cooldowns
            WHERE cooldown_end_time > datetime('now')
            ORDER BY cooldown_end_time ASC
        """
        query, params = self._convert_query_to_postgres(query, ())

        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
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
                WHERE signal_generated_at > ?
                GROUP BY status
            """
            params = (time_window,)
            query, params = self._convert_query_to_postgres(query, params)
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
