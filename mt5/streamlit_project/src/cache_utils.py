"""
Cache Utilities - Centralized caching helpers for performance optimization.
Provides Streamlit cache decorators and cache management functions.
"""

import streamlit as st
import pandas as pd
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from functools import wraps
import hashlib
import json

from .config import config
from .logger import get_logger

logger = get_logger(__name__)


def get_cache_key(*args, **kwargs) -> str:
    """
    Generate a cache key from arguments.

    Args:
        *args: Positional arguments
        **kwargs: Keyword arguments

    Returns:
        Hash string for cache key
    """
    key_data = {
        'args': str(args),
        'kwargs': str(sorted(kwargs.items()))
    }
    key_str = json.dumps(key_data, sort_keys=True)
    return hashlib.md5(key_str.encode()).hexdigest()


@st.cache_data(ttl=config.SYMBOL_SCORES_CACHE_TTL, show_spinner=False)
def cached_symbol_scores(
    scorer_instance_id: str,
    symbols: tuple,
    performance_data_hash: Optional[str] = None
) -> pd.DataFrame:
    """
    Cached wrapper for symbol scoring.

    Args:
        scorer_instance_id: ID of scorer instance
        symbols: Tuple of symbols to score
        performance_data_hash: Hash of performance data for cache invalidation

    Returns:
        DataFrame of symbol scores

    Note: This is a placeholder that should be called from SymbolScorer
    """
    # This will be imported and used by symbol_scorer
    pass


@st.cache_data(ttl=config.CORRELATION_CACHE_TTL, show_spinner=False)
def cached_correlation_matrix(
    symbols: tuple,
    timeframe: str,
    bars: int,
    timestamp: str
) -> pd.DataFrame:
    """
    Cached wrapper for correlation matrix calculation.

    Args:
        symbols: Tuple of symbols
        timeframe: Timeframe string
        bars: Number of bars
        timestamp: Timestamp for cache invalidation

    Returns:
        Correlation matrix DataFrame
    """
    # This will be imported and used by correlation_engine
    pass


@st.cache_data(ttl=config.GROUPS_CACHE_TTL, show_spinner=False)
def cached_valid_groups(
    symbols: tuple,
    correlation_hash: str,
    config_hash: str
) -> List[tuple]:
    """
    Cached wrapper for group generation.

    Args:
        symbols: Tuple of symbols
        correlation_hash: Hash of correlation matrix
        config_hash: Hash of group generation config

    Returns:
        List of valid groups (as tuples)
    """
    # This will be imported and used by group_generator
    pass


@st.cache_data(ttl=60, show_spinner=False)
def cached_trades_fetch(days: int, timestamp_hour: str) -> pd.DataFrame:
    """
    Cached wrapper for trade fetching.
    Cache invalidates every hour via timestamp_hour parameter.

    Args:
        days: Number of days to fetch
        timestamp_hour: Hour timestamp for cache invalidation

    Returns:
        DataFrame of trades
    """
    from .data_engine import DataEngine
    engine = DataEngine()
    return engine.fetch_trades(days)


@st.cache_data(ttl=300, show_spinner=False)
def cached_ohlc_fetch(
    symbol: str,
    timeframe: int,
    bars: int,
    timestamp_5min: str
) -> pd.DataFrame:
    """
    Cached wrapper for OHLC data fetching.
    Cache invalidates every 5 minutes.

    Args:
        symbol: Symbol name
        timeframe: MT5 timeframe constant
        bars: Number of bars
        timestamp_5min: 5-minute timestamp for cache invalidation

    Returns:
        DataFrame of OHLC data
    """
    from datetime import datetime, timedelta
    from .data_engine import DataEngine

    engine = DataEngine()
    to_date = datetime.now()
    from_date = to_date - timedelta(days=bars // 24)  # Rough estimate

    return engine.fetch_ohlc(symbol, timeframe, from_date, to_date)


def get_timestamp_key(minutes: int = 60) -> str:
    """
    Generate a timestamp key that changes every N minutes.
    Used for time-based cache invalidation.

    Args:
        minutes: Interval in minutes

    Returns:
        Timestamp string
    """
    now = datetime.now()
    interval_start = now - timedelta(
        minutes=now.minute % minutes,
        seconds=now.second,
        microseconds=now.microsecond
    )
    return interval_start.strftime("%Y-%m-%d %H:%M")


@st.cache_resource
def get_singleton_instance(class_name: str, _instance_creator):
    """
    Cache singleton instances across Streamlit reruns.

    Args:
        class_name: Name of the class for cache key
        _instance_creator: Callable that creates the instance

    Returns:
        Singleton instance
    """
    logger.debug(f"Creating cached singleton instance: {class_name}")
    return _instance_creator()


def clear_all_caches():
    """Clear all Streamlit caches."""
    try:
        st.cache_data.clear()
        st.cache_resource.clear()
        logger.info("All caches cleared successfully")
    except Exception as e:
        logger.error(f"Error clearing caches: {e}")


def get_cache_stats() -> Dict[str, Any]:
    """
    Get cache statistics.

    Returns:
        Dict with cache information
    """
    return {
        "cache_enabled": config.CACHE_ENABLED,
        "symbol_scores_ttl": config.SYMBOL_SCORES_CACHE_TTL,
        "correlation_ttl": config.CORRELATION_CACHE_TTL,
        "groups_ttl": config.GROUPS_CACHE_TTL,
        "current_time": datetime.now().isoformat()
    }


# Performance monitoring decorator
def monitor_performance(operation_name: str):
    """
    Decorator to monitor and log performance of functions.

    Args:
        operation_name: Name of the operation for logging
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            import time
            start_time = time.time()

            try:
                result = func(*args, **kwargs)
                duration_ms = (time.time() - start_time) * 1000

                if duration_ms > 1000:
                    logger.warning(
                        f"Slow operation: {operation_name} took {duration_ms:.2f}ms"
                    )
                else:
                    logger.debug(
                        f"Performance: {operation_name} completed in {duration_ms:.2f}ms"
                    )

                return result

            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                logger.error(
                    f"Failed: {operation_name} (after {duration_ms:.2f}ms): {e}",
                    exc_info=True
                )
                raise

        return wrapper
    return decorator


# Data hash helper for cache invalidation
def get_dataframe_hash(df: pd.DataFrame) -> str:
    """
    Generate a hash of a DataFrame for cache invalidation.

    Args:
        df: DataFrame to hash

    Returns:
        Hash string
    """
    if df is None or df.empty:
        return "empty"

    try:
        # Use shape and a sample of data for hash
        hash_data = {
            'shape': df.shape,
            'columns': list(df.columns),
            'head': df.head(5).to_dict() if len(df) > 0 else {},
            'tail': df.tail(5).to_dict() if len(df) > 5 else {}
        }
        hash_str = json.dumps(hash_data, sort_keys=True, default=str)
        return hashlib.md5(hash_str.encode()).hexdigest()
    except Exception as e:
        logger.warning(f"Error hashing DataFrame: {e}")
        return str(datetime.now().timestamp())
