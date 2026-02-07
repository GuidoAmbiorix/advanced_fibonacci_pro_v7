import sqlite3
import pandas as pd
import os
import time
import json

class DatabaseManager:
    def __init__(self, db_path=None):
        if db_path is None:
            # Default to env var or local file
            self.db_path = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")
        else:
            self.db_path = db_path

        # Initialize optimization tracking tables
        self._init_optimization_tables()
            
    def get_connection(self):
        """Returns a sqlite3 connection or None if file not found."""
        if not os.path.exists(self.db_path):
            print(f"❌ DB File not found at: {self.db_path}")
            return None
        return sqlite3.connect(self.db_path, check_same_thread=False)

    def load_configs(self):
        """Loads all symbol configurations into a DataFrame."""
        conn = self.get_connection()
        if not conn: return pd.DataFrame()
        try:
            return pd.read_sql("SELECT * FROM SymbolConfigs", conn)
        except Exception as e:
            print(f"❌ Error loading configs: {e}")
            return pd.DataFrame()
        finally:
            conn.close()

    def get_logs(self, limit=100):
        """Loads system logs."""
        conn = self.get_connection()
        if not conn: return pd.DataFrame()
        try:
            return pd.read_sql(f"SELECT * FROM SystemLogs ORDER BY time DESC LIMIT {limit}", conn)
        except Exception as e:
            print(f"❌ Error loading logs: {e}")
            return pd.DataFrame()
        finally:
            conn.close()

    def save_config(self, config_dict):
        """Saves a single symbol configuration dict to DB (Update)."""
        conn = self.get_connection()
        if not conn: return False
        try:
            cursor = conn.cursor()
            symbol = config_dict.get('symbol')
            if not symbol:
                print("❌ Config dict missing 'symbol' key")
                return False
                
            # Filter out keys that might not exist in columns or shouldn't be updated loosely if needed
            # For now, we assume config_dict came from load_configs, so keys are valid.
            
            # Construct UPDATE statement
            set_clauses = []
            values = []
            for key, value in config_dict.items():
                if key != 'symbol': # Don't update the primary key
                    set_clauses.append(f"{key} = ?")
                    values.append(value)
            
            values.append(symbol) # For WHERE clause
            
            sql = f"UPDATE SymbolConfigs SET {', '.join(set_clauses)} WHERE symbol = ?"
            
            cursor.execute(sql, tuple(values))
            
            if cursor.rowcount == 0:
                # If no row updated, try INSERT (Upsert fallback)
                print(f"⚠️ Update affected 0 rows for {symbol}. Trying Insert.")
                cols = ", ".join(config_dict.keys())
                placeholders = ", ".join(["?"] * len(config_dict))
                sql_insert = f"INSERT OR REPLACE INTO SymbolConfigs ({cols}) VALUES ({placeholders})"
                cursor.execute(sql_insert, tuple(config_dict.values()))
                
            conn.commit()
            print(f"✅ Configuration saved for {symbol}")
            return True
        except Exception as e:
            print(f"❌ Error saving config for {config_dict.get('symbol')}: {e}")
            return False
        finally:
            conn.close()

    def verify_config_sync(self, symbol, expected_params):
        """Verifies that the DB actually contains the expected values."""
        conn = self.get_connection()
        if not conn: return False
        try:
            config = pd.read_sql("SELECT * FROM SymbolConfigs WHERE symbol=?", conn, params=(symbol,))
            if config.empty: return False
            
            row = config.iloc[0].to_dict()
            matches = True
            for key, val in expected_params.items():
                # Allow small float differences
                db_val = row.get(key)
                if isinstance(val, float) and isinstance(db_val, float):
                    if abs(val - db_val) > 0.0001:
                        print(f"❌ Mismatch {key}: Exp {val} vs DB {db_val}")
                        matches = False
                elif str(val) != str(db_val):
                     print(f"❌ Mismatch {key}: Exp {val} vs DB {db_val}")
                     matches = False
            return matches
        except Exception as e:
            print(f"❌ Verification error: {e}")
            return False
        finally:
            conn.close()

    def log_event(self, source, level, message):
        """Logs a system event."""
        conn = self.get_connection()
        if not conn: return False
        try:
            cursor = conn.cursor()
            sql = "INSERT INTO SystemLogs (time, source, level, message) VALUES (?, ?, ?, ?)"
            cursor.execute(sql, (int(time.time()), source, level, message))
            conn.commit()
            return True
        except Exception as e:
            print(f"❌ Error logging event: {e}")
            return False
        finally:
            conn.close()

    def get_market_data(self, symbol, timeframe, limit=1000):
        """Loads market data for optimization."""
        conn = self.get_connection()
        if not conn: return pd.DataFrame()
        try:
            query = """
                SELECT time, open, high, low, close, tick_volume
                FROM MarketData
                WHERE symbol=? AND timeframe=?
                ORDER BY time ASC
                LIMIT ?
            """
            df = pd.read_sql(query, conn, params=(symbol, timeframe, limit))
            if not df.empty:
                df['time'] = pd.to_datetime(df['time'], unit='s')
            return df
        except Exception as e:
            print(f"❌ Error loading market data: {e}")
            return pd.DataFrame()
        finally:
            conn.close()

    def _init_optimization_tables(self):
        """Create optimization tracking tables if they don't exist."""
        conn = self.get_connection()
        if not conn: return

        try:
            cursor = conn.cursor()

            # OptimizationRuns table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS OptimizationRuns (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    mode TEXT NOT NULL,
                    status TEXT NOT NULL,
                    started_at INTEGER NOT NULL,
                    completed_at INTEGER,
                    n_trials INTEGER,
                    best_sharpe REAL,
                    best_params TEXT,
                    train_sharpe REAL,
                    test_sharpe REAL,
                    oos_degradation REAL,
                    param_count INTEGER,
                    trade_count_train INTEGER,
                    trade_count_test INTEGER,
                    overfitting_risk TEXT,
                    error_message TEXT
                )
            """)

            # SymbolConfigsBackup table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS SymbolConfigsBackup (
                    backup_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    backup_timestamp INTEGER NOT NULL,
                    config_json TEXT NOT NULL,
                    backup_reason TEXT
                )
            """)

            # ABTests table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS ABTests (
                    test_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    start_time INTEGER NOT NULL,
                    end_time INTEGER,
                    config_a TEXT NOT NULL,
                    config_b TEXT NOT NULL,
                    trades_a INTEGER DEFAULT 0,
                    trades_b INTEGER DEFAULT 0,
                    sharpe_a REAL DEFAULT 0,
                    sharpe_b REAL DEFAULT 0,
                    winner TEXT,
                    status TEXT DEFAULT 'running'
                )
            """)

            conn.commit()
        except Exception as e:
            print(f"⚠️ Error initializing optimization tables: {e}")
        finally:
            conn.close()

    def log_optimization_run(self, run_data):
        """Log an optimization run to the database."""
        conn = self.get_connection()
        if not conn: return None

        try:
            cursor = conn.cursor()

            # Convert params dict to JSON string
            best_params_json = json.dumps(run_data.get('best_params', {}))

            cursor.execute("""
                INSERT INTO OptimizationRuns (
                    symbol, mode, status, started_at, completed_at,
                    n_trials, best_sharpe, best_params, train_sharpe, test_sharpe,
                    oos_degradation, param_count, trade_count_train, trade_count_test,
                    overfitting_risk, error_message
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                run_data.get('symbol'),
                run_data.get('mode', 'single'),
                run_data.get('status', 'completed'),
                run_data.get('started_at'),
                run_data.get('completed_at'),
                run_data.get('n_trials'),
                run_data.get('best_sharpe'),
                best_params_json,
                run_data.get('train_sharpe'),
                run_data.get('test_sharpe'),
                run_data.get('oos_degradation'),
                run_data.get('param_count'),
                run_data.get('trade_count_train'),
                run_data.get('trade_count_test'),
                run_data.get('overfitting_risk'),
                run_data.get('error_message')
            ))

            conn.commit()
            return cursor.lastrowid
        except Exception as e:
            print(f"❌ Error logging optimization run: {e}")
            return None
        finally:
            conn.close()

    def get_optimization_history(self, symbol=None, limit=100):
        """Get optimization run history."""
        conn = self.get_connection()
        if not conn: return pd.DataFrame()

        try:
            if symbol:
                query = """
                    SELECT * FROM OptimizationRuns
                    WHERE symbol = ?
                    ORDER BY started_at DESC
                    LIMIT ?
                """
                return pd.read_sql(query, conn, params=(symbol, limit))
            else:
                query = """
                    SELECT * FROM OptimizationRuns
                    ORDER BY started_at DESC
                    LIMIT ?
                """
                return pd.read_sql(query, conn, params=(limit,))
        except Exception as e:
            print(f"❌ Error loading optimization history: {e}")
            return pd.DataFrame()
        finally:
            conn.close()

    def backup_config(self, symbol, reason="manual"):
        """Create backup before optimization."""
        conn = self.get_connection()
        if not conn: return False

        try:
            cursor = conn.cursor()

            # Read current config
            config = pd.read_sql("SELECT * FROM SymbolConfigs WHERE symbol=?", conn, params=(symbol,))
            if config.empty:
                return False

            config_json = config.iloc[0].to_json()

            # Insert backup
            cursor.execute("""
                INSERT INTO SymbolConfigsBackup (symbol, backup_timestamp, config_json, backup_reason)
                VALUES (?, ?, ?, ?)
            """, (symbol, int(time.time()), config_json, reason))

            conn.commit()
            return True
        except Exception as e:
            print(f"❌ Backup error: {e}")
            return False
        finally:
            conn.close()

    def restore_config(self, symbol, backup_id):
        """Restore configuration from backup."""
        conn = self.get_connection()
        if not conn: return False

        try:
            # Load backup
            backup = pd.read_sql(
                "SELECT config_json FROM SymbolConfigsBackup WHERE backup_id=?",
                conn,
                params=(backup_id,)
            )

            if backup.empty:
                return False

            config_dict = json.loads(backup.iloc[0]['config_json'])

            # Restore
            return self.save_config(config_dict)
        except Exception as e:
            print(f"❌ Restore error: {e}")
            return False
        finally:
            conn.close()

    def get_backups(self, symbol, limit=10):
        """Get configuration backups for a symbol."""
        conn = self.get_connection()
        if not conn: return pd.DataFrame()

        try:
            query = """
                SELECT backup_id, symbol,
                       datetime(backup_timestamp, 'unixepoch') as backed_up_at,
                       backup_reason
                FROM SymbolConfigsBackup
                WHERE symbol = ?
                ORDER BY backup_timestamp DESC
                LIMIT ?
            """
            return pd.read_sql(query, conn, params=(symbol, limit))
        except Exception as e:
            print(f"❌ Error loading backups: {e}")
            return pd.DataFrame()
        finally:
            conn.close()
