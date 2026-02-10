"""
Fibonacci Analyzer - Advanced Fibonacci Analysis for Trading Signals

Detects and scores Fibonacci-based trading opportunities:
- Swing point detection (highs/lows)
- Fibonacci retracement levels (0.236, 0.382, 0.5, 0.618, 0.786)
- Fibonacci extension levels (1.272, 1.618, 2.0, 2.618)
- Optimal Trade Entry (OTE) zone (0.62-0.79 retracement)
- Multi-timeframe Fibonacci confluence
- Fibonacci confluence detection (multiple levels aligning)

Integrates with SignalValidator to enhance signal confirmation.
"""

import logging
import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Optional
from datetime import datetime, timedelta
import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))

try:
    import talib
    TALIB_AVAILABLE = True
except ImportError:
    TALIB_AVAILABLE = False


class FibonacciAnalyzer:
    """
    Analyzes Fibonacci retracements, extensions, and confluence zones.
    """

    # Standard Fibonacci retracement levels
    RETRACEMENT_LEVELS = {
        '0.236': 0.236,
        '0.382': 0.382,
        '0.500': 0.500,
        '0.618': 0.618,
        '0.786': 0.786
    }

    # Fibonacci extension levels
    EXTENSION_LEVELS = {
        '1.272': 1.272,
        '1.618': 1.618,
        '2.000': 2.000,
        '2.618': 2.618
    }

    # OTE (Optimal Trade Entry) zone
    OTE_LOW = 0.62
    OTE_HIGH = 0.79

    def __init__(self, db_manager=None, config: Dict = None):
        """
        Initialize Fibonacci Analyzer.

        Args:
            db_manager: DatabaseManager instance
            config: Configuration dictionary
        """
        self.db = db_manager
        self.config = config or {}
        self.logger = logging.getLogger(__name__)

        # Get configuration
        fib_config = self.config.get('signal_confirmation', {}).get('fibonacci_validation', {})
        self.swing_lookback = fib_config.get('swing_lookback', 50)
        self.confluence_distance_pips = fib_config.get('min_confluence_distance_pips', 5)

    def calculate_swing_points(self, df: pd.DataFrame, lookback: int = None) -> Dict:
        """
        Detect swing high and swing low using zigzag logic.

        Args:
            df: DataFrame with OHLC data
            lookback: Number of bars to look back (default: self.swing_lookback)

        Returns:
            Dictionary with swing_high, swing_low, swing_high_index, swing_low_index
        """
        if lookback is None:
            lookback = self.swing_lookback

        if len(df) < lookback:
            self.logger.warning(f"Insufficient data for swing detection: {len(df)} < {lookback}")
            return {
                'swing_high': df['high'].iloc[-1],
                'swing_low': df['low'].iloc[-1],
                'swing_high_index': len(df) - 1,
                'swing_low_index': len(df) - 1
            }

        # Get recent data
        recent_df = df.iloc[-lookback:].copy()

        # Find swing high (highest high in lookback period)
        swing_high_idx = recent_df['high'].idxmax()
        swing_high = recent_df.loc[swing_high_idx, 'high']

        # Find swing low (lowest low in lookback period)
        swing_low_idx = recent_df['low'].idxmin()
        swing_low = recent_df.loc[swing_low_idx, 'low']

        # Get absolute indices
        swing_high_abs_idx = df.index.get_loc(swing_high_idx)
        swing_low_abs_idx = df.index.get_loc(swing_low_idx)

        return {
            'swing_high': float(swing_high),
            'swing_low': float(swing_low),
            'swing_high_index': swing_high_abs_idx,
            'swing_low_index': swing_low_abs_idx,
            'swing_range': float(swing_high - swing_low)
        }

    def calculate_retracement_levels(self, swing_high: float, swing_low: float,
                                    trend_direction: str = 'up') -> Dict[str, float]:
        """
        Calculate Fibonacci retracement levels.

        Args:
            swing_high: Swing high price
            swing_low: Swing low price
            trend_direction: 'up' for uptrend (retracing from high), 'down' for downtrend

        Returns:
            Dictionary of Fibonacci levels with prices
        """
        swing_range = swing_high - swing_low

        if trend_direction == 'up':
            # Uptrend: retracing down from swing high
            levels = {
                name: swing_high - (ratio * swing_range)
                for name, ratio in self.RETRACEMENT_LEVELS.items()
            }
        else:
            # Downtrend: retracing up from swing low
            levels = {
                name: swing_low + (ratio * swing_range)
                for name, ratio in self.RETRACEMENT_LEVELS.items()
            }

        # Add swing points
        levels['swing_high'] = float(swing_high)
        levels['swing_low'] = float(swing_low)
        levels['swing_range'] = float(swing_range)

        return levels

    def calculate_extension_levels(self, swing_high: float, swing_low: float,
                                   retracement_point: float,
                                   direction: str = 'up') -> Dict[str, float]:
        """
        Calculate Fibonacci extension levels for profit targets.

        Args:
            swing_high: Swing high price
            swing_low: Swing low price
            retracement_point: Price where retracement occurred
            direction: 'up' for bullish extension, 'down' for bearish extension

        Returns:
            Dictionary of extension levels
        """
        swing_range = swing_high - swing_low

        if direction == 'up':
            # Bullish: extending up from retracement
            levels = {
                name: retracement_point + (ratio * swing_range)
                for name, ratio in self.EXTENSION_LEVELS.items()
            }
        else:
            # Bearish: extending down from retracement
            levels = {
                name: retracement_point - (ratio * swing_range)
                for name, ratio in self.EXTENSION_LEVELS.items()
            }

        return levels

    def detect_ote_zone(self, current_price: float, swing_high: float,
                       swing_low: float, signal_direction: str) -> Tuple[bool, float, Dict]:
        """
        Check if current price is in OTE (Optimal Trade Entry) zone (0.62-0.79).

        Args:
            current_price: Current market price
            swing_high: Swing high
            swing_low: Swing low
            signal_direction: 'BUY' or 'SELL'

        Returns:
            (in_ote_zone, ote_score, details)
        """
        swing_range = swing_high - swing_low

        if signal_direction in ['BUY', 'UP', 'UP ▲']:
            # For BUY: looking for retracement into OTE zone from top
            ote_high_price = swing_high - (self.OTE_LOW * swing_range)
            ote_low_price = swing_high - (self.OTE_HIGH * swing_range)

            in_zone = ote_low_price <= current_price <= ote_high_price

            if in_zone:
                # Calculate position within OTE zone (0-1)
                zone_position = (current_price - ote_low_price) / (ote_high_price - ote_low_price)
                # Optimal position is middle of zone
                ote_score = 100 - abs(zone_position - 0.5) * 40  # Max 100, min 80
            else:
                ote_score = 0

        else:  # SELL
            # For SELL: looking for retracement into OTE zone from bottom
            ote_low_price = swing_low + (self.OTE_LOW * swing_range)
            ote_high_price = swing_low + (self.OTE_HIGH * swing_range)

            in_zone = ote_low_price <= current_price <= ote_high_price

            if in_zone:
                zone_position = (current_price - ote_low_price) / (ote_high_price - ote_low_price)
                ote_score = 100 - abs(zone_position - 0.5) * 40
            else:
                ote_score = 0

        details = {
            'in_ote': in_zone,
            'ote_high': float(ote_high_price),
            'ote_low': float(ote_low_price),
            'current_price': float(current_price),
            'distance_to_ote': float(min(abs(current_price - ote_high_price),
                                        abs(current_price - ote_low_price)))
        }

        return in_zone, ote_score, details

    def detect_fibonacci_confluence(self, df: pd.DataFrame, current_price: float,
                                    timeframes: List[str] = None) -> Dict:
        """
        Detect multiple Fibonacci levels aligning across timeframes.

        Args:
            df: DataFrame with price data
            current_price: Current market price
            timeframes: List of timeframes to check (not used in current implementation)

        Returns:
            Dictionary with confluence information
        """
        if len(df) < self.swing_lookback:
            return {'count': 0, 'levels': []}

        # Calculate swings and Fib levels
        swings = self.calculate_swing_points(df)
        fib_levels_up = self.calculate_retracement_levels(
            swings['swing_high'], swings['swing_low'], 'up'
        )
        fib_levels_down = self.calculate_retracement_levels(
            swings['swing_high'], swings['swing_low'], 'down'
        )

        # Combine all Fib levels
        all_levels = []
        for name, price in fib_levels_up.items():
            if name not in ['swing_high', 'swing_low', 'swing_range']:
                all_levels.append({'name': f'up_{name}', 'price': price})
        for name, price in fib_levels_down.items():
            if name not in ['swing_high', 'swing_low', 'swing_range']:
                all_levels.append({'name': f'down_{name}', 'price': price})

        # Detect confluence (levels within confluence_distance_pips)
        confluence_pips = self.confluence_distance_pips / 10000  # Convert to price

        confluent_levels = []
        for i, level1 in enumerate(all_levels):
            count = 1
            for j, level2 in enumerate(all_levels):
                if i != j and abs(level1['price'] - level2['price']) <= confluence_pips:
                    count += 1

            if count >= 2:  # At least 2 levels converging
                level1['confluence_count'] = count
                confluent_levels.append(level1)

        # Check if current price is near any confluent level
        near_confluence = any(
            abs(current_price - level['price']) <= confluence_pips
            for level in confluent_levels
        )

        return {
            'count': len(confluent_levels),
            'levels': confluent_levels,
            'near_confluence': near_confluence,
            'confluence_distance_pips': self.confluence_distance_pips
        }

    def score_fibonacci_alignment(self, signal_direction: str, current_price: float,
                                  df: pd.DataFrame) -> Tuple[float, Dict]:
        """
        Calculate comprehensive Fibonacci alignment score (0-100).

        Scoring breakdown:
        - OTE zone alignment: up to 40 points
        - Fibonacci confluence: up to 30 points
        - Near key retracement: up to 20 points
        - Swing structure: up to 10 points

        Args:
            signal_direction: 'BUY' or 'SELL'
            current_price: Current market price
            df: DataFrame with OHLC data

        Returns:
            (score, details)
        """
        if len(df) < self.swing_lookback:
            return 50.0, {'error': 'Insufficient data for Fibonacci analysis'}

        try:
            total_score = 0.0
            details = {}

            # Detect swing points
            swings = self.calculate_swing_points(df)
            details['swings'] = swings

            # Calculate Fib levels
            trend_direction = 'up' if signal_direction in ['BUY', 'UP', 'UP ▲'] else 'down'
            fib_levels = self.calculate_retracement_levels(
                swings['swing_high'], swings['swing_low'], trend_direction
            )
            details['fib_levels'] = fib_levels

            # 1. OTE Zone Check (40 points max)
            in_ote, ote_score, ote_details = self.detect_ote_zone(
                current_price, swings['swing_high'], swings['swing_low'], signal_direction
            )
            details['ote'] = ote_details
            if in_ote:
                total_score += 40  # Full points for being in OTE
                details['ote_contribution'] = 40
            else:
                # Partial credit if near OTE
                distance_to_ote = ote_details['distance_to_ote']
                if distance_to_ote < (swings['swing_range'] * 0.1):  # Within 10% of range
                    total_score += 20
                    details['ote_contribution'] = 20
                else:
                    details['ote_contribution'] = 0

            # 2. Fibonacci Confluence (30 points max)
            confluence = self.detect_fibonacci_confluence(df, current_price)
            details['confluence'] = confluence

            if confluence['near_confluence']:
                # Scale based on number of confluent levels
                confluence_score = min(30, confluence['count'] * 10)
                total_score += confluence_score
                details['confluence_contribution'] = confluence_score
            else:
                details['confluence_contribution'] = 0

            # 3. Near Key Retracement Level (20 points)
            key_levels = ['0.618', '0.500', '0.382']
            near_key_level = False
            tolerance = swings['swing_range'] * 0.02  # 2% tolerance

            for level_name in key_levels:
                level_price = fib_levels.get(level_name)
                if level_price and abs(current_price - level_price) <= tolerance:
                    near_key_level = True
                    details['near_level'] = level_name
                    break

            if near_key_level:
                total_score += 20
                details['key_level_contribution'] = 20
            else:
                details['key_level_contribution'] = 0

            # 4. Swing Structure Quality (10 points)
            # Check if swing range is significant (not ranging market)
            recent_atr = df['high'].rolling(14).mean().iloc[-1] - df['low'].rolling(14).mean().iloc[-1]
            if swings['swing_range'] > recent_atr * 2:
                total_score += 10
                details['structure_contribution'] = 10
            else:
                details['structure_contribution'] = 5

            details['total_score'] = total_score

            return total_score, details

        except Exception as e:
            self.logger.error(f"Error in Fibonacci scoring: {e}")
            return 50.0, {'error': str(e)}

    def get_fibonacci_targets(self, current_price: float, swing_high: float,
                             swing_low: float, signal_direction: str) -> Dict[str, float]:
        """
        Calculate Fibonacci-based profit targets.

        Args:
            current_price: Entry price
            swing_high: Swing high
            swing_low: Swing low
            signal_direction: 'BUY' or 'SELL'

        Returns:
            Dictionary of profit targets
        """
        direction = 'up' if signal_direction in ['BUY', 'UP', 'UP ▲'] else 'down'
        extensions = self.calculate_extension_levels(
            swing_high, swing_low, current_price, direction
        )

        return {
            'tp1': extensions['1.272'],  # Conservative target
            'tp2': extensions['1.618'],  # Standard target
            'tp3': extensions['2.000'],  # Extended target
            'tp4': extensions['2.618']   # Maximum target
        }
