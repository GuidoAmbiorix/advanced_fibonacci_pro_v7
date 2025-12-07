import MetaTrader5 as mt5
from datetime import datetime, timedelta
import pandas as pd

def test_data():
    if not mt5.initialize():
        print("MT5 init failed")
        return

    symbol = "EURUSD"
    if not mt5.symbol_select(symbol, True):
        print(f"Failed to select {symbol}")
        return

    # Try last 30 days
    end = datetime.utcnow()
    start = end - timedelta(days=30)
    
    print(f"Fetching {symbol} M15 from {start} to {end}")
    
    rates = mt5.copy_rates_range(symbol, mt5.TIMEFRAME_M15, start, end)
    
    if rates is None:
        print(f"Failed. Error: {mt5.last_error()}")
    else:
        print(f"Success! Retrieved {len(rates)} bars")
        df = pd.DataFrame(rates)
        print(df.head())
        print(df.tail())

    mt5.shutdown()

if __name__ == "__main__":
    test_data()
