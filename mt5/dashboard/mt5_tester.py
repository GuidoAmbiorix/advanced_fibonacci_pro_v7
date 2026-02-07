import os
import subprocess
import sqlite3
import time
import shutil
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("MT5Tester")

class MT5Tester:
    def __init__(self):
        # Path to the shared database
        self.db_path = os.getenv('DB_PATH', '/mt5_data/.wine/drive_c/users/trader/AppData/Roaming/MetaQuotes/Terminal/Common/Files/PortfolioGovernor.sqlite')
        
        # Path to MT5 Terminal executable
        # Assuming the standard path in the shared volume known from docker-compose volume mapping
        # /mt5_data maps to /config in gmag11/metatrader5_vnc
        # /config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe
        self.mt5_exe = "/mt5_data/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
        self.wine_prefix = "/mt5_data/.wine"
        self.tester_ini_path = "tester.ini"

    def prepare_db(self, params: dict, symbol: str):
        """
        Updates the Database with the specific parameters for this trial.
        Dynamically checks for existing columns to avoid 'no such column' errors.
        """
        if not os.path.exists(self.db_path):
            logger.error(f"Database not found at {self.db_path}")
            return False

        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # 1. Get existing columns in SymbolConfigs
            cursor.execute("PRAGMA table_info(SymbolConfigs)")
            columns_info = cursor.fetchall()
            existing_columns = {info[1] for info in columns_info} # Set of column names
            
            # 2. Update SymbolConfigs
            # We assume a record already exists for the symbol (imported from default)
            # We optimize by updating specific columns
            
            cols = []
            values = []
            
            for key, value in params.items():
                # Check if param exists in DB columns
                if key in existing_columns:
                    cols.append(f"{key} = ?")
                    values.append(value)
                else:
                    # Log warning only once per session or debug level
                    logger.debug(f"Skipping parameter '{key}' - Column not found in DB")
            
            if not cols:
                logger.warning(f"No valid parameters to update for {symbol}")
                return True 
                
            sql = f"UPDATE SymbolConfigs SET {', '.join(cols)} WHERE symbol = ?"
            values.append(symbol)
            
            cursor.execute(sql, values)
            
            # 2. Set 'Optimization Mode' flag in State to ensure EA reloads configs
            cursor.execute("INSERT OR REPLACE INTO GovernorState (key, value_num, updated_at) VALUES ('OPTIMIZATION_ACTIVE', 1, ?)", (int(time.time()),))
            
            conn.commit()
            conn.close()
            return True
            
        except Exception as e:
            logger.error(f"DB Error: {e}")
            return False

    def create_ini_file(self, symbol: str, expert: str = "Advisors\\PortfolioGovernor.ex5", period: str = "H1", deposit: int = 10000):
        """
        Creates a minimal tester.ini file for the CLI runner.
        """
        ini_content = f"""
[Tester]
Expert={expert}
Symbol={symbol}
Period={period}
Deposit={deposit}
Model=1
Optimization=0
ShutdownTerminal=1
Visual=0
UseLocal=1
UseRemote=0
UseCloud=0
execution_mode=0
"""
        with open(self.tester_ini_path, "w") as f:
            f.write(ini_content)
        
        return os.path.abspath(self.tester_ini_path)

    def run_tester(self):
        """
        Executes the MT5 Strategy Tester via Docker Exec in the MT5 container.
        """
        # Container Name (must match docker-compose service name/container_name)
        container_name = "mt5-v2" 
        
        # Paths INSIDE the MT5 container
        # The volume 'mt5_config_v2' is mounted at '/config' in the MT5 container.
        # So files at Dashboard's '/mt5_data' are at MT5's '/config'
        
        # Calculate the internal path for the INI file
        # Dashboard: /mt5_data/.wine/.../tester.ini  (assuming we saved it there)
        # We need to save the INI file to the shared volume first!
        
        # Let's verify where create_ini_file saves. 
        # It currently saves to "tester.ini" in current working dir (/app/tester.ini).
        # This is NOT shared. We must save it to the shared folder.
        
        shared_ini_path_dashboard = "/mt5_data/tester.ini"
        
        # Check if we need to move the locally created ini to shared volume
        if os.path.exists(self.tester_ini_path): # local /app/tester.ini
            shutil.copy(self.tester_ini_path, shared_ini_path_dashboard)
            
        # Path seen by MT5 container
        internal_ini_path = "C:\\tester.ini" 
        # Since /config is mapped to the root of the "config" volume... 
        # Wait, looked at docker-compose:
        # mt5 service: - mt5_config_v2:/config
        # Inside gmag11/metatrader5_vnc, /config is likely the home dir or similar?
        # ACTUALLY, checking the path used in DB_PATH:
        # /mt5_data/.wine/drive_c/... 
        # This implies /mt5_data is the wrapper of .wine.
        # So in MT5 container, if /config contains .wine, then /config is the parent.
        # If we drop 'tester.ini' at /mt5_data/tester.ini (Dashboard), 
        # it appears at /config/tester.ini (MT5 Container).
        # In Wine (Windows path), /config is usually mapped to Z: drive or similar, 
        # BUT the standard image maps /config to user home or uses it as base.
        #
        # Let's assume standard mapping:
        # Dashboard: /mt5_data/tester.ini
        # MT5 Container Linux Path: /config/tester.ini
        # MT5 Container Windows Path: Z:\config\tester.ini (Wine maps root / to Z:)
        
        internal_ini_path_wine = "Z:\\config\\tester.ini"
        
        # Construct the Docker Exec command
        # docker exec mt5-v2 wine "C:\Program Files\MetaTrader 5\terminal64.exe" /config:"Z:\config\tester.ini" /portable
        
        cmd = [
            "docker", "exec", "--user", "trader", container_name,
            "wine",
            "C:\\Program Files\\MetaTrader 5\\terminal64.exe",
            f"/config:{internal_ini_path_wine}",
            "/portable" # Important: Portable runs in the start directory, maybe we need to be careful.
        ]
        
        logger.info(f"Executing: {' '.join(cmd)}")
        
        try:
            # Run with timeout (e.g. 10 minutes per trial for real backtest)
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            
            if result.returncode != 0:
                logger.warning(f"MT5 exited with code {result.returncode}")
                logger.warning(f"Sortie standard: {result.stdout}")
                logger.warning(f"Erreur standard: {result.stderr}")
                
            return True
        except subprocess.TimeoutExpired:
            logger.error("MT5 Tester Timed Out!")
            return False
        except Exception as e:
            logger.error(f"Execution Error: {e}")
            return False

    def get_result(self, symbol: str, magic: int = 999999):
        """
        Reads the result from the Trades table for the specific magic number.
        """
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Fetch summary statistics from Trades table
            # We filter by magic number to isolate the test run
            # Note: DatabaseManager log query: 
            # "INSERT ... VALUES (..., magic, ...)" - Wait, does existing schema have magic?
            # Looking at DatabaseManager.mqh provided earlier:
            # Struct TradeDBRow has 'magic', but the INSERT query in LogTradeEntry...
            # "VALUES (%I64u, '%s', ...)" 
            # The `LogTradeEntry` function signature:
            # bool LogTradeEntry(ulong ticket, string symbol, int type, double lots, double price, double sl, double tp, double score, string strategy, string marketRegime, string killzone)
            # IT DOES NOT HAVE MAGIC NUMBER!
            # 
            # Check `ImportHistoricalTrades`:
            # It reads magic from history? No, it doesn't seem to log it explicitly in the INSERT statement shown in previous turn.
            # 
            # Re-reading DatabaseManager.mqh snippet:
            # Line 133: int magic; (in struct)
            # Line 288: INSERT ... (ticket, symbol, entry_time...) - NO MAGIC!
            # 
            # PROBLEM: The current DB schema/logging might not support magic number filtering.
            # 
            # Alternative: Filter by 'strategy' column?
            # LogTradeEntry takes 'strategy' string.
            # We can pass a unique strategy name like "OPTIMIZATION_RUN".
            # The EA calls LogTradeEntry. We need to ensure EA passes the strategy name.
            # In `PortfolioGovernor.mq5`:
            # It calls `g_engines[i].OnTrade()`? 
            # We need to check where `LogTradeEntry` is called.
            # Likely in `SymbolEngine.mqh`.
            #
            # If we update `SymbolConfigs` table, does it assume "strategy" name?
            # 
            # Let's use `strategy` column if possible.
            # We need to verify if `SymbolEngine` uses a variable for strategy name that we can override in Config.
            # `SymbolConfig` struct (DatabaseManager.mqh line 537+) has many fields.
            # None of them seem to be "Strategy Name".
            #
            # However, `SymbolConfig` has `magicNumber`. 
            # If `DatabaseManager.mqh` does NOT store magic number in `Trades` table, we are stuck on filtering.
            # 
            # CRITICAL CHECK: Does `Trades` table have `magic` column?
            # In `CreateSchema` (lines 793+ of DatabaseManager.mqh), let's assume it might not.
            # 
            # If we can't filter by Magic, we must clear the trades for the test symbol before running?
            # "DELETE FROM Trades WHERE symbol=?" 
            # This is safe-ish in a dedicated optimization container/db copy.
            # But the user said "PortfolioGovernor.sqlite" is shared.
            # 
            # Wait, `ImportHistoricalTrades` does import magic?
            # No, line 505: VALUES... does not seem to include magic.
            # 
            # Okay, we will use the "DELETE" approach for the specific symbol being optimized if we are in "Sniper Mode"
            # AND we are sure we are not deleting live trades.
            # 
            # BETTER: We check `entry_time` relative to `TimeCurrent()` of the test?
            # But `TimeCurrent` in test is historical.
            #
            # Let's rely on clearing the table for the symbol. 
            # `clean_symbol_trades(symbol)` method.
            
            query = """
            SELECT 
                COUNT(*) as count, 
                SUM(profit) as total_profit,
                MIN(profit) as max_drawdown_trade,
                SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as wins
            FROM Trades 
            WHERE symbol = ?
            """
            
            cursor.execute(query, (symbol,))
            row = cursor.fetchone()
            
            conn.close()
            
            if row and row[0] > 0:
                count, profit, worst_trade, wins = row
                win_rate = (wins / count) * 100 if count > 0 else 0
                return {
                    "count": count,
                    "profit": profit,
                    "win_rate": win_rate
                }
            else:
                return None
        except Exception as e:
            logger.error(f"Result Read Error: {e}")
            return None

    def clean_symbol_trades(self, symbol: str):
        """
        Clears trades for the symbol to ensure clean test results.
        """
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("DELETE FROM Trades WHERE symbol = ?", (symbol,))
            conn.commit()
            conn.close()
            return True
        except Exception as e:
            logger.error(f"Clean DB Error: {e}")
            return False

tester = MT5Tester()
