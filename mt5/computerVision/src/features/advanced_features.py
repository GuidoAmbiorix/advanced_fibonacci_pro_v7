"""
Advanced Feature Engineering Module - Maximum TA-Lib Exploitation

This module extracts ALL available TA-Lib indicators to maximize
trading signal quality and model performance.
"""

import pandas as pd
import numpy as np

try:
    import talib
    TALIB_AVAILABLE = True
except ImportError:
    TALIB_AVAILABLE = False
    print("WARNING: TA-Lib not installed. Advanced features unavailable.")


def create_pattern_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Extract ALL 60+ candlestick patterns from TA-Lib.
    
    Returns aggregated pattern scores for model training.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    
    # Convert to numpy arrays
    open_prices = df['open'].astype('float64').values
    high_prices = df['high'].astype('float64').values
    low_prices = df['low'].astype('float64').values
    close_prices = df['close'].astype('float64').values
    
    # All 60+ candlestick patterns
    patterns = {
        'CDL2CROWS': talib.CDL2CROWS,
        'CDL3BLACKCROWS': talib.CDL3BLACKCROWS,
        'CDL3INSIDE': talib.CDL3INSIDE,
        'CDL3LINESTRIKE': talib.CDL3LINESTRIKE,
        'CDL3OUTSIDE': talib.CDL3OUTSIDE,
        'CDL3STARSINSOUTH': talib.CDL3STARSINSOUTH,
        'CDL3WHITESOLDIERS': talib.CDL3WHITESOLDIERS,
        'CDLABANDONEDBABY': talib.CDLABANDONEDBABY,
        'CDLADVANCEBLOCK': talib.CDLADVANCEBLOCK,
        'CDLBELTHOLD': talib.CDLBELTHOLD,
        'CDLBREAKAWAY': talib.CDLBREAKAWAY,
        'CDLCLOSINGMARUBOZU': talib.CDLCLOSINGMARUBOZU,
        'CDLCONCEALBABYSWALL': talib.CDLCONCEALBABYSWALL,
        'CDLCOUNTERATTACK': talib.CDLCOUNTERATTACK,
        'CDLDARKCLOUDCOVER': talib.CDLDARKCLOUDCOVER,
        'CDLDOJI': talib.CDLDOJI,
        'CDLDOJISTAR': talib.CDLDOJISTAR,
        'CDLDRAGONFLYDOJI': talib.CDLDRAGONFLYDOJI,
        'CDLENGULFING': talib.CDLENGULFING,
        'CDLEVENINGDOJISTAR': talib.CDLEVENINGDOJISTAR,
        'CDLEVENINGSTAR': talib.CDLEVENINGSTAR,
        'CDLGAPSIDESIDEWHITE': talib.CDLGAPSIDESIDEWHITE,
        'CDLGRAVESTONEDOJI': talib.CDLGRAVESTONEDOJI,
        'CDLHAMMER': talib.CDLHAMMER,
        'CDLHANGINGMAN': talib.CDLHANGINGMAN,
        'CDLHARAMI': talib.CDLHARAMI,
        'CDLHARAMICROSS': talib.CDLHARAMICROSS,
        'CDLHIGHWAVE': talib.CDLHIGHWAVE,
        'CDLHIKKAKE': talib.CDLHIKKAKE,
        'CDLHIKKAKEMOD': talib.CDLHIKKAKEMOD,
        'CDLHOMINGPIGEON': talib.CDLHOMINGPIGEON,
        'CDLIDENTICAL3CROWS': talib.CDLIDENTICAL3CROWS,
        'CDLINNECK': talib.CDLINNECK,
        'CDLINVERTEDHAMMER': talib.CDLINVERTEDHAMMER,
        'CDLKICKING': talib.CDLKICKING,
        'CDLKICKINGBYLENGTH': talib.CDLKICKINGBYLENGTH,
        'CDLLADDERBOTTOM': talib.CDLLADDERBOTTOM,
        'CDLLONGLEGGEDDOJI': talib.CDLLONGLEGGEDDOJI,
        'CDLLONGLINE': talib.CDLLONGLINE,
        'CDLMARUBOZU': talib.CDLMARUBOZU,
        'CDLMATCHINGLOW': talib.CDLMATCHINGLOW,
        'CDLMATHOLD': talib.CDLMATHOLD,
        'CDLMORNINGDOJISTAR': talib.CDLMORNINGDOJISTAR,
        'CDLMORNINGSTAR': talib.CDLMORNINGSTAR,
        'CDLONNECK': talib.CDLONNECK,
        'CDLPIERCING': talib.CDLPIERCING,
        'CDLRICKSHAWMAN': talib.CDLRICKSHAWMAN,
        'CDLRISEFALL3METHODS': talib.CDLRISEFALL3METHODS,
        'CDLSEPARATINGLINES': talib.CDLSEPARATINGLINES,
        'CDLSHOOTINGSTAR': talib.CDLSHOOTINGSTAR,
        'CDLSHORTLINE': talib.CDLSHORTLINE,
        'CDLSPINNINGTOP': talib.CDLSPINNINGTOP,
        'CDLSTALLEDPATTERN': talib.CDLSTALLEDPATTERN,
        'CDLSTICKSANDWICH': talib.CDLSTICKSANDWICH,
        'CDLTAKURI': talib.CDLTAKURI,
        'CDLTASUKIGAP': talib.CDLTASUKIGAP,
        'CDLTHRUSTING': talib.CDLTHRUSTING,
        'CDLTRISTAR': talib.CDLTRISTAR,
        'CDLUNIQUE3RIVER': talib.CDLUNIQUE3RIVER,
        'CDLUPSIDEGAP2CROWS': talib.CDLUPSIDEGAP2CROWS,
        'CDLXSIDEGAP3METHODS': talib.CDLXSIDEGAP3METHODS,
    }
    
    # Calculate all patterns
    for name, func in patterns.items():
        try:
            df[name] = func(open_prices, high_prices, low_prices, close_prices)
        except Exception as e:
            print(f"Warning: Failed to calculate {name}: {e}")
            df[name] = 0
    
    # Aggregate pattern signals
    pattern_cols = list(patterns.keys())
    
    # Count bullish patterns (value = 100)
    df['bullish_pattern_count'] = (df[pattern_cols] == 100).sum(axis=1)
    
    # Count bearish patterns (value = -100)
    df['bearish_pattern_count'] = (df[pattern_cols] == -100).sum(axis=1)
    
    # Net pattern strength
    df['pattern_strength'] = df['bullish_pattern_count'] - df['bearish_pattern_count']
    
    # Pattern diversity (how many different patterns detected)
    df['pattern_diversity'] = (df[pattern_cols] != 0).sum(axis=1)
    
    return df


def create_cycle_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Hilbert Transform cycle indicators for market regime detection.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    close_prices = df['close'].astype('float64').values
    
    # Hilbert Transform - Dominant Cycle Period
    df['HT_DCPERIOD'] = talib.HT_DCPERIOD(close_prices)
    
    # Hilbert Transform - Dominant Cycle Phase
    df['HT_DCPHASE'] = talib.HT_DCPHASE(close_prices)
    
    # Hilbert Transform - Phasor Components
    df['HT_PHASOR_inphase'], df['HT_PHASOR_quad'] = talib.HT_PHASOR(close_prices)
    
    # Hilbert Transform - SineWave
    df['HT_SINE_sine'], df['HT_SINE_lead'] = talib.HT_SINE(close_prices)
    
    # Hilbert Transform - Trend vs Cycle Mode
    df['HT_TRENDMODE'] = talib.HT_TRENDMODE(close_prices)  # 0 = cycle, 1 = trend
    
    return df


def create_statistical_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Statistical analysis features using TA-Lib.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    high_prices = df['high'].astype('float64').values
    low_prices = df['low'].astype('float64').values
    close_prices = df['close'].astype('float64').values
    
    # Pearson's Correlation Coefficient (high vs low)
    df['CORREL'] = talib.CORREL(high_prices, low_prices, timeperiod=30)
    
    # Linear Regression
    df['LINEARREG'] = talib.LINEARREG(close_prices, timeperiod=14)
    df['LINEARREG_ANGLE'] = talib.LINEARREG_ANGLE(close_prices, timeperiod=14)
    df['LINEARREG_INTERCEPT'] = talib.LINEARREG_INTERCEPT(close_prices, timeperiod=14)
    df['LINEARREG_SLOPE'] = talib.LINEARREG_SLOPE(close_prices, timeperiod=14)
    
    # Standard Deviation
    df['STDDEV'] = talib.STDDEV(close_prices, timeperiod=5, nbdev=1)
    
    # Time Series Forecast
    df['TSF'] = talib.TSF(close_prices, timeperiod=14)
    
    # Variance
    df['VAR'] = talib.VAR(close_prices, timeperiod=5, nbdev=1)
    
    return df


def create_advanced_momentum_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Advanced momentum indicators not in basic feature set.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    high_prices = df['high'].astype('float64').values
    low_prices = df['low'].astype('float64').values
    close_prices = df['close'].astype('float64').values
    open_prices = df['open'].astype('float64').values
    volume = (df['tick_volume'].astype('float64').values if 'tick_volume' in df.columns 
              else df['real_volume'].astype('float64').values)
    
    # Aroon Indicator
    df['AROON_down'], df['AROON_up'] = talib.AROON(high_prices, low_prices, timeperiod=14)
    df['AROONOSC'] = talib.AROONOSC(high_prices, low_prices, timeperiod=14)
    
    # Balance of Power
    df['BOP'] = talib.BOP(open_prices, high_prices, low_prices, close_prices)
    
    # Chande Momentum Oscillator
    df['CMO'] = talib.CMO(close_prices, timeperiod=14)
    
    # Directional Movement Index
    df['DX'] = talib.DX(high_prices, low_prices, close_prices, timeperiod=14)
    df['MINUS_DI'] = talib.MINUS_DI(high_prices, low_prices, close_prices, timeperiod=14)
    df['PLUS_DI'] = talib.PLUS_DI(high_prices, low_prices, close_prices, timeperiod=14)
    
    # Momentum
    df['MOM'] = talib.MOM(close_prices, timeperiod=10)
    
    # Plus/Minus Directional Movement
    df['PLUS_DM'] = talib.PLUS_DM(high_prices, low_prices, timeperiod=14)
    df['MINUS_DM'] = talib.MINUS_DM(high_prices, low_prices, timeperiod=14)
    
    # Percentage Price Oscillator
    df['PPO'] = talib.PPO(close_prices, fastperiod=12, slowperiod=26, matype=0)
    
    # Stochastic RSI
    df['STOCHRSI_K'], df['STOCHRSI_D'] = talib.STOCHRSI(close_prices, timeperiod=14, 
                                                         fastk_period=5, fastd_period=3, fastd_matype=0)
    
    # Triple Exponential Derivative
    df['TRIX'] = talib.TRIX(close_prices, timeperiod=30)
    
    # Ultimate Oscillator
    df['ULTOSC'] = talib.ULTOSC(high_prices, low_prices, close_prices, 
                                 timeperiod1=7, timeperiod2=14, timeperiod3=28)
    
    return df


def create_advanced_overlap_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Advanced moving average and overlap studies.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    close_prices = df['close'].astype('float64').values
    
    # Kaufman Adaptive Moving Average
    df['KAMA'] = talib.KAMA(close_prices, timeperiod=30)
    
    # Triple Exponential Moving Average
    df['TEMA'] = talib.TEMA(close_prices, timeperiod=30)
    
    # Triangular Moving Average
    df['TRIMA'] = talib.TRIMA(close_prices, timeperiod=30)
    
    # Weighted Moving Average
    df['WMA'] = talib.WMA(close_prices, timeperiod=30)
    
    # MESA Adaptive Moving Average
    df['MAMA'], df['FAMA'] = talib.MAMA(close_prices, fastlimit=0.5, slowlimit=0.05)
    
    # T3 - Triple Exponential Moving Average
    df['T3'] = talib.T3(close_prices, timeperiod=5, vfactor=0)
    
    # Double Exponential Moving Average
    df['DEMA'] = talib.DEMA(close_prices, timeperiod=30)
    
    return df


def create_price_transform_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Price transformation indicators.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    open_prices = df['open'].astype('float64').values
    high_prices = df['high'].astype('float64').values
    low_prices = df['low'].astype('float64').values
    close_prices = df['close'].astype('float64').values
    
    # Average Price
    df['AVGPRICE'] = talib.AVGPRICE(open_prices, high_prices, low_prices, close_prices)
    
    # Median Price
    df['MEDPRICE'] = talib.MEDPRICE(high_prices, low_prices)
    
    # Typical Price
    df['TYPPRICE'] = talib.TYPPRICE(high_prices, low_prices, close_prices)
    
    # Weighted Close Price
    df['WCLPRICE'] = talib.WCLPRICE(high_prices, low_prices, close_prices)
    
    return df


def create_advanced_volatility_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Advanced volatility indicators.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    high_prices = df['high'].astype('float64').values
    low_prices = df['low'].astype('float64').values
    close_prices = df['close'].astype('float64').values
    
    # Normalized Average True Range
    df['NATR'] = talib.NATR(high_prices, low_prices, close_prices, timeperiod=14)
    
    # True Range
    df['TRANGE'] = talib.TRANGE(high_prices, low_prices, close_prices)
    
    return df


def create_advanced_volume_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Advanced volume indicators.
    """
    if not TALIB_AVAILABLE:
        return df
    
    df = df.copy()
    high_prices = df['high'].astype('float64').values
    low_prices = df['low'].astype('float64').values
    close_prices = df['close'].astype('float64').values
    volume = (df['tick_volume'].astype('float64').values if 'tick_volume' in df.columns 
              else df['real_volume'].astype('float64').values)
    
    # Chaikin A/D Oscillator
    df['ADOSC'] = talib.ADOSC(high_prices, low_prices, close_prices, volume, 
                               fastperiod=3, slowperiod=10)
    
    return df


def create_all_advanced_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Apply ALL advanced feature engineering functions.
    
    This creates 150+ features from TA-Lib.
    """
    if not TALIB_AVAILABLE:
        print("⚠️ TA-Lib not available. Cannot create advanced features.")
        return df
    
    print("🚀 Creating advanced features with TA-Lib...")
    
    # Apply all feature creation functions
    df = create_pattern_features(df)
    print("  ✅ Pattern features (60+ candlestick patterns)")
    
    df = create_cycle_features(df)
    print("  ✅ Cycle features (Hilbert Transform)")
    
    df = create_statistical_features(df)
    print("  ✅ Statistical features")
    
    df = create_advanced_momentum_features(df)
    print("  ✅ Advanced momentum features")
    
    df = create_advanced_overlap_features(df)
    print("  ✅ Advanced overlap features")
    
    df = create_price_transform_features(df)
    print("  ✅ Price transform features")
    
    df = create_advanced_volatility_features(df)
    print("  ✅ Advanced volatility features")
    
    df = create_advanced_volume_features(df)
    print("  ✅ Advanced volume features")
    
    print(f"📊 Total features created: {len(df.columns)}")
    
    return df


def get_advanced_feature_list() -> list:
    """
    Get list of all advanced feature names.
    """
    features = [
        # Pattern aggregations
        'bullish_pattern_count', 'bearish_pattern_count', 'pattern_strength', 'pattern_diversity',
        
        # Cycle indicators
        'HT_DCPERIOD', 'HT_DCPHASE', 'HT_PHASOR_inphase', 'HT_PHASOR_quad',
        'HT_SINE_sine', 'HT_SINE_lead', 'HT_TRENDMODE',
        
        # Statistical
        'CORREL', 'LINEARREG', 'LINEARREG_ANGLE', 'LINEARREG_INTERCEPT', 
        'LINEARREG_SLOPE', 'STDDEV', 'TSF', 'VAR',
        
        # Advanced Momentum
        'AROON_down', 'AROON_up', 'AROONOSC', 'BOP', 'CMO', 'DX', 
        'MINUS_DI', 'PLUS_DI', 'MOM', 'PLUS_DM', 'MINUS_DM', 'PPO',
        'STOCHRSI_K', 'STOCHRSI_D', 'TRIX', 'ULTOSC',
        
        # Advanced Overlap
        'KAMA', 'TEMA', 'TRIMA', 'WMA', 'MAMA', 'FAMA', 'T3', 'DEMA',
        
        # Price Transform
        'AVGPRICE', 'MEDPRICE', 'TYPPRICE', 'WCLPRICE',
        
        # Advanced Volatility
        'NATR', 'TRANGE',
        
        # Advanced Volume
        'ADOSC',
    ]
    
    return features
