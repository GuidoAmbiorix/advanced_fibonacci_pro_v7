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
        """Saves a single symbol configuration dict to DB (Upsert)."""
        conn = self.get_connection()
        if not conn: return False
        try:
            cursor = conn.cursor()
            cols = ", ".join(config_dict.keys())
            placeholders = ", ".join(["?"] * len(config_dict))
            sql = f"INSERT OR REPLACE INTO SymbolConfigs ({cols}) VALUES ({placeholders})"
            cursor.execute(sql, tuple(config_dict.values()))
            conn.commit()
            return True
        except Exception as e:
            print(f"❌ Error saving config: {e}")
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
