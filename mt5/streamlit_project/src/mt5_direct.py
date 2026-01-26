"""
Direct MT5 Connector using mt5linux (Wine environment).
No API bridge needed - connects directly to MT5 in Wine.
"""

import sys
from src.logger import get_logger

logger = get_logger(__name__)

# Import MT5 with proper handling for mt5linux vs MetaTrader5
MT5_AVAILABLE = False
MT5_MODE = "none"
mt5 = None

try:
    # Try mt5linux first (Wine/Linux)
    from mt5linux import MetaTrader5
    # For mt5linux, we instantiate the class and connect to localhost:18812
    mt5 = MetaTrader5(host='localhost', port=18812)
    MT5_AVAILABLE = True
    MT5_MODE = "mt5linux"
    logger.info("✅ Using mt5linux (Wine environment)")
except ConnectionRefusedError:
    logger.warning("⚠️  mt5linux server not running on port 18812")
    logger.warning("    Server may still be starting up. Connection will retry on first use.")
    mt5 = None
    MT5_AVAILABLE = False
    MT5_MODE = "none"
except ImportError:
    try:
        # Fallback to MetaTrader5 (Windows)
        import MetaTrader5 as mt5
        MT5_AVAILABLE = True
        MT5_MODE = "MetaTrader5"
        logger.info("✅ Using MetaTrader5 (Windows native)")
    except ImportError:
        logger.error("❌ Neither mt5linux nor MetaTrader5 available")
        MT5_AVAILABLE = False
        MT5_MODE = "none"
except Exception as e:
    logger.error(f"❌ mt5linux connection failed: {e}")
    mt5 = None
    MT5_AVAILABLE = False
    MT5_MODE = "none"


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
        if not MT5_AVAILABLE or mt5 is None:
            logger.error("MT5 library not available")
            return False
        
        try:
            # Both mt5linux and MetaTrader5 use the same initialize() method
            if not mt5.initialize():
                error = mt5.last_error() if hasattr(mt5, 'last_error') else "Unknown error"
                logger.error(f"MT5 initialization failed: {error}")
                return False
            
            self.connected = True
            logger.info(f"✅ Connected to MT5 via {MT5_MODE}")
            
            # Try to get terminal info
            try:
                terminal_info = mt5.terminal_info()
                if terminal_info:
                    company = getattr(terminal_info, 'company', 'MT5')
                    logger.info(f"Terminal: {company}")
            except Exception as e:
                logger.warning(f"Could not get terminal info: {e}")
            
            # Try to get account info
            try:
                account_info = mt5.account_info()
                if account_info:
                    login = getattr(account_info, 'login', 'N/A')
                    balance = getattr(account_info, 'balance', 0)
                    logger.info(f"Account: {login} | Balance: {balance}")
            except Exception as e:
                logger.warning(f"Could not get account info: {e}")
            
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
            if MT5_AVAILABLE and mt5:
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
        return mt5


# Global instance
connector = MT5Connector()


def get_connector() -> MT5Connector:
    """Get global MT5 connector instance."""
    return connector
