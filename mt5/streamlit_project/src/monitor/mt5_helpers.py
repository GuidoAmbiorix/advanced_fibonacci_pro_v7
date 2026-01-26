"""
MT5 Helper Functions - Compatibility layer for global variables API.
"""

from src.mt5_compat import mt5, MT5_AVAILABLE
from typing import Optional, Dict
import time
from ..logger import get_logger

logger = get_logger(__name__)

# Cache for global variables
_gv_cache: Dict[str, float] = {}
_cache_timestamp: float = 0
_CACHE_TTL = 2  # seconds


def refresh_gv_cache() -> bool:
    """
    Force refresh of global variables cache.
    
    Returns:
        True if successful
    """
    global _gv_cache, _cache_timestamp
    
    try:
        gv_tuple = mt5.global_variables_get()
        if gv_tuple:
            _gv_cache = dict(gv_tuple)
            _cache_timestamp = time.time()
            return True
        else:
            logger.warning("No global variables returned from MT5")
            _gv_cache = {}
            return False
    except Exception as e:
        logger.error(f"Error refreshing GV cache: {e}")
        return False


def global_variable_exists(var_name: str, use_cache: bool = True) -> bool:
    """
    Check if global variable exists.
    Compatible replacement for mt5.global_variable_check() which doesn't exist.
    
    Args:
        var_name: Variable name to check
        use_cache: Use cached values (reduces API calls)
        
    Returns:
        True if variable exists
    """
    global _gv_cache, _cache_timestamp
    
    current_time = time.time()
    
    # Refresh cache if expired or not using cache
    if not use_cache or (current_time - _cache_timestamp) > _CACHE_TTL:
        refresh_gv_cache()
    
    return var_name in _gv_cache


def global_variable_get_safe(var_name: str, default: float = 0.0, use_cache: bool = True) -> float:
    """
    Safely get global variable value.
    
    Args:
        var_name: Variable name
        default: Default value if not found
        use_cache: Use cached values
        
    Returns:
        Variable value or default
    """
    global _gv_cache, _cache_timestamp
    
    current_time = time.time()
    
    # Refresh cache if expired or not using cache
    if not use_cache or (current_time - _cache_timestamp) > _CACHE_TTL:
        refresh_gv_cache()
    
    return _gv_cache.get(var_name, default)


def get_all_global_variables(prefix: str = "") -> Dict[str, float]:
    """
    Get all global variables, optionally filtered by prefix.
    
    Args:
        prefix: Optional prefix filter
        
    Returns:
        Dict mapping variable names to values
    """
    try:
        gv_tuple = mt5.global_variables_get()
        if not gv_tuple:
            return {}
        
        gv_dict = dict(gv_tuple)
        
        if prefix:
            gv_dict = {k: v for k, v in gv_dict.items() if k.startswith(prefix)}
        
        return gv_dict
        
    except Exception as e:
        logger.error(f"Error getting global variables: {e}")
        return {}
