"""
Governor Monitor - Reads Portfolio Governor GlobalVariables in real-time.
Tracks DD, PF, exposure, risk multipliers, and trading status.
"""

import MetaTrader5 as mt5
from typing import Dict, Optional
from datetime import datetime
from ..logger import get_logger
from .mt5_helpers import (
    global_variable_exists,
    global_variable_get_safe,
    get_all_global_variables
)

logger = get_logger(__name__)


class GovernorMonitor:
    """
    Monitors Portfolio Governor status via MT5 GlobalVariables.
    
    Reads variables like:
    - PG_GovernorActive
    - PG_TotalExposure
    - PG_CurrentDD
    - PG_RollingPF
    - PG_RiskMultiplier
    - PG_TradingEnabled
    - PG_GroupUSD, PG_GroupJPY, etc.
    """
    
    # GlobalVariable keys (matching PortfolioGlobals.mqh)
    GV_GOVERNOR_ACTIVE = "PG_GovernorActive"
    GV_TOTAL_EXPOSURE = "PG_TotalExposure"
    GV_CURRENT_DD = "PG_CurrentDD"
    GV_PEAK_EQUITY = "PG_PeakEquity"
    GV_ROLLING_PF = "PG_RollingPF"
    GV_RISK_MULTIPLIER = "PG_RiskMultiplier"
    GV_TRADING_ENABLED = "PG_TradingEnabled"
    GV_LAST_UPDATE = "PG_LastUpdate"
    
    # Group risk keys
    GV_GROUP_USD = "PG_GroupUSD"
    GV_GROUP_JPY = "PG_GroupJPY"
    GV_GROUP_GBP = "PG_GroupGBP"
    GV_GROUP_METALS = "PG_GroupMetals"
    GV_GROUP_INDICES = "PG_GroupIndices"
    
    # Daily/Weekly limits
    GV_DAILY_DD = "PG_DailyDD"
    GV_WEEKLY_DD = "PG_WeeklyDD"
    
    def __init__(self):
        """Initialize Governor Monitor."""
        self.last_check = None
        self.cached_metrics = {}
        
    def is_governor_active(self) -> bool:
        """
        Check if Portfolio Governor is running.
        
        Returns:
            True if Governor is active (GV exists and = 1.0)
        """
        try:
            if mt5.global_variable_check(self.GV_GOVERNOR_ACTIVE):
                value = mt5.global_variable_get(self.GV_GOVERNOR_ACTIVE)
                return value == 1.0
            return False
        except Exception as e:
            logger.error(f"Error checking Governor active status: {e}")
            return False
    
    def get_governor_metrics(self) -> Dict:
        """
        Get all Governor metrics from GlobalVariables.
        
        Returns:
            Dict with metrics:
            - active: bool
            - dd: float (current drawdown %)
            - pf: float (rolling profit factor)
            - exposure: float (total exposure %)
            - risk_multiplier: float (0.0 to 1.0)
            - trading_enabled: bool
            - last_update: datetime or None
            - peak_equity: float
            - daily_dd: float
            - weekly_dd: float
        """
        metrics = {
            'active': False,
            'dd': 0.0,
            'pf': 0.0,
            'exposure': 0.0,
            'risk_multiplier': 1.0,
            'trading_enabled': False,
            'last_update': None,
            'peak_equity': 0.0,
            'daily_dd': 0.0,
            'weekly_dd': 0.0,
            'status': 'OFFLINE'
        }
        
        try:
            # Check if Governor is active
            metrics['active'] = self.is_governor_active()
            
            if not metrics['active']:
                metrics['status'] = 'OFFLINE'
                return metrics
            
            # Read all metrics
            metrics['dd'] = self._get_gv(self.GV_CURRENT_DD, 0.0)
            metrics['pf'] = self._get_gv(self.GV_ROLLING_PF, 0.0)
            metrics['exposure'] = self._get_gv(self.GV_TOTAL_EXPOSURE, 0.0)
            metrics['risk_multiplier'] = self._get_gv(self.GV_RISK_MULTIPLIER, 1.0)
            metrics['peak_equity'] = self._get_gv(self.GV_PEAK_EQUITY, 0.0)
            metrics['daily_dd'] = self._get_gv(self.GV_DAILY_DD, 0.0)
            metrics['weekly_dd'] = self._get_gv(self.GV_WEEKLY_DD, 0.0)
            
            # Trading enabled
            trading_enabled_val = self._get_gv(self.GV_TRADING_ENABLED, 0.0)
            metrics['trading_enabled'] = (trading_enabled_val == 1.0)
            
            # Last update timestamp
            last_update_ts = self._get_gv(self.GV_LAST_UPDATE, 0.0)
            if last_update_ts > 0:
                metrics['last_update'] = datetime.fromtimestamp(last_update_ts)
            
            # Determine status
            if not metrics['trading_enabled']:
                metrics['status'] = 'PAUSED'
            elif metrics['dd'] >= 8.0:  # DD threshold
                metrics['status'] = 'PAUSED_DD'
            else:
                metrics['status'] = 'ACTIVE'
            
            self.last_check = datetime.now()
            self.cached_metrics = metrics
            
            logger.debug(f"Governor metrics: DD={metrics['dd']:.1f}%, PF={metrics['pf']:.2f}, Status={metrics['status']}")
            
        except Exception as e:
            logger.error(f"Error getting Governor metrics: {e}")
            metrics['status'] = 'ERROR'
        
        return metrics
    
    def get_group_risks(self) -> Dict[str, float]:
        """
        Get correlation group risk allocations.
        
        Returns:
            Dict mapping group name to risk %:
            {'USD': 0.6, 'JPY': 0.4, 'GBP': 0.3, 'Metals': 0.5, 'Indices': 0.2}
        """
        groups = {
            'USD': self._get_gv(self.GV_GROUP_USD, 0.0),
            'JPY': self._get_gv(self.GV_GROUP_JPY, 0.0),
            'GBP': self._get_gv(self.GV_GROUP_GBP, 0.0),
            'Metals': self._get_gv(self.GV_GROUP_METALS, 0.0),
            'Indices': self._get_gv(self.GV_GROUP_INDICES, 0.0)
        }
        
        logger.debug(f"Group risks: {groups}")
        return groups
    
    def get_last_update_time(self) -> Optional[datetime]:
        """
        Get timestamp of last Governor update.
        
        Returns:
            datetime of last update, or None if never updated
        """
        try:
            ts = self._get_gv(self.GV_LAST_UPDATE, 0.0)
            if ts > 0:
                return datetime.fromtimestamp(ts)
        except Exception as e:
            logger.error(f"Error getting last update time: {e}")
        
        return None
    
    def get_age_seconds(self) -> Optional[int]:
        """
        Get age in seconds since last Governor update.
        
        Returns:
            Seconds since last update, or None if never updated
        """
        last_update = self.get_last_update_time()
        if last_update:
            return int((datetime.now() - last_update).total_seconds())
        return None
    
    def _get_gv(self, var_name: str, default: float = 0.0) -> float:
        """
        Safely get GlobalVariable value.
        
        Args:
            var_name: Variable name
            default: Default value if not found
            
        Returns:
            Variable value or default
        """
        try:
            if mt5.global_variable_check(var_name):
                return mt5.global_variable_get(var_name)
        except Exception as e:
            logger.warning(f"Error reading GV '{var_name}': {e}")
        
        return default
    
    def get_all_governor_variables(self) -> Dict[str, float]:
        """
        Get ALL Governor-related GlobalVariables.
        
        Returns:
            Dict mapping variable name to value
        """
        all_vars = {}
        
        try:
            # Get all global variables from MT5
            gv_tuple = mt5.global_variables_get()
            
            if gv_tuple:
                for var_name, var_value in gv_tuple:
                    # Filter for Governor variables (prefix PG_)
                    if var_name.startswith("PG_"):
                        all_vars[var_name] = var_value
                        
        except Exception as e:
            logger.error(f"Error getting all Governor variables: {e}")
        
        return all_vars
