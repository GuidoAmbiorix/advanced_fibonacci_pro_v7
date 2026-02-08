"""
Technical Indicators Module

Core indicators with proper vectorization for fast backtesting.
Mirrors MT5 EA indicator calculations.
"""

import pandas as pd
import numpy as np
from typing import Dict, Any


class TechnicalIndicators:
    """Calculates technical indicators used in confluence scoring."""

    @staticmethod
    def calculate_rsi(df: pd.DataFrame, period: int = 14, column: str = 'close') -> pd.Series:
        """
        Calculate RSI (Relative Strength Index).

        Args:
            df: DataFrame with OHLCV data
            period: RSI period (default 14)
            column: Price column to use (default 'close')

        Returns:
            Series with RSI values (0-100)
        """
        delta = df[column].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()

        rs = gain / loss
        rsi = 100 - (100 / (1 + rs))

        return rsi

    @staticmethod
    def calculate_ema(df: pd.DataFrame, period: int = 200, column: str = 'close') -> pd.Series:
        """
        Calculate EMA (Exponential Moving Average).

        Args:
            df: DataFrame with OHLCV data
            period: EMA period (default 200)
            column: Price column to use (default 'close')

        Returns:
            Series with EMA values
        """
        return df[column].ewm(span=period, adjust=False).mean()

    @staticmethod
    def calculate_ema_slope(ema: pd.Series, lookback: int = 5) -> pd.Series:
        """
        Calculate EMA slope over lookback period.

        Args:
            ema: EMA series
            lookback: Number of bars to calculate slope (default 5)

        Returns:
            Series with slope values
        """
        return (ema - ema.shift(lookback)) / lookback

    @staticmethod
    def calculate_atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
        """
        Calculate ATR (Average True Range).

        Args:
            df: DataFrame with OHLCV data
            period: ATR period (default 14)

        Returns:
            Series with ATR values
        """
        high_low = df['high'] - df['low']
        high_close = np.abs(df['high'] - df['close'].shift(1))
        low_close = np.abs(df['low'] - df['close'].shift(1))

        tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        atr = tr.rolling(window=period).mean()

        return atr

    @staticmethod
    def calculate_atr_ma(atr: pd.Series, period: int = 50) -> pd.Series:
        """
        Calculate ATR moving average for volatility ratio.

        Args:
            atr: ATR series
            period: MA period (default 50)

        Returns:
            Series with ATR MA values
        """
        return atr.rolling(window=period).mean()

    @staticmethod
    def check_displacement(df: pd.DataFrame, ema: pd.Series, atr: pd.Series,
                          direction: int, multiplier: float = 2.0) -> pd.Series:
        """
        Check if price has displaced from EMA (strong momentum).

        Args:
            df: DataFrame with OHLCV data
            ema: EMA series
            atr: ATR series
            direction: Trade direction (1=long, -1=short)
            multiplier: ATR multiplier for displacement (default 2.0)

        Returns:
            Boolean series indicating displacement
        """
        if direction == 1:
            displacement = (df['close'] - ema) >= (atr * multiplier)
        else:
            displacement = (ema - df['close']) >= (atr * multiplier)

        return displacement

    @staticmethod
    def check_chop_filter(atr: pd.Series, atr_ma: pd.Series,
                         min_ratio: float = 0.5) -> pd.Series:
        """
        Check if market is choppy (low volatility).

        Args:
            atr: Current ATR series
            atr_ma: ATR moving average series
            min_ratio: Minimum ATR/ATR_MA ratio (default 0.5)

        Returns:
            Boolean series indicating choppy conditions (True = choppy, penalize)
        """
        # Avoid division by zero
        ratio = atr / atr_ma.replace(0, np.nan)
        choppy = ratio < min_ratio

        return choppy.fillna(False)

    @staticmethod
    def detect_market_regime(df: pd.DataFrame, ema: pd.Series, atr: pd.Series,
                           rsi: pd.Series, lookback: int = 20) -> pd.Series:
        """
        Detect market regime: TREND, RANGE, or CHAOS.

        Args:
            df: DataFrame with OHLCV data
            ema: EMA series
            atr: ATR series
            rsi: RSI series
            lookback: Lookback period for regime detection (default 20)

        Returns:
            Series with regime labels (0=RANGE, 1=TREND, 2=CHAOS)
        """
        regime = pd.Series(0, index=df.index)  # Default: RANGE

        # Calculate price range
        rolling_high = df['high'].rolling(window=lookback).max()
        rolling_low = df['low'].rolling(window=lookback).min()
        price_range = rolling_high - rolling_low

        # EMA slope for trend detection
        ema_slope = TechnicalIndicators.calculate_ema_slope(ema, lookback)
        ema_slope_abs = ema_slope.abs()

        # Volatility ratio
        atr_ma = TechnicalIndicators.calculate_atr_ma(atr, lookback)
        volatility_ratio = atr / atr_ma.replace(0, np.nan)

        # TREND: Strong EMA slope + high volatility + consistent price moves
        trend_condition = (
            (ema_slope_abs >= atr * 0.1) &  # Strong slope
            (volatility_ratio >= 0.8) &      # Normal to high volatility
            ((rsi > 55) | (rsi < 45))        # Directional bias
        )

        # CHAOS: Very high volatility + erratic moves
        chaos_condition = (volatility_ratio >= 1.5)

        regime.loc[trend_condition] = 1   # TREND
        regime.loc[chaos_condition] = 2   # CHAOS

        return regime

    @staticmethod
    def calculate_volume_ma(df: pd.DataFrame, period: int = 20,
                           column: str = 'tick_volume') -> pd.Series:
        """
        Calculate volume moving average.

        Args:
            df: DataFrame with OHLCV data
            period: MA period (default 20)
            column: Volume column (default 'tick_volume')

        Returns:
            Series with volume MA values
        """
        if column not in df.columns:
            # Fallback if tick_volume not available
            return pd.Series(1.0, index=df.index)

        return df[column].rolling(window=period).mean()

    @staticmethod
    def calculate_all_indicators(df: pd.DataFrame, params: Dict[str, Any]) -> pd.DataFrame:
        """
        Calculate all technical indicators needed for confluence scoring.

        Args:
            df: DataFrame with OHLCV data
            params: Parameter dictionary with indicator settings

        Returns:
            DataFrame with all indicators added as columns
        """
        df = df.copy()

        # Extract parameters
        rsi_period = params.get('rsi_period', 14)
        ema_period = params.get('ema_period', 200)
        atr_period = params.get('atr_period', 14)

        # Core indicators
        df['rsi'] = TechnicalIndicators.calculate_rsi(df, rsi_period)
        df['rsi_prev'] = df['rsi'].shift(1)

        df['ema'] = TechnicalIndicators.calculate_ema(df, ema_period)
        df['ema_prev'] = df['ema'].shift(1)
        df['ema_slope'] = TechnicalIndicators.calculate_ema_slope(df['ema'], 5)

        df['atr'] = TechnicalIndicators.calculate_atr(df, atr_period)
        df['atr_ma'] = TechnicalIndicators.calculate_atr_ma(df['atr'], 50)

        # Regime detection
        df['regime'] = TechnicalIndicators.detect_market_regime(
            df, df['ema'], df['atr'], df['rsi']
        )

        # Volume
        df['volume_ma'] = TechnicalIndicators.calculate_volume_ma(df)

        return df
