"""
============================================================================
Redis Client - Async Cache and Session Management
============================================================================
"""

import json
from typing import Optional, Any
import redis.asyncio as redis
from app.core.config import settings

# Global Redis client
redis_client: Optional[redis.Redis] = None


async def init_redis() -> redis.Redis:
    """Initialize Redis connection"""
    global redis_client
    redis_client = redis.Redis(
        host=settings.REDIS_HOST,
        port=settings.REDIS_PORT,
        db=settings.REDIS_DB,
        password=settings.REDIS_PASSWORD or None,
        decode_responses=True
    )
    # Test connection
    await redis_client.ping()
    return redis_client


async def close_redis():
    """Close Redis connection"""
    global redis_client
    if redis_client:
        await redis_client.close()
        redis_client = None


def get_redis() -> redis.Redis:
    """Get Redis client instance"""
    if redis_client is None:
        raise RuntimeError("Redis not initialized. Call init_redis() first.")
    return redis_client


# ==========================================================================
# MARKET DATA CACHE
# ==========================================================================

async def cache_market_data(symbol: str, data: dict, ttl: int = 5) -> bool:
    """
    Cache market data (prices, analysis) with short TTL
    
    Args:
        symbol: Trading symbol (e.g., 'EURUSD')
        data: Market data dict
        ttl: Time-to-live in seconds (default 5s for real-time data)
    """
    key = f"market:{symbol}"
    await redis_client.setex(key, ttl, json.dumps(data))
    return True


async def get_cached_market_data(symbol: str) -> Optional[dict]:
    """Get cached market data for symbol"""
    key = f"market:{symbol}"
    data = await redis_client.get(key)
    return json.loads(data) if data else None


# ==========================================================================
# ANALYSIS CACHE (Longer TTL for computed analysis)
# ==========================================================================

async def cache_analysis(symbol: str, timeframe: str, data: dict, ttl: int = 300) -> bool:
    """
    Cache trading analysis results (SMC, Fibonacci, etc.)
    
    Args:
        symbol: Trading symbol
        timeframe: Timeframe (e.g., 'H1', 'M15')
        data: Analysis results
        ttl: Time-to-live in seconds (default 5 min)
    """
    key = f"analysis:{symbol}:{timeframe}"
    await redis_client.setex(key, ttl, json.dumps(data))
    return True


async def get_cached_analysis(symbol: str, timeframe: str) -> Optional[dict]:
    """Get cached analysis for symbol/timeframe"""
    key = f"analysis:{symbol}:{timeframe}"
    data = await redis_client.get(key)
    return json.loads(data) if data else None


# ==========================================================================
# RATE LIMITING
# ==========================================================================

async def check_rate_limit(key: str, limit: int, window: int = 60) -> bool:
    """
    Check if rate limit exceeded
    
    Args:
        key: Unique key for rate limit (e.g., 'api:user:123')
        limit: Max requests allowed
        window: Time window in seconds
    
    Returns:
        True if allowed, False if rate limited
    """
    current = await redis_client.incr(key)
    if current == 1:
        await redis_client.expire(key, window)
    return current <= limit


# ==========================================================================
# SESSION STORAGE
# ==========================================================================

async def set_session(session_id: str, data: dict, ttl: int = 3600) -> bool:
    """Store session data (1 hour default)"""
    key = f"session:{session_id}"
    await redis_client.setex(key, ttl, json.dumps(data))
    return True


async def get_session(session_id: str) -> Optional[dict]:
    """Get session data"""
    key = f"session:{session_id}"
    data = await redis_client.get(key)
    return json.loads(data) if data else None


async def delete_session(session_id: str) -> bool:
    """Delete session"""
    key = f"session:{session_id}"
    await redis_client.delete(key)
    return True


# ==========================================================================
# GENERIC HELPERS
# ==========================================================================

async def cache_set(key: str, value: Any, ttl: int = 300) -> bool:
    """Generic cache set"""
    if isinstance(value, (dict, list)):
        value = json.dumps(value)
    await redis_client.setex(key, ttl, value)
    return True


async def cache_get(key: str) -> Optional[Any]:
    """Generic cache get"""
    data = await redis_client.get(key)
    if data:
        try:
            return json.loads(data)
        except json.JSONDecodeError:
            return data
    return None


async def cache_delete(key: str) -> bool:
    """Delete cache key"""
    await redis_client.delete(key)
    return True
