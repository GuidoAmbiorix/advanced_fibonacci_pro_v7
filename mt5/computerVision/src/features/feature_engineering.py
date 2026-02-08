"""
Advanced Feature Engineering Module using TA-Lib

This module creates professional technical indicators for trading models.
"""

import pandas as pd
import numpy as np

try:
    import talib
    TALIB_AVAILABLE = True
except ImportError:
    TALIB_AVAILABLE = False
    print("WARNING: TA-Lib not installed. Using basic features only.")


def create_basic_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Create basic features without TA-Lib (fallback).
    
    Args:
        df: DataFrame with OHLCV data
        
    Returns:
        DataFrame with basic features added
    """
    df = df.copy()
    
    # Price changes
    df['price_change'] = df['close'].pct_change()
    df['high_low_range'] = (df['high'] - df['low']) / df['close']
    
    # Simple moving averages
    df['ma_5'] = df['close'].rolling(5).mean()
    df['ma_10'] = df['close'].rolling(10).mean()
    df['ma_20'] = df['close'].rolling(20).mean()
    df['ma_cross'] = df['ma_5'] - df['ma_10']
    
    # Momentum
    df['momentum'] = df['close'] - df['close'].shift(5)
    df['momentum_pct'] = df['close'].pct_change(5)
    
    # Volume
    if 'tick_volume' in df.columns:
        df['volume_change'] = df['tick_volume'].pct_change()
        df['volume_ma'] = df['tick_volume'].rolling(10).mean()
    
    return df


def create_talib_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Create advanced features using TA-Lib.
    
    Args:
        df: DataFrame with OHLCV data (must have: open, high, low, close, volume)
        
    Returns:
        DataFrame with TA-Lib features added
    """
    if not TALIB_AVAILABLE:
        print("TA-Lib not available, using basic features")
        return create_basic_features(df)
    
    df = df.copy()
    
    # Convert to numpy arrays for TA-Lib (must be float64)
    open_prices = df['open'].astype('float64').values
    high_prices = df['high'].astype('float64').values
    low_prices = df['low'].astype('float64').values
    close_prices = df['close'].astype('float64').values
    volume = (df['tick_volume'].astype('float64').values if 'tick_volume' in df.columns 
              else df['real_volume'].astype('float64').values)
    
    # ==================== TREND INDICATORS ====================
    
    # ADX - Average Directional Movement Index
    df['ADX'] = talib.ADX(high_prices, low_prices, close_prices, timeperiod=14)
    
    # MACD - Moving Average Convergence Divergence
    df['MACD'], df['MACD_signal'], df['MACD_hist'] = talib.MACD(
        close_prices, fastperiod=12, slowperiod=26, signalperiod=9
    )
    
    # Parabolic SAR
    df['SAR'] = talib.SAR(high_prices, low_prices, acceleration=0.02, maximum=0.2)
    
    # Moving Averages
    df['SMA_10'] = talib.SMA(close_prices, timeperiod=10)
    df['SMA_20'] = talib.SMA(close_prices, timeperiod=20)
    df['SMA_50'] = talib.SMA(close_prices, timeperiod=50)
    df['EMA_10'] = talib.EMA(close_prices, timeperiod=10)
    df['EMA_20'] = talib.EMA(close_prices, timeperiod=20)
    
    # ==================== MOMENTUM INDICATORS ====================
    
    # RSI - Relative Strength Index
    df['RSI'] = talib.RSI(close_prices, timeperiod=14)
    
    # Stochastic Oscillator
    df['STOCH_K'], df['STOCH_D'] = talib.STOCH(
        high_prices, low_prices, close_prices,
        fastk_period=14, slowk_period=3, slowd_period=3
    )
    
    # Williams %R
    df['WILLR'] = talib.WILLR(high_prices, low_prices, close_prices, timeperiod=14)
    
    # Rate of Change
    df['ROC'] = talib.ROC(close_prices, timeperiod=10)
    
    # Commodity Channel Index
    df['CCI'] = talib.CCI(high_prices, low_prices, close_prices, timeperiod=14)
    
    # ==================== VOLATILITY INDICATORS ====================
    
    # ATR - Average True Range
    df['ATR'] = talib.ATR(high_prices, low_prices, close_prices, timeperiod=14)
    
    # Bollinger Bands
    df['BB_upper'], df['BB_middle'], df['BB_lower'] = talib.BBANDS(
        close_prices, timeperiod=20, nbdevup=2, nbdevdn=2
    )
    df['BB_width'] = (df['BB_upper'] - df['BB_lower']) / df['BB_middle']
    df['BB_position'] = (close_prices - df['BB_lower']) / (df['BB_upper'] - df['BB_lower'])
    
    # ==================== VOLUME INDICATORS ====================
    
    # OBV - On Balance Volume
    df['OBV'] = talib.OBV(close_prices, volume)
    
    # Money Flow Index
    df['MFI'] = talib.MFI(high_prices, low_prices, close_prices, volume, timeperiod=14)
    
    # Chaikin A/D Line
    df['AD'] = talib.AD(high_prices, low_prices, close_prices, volume)
    
    # ==================== PATTERN RECOGNITION ====================
    
    # Candlestick patterns (returns -100, 0, or 100)
    df['CDLDOJI'] = talib.CDLDOJI(open_prices, high_prices, low_prices, close_prices)
    df['CDLHAMMER'] = talib.CDLHAMMER(open_prices, high_prices, low_prices, close_prices)
    df['CDLENGULFING'] = talib.CDLENGULFING(open_prices, high_prices, low_prices, close_prices)
    
    # ==================== DERIVED FEATURES ====================
    
    # Trend strength
    df['trend_strength'] = abs(df['MACD_hist'])
    
    # Volatility ratio
    df['volatility_ratio'] = df['ATR'] / close_prices
    
    # Price position relative to MA
    df['price_vs_sma20'] = (close_prices - df['SMA_20']) / df['SMA_20']
    df['price_vs_ema20'] = (close_prices - df['EMA_20']) / df['EMA_20']
    
    # RSI divergence
    df['RSI_change'] = df['RSI'].diff()
    
    return df


def get_feature_list(use_talib: bool = True) -> list:
    """
    Get list of feature names for model training.
    
    Args:
        use_talib: Whether to include TA-Lib features
        
    Returns:
        List of feature column names
    """
    if use_talib and TALIB_AVAILABLE:
        return [
            # Trend
            'ADX', 'MACD', 'MACD_signal', 'MACD_hist',
            'SMA_10', 'SMA_20', 'EMA_10', 'EMA_20',
            
            # Momentum
            'RSI', 'STOCH_K', 'STOCH_D', 'WILLR', 'ROC', 'CCI',
            
            # Volatility
            'ATR', 'BB_width', 'BB_position', 'volatility_ratio',
            
            # Volume
            'OBV', 'MFI', 'AD',
            
            # Derived
            'trend_strength', 'price_vs_sma20', 'price_vs_ema20', 'RSI_change'
        ]
    else:
        return [
            'price_change', 'high_low_range',
            'ma_5', 'ma_10', 'ma_20', 'ma_cross',
            'momentum', 'momentum_pct',
            'volume_change', 'volume_ma'
        ]


def prepare_training_data(df: pd.DataFrame, use_talib: bool = True) -> tuple:
    """
    Prepare data for model training with features and labels.
    
    Args:
        df: Raw OHLCV DataFrame
        use_talib: Whether to use TA-Lib features
        
    Returns:
        (features_df, labels, feature_names)
    """
    # Create features
    if use_talib and TALIB_AVAILABLE:
        df = create_talib_features(df)
    else:
        df = create_basic_features(df)
    
    # Create labels (1 = price goes up, 0 = price goes down)
    df['future_return'] = df['close'].shift(-1) / df['close'] - 1
    df['label'] = (df['future_return'] > 0).astype(int)
    
    # Drop NaN values
    df = df.dropna()
    
    # Get feature columns
    feature_names = get_feature_list(use_talib and TALIB_AVAILABLE)
    
    # Filter to only existing columns
    feature_names = [f for f in feature_names if f in df.columns]
    
    X = df[feature_names]
    y = df['label']
    
    return X, y, feature_names
