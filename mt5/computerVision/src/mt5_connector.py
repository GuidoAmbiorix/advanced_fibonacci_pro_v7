import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime, timedelta

def connect_to_mt5():
    """
    Initializes connection to MetaTrader 5 terminal.
    Returns:
        bool: True if connection successful, False otherwise.
    """
    if not mt5.initialize():
        print("Error initializing MetaTrader5")
        mt5.shutdown()
        return False
    return True

def get_historical_data(symbol="EURUSD", timeframe=mt5.TIMEFRAME_H1, num_bars=1000):
    """
    Retrieves historical OHLC data from MT5.
    
    Args:
        symbol (str): Symbol to retrieve.
        timeframe (int): MT5 timeframe constant.
        num_bars (int): Number of bars to retrieve.
        
    Returns:
        pd.DataFrame: DataFrame with time index and OHLC columns.
    """
    # Calculate start date based on number of bars and timeframe (approximate)
    # This is a rough estimation, copy_rates_from_pos might be safer if exact count needed
    # using copy_rates_from_pos to get exact number of recent bars
    
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, num_bars)
    
    if rates is None or len(rates) == 0:
        print(f"Error loading historical quotes for {symbol}")
        return None
    
    # Convert to pandas DataFrame
    rates_frame = pd.DataFrame(rates)
    rates_frame['time'] = pd.to_datetime(rates_frame['time'], unit='s')
    rates_frame.set_index('time', inplace=True)
    
    return rates_frame
