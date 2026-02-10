"""
Smart Money Concepts (SMC) Analyzer

Detects institutional trading patterns and Smart Money footprints:
- Order Blocks (OB) - Institutional support/resistance zones
- Fair Value Gaps (FVG) - Price imbalances
- Break of Structure (BOS) - Trend continuation signals
- Change of Character (CHoCH) - Trend reversal signals
- Liquidity Sweeps - Stop hunts before reversals
- Premium/Discount Zones - Relative price positioning
- Market Structure - Higher Highs/Lower Lows tracking

Integrates with SignalValidator for enhanced signal confirmation.
"""

import logging
import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Optional
from datetime import datetime
import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))

try:
    import talib
    TALIB_AVAILABLE = True
except ImportError:
    TALIB_AVAILABLE = False


class SMCAnalyzer:
    """
    Detects Smart Money Concepts: Order Blocks, FVGs, BOS, CHoCH, Liquidity.
    """

    def __init__(self, db_manager=None, config: Dict = None):
        """
        Initialize SMC Analyzer.

        Args:
            db_manager: DatabaseManager instance
            config: Configuration dictionary
        """
        self.db = db_manager
        self.config = config or {}
        self.logger = logging.getLogger(__name__)

        # Get configuration
        smc_config = self.config.get('signal_confirmation', {}).get('smc_validation', {})
        self.ob_lookback = smc_config.get('order_block_lookback', 50)
        self.ob_min_volume_ratio = smc_config.get('order_block_min_volume_ratio', 1.5)
        self.ob_min_move_atr = smc_config.get('order_block_min_move_atr', 2.0)
        self.fvg_min_gap_pips = smc_config.get('fvg_min_gap_pips', 3)
        self.fvg_max_age_bars = smc_config.get('fvg_max_age_bars', 50)
        self.liquidity_sweep_pips = smc_config.get('liquidity_sweep_threshold_pips', 5)

    def detect_order_blocks(self, df: pd.DataFrame, lookback: int = None) -> List[Dict]:
        """
        Detect Order Blocks (OB) - last opposing candle before sharp move.

        Order Block Criteria:
        1. Significant price move (> 2 ATR) following the candle
        2. High volume (> 1.5x average)
        3. The candle is the last one opposing the move direction

        Args:
            df: DataFrame with OHLC and volume data
            lookback: Number of bars to look back

        Returns:
            List of order blocks with details
        """
        if lookback is None:
            lookback = self.ob_lookback

        if len(df) < lookback + 20:
            return []

        order_blocks = []

        # Calculate ATR for move detection
        if TALIB_AVAILABLE and 'high' in df.columns and 'low' in df.columns:
            atr = talib.ATR(
                df['high'].astype('float64').values,
                df['low'].astype('float64').values,
                df['close'].astype('float64').values,
                timeperiod=14
            )
        else:
            # Fallback: simple range
            atr = (df['high'] - df['low']).rolling(14).mean().values

        # Calculate average volume
        if 'tick_volume' in df.columns:
            volume = df['tick_volume'].values
        elif 'volume' in df.columns:
            volume = df['volume'].values
        else:
            return []  # No volume data available

        avg_volume = pd.Series(volume).rolling(20).mean().values

        # Scan for order blocks
        for i in range(len(df) - lookback, len(df) - 5):
            if i < 20:  # Need history for averages
                continue

            current_candle = df.iloc[i]
            current_atr = atr[i]
            current_vol = volume[i]
            current_avg_vol = avg_volume[i]

            if current_atr == 0 or np.isnan(current_atr):
                continue

            # Check next few candles for significant move
            for j in range(i + 1, min(i + 6, len(df))):
                next_candle = df.iloc[j]
                move_size = abs(next_candle['close'] - current_candle['close'])

                # Check if move is significant
                if move_size > (current_atr * self.ob_min_move_atr):
                    # Check volume requirement
                    if current_vol > (current_avg_vol * self.ob_min_volume_ratio):
                        # Determine OB type
                        if next_candle['close'] > current_candle['close']:
                            # Bullish move: check if current candle is bearish (last opposing)
                            if current_candle['close'] < current_candle['open']:
                                order_blocks.append({
                                    'type': 'BULLISH',
                                    'index': i,
                                    'high': float(current_candle['high']),
                                    'low': float(current_candle['low']),
                                    'open': float(current_candle['open']),
                                    'close': float(current_candle['close']),
                                    'volume': float(current_vol),
                                    'volume_ratio': float(current_vol / current_avg_vol),
                                    'move_size': float(move_size),
                                    'move_atr_ratio': float(move_size / current_atr),
                                    'age_bars': len(df) - i
                                })
                        else:
                            # Bearish move: check if current candle is bullish
                            if current_candle['close'] > current_candle['open']:
                                order_blocks.append({
                                    'type': 'BEARISH',
                                    'index': i,
                                    'high': float(current_candle['high']),
                                    'low': float(current_candle['low']),
                                    'open': float(current_candle['open']),
                                    'close': float(current_candle['close']),
                                    'volume': float(current_vol),
                                    'volume_ratio': float(current_vol / current_avg_vol),
                                    'move_size': float(move_size),
                                    'move_atr_ratio': float(move_size / current_atr),
                                    'age_bars': len(df) - i
                                })

                        break  # Found OB, move to next candle

        return order_blocks

    def detect_fair_value_gaps(self, df: pd.DataFrame) -> List[Dict]:
        """
        Detect Fair Value Gaps (FVG) - 3-candle pattern with price gap.

        FVG Criteria:
        - Bullish FVG: Gap between candle[i-2].high and candle[i].low
        - Bearish FVG: Gap between candle[i-2].low and candle[i].high
        - Minimum gap size threshold

        Args:
            df: DataFrame with OHLC data

        Returns:
            List of FVGs with details
        """
        if len(df) < self.fvg_max_age_bars:
            return []

        fvgs = []
        min_gap = self.fvg_min_gap_pips / 10000  # Convert pips to price

        # Scan for FVGs (need 3-candle pattern)
        for i in range(2, len(df)):
            candle_1 = df.iloc[i - 2]
            candle_2 = df.iloc[i - 1]
            candle_3 = df.iloc[i]

            # Bullish FVG: gap up
            # Gap exists if candle_1 high < candle_3 low
            if candle_1['high'] < candle_3['low']:
                gap_size = candle_3['low'] - candle_1['high']

                if gap_size >= min_gap:
                    # Check if gap has been filled
                    filled = False
                    fill_index = None

                    for j in range(i + 1, len(df)):
                        if df.iloc[j]['low'] <= candle_1['high']:
                            filled = True
                            fill_index = j
                            break

                    age_bars = len(df) - i

                    if age_bars <= self.fvg_max_age_bars:
                        fvgs.append({
                            'type': 'BULLISH',
                            'index': i,
                            'top': float(candle_3['low']),
                            'bottom': float(candle_1['high']),
                            'gap_size': float(gap_size),
                            'filled': filled,
                            'fill_index': fill_index,
                            'age_bars': age_bars
                        })

            # Bearish FVG: gap down
            # Gap exists if candle_1 low > candle_3 high
            elif candle_1['low'] > candle_3['high']:
                gap_size = candle_1['low'] - candle_3['high']

                if gap_size >= min_gap:
                    # Check if gap has been filled
                    filled = False
                    fill_index = None

                    for j in range(i + 1, len(df)):
                        if df.iloc[j]['high'] >= candle_1['low']:
                            filled = True
                            fill_index = j
                            break

                    age_bars = len(df) - i

                    if age_bars <= self.fvg_max_age_bars:
                        fvgs.append({
                            'type': 'BEARISH',
                            'index': i,
                            'top': float(candle_1['low']),
                            'bottom': float(candle_3['high']),
                            'gap_size': float(gap_size),
                            'filled': filled,
                            'fill_index': fill_index,
                            'age_bars': age_bars
                        })

        return fvgs

    def detect_break_of_structure(self, df: pd.DataFrame, lookback: int = 50) -> Optional[Dict]:
        """
        Detect Break of Structure (BOS) - price breaks previous swing high/low.

        BOS signals trend continuation.

        Args:
            df: DataFrame with OHLC data
            lookback: Bars to look back for swing points

        Returns:
            BOS information or None
        """
        if len(df) < lookback:
            return None

        recent_df = df.iloc[-lookback:].copy()

        # Find swing highs and lows
        swing_high = recent_df['high'].max()
        swing_low = recent_df['low'].min()
        swing_high_idx = recent_df['high'].idxmax()
        swing_low_idx = recent_df['low'].idxmin()

        current_price = df['close'].iloc[-1]
        previous_close = df['close'].iloc[-2]

        # Bullish BOS: break above previous swing high
        if current_price > swing_high and previous_close <= swing_high:
            return {
                'type': 'BULLISH',
                'broken_level': float(swing_high),
                'current_price': float(current_price),
                'break_strength': float((current_price - swing_high) / swing_high * 100),
                'swing_index': df.index.get_loc(swing_high_idx)
            }

        # Bearish BOS: break below previous swing low
        elif current_price < swing_low and previous_close >= swing_low:
            return {
                'type': 'BEARISH',
                'broken_level': float(swing_low),
                'current_price': float(current_price),
                'break_strength': float((swing_low - current_price) / swing_low * 100),
                'swing_index': df.index.get_loc(swing_low_idx)
            }

        return None

    def detect_change_of_character(self, df: pd.DataFrame, lookback: int = 50) -> Optional[Dict]:
        """
        Detect Change of Character (CHoCH) - shift in market structure.

        CHoCH signals potential trend reversal:
        - HH/HL pattern breaks to LH (bearish CHoCH)
        - LL/LH pattern breaks to HL (bullish CHoCH)

        Args:
            df: DataFrame with OHLC data
            lookback: Bars to analyze structure

        Returns:
            CHoCH information or None
        """
        if len(df) < lookback:
            return None

        recent_df = df.iloc[-lookback:].copy()

        # Simplified CHoCH detection: look for structure shift
        # Find recent swings
        highs = recent_df['high'].rolling(5, center=True).max()
        lows = recent_df['low'].rolling(5, center=True).min()

        swing_highs = recent_df[recent_df['high'] == highs]['high'].dropna()
        swing_lows = recent_df[recent_df['low'] == lows]['low'].dropna()

        if len(swing_highs) < 2 or len(swing_lows) < 2:
            return None

        # Check for structure change
        recent_highs = list(swing_highs.iloc[-3:])
        recent_lows = list(swing_lows.iloc[-3:])

        # Bullish CHoCH: was making LL, now making HL
        if len(recent_lows) >= 2:
            if recent_lows[-1] > recent_lows[-2]:  # Higher Low
                return {
                    'type': 'BULLISH',
                    'signal': 'Trend reversal to upside',
                    'previous_low': float(recent_lows[-2]),
                    'current_low': float(recent_lows[-1])
                }

        # Bearish CHoCH: was making HH, now making LH
        if len(recent_highs) >= 2:
            if recent_highs[-1] < recent_highs[-2]:  # Lower High
                return {
                    'type': 'BEARISH',
                    'signal': 'Trend reversal to downside',
                    'previous_high': float(recent_highs[-2]),
                    'current_high': float(recent_highs[-1])
                }

        return None

    def calculate_premium_discount_zone(self, df: pd.DataFrame, lookback: int = 50) -> Dict:
        """
        Calculate Premium/Discount zones based on recent range.

        Premium: Above 50% of range (expensive - good for selling)
        Discount: Below 50% of range (cheap - good for buying)
        Equilibrium: At 50%

        Args:
            df: DataFrame with OHLC data
            lookback: Bars for range calculation

        Returns:
            Dictionary with zone information
        """
        if len(df) < lookback:
            lookback = len(df)

        recent_df = df.iloc[-lookback:]

        range_high = recent_df['high'].max()
        range_low = recent_df['low'].min()
        range_mid = (range_high + range_low) / 2

        current_price = df['close'].iloc[-1]

        # Calculate position in range (0-100%)
        if range_high != range_low:
            position_pct = (current_price - range_low) / (range_high - range_low) * 100
        else:
            position_pct = 50

        # Determine zone
        if position_pct > 50:
            zone = 'PREMIUM'
            zone_strength = position_pct - 50  # 0-50 scale
        elif position_pct < 50:
            zone = 'DISCOUNT'
            zone_strength = 50 - position_pct  # 0-50 scale
        else:
            zone = 'EQUILIBRIUM'
            zone_strength = 0

        return {
            'zone': zone,
            'position_pct': float(position_pct),
            'zone_strength': float(zone_strength),
            'range_high': float(range_high),
            'range_low': float(range_low),
            'equilibrium': float(range_mid),
            'current_price': float(current_price)
        }

    def score_smc_alignment(self, signal_direction: str, current_price: float,
                           df: pd.DataFrame) -> Tuple[float, Dict]:
        """
        Calculate comprehensive SMC alignment score (0-100).

        Scoring breakdown:
        - Order Block alignment: up to 30 points
        - Fair Value Gap: up to 25 points
        - Break of Structure: up to 20 points
        - Premium/Discount zone: up to 15 points
        - Change of Character: up to 10 points

        Args:
            signal_direction: 'BUY' or 'SELL'
            current_price: Current market price
            df: DataFrame with OHLC data

        Returns:
            (score, details)
        """
        try:
            total_score = 0.0
            details = {}

            # 1. Order Block Check (30 points)
            order_blocks = self.detect_order_blocks(df)
            details['order_blocks'] = order_blocks

            ob_aligned = False
            for ob in order_blocks:
                # Check if price is near OB and OB type matches signal
                if signal_direction in ['BUY', 'UP', 'UP ▲'] and ob['type'] == 'BULLISH':
                    if ob['low'] <= current_price <= ob['high'] * 1.01:  # Within 1%
                        ob_aligned = True
                        total_score += 30
                        details['ob_contribution'] = 30
                        details['aligned_ob'] = ob
                        break
                elif signal_direction in ['SELL', 'DOWN', 'DOWN ▼'] and ob['type'] == 'BEARISH':
                    if ob['low'] * 0.99 <= current_price <= ob['high']:
                        ob_aligned = True
                        total_score += 30
                        details['ob_contribution'] = 30
                        details['aligned_ob'] = ob
                        break

            if not ob_aligned:
                details['ob_contribution'] = 0

            # 2. Fair Value Gap Check (25 points)
            fvgs = self.detect_fair_value_gaps(df)
            details['fvgs'] = fvgs

            fvg_aligned = False
            for fvg in fvgs:
                if not fvg['filled']:  # Only consider unfilled FVGs
                    if signal_direction in ['BUY', 'UP', 'UP ▲'] and fvg['type'] == 'BULLISH':
                        if fvg['bottom'] <= current_price <= fvg['top']:
                            fvg_aligned = True
                            total_score += 25
                            details['fvg_contribution'] = 25
                            details['aligned_fvg'] = fvg
                            break
                    elif signal_direction in ['SELL', 'DOWN', 'DOWN ▼'] and fvg['type'] == 'BEARISH':
                        if fvg['bottom'] <= current_price <= fvg['top']:
                            fvg_aligned = True
                            total_score += 25
                            details['fvg_contribution'] = 25
                            details['aligned_fvg'] = fvg
                            break

            if not fvg_aligned:
                details['fvg_contribution'] = 0

            # 3. Break of Structure (20 points)
            bos = self.detect_break_of_structure(df)
            details['bos'] = bos

            if bos:
                if (signal_direction in ['BUY', 'UP', 'UP ▲'] and bos['type'] == 'BULLISH') or \
                   (signal_direction in ['SELL', 'DOWN', 'DOWN ▼'] and bos['type'] == 'BEARISH'):
                    total_score += 20
                    details['bos_contribution'] = 20
                else:
                    details['bos_contribution'] = 0
            else:
                details['bos_contribution'] = 0

            # 4. Premium/Discount Zone (15 points)
            pd_zone = self.calculate_premium_discount_zone(df)
            details['premium_discount'] = pd_zone

            if signal_direction in ['BUY', 'UP', 'UP ▲'] and pd_zone['zone'] == 'DISCOUNT':
                # Buying from discount is good
                score_pct = min(15, pd_zone['zone_strength'] / 50 * 15)
                total_score += score_pct
                details['pd_contribution'] = score_pct
            elif signal_direction in ['SELL', 'DOWN', 'DOWN ▼'] and pd_zone['zone'] == 'PREMIUM':
                # Selling from premium is good
                score_pct = min(15, pd_zone['zone_strength'] / 50 * 15)
                total_score += score_pct
                details['pd_contribution'] = score_pct
            else:
                details['pd_contribution'] = 0

            # 5. Change of Character (10 points)
            choch = self.detect_change_of_character(df)
            details['choch'] = choch

            if choch:
                if (signal_direction in ['BUY', 'UP', 'UP ▲'] and choch['type'] == 'BULLISH') or \
                   (signal_direction in ['SELL', 'DOWN', 'DOWN ▼'] and choch['type'] == 'BEARISH'):
                    total_score += 10
                    details['choch_contribution'] = 10
                else:
                    details['choch_contribution'] = 0
            else:
                details['choch_contribution'] = 0

            details['total_score'] = total_score

            return total_score, details

        except Exception as e:
            self.logger.error(f"Error in SMC scoring: {e}")
            return 50.0, {'error': str(e)}
