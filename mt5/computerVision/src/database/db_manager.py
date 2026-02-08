import sqlite3
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
import pandas as pd

class DatabaseManager:
    """Manages all database operations for the CV Trading Agent."""
    
    def __init__(self, db_path: str = None):
        """
        Initialize database manager.
        
        Args:
            db_path: Path to SQLite database file
        """
        if db_path is None:
            # Resolve path relative to this file: src/database/db_manager.py -> project_root/data/cv_agent.db
            root_dir = Path(__file__).parent.parent.parent
            self.db_path = str(root_dir / "data" / "cv_agent.db")
        else:
            self.db_path = db_path
            
        self._ensure_db_exists()
    
    def _ensure_db_exists(self):
        """Create database and tables if they don't exist."""
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        
        # Read schema file
        schema_path = Path(__file__).parent / "schema.sql"
        with open(schema_path, 'r') as f:
            schema_sql = f.read()
        
        # Execute schema
        with self.get_connection() as conn:
            conn.executescript(schema_sql)
            conn.commit()
    
    def get_connection(self) -> sqlite3.Connection:
        """Get database connection."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn
    
    # ==================== Market Data ====================
    
    def insert_market_data(self, symbol: str, timeframe: str, bars: pd.DataFrame):
        """
        Insert market data bars.
        
        Args:
            symbol: Trading symbol
            timeframe: Timeframe (e.g., 'H1', 'M15')
            bars: DataFrame with columns: timestamp, open, high, low, close, tick_volume, spread, real_volume
        """
        with self.get_connection() as conn:
            for _, row in bars.iterrows():
                # Convert timestamp to string for SQLite
                timestamp_str = row['timestamp'].isoformat() if hasattr(row['timestamp'], 'isoformat') else str(row['timestamp'])
                
                conn.execute("""
                    INSERT OR REPLACE INTO market_data 
                    (symbol, timeframe, timestamp, open, high, low, close, tick_volume, spread, real_volume)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    symbol, timeframe, timestamp_str, row['open'], row['high'], 
                    row['low'], row['close'], row.get('tick_volume'), 
                    row.get('spread'), row.get('real_volume')
                ))
            conn.commit()
    
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
        with self.get_connection() as conn:
            df = pd.read_sql_query(query, conn, params=(symbol, timeframe, limit))
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
        
        with self.get_connection() as conn:
            cursor = conn.execute("""
                INSERT INTO models (name, version, model_type, hyperparameters, file_path, 
                                   training_accuracy, validation_accuracy)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (name, version, model_type, json.dumps(params), file_path,
                  training_accuracy, validation_accuracy))
            conn.commit()
            return cursor.lastrowid
    
    def save_model(self, **kwargs):
        """Alias for insert_model for compatibility."""
        return self.insert_model(**kwargs)
    
    def set_active_model(self, model_id: int):
        """Set a model as active (deactivate all others)."""
        with self.get_connection() as conn:
            conn.execute("UPDATE models SET is_active = 0")
            conn.execute("UPDATE models SET is_active = 1 WHERE id = ?", (model_id,))
            conn.commit()
    
    def get_model(self, model_id: int) -> Optional[Dict]:
        """Get model by ID."""
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM models WHERE id = ?", (model_id,)).fetchone()
            return dict(row) if row else None
    
    def get_active_model(self) -> Optional[Dict]:
        """Get the currently active model."""
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM models WHERE is_active = 1 LIMIT 1").fetchone()
            return dict(row) if row else None
    
    # ==================== Predictions ====================
    
    def insert_prediction(self, model_id: int, symbol: str, prediction_direction: str,
                         confidence: float, window_start: datetime, window_end: datetime,
                         prediction_horizon: int) -> int:
        """Insert prediction record."""
        # Convert datetime objects to ISO format strings for SQLite
        timestamp_str = datetime.now().isoformat()
        window_start_str = window_start.isoformat() if hasattr(window_start, 'isoformat') else str(window_start)
        window_end_str = window_end.isoformat() if hasattr(window_end, 'isoformat') else str(window_end)
        
        with self.get_connection() as conn:
            cursor = conn.execute("""
                INSERT INTO predictions (model_id, symbol, timestamp, prediction_direction, 
                                        confidence, window_start, window_end, prediction_horizon)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (model_id, symbol, timestamp_str, prediction_direction, confidence,
                  window_start_str, window_end_str, prediction_horizon))
            conn.commit()
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
                
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None
    
    # ==================== Positions ====================
    
    def insert_position(self, mt5_ticket: int, symbol: str, position_type: str,
                       volume: float, open_price: float, open_time: datetime,
                       stop_loss: float = None, take_profit: float = None,
                       prediction_id: int = None) -> int:
        """Insert new position."""
        with self.get_connection() as conn:
            cursor = conn.execute("""
                INSERT INTO positions (mt5_ticket, symbol, position_type, volume, open_price, 
                                      open_time, stop_loss, take_profit, prediction_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (mt5_ticket, symbol, position_type, volume, open_price, open_time,
                  stop_loss, take_profit, prediction_id))
            conn.commit()
            return cursor.lastrowid
    
    def get_open_positions(self) -> List[Dict]:
        """Get all open positions."""
        with self.get_connection() as conn:
            rows = conn.execute("SELECT * FROM positions WHERE status = 'OPEN'").fetchall()
            return [dict(row) for row in rows]
    
    def close_position(self, position_id: int):
        """Mark position as closed."""
        with self.get_connection() as conn:
            conn.execute("UPDATE positions SET status = 'CLOSED' WHERE id = ?", (position_id,))
            conn.commit()
    
    # ==================== Trades ====================
    
    def insert_trade(self, position_id: int, mt5_ticket: int, symbol: str, trade_type: str,
                    volume: float, open_price: float, close_price: float,
                    open_time: datetime, close_time: datetime, profit: float,
                    commission: float = 0, swap: float = 0, prediction_id: int = None,
                    entry_reason: str = None, exit_reason: str = None) -> int:
        """Insert completed trade."""
        with self.get_connection() as conn:
            cursor = conn.execute("""
                INSERT INTO trades (position_id, mt5_ticket, symbol, trade_type, volume,
                                   open_price, close_price, open_time, close_time, profit,
                                   commission, swap, prediction_id, entry_reason, exit_reason)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (position_id, mt5_ticket, symbol, trade_type, volume, open_price, close_price,
                  open_time, close_time, profit, commission, swap, prediction_id,
                  entry_reason, exit_reason))
            conn.commit()
            return cursor.lastrowid
    
    def get_trades(self, limit: int = 100) -> List[Dict]:
        """Get recent trades."""
        with self.get_connection() as conn:
            rows = conn.execute("""
                SELECT * FROM trades 
                ORDER BY close_time DESC 
                LIMIT ?
            """, (limit,)).fetchall()
            return [dict(row) for row in rows]
    
    def get_daily_pnl(self) -> float:
        """Get today's total P&L."""
        with self.get_connection() as conn:
            row = conn.execute("""
                SELECT COALESCE(SUM(profit + commission + swap), 0) as daily_pnl
                FROM trades
                WHERE DATE(close_time) = DATE('now')
            """).fetchone()
            return row['daily_pnl'] if row else 0.0
    
    # ==================== Configuration ====================
    
    def get_config(self, key: str) -> Optional[str]:
        """Get configuration value."""
        with self.get_connection() as conn:
            row = conn.execute("SELECT value FROM trading_config WHERE key = ?", (key,)).fetchone()
            return row['value'] if row else None
    
    def set_config(self, key: str, value: str):
        """Set configuration value."""
        with self.get_connection() as conn:
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
        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO system_logs (level, component, message, details)
                VALUES (?, ?, ?, ?)
            """, (level, component, message, json.dumps(details) if details else None))
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
        
        with self.get_connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]
            
    # ==================== Portfolio Management ====================
    
    def create_portfolio(self, name: str, initial_capital: float, description: str = None) -> int:
        """Create a new portfolio."""
        with self.get_connection() as conn:
            cursor = conn.execute("""
                INSERT INTO portfolios (name, initial_capital, current_capital, description)
                VALUES (?, ?, ?, ?)
            """, (name, initial_capital, initial_capital, description))
            conn.commit()
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
        with self.get_connection() as conn:
            cursor = conn.execute("""
                INSERT INTO strategies (name, type, model_id, config)
                VALUES (?, ?, ?, ?)
            """, (name, type, model_id, json.dumps(config) if config else None))
            conn.commit()
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
            conn.execute("""
                INSERT OR REPLACE INTO portfolio_allocations (portfolio_id, strategy_id, symbol, weight)
                VALUES (?, ?, ?, ?)
            """, (portfolio_id, strategy_id, symbol, weight))
            conn.commit()
            
    def get_allocations(self, portfolio_id: int) -> List[Dict]:
        """Get allocations for a portfolio."""
        with self.get_connection() as conn:
            rows = conn.execute("""
                SELECT a.*, s.name as strategy_name, s.type as strategy_type, s.model_id
                FROM portfolio_allocations a
                JOIN strategies s ON a.strategy_id = s.id
                WHERE a.portfolio_id = ? AND a.is_active = 1
                ORDER BY a.weight DESC
            """, (portfolio_id,)).fetchall()
            return [dict(row) for row in rows]
            
    def update_portfolio_performance(self, portfolio_id: int, total_equity: float, daily_pnl: float, drawdown: float):
        """Record daily portfolio performance."""
        date_str = datetime.now().date().isoformat()
        with self.get_connection() as conn:
            conn.execute("""
                INSERT OR REPLACE INTO portfolio_performance (portfolio_id, date, total_equity, daily_pnl, drawdown)
                VALUES (?, ?, ?, ?, ?)
            """, (portfolio_id, date_str, total_equity, daily_pnl, drawdown))
            conn.commit()
            
    def get_portfolio_performance(self, portfolio_id: int, days: int = 30) -> List[Dict]:
        """Get performance history for a portfolio."""
        with self.get_connection() as conn:
            rows = conn.execute("""
                SELECT * FROM portfolio_performance 
                WHERE portfolio_id = ? 
                ORDER BY date ASC 
                LIMIT ?
            """, (portfolio_id, days)).fetchall()
            return [dict(row) for row in rows]
