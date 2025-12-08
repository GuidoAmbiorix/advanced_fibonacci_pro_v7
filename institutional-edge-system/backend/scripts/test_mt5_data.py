import MetaTrader5 as mt5
from datetime import datetime, timedelta, timezone
import pandas as pd

def test_mt5_data():
    if not mt5.initialize():
        print("initialize() failed, error code =", mt5.last_error())
        quit()

    symbol = "EURCHF"
    timeframe = mt5.TIMEFRAME_M5
    
    # Create naive datetimes matching the backtest request
    start_date = datetime(2023, 1, 1)
    end_date = datetime(2023, 12, 31)
    
    print(f"Attempting to fetch {symbol} M5 from {start_date} to {end_date}")
    
    # Ensure symbol is selected
    if not mt5.symbol_select(symbol, True):
        print(f"Failed to select {symbol}")
        return

    # Test 5: Try full year with chunking (The Fix)
    print("\nTest 5: Full Year with Chunking (The Fix)")
    
    all_rates = []
    current_start = start_date
    
    while current_start < end_date:
        current_end = min(current_start + timedelta(days=30), end_date)
        print(f"Fetching chunk: {current_start} to {current_end}")
        
        rates = mt5.copy_rates_range(symbol, timeframe, current_start, current_end)
        if rates is not None and len(rates) > 0:
            all_rates.extend(rates)
        else:
            # Check error
            error = mt5.last_error()
            if error[0] != 1: # 1 = No data
                print(f"Chunk failed or empty: {error}")
            
        current_start = current_end

    print(f"Total bars loaded: {len(all_rates)}")
    if len(all_rates) > 0:
        print("✅ Chunking strategy SUCCESS!")
    else:
        print("❌ Chunking strategy FAILED")

    mt5.shutdown()

if __name__ == "__main__":
    test_mt5_data()
