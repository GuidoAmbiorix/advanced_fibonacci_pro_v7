"""
Direct MT5 Connector using mt5linux (Wine environment).
No API bridge needed - connects directly to MT5 in Wine.
"""

import sys
import time
from src.logger import get_logger

logger = get_logger(__name__)

# Constants
MT5_AVAILABLE = False
MT5_MODE = "none"
mt5 = None

# Try to import just the module, don't connect yet
try:
    from mt5linux import MetaTrader5
    MT5_AVAILABLE = True
    MT5_MODE = "mt5linux"
    logger.info("✅ mt5linux package available (Wine environment)")
except ImportError:
    try:
        import MetaTrader5 as mt5
        MT5_AVAILABLE = True
        MT5_MODE = "MetaTrader5"
        logger.info("✅ MetaTrader5 package available (Windows native)")
    except ImportError:
        logger.error("❌ Neither mt5linux nor MetaTrader5 package found")
        MT5_AVAILABLE = False
        MT5_MODE = "none"


class MT5Connector:
    """Direct connector to MT5 terminal."""
    
    def __init__(self):
        """Initialize connector."""
        self.connected = False
        self._mt5_instance = None
        
    def _initialize_mt5linux(self) -> bool:
        """Attempt to connect to mt5linux server."""
        try:
            from mt5linux import MetaTrader5
            # Try connecting on standard ports with retry
            ports = [18812, 8001]
            
            for port in ports:
                try:
                    logger.info(f"Attempting mt5linux connection on localhost:{port}...")
                    self._mt5_instance = MetaTrader5(host='localhost', port=port)
                    
                    # Verify connection by calling a simple method
                    if self._mt5_instance and self._mt5_instance.terminal_info():
                        logger.info(f"✅ Connected to mt5linux server on port {port}")
                        return True
                except (ConnectionRefusedError, EOFError, Exception) as e:
                    logger.debug(f"Connection to port {port} failed: {e}")
            
            logger.warning("Could not connect to any mt5linux server")
            return False
            
        except Exception as e:
            logger.error(f"mt5linux initialization error: {e}")
            return False

    def connect(self) -> bool:
        """
        Connect to MT5 terminal.
        
        Returns:
            True if connected successfully
        """
        global mt5
        
        if not MT5_AVAILABLE:
            logger.error("MT5 packages not installed")
            return False
            
        # Lazy initialization for mt5linux
        if MT5_MODE == "mt5linux":
            if self._mt5_instance is None:
                if not self._initialize_mt5linux():
                    # Retry once after short delay
                    time.sleep(1)
                    if not self._initialize_mt5linux():
                        return False
            
            # Use the instance
            mt5_obj = self._mt5_instance
        else:
            # Native Windows
            mt5_obj = mt5

        try:
            # Initialize MT5
            if not mt5_obj.initialize():
                error = mt5_obj.last_error() if hasattr(mt5_obj, 'last_error') else "Unknown error"
                logger.error(f"MT5 initialization failed: {error}")
                return False
            
            self.connected = True
            logger.info(f"✅ Connected to MT5 via {MT5_MODE}")
            
            # Only try to get info if we are confident connection works
            try:
                terminal_info = mt5_obj.terminal_info()
                if terminal_info:
                    company = getattr(terminal_info, 'company', 'MT5')
                    logger.info(f"Terminal: {company}")
            except Exception as e:
                logger.warning(f"Could not get terminal info: {e}")
            
            return True
            
        except Exception as e:
            logger.error(f"Connection error: {e}")
            # Reset instance on error to force reconnection next time
            if MT5_MODE == "mt5linux":
                self._mt5_instance = None
            return False
    
    def disconnect(self):
        """Disconnect from MT5."""
        if not self.connected:
            return
            
        try:
            if MT5_MODE == "mt5linux" and self._mt5_instance:
                self._mt5_instance.shutdown()
                self._mt5_instance = None
            elif MT5_MODE == "MetaTrader5" and mt5:
                mt5.shutdown()
            
            self.connected = False
            logger.info("Disconnected from MT5")
        except Exception as e:
            logger.error(f"Error disconnecting: {e}")
            # Force cleanup
            self.connected = False
            self._mt5_instance = None
    
    def is_connected(self) -> bool:
        """Check if connected to MT5."""
        # Simple check - could be improved with ping
        return self.connected
    
    def get_mt5_instance(self):
        """Get the MT5 instance for direct access."""
        if MT5_MODE == "mt5linux":
            return self._mt5_instance
        return mt5


# Global instance
connector = MT5Connector()


def get_connector() -> MT5Connector:
    """Get global MT5 connector instance."""
    return connector
