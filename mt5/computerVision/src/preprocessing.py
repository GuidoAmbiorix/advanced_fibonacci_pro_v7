import numpy as np
import pandas as pd
from sklearn.preprocessing import MinMaxScaler

def create_images(data, window_size=48, prediction_window=24):
    """
    Converts time series data into 'images' for the CNN.
    
    Args:
        data (pd.DataFrame): Input OHLC data.
        window_size (int): Size of the input window (width of the image).
        prediction_window (int): Horizon for prediction target.
        
    Returns:
        tuple: (images, targets) arrays.
    """
    images = []
    targets = []
    
    # Ensure we have enough data
    if len(data) < window_size + prediction_window:
        return np.array([]), np.array([])
    
    # Using OHLC data to create images
    # We iterate until we can't form a full target window anymore
    for i in range(len(data) - window_size - prediction_window):
        window_data = data.iloc[i:i+window_size]
        target_data = data.iloc[i+window_size:i+window_size+prediction_window]
        
        # Normalize data in the window locally to capture relative shape
        # Each window is normalized independently to be translation invariant in price
        scaler = MinMaxScaler(feature_range=(0, 1))
        # We use Open, High, Low, Close for the 4 'channels'
        window_scaled = scaler.fit_transform(window_data[['open', 'high', 'low', 'close']])
        
        # Predict price direction (up/down) for the forecast period
        # Target: 1 if future close > current close, else 0
        current_close = window_data['close'].iloc[-1]
        future_close = target_data['close'].iloc[-1]
        
        price_direction = 1 if future_close > current_close else 0
        
        images.append(window_scaled)
        targets.append(price_direction)
    
    return np.array(images), np.array(targets)
