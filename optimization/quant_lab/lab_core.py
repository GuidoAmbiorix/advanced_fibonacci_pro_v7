import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime
import os

# --- MT5 CONNECTION ---
def connect_mt5():
    if not mt5.initialize():
        print("❌ MT5 Initialization failed")
        return False
    print("✅ MT5 Connected")
    return True

def shutdown_mt5():
    mt5.shutdown()

def fetch_data(symbol, timeframe, bars=10000):
    """Fetch OHLCV data from MT5"""
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars)
    if rates is None:
        print(f"❌ Failed to fetch data for {symbol}")
        return None
    
    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    return df

# --- FEATURE ENGINEERING ---
def calculate_rsi(series, period=14):
    delta = series.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    return 100 - (100 / (1 + rs))

def calculate_atr(df, period=14):
    high_low = df['high'] - df['low']
    high_close = np.abs(df['high'] - df['close'].shift())
    low_close = np.abs(df['low'] - df['close'].shift())
    ranges = pd.concat([high_low, high_close, low_close], axis=1)
    true_range = ranges.max(axis=1)
    return true_range.rolling(window=period).mean()

def prepare_features(df):
    """
    Calculate Technical Indicators (The 'Menu' for Genetic Programming)
    """
    df = df.copy()
    
    # 1. Price Action
    df['Returns'] = df['close'].pct_change()
    df['Log_Returns'] = np.log(df['close'] / df['close'].shift(1))
    
    # 2. Moving Averages
    df['SMA_20'] = df['close'].rolling(window=20).mean()
    df['SMA_50'] = df['close'].rolling(window=50).mean()
    df['SMA_200'] = df['close'].rolling(window=200).mean()
    
    # Distance from MAs (Normalized)
    df['Dist_SMA20'] = (df['close'] - df['SMA_20']) / df['close']
    df['Dist_SMA200'] = (df['close'] - df['SMA_200']) / df['close']
    
    # 3. Momentum
    df['RSI_14'] = calculate_rsi(df['close'], 14)
    df['Momentum_10'] = df['close'] - df['close'].shift(10)
    
    # 4. Volatility
    df['ATR_14'] = calculate_atr(df, 14)
    df['Rel_Vol'] = df['ATR_14'] / df['close'] # Relative Volatility
    
    # 5. Volume
    df['Vol_SMA_20'] = df['tick_volume'].rolling(window=20).mean()
    df['Rel_Volume'] = df['tick_volume'] / df['Vol_SMA_20']
    
    # --- TARGET GENERATION (What we want to predict) ---
    # Prediction: Return 5 bars into the future
    prediction_horizon = 5
    df['Target_Return'] = df['close'].shift(-prediction_horizon) / df['close'] - 1.0
    
    # Classification Target: 1 if Up, -1 if Down (with threshold)
    threshold = 0.0005 # 0.05% move required to care
    df['Target_Class'] = 0
    df['Target_Class'] = np.where(df['Target_Return'] > threshold, 1, df['Target_Class'])
    df['Target_Class'] = np.where(df['Target_Return'] < -threshold, -1, df['Target_Class'])
    
    # Cleanup
    df.dropna(inplace=True)
    return df
