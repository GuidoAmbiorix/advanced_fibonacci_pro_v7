import sys

try:
    import MetaTrader5 as mt5
    print(f"MetaTrader5 package found. Version: {mt5.__version__}")
    
    if mt5.initialize():
        print("MT5 initialized successfully")
        print(f"Terminal Info: {mt5.terminal_info()}")
        print(f"Version: {mt5.version()}")
        mt5.shutdown()
    else:
        print(f"MT5 initialization failed. Error: {mt5.last_error()}")
        
except ImportError:
    print("MetaTrader5 package NOT installed")
except Exception as e:
    print(f"An error occurred: {e}")
