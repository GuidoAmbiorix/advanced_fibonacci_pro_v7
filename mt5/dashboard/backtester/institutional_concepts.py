"""
Institutional Concepts Module

Implements ICT (Inner Circle Trader) concepts:
- Breaker Blocks (failed structures that become zones)
- Macro Windows (Silver Bullet timing windows)
- Power of 3 (Accumulation, Manipulation, Distribution)
- Wyckoff Analysis (Springs and Upthrusts)
"""

import pandas as pd
import numpy as np
from datetime import time
from typing import List, Tuple


class BreakerBlockAnalyzer:
    """
    Detects breaker blocks (broken structure that becomes support/resistance).
    Scoring: 0-2.0 points
    """

    @staticmethod
    def detect_breaker_blocks(df: pd.DataFrame, atr: pd.Series, lookback: int = 30) -> Tuple[List, List]:
        """
        Detect bullish and bearish breaker blocks.

        Breaker block = Structure level that was broken but price returns to retest.

        Args:
            df: DataFrame with OHLCV data
            atr: ATR series
            lookback: Lookback period

        Returns:
            Tuple of (bullish_breakers, bearish_breakers) as lists
        """
        bullish_breakers = []
        bearish_breakers = []

        for i in range(lookback, len(df) - 5):
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0
            if current_atr == 0:
                continue

            # Find swing high/low in recent past
            recent_high = df['high'].iloc[i-lookback:i].max()
            recent_low = df['low'].iloc[i-lookback:i].min()

            # Bullish breaker: Price broke below support, now retesting from above
            if df['low'].iloc[i] < recent_low - current_atr * 0.5:
                # Check if price rallied back above
                if df['close'].iloc[i+1:i+5].max() > recent_low + current_atr * 0.3:
                    bullish_breakers.append({
                        'index': i,
                        'level': recent_low,
                        'strength': 1.0
                    })

            # Bearish breaker: Price broke above resistance, now retesting from below
            if df['high'].iloc[i] > recent_high + current_atr * 0.5:
                # Check if price fell back below
                if df['close'].iloc[i+1:i+5].min() < recent_high - current_atr * 0.3:
                    bearish_breakers.append({
                        'index': i,
                        'level': recent_high,
                        'strength': 1.0
                    })

        return bullish_breakers, bearish_breakers

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate breaker block confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-2.0 pts)
        """
        lookback = params.get('breaker_lookback', 30)
        atr = df['atr'] if 'atr' in df.columns else pd.Series(1.0, index=df.index)

        bullish_breakers, bearish_breakers = BreakerBlockAnalyzer.detect_breaker_blocks(
            df, atr, lookback
        )

        score = pd.Series(0.0, index=df.index)

        # Check if current price is near a breaker block
        for i in range(len(df)):
            current_price = df['close'].iloc[i]
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0

            if current_atr == 0:
                continue

            if direction == 1:
                # Check if near bullish breaker
                for breaker in bullish_breakers:
                    if breaker['index'] < i <= breaker['index'] + 40:
                        distance = abs(current_price - breaker['level'])
                        if distance <= current_atr * 0.5:
                            score.iloc[i] = 2.0 * breaker['strength']
                            break

            else:
                # Check if near bearish breaker
                for breaker in bearish_breakers:
                    if breaker['index'] < i <= breaker['index'] + 40:
                        distance = abs(current_price - breaker['level'])
                        if distance <= current_atr * 0.5:
                            score.iloc[i] = 2.0 * breaker['strength']
                            break

        return score


class MacroWindowChecker:
    """
    Checks if current time is within macro windows (Silver Bullet timing).
    Scoring: 0-1.5 points
    """

    # Define macro windows (UTC times)
    LONDON_KILL_ZONE = [(2, 0), (5, 0)]  # 02:00-05:00 UTC
    NEW_YORK_KILL_ZONE = [(13, 0), (16, 0)]  # 13:00-16:00 UTC
    ASIAN_KILL_ZONE = [(20, 0), (23, 59)]  # 20:00-23:59 UTC

    @staticmethod
    def is_in_macro_window(timestamp: pd.Timestamp) -> float:
        """
        Check if timestamp is in a macro window.

        Args:
            timestamp: Pandas timestamp

        Returns:
            Score multiplier (1.5 if in window, 0 otherwise)
        """
        hour = timestamp.hour
        minute = timestamp.minute

        # Check each kill zone
        for start, end in [MacroWindowChecker.LONDON_KILL_ZONE,
                          MacroWindowChecker.NEW_YORK_KILL_ZONE,
                          MacroWindowChecker.ASIAN_KILL_ZONE]:
            start_hour, start_min = start
            end_hour, end_min = end

            if start_hour <= hour <= end_hour:
                if hour == start_hour and minute < start_min:
                    continue
                if hour == end_hour and minute > end_min:
                    continue
                return 1.5

        return 0.0

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate macro window confluence score.

        Args:
            df: DataFrame with OHLCV data (must have datetime index)
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-1.5 pts)
        """
        if 'time' not in df.columns:
            # No time data, return zeros
            return pd.Series(0.0, index=df.index)

        score = pd.Series(0.0, index=df.index)

        for i in range(len(df)):
            timestamp = df['time'].iloc[i] if isinstance(df['time'].iloc[i], pd.Timestamp) else pd.to_datetime(df['time'].iloc[i])
            score.iloc[i] = MacroWindowChecker.is_in_macro_window(timestamp)

        return score


class PowerOf3Detector:
    """
    Detects Power of 3 phases (Accumulation, Manipulation, Distribution).
    Scoring: 0-2.0 points
    """

    @staticmethod
    def detect_accumulation(df: pd.DataFrame, i: int, atr: float, lookback: int = 10) -> bool:
        """
        Detect accumulation phase (consolidation/range).

        Args:
            df: DataFrame with OHLCV data
            i: Current index
            atr: Current ATR
            lookback: Lookback period

        Returns:
            True if in accumulation phase
        """
        if i < lookback or atr == 0:
            return False

        # Check if recent price action is ranging (low volatility)
        recent_high = df['high'].iloc[i-lookback:i].max()
        recent_low = df['low'].iloc[i-lookback:i].min()
        range_size = recent_high - recent_low

        # Accumulation = range size < 2 ATR
        return range_size < atr * 2.0

    @staticmethod
    def detect_manipulation(df: pd.DataFrame, i: int, atr: float) -> bool:
        """
        Detect manipulation phase (fake breakout).

        Args:
            df: DataFrame with OHLCV data
            i: Current index
            atr: Current ATR

        Returns:
            True if manipulation detected
        """
        if i < 3 or atr == 0:
            return False

        # Manipulation = large wick (rejection)
        current_bar = df.iloc[i]
        body_size = abs(current_bar['close'] - current_bar['open'])
        total_size = current_bar['high'] - current_bar['low']

        # Large wick = manipulation
        if total_size > 0:
            wick_ratio = body_size / total_size
            return wick_ratio < 0.4  # Body < 40% of total range

        return False

    @staticmethod
    def detect_distribution(df: pd.DataFrame, i: int, atr: float) -> bool:
        """
        Detect distribution phase (strong directional move).

        Args:
            df: DataFrame with OHLCV data
            i: Current index
            atr: Current ATR

        Returns:
            True if in distribution phase
        """
        if i < 1 or atr == 0:
            return False

        # Distribution = strong breakout candle
        current_bar = df.iloc[i]
        body_size = abs(current_bar['close'] - current_bar['open'])

        # Strong candle = body > 1.5 ATR
        return body_size >= atr * 1.5

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate Power of 3 confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-2.0 pts)
        """
        lookback = params.get('po3_lookback', 10)
        atr = df['atr'] if 'atr' in df.columns else pd.Series(1.0, index=df.index)

        score = pd.Series(0.0, index=df.index)

        for i in range(lookback, len(df)):
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0
            if current_atr == 0:
                continue

            # Check phases
            in_accumulation = PowerOf3Detector.detect_accumulation(df, i-1, current_atr, lookback)
            in_manipulation = PowerOf3Detector.detect_manipulation(df, i-1, current_atr)
            in_distribution = PowerOf3Detector.detect_distribution(df, i, current_atr)

            # Award points if we're in distribution phase after accumulation/manipulation
            if in_distribution and (in_accumulation or in_manipulation):
                # Check if distribution matches our direction
                if direction == 1 and df['close'].iloc[i] > df['open'].iloc[i]:
                    score.iloc[i] = 2.0
                elif direction == -1 and df['close'].iloc[i] < df['open'].iloc[i]:
                    score.iloc[i] = 2.0

        return score


class WyckoffAnalyzer:
    """
    Detects Wyckoff patterns (springs and upthrusts).
    Scoring: 0-1.5 points
    """

    @staticmethod
    def detect_spring(df: pd.DataFrame, i: int, atr: float, lookback: int = 20) -> bool:
        """
        Detect spring (false breakdown followed by rally).

        Args:
            df: DataFrame with OHLCV data
            i: Current index
            atr: Current ATR
            lookback: Lookback period

        Returns:
            True if spring detected
        """
        if i < lookback + 1 or atr == 0:
            return False

        # Find recent support
        support = df['low'].iloc[i-lookback:i-1].min()

        # Spring = wick below support, close above support
        current_bar = df.iloc[i]
        if current_bar['low'] < support - atr * 0.1:  # Swept below support
            if current_bar['close'] > support + atr * 0.2:  # Closed back above
                return True

        return False

    @staticmethod
    def detect_upthrust(df: pd.DataFrame, i: int, atr: float, lookback: int = 20) -> bool:
        """
        Detect upthrust (false breakout followed by decline).

        Args:
            df: DataFrame with OHLCV data
            i: Current index
            atr: Current ATR
            lookback: Lookback period

        Returns:
            True if upthrust detected
        """
        if i < lookback + 1 or atr == 0:
            return False

        # Find recent resistance
        resistance = df['high'].iloc[i-lookback:i-1].max()

        # Upthrust = wick above resistance, close below resistance
        current_bar = df.iloc[i]
        if current_bar['high'] > resistance + atr * 0.1:  # Broke above resistance
            if current_bar['close'] < resistance - atr * 0.2:  # Closed back below
                return True

        return False

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate Wyckoff confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-1.5 pts)
        """
        lookback = params.get('wyckoff_lookback', 20)
        atr = df['atr'] if 'atr' in df.columns else pd.Series(1.0, index=df.index)

        score = pd.Series(0.0, index=df.index)

        for i in range(lookback + 1, len(df)):
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0
            if current_atr == 0:
                continue

            if direction == 1:
                # Check for spring (bullish signal)
                if WyckoffAnalyzer.detect_spring(df, i, current_atr, lookback):
                    score.iloc[i] = 1.5

            else:
                # Check for upthrust (bearish signal)
                if WyckoffAnalyzer.detect_upthrust(df, i, current_atr, lookback):
                    score.iloc[i] = 1.5

        return score
