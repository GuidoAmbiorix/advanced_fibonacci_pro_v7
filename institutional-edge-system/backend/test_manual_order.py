import sys
import os
import logging

# Configure logging to stdout
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add current dir to path so we can import app modules
sys.path.append(os.getcwd())

try:
    from app.core.mt5_connector import MT5Connector
    from app.core.config import settings
except ImportError as e:
    print(f"Import Error: {e}")
    # Fallback for running inside container where app might be top level or not
    sys.path.append(os.path.join(os.getcwd(), '..'))
    from app.core.mt5_connector import MT5Connector
    from app.core.config import settings

def test_order():
    print("--- Starting Manual Order Test ---")
    
    # Initialize connector
    # Mocking settings if needed, or loading from env
    connector = MT5Connector(settings.dict())
    
    if not connector.connect():
        print("❌ Failed to connect to MT5 Terminal")
        return

    print("✅ Connected to MT5")
    
    account = connector.get_account_info()
    print(f"ℹ️ Account: {account.get('login')} | Balance: {account.get('balance')}")

    # TEST PARAMETERS
    symbol = "GBPJPY"
    volume = 0.01
    order_type = "BUY"
    
    print(f"\n🚀 Attempting {order_type} {volume} lots of {symbol}...")
    
    # This call uses the updated 'open_position' with retry logic
    result = connector.open_position(
        symbol=symbol,
        order_type=order_type,
        volume=volume,
        comment="ManualTest_Antigravity"
    )
    
    if result and result.get("success") is not False: # check for explicit False or existence
        # Our open_position returns dict. Success usually implies keys like 'order', 'price' or handled in wrapper
        # The updated open_position returns a dict.
        print(f"✅ Result: {result}")
    else:
        print(f"❌ FAILED. Result: {result}")

    connector.disconnect()
    print("\n--- Test Complete ---")

if __name__ == "__main__":
    test_order()
