"""
MT5 HTTP Connector
Connects to MT5 via HTTP API instead of direct MetaTrader5 library
"""
import requests
import pandas as pd
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
import streamlit as st

from .logger import get_logger, log_mt5_error, LogContext
from .config import config

logger = get_logger(__name__)


class MT5ConnectionError(Exception):
    """Custom exception for MT5 connection errors."""
    pass


class MT5HttpConnector:
    """HTTP-based connector for MetaTrader5 terminal via REST API."""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(MT5HttpConnector, cls).__new__(cls)
            cls._instance.initialized = False
            cls._instance.base_url = None
            logger.info("MT5HttpConnector singleton instance created")
        return cls._instance

    def connect(self) -> bool:
        """
        Initializes the connection to the MT5 API server.

        Returns:
            True if connection successful, False otherwise
        """
        if self.initialized:
            logger.debug("MT5 HTTP API already initialized")
            return True

        try:
            # Get MT5 host from environment or default to trading_mt5
            mt5_host = config.get("MT5_HOST", "trading_mt5")
            mt5_port = config.get("MT5_PORT", 8001)
            self.base_url = f"http://{mt5_host}:{mt5_port}"

            logger.info(f"Connecting to MT5 API at {self.base_url}")

            # Test connection
            response = requests.get(f"{self.base_url}/health", timeout=5)
            response.raise_for_status()

            health = response.json()
            if health.get("status") == "healthy" and health.get("mt5_connected"):
                self.initialized = True
                logger.info("MT5 HTTP API connection successful")
                return True
            else:
                logger.error("MT5 API unhealthy or not connected to terminal")
                return False

        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to connect to MT5 API: {e}")
            raise MT5ConnectionError(f"Cannot connect to MT5 API at {self.base_url}: {e}")

    def disconnect(self):
        """Disconnect from MT5 API."""
        self.initialized = False
        logger.info("Disconnected from MT5 API")

    def _get(self, endpoint: str, params: Optional[Dict] = None) -> Any:
        """Make GET request to API."""
        if not self.initialized:
            raise MT5ConnectionError("Not connected to MT5 API. Call connect() first.")

        try:
            url = f"{self.base_url}{endpoint}"
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"API request failed: {endpoint} - {e}")
            raise MT5ConnectionError(f"API request failed: {e}")

    def account_info(self) -> Optional[Dict]:
        """Get account information."""
        try:
            return self._get("/account/info")
        except Exception as e:
            logger.error(f"Failed to get account info: {e}")
            return None

    def positions_get(self, symbol: Optional[str] = None) -> List[Dict]:
        """Get open positions."""
        try:
            params = {"symbol": symbol} if symbol else None
            return self._get("/positions", params=params)
        except Exception as e:
            logger.error(f"Failed to get positions: {e}")
            return []

    def orders_get(self, symbol: Optional[str] = None) -> List[Dict]:
        """Get pending orders."""
        try:
            params = {"symbol": symbol} if symbol else None
            return self._get("/orders", params=params)
        except Exception as e:
            logger.error(f"Failed to get orders: {e}")
            return []

    def history_deals_get(self, date_from: datetime, date_to: datetime) -> List[Dict]:
        """Get deals history."""
        try:
            params = {
                "from_date": date_from.isoformat(),
                "to_date": date_to.isoformat()
            }
            return self._get("/history/deals", params=params)
        except Exception as e:
            logger.error(f"Failed to get deals history: {e}")
            return []

    def history_orders_get(self, date_from: datetime, date_to: datetime) -> List[Dict]:
        """Get orders history."""
        try:
            params = {
                "from_date": date_from.isoformat(),
                "to_date": date_to.isoformat()
            }
            return self._get("/history/orders", params=params)
        except Exception as e:
            logger.error(f"Failed to get orders history: {e}")
            return []

    def symbols_get(self, group: Optional[str] = None) -> List[Dict]:
        """Get available symbols."""
        try:
            params = {"group": group} if group else None
            return self._get("/symbols", params=params)
        except Exception as e:
            logger.error(f"Failed to get symbols: {e}")
            return []

    def symbol_info(self, symbol: str) -> Optional[Dict]:
        """Get symbol information."""
        try:
            return self._get(f"/symbols/{symbol}/info")
        except Exception as e:
            logger.error(f"Failed to get symbol info for {symbol}: {e}")
            return None

    def symbol_info_tick(self, symbol: str) -> Optional[Dict]:
        """Get last tick for symbol."""
        try:
            return self._get(f"/symbols/{symbol}/tick")
        except Exception as e:
            logger.error(f"Failed to get tick for {symbol}: {e}")
            return None

    def copy_rates_from_pos(self, symbol: str, timeframe: int, start_pos: int, count: int) -> Optional[pd.DataFrame]:
        """Get historical rates."""
        try:
            # Map timeframe integer to string
            timeframe_map = {
                1: "M1", 5: "M5", 15: "M15", 30: "M30",
                60: "H1", 240: "H4", 1440: "D1",
                10080: "W1", 43200: "MN1"
            }
            tf_str = timeframe_map.get(timeframe, "H1")

            params = {
                "timeframe": tf_str,
                "count": count
            }
            rates = self._get(f"/symbols/{symbol}/rates", params=params)

            if rates:
                df = pd.DataFrame(rates)
                df['time'] = pd.to_datetime(df['time'])
                return df
            return None
        except Exception as e:
            logger.error(f"Failed to get rates for {symbol}: {e}")
            return None

    def terminal_info(self) -> Optional[Dict]:
        """Get terminal information."""
        try:
            return self._get("/terminal/info")
        except Exception as e:
            logger.error(f"Failed to get terminal info: {e}")
            return None

    def version(self) -> Optional[tuple]:
        """Get MT5 version."""
        try:
            data = self._get("/version")
            version = data.get("mt5_version", ())
            return tuple(version) if isinstance(version, list) else version
        except Exception as e:
            logger.error(f"Failed to get version: {e}")
            return None
