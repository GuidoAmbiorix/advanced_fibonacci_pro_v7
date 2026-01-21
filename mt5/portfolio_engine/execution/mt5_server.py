"""
MT5 RPyC Sidecar - Port 8002
Acts as a proxy for MT5 (Manual RPyC Bridge) and provides custom automation methods.
"""
import sys
import os
import rpyc
import time
import logging
import subprocess
from rpyc.utils.server import ThreadedServer
from rpyc.core.service import SlaveService

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("MT5Sidecar")

# Global MT5 Proxy Connection
_internal_conn = None

def get_mt5_proxy():
    """Returns a connected MT5 module proxy from the internal Wine bridge (8001)."""
    global _internal_conn
    
    try:
        if _internal_conn:
            try:
                _internal_conn.ping()
                return _internal_conn.modules.MetaTrader5
            except:
                _internal_conn = None

        logger.info("Connecting to internal MT5 bridge at 127.0.0.1:8001...")
        _internal_conn = rpyc.classic.connect('127.0.0.1', 8001)
        
        # Inject dict-handling proxies on the remote (Wine) side
        _internal_conn.execute("""
import MetaTrader5 as _mt5
def _proxy_call(func_name, req):
    if not hasattr(_mt5, func_name):
        return None
    func = getattr(_mt5, func_name)
    if isinstance(req, (dict, list)):
        # Convert RPyC netref to local dict/list
        return func(dict(req) if isinstance(req, dict) else list(req))
    return func(req)
""")
        
        mt5 = _internal_conn.modules.MetaTrader5
        
        # Inspection - help debug the missing attributes
        logger.info(f"MetaTrader5 version: {getattr(mt5, '__version__', 'unknown')}")
        all_attrs = dir(mt5)
        # Check for both casing
        global _cached_gv_func
        for variant in ['global_variable_get', 'GlobalVariableGet', 'global_variables_get']:
            if variant in all_attrs:
                _cached_gv_func = variant
                logger.info(f"Found GV function: {_cached_gv_func}")
                break
        
        if mt5.initialize():
            logger.info("✅ Internal MT5 bridge initialized.")
            return mt5
    except Exception as e:
        logger.error(f"Error bridging to MT5: {e}")
    return None

def order_send(request):
    """Bridge-safe order_send."""
    global _internal_conn
    if not _internal_conn: get_mt5_proxy()
    try:
        return _internal_conn.namespace['_proxy_call']('order_send', request)
    except Exception as e:
        logger.error(f"order_send failed: {e}")
        return None

def order_check(request):
    """Bridge-safe order_check."""
    global _internal_conn
    if not _internal_conn: get_mt5_proxy()
    try:
        return _internal_conn.namespace['_proxy_call']('order_check', request)
    except Exception as e:
        logger.error(f"order_check failed: {e}")
        return None

# Global cache for the GV function name to avoid probing RPyC
_cached_gv_func = None

def safe_get_global_variable(name):
    """Safely retrieves a global variable using a cached function name."""
    global _cached_gv_func
    mt5 = get_mt5_proxy()
    if not mt5: return 0.0
    
    # If we didn't find a function yet, try one last check
    if _cached_gv_func is None:
        all_attrs = dir(mt5)
        for variant in ['global_variable_get', 'GlobalVariableGet', 'global_variables_get']:
            if variant in all_attrs:
                _cached_gv_func = variant
                break
    
    if _cached_gv_func is None:
        return 0.0
        
    try:
        func = getattr(mt5, _cached_gv_func)
        if _cached_gv_func == 'global_variables_get':
            res = func()
            if res:
                for gv in res:
                    if gv.name == name: return float(gv.value)
        else:
            val = func(name)
            return float(val) if val is not None else 0.0
    except Exception as e:
        logger.debug(f"GV Error for {name}: {e}")
        return 0.0
    return 0.0

def get_ohlcv(symbol, timeframe_name, count):
    """Helper for robust OHLCV retrieval with symbol selection."""
    mt5 = get_mt5_proxy()
    if not mt5: return None
    
    try:
        # Ensure symbol is selected
        mt5.symbol_select(symbol, True)
        
        # Determine timeframe
        tf = getattr(mt5, f"TIMEFRAME_{timeframe_name}", 16385) # Default H1
        
        # Try different copy methods
        rates = mt5.copy_rates_from_pos(symbol, tf, 0, count)
        if rates is None:
            import datetime
            rates = mt5.copy_rates_from(symbol, tf, datetime.datetime.now(), count)
            
        if rates is not None:
            # Crucial: Obtain the data to Linux host memory
            import rpyc
            return rpyc.utils.classic.obtain(rates)
        return None
    except Exception as e:
        logger.error(f"OHLCV Error for {symbol}: {e}")
        return None

# Global attribute cache
_cached_attrs = []

# Silence RPyC noise for expected AttributeError probes
import logging
logging.getLogger('rpyc').setLevel(logging.WARNING)

# --- Automation Helpers ---

def open_chart_with_ea(symbol: str = "XAUUSD") -> str:
    """Opens a chart - requires manual intervention as Python API doesn't support chart operations."""
    mt5 = get_mt5_proxy()
    if not mt5:
        return "Error: MT5 Bridge not available"
    
    # Verify symbol exists and is selected
    try:
        mt5.symbol_select(symbol, True)
            
        return (
            f"ℹ️ Chart automation not available in MT5 Python API.\n"
            f"Please manually:\n"
            f"1. Open VNC (localhost:3000)\n"
            f"2. Open a chart for {symbol}\n"
            f"3. Attach your EA to the chart\n"
            f"Symbol {symbol} has been selected in Market Watch."
        )
    except Exception as e:
        return f"Error: {e}"

def run_backtest(config_content: str) -> str:
    """Executes a backtest using the MT5 terminal in Wine."""
    try:
        # 1. Parse Symbol to pre-load data
        symbol = "XAUUSD"
        for line in config_content.splitlines():
            if line.strip().startswith("Symbol="):
                symbol = line.split("=")[1].strip()
                break
        
        # 2. Force History Pre-load
        mt5 = get_mt5_proxy()
        if mt5:
            logger.info(f"Pre-loading history for {symbol} to prevent sync errors...")
            mt5.symbol_select(symbol, True)
            # Force download of M1 data (base for all TFs)
            # Requesting a small chunk often triggers the full sync process in background
            mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 0, 1000)
            time.sleep(3) # Give it a moment to write to disk
        
        output_path = "/app/tester.ini"
        with open(output_path, "w") as f:
            f.write(config_content)
        logger.info(f"Written tester config to {output_path}")
        
        mt5_path = "/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
        if not os.path.exists(mt5_path):
             return "Error: terminal64.exe not found"
             
        cmd = ["wine", mt5_path, "/config:C:\\app\\tester.ini", "/portable"]
        logger.info(f"Launching Backtest: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        return f"Exit Code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    except Exception as e:
        logger.error(f"Backtest failed: {e}")
        return f"Exception: {e}"



# --- Main Server Loop ---

if __name__ == "__main__":
    PORT = int(os.environ.get("RPYC_PORT", 8002))
    
    # Wait for the internal MT5 bridge (8001) to be ready
    logger.info("Waiting for internal MT5 bridge on port 8001...")
    max_wait = 120
    for i in range(max_wait):
        import socket
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(('127.0.0.1', 8001)) == 0:
                logger.info("Internal bridge detected.")
                break
        if i % 5 == 0: logger.info(f"Still waiting for 8001... ({i}/{max_wait}s)")
        time.sleep(2)
    else:
        logger.error("Timed out waiting for internal bridge on port 8001.")
    
    # Initial bridge attempt
    get_mt5_proxy()
    
    logger.info(f"Starting Extended Sidecar Server on port {PORT}...")
    server = ThreadedServer(
        SlaveService,
        hostname='0.0.0.0',
        port=PORT,
        protocol_config={
            'allow_public_attrs': True,
            'allow_all_attrs': True,
            'allow_pickle': True,
            'sync_request_timeout': 300,
        }
    )
    server.start()
