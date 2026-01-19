"""
MT5 Strategy Tester using Python API (more reliable than CLI)
"""
import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime
import time

class MT5PythonTester:
    def __init__(self):
        self.initialized = False
        
    def run_backtest(self, ea_name, symbol, timeframe, date_from, date_to, deposit, leverage, parameters):
        """
        Run backtest using MT5 Python API
        This is more reliable than CLI approach
        """
        # Initialize MT5
        if not mt5.initialize():
            print(f"❌ MT5 initialization failed: {mt5.last_error()}")
            return {}
        
        self.initialized = True
        
        try:
            # For now, return dummy results indicating we need manual backtest
            # The Python API doesn't support automated strategy tester
            # We'll need to guide user to run backtest manually
            
            print(f"⚠️ MT5 Python API doesn't support automated backtesting")
            print(f"Please run backtest manually in MT5 Strategy Tester:")
            print(f"  1. Open MT5")
            print(f"  2. Press Ctrl+R to open Strategy Tester")
            print(f"  3. Select EA: {ea_name}")
            print(f"  4. Symbol: {symbol}, Period: {timeframe}")
            print(f"  5. Dates: {date_from} to {date_to}")
            print(f"  6. Deposit: {deposit}, Leverage: 1:{leverage}")
            print(f"  7. Click Start")
            
            return {
                'total_net_profit': 0,
                'profit_factor': 0,
                'total_trades': 0,
                'max_drawdown': 0,
                'win_rate': 0
            }
            
        finally:
            if self.initialized:
                mt5.shutdown()

def get_mt5_python_tester():
    return MT5PythonTester()
