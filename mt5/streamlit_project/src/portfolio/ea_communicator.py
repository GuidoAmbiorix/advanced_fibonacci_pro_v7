"""
EA Communicator - Dual communication with MT5 Expert Advisors.
Syncs active portfolio via file and global variables.
"""

import os
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
from src.mt5_compat import mt5, MT5_AVAILABLE
class EACommunicator:
    """
    Handles communication between Portfolio Governor and MT5 EAs.
    
    Two communication channels:
    1. File-based: active_symbols.txt in MQL5/Files/
    2. Global variables: GovernorMultiplier_<SYMBOL>
    """
    
    ACTIVE_SYMBOLS_FILENAME = "active_symbols.txt"
    GOVERNOR_VAR_PREFIX = "GovernorMultiplier_"
    
    def __init__(self, mt5_data_path: Optional[Path] = None):
        """
        Initialize EA communicator.
        
        Args:
            mt5_data_path: Path to MT5 data folder (auto-detected if None)
        """
        self.mt5_data_path = mt5_data_path or self._detect_mt5_data_path()
        self.last_sync_time: Optional[datetime] = None
        self.last_sync_result: Dict = {}
    
    def _detect_mt5_data_path(self) -> Optional[Path]:
        """
        Detect MT5 terminal data path.
        
        Returns path to MQL5/Files/ directory.
        """
        try:
            terminal_info = mt5.terminal_info()
            if terminal_info:
                data_path = Path(terminal_info.data_path)
                files_path = data_path / "MQL5" / "Files"
                if files_path.exists():
                    return files_path
        except Exception:
            pass
        
        return None
    
    def write_active_symbols_file(self, active_symbols: List[str]) -> bool:
        """
        Write active symbols to file for EAs to read.
        
        File format:
        # Portfolio Governor - Active Symbols
        # Updated: 2026-01-22 15:42:00
        EURUSD=1.0
        USDJPY=1.0
        XAUUSD=1.0
        US30=1.0
        
        Returns:
            True if file was written successfully
        """
        if not self.mt5_data_path:
            return False
        
        file_path = self.mt5_data_path / self.ACTIVE_SYMBOLS_FILENAME
        
        try:
            now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            lines = [
                "# Portfolio Governor - Active Symbols",
                f"# Updated: {now}",
                f"# Count: {len(active_symbols)}",
                ""
            ]
            
            for symbol in sorted(active_symbols):
                lines.append(f"{symbol}=1.0")
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines))
            
            return True
            
        except Exception as e:
            print(f"Error writing active symbols file: {e}")
            return False
    
    def set_governor_multipliers(
        self,
        active_symbols: List[str],
        all_symbols: List[str]
    ) -> Dict[str, bool]:
        """
        Set GovernorMultiplier global variables in MT5.
        
        Active symbols get 1.0, inactive get 0.0.
        
        Args:
            active_symbols: List of symbols to activate
            all_symbols: List of all available symbols
            
        Returns:
            Dict mapping symbol to success status
        """
        results = {}
        active_set = set(active_symbols)
        
        for symbol in all_symbols:
            var_name = f"{self.GOVERNOR_VAR_PREFIX}{symbol}"
            value = 1.0 if symbol in active_set else 0.0
            
            try:
                # Set global variable in MT5
                success = mt5.global_variable_set(var_name, value)
                results[symbol] = success
            except Exception as e:
                print(f"Error setting {var_name}: {e}")
                results[symbol] = False
        
        return results
    
    def get_governor_multiplier(self, symbol: str) -> float:
        """
        Get current GovernorMultiplier for a symbol.
        
        Returns -1.0 if variable doesn't exist.
        """
        var_name = f"{self.GOVERNOR_VAR_PREFIX}{symbol}"
        
        try:
            if mt5.global_variable_check(var_name):
                return mt5.global_variable_get(var_name)
            return -1.0
        except Exception:
            return -1.0
    
    def get_all_governor_multipliers(self, symbols: List[str]) -> Dict[str, float]:
        """
        Get all GovernorMultiplier values for symbols.
        """
        return {symbol: self.get_governor_multiplier(symbol) for symbol in symbols}
    
    def sync_with_mt5(
        self,
        active_group: List[str],
        all_symbols: List[str]
    ) -> Dict:
        """
        Full sync with MT5 - file and global variables.
        
        Args:
            active_group: List of 4 active symbols
            all_symbols: List of all 20 symbols
            
        Returns:
            Dict with sync status and details
        """
        result = {
            "success": True,
            "timestamp": datetime.now(),
            "active_symbols": active_group,
            "file_written": False,
            "global_vars": {},
            "errors": []
        }
        
        # 1. Write file
        file_ok = self.write_active_symbols_file(active_group)
        result["file_written"] = file_ok
        if not file_ok:
            result["errors"].append("Failed to write active_symbols.txt")
            result["success"] = False
        
        # 2. Set global variables
        var_results = self.set_governor_multipliers(active_group, all_symbols)
        result["global_vars"] = var_results
        
        failed_vars = [s for s, ok in var_results.items() if not ok]
        if failed_vars:
            result["errors"].append(f"Failed to set vars: {failed_vars}")
            result["success"] = False
        
        # Store result
        self.last_sync_time = result["timestamp"]
        self.last_sync_result = result
        
        return result
    
    def read_active_symbols_file(self) -> List[str]:
        """
        Read currently active symbols from file.
        
        Returns list of active symbols.
        """
        if not self.mt5_data_path:
            return []
        
        file_path = self.mt5_data_path / self.ACTIVE_SYMBOLS_FILENAME
        
        if not file_path.exists():
            return []
        
        try:
            symbols = []
            with open(file_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if '=' in line:
                        symbol, value = line.split('=', 1)
                        if float(value.strip()) > 0:
                            symbols.append(symbol.strip())
            return symbols
        except Exception as e:
            print(f"Error reading active symbols file: {e}")
            return []
    
    def clear_all_multipliers(self, symbols: List[str]) -> bool:
        """
        Set all GovernorMultipliers to 0.0 (pause all trading).
        """
        try:
            for symbol in symbols:
                var_name = f"{self.GOVERNOR_VAR_PREFIX}{symbol}"
                mt5.global_variable_set(var_name, 0.0)
            return True
        except Exception as e:
            print(f"Error clearing multipliers: {e}")
            return False
    
    def get_sync_status(self) -> Dict:
        """
        Get current sync status.
        """
        return {
            "last_sync": self.last_sync_time,
            "last_result": self.last_sync_result,
            "file_path": str(self.mt5_data_path / self.ACTIVE_SYMBOLS_FILENAME) if self.mt5_data_path else None,
            "mt5_connected": mt5.terminal_info() is not None
        }
