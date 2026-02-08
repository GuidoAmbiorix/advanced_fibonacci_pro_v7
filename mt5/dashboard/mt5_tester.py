import os
import subprocess
import sqlite3
import time
import json
import logging
from datetime import datetime, timedelta

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("MT5Tester")

class MT5Tester:
    def __init__(self):
        # Path to the shared database
        self.db_path = os.getenv('DB_PATH', '/mt5_data/.wine/drive_c/users/abc/AppData/Roaming/MetaQuotes/Terminal/Common/Files/PortfolioGovernor.sqlite')

        # MT5 Backtest configuration
        self.ea_name = "portafolio_manager\\Portfolio_Governor.ex5"
        self.backtest_image = "mt5-backtest:latest"
        self.results_dir = "/app/backtest_results"

        # Backtest date range
        self.default_backtest_days = 90

    def prepare_db(self, params: dict, symbol: str):
        """Updates the Database with the specific parameters for this trial."""
        if not os.path.exists(self.db_path):
            logger.error(f"Database not found at {self.db_path}")
            return False

        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            cursor.execute("PRAGMA table_info(SymbolConfigs)")
            columns_info = cursor.fetchall()
            existing_columns = {info[1] for info in columns_info}

            cols = []
            values = []

            for key, value in params.items():
                if key in existing_columns:
                    cols.append(f"{key} = ?")
                    values.append(value)

            if not cols:
                logger.warning(f"No valid parameters to update for {symbol}")
                return True

            sql = f"UPDATE SymbolConfigs SET {', '.join(cols)} WHERE symbol = ?"
            values.append(symbol)

            cursor.execute(sql, values)
            cursor.execute("INSERT OR REPLACE INTO GovernorState (key, value_num, updated_at) VALUES ('OPTIMIZATION_ACTIVE', 1, ?)", (int(time.time()),))

            conn.commit()
            conn.close()
            return True

        except Exception as e:
            logger.error(f"DB Error: {e}")
            return False

    def create_ini_file(self, symbol: str, period: str = "H1", backtest_days: int = None):
        """Creates tester.ini with proper MT5 backtest configuration."""
        if backtest_days is None:
            backtest_days = self.default_backtest_days

        end_date = datetime.now()
        start_date = end_date - timedelta(days=backtest_days)

        from_date = start_date.strftime("%Y.%m.%d")
        to_date = end_date.strftime("%Y.%m.%d")

        ini_content = f"""[Tester]
Expert={self.ea_name}
Symbol={symbol}
Period={period}
FromDate={from_date}
ToDate={to_date}
Model=1
Deposit=10000
Currency=USD
Leverage=1:100
ExecutionMode=0
Optimization=0
ShutdownTerminal=1
Visual=0
UseLocal=1
UseRemote=0
UseCloud=0
Report=backtest_report
ReplaceReport=1
"""

        ini_path = os.path.join(self.results_dir, "Config", "tester.ini")
        os.makedirs(os.path.dirname(ini_path), exist_ok=True)

        with open(ini_path, "w") as f:
            f.write(ini_content)

        logger.info(f"Created tester.ini: {symbol} {period} from {from_date} to {to_date}")
        return ini_path

    def run_tester(self, symbol: str, period: str = "H1", backtest_days: int = None):
        """
        Runs MT5 Strategy Tester using automated backtest container.
        Based on S-A-RB05/MetaTraderContainer approach.
        """
        # Create ini file
        self.create_ini_file(symbol, period, backtest_days)

        # Run automated backtest container
        cmd = [
            "docker", "run", "--rm",
            # Mount configurations
            "-v", f"{self.results_dir}/Config:/MetaTrader/Config:ro",
            # Mount EA files
            "-v", "/root/advanced_fibonacci_pro_v7/mt5/portafolio_manager:/MetaTrader/EA:ro",
            # Mount database
            "-v", "advanced_fibonacci_pro_v7_mt5_config_v2:/MetaTrader/Data:ro",
            # Mount results output
            "-v", f"{self.results_dir}/Report:/MetaTrader/Report",
            # Run backtest image
            self.backtest_image
        ]

        logger.info(f"Running automated MT5 backtest: {symbol} {period}")

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)

            if result.returncode != 0:
                logger.warning(f"Backtest container exited with code {result.returncode}")
                logger.debug(f"STDOUT: {result.stdout}")
                logger.debug(f"STDERR: {result.stderr}")
                return False

            logger.info(f"Automated backtest completed for {symbol}")
            logger.debug(f"Output: {result.stdout}")

            return True

        except subprocess.TimeoutExpired:
            logger.error("Backtest Timed Out!")
            return False
        except Exception as e:
            logger.error(f"Execution Error: {e}")
            return False

    def get_result(self, symbol: str, magic: int = None):
        """Reads results from database."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            query = """
            SELECT
                COUNT(*) as count,
                SUM(profit) as total_profit,
                SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as wins
            FROM Trades
            WHERE symbol = ?
            """

            cursor.execute(query, (symbol,))
            row = cursor.fetchone()

            conn.close()

            if row and row[0] > 0:
                count, profit, wins = row
                win_rate = (wins / count) * 100 if count > 0 else 0

                logger.info(f"Results: {count} trades, ${profit:.2f} profit, {win_rate:.1f}% win rate")

                return {
                    "count": count,
                    "profit": profit,
                    "win_rate": win_rate
                }
            else:
                logger.warning(f"No trades found for {symbol}")
                return None

        except Exception as e:
            logger.error(f"Result Read Error: {e}")
            return None

    def clean_symbol_trades(self, symbol: str):
        """Clears trades for the symbol."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("DELETE FROM Trades WHERE symbol = ?", (symbol,))
            deleted = cursor.rowcount
            conn.commit()
            conn.close()

            if deleted > 0:
                logger.info(f"Cleaned {deleted} trades for {symbol}")

            return True
        except Exception as e:
            logger.error(f"Clean DB Error: {e}")
            return False

# Singleton instance
tester = MT5Tester()
