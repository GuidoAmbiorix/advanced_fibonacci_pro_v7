import sqlite3
import pandas as pd
import os
import time

class DatabaseManager:
    def __init__(self, db_path=None):
        if db_path is None:
            # Default to env var or local file
            self.db_path = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")
        else:
            self.db_path = db_path
            
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
            config = pd.read_sql(f"SELECT * FROM SymbolConfigs WHERE symbol='{symbol}'", conn)
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
            query = f"""
                SELECT time, open, high, low, close, tick_volume 
                FROM MarketData 
                WHERE symbol='{symbol}' AND timeframe={timeframe} 
                ORDER BY time ASC 
                LIMIT {limit}
            """
            df = pd.read_sql(query, conn)
            if not df.empty:
                df['time'] = pd.to_datetime(df['time'], unit='s')
            return df
        except Exception as e:
            print(f"❌ Error loading market data: {e}")
            return pd.DataFrame()
        finally:
            conn.close()
