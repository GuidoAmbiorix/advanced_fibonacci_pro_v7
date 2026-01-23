import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime
import streamlit as st
from typing import Optional, Dict, Any

from .logger import get_logger, log_mt5_error, LogContext
from .config import config

logger = get_logger(__name__)


class MT5ConnectionError(Exception):
    """Custom exception for MT5 connection errors."""
    pass


class MT5Connector:
    """Singleton connector for MetaTrader5 terminal with comprehensive error handling."""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(MT5Connector, cls).__new__(cls)
            cls._instance.initialized = False
            logger.info("MT5Connector singleton instance created")
        return cls._instance

    def connect(self) -> bool:
        """
        Initializes the connection to the MT5 terminal.

        Returns:
            True if connection successful, False otherwise

        Raises:
            MT5ConnectionError: If connection fails critically
        """
        if self.initialized:
            logger.debug("MT5 already initialized")
            return True

        try:
            with LogContext(logger, "MT5 initialization"):
                # Initialize with optional credentials
                if config.MT5_LOGIN and config.MT5_PASSWORD and config.MT5_SERVER:
                    logger.info(f"Initializing MT5 with credentials for server: {config.MT5_SERVER}")
                    success = mt5.initialize(
                        login=int(config.MT5_LOGIN),
                        password=config.MT5_PASSWORD,
                        server=config.MT5_SERVER,
                        timeout=config.MT5_TIMEOUT
                    )
                else:
                    logger.info("Initializing MT5 with default terminal")
                    success = mt5.initialize(timeout=config.MT5_TIMEOUT)

                if not success:
                    error_code, error_msg = mt5.last_error()
                    log_mt5_error(logger, "initialization", error_code, error_msg)
                    st.error(f"MT5 Initialization failed: {error_msg} (Code: {error_code})")
                    return False

                self.initialized = True

                # Log terminal info
                terminal_info = mt5.terminal_info()
                if terminal_info:
                    logger.info(f"Connected to MT5 Terminal: {terminal_info.name}, Build: {terminal_info.build}")

                # Log account info
                account_info = mt5.account_info()
                if account_info:
                    logger.info(
                        f"Account: {account_info.login}, "
                        f"Server: {account_info.server}, "
                        f"Balance: {account_info.balance}"
                    )

                return True

        except Exception as e:
            logger.error(f"Unexpected error during MT5 initialization: {e}", exc_info=True)
            st.error(f"MT5 connection error: {str(e)}")
            return False

    def disconnect(self):
        """Shuts down the MT5 connection gracefully."""
        if self.initialized:
            try:
                logger.info("Shutting down MT5 connection")
                mt5.shutdown()
                self.initialized = False
                logger.info("MT5 connection closed successfully")
            except Exception as e:
                logger.error(f"Error during MT5 shutdown: {e}", exc_info=True)
                self.initialized = False

    def get_account_info(self) -> Optional[Dict[str, Any]]:
        """
        Returns account information as a dictionary.

        Returns:
            Account info dict or None if failed
        """
        if not self.connect():
            return None

        try:
            info = mt5.account_info()
            if info:
                logger.debug(f"Retrieved account info for account: {info.login}")
                return info._asdict()
            else:
                error_code, error_msg = mt5.last_error()
                log_mt5_error(logger, "get_account_info", error_code, error_msg)
                return None
        except Exception as e:
            logger.error(f"Error retrieving account info: {e}", exc_info=True)
            return None

    def get_terminal_info(self) -> Optional[Dict[str, Any]]:
        """
        Returns terminal information.

        Returns:
            Terminal info dict or None if failed
        """
        if not self.connect():
            return None

        try:
            info = mt5.terminal_info()
            if info:
                logger.debug(f"Retrieved terminal info: {info.name}")
                return info._asdict()
            else:
                error_code, error_msg = mt5.last_error()
                log_mt5_error(logger, "get_terminal_info", error_code, error_msg)
                return None
        except Exception as e:
            logger.error(f"Error retrieving terminal info: {e}", exc_info=True)
            return None
