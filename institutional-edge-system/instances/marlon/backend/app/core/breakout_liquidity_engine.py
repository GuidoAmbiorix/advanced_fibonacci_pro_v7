"""
BREAKOUT + LIQUIDITY ENGINE
100% Quantifiable Trading System for Algorithmic Execution

Core Philosophy:
- NO ambiguous Order Blocks
- NO subjective Fair Value Gaps
- NO complex CHoCH detection
- ONLY objective, measurable factors

Strategy:
1. Liquidity Sweeps (Internal vs External)
2. Breakout Confirmation (Body + Volume)
3. Retest Entry (Mechanical)
4. Objective Scoring (10+ minimum)

Author: Institutional Edge Pro
Model: Breakout + Liquidity (Prop Firm Standard)
"""

import pandas as pd
import numpy as np
from datetime import datetime, time, timedelta
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from loguru import logger


@dataclass
class SwingPoint:
    """Swing High/Low structure"""
    price: float
    time: datetime
    bar_index: int
    is_high: bool  # True = High, False = Low


@dataclass
class LiquiditySweep:
    """Liquidity sweep structure"""
    price: float
    time: datetime
    direction: str  # "BULLISH" or "BEARISH"
    sweep_type: str  # "INTERNAL" or "EXTERNAL"
    distance_pips: float
    volume_percentile: float
    score: int  # 1-5


@dataclass
class BreakoutSignal:
    """Breakout signal structure"""
    entry_price: float
    stop_loss: float
    take_profit: float
    direction: str  # "BUY" or "SELL"
    signal_type: str  # "BREAKOUT_RETEST"
    score: int
    breakdown: Dict
    timestamp: datetime

    # Entry details
    sweep: Optional[LiquiditySweep]
    breakout_level: float
    retest_confirmed: bool


class BreakoutLiquidityEngine:
    """
    Breakout + Liquidity Trading Engine

    100% Quantifiable - Zero Ambiguity
    """

    def __init__(self, config: Dict):
        """
        Initialize engine

        Args:
            config: Engine configuration
                - symbol: Trading symbol
                - timeframe: Timeframe
                - swing_length: Swing detection period (default 10)
                - min_score: Minimum score for entry (default 10)
                - atr_period: ATR period (default 14)
                - volume_lookback: Volume percentile lookback (default 50)
        """
        self.symbol = config.get('symbol', 'EURUSD')
        self.timeframe = config.get('timeframe', 'H1')
        self.swing_length = config.get('swing_length', 10)
        self.min_score = config.get('min_score', 10)
        self.atr_period = config.get('atr_period', 14)
        self.volume_lookback = config.get('volume_lookback', 50)

        # State
        self.swing_highs: List[SwingPoint] = []
        self.swing_lows: List[SwingPoint] = []
        self.recent_sweeps: List[LiquiditySweep] = []

        # Scoring weights (Total = 16 max for perfect setup)
        self.WEIGHTS = {
            # Liquidity (1-5)
            'EXTERNAL_SWEEP': 5,      # Strong external liquidity
            'INTERNAL_SWEEP': 2,      # Weak internal liquidity

            # Breakout (1-3)
            'STRONG_BREAKOUT': 3,     # Body >70%, volume >80%
            'MEDIUM_BREAKOUT': 2,     # Body >60%, volume >70%
            'WEAK_BREAKOUT': 1,       # Body >50%, volume >60%

            # Retest (1-3)
            'RETEST_CONFIRMED': 3,    # Clean rejection from zone
            'RETEST_PARTIAL': 1,      # Touch but no clear rejection

            # Filters (1-2 each)
            'KILLZONE_ACTIVE': 2,     # London/NY session
            'ATR_REGIME_OK': 1,       # ATR > 1.0x SMA
            'HTF_ALIGNED': 2,         # Higher TF trend aligned
            'VOLUME_SPIKE': 1,        # Volume > 90%
        }

        logger.info(f"BreakoutLiquidityEngine initialized - {self.symbol} {self.timeframe}")
        logger.info(f"Min Score: {self.min_score}, Swing Length: {self.swing_length}")


    def _calculate_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Calculate required indicators if not present

        Adds:
        - ATR (Average True Range)
        """
        df = df.copy()

        # Calculate True Range
        df['tr'] = np.maximum(
            df['high'] - df['low'],
            np.maximum(
                abs(df['high'] - df['close'].shift(1)),
                abs(df['low'] - df['close'].shift(1))
            )
        )

        # Calculate ATR
        df['atr'] = df['tr'].rolling(window=self.atr_period).mean()

        return df


    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None) -> Dict:
        """
        Main analysis method

        Args:
            df: Price data with OHLCV + indicators
            df_higher_tf: Higher timeframe data (optional)

        Returns:
            Analysis results with signals
        """
        if len(df) < 100:
            return {'signals': [], 'message': 'Insufficient data'}

        # Calculate ATR if not present
        if 'atr' not in df.columns:
            df = self._calculate_indicators(df)

        # 1. Detect swings
        self._detect_swings(df)

        # 2. Detect liquidity sweeps
        sweeps = self._detect_liquidity_sweeps(df)

        # 3. Check for breakout
        breakout_data = self._detect_breakout(df)

        # 4. Check for retest
        retest_data = self._check_retest(df, breakout_data)

        # 5. Apply filters
        filters = self._apply_filters(df, df_higher_tf)

        # 6. Calculate score and generate signals
        signals = self._generate_signals(df, sweeps, breakout_data, retest_data, filters)

        return {
            'signals': signals,
            'swings': {'highs': len(self.swing_highs), 'lows': len(self.swing_lows)},
            'sweeps': len(sweeps),
            'breakout': breakout_data,
            'retest': retest_data,
            'filters': filters
        }


    def _detect_swings(self, df: pd.DataFrame) -> None:
        """
        Detect swing highs and lows

        Swing High = high[i] > high[i-n:i] and high[i] > high[i+1:i+n]
        Swing Low = low[i] < low[i-n:i] and low[i] < low[i+1:i+n]
        """
        if len(df) < self.swing_length * 2 + 1:
            return

        self.swing_highs = []
        self.swing_lows = []

        for i in range(self.swing_length, len(df) - self.swing_length):
            # Check swing high
            high = df.iloc[i]['high']
            is_swing_high = True

            for j in range(1, self.swing_length + 1):
                if df.iloc[i - j]['high'] >= high or df.iloc[i + j]['high'] >= high:
                    is_swing_high = False
                    break

            if is_swing_high:
                self.swing_highs.append(SwingPoint(
                    price=high,
                    time=df.iloc[i]['time'],
                    bar_index=i,
                    is_high=True
                ))

            # Check swing low
            low = df.iloc[i]['low']
            is_swing_low = True

            for j in range(1, self.swing_length + 1):
                if df.iloc[i - j]['low'] <= low or df.iloc[i + j]['low'] <= low:
                    is_swing_low = False
                    break

            if is_swing_low:
                self.swing_lows.append(SwingPoint(
                    price=low,
                    time=df.iloc[i]['time'],
                    bar_index=i,
                    is_high=False
                ))

        logger.debug(f"Detected {len(self.swing_highs)} swing highs, {len(self.swing_lows)} swing lows")


    def _detect_liquidity_sweeps(self, df: pd.DataFrame) -> List[LiquiditySweep]:
        """
        Detect liquidity sweeps

        Sweep = Price breaks swing high/low then reverses

        Classification:
        - INTERNAL: <50 pips from recent swing (weak)
        - EXTERNAL: >50 pips or HTF swing (strong)
        """
        if not self.swing_highs and not self.swing_lows:
            return []

        current = df.iloc[-1]
        prev = df.iloc[-2] if len(df) > 1 else current

        sweeps = []

        # Check bullish sweep (sweep low then rally)
        if self.swing_lows:
            recent_lows = [s for s in self.swing_lows if len(df) - s.bar_index <= 20]

            for swing_low in recent_lows:
                # Did we sweep below?
                if prev['low'] <= swing_low.price < current['close']:
                    # Calculate distance
                    distance_pips = abs(current['close'] - swing_low.price) * 10000

                    # Classify
                    bars_ago = len(df) - swing_low.bar_index
                    sweep_type = "EXTERNAL" if distance_pips > 50 or bars_ago > 50 else "INTERNAL"

                    # Volume check
                    volume_pct = (df.tail(self.volume_lookback)['volume'].rank(pct=True).iloc[-1]) * 100

                    # Score
                    score = 5 if sweep_type == "EXTERNAL" else 2
                    if volume_pct > 80:
                        score += 1

                    sweeps.append(LiquiditySweep(
                        price=swing_low.price,
                        time=current['time'],
                        direction="BULLISH",
                        sweep_type=sweep_type,
                        distance_pips=distance_pips,
                        volume_percentile=volume_pct,
                        score=min(score, 5)
                    ))

                    logger.info(f"BULLISH {sweep_type} SWEEP detected @ {swing_low.price:.5f} (+{distance_pips:.1f} pips)")
                    break

        # Check bearish sweep (sweep high then drop)
        if self.swing_highs:
            recent_highs = [s for s in self.swing_highs if len(df) - s.bar_index <= 20]

            for swing_high in recent_highs:
                # Did we sweep above?
                if prev['high'] >= swing_high.price > current['close']:
                    # Calculate distance
                    distance_pips = abs(swing_high.price - current['close']) * 10000

                    # Classify
                    bars_ago = len(df) - swing_high.bar_index
                    sweep_type = "EXTERNAL" if distance_pips > 50 or bars_ago > 50 else "INTERNAL"

                    # Volume check
                    volume_pct = (df.tail(self.volume_lookback)['volume'].rank(pct=True).iloc[-1]) * 100

                    # Score
                    score = 5 if sweep_type == "EXTERNAL" else 2
                    if volume_pct > 80:
                        score += 1

                    sweeps.append(LiquiditySweep(
                        price=swing_high.price,
                        time=current['time'],
                        direction="BEARISH",
                        sweep_type=sweep_type,
                        distance_pips=distance_pips,
                        volume_percentile=volume_pct,
                        score=min(score, 5)
                    ))

                    logger.info(f"BEARISH {sweep_type} SWEEP detected @ {swing_high.price:.5f} (-{distance_pips:.1f} pips)")
                    break

        self.recent_sweeps = sweeps
        return sweeps


    def _detect_breakout(self, df: pd.DataFrame) -> Dict:
        """
        Detect breakout confirmation

        Strong Breakout:
        - Body close beyond level
        - Body size >70% of total range
        - Volume >80th percentile

        Returns score 1-3
        """
        if len(df) < 2:
            return {'has_breakout': False}

        current = df.iloc[-1]

        # Calculate body ratio
        body = abs(current['close'] - current['open'])
        total_range = current['high'] - current['low']
        body_ratio = body / total_range if total_range > 0 else 0

        # Volume percentile
        volume_pct = (df.tail(self.volume_lookback)['volume'].rank(pct=True).iloc[-1]) * 100

        # Determine breakout quality
        score = 0
        quality = "NONE"

        if body_ratio > 0.7 and volume_pct > 80:
            score = 3
            quality = "STRONG"
        elif body_ratio > 0.6 and volume_pct > 70:
            score = 2
            quality = "MEDIUM"
        elif body_ratio > 0.5 and volume_pct > 60:
            score = 1
            quality = "WEAK"

        has_breakout = score > 0

        if has_breakout:
            direction = "BULLISH" if current['close'] > current['open'] else "BEARISH"
            logger.debug(f"{quality} {direction} breakout: body={body_ratio:.1%}, volume={volume_pct:.1f}%")

        return {
            'has_breakout': has_breakout,
            'quality': quality,
            'score': score,
            'body_ratio': body_ratio,
            'volume_percentile': volume_pct,
            'direction': "BULLISH" if current['close'] > current['open'] else "BEARISH"
        }


    def _check_retest(self, df: pd.DataFrame, breakout_data: Dict) -> Dict:
        """
        Check for retest of breakout level

        Retest criteria:
        - Price returns within 10-20 pips of breakout level
        - Rejection candle (wick >40% of range)
        - Opposite direction close

        Returns score 1-3
        """
        if not breakout_data.get('has_breakout', False):
            return {'has_retest': False}

        if len(df) < 3:
            return {'has_retest': False}

        current = df.iloc[-1]
        prev = df.iloc[-2]

        # Find recent swing that was broken
        breakout_level = None

        if breakout_data['direction'] == "BULLISH" and self.swing_lows:
            # Find swing low that was swept
            recent_lows = sorted([s for s in self.swing_lows if len(df) - s.bar_index <= 10],
                                key=lambda x: len(df) - x.bar_index)
            if recent_lows:
                breakout_level = recent_lows[0].price

        elif breakout_data['direction'] == "BEARISH" and self.swing_highs:
            # Find swing high that was swept
            recent_highs = sorted([s for s in self.swing_highs if len(df) - s.bar_index <= 10],
                                 key=lambda x: len(df) - x.bar_index)
            if recent_highs:
                breakout_level = recent_highs[0].price

        if not breakout_level:
            return {'has_retest': False}

        # Check if price is retesting
        atr = df.iloc[-1]['atr']
        retest_zone_pips = 20  # 20 pips
        retest_zone = retest_zone_pips * 0.0001

        in_retest_zone = abs(current['close'] - breakout_level) <= retest_zone

        if not in_retest_zone:
            return {'has_retest': False, 'breakout_level': breakout_level}

        # Check for rejection
        total_range = current['high'] - current['low']

        if breakout_data['direction'] == "BULLISH":
            # Check for bullish rejection (long lower wick)
            lower_wick = current['close'] - current['low'] if current['close'] > current['open'] else current['open'] - current['low']
            wick_ratio = lower_wick / total_range if total_range > 0 else 0

            rejection_confirmed = wick_ratio > 0.4 and current['close'] > current['open']

        else:  # BEARISH
            # Check for bearish rejection (long upper wick)
            upper_wick = current['high'] - current['close'] if current['close'] < current['open'] else current['high'] - current['open']
            wick_ratio = upper_wick / total_range if total_range > 0 else 0

            rejection_confirmed = wick_ratio > 0.4 and current['close'] < current['open']

        score = 3 if rejection_confirmed else 1

        if in_retest_zone:
            logger.info(f"RETEST detected @ {breakout_level:.5f}, rejection={rejection_confirmed}")

        return {
            'has_retest': in_retest_zone,
            'breakout_level': breakout_level,
            'rejection_confirmed': rejection_confirmed,
            'score': score,
            'wick_ratio': wick_ratio if 'wick_ratio' in locals() else 0
        }


    def _apply_filters(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame]) -> Dict:
        """
        Apply objective filters

        Returns filter scores
        """
        current = df.iloc[-1]
        filters = {}

        # 1. Killzone (London/NY sessions)
        filters['killzone'] = self._check_killzone(current['time'])

        # 2. ATR Regime
        filters['atr_regime'] = self._check_atr_regime(df)

        # 3. HTF Alignment
        filters['htf_aligned'] = self._check_htf_alignment(df, df_higher_tf)

        # 4. Volume Spike
        volume_pct = (df.tail(50)['volume'].rank(pct=True).iloc[-1]) * 100
        filters['volume_spike'] = volume_pct > 90

        return filters


    def _check_killzone(self, current_time: datetime) -> bool:
        """
        Check if in killzone

        Killzones (UTC):
        - London: 07:00-10:00
        - NY AM: 13:30-16:00
        - NY PM: 18:00-20:00
        """
        hour = current_time.hour
        minute = current_time.minute

        # London killzone (07:00-10:00 UTC)
        if 7 <= hour < 10:
            return True

        # NY AM killzone (13:30-16:00 UTC)
        if (hour == 13 and minute >= 30) or (14 <= hour < 16):
            return True

        # NY PM killzone (18:00-20:00 UTC)
        if 18 <= hour < 20:
            return True

        return False


    def _check_atr_regime(self, df: pd.DataFrame) -> bool:
        """
        Check ATR regime

        Only trade when ATR > 1.0x SMA(ATR, 14)
        """
        if len(df) < 14:
            return False

        current_atr = df.iloc[-1]['atr']
        atr_sma = df['atr'].tail(14).mean()

        return current_atr > atr_sma * 1.0


    def _check_htf_alignment(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame]) -> bool:
        """
        Check higher timeframe alignment

        Simple: EMA(20) slope direction
        """
        if df_higher_tf is None or len(df_higher_tf) < 20:
            return False

        ema = df_higher_tf['close'].ewm(span=20).mean()

        if len(ema) < 2:
            return False

        htf_trend = "BULLISH" if ema.iloc[-1] > ema.iloc[-2] else "BEARISH"

        # Current timeframe trend
        current_ema = df['close'].ewm(span=20).mean()
        current_trend = "BULLISH" if current_ema.iloc[-1] > current_ema.iloc[-2] else "BEARISH"

        return htf_trend == current_trend


    def _generate_signals(
        self,
        df: pd.DataFrame,
        sweeps: List[LiquiditySweep],
        breakout_data: Dict,
        retest_data: Dict,
        filters: Dict
    ) -> List[BreakoutSignal]:
        """
        Generate trading signals with scoring

        Minimum score: 8+

        Scoring:
        - Liquidity: 2-5 (REQUIRED)
        - Breakout: 1-3 (REQUIRED)
        - Retest: 1-3 (OPTIONAL - bonus points)
        - Filters: 1-2 each (max 6)

        Total possible: 17

        NEW: Retest is OPTIONAL - Sweep + Breakout is enough for entry
        """
        signals = []

        if not sweeps:
            return signals

        if not breakout_data.get('has_breakout', False):
            return signals

        # RETEST NOW OPTIONAL - Don't return early
        # if not retest_data.get('has_retest', False):
        #     return signals

        current = df.iloc[-1]
        atr = current['atr']

        # Check if we have retest
        has_retest = retest_data.get('has_retest', False)

        for sweep in sweeps:
            # Check direction alignment
            if sweep.direction == "BULLISH" and breakout_data['direction'] != "BULLISH":
                continue
            if sweep.direction == "BEARISH" and breakout_data['direction'] != "BEARISH":
                continue

            # Calculate score
            score = 0
            breakdown = {}

            # 1. Liquidity sweep score
            if sweep.sweep_type == "EXTERNAL":
                score += self.WEIGHTS['EXTERNAL_SWEEP']
                breakdown['External Sweep'] = self.WEIGHTS['EXTERNAL_SWEEP']
            else:
                score += self.WEIGHTS['INTERNAL_SWEEP']
                breakdown['Internal Sweep'] = self.WEIGHTS['INTERNAL_SWEEP']

            # 2. Breakout score
            if breakout_data['quality'] == "STRONG":
                score += self.WEIGHTS['STRONG_BREAKOUT']
                breakdown['Strong Breakout'] = self.WEIGHTS['STRONG_BREAKOUT']
            elif breakout_data['quality'] == "MEDIUM":
                score += self.WEIGHTS['MEDIUM_BREAKOUT']
                breakdown['Medium Breakout'] = self.WEIGHTS['MEDIUM_BREAKOUT']
            else:
                score += self.WEIGHTS['WEAK_BREAKOUT']
                breakdown['Weak Breakout'] = self.WEIGHTS['WEAK_BREAKOUT']

            # 3. Retest score (OPTIONAL - bonus points only)
            if has_retest:
                if retest_data.get('rejection_confirmed', False):
                    score += self.WEIGHTS['RETEST_CONFIRMED']
                    breakdown['Retest Confirmed'] = self.WEIGHTS['RETEST_CONFIRMED']
                else:
                    score += self.WEIGHTS['RETEST_PARTIAL']
                    breakdown['Retest Partial'] = self.WEIGHTS['RETEST_PARTIAL']

            # 4. Filters
            if filters.get('killzone', False):
                score += self.WEIGHTS['KILLZONE_ACTIVE']
                breakdown['Killzone'] = self.WEIGHTS['KILLZONE_ACTIVE']

            if filters.get('atr_regime', False):
                score += self.WEIGHTS['ATR_REGIME_OK']
                breakdown['ATR Regime'] = self.WEIGHTS['ATR_REGIME_OK']

            if filters.get('htf_aligned', False):
                score += self.WEIGHTS['HTF_ALIGNED']
                breakdown['HTF Aligned'] = self.WEIGHTS['HTF_ALIGNED']

            if filters.get('volume_spike', False):
                score += self.WEIGHTS['VOLUME_SPIKE']
                breakdown['Volume Spike'] = self.WEIGHTS['VOLUME_SPIKE']

            # Check minimum score
            if score < self.min_score:
                logger.debug(f"Signal rejected: score {score} < {self.min_score} minimum")
                continue

            # Calculate entry, SL, TP
            # Use sweep price as stop level (more objective than retest level)
            if sweep.direction == "BULLISH":
                entry_price = current['close']
                stop_loss = sweep.price - (atr * 0.5)  # 0.5 ATR below sweep

                # TP targets: 2R
                risk = entry_price - stop_loss
                take_profit = entry_price + (risk * 2.0)  # 2R target

                signal_direction = "BUY"

            else:  # BEARISH
                entry_price = current['close']
                stop_loss = sweep.price + (atr * 0.5)  # 0.5 ATR above sweep

                # TP targets: 2R
                risk = stop_loss - entry_price
                take_profit = entry_price - (risk * 2.0)  # 2R target

                signal_direction = "SELL"

            # Create signal
            signal = BreakoutSignal(
                entry_price=entry_price,
                stop_loss=stop_loss,
                take_profit=take_profit,
                direction=signal_direction,
                signal_type="SWEEP_BREAKOUT" if not has_retest else "BREAKOUT_RETEST",
                score=score,
                breakdown=breakdown,
                timestamp=current['time'],
                sweep=sweep,
                breakout_level=sweep.price,  # Use sweep price as reference
                retest_confirmed=retest_data.get('rejection_confirmed', False) if has_retest else False
            )

            signals.append(signal)

            logger.info(f"SIGNAL GENERATED: {signal_direction} @ {entry_price:.5f}")
            logger.info(f"  Score: {score}/17, Breakdown: {breakdown}")
            logger.info(f"  SL: {stop_loss:.5f}, TP: {take_profit:.5f}, Risk: {abs(entry_price - stop_loss):.5f}")

        return signals
