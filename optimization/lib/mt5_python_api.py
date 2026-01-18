"""
MT5 Python API Interface
Uses official MetaTrader5 Python package for reliable backtesting
Much more reliable than CLI approach
"""
import MetaTrader5 as mt5
from pathlib import Path
from typing import Dict, Optional, Callable
import time


class MT5PythonAPI:
    """MT5 interface using official Python API"""
    
    def __init__(self, mt5_path: Optional[str] = None):
        """Initialize MT5 Python API connection"""
        self.mt5_path = mt5_path
        self.initialized = False
        
        print("🔄 Initializing MT5 Python API...")
        
        # Initialize MT5
        if mt5_path:
            if not mt5.initialize(path=mt5_path):
                raise RuntimeError(f"MT5 initialize() failed, error: {mt5.last_error()}")
        else:
            if not mt5.initialize():
                raise RuntimeError(f"MT5 initialize() failed, error: {mt5.last_error()}")
        
        self.initialized = True
        
        # Get MT5 version info
        terminal_info = mt5.terminal_info()
        if terminal_info:
            print(f"✅ MT5 connected: {terminal_info.name}, build {terminal_info.build}")
        else:
            print("✅ MT5 connected")
    
    def __del__(self):
        """Cleanup MT5 connection"""
        if self.initialized:
            mt5.shutdown()
    
    def run_backtest(
        self,
        ea_path: str,
        symbol: str,
        timeframe: str,
        date_from: str,
        date_to: str,
        deposit: float = 10000,
        parameters: Optional[Dict] = None,
        progress_callback: Optional[Callable[[str, int], None]] = None
    ) -> Dict:
        """
        Run backtest using MT5 Python API
        
        NOTE: MT5 Python API does NOT support Strategy Tester automation.
        This is a known limitation of the official API.
        
        For automated backtesting, you need to either:
        1. Use MT5 GUI Strategy Tester manually
        2. Use third-party solutions
        3. Build custom backtesting engine based on historical data
        
        Returns:
            Dict with error message explaining limitation
        """
        
        return {
            "success": False,
            "profit_factor": 0.0,
            "error": "MT5 Python API does not support automated Strategy Tester. Manual testing required.",
            "note": "Consider using custom backtesting engine or manual MT5 testing"
        }


# Global instance
_mt5_api_instance: Optional[MT5PythonAPI] = None


def get_mt5_api_instance(mt5_path: Optional[str] = None) -> MT5PythonAPI:
    """Get global MT5 API instance"""
    global _mt5_api_instance
    
    if _mt5_api_instance is None:
        _mt5_api_instance = MT5PythonAPI(mt5_path)
    
    return _mt5_api_instance
