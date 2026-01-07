
import os
import rpyc
from datetime import datetime, timezone

MT5_HOST = os.getenv("MT5_HOST", "mt5")
MT5_PORT = int(os.getenv("MT5_PORT", 8001))

def debug_data():
    try:
        conn = rpyc.classic.connect(MT5_HOST, MT5_PORT)
        mt5 = conn.modules.MetaTrader5
        if not mt5.initialize(): return

        symbol = "XAUUSD"
        
        for tf_name, tf_val in [("M5", mt5.TIMEFRAME_M5), ("M30", mt5.TIMEFRAME_M30)]:
             print(f"--- Checking {tf_name} ---")
             rates = mt5.copy_rates_from_pos(symbol, tf_val, 0, 100000) # Request max chart bars
             if rates is not None and len(rates) > 0:
                 oldest = rates[0]
                 newest = rates[-1]
                 d_old = datetime.fromtimestamp(oldest[0], timezone.utc)
                 d_new = datetime.fromtimestamp(newest[0], timezone.utc)
                 print(f"Count: {len(rates)}")
                 print(f"Oldest: {d_old}")
                 print(f"Newest: {d_new}")
                 
                 # Check if we can go deeper
                 rates_deep = mt5.copy_rates_from_pos(symbol, tf_val, 100000, 1)
                 if rates_deep is not None and len(rates_deep) > 0:
                      print(f"Data exists beyond 100k!")
                      print(f"Bar 100001: {datetime.fromtimestamp(rates_deep[0][0], timezone.utc)}")
                 else:
                      print("No data beyond 100k bars (from pos)")
                      
             else:
                 print("No data returned")

    except Exception as e:
        print(e)

if __name__ == "__main__":
    debug_data()
