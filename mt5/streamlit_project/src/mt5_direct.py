"""
Direct MT5 Connector using mt5linux (Wine environment).
No API bridge needed - connects directly to MT5 in Wine.
"""

import sys
from ..logger import get_logger

logger = get_logger(__name__)

# Try to import mt5linux (for Wine/Linux)
mt5 = None
MT5_AVAILABLE = False

try:
    import mt5linux as mt5
    MT5_AVAILABLE = True
    logger.info("✅ Using mt5linux (Wine environment)")
except ImportError:
    try:
        import MetaTrader5 as mt5
        MT5_AVAILABLE = True
        logger.info("✅ Using MetaTrader5 (Windows native)")
    except ImportError:
        logger.error("❌ Neither mt5linux nor MetaTrader5 available")
        MT5_AVAILABLE = False


class MT5Connector:
    """Direct connector to MT5 terminal."""
    
    def __init__(self):
        """Initialize connector."""
        self.connected = False
        
    def connect(self) -> bool:
        """
        Connect to MT5 terminal.
        
        Returns:
            True if connected successfully
        """
        if not MT5_AVAILABLE:
            logger.error("MT5 library not available")
            return False
        
        try:
            # Initialize MT5
            if not mt5.initialize():
                error = mt5.last_error()
                logger.error(f"MT5 initialization failed: {error}")
                return False
            
            self.connected = True
            
            # Log terminal info
            terminal_info = mt5.terminal_info()
            if terminal_info:
                logger.info(f"Connected to: {terminal_info.company}")
            
            # Log account info
            account_info = mt5.account_info()
            if account_info:
                logger.info(f"Account: {account_info.login} | Balance: {account_info.balance}")
            
            return True
            
        except Exception as e:
            logger.error(f"Connection error: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from MT5."""
        if MT5_AVAILABLE and self.connected:
            mt5.shutdown()
            self.connected = False
            logger.info("Disconnected from MT5")
    
    def is_connected(self) -> bool:
        """Check if connected to MT5."""
        return self.connected and MT5_AVAILABLE


# Global instance
connector = MT5Connector()


def get_connector() -> MT5Connector:
    """Get global MT5 connector instance."""
    return connector
