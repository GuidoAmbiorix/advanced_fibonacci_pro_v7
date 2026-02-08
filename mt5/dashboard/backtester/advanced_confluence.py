"""
Advanced Confluence Module

Implements advanced technical analysis:
- Volume Profile Analysis
- Divergence Detection (RSI vs Price)
- Multi-Timeframe Analysis
- Fibonacci Zone Calculator
"""

import pandas as pd
import numpy as np
from typing import Tuple, Optional


class VolumeProfileAnalyzer:
    """
    Analyzes volume profile for confluence.
    Scoring: 0-2.5 points
    """

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate volume profile confluence score.

        High volume confirms moves.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-2.5 pts)
        """
        volume_column = 'tick_volume' if 'tick_volume' in df.columns else 'volume'

        if volume_column not in df.columns or 'volume_ma' not in df.columns:
            # No volume data available
            return pd.Series(0.0, index=df.index)

        # Calculate volume ratio
        volume_ratio = df[volume_column] / df['volume_ma'].replace(0, np.nan)
        volume_ratio = volume_ratio.fillna(1.0)

        score = pd.Series(0.0, index=df.index)

        # Award points based on volume confirmation
        # High volume (> 1.5x average) = full points
        # Medium volume (1.0-1.5x) = partial points
        # Low volume (< 1.0x) = no points

        high_volume = volume_ratio >= 1.5
        medium_volume = (volume_ratio >= 1.0) & (volume_ratio < 1.5)

        score.loc[high_volume] = 2.5
        score.loc[medium_volume] = 1.5

        return score


class DivergenceDetector:
    """
    Detects divergence between RSI and price.
    Scoring: 0-1.5 points
    """

    @staticmethod
    def detect_bullish_divergence(df: pd.DataFrame, rsi: pd.Series,
                                  lookback: int = 14) -> pd.Series:
        """
        Detect bullish divergence (price makes lower low, RSI makes higher low).

        Args:
            df: DataFrame with OHLCV data
            rsi: RSI series
            lookback: Lookback period

        Returns:
            Boolean series indicating bullish divergence
        """
        divergence = pd.Series(False, index=df.index)

        for i in range(lookback * 2, len(df)):
            # Find recent price low
            recent_price_low = df['low'].iloc[i-lookback:i].min()
            recent_price_low_idx = df['low'].iloc[i-lookback:i].idxmin()

            # Find earlier price low
            earlier_price_low = df['low'].iloc[i-lookback*2:i-lookback].min()
            earlier_price_low_idx = df['low'].iloc[i-lookback*2:i-lookback].idxmin()

            # Check if price made lower low
            if recent_price_low < earlier_price_low:
                # Check if RSI made higher low
                recent_rsi_low = rsi.loc[recent_price_low_idx] if recent_price_low_idx in rsi.index else 0
                earlier_rsi_low = rsi.loc[earlier_price_low_idx] if earlier_price_low_idx in rsi.index else 0

                if recent_rsi_low > earlier_rsi_low and earlier_rsi_low > 0:
                    divergence.iloc[i] = True

        return divergence

    @staticmethod
    def detect_bearish_divergence(df: pd.DataFrame, rsi: pd.Series,
                                  lookback: int = 14) -> pd.Series:
        """
        Detect bearish divergence (price makes higher high, RSI makes lower high).

        Args:
            df: DataFrame with OHLCV data
            rsi: RSI series
            lookback: Lookback period

        Returns:
            Boolean series indicating bearish divergence
        """
        divergence = pd.Series(False, index=df.index)

        for i in range(lookback * 2, len(df)):
            # Find recent price high
            recent_price_high = df['high'].iloc[i-lookback:i].max()
            recent_price_high_idx = df['high'].iloc[i-lookback:i].idxmax()

            # Find earlier price high
            earlier_price_high = df['high'].iloc[i-lookback*2:i-lookback].max()
            earlier_price_high_idx = df['high'].iloc[i-lookback*2:i-lookback].idxmax()

            # Check if price made higher high
            if recent_price_high > earlier_price_high:
                # Check if RSI made lower high
                recent_rsi_high = rsi.loc[recent_price_high_idx] if recent_price_high_idx in rsi.index else 100
                earlier_rsi_high = rsi.loc[earlier_price_high_idx] if earlier_price_high_idx in rsi.index else 100

                if recent_rsi_high < earlier_rsi_high and recent_rsi_high < 100:
                    divergence.iloc[i] = True

        return divergence

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate divergence confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-1.5 pts)
        """
        lookback = params.get('divergence_lookback', 14)

        if 'rsi' not in df.columns:
            return pd.Series(0.0, index=df.index)

        rsi = df['rsi']

        bullish_div = DivergenceDetector.detect_bullish_divergence(df, rsi, lookback)
        bearish_div = DivergenceDetector.detect_bearish_divergence(df, rsi, lookback)

        score = pd.Series(0.0, index=df.index)

        if direction == 1:
            # Award points for bullish divergence within last 5 bars
            score += bullish_div.rolling(window=5).sum().clip(0, 1) * 1.5
        else:
            # Award points for bearish divergence
            score += bearish_div.rolling(window=5).sum().clip(0, 1) * 1.5

        return score


class MultiTimeframeAnalyzer:
    """
    Analyzes higher timeframe bias for confluence.
    Scoring: 0-2.0 points
    """

    @staticmethod
    def resample_to_htf(df: pd.DataFrame, target_tf: str = '4h') -> pd.DataFrame:
        """
        Resample data to higher timeframe.

        Args:
            df: DataFrame with OHLCV data (must have datetime index)
            target_tf: Target timeframe (e.g., '4h', '1D')

        Returns:
            Resampled DataFrame
        """
        if 'time' not in df.columns:
            return pd.DataFrame()

        # Set time as index
        df_copy = df.copy()
        df_copy['time'] = pd.to_datetime(df_copy['time'])
        df_copy = df_copy.set_index('time')

        # Resample
        resampled = df_copy.resample(target_tf).agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'tick_volume': 'sum' if 'tick_volume' in df.columns else 'first'
        }).dropna()

        return resampled.reset_index()

    @staticmethod
    def calculate_htf_bias(htf_df: pd.DataFrame, params: dict) -> int:
        """
        Calculate higher timeframe bias.

        Args:
            htf_df: Higher timeframe DataFrame
            params: Parameter dictionary

        Returns:
            Bias direction (1=bullish, -1=bearish, 0=neutral)
        """
        if htf_df.empty or len(htf_df) < 10:
            return 0

        # Calculate HTF EMA
        ema_period = params.get('htf_ema_period', 50)
        htf_df['ema'] = htf_df['close'].ewm(span=ema_period, adjust=False).mean()

        # Get last value
        last_close = htf_df['close'].iloc[-1]
        last_ema = htf_df['ema'].iloc[-1]

        # Determine bias
        if last_close > last_ema * 1.01:  # 1% above EMA
            return 1  # Bullish
        elif last_close < last_ema * 0.99:  # 1% below EMA
            return -1  # Bearish
        else:
            return 0  # Neutral

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate multi-timeframe confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-2.0 pts)
        """
        # Resample to higher timeframe (4H)
        htf_df = MultiTimeframeAnalyzer.resample_to_htf(df, '4h')

        if htf_df.empty:
            # Can't analyze HTF, return zeros
            return pd.Series(0.0, index=df.index)

        # Calculate HTF bias
        htf_bias = MultiTimeframeAnalyzer.calculate_htf_bias(htf_df, params)

        # Award full points if aligned, no points if not
        score = pd.Series(0.0, index=df.index)

        if direction == htf_bias:
            score[:] = 2.0  # Full alignment
        elif htf_bias == 0:
            score[:] = 1.0  # Neutral (partial points)

        return score


class FibonacciZoneCalculator:
    """
    Calculates Fibonacci retracement zones.
    Scoring: 0-1.5 points
    """

    @staticmethod
    def calculate_fibonacci_levels(swing_high: float, swing_low: float) -> dict:
        """
        Calculate Fibonacci retracement levels.

        Args:
            swing_high: Recent swing high
            swing_low: Recent swing low

        Returns:
            Dictionary of Fibonacci levels
        """
        diff = swing_high - swing_low

        return {
            'level_0': swing_low,
            'level_236': swing_low + diff * 0.236,
            'level_382': swing_low + diff * 0.382,
            'level_500': swing_low + diff * 0.500,
            'level_618': swing_low + diff * 0.618,
            'level_786': swing_low + diff * 0.786,
            'level_100': swing_high
        }

    @staticmethod
    def is_in_golden_zone(price: float, fib_levels: dict,
                         low_level: float = 0.618, high_level: float = 0.786) -> bool:
        """
        Check if price is in golden zone (61.8%-78.6%).

        Args:
            price: Current price
            fib_levels: Fibonacci levels dictionary
            low_level: Lower bound (default 0.618)
            high_level: Upper bound (default 0.786)

        Returns:
            True if in golden zone
        """
        return fib_levels['level_618'] <= price <= fib_levels['level_786']

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate Fibonacci zone confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-1.5 pts)
        """
        lookback = params.get('fib_lookback', 50)
        fib_low = params.get('fib_level_low', 0.618)
        fib_high = params.get('fib_level_high', 0.786)

        score = pd.Series(0.0, index=df.index)

        for i in range(lookback, len(df)):
            # Find swing high/low in lookback period
            swing_high = df['high'].iloc[i-lookback:i].max()
            swing_low = df['low'].iloc[i-lookback:i].min()

            if swing_high <= swing_low:
                continue

            # Calculate Fibonacci levels
            fib_levels = FibonacciZoneCalculator.calculate_fibonacci_levels(
                swing_high, swing_low
            )

            current_price = df['close'].iloc[i]

            # Check if in golden zone
            if direction == 1:
                # For longs, check if retracing into golden zone from above
                if fib_levels['level_618'] <= current_price <= fib_levels['level_786']:
                    score.iloc[i] = 1.5

            else:
                # For shorts, check if rallying into golden zone from below
                if fib_levels['level_618'] <= current_price <= fib_levels['level_786']:
                    score.iloc[i] = 1.5

        return score


class RegimeConfirmation:
    """
    Provides bonus points for TREND regime confirmation.
    Scoring: 0-1.0 points
    """

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate regime confirmation score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-1.0 pts)
        """
        if 'regime' not in df.columns:
            return pd.Series(0.0, index=df.index)

        score = pd.Series(0.0, index=df.index)

        # REGIME_TREND = 1
        # Award bonus points if in trending regime
        in_trend = df['regime'] == 1

        score.loc[in_trend] = 1.0

        return score
