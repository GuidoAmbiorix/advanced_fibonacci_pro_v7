
import os
import rpyc
import sys

# Get env vars
MT5_HOST = os.getenv("MT5_HOST", "mt5")
MT5_PORT = int(os.getenv("MT5_PORT", 8001))
LOGIN = int(os.getenv("MT5_LOGIN", 0))
PASSWORD = os.getenv("MT5_PASSWORD", "")
SERVER = os.getenv("MT5_SERVER", "")

print(f"DEBUG: Host={MT5_HOST}:{MT5_PORT}")
print(f"DEBUG: Creds={LOGIN} / {PASSWORD} / {SERVER}")

try:
    print(f"Connecting to RPyC...")
    conn = rpyc.classic.connect(MT5_HOST, MT5_PORT)
    mt5 = conn.modules.MetaTrader5
    print("RPyC Connected.")
    
    print("Initializing MT5...")
    # Try with explicit path if needed, but rpyc usually uses default
    res = mt5.initialize(login=LOGIN, password=PASSWORD, server=SERVER)
    
    if not res:
        err = mt5.last_error()
        print(f"❌ INITIALIZE FAILED. Error: {err}")
        sys.exit(1)
        
    print("✅ INITIALIZE SUCCESS")
    
    print("Logging in...")
    res_login = mt5.login(login=LOGIN, password=PASSWORD, server=SERVER)
    
    if not res_login:
        err = mt5.last_error()
        print(f"❌ LOGIN FAILED. Error: {err}")
        sys.exit(1)
        
    print("✅ LOGIN SUCCESS")
    
    info = mt5.account_info()
    if info:
        print(f"Account: {info.login} {info.name} Balance: {info.balance}")
    else:
        print("Could not get account info")

except Exception as e:
    print(f"EXCEPTION: {e}")
