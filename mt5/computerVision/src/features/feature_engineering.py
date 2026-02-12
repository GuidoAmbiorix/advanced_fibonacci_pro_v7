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

# Import advanced features
try:
    from .advanced_features import create_all_advanced_features, get_advanced_feature_list
    ADVANCED_FEATURES_AVAILABLE = True
except ImportError:
    ADVANCED_FEATURES_AVAILABLE = False
    print("WARNING: Advanced features module not available.")


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


def create_talib_features(df: pd.DataFrame, use_advanced: bool = True) -> pd.DataFrame:
    """
    Create advanced features using TA-Lib.
    
    Args:
        df: DataFrame with OHLCV data (must have: open, high, low, close, volume)
        use_advanced: If True, include all 150+ advanced features
        
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
    
    # ==================== CORE INDICATORS (Always included) ====================
    
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
    
    # ==================== PATTERN RECOGNITION (Basic) ====================
    
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
    
    # ==================== ADVANCED FEATURES (150+) ====================
    
    if use_advanced and ADVANCED_FEATURES_AVAILABLE:
        print("🚀 Adding 150+ advanced TA-Lib features...")
        df = create_all_advanced_features(df)
    
    return df



def get_feature_list(use_talib: bool = True, use_advanced: bool = True) -> list:
    """
    Get list of feature names for model training.
    
    Args:
        use_talib: Whether to include TA-Lib features
        use_advanced: Whether to include advanced features (150+)
        
    Returns:
        List of feature column names
    """
    if use_talib and TALIB_AVAILABLE:
        # Core features (always included)
        core_features = [
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
        
        # Add advanced features if available
        if use_advanced and ADVANCED_FEATURES_AVAILABLE:
            advanced_features = get_advanced_feature_list()
            return core_features + advanced_features
        
        return core_features
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
        df = create_talib_features(df, use_advanced=False)  # Disable 150+ features
    else:
        df = create_basic_features(df)
    
    # Create labels using Triple Barrier Method
    # PHASE 3.2: Extended to 24 bars for full trading day (H1 = 24 hours)
    # Longer horizon filters noise and improves win rate at cost of trade frequency
    # Triple Barrier ensures labels represent PROFITABLE trades (after 0.10% fees)
    from src.training.labeling import triple_barrier_labels
    import talib

    prediction_horizon = 24  # Was 12 (24 hours = full trading day)

    # Calculate ATR for dynamic barriers
    atr = talib.ATR(df['high'].values, df['low'].values, df['close'].values, timeperiod=14)
    atr_series = pd.Series(atr, index=df.index)

    # Triple Barrier BALANCED for realistic profitability (CRITICAL FIX v2)
    # Previous: pt_sl=[6.0, 3.0] was TOO STRICT → max prob 0.054 → model unconfident
    # Solution: Use moderate barriers that are achievable but still selective
    # pt_sl=[3.0, 2.0] means TP at 3x ATR, SL at 2x ATR (1.5:1 reward:risk)
    # With trailing stops, we can let winners run beyond the 3x ATR target
    df['label_raw'] = triple_barrier_labels(
        prices=df['close'],
        volatility=atr_series,
        time_horizon_bars=prediction_horizon,
        pt_sl=[3.0, 2.0],  # TP at 3x ATR, SL at 2x ATR (balanced, achievable)
        min_ret=0.0002,    # 0.02% minimum (covers fees)
        vertical_barrier=True
    )

    # Binary: 1=TP hit (profitable), 0=SL/time barrier (not profitable)
    df['label'] = (df['label_raw'] == 1).astype(int)

    # Log label distribution
    label_dist = df['label'].value_counts()
    total = len(df['label'].dropna())
    if total > 0:
        pct_profitable = (label_dist.get(1, 0) / total) * 100
        pct_unprofitable = (label_dist.get(0, 0) / total) * 100
        print(f"   📊 Label Distribution: Profitable={pct_profitable:.1f}%, Unprofitable={pct_unprofitable:.1f}%")

    # Feature Selection: Reduce to top 35 features
    selected_features = None
    if use_talib and TALIB_AVAILABLE:
        from src.training.feature_selection import FeatureSelector

        # Get initial feature list
        initial_features = get_feature_list(use_talib=True, use_advanced=False)
        initial_features = [f for f in initial_features if f in df.columns]

        # Only run feature selection if we have more than 35 features
        if len(initial_features) > 35:
            print(f"🔍 Selecting top 35 features from {len(initial_features)} candidates...")

            # Prepare data for feature selection (drop NaNs temporarily)
            df_temp = df[initial_features + ['label']].dropna()
            X_temp = df_temp[initial_features]
            y_temp = df_temp['label']

            # Select features
            selector = FeatureSelector(n_estimators=100, random_state=42)
            selected_features = selector.select_features(X_temp, y_temp, n_features=35)

            print(f"✅ Selected {len(selected_features)} features")
        else:
            selected_features = initial_features
            print(f"✅ Using all {len(selected_features)} features (already < 35)")

    # Drop NaN values
    # IMPORTANT: NaN rows appear at BOTH ends:
    # - Beginning: Due to lagging indicators (MA, RSI, etc.) requiring warmup
    # - End: Due to shift(-prediction_horizon) looking forward

    # Track exact NaN locations BEFORE dropping
    original_len = len(df)
    nan_mask = df.isnull().any(axis=1)

    # Find first and last valid indices
    valid_indices = df[~nan_mask].index
    if len(valid_indices) > 0:
        first_valid = valid_indices[0]
        last_valid = valid_indices[-1]
        nans_at_start = first_valid
        nans_at_end = original_len - 1 - last_valid
    else:
        nans_at_start = 0
        nans_at_end = 0

    # Drop NaNs
    df = df.dropna()

    # Log precise NaN drop info for alignment verification
    total_nans = original_len - len(df)
    print(f"   ✅ NaN Analysis: Original={original_len}, Final={len(df)}")
    print(f"      - NaNs at START: {nans_at_start} (warmup period)")
    print(f"      - NaNs at END: {nans_at_end} (prediction horizon={prediction_horizon})")
    print(f"      - Total dropped: {total_nans}")
    
    # Get feature columns
    if selected_features is not None:
        # Use selected features from feature selection
        feature_names = selected_features
    else:
        # Fallback to default feature list
        feature_names = get_feature_list(use_talib and TALIB_AVAILABLE, use_advanced=False)
        # Filter to only existing columns
        feature_names = [f for f in feature_names if f in df.columns]
    
    X = df[feature_names]
    y = df['label']

    # CRITICAL: Return the aligned dataframe for proper price alignment
    # The returned df has NaNs already dropped and aligns perfectly with X and y
    return X, y, feature_names, df
