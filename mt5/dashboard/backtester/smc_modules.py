"""
Smart Money Concepts (SMC) Modules

Implements institutional trading concepts:
- Structure Break Detection (BOS/CHoCH)
- Order Block Detection
- Fair Value Gap (FVG) Detection
- Liquidity Sweep Detection
"""

import pandas as pd
import numpy as np
from typing import Tuple, List


class StructureBreakDetector:
    """
    Detects market structure breaks (BOS) and Change of Character (CHoCH).
    Scoring: 0-1.5 points
    """

    @staticmethod
    def detect_swing_points(df: pd.DataFrame, lookback: int = 10) -> Tuple[pd.Series, pd.Series]:
        """
        Detect swing highs and lows.

        Args:
            df: DataFrame with OHLCV data
            lookback: Lookback period for swing detection

        Returns:
            Tuple of (swing_highs, swing_lows) as boolean series
        """
        swing_highs = pd.Series(False, index=df.index)
        swing_lows = pd.Series(False, index=df.index)

        for i in range(lookback, len(df) - lookback):
            # Swing high: Current high > all highs in lookback window
            if df['high'].iloc[i] == df['high'].iloc[i-lookback:i+lookback+1].max():
                swing_highs.iloc[i] = True

            # Swing low: Current low < all lows in lookback window
            if df['low'].iloc[i] == df['low'].iloc[i-lookback:i+lookback+1].min():
                swing_lows.iloc[i] = True

        return swing_highs, swing_lows

    @staticmethod
    def detect_structure_breaks(df: pd.DataFrame, swing_highs: pd.Series,
                               swing_lows: pd.Series, lookback: int = 50) -> Tuple[pd.Series, pd.Series]:
        """
        Detect bullish and bearish structure breaks.

        Args:
            df: DataFrame with OHLCV data
            swing_highs: Boolean series of swing highs
            swing_lows: Boolean series of swing lows
            lookback: Lookback period for structure analysis

        Returns:
            Tuple of (bullish_breaks, bearish_breaks) as boolean series
        """
        bullish_breaks = pd.Series(False, index=df.index)
        bearish_breaks = pd.Series(False, index=df.index)

        # Find last significant swing high/low
        last_swing_high = 0
        last_swing_low = 0

        for i in range(lookback, len(df)):
            # Update last swing levels
            if swing_highs.iloc[i]:
                last_swing_high = df['high'].iloc[i]

            if swing_lows.iloc[i]:
                last_swing_low = df['low'].iloc[i]

            # Bullish break: Price breaks above last swing high
            if last_swing_high > 0 and df['close'].iloc[i] > last_swing_high:
                bullish_breaks.iloc[i] = True

            # Bearish break: Price breaks below last swing low
            if last_swing_low > 0 and df['close'].iloc[i] < last_swing_low:
                bearish_breaks.iloc[i] = True

        return bullish_breaks, bearish_breaks

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate structure break confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-1.5 pts)
        """
        lookback = params.get('swing_lookback', 10)
        structure_lookback = params.get('structure_lookback', 50)

        swing_highs, swing_lows = StructureBreakDetector.detect_swing_points(df, lookback)
        bullish_breaks, bearish_breaks = StructureBreakDetector.detect_structure_breaks(
            df, swing_highs, swing_lows, structure_lookback
        )

        score = pd.Series(0.0, index=df.index)

        if direction == 1:
            # Award points for recent bullish breaks (within last 5 bars)
            score += bullish_breaks.rolling(window=5).sum().clip(0, 1) * 1.5
        else:
            # Award points for recent bearish breaks
            score += bearish_breaks.rolling(window=5).sum().clip(0, 1) * 1.5

        return score


class OrderBlockDetector:
    """
    Detects institutional order blocks (areas of strong buying/selling).
    Scoring: 0-2.25 points
    """

    @staticmethod
    def detect_order_blocks(df: pd.DataFrame, atr: pd.Series, lookback: int = 20) -> Tuple[List, List]:
        """
        Detect bullish and bearish order blocks.

        Order block = Last bearish/bullish candle before strong move in opposite direction.

        Args:
            df: DataFrame with OHLCV data
            atr: ATR series
            lookback: Lookback period for OB detection

        Returns:
            Tuple of (bullish_obs, bearish_obs) as lists of dicts
        """
        bullish_obs = []
        bearish_obs = []

        for i in range(lookback, len(df) - 1):
            current_atr = atr.iloc[i]
            if pd.isna(current_atr) or current_atr == 0:
                continue

            # Bullish OB: Bearish candle followed by strong bullish move
            if df['close'].iloc[i] < df['open'].iloc[i]:  # Bearish candle
                next_move = df['close'].iloc[i+1] - df['low'].iloc[i]
                if next_move >= current_atr * 1.5:  # Strong bullish move
                    bullish_obs.append({
                        'index': i,
                        'high': df['high'].iloc[i],
                        'low': df['low'].iloc[i],
                        'strength': next_move / current_atr
                    })

            # Bearish OB: Bullish candle followed by strong bearish move
            if df['close'].iloc[i] > df['open'].iloc[i]:  # Bullish candle
                next_move = df['high'].iloc[i] - df['close'].iloc[i+1]
                if next_move >= current_atr * 1.5:  # Strong bearish move
                    bearish_obs.append({
                        'index': i,
                        'high': df['high'].iloc[i],
                        'low': df['low'].iloc[i],
                        'strength': next_move / current_atr
                    })

        return bullish_obs, bearish_obs

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate order block confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-2.25 pts)
        """
        lookback = params.get('ob_lookback', 20)
        atr = df['atr'] if 'atr' in df.columns else pd.Series(0, index=df.index)

        bullish_obs, bearish_obs = OrderBlockDetector.detect_order_blocks(df, atr, lookback)

        score = pd.Series(0.0, index=df.index)

        # Check if current price is near an order block
        for i in range(len(df)):
            current_price = df['close'].iloc[i]
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0

            if current_atr == 0:
                continue

            if direction == 1:
                # Check if near bullish OB
                for ob in bullish_obs:
                    if ob['index'] < i <= ob['index'] + 50:  # OB valid for 50 bars
                        distance = abs(current_price - (ob['low'] + ob['high']) / 2)
                        if distance <= current_atr * 0.5:  # Within 0.5 ATR
                            score.iloc[i] = min(2.25, ob['strength'] * 0.75)
                            break

            else:
                # Check if near bearish OB
                for ob in bearish_obs:
                    if ob['index'] < i <= ob['index'] + 50:
                        distance = abs(current_price - (ob['low'] + ob['high']) / 2)
                        if distance <= current_atr * 0.5:
                            score.iloc[i] = min(2.25, ob['strength'] * 0.75)
                            break

        return score


class FairValueGapDetector:
    """
    Detects Fair Value Gaps (FVG) - imbalances in price action.
    Scoring: 0-1.0 points
    """

    @staticmethod
    def detect_fvg(df: pd.DataFrame, min_gap_atr: float = 0.5) -> Tuple[List, List]:
        """
        Detect bullish and bearish FVGs.

        FVG = Gap between bar[i-1].low and bar[i+1].high (bullish)
            or gap between bar[i-1].high and bar[i+1].low (bearish)

        Args:
            df: DataFrame with OHLCV data
            min_gap_atr: Minimum gap size as ATR multiplier

        Returns:
            Tuple of (bullish_fvgs, bearish_fvgs) as lists of dicts
        """
        bullish_fvgs = []
        bearish_fvgs = []

        atr = df['atr'] if 'atr' in df.columns else pd.Series(1.0, index=df.index)

        for i in range(1, len(df) - 1):
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0
            if current_atr == 0:
                continue

            # Bullish FVG: Gap up (bar[i+1].low > bar[i-1].high)
            gap_up = df['low'].iloc[i+1] - df['high'].iloc[i-1]
            if gap_up >= current_atr * min_gap_atr:
                bullish_fvgs.append({
                    'index': i,
                    'top': df['low'].iloc[i+1],
                    'bottom': df['high'].iloc[i-1],
                    'size': gap_up / current_atr
                })

            # Bearish FVG: Gap down (bar[i+1].high < bar[i-1].low)
            gap_down = df['low'].iloc[i-1] - df['high'].iloc[i+1]
            if gap_down >= current_atr * min_gap_atr:
                bearish_fvgs.append({
                    'index': i,
                    'top': df['low'].iloc[i-1],
                    'bottom': df['high'].iloc[i+1],
                    'size': gap_down / current_atr
                })

        return bullish_fvgs, bearish_fvgs

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate FVG confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-1.0 pts)
        """
        min_gap_atr = params.get('fvg_min_gap_atr', 0.5)

        bullish_fvgs, bearish_fvgs = FairValueGapDetector.detect_fvg(df, min_gap_atr)

        score = pd.Series(0.0, index=df.index)
        atr = df['atr'] if 'atr' in df.columns else pd.Series(1.0, index=df.index)

        # Check if current price is in an unfilled FVG
        for i in range(len(df)):
            current_price = df['close'].iloc[i]

            if direction == 1:
                # Check if price is in bullish FVG (support zone)
                for fvg in bullish_fvgs:
                    if fvg['index'] < i <= fvg['index'] + 30:  # FVG valid for 30 bars
                        if fvg['bottom'] <= current_price <= fvg['top']:
                            score.iloc[i] = min(1.0, fvg['size'] * 0.5)
                            break

            else:
                # Check if price is in bearish FVG (resistance zone)
                for fvg in bearish_fvgs:
                    if fvg['index'] < i <= fvg['index'] + 30:
                        if fvg['bottom'] <= current_price <= fvg['top']:
                            score.iloc[i] = min(1.0, fvg['size'] * 0.5)
                            break

        return score


class LiquiditySweepDetector:
    """
    Detects liquidity sweeps (stop hunts followed by reversals).
    Scoring: 0-2.25 points
    """

    @staticmethod
    def detect_liquidity_levels(df: pd.DataFrame, lookback: int = 20) -> Tuple[List, List]:
        """
        Detect liquidity levels (equal highs/lows where stops accumulate).

        Args:
            df: DataFrame with OHLCV data
            lookback: Lookback period for level detection

        Returns:
            Tuple of (resistance_levels, support_levels) as lists of dicts
        """
        resistance_levels = []
        support_levels = []

        atr = df['atr'] if 'atr' in df.columns else pd.Series(1.0, index=df.index)

        for i in range(lookback, len(df)):
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0
            if current_atr == 0:
                continue

            # Find equal highs (resistance)
            recent_highs = df['high'].iloc[i-lookback:i]
            max_high = recent_highs.max()

            # Count how many times price touched this level
            touches = ((recent_highs >= max_high - current_atr * 0.1).sum())

            if touches >= 2:  # At least 2 touches = liquidity level
                resistance_levels.append({
                    'index': i,
                    'level': max_high,
                    'touches': touches
                })

            # Find equal lows (support)
            recent_lows = df['low'].iloc[i-lookback:i]
            min_low = recent_lows.min()

            touches = ((recent_lows <= min_low + current_atr * 0.1).sum())

            if touches >= 2:
                support_levels.append({
                    'index': i,
                    'level': min_low,
                    'touches': touches
                })

        return resistance_levels, support_levels

    @staticmethod
    def detect_sweeps(df: pd.DataFrame, resistance_levels: List, support_levels: List,
                     atr: pd.Series) -> Tuple[pd.Series, pd.Series]:
        """
        Detect liquidity sweeps (fake breakouts followed by reversals).

        Args:
            df: DataFrame with OHLCV data
            resistance_levels: List of resistance level dicts
            support_levels: List of support level dicts
            atr: ATR series

        Returns:
            Tuple of (bullish_sweeps, bearish_sweeps) as boolean series
        """
        bullish_sweeps = pd.Series(False, index=df.index)
        bearish_sweeps = pd.Series(False, index=df.index)

        for i in range(1, len(df)):
            current_atr = atr.iloc[i] if not pd.isna(atr.iloc[i]) else 0
            if current_atr == 0:
                continue

            # Bullish sweep: Break below support then reverse up
            for level in support_levels:
                if level['index'] < i <= level['index'] + 20:
                    # Check if low swept below level
                    if df['low'].iloc[i-1] < level['level'] - current_atr * 0.1:
                        # Check if closed back above
                        if df['close'].iloc[i] > level['level'] + current_atr * 0.2:
                            bullish_sweeps.iloc[i] = True
                            break

            # Bearish sweep: Break above resistance then reverse down
            for level in resistance_levels:
                if level['index'] < i <= level['index'] + 20:
                    # Check if high swept above level
                    if df['high'].iloc[i-1] > level['level'] + current_atr * 0.1:
                        # Check if closed back below
                        if df['close'].iloc[i] < level['level'] - current_atr * 0.2:
                            bearish_sweeps.iloc[i] = True
                            break

        return bullish_sweeps, bearish_sweeps

    @staticmethod
    def get_confluence_score(df: pd.DataFrame, direction: int, params: dict) -> pd.Series:
        """
        Calculate liquidity sweep confluence score.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary

        Returns:
            Series with confluence scores (0-2.25 pts)
        """
        lookback = params.get('liquidity_lookback', 20)
        atr = df['atr'] if 'atr' in df.columns else pd.Series(1.0, index=df.index)

        resistance_levels, support_levels = LiquiditySweepDetector.detect_liquidity_levels(
            df, lookback
        )
        bullish_sweeps, bearish_sweeps = LiquiditySweepDetector.detect_sweeps(
            df, resistance_levels, support_levels, atr
        )

        score = pd.Series(0.0, index=df.index)

        if direction == 1:
            # Award points for recent bullish sweeps (within last 3 bars)
            score += bullish_sweeps.rolling(window=3).sum().clip(0, 1) * 2.25
        else:
            # Award points for recent bearish sweeps
            score += bearish_sweeps.rolling(window=3).sum().clip(0, 1) * 2.25

        return score
