"""
EA Status Checker - Detects which Symbol Engines are active/inactive.
Uses GlobalVariable timestamps and magic numbers to determine EA status.
"""

import MetaTrader5 as mt5
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from ..logger import get_logger

logger = get_logger(__name__)


class EAStatusChecker:
    """
    Detects which Symbol Engine EAs are currently running.
    
    Uses multiple detection methods:
    1. GovernorMultiplier_<SYMBOL> global variables (active if 1.0, inactive if 0.0)
    2. Open positions with magic numbers
    3. Timestamp-based activity detection (if EA updates GVs regularly)
    """
    
    # Expected symbols (configure based on your setup)
    # These are the symbols you typically trade with Symbol Engines
    DEFAULT_SYMBOLS = [
        "XAUUSD", "NAS100", "GBPJPY", "EURUSD",
        "USDJPY", "GBPUSD", "EURGBP", "AUDUSD",
        "NZDUSD", "USDCAD", "USDCHF", "EURJPY"
    ]
    
    # Magic number ranges for Symbol Engines
    # Typically each symbol has unique magic (e.g., 100001, 100002, etc.)
    MAGIC_NUMBER_START = 100001
    MAGIC_NUMBER_END = 100020
    
    # Timeout for considering EA "offline" (seconds)
    ACTIVITY_TIMEOUT = 120  # 2 minutes without activity = offline
    
    def __init__(self, symbols: Optional[List[str]] = None):
        """
        Initialize EA Status Checker.
        
        Args:
            symbols: List of symbols to monitor (uses DEFAULT_SYMBOLS if None)
        """
        self.symbols = symbols or self.DEFAULT_SYMBOLS
        self.last_check = None
        
    def get_ea_status(self, symbol: str) -> Dict:
        """
        Get status of a specific Symbol Engine.
        
        Args:
            symbol: Symbol name (e.g., "XAUUSD")
            
        Returns:
            Dict with keys:
            - symbol: str
            - active: bool (True if EA is running)
            - governor_multiplier: float (1.0 = enabled, 0.0 = disabled)
            - has_positions: bool
            - position_count: int
            - magic_number: int or None
            - last_update: datetime or None
            - status: str ('ACTIVE', 'INACTIVE', 'UNKNOWN')
            - risk_percent: float (if available)
        """
        status = {
            'symbol': symbol,
            'active': False,
            'governor_multiplier': 0.0,
            'has_positions': False,
            'position_count': 0,
            'magic_number': None,
            'last_update': None,
            'status': 'UNKNOWN',
            'risk_percent': 0.0
        }
        
        try:
            # 1. Check GovernorMultiplier
            var_name = f"GovernorMultiplier_{symbol}"
            if mt5.global_variable_check(var_name):
                status['governor_multiplier'] = mt5.global_variable_get(var_name)
                
            # 2. Check for open positions
            positions = mt5.positions_get(symbol=symbol)
            if positions:
                status['has_positions'] = True
                status['position_count'] = len(positions)
                
                # Get magic number from first position
                magic = positions[0].magic
                if self.MAGIC_NUMBER_START <= magic <= self.MAGIC_NUMBER_END:
                    status['magic_number'] = magic
            
            # 3. Determine active status
            # EA is active if:
            # - GovernorMultiplier = 1.0, OR
            # - Has open positions with valid magic number
            if status['governor_multiplier'] == 1.0:
                status['active'] = True
                status['status'] = 'ACTIVE'
            elif status['has_positions'] and status['magic_number']:
                status['active'] = True
                status['status'] = 'ACTIVE'
            else:
                status['active'] = False
                status['status'] = 'INACTIVE'
            
            # 4. Check for EA-specific timestamp (if EA writes one)
            # Format: SE_<SYMBOL>_LastUpdate
            ts_var = f"SE_{symbol}_LastUpdate"
            if mt5.global_variable_check(ts_var):
                ts = mt5.global_variable_get(ts_var)
                if ts > 0:
                    status['last_update'] = datetime.fromtimestamp(ts)
                    
                    # Check if timestamp is recent
                    age = (datetime.now() - status['last_update']).total_seconds()
                    if age > self.ACTIVITY_TIMEOUT:
                        status['active'] = False
                        status['status'] = 'OFFLINE'
            
            logger.debug(f"EA Status {symbol}: {status['status']} (GM={status['governor_multiplier']}, Positions={status['position_count']})")
            
        except Exception as e:
            logger.error(f"Error getting EA status for {symbol}: {e}")
            status['status'] = 'ERROR'
        
        return status
    
    def get_all_ea_statuses(self) -> Dict[str, Dict]:
        """
        Get status of all monitored Symbol Engines.
        
        Returns:
            Dict mapping symbol to status dict
        """
        all_statuses = {}
        
        for symbol in self.symbols:
            all_statuses[symbol] = self.get_ea_status(symbol)
        
        self.last_check = datetime.now()
        return all_statuses
    
    def is_ea_running(self, symbol: str) -> bool:
        """
        Quick check if EA is running.
        
        Args:
            symbol: Symbol name
            
        Returns:
            True if EA is active
        """
        status = self.get_ea_status(symbol)
        return status['active']
    
    def get_active_symbols(self) -> List[str]:
        """
        Get list of symbols with active EAs.
        
        Returns:
            List of symbol names
        """
        all_statuses = self.get_all_ea_statuses()
        return [symbol for symbol, status in all_statuses.items() if status['active']]
    
    def get_inactive_symbols(self) -> List[str]:
        """
        Get list of symbols with inactive EAs.
        
        Returns:
            List of symbol names
        """
        all_statuses = self.get_all_ea_statuses()
        return [symbol for symbol, status in all_statuses.items() if not status['active']]
    
    def get_summary_stats(self) -> Dict:
        """
        Get summary statistics.
        
        Returns:
            Dict with:
            - total_symbols: int
            - active_count: int
            - inactive_count: int
            - total_positions: int
            - last_check: datetime
        """
        all_statuses = self.get_all_ea_statuses()
        
        active_count = sum(1 for s in all_statuses.values() if s['active'])
        total_positions = sum(s['position_count'] for s in all_statuses.values())
        
        return {
            'total_symbols': len(self.symbols),
            'active_count': active_count,
            'inactive_count': len(self.symbols) - active_count,
            'total_positions': total_positions,
            'last_check': self.last_check or datetime.now()
        }
    
    def detect_symbols_from_positions(self) -> List[str]:
        """
        Auto-detect symbols from open positions with EA magic numbers.
        
        Returns:
            List of unique symbols found
        """
        symbols = set()
        
        try:
            positions = mt5.positions_get()
            if positions:
                for pos in positions:
                    if self.MAGIC_NUMBER_START <= pos.magic <= self.MAGIC_NUMBER_END:
                        symbols.add(pos.symbol)
        except Exception as e:
            logger.error(f"Error detecting symbols from positions: {e}")
        
        return sorted(list(symbols))
    
    def detect_symbols_from_global_variables(self) -> List[str]:
        """
        Auto-detect symbols from GovernorMultiplier_ global variables.
        
        Returns:
            List of symbols with Governor multipliers
        """
        symbols = []
        
        try:
            gv_tuple = mt5.global_variables_get()
            if gv_tuple:
                for var_name, var_value in gv_tuple:
                    if var_name.startswith("GovernorMultiplier_"):
                        symbol = var_name.replace("GovernorMultiplier_", "")
                        symbols.append(symbol)
        except Exception as e:
            logger.error(f"Error detecting symbols from GVs: {e}")
        
        return sorted(symbols)
    
    def auto_detect_symbols(self) -> List[str]:
        """
        Auto-detect all symbols being managed by Symbol Engines.
        
        Combines detection from:
        1. GovernorMultiplier variables
        2. Open positions
        3. Default symbol list
        
        Returns:
            Combined list of unique symbols
        """
        symbols = set()
        
        # Method 1: From GlobalVariables
        symbols.update(self.detect_symbols_from_global_variables())
        
        # Method 2: From positions
        symbols.update(self.detect_symbols_from_positions())
        
        # Method 3: Add defaults if nothing found
        if not symbols:
            symbols.update(self.DEFAULT_SYMBOLS)
        
        logger.info(f"Auto-detected {len(symbols)} symbols: {sorted(symbols)}")
        
        return sorted(list(symbols))
