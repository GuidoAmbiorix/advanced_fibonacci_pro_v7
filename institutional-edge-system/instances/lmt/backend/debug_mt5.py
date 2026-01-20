import rpyc
import time
import os

# Configuration (mirrors Docker environment)
MT5_HOST = "localhost" # Testing from host against mapped port
MT5_PORT = 9011 # Assuming we might map 8001->9011 or similar, but wait, internal is 8001. 
# User said "Connecting to MT5 Service at mt5:8001..." inside container.
# Externally, we need to know the port mapping. 
# Checking docker-compose.admin.yml... it doesn't map MT5 port.
# However, usually the broker/mt5 container exposes a port.
# Let's assume we run this LOCALLY on the machine, so we need to hit localhost:18812 (default) or whatever port the MT5 container uses.
# Wait, user logs show: "Connecting to MT5 Service at mt5:8001" (internal).

# Let's try to connect to the internal network or the exposed port.
# If I run this script on the host, I need the exposed port.
# I will check `docker ps` for exposed ports for the `mt5` service (implied).
# But checking the file list, I see `docker-compose.yml` which likely defines the MT5 service.
# I'll presume for now we can't easily run this outside without port mapping.
# BETTER STRATEGY: Create this script and copy it INTO the fleet_commander container to run it.

def debug_connection():
    host = "mt5"
    port = 8001
    
    print(f"--- MT5 Debug Tool ---")
    print(f"Target: {host}:{port}")
    
    try:
        config = {'sync_request_timeout': 30, 'allow_pickle': True}
        print("1. Connecting RPyC...")
        conn = rpyc.classic.connect(host, port, config=config)
        mt5 = conn.modules.MetaTrader5
        print("   [OK] RPyC Connected")
        
        print("2. Initializing MT5...")
        if not mt5.initialize():
             print(f"   [FAIL] Initialize: {mt5.last_error()}")
             return
        print("   [OK] Initialized")
        
        # Test Credentials
        credentials = [
            (49290627, "Motivo@1", "HFMarketsGlobal-Demo"), # .env
            (11258247, "?", "?") # Seen in logs (Auto-11258247)
        ]
        
        for login, pwd, server in credentials:
             print(f"\n3. Testing Login: {login}")
             if mt5.login(login, pwd, server):
                  info = mt5.account_info()
                  print(f"   [SUCCESS] Balance: {info.balance}")
             else:
                  print(f"   [FAIL] {mt5.last_error()}")
                  
        # Test Loop
        print("\n4. Stability Test (10s)...")
        for i in range(10):
             try:
                 tick = mt5.symbol_info_tick("EURUSD")
                 print(f"   Tick {i}: {tick.bid if tick else 'None'}")
                 time.sleep(1)
             except Exception as e:
                 print(f"   [ERROR] Connection lost: {e}")
                 break
                 
    except Exception as e:
        print(f"[CRITICAL] {e}")

if __name__ == "__main__":
    debug_connection()
