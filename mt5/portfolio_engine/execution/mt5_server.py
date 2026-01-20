"""
MT5 RPyC Sidecar (Classic Mode)
Runs a SlaveService to allow full remote control (Imports, Exec) from the bridge.
"""
import sys
import os
import rpyc
from rpyc.utils.server import ThreadedServer
from rpyc.core.service import SlaveService
import logging

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("MT5Sidecar")

if __name__ == "__main__":
    PORT = int(os.environ.get("RPYC_PORT", 18812))
    logger.info(f"Starting MT5 RPyC Classic Sidecar on port {PORT}...")
    logger.info(f"RPyC Version: {rpyc.__version__}")

    # We don't need to pre-import MT5 here, the client will do it via conn.modules.MetaTrader5
    # But we can check if it exists
    # Try to initialize MT5 with retries
    import time
    try:
        import MetaTrader5 as mt5
        
        # Explicit path in the container
        mt5_path = "/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
        
        MAX_RETRIES = 30
        for i in range(MAX_RETRIES):
            logger.info(f"Attempting MT5 initialization ({i+1}/{MAX_RETRIES})...")
            
            # Try with path first, then without
            if os.path.exists(mt5_path):
                init_res = mt5.initialize(mt5_path)
            else:
                logger.warning(f"MT5 binary not found at {mt5_path}, trying default lookup...")
                init_res = mt5.initialize()
                
            if init_res:
                logger.info("✅ Startup MT5 init check passed.")
                # Verify account info to be sure
                if mt5.account_info():
                     logger.info(f"Connected to account: {mt5.account_info().login}")
                break
            else:
                err = mt5.last_error()
                logger.warning(f"Startup MT5 init failed: {err}. Retrying in 2s...")
                time.sleep(2)
        else:
             logger.error("❌ Failed to initialize MT5 after all retries.")
             
    except ImportError:
        logger.error("MetaTrader5 package not found!")
    except Exception as e:
        logger.exception(f"Unexpected error during MT5 init: {e}")

# --- Automation Helpers ---
import subprocess

def run_backtest(config_content: str) -> str:
    """
    Writes config to 'tester.ini' and runs terminal64.exe in portable mode.
    Returns: stdout/stderr logs.
    """
    try:
        ini_path = r"C:\app\tester.ini" # Wine path inside container mapping
        # In Linux container, mapped to /app/tester.ini. Wine sees it as C:\app\tester.ini
        # Actually, let's write to local linux path
        output_path = "/app/tester.ini"
        
        with open(output_path, "w") as f:
            f.write(config_content)
            
        logger.info(f"Written tester config to {output_path}")
        
        mt5_path = "/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
        if not os.path.exists(mt5_path):
             return "Error: terminal64.exe not found"
             
        # Wine command
        cmd = ["wine", mt5_path, "/config:C:\\app\\tester.ini", "/portable"]
        
        logger.info(f"Launching Backtest: {' '.join(cmd)}")
        
        # Run process (blocking for simplicity, or use Popen for async)
        # For Streamlit, blocking is okay for short tests, but async is better.
        # Let's do blocking first to ensure report is generated.
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        return f"Exit Code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
        
    except Exception as e:
        logger.error(f"Backtest failed: {e}")
        return f"Exception: {e}"

def apply_bot_template(chart_id: int, symbol: str) -> bool:
    """
    Generates a .tpl file and applies it to the chart.
    """
    try:
        import MetaTrader5 as mt5
        
        # 1. Define template path inside the MT5 terminal directory
        # MQL5/Profiles/Templates/bot_launcher.tpl
        terminal_data_path = mt5.terminal_info().data_path
        template_dir = os.path.join(terminal_data_path, "MQL5", "Profiles", "Templates")
        os.makedirs(template_dir, exist_ok=True)
        template_path = os.path.join(template_dir, "bot_launcher.tpl")
        
        # 2. Template content
        # Note: flags=339 is common for 'Allow Algo Trading' + 'Allow DLL'
        tpl_content = f"""<chart>
symbol={symbol}
period=15
<expert>
name=Portfolio_Governor
path=Experts\\PortfolioManager\\Portfolio_Governor.ex5
flags=339
window_num=0
</expert>
</chart>
"""
        with open(template_path, "w") as f:
            f.write(tpl_content)
            
        logger.info(f"Generated template at {template_path}")
        
        # 3. Apply template
        res = mt5.chart_apply_template(chart_id, "bot_launcher.tpl")
        if not res:
            logger.error(f"Failed to apply template: {mt5.last_error()}")
            return False
            
        return True
    except Exception as e:
        logger.error(f"Error in apply_bot_template: {e}")
        return False

def open_chart_with_ea(symbol: str = "XAUUSD") -> str:
    """
    Opens a new chart and attaches the Governor EA via template.
    """
    try:
        import MetaTrader5 as mt5
        
        # 1. Open Chart
        chart_id = mt5.chart_open(symbol, mt5.TIMEFRAME_M15)
        if chart_id == 0:
            return f"Error: Could not open chart for {symbol}"
            
        # 2. Apply template
        if apply_bot_template(chart_id, symbol):
            return f"Success: Bot launched on {symbol} (Chart ID: {chart_id})"
        else:
            return f"Error: Chart opened but EA attachment failed. Check MT5 logs."
            
    except Exception as e:
        logger.error(f"Launch failed: {e}")
        return f"Exception: {e}"

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
