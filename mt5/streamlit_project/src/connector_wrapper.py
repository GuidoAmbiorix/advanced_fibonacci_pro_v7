"""
MT5 Connector Wrapper
Automatically selects HTTP or direct MT5 connector based on environment
"""
import os
from .logger import get_logger

logger = get_logger(__name__)

# Determine which connector to use
USE_HTTP_API = os.getenv("USE_MT5_HTTP_API", "true").lower() == "true"

if USE_HTTP_API:
    logger.info("Using MT5 HTTP API Connector")
    from .mt5_http_connector import MT5HttpConnector as MT5Connector, MT5ConnectionError
else:
    logger.info("Using Direct MT5 Connector")
    from .connector import MT5Connector, MT5ConnectionError

__all__ = ["MT5Connector", "MT5ConnectionError"]
