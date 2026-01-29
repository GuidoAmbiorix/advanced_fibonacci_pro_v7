"""
V3 Trading System - Order Flow Analysis Service
Analyzes market microstructure and institutional order flow
"""

import asyncio
import json
from datetime import datetime
from typing import Optional, Dict
import numpy as np
import redis.asyncio as redis
import structlog
import os

# Configure logging
log = structlog.get_logger()

# ==================== Configuration ====================

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))

# ==================== Order Flow Analyzer ====================

class OrderFlowAnalyzer:
    """Analyzes order flow and market microstructure"""

    def __init__(self):
        self.volume_history = {}  # Symbol -> volume arrays

    def analyze_order_book(self, symbol: str, bid_volumes: np.ndarray, ask_volumes: np.ndarray) -> Dict:
        """
        Analyze order book depth
        bid_volumes: array of volumes at each bid level
        ask_volumes: array of volumes at each ask level
        """
        total_bid = np.sum(bid_volumes)
        total_ask = np.sum(ask_volumes)

        # Order book imbalance
        if total_bid + total_ask > 0:
            imbalance = (total_bid - total_ask) / (total_bid + total_ask)
        else:
            imbalance = 0.0

        return {
            "total_bid_volume": float(total_bid),
            "total_ask_volume": float(total_ask),
            "imbalance": float(imbalance)
        }

    def detect_large_orders(self, symbol: str, recent_volumes: np.ndarray, threshold_multiplier: float = 3.0) -> bool:
        """
        Detect large institutional orders
        Large order = volume > threshold_multiplier * average volume
        """
        if len(recent_volumes) < 20:
            return False

        avg_volume = np.mean(recent_volumes[-20:])
        current_volume = recent_volumes[-1]

        if current_volume > avg_volume * threshold_multiplier:
            return True

        return False

    def calculate_buy_sell_pressure(self, buy_volume: float, sell_volume: float) -> Dict:
        """Calculate buy/sell pressure from volume data"""
        total_volume = buy_volume + sell_volume

        if total_volume > 0:
            imbalance = (buy_volume - sell_volume) / total_volume
        else:
            imbalance = 0.0

        # Determine direction
        if imbalance > 0.2:
            direction = 1  # Buy pressure
        elif imbalance < -0.2:
            direction = -1  # Sell pressure
        else:
            direction = 0  # Neutral

        # Confidence based on volume magnitude
        confidence = min(abs(imbalance) * 2, 1.0)

        return {
            "buy_volume": buy_volume,
            "sell_volume": sell_volume,
            "imbalance": float(imbalance),
            "direction": direction,
            "confidence": float(confidence)
        }

# ==================== Order Flow Service ====================

class OrderFlowService:
    """Main order flow service"""

    def __init__(self):
        self.analyzer = OrderFlowAnalyzer()
        self.redis_client: Optional[redis.Redis] = None

    async def connect_redis(self):
        """Connect to Redis"""
        self.redis_client = await redis.from_url(
            f"redis://{REDIS_HOST}:{REDIS_PORT}",
            encoding="utf-8",
            decode_responses=True
        )
        await self.redis_client.ping()
        log.info("redis_connected", host=REDIS_HOST, port=REDIS_PORT)

    async def analyze_symbol(self, symbol: str) -> Dict:
        """
        Analyze order flow for a symbol
        In production, would fetch real order book data
        """
        # Mock data (in production, fetch from broker API or TrueFX)
        np.random.seed(int(datetime.utcnow().timestamp()) % 1000)

        # Simulate buy/sell volume
        buy_volume = np.random.uniform(800, 1200)
        sell_volume = np.random.uniform(600, 1000)

        # Calculate pressure
        pressure = self.analyzer.calculate_buy_sell_pressure(buy_volume, sell_volume)

        # Simulate order book
        bid_volumes = np.random.uniform(100, 200, size=10)
        ask_volumes = np.random.uniform(90, 190, size=10)
        order_book = self.analyzer.analyze_order_book(symbol, bid_volumes, ask_volumes)

        # Detect large orders
        recent_volumes = np.random.uniform(500, 1000, size=50)
        large_order = self.analyzer.detect_large_orders(symbol, recent_volumes)

        result = {
            "symbol": symbol,
            "buy_volume": pressure["buy_volume"],
            "sell_volume": pressure["sell_volume"],
            "imbalance": pressure["imbalance"],
            "large_order_detected": large_order,
            "direction": pressure["direction"],
            "confidence": pressure["confidence"],
            "timestamp": datetime.utcnow().isoformat()
        }

        # Cache in Redis (1-minute TTL)
        cache_key = f"orderflow:{symbol}"
        await self.redis_client.setex(
            cache_key,
            60,
            json.dumps(result)
        )

        log.info("orderflow_analyzed", symbol=symbol, imbalance=pressure["imbalance"])

        return result

    async def update_all_symbols(self):
        """Update order flow for all symbols"""
        symbols = ["EURUSD", "GBPUSD", "USDJPY", "USDCAD", "XAUUSD"]

        for symbol in symbols:
            try:
                await self.analyze_symbol(symbol)
            except Exception as e:
                log.error("orderflow_update_failed", symbol=symbol, error=str(e))

    async def run_periodic_updates(self):
        """Run order flow updates every minute"""
        while True:
            try:
                await self.update_all_symbols()
            except Exception as e:
                log.error("periodic_update_failed", error=str(e))

            # Wait 1 minute
            await asyncio.sleep(60)

    async def heartbeat(self):
        """Send heartbeat to Redis"""
        while True:
            try:
                await self.redis_client.setex("heartbeat:orderflow", 120, "alive")
            except Exception as e:
                log.error("heartbeat_failed", error=str(e))

            await asyncio.sleep(60)

# ==================== Main ====================

async def main():
    """Main entry point"""
    log.info("orderflow_service_starting")

    service = OrderFlowService()
    await service.connect_redis()

    # Start background tasks
    tasks = [
        asyncio.create_task(service.run_periodic_updates()),
        asyncio.create_task(service.heartbeat())
    ]

    log.info("orderflow_service_running")

    # Wait for tasks
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
