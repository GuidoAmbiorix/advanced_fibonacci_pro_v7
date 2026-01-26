"""
Direct MT5 Connector using mt5linux (Wine environment).
No API bridge needed - connects directly to MT5 in Wine.
"""

import sys
from src.logger import get_logger
from src.mt5_compat import mt5, MT5_AVAILABLE

logger = get_logger(__name__)
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
    """Direct connector to MT5 terminal using mt5linux."""
    
    def __init__(self):
        """Initialize connector."""
        self.connected = False
        self._mt5_instance = None
        
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
            # For mt5linux, we use MetaTrader() class instead of initialize()
            if MT5_MODE == "mt5linux":
                self._mt5_instance = mt5.MetaTrader()
                
                # Check if connection is successful
                if self._mt5_instance is None:
                    logger.error("Failed to create MT5 instance")
                    return False
                
                self.connected = True
                logger.info("✅ Connected to MT5 via mt5linux")
                
                # Try to get terminal info
                try:
                    terminal_info = self._mt5_instance.terminal_info()
                    if terminal_info:
                        logger.info(f"Terminal: {terminal_info.company if hasattr(terminal_info, 'company') else 'MT5'}")
                except Exception as e:
                    logger.warning(f"Could not get terminal info: {e}")
                
                # Try to get account info
                try:
                    account_info = self._mt5_instance.account_info()
                    if account_info:
                        logger.info(f"Account: {account_info.login if hasattr(account_info, 'login') else 'N/A'}")
                except Exception as e:
                    logger.warning(f"Could not get account info: {e}")
                
                return True
            else:
                # Using MetaTrader5 (Windows)
                if not mt5.initialize():
                    error = mt5.last_error()
                    logger.error(f"MT5 initialization failed: {error}")
                    return False
                
                self.connected = True
                logger.info("✅ Connected to MT5 (Windows)")
                
                terminal_info = mt5.terminal_info()
                if terminal_info:
                    logger.info(f"Connected to: {terminal_info.company}")
                
                account_info = mt5.account_info()
                if account_info:
                    logger.info(f"Account: {account_info.login} | Balance: {account_info.balance}")
                
                return True
            
        except Exception as e:
            logger.error(f"Connection error: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return False
    
    def disconnect(self):
        """Disconnect from MT5."""
        if not self.connected:
            return
            
        try:
            if MT5_MODE == "mt5linux" and self._mt5_instance:
                # mt5linux cleanup (if needed)
                self._mt5_instance = None
            elif MT5_AVAILABLE:
                mt5.shutdown()
            
            self.connected = False
            logger.info("Disconnected from MT5")
        except Exception as e:
            logger.error(f"Error disconnecting: {e}")
    
    def is_connected(self) -> bool:
        """Check if connected to MT5."""
        return self.connected and MT5_AVAILABLE
    
    def get_mt5_instance(self):
        """Get the MT5 instance for direct access."""
        return self._mt5_instance if MT5_MODE == "mt5linux" else mt5


# Global instance
connector = MT5Connector()


def get_connector() -> MT5Connector:
    """Get global MT5 connector instance."""
    return connector
