import rpyc
import os
import sys

def debug():
    host = os.environ.get('MT5_HOST', 'mt5')
    port = 8001
    print(f"Connecting to {host}:{port}...")
    try:
        conn = rpyc.classic.connect(host, port)
        print("Connected!")
        mt5 = conn.modules.MetaTrader5
        print(f"MetaTrader5 module: {mt5}")
        
        attrs = dir(mt5)
        print(f"Attributes: {attrs}")
        
        if 'global_variable_get' in attrs:
            print("✓ global_variable_get exists")
        else:
            print("✗ global_variable_get MISSING")
            # Look for alternatives
            alternatives = [a for a in attrs if 'variable' in a.lower()]
            print(f"Potential alternatives: {alternatives}")
            
        # Try to get version
        try:
            print(f"MT5 Version: {mt5.version()}")
        except:
            print("Could not get version")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    debug()
