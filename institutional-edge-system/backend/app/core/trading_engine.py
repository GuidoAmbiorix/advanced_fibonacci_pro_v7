"""
============================================================================
INSTITUTIONAL EDGE PRO - Core Trading Engine
============================================================================
Smart Money Concepts + Volume Profile + Confluence Scoring

This is the heart of the system. Converted from Pine Script to Python.
"""

import numpy as np
import pandas as pd
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from datetime import datetime
from loguru import logger

try:
    from app.ml.signal_predictor import get_predictor
    ML_AVAILABLE = True
except ImportError:
    ML_AVAILABLE = False
    logger.warning("ML module not available - AI predictions disabled")

from app.core.confluence_system import EnhancedConfluenceScorer, ConfluenceBreakdown


@dataclass
class OrderBlock:
    """Order Block structure with quality scoring"""
    top: float
    bottom: float
    start_time: datetime
    is_bullish: bool
    is_mitigated: bool
    volume: float
    bar_index: int
    # Quality scoring (0-5)
    quality_score: int = 0
    has_displacement: bool = False
    wick_ratio: float = 0.0  # Wick size / total range
    volume_percentile: float = 0.0


@dataclass
class FairValueGap:
    """Fair Value Gap structure with quality scoring"""
    top: float
    bottom: float
    start_time: datetime
    is_bullish: bool
    is_filled: bool
    bar_index: int
    # Quality scoring (0-5)
    quality_score: int = 0
    is_htf: bool = False  # From H4/D1
    has_displacement: bool = False
    size_in_atr: float = 0.0


@dataclass
class SwingPoint:
    """Swing High/Low structure"""
    price: float
    time: datetime
    is_high: bool
    bar_index: int


@dataclass
class TradingSignal:
    """Trading Signal with full context"""
    signal_type: str  # "BUY" or "SELL"
    entry_price: float
    stop_loss: float
    take_profit_1: float
    take_profit_2: float
    take_profit_3: float
    confluence_score: int
    score_breakdown: Dict[str, int]
    timestamp: datetime
    symbol: str
    timeframe: str
    risk_reward_ratio: float
    ai_confidence: float = 0.0  # AI confidence score (0-100)
    ai_recommendation: str = "UNCERTAIN"  # AI recommendation
    fib_level: Optional[str] = None
    fib_zone: Optional[str] = None
    order_type: str = "MARKET"  # MARKET, BUY_LIMIT, SELL_LIMIT, BUY_STOP, SELL_STOP


class TradingEngine:
    """
    Core Trading Engine implementing Institutional Edge Pro logic
    """

    def __init__(self, config: Dict):
        """
        Initialize Trading Engine

        Args:
            config: Configuration dictionary with trading parameters
        """
        self.config = config

        # Trading parameters
        self.swing_length = config.get('swing_length', 10)
        self.ob_lookback = config.get('ob_lookback', 50)
        self.fvg_min_size_atr = config.get('fvg_min_size', 0.3)
        self.min_confluence_score = config.get('min_confluence_score', 6)

        # Multi-timeframe
        self.use_multi_timeframe = config.get('use_multi_timeframe', True)
        self.higher_tf_trend: Optional[str] = None

        # Volume Profile
        self.vp_lookback = config.get('vp_lookback', 100)
        self.vp_rows = config.get('vp_rows', 24)
        self.value_area_percent = config.get('value_area_percent', 70)

        # Storage
        self.bullish_obs: List[OrderBlock] = []
        self.bearish_obs: List[OrderBlock] = []
        self.bullish_fvgs: List[FairValueGap] = []
        self.bearish_fvgs: List[FairValueGap] = []
        self.swing_highs: List[SwingPoint] = []
        self.swing_lows: List[SwingPoint] = []

        # State
        self.trend_bullish = True
        self.poc_level: Optional[float] = None
        self.vah_level: Optional[float] = None
        self.val_level: Optional[float] = None
        self.poc_history: List[float] = []  # Track POC movement

        # Phase 1: BOS/CHoCH tracking
        self.last_bos_type: Optional[str] = None
        self.last_bos_bar_index: Optional[int] = None

        # Session levels
        self.asian_high: Optional[float] = None
        self.asian_low: Optional[float] = None
        self.london_high: Optional[float] = None
        self.london_low: Optional[float] = None
        self.pdh: Optional[float] = None  # Previous Day High
        self.pdl: Optional[float] = None  # Previous Day Low

        # Initialize Enhanced Confluence Scorer (NEW!)
        self.confluence_scorer = EnhancedConfluenceScorer()
        self.use_enhanced_confluence = config.get('use_enhanced_confluence', True)

        # Scoring Weights (OLD - Deprecated, kept for compatibility)
        self.SCORING_WEIGHTS = {
            # Core Structure (Highest Weight)
            'BOS': 3,
            'CHOCH': 3,
            'ORDER_BLOCK': 3,
            'FVG': 2,

            # Liquidity & Manipulation
            'LIQUIDITY_SWEEP': 2,
            'STOP_HUNT': 2,

            # Levels & Zones
            'FIB_GOLDEN': 2,
            'PREMIUM_DISCOUNT': 2,
            'SESSION_LEVEL': 1,

            # Volume Confirmation
            'DELTA_VOLUME': 2,
            'POC_PROXIMITY': 1,
            'VOLUME_SPIKE': 1,

            # Divergence (Leading Indicator)
            'RSI_DIVERGENCE': 2,

            # Multi-Timeframe
            'HTF_ALIGNMENT': 2,

            # Deprecated (kept for compatibility)
            'FIB_NORMAL': 1,
            'TREND_ALIGNMENT': 2
        }

        logger.info("Trading Engine initialized with config: {}", config)


    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None) -> Dict:
        """
        Main analysis function - analyzes price data and returns trading signals

        Args:
            df: DataFrame with OHLCV data (columns: open, high, low, close, volume, time)
            df_higher_tf: Optional higher timeframe data for multi-timeframe analysis

        Returns:
            Dictionary with analysis results and potential signals
        """
        if len(df) < self.vp_lookback:
            logger.warning("Not enough data for analysis. Need at least {} bars", self.vp_lookback)
            return {"error": "Insufficient data"}

        # Multi-timeframe trend check
        if self.use_multi_timeframe and df_higher_tf is not None:
            self._analyze_higher_timeframe(df_higher_tf)

        # Calculate indicators
        df = self._calculate_indicators(df)

        # Detect market structure
        self._detect_swing_points(df)
        self._update_market_structure(df)

        # Phase 1: Detect BOS/CHoCH
        bos_choch_data = self._detect_bos_choch(df)

        # Detect patterns
        self._detect_order_blocks(df)
        self._detect_fair_value_gaps(df)
        self._detect_liquidity_sweeps(df)

        # Volume Profile
        self._calculate_volume_profile(df)

        # Calculate confluence and generate signals
        # Use ENHANCED confluence if enabled
        if self.use_enhanced_confluence:
            confluence_data = self._calculate_confluence_enhanced(df, bos_choch_data)
            logger.debug("Using ENHANCED confluence scoring")
        else:
            confluence_data = self._calculate_confluence(df, bos_choch_data)
            logger.debug("Using OLD confluence scoring")

        signals = self._generate_signals(df, confluence_data)

        return {
            "timestamp": df.iloc[-1]['time'],
            "current_price": df.iloc[-1]['close'],
            "trend": "BULLISH" if self.trend_bullish else "BEARISH",
            "higher_tf_trend": self.higher_tf_trend,
            "active_order_blocks": len([ob for ob in self.bullish_obs + self.bearish_obs if not ob.is_mitigated]),
            "active_fvgs": len([fvg for fvg in self.bullish_fvgs + self.bearish_fvgs if not fvg.is_filled]),
            "poc_level": self.poc_level,
            "vah_level": self.vah_level,
            "val_level": self.val_level,
            "bull_confluence_score": confluence_data['bull_score'],
            "bear_confluence_score": confluence_data['bear_score'],
            "bull_score_breakdown": confluence_data['bull_breakdown'],
            "bear_score_breakdown": confluence_data['bear_breakdown'],
            "signals": signals,
            "premium_discount": self._get_premium_discount_zone(df),
        }

    def _analyze_higher_timeframe(self, df: pd.DataFrame):
        """
        Analyze higher timeframe to determine overall trend

        Args:
            df: Higher timeframe DataFrame
        """
        if len(df) < 20:
            self.higher_tf_trend = "NEUTRAL"
            return

        # Calculate EMA 20 and 50 for trend
        df['ema20'] = df['close'].ewm(span=20).mean()
        df['ema50'] = df['close'].ewm(span=50).mean()

        current_price = df.iloc[-1]['close']
        ema20 = df.iloc[-1]['ema20']
        ema50 = df.iloc[-1]['ema50']

        # Check swing structure
        highs = df['high'].tail(10)
        lows = df['low'].tail(10)

        higher_highs = highs.iloc[-1] > highs.iloc[-5]
        higher_lows = lows.iloc[-1] > lows.iloc[-5]
        lower_highs = highs.iloc[-1] < highs.iloc[-5]
        lower_lows = lows.iloc[-1] < lows.iloc[-5]

        # Determine trend
        if current_price > ema20 > ema50 and higher_highs and higher_lows:
            self.higher_tf_trend = "BULLISH"
            logger.info("Higher TF trend: BULLISH")
        elif current_price < ema20 < ema50 and lower_highs and lower_lows:
            self.higher_tf_trend = "BEARISH"
            logger.info("Higher TF trend: BEARISH")
        else:
            self.higher_tf_trend = "NEUTRAL"
            logger.info("Higher TF trend: NEUTRAL")


    def _calculate_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """Calculate institutional SMC indicators"""
        import ta

        # ===== CORE SMC INDICATORS =====

        # 1. ATR (Volatility + Position Sizing) - ENHANCED
        df['atr'] = ta.volatility.average_true_range(
            df['high'], df['low'], df['close'],
            window=self.config.get('ATR_PERIOD', 14)
        )

        # ATR Percentile Rank (know if volatility is high/low)
        df['atr_rank'] = df['atr'].rolling(100).apply(
            lambda x: (x.iloc[-1] <= x).sum() / len(x) * 100 if len(x) > 0 else 50
        )

        # 2. RSI (For Divergence Detection Only)
        df['rsi'] = ta.momentum.rsi(df['close'], window=14)

        # 3. Volume Analysis
        df['avg_volume'] = df['volume'].rolling(window=20).mean()
        df['volume_spike'] = df['volume'] > (df['avg_volume'] * 1.5)

        # 4. Delta Volume (Buy vs Sell Pressure)
        df = self._calculate_delta_volume(df)

        # 5. Session Levels (Time-Based Support/Resistance)
        df = self._mark_session_levels(df)

        return df

    def _calculate_delta_volume(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Calculate buying vs selling pressure
        Delta = Buy Volume - Sell Volume
        """
        # Approximation: Up volume vs Down volume
        df['up_volume'] = np.where(df['close'] > df['open'], df['volume'], 0)
        df['down_volume'] = np.where(df['close'] < df['open'], df['volume'], 0)

        # Net buying/selling pressure
        df['delta_volume'] = df['up_volume'] - df['down_volume']

        # Cumulative delta (institutional footprint)
        df['cumulative_delta'] = df['delta_volume'].cumsum()

        # Delta moving average
        df['delta_ma'] = df['delta_volume'].rolling(20).mean()

        return df

    def _mark_session_levels(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Mark key session levels (Asian, London, NY)
        Institutions respect these levels
        """
        # Ensure we have datetime
        if 'time' in df.columns:
            df['datetime'] = pd.to_datetime(df['time'])
            df['hour'] = df['datetime'].dt.hour

            # Asian Session: 00:00 - 08:00 UTC
            asian_mask = (df['hour'] >= 0) & (df['hour'] < 8)
            if asian_mask.any():
                self.asian_high = df[asian_mask]['high'].max()
                self.asian_low = df[asian_mask]['low'].min()

            # London Session: 08:00 - 16:00 UTC
            london_mask = (df['hour'] >= 8) & (df['hour'] < 16)
            if london_mask.any():
                self.london_high = df[london_mask]['high'].max()
                self.london_low = df[london_mask]['low'].min()

            # Previous Day High/Low (last 24 bars for H1)
            if len(df) >= 24:
                self.pdh = df['high'].iloc[-24:-1].max()
                self.pdl = df['low'].iloc[-24:-1].min()

        return df

    def _check_session_level_proximity(self, current_price: float, atr: float) -> Dict:
        """
        Check if price is near key session levels
        """
        levels = {
            'asian_high': self.asian_high,
            'asian_low': self.asian_low,
            'london_high': self.london_high,
            'london_low': self.london_low,
            'pdh': self.pdh,
            'pdl': self.pdl
        }

        near_levels = {}
        tolerance = atr * 0.5

        for name, level in levels.items():
            if level and abs(current_price - level) < tolerance:
                near_levels[name] = level

        return near_levels

    def _detect_rsi_divergence(self, df: pd.DataFrame) -> Dict:
        """
        Detect divergences (leading indicator for reversals)
        """
        # Bullish Divergence: Price makes lower low, RSI makes higher low
        # = Momentum weakening, reversal likely

        # Bearish Divergence: Price makes higher high, RSI makes lower high
        # = Uptrend losing steam

        if len(self.swing_lows) < 2:
            return {'bull_div': False, 'bear_div': False}

        bull_div = False
        bear_div = False

        # Check last 2 swing lows
        if (self.swing_lows[-1].price < self.swing_lows[-2].price and
            df.loc[self.swing_lows[-1].bar_index, 'rsi'] >
            df.loc[self.swing_lows[-2].bar_index, 'rsi']):
            bull_div = True
            logger.info("🔵 Bullish RSI Divergence detected")

        # Check last 2 swing highs
        if len(self.swing_highs) >= 2:
            if (self.swing_highs[-1].price > self.swing_highs[-2].price and
                df.loc[self.swing_highs[-1].bar_index, 'rsi'] <
                df.loc[self.swing_highs[-2].bar_index, 'rsi']):
                bear_div = True
                logger.info("🔴 Bearish RSI Divergence detected")

        return {'bull_div': bull_div, 'bear_div': bear_div}

    def _check_volume_confirmation(self, df: pd.DataFrame, signal_type: str) -> bool:
        """
        Check if volume supports the signal
        """
        current = df.iloc[-1]
        avg_delta = df['delta_ma'].iloc[-20:].mean()

        if signal_type == "BUY":
            # Need positive delta (buying pressure)
            return current['delta_volume'] > 0 and current['delta_volume'] > avg_delta
        else:
            # Need negative delta (selling pressure)
            return current['delta_volume'] < 0 and current['delta_volume'] < avg_delta

    def _detect_stop_hunt(self, df: pd.DataFrame) -> Dict:
        """
        Detect classic stop hunts (market maker manipulation)

        Pattern:
        1. Price spikes through obvious level (triggers stops)
        2. Immediately reverses
        3. Strong volume on reversal = liquidity grab
        """
        if len(df) < 5:
            return {'bull_stop_hunt': False, 'bear_stop_hunt': False}

        current = df.iloc[-1]
        prev = df.iloc[-2]
        prev2 = df.iloc[-3]

        # Bullish stop hunt (sweep low, then rally)
        bull_hunt = (
            prev['low'] < prev2['low'] and  # Took out previous low
            current['close'] > prev['high'] and  # Reversed strongly
            current['volume'] > current['avg_volume'] * 1.5  # High volume
        )

        # Bearish stop hunt (sweep high, then dump)
        bear_hunt = (
            prev['high'] > prev2['high'] and  # Took out previous high
            current['close'] < prev['low'] and  # Reversed strongly
            current['volume'] > current['avg_volume'] * 1.5
        )

        if bull_hunt:
            logger.info("🎯 Bullish Stop Hunt detected - Liquidity grab complete")
        if bear_hunt:
            logger.info("🎯 Bearish Stop Hunt detected - Liquidity grab complete")

        return {'bull_stop_hunt': bull_hunt, 'bear_stop_hunt': bear_hunt}

    def _detect_displacement(self, df: pd.DataFrame) -> Dict:
        """
        Detect institutional displacement (strong impulse moves)

        Displacement = Large candle body (>1.5 ATR) + High volume
        Indicates real institutional activity, not retail noise

        Source: LuxAlgo ICT Concepts, MentFX SMC Playbook
        Returns: Dict with bullish/bearish displacement + strength
        """
        if len(df) < 2:
            return {
                'bullish_displacement': False,
                'bearish_displacement': False,
                'strength': 0.0
            }

        current = df.iloc[-1]
        atr = current['atr']

        # Calculate candle body size
        body_size = abs(current['close'] - current['open'])
        total_range = current['high'] - current['low']

        # Displacement criteria
        is_large_body = body_size > (atr * 1.5)  # Strong impulse
        is_high_volume = current['volume'] > df['volume'].quantile(0.80)  # Top 20% volume
        body_dominance = body_size / total_range if total_range > 0 else 0
        is_dominant_body = body_dominance > 0.65  # Body > 65% of total range

        # Determine direction
        is_bullish = current['close'] > current['open']
        is_bearish = current['close'] < current['open']

        # Valid displacement requires all criteria
        bullish_disp = is_bullish and is_large_body and is_high_volume and is_dominant_body
        bearish_disp = is_bearish and is_large_body and is_high_volume and is_dominant_body

        # Calculate strength (for weighting)
        strength = (body_size / atr) if atr > 0 else 0

        if bullish_disp:
            logger.debug(f"🚀 Bullish DISPLACEMENT: {body_size/atr:.2f}x ATR, vol={current['volume']:.0f}")
        if bearish_disp:
            logger.debug(f"🔻 Bearish DISPLACEMENT: {body_size/atr:.2f}x ATR, vol={current['volume']:.0f}")

        return {
            'bullish_displacement': bullish_disp,
            'bearish_displacement': bearish_disp,
            'strength': strength,
            'body_ratio': body_dominance
        }

    def _detect_equal_highs_lows(self, df: pd.DataFrame, tolerance_atr: float = 0.3) -> Dict:
        """
        Detect Equal Highs (EQH) and Equal Lows (EQL) - engineered liquidity

        EQH/EQL = Multiple touches at same level (±tolerance)
        These are liquidity pools that smart money targets for sweeps

        Source: ICT, Smart Money Concepts
        Returns: Dict with EQH/EQL levels and touch counts
        """
        if len(df) < 20:
            return {'eqh_levels': [], 'eql_levels': []}

        atr = df.iloc[-1]['atr']
        tolerance = atr * tolerance_atr

        # Get recent swing highs and lows (last 50 bars)
        lookback = min(50, len(df))
        recent_highs = []
        recent_lows = []

        for i in range(len(df) - lookback, len(df)):
            if i < self.swing_length or i >= len(df) - self.swing_length:
                continue

            bar = df.iloc[i]
            is_swing_high = all(bar['high'] >= df.iloc[i-self.swing_length:i+self.swing_length+1]['high'])
            is_swing_low = all(bar['low'] <= df.iloc[i-self.swing_length:i+self.swing_length+1]['low'])

            if is_swing_high:
                recent_highs.append(bar['high'])
            if is_swing_low:
                recent_lows.append(bar['low'])

        # Find equal levels (clustered touches)
        def find_equal_levels(levels, tolerance):
            if not levels:
                return []

            equal_groups = []
            sorted_levels = sorted(levels)

            current_group = [sorted_levels[0]]
            for level in sorted_levels[1:]:
                if abs(level - current_group[0]) <= tolerance:
                    current_group.append(level)
                else:
                    if len(current_group) >= 2:  # At least 2 touches
                        equal_groups.append({
                            'price': sum(current_group) / len(current_group),
                            'touches': len(current_group)
                        })
                    current_group = [level]

            # Don't forget last group
            if len(current_group) >= 2:
                equal_groups.append({
                    'price': sum(current_group) / len(current_group),
                    'touches': len(current_group)
                })

            return equal_groups

        eqh_levels = find_equal_levels(recent_highs, tolerance)
        eql_levels = find_equal_levels(recent_lows, tolerance)

        if eqh_levels:
            eqh_str = ', '.join([f"{eq['price']:.5f}({eq['touches']}x)" for eq in eqh_levels])
            logger.debug(f"🔺 Found {len(eqh_levels)} EQH level(s): {eqh_str}")
        if eql_levels:
            eql_str = ', '.join([f"{eq['price']:.5f}({eq['touches']}x)" for eq in eql_levels])
            logger.debug(f"🔻 Found {len(eql_levels)} EQL level(s): {eql_str}")

        return {
            'eqh_levels': eqh_levels,
            'eql_levels': eql_levels
        }

    def _check_internal_vs_external_liquidity(self, swept_level: float, df: pd.DataFrame) -> str:
        """
        Classify liquidity sweep as INTERNAL (weak) or EXTERNAL (strong)

        Internal = Recent small swing (last 10-20 bars, <50 pips)
        External = Major HTF swing (50+ bars ago, >100 pips range)

        Only external liquidity sweeps are valid for reversals

        Source: ICT Liquidity Concepts, MentFX
        """
        current_price = df.iloc[-1]['close']
        atr = df.iloc[-1]['atr']

        # Find the swing that was swept
        lookback_short = 20  # Internal
        lookback_long = 100  # External

        # Check if swept level is from recent price action (internal)
        recent_range = df.iloc[-lookback_short:][['high', 'low']].values.flatten()
        is_internal = any(abs(swept_level - price) < atr * 0.5 for price in recent_range)

        if is_internal:
            # Verify it's actually small range
            recent_high = df.iloc[-lookback_short:]['high'].max()
            recent_low = df.iloc[-lookback_short:]['low'].min()
            range_pips = (recent_high - recent_low) / 0.0001  # EURUSD pips

            if range_pips < 50:  # Small internal range
                return "INTERNAL"

        # Check if it's a major HTF level (external)
        htf_range = df.iloc[-lookback_long:][['high', 'low']].values.flatten()
        is_external = any(abs(swept_level - price) < atr * 0.5 for price in htf_range)

        if is_external:
            return "EXTERNAL"

        return "UNKNOWN"

    def _is_in_killzone(self, current_time: datetime) -> Dict:
        """
        Check if current time is within ICT Killzones (high probability trading windows)

        Killzones (EST/NYC time):
        - London Killzone: 02:00-05:00 (Asian-London transition)
        - NY AM Killzone: 08:30-11:00 (NY open)
        - NY PM Killzone: 13:00-15:00 (Lunch + PM session)

        Source: ICT, Smart Money Concepts
        Win rate drops 10-15% outside killzones
        """
        # Convert to UTC hour (assuming input is UTC)
        utc_hour = current_time.hour
        utc_minute = current_time.minute

        # EST = UTC - 5 (standard) or UTC - 4 (daylight)
        # Simplified: use UTC - 5
        est_hour = (utc_hour - 5) % 24

        # London Killzone: 02:00-05:00 EST = 07:00-10:00 UTC
        in_london_kz = 7 <= utc_hour < 10

        # NY AM Killzone: 08:30-11:00 EST = 13:30-16:00 UTC
        in_ny_am_kz = (utc_hour == 13 and utc_minute >= 30) or (14 <= utc_hour < 16)

        # NY PM Killzone: 13:00-15:00 EST = 18:00-20:00 UTC
        in_ny_pm_kz = 18 <= utc_hour < 20

        in_any_killzone = in_london_kz or in_ny_am_kz or in_ny_pm_kz

        killzone_name = ""
        if in_london_kz:
            killzone_name = "LONDON"
        elif in_ny_am_kz:
            killzone_name = "NY_AM"
        elif in_ny_pm_kz:
            killzone_name = "NY_PM"

        return {
            'in_killzone': in_any_killzone,
            'killzone_name': killzone_name,
            'in_london': in_london_kz,
            'in_ny_am': in_ny_am_kz,
            'in_ny_pm': in_ny_pm_kz
        }

    def _check_atr_regime(self, df: pd.DataFrame) -> Dict:
        """
        Check if market volatility is suitable for trading

        Low ATR = ranging/dead market (avoid trading)
        Normal/High ATR = trending market (good for SMC)

        Filter: Only trade when ATR > 1.0x SMA(ATR, 20)
        """
        if len(df) < 20:
            return {'is_suitable': True, 'regime': 'UNKNOWN'}

        current_atr = df.iloc[-1]['atr']
        atr_sma = df['atr'].iloc[-20:].mean()

        atr_ratio = current_atr / atr_sma if atr_sma > 0 else 1.0

        # Classify regime
        if atr_ratio < 0.8:
            regime = "DEAD"  # Very low volatility
            is_suitable = False
        elif atr_ratio < 1.0:
            regime = "LOW"  # Below average
            is_suitable = False
        elif atr_ratio <= 1.3:
            regime = "NORMAL"  # Good
            is_suitable = True
        else:
            regime = "HIGH"  # High volatility (good but manage risk)
            is_suitable = True

        return {
            'is_suitable': is_suitable,
            'regime': regime,
            'atr_ratio': atr_ratio
        }

    def _calculate_vp_trend(self) -> str:
        """Check if POC is rising or falling"""
        if len(self.poc_history) < 3:
            return "NEUTRAL"

        recent_pocs = self.poc_history[-3:]
        if all(recent_pocs[i] < recent_pocs[i+1] for i in range(len(recent_pocs)-1)):
            return "RISING"  # Bullish accumulation
        elif all(recent_pocs[i] > recent_pocs[i+1] for i in range(len(recent_pocs)-1)):
            return "FALLING"  # Bearish distribution
        return "NEUTRAL"

    def _calculate_ob_quality(self, ob: OrderBlock, df: pd.DataFrame, bar_idx: int) -> int:
        """
        Calculate Order Block quality score (0-5)

        Quality factors:
        - Fresh (not mitigated): +2
        - Small wick ratio (<20%): +1
        - High volume (>70th percentile): +1
        - Followed by displacement: +1
        - Strong body dominance: +1 (optional bonus)

        Source: MentFX Institutional Playbook, LuxAlgo
        """
        quality = 0

        # Factor 1: Fresh OB (not mitigated)
        if not ob.is_mitigated:
            quality += 2

        # Factor 2: Small wicks (clean OB)
        total_range = ob.top - ob.bottom
        if total_range > 0:
            # Estimate wick from bar data
            bar = df.iloc[bar_idx]
            if ob.is_bullish:
                lower_wick = bar['low'] - bar['open']
                upper_wick = bar['high'] - bar['close']
            else:
                lower_wick = bar['open'] - bar['low']
                upper_wick = bar['close'] - bar['high']

            total_wick = abs(lower_wick) + abs(upper_wick)
            wick_ratio = total_wick / total_range if total_range > 0 else 1.0

            if wick_ratio < 0.20:  # Wicks < 20% of range
                quality += 1

        # Factor 3: High volume
        vol_percentile = (df.iloc[:bar_idx+1]['volume'] < ob.volume).sum() / len(df.iloc[:bar_idx+1]) * 100
        if vol_percentile > 70:
            quality += 1

        # Factor 4: Followed by displacement (check next 1-3 bars)
        has_displacement = False
        for i in range(bar_idx + 1, min(bar_idx + 4, len(df))):
            next_bar = df.iloc[i]
            body_size = abs(next_bar['close'] - next_bar['open'])
            atr = next_bar['atr']
            if body_size > atr * 1.5:
                has_displacement = True
                break

        if has_displacement:
            quality += 1

        return min(quality, 5)  # Cap at 5

    def _calculate_fvg_quality(self, fvg: FairValueGap, df: pd.DataFrame, bar_idx: int) -> int:
        """
        Calculate Fair Value Gap quality score (0-5)

        Quality factors:
        - Fresh (unfilled): +2
        - Large size (>1.0 ATR): +2
        - HTF aligned: +1
        - Followed by displacement: +1

        Source: ICT FVG concepts, Smart Money
        """
        quality = 0

        # Factor 1: Fresh FVG
        if not fvg.is_filled:
            quality += 2

        # Factor 2: Large FVG (significant imbalance)
        fvg_size = fvg.top - fvg.bottom
        atr = df.iloc[bar_idx]['atr']
        size_in_atr = fvg_size / atr if atr > 0 else 0

        if size_in_atr > 1.0:  # > 1 ATR
            quality += 2
        elif size_in_atr > 0.5:  # > 0.5 ATR
            quality += 1

        # Factor 3: Followed by displacement
        has_displacement = False
        for i in range(bar_idx + 1, min(bar_idx + 4, len(df))):
            next_bar = df.iloc[i]
            body_size = abs(next_bar['close'] - next_bar['open'])
            atr_next = next_bar['atr']
            if body_size > atr_next * 1.5:
                has_displacement = True
                break

        if has_displacement:
            quality += 1

        return min(quality, 5)  # Cap at 5

    def _calculate_bos_choch_quality(self, df: pd.DataFrame, break_bar_idx: int, break_type: str) -> int:
        """
        Calculate Market Structure break quality (0-5)

        Quality factors for BOS/CHoCH:
        - Clean close beyond level (not just wick): +2
        - Accompanied by displacement: +2
        - High volume: +1
        - Body > 50% of candle range: +1

        Source: ICT Market Structure, MentFX
        """
        if break_bar_idx >= len(df):
            return 0

        quality = 0
        break_bar = df.iloc[break_bar_idx]

        # Factor 1: Clean close (body breaks, not just wick)
        body_close = break_bar['close']
        body_open = break_bar['open']

        # For bullish break, close should be high
        # For bearish break, close should be low
        candle_range = break_bar['high'] - break_bar['low']
        if candle_range > 0:
            if break_type in ['BOS_BULL', 'CHOCH_BULL']:
                close_position = (break_bar['close'] - break_bar['low']) / candle_range
            else:
                close_position = (break_bar['high'] - break_bar['close']) / candle_range

            if close_position > 0.5:  # Close in top 50% of range
                quality += 2

        # Factor 2: Displacement (large body)
        body_size = abs(break_bar['close'] - break_bar['open'])
        atr = break_bar['atr']
        if body_size > atr * 1.5:
            quality += 2

        # Factor 3: High volume
        if break_bar['volume'] > break_bar['avg_volume'] * 1.3:
            quality += 1

        # Factor 4: Body dominance
        body_ratio = body_size / candle_range if candle_range > 0 else 0
        if body_ratio > 0.65:
            quality += 1

        return min(quality, 5)

    def _detect_smt_divergence(self, df: pd.DataFrame, correlated_symbol_df: Optional[pd.DataFrame] = None) -> Dict:
        """
        Detect Smart Money Tool (SMT) Divergence

        SMT Divergence = Correlated pairs making opposite moves
        Example: EURUSD makes LL but GBPUSD does NOT = bullish divergence

        This is one of ICT's most powerful tools for filtering false breaks

        Source: ICT SMT Concepts
        Impact: Reduces false BOS/CHOCH by 30%

        Note: Requires correlated pair data (future enhancement)
        For now, returns placeholder
        """
        # TODO: Implement when multi-symbol data available
        # For EURUSD, would check: GBPUSD, USDCHF, DXY

        # Placeholder implementation
        return {
            'has_bullish_smt': False,
            'has_bearish_smt': False,
            'smt_strength': 0,
            'note': 'SMT requires correlated symbol data (not yet implemented)'
        }

    def _detect_swing_points(self, df: pd.DataFrame):
        """Detect swing highs and lows"""
        # Simple pivot detection
        for i in range(self.swing_length, len(df) - self.swing_length):
            # Swing High
            if all(df.iloc[i]['high'] > df.iloc[i-j]['high'] for j in range(1, self.swing_length + 1)) and \
               all(df.iloc[i]['high'] > df.iloc[i+j]['high'] for j in range(1, self.swing_length + 1)):
                swing = SwingPoint(
                    price=df.iloc[i]['high'],
                    time=df.iloc[i]['time'],
                    is_high=True,
                    bar_index=i
                )
                self.swing_highs.append(swing)

            # Swing Low
            if all(df.iloc[i]['low'] < df.iloc[i-j]['low'] for j in range(1, self.swing_length + 1)) and \
               all(df.iloc[i]['low'] < df.iloc[i+j]['low'] for j in range(1, self.swing_length + 1)):
                swing = SwingPoint(
                    price=df.iloc[i]['low'],
                    time=df.iloc[i]['time'],
                    is_high=False,
                    bar_index=i
                )
                self.swing_lows.append(swing)

        # Keep only recent swings
        max_swings = 50
        if len(self.swing_highs) > max_swings:
            self.swing_highs = self.swing_highs[-max_swings:]
        if len(self.swing_lows) > max_swings:
            self.swing_lows = self.swing_lows[-max_swings:]


    def _update_market_structure(self, df: pd.DataFrame):
        """Update market structure (BOS/CHOCH)"""
        if not self.swing_highs or not self.swing_lows:
            return

        last_high = self.swing_highs[-1].price
        last_low = self.swing_lows[-1].price
        current_price = df.iloc[-1]['close']

        # Simple trend detection based on swing points
        if len(self.swing_highs) >= 2 and len(self.swing_lows) >= 2:
            higher_highs = self.swing_highs[-1].price > self.swing_highs[-2].price
            higher_lows = self.swing_lows[-1].price > self.swing_lows[-2].price

            if higher_highs and higher_lows:
                self.trend_bullish = True
            elif not higher_highs and not higher_lows:
                self.trend_bullish = False


    def _detect_order_blocks(self, df: pd.DataFrame):
        """Detect bullish and bearish order blocks"""
        # Clear old mitigated OBs
        self.bullish_obs = [ob for ob in self.bullish_obs if not ob.is_mitigated]
        self.bearish_obs = [ob for ob in self.bearish_obs if not ob.is_mitigated]

        # Look for new OBs in recent bars
        for i in range(max(2, len(df) - self.ob_lookback), len(df) - 2):
            # Calculate average body size for displacement check
            avg_body = abs(df['close'] - df['open']).rolling(window=20).mean().iloc[i]
            current_body = abs(df.iloc[i+1]['close'] - df.iloc[i+1]['open'])
            
            # Bullish OB: down candle followed by strong up move
            if (df.iloc[i]['close'] < df.iloc[i]['open'] and  # Down candle
                df.iloc[i+1]['close'] > df.iloc[i+1]['open'] and  # Up candle
                df.iloc[i+2]['close'] > df.iloc[i]['high'] and  # Break high
                df.iloc[i]['volume'] > df.iloc[i]['avg_volume'] and # Volume confirmation
                current_body > (avg_body * 1.5)): # Displacement check

                ob = OrderBlock(
                    top=df.iloc[i]['high'],
                    bottom=df.iloc[i]['low'],
                    start_time=df.iloc[i]['time'],
                    is_bullish=True,
                    is_mitigated=False,
                    volume=df.iloc[i]['volume'],
                    bar_index=i
                )
                self.bullish_obs.append(ob)

            # Bearish OB: up candle followed by strong down move
            if (df.iloc[i]['close'] > df.iloc[i]['open'] and  # Up candle
                df.iloc[i+1]['close'] < df.iloc[i+1]['open'] and  # Down candle
                df.iloc[i+2]['close'] < df.iloc[i]['low'] and  # Break low
                df.iloc[i]['volume'] > df.iloc[i]['avg_volume'] and # Volume confirmation
                current_body > (avg_body * 1.5)): # Displacement check

                ob = OrderBlock(
                    top=df.iloc[i]['high'],
                    bottom=df.iloc[i]['low'],
                    start_time=df.iloc[i]['time'],
                    is_bullish=False,
                    is_mitigated=False,
                    volume=df.iloc[i]['volume'],
                    bar_index=i
                )
                self.bearish_obs.append(ob)

        # Check for mitigation
        current_close = df.iloc[-1]['close']
        for ob in self.bullish_obs:
            if current_close < ob.bottom:
                ob.is_mitigated = True

        for ob in self.bearish_obs:
            if current_close > ob.top:
                ob.is_mitigated = True

        # Limit storage
        self.bullish_obs = self.bullish_obs[-20:]
        self.bearish_obs = self.bearish_obs[-20:]


    def _detect_fair_value_gaps(self, df: pd.DataFrame):
        """Detect Fair Value Gaps"""
        # Clear old filled FVGs
        self.bullish_fvgs = [fvg for fvg in self.bullish_fvgs if not fvg.is_filled]
        self.bearish_fvgs = [fvg for fvg in self.bearish_fvgs if not fvg.is_filled]

        fvg_min_size = df.iloc[-1]['atr'] * 0.5 # Stricter: Min 0.5 ATR

        for i in range(max(2, len(df) - 100), len(df) - 1):
            # Bullish FVG: gap between candle[i-2] high and candle[i] low
            bull_top = df.iloc[i]['low']
            bull_bottom = df.iloc[i-2]['high']

            if bull_bottom < bull_top and (bull_top - bull_bottom) > fvg_min_size:
                fvg = FairValueGap(
                    top=bull_top,
                    bottom=bull_bottom,
                    start_time=df.iloc[i-1]['time'],
                    is_bullish=True,
                    is_filled=False,
                    bar_index=i-1
                )
                self.bullish_fvgs.append(fvg)

            # Bearish FVG: gap between candle[i] high and candle[i-2] low
            bear_top = df.iloc[i-2]['low']
            bear_bottom = df.iloc[i]['high']

            if bear_bottom < bear_top and (bear_top - bear_bottom) > fvg_min_size:
                fvg = FairValueGap(
                    top=bear_top,
                    bottom=bear_bottom,
                    start_time=df.iloc[i-1]['time'],
                    is_bullish=False,
                    is_filled=False,
                    bar_index=i-1
                )
                self.bearish_fvgs.append(fvg)

        # Check for fills
        current_low = df.iloc[-1]['low']
        current_high = df.iloc[-1]['high']

        for fvg in self.bullish_fvgs:
            if current_low <= fvg.bottom:
                fvg.is_filled = True

        for fvg in self.bearish_fvgs:
            if current_high >= fvg.top:
                fvg.is_filled = True

        # Limit storage
        self.bullish_fvgs = self.bullish_fvgs[-30:]
        self.bearish_fvgs = self.bearish_fvgs[-30:]


    def _detect_liquidity_sweeps(self, df: pd.DataFrame) -> Tuple[bool, bool]:
        """Detect liquidity sweeps"""
        if not self.swing_highs or not self.swing_lows:
            return False, False

        last_high = self.swing_highs[-1].price
        last_low = self.swing_lows[-1].price
        current_high = df.iloc[-1]['high']
        current_low = df.iloc[-1]['low']
        current_close = df.iloc[-1]['close']

        # Bullish sweep: low breaks below swing low but closes above
        bull_sweep = current_low < last_low and current_close > last_low

        # Bearish sweep: high breaks above swing high but closes below
        bear_sweep = current_high > last_high and current_close < last_high

        return bull_sweep, bear_sweep


    def _detect_bos_choch(self, df: pd.DataFrame) -> Dict:
        """
        Detect Break of Structure (BOS) and Change of Character (CHoCH)
        
        BOS: Price breaks the most recent swing high (bullish) or swing low (bearish)
        CHoCH: Price breaks structure in opposite direction, signaling potential reversal
        
        Returns:
            Dict with BOS/CHoCH flags and recency
        """
        from app.core.phase1_config import BOS_RECENT_BARS
        
        result = {
            'bos_bullish': False,
            'bos_bearish': False,
            'choch_to_bullish': False,
            'choch_to_bearish': False,
            'bos_recent': False
        }
        
        if not self.swing_highs or not self.swing_lows or len(self.swing_highs) < 2 or len(self.swing_lows) < 2:
            return result
            
        current_bar = len(df) - 1
        current_high = df.iloc[-1]['high']
        current_low = df.iloc[-1]['low']
        
        # Get most recent swing points
        last_swing_high = self.swing_highs[-1]
        prev_swing_high = self.swing_highs[-2]
        last_swing_low = self.swing_lows[-1]
        prev_swing_low = self.swing_lows[-2]
        
        current_close = df.iloc[-1]['close']

        # Bullish BOS: Price breaks above most recent swing high (continuation in uptrend)
        # STRICT: Requires CLOSE above swing high, not just wick
        if current_close > last_swing_high.price:
            result['bos_bullish'] = True
            self.last_bos_type = "BULLISH"
            self.last_bos_bar_index = current_bar
            logger.info("🔵 Bullish BOS detected - Price closed above {:.5f}", last_swing_high.price)
            
        # Bearish BOS: Price breaks below most recent swing low (continuation in downtrend)
        # STRICT: Requires CLOSE below swing low
        if current_close < last_swing_low.price:
            result['bos_bearish'] = True
            self.last_bos_type = "BEARISH"
            self.last_bos_bar_index = current_bar
            logger.info("🔴 Bearish BOS detected - Price closed below {:.5f}", last_swing_low.price)
            
        # CHoCH to Bullish: In downtrend, price breaks above previous swing high (trend change signal)
        if not self.trend_bullish and current_high > prev_swing_high.price:
            result['choch_to_bullish'] = True
            logger.info("🟢 CHoCH to Bullish - Potential trend reversal")
            
        # CHoCH to Bearish: In uptrend, price breaks below previous swing low (trend change signal)
        if self.trend_bullish and current_low < prev_swing_low.price:
            result['choch_to_bearish'] = True
            logger.info("🟠 CHoCH to Bearish - Potential trend reversal")
            
        # Check if BOS is recent (within last N bars)
        if self.last_bos_bar_index is not None:
            bars_since_bos = current_bar - self.last_bos_bar_index
            result['bos_recent'] = bars_since_bos <= BOS_RECENT_BARS
            
        return result


    def _calculate_volume_profile(self, df: pd.DataFrame):
        """Calculate Volume Profile and POC"""
        if len(df) < self.vp_lookback:
            return

        # Get recent data
        recent_df = df.tail(self.vp_lookback)

        highest_price = recent_df['high'].max()
        lowest_price = recent_df['low'].min()
        price_range = highest_price - lowest_price
        row_height = price_range / self.vp_rows

        # Build volume profile
        vp_volumes = np.zeros(self.vp_rows)

        for idx, row in recent_df.iterrows():
            for i in range(self.vp_rows):
                row_low = lowest_price + (i * row_height)
                row_high = row_low + row_height

                # Check overlap
                if row['low'] <= row_high and row['high'] >= row_low:
                    overlap = min(row['high'], row_high) - max(row['low'], row_low)
                    candle_range = row['high'] - row['low']
                    if candle_range > 0:
                        vp_volumes[i] += row['volume'] * (overlap / candle_range)

        # Find POC (Point of Control)
        max_volume_row = np.argmax(vp_volumes)
        self.poc_level = lowest_price + (max_volume_row * row_height) + (row_height / 2)

        # Track POC history for trend detection
        self.poc_history.append(self.poc_level)
        if len(self.poc_history) > 10:
            self.poc_history = self.poc_history[-10:]

        # Calculate Value Area
        total_volume = vp_volumes.sum()
        va_volume = total_volume * (self.value_area_percent / 100)

        accumulated_volume = vp_volumes[max_volume_row]
        vah_row = max_volume_row
        val_row = max_volume_row

        while accumulated_volume < va_volume:
            above_vol = vp_volumes[vah_row + 1] if vah_row < self.vp_rows - 1 else 0
            below_vol = vp_volumes[val_row - 1] if val_row > 0 else 0

            if above_vol >= below_vol and vah_row < self.vp_rows - 1:
                vah_row += 1
                accumulated_volume += above_vol
            elif val_row > 0:
                val_row -= 1
                accumulated_volume += below_vol
            else:
                break

        self.vah_level = lowest_price + (vah_row * row_height) + row_height
        self.val_level = lowest_price + (val_row * row_height)


    def _get_premium_discount_zone(self, df: pd.DataFrame) -> Dict:
        """Get current premium/discount zone"""
        if not self.swing_highs or not self.swing_lows:
            return {"zone": "NEUTRAL", "equilibrium": None}

        last_high = self.swing_highs[-1].price
        last_low = self.swing_lows[-1].price
        equilibrium = (last_high + last_low) / 2
        current_price = df.iloc[-1]['close']

        if current_price > equilibrium:
            return {"zone": "PREMIUM", "equilibrium": equilibrium}
        else:
            return {"zone": "DISCOUNT", "equilibrium": equilibrium}


    def _calculate_confluence(self, df: pd.DataFrame, bos_choch_data: Dict) -> Dict:
        """
        Calculate confluence scores for both directions
        ENHANCED: Pure SMC with institutional indicators
        """
        bull_score = 0
        bear_score = 0
        bull_breakdown = {}
        bear_breakdown = {}

        current_price = df.iloc[-1]['close']
        current_low = df.iloc[-1]['low']
        current_high = df.iloc[-1]['high']
        atr = df.iloc[-1]['atr']

        # ===== CORE STRUCTURE (Highest Weight) =====

        # 1. Order Block (Weight: 3)
        at_bullish_ob = any(ob.bottom <= current_low <= ob.top for ob in self.bullish_obs if not ob.is_mitigated)
        at_bearish_ob = any(ob.bottom <= current_high <= ob.top for ob in self.bearish_obs if not ob.is_mitigated)

        if at_bullish_ob:
            bull_score += self.SCORING_WEIGHTS['ORDER_BLOCK']
            bull_breakdown['Order Block'] = self.SCORING_WEIGHTS['ORDER_BLOCK']
        if at_bearish_ob:
            bear_score += self.SCORING_WEIGHTS['ORDER_BLOCK']
            bear_breakdown['Order Block'] = self.SCORING_WEIGHTS['ORDER_BLOCK']

        # 2. FVG (Weight: 2)
        at_bullish_fvg = any(fvg.bottom <= current_price <= fvg.top for fvg in self.bullish_fvgs if not fvg.is_filled)
        at_bearish_fvg = any(fvg.bottom <= current_price <= fvg.top for fvg in self.bearish_fvgs if not fvg.is_filled)

        if at_bullish_fvg:
            bull_score += self.SCORING_WEIGHTS['FVG']
            bull_breakdown['FVG'] = self.SCORING_WEIGHTS['FVG']
        if at_bearish_fvg:
            bear_score += self.SCORING_WEIGHTS['FVG']
            bear_breakdown['FVG'] = self.SCORING_WEIGHTS['FVG']

        # 3. BOS/CHoCH (Weight: 3)
        if bos_choch_data['bos_bullish'] and bos_choch_data['bos_recent']:
            bull_score += self.SCORING_WEIGHTS['BOS']
            bull_breakdown['BOS Bullish'] = self.SCORING_WEIGHTS['BOS']

        if bos_choch_data['bos_bearish'] and bos_choch_data['bos_recent']:
            bear_score += self.SCORING_WEIGHTS['BOS']
            bear_breakdown['BOS Bearish'] = self.SCORING_WEIGHTS['BOS']

        if bos_choch_data['choch_to_bullish']:
            bull_score += self.SCORING_WEIGHTS['CHOCH']
            bull_breakdown['CHoCH Reversal'] = self.SCORING_WEIGHTS['CHOCH']

        if bos_choch_data['choch_to_bearish']:
            bear_score += self.SCORING_WEIGHTS['CHOCH']
            bear_breakdown['CHoCH Reversal'] = self.SCORING_WEIGHTS['CHOCH']

        # ===== LIQUIDITY & MANIPULATION =====

        # 4. Liquidity Sweep (Weight: 2)
        bull_sweep, bear_sweep = self._detect_liquidity_sweeps(df)
        if bull_sweep:
            bull_score += self.SCORING_WEIGHTS['LIQUIDITY_SWEEP']
            bull_breakdown['Liquidity Sweep'] = self.SCORING_WEIGHTS['LIQUIDITY_SWEEP']
        if bear_sweep:
            bear_score += self.SCORING_WEIGHTS['LIQUIDITY_SWEEP']
            bear_breakdown['Liquidity Sweep'] = self.SCORING_WEIGHTS['LIQUIDITY_SWEEP']

        # 5. Stop Hunt (Weight: 2)
        stop_hunt = self._detect_stop_hunt(df)
        if stop_hunt['bull_stop_hunt']:
            bull_score += self.SCORING_WEIGHTS['STOP_HUNT']
            bull_breakdown['Stop Hunt'] = self.SCORING_WEIGHTS['STOP_HUNT']
        if stop_hunt['bear_stop_hunt']:
            bear_score += self.SCORING_WEIGHTS['STOP_HUNT']
            bear_breakdown['Stop Hunt'] = self.SCORING_WEIGHTS['STOP_HUNT']

        # ===== LEVELS & ZONES =====

        # 6. Fibonacci Confluence (Weight: 2 for golden, 1 for normal)
        fib_data = self._calculate_fibonacci_levels(df)

        if fib_data['bullish_level']:
            score = self.SCORING_WEIGHTS['FIB_GOLDEN'] if fib_data['is_golden_zone'] else self.SCORING_WEIGHTS['FIB_NORMAL']
            bull_score += score
            bull_breakdown[f'Fib {fib_data["bullish_level"]}'] = score

        if fib_data['bearish_level']:
            score = self.SCORING_WEIGHTS['FIB_GOLDEN'] if fib_data['is_golden_zone'] else self.SCORING_WEIGHTS['FIB_NORMAL']
            bear_score += score
            bear_breakdown[f'Fib {fib_data["bearish_level"]}'] = score

        # 7. Premium/Discount Zone (Weight: 2)
        pd_zone = self._get_premium_discount_zone(df)
        if pd_zone['zone'] == 'DISCOUNT':
            bull_score += self.SCORING_WEIGHTS['PREMIUM_DISCOUNT']
            bull_breakdown['Discount Zone'] = self.SCORING_WEIGHTS['PREMIUM_DISCOUNT']
        elif pd_zone['zone'] == 'PREMIUM':
            bear_score += self.SCORING_WEIGHTS['PREMIUM_DISCOUNT']
            bear_breakdown['Premium Zone'] = self.SCORING_WEIGHTS['PREMIUM_DISCOUNT']

        # 8. Session Levels (Weight: 1)
        near_session_levels = self._check_session_level_proximity(current_price, atr)
        if near_session_levels:
            # If price at session low + bullish setup = strong support
            if any('low' in level for level in near_session_levels):
                bull_score += self.SCORING_WEIGHTS['SESSION_LEVEL']
                bull_breakdown['Session Level'] = self.SCORING_WEIGHTS['SESSION_LEVEL']

            # If price at session high + bearish setup = strong resistance
            if any('high' in level for level in near_session_levels):
                bear_score += self.SCORING_WEIGHTS['SESSION_LEVEL']
                bear_breakdown['Session Level'] = self.SCORING_WEIGHTS['SESSION_LEVEL']

        # ===== VOLUME CONFIRMATION =====

        # 9. Delta Volume (Weight: 2)
        delta_vol_bull = self._check_volume_confirmation(df, "BUY")
        delta_vol_bear = self._check_volume_confirmation(df, "SELL")

        if delta_vol_bull:
            bull_score += self.SCORING_WEIGHTS['DELTA_VOLUME']
            bull_breakdown['Delta Volume'] = self.SCORING_WEIGHTS['DELTA_VOLUME']
        if delta_vol_bear:
            bear_score += self.SCORING_WEIGHTS['DELTA_VOLUME']
            bear_breakdown['Delta Volume'] = self.SCORING_WEIGHTS['DELTA_VOLUME']

        # 10. POC Proximity (Weight: 1)
        if self.poc_level and abs(current_price - self.poc_level) < atr * 0.5:
            # Check POC trend direction
            poc_trend = self._calculate_vp_trend()
            if poc_trend == "RISING":
                bull_score += self.SCORING_WEIGHTS['POC_PROXIMITY']
                bull_breakdown['POC Rising'] = self.SCORING_WEIGHTS['POC_PROXIMITY']
            elif poc_trend == "FALLING":
                bear_score += self.SCORING_WEIGHTS['POC_PROXIMITY']
                bear_breakdown['POC Falling'] = self.SCORING_WEIGHTS['POC_PROXIMITY']
            else:
                # Neutral POC = support/resistance
                bull_score += self.SCORING_WEIGHTS['POC_PROXIMITY']
                bear_score += self.SCORING_WEIGHTS['POC_PROXIMITY']
                bull_breakdown['Near POC'] = self.SCORING_WEIGHTS['POC_PROXIMITY']
                bear_breakdown['Near POC'] = self.SCORING_WEIGHTS['POC_PROXIMITY']

        # 11. Volume Spike (Weight: 1)
        if df.iloc[-1]['volume_spike']:
            if df.iloc[-1]['close'] > df.iloc[-1]['open']:
                bull_score += self.SCORING_WEIGHTS['VOLUME_SPIKE']
                bull_breakdown['Volume Spike'] = self.SCORING_WEIGHTS['VOLUME_SPIKE']
            else:
                bear_score += self.SCORING_WEIGHTS['VOLUME_SPIKE']
                bear_breakdown['Volume Spike'] = self.SCORING_WEIGHTS['VOLUME_SPIKE']

        # ===== DIVERGENCE (Leading Indicator) =====

        # 12. RSI Divergence (Weight: 2)
        rsi_div = self._detect_rsi_divergence(df)
        if rsi_div['bull_div']:
            bull_score += self.SCORING_WEIGHTS['RSI_DIVERGENCE']
            bull_breakdown['RSI Divergence'] = self.SCORING_WEIGHTS['RSI_DIVERGENCE']
        if rsi_div['bear_div']:
            bear_score += self.SCORING_WEIGHTS['RSI_DIVERGENCE']
            bear_breakdown['RSI Divergence'] = self.SCORING_WEIGHTS['RSI_DIVERGENCE']

        # ===== MULTI-TIMEFRAME =====

        # 13. HTF Alignment (Weight: 2)
        if self.higher_tf_trend == "BULLISH":
            bull_score += self.SCORING_WEIGHTS['HTF_ALIGNMENT']
            bull_breakdown['HTF Bullish'] = self.SCORING_WEIGHTS['HTF_ALIGNMENT']
        elif self.higher_tf_trend == "BEARISH":
            bear_score += self.SCORING_WEIGHTS['HTF_ALIGNMENT']
            bear_breakdown['HTF Bearish'] = self.SCORING_WEIGHTS['HTF_ALIGNMENT']

        # Don't cap scores - let them reflect true confluence
        # Maximum possible ~25 points with all confluence

        return {
            'bull_score': bull_score,
            'bear_score': bear_score,
            'bull_breakdown': bull_breakdown,
            'bear_breakdown': bear_breakdown,
            'fib_data': fib_data,
            'bos_choch_data': bos_choch_data
        }

    def _calculate_confluence_enhanced(self, df: pd.DataFrame, bos_choch_data: Dict) -> Dict:
        """
        FULLY ENHANCED confluence calculation with ALL new factors

        Integrates:
        - Displacement detection
        - OB/FVG quality scoring
        - Market structure quality
        - Internal vs External liquidity
        - EQH/EQL detection
        - Killzones
        - ATR regime filter
        - SMT divergence (placeholder)

        Returns separate scores for CONTINUATION vs REVERSAL
        """
        current_price = df.iloc[-1]['close']
        current_low = df.iloc[-1]['low']
        current_high = df.iloc[-1]['high']
        current_time = df.iloc[-1]['time']
        atr = df.iloc[-1]['atr']

        # ===== RUN ALL DETECTORS =====

        # 🔥 NEW: Displacement
        displacement = self._detect_displacement(df)
        has_bull_displacement = displacement['bullish_displacement']
        has_bear_displacement = displacement['bearish_displacement']

        # 🔥 NEW: EQH/EQL
        eqh_eql = self._detect_equal_highs_lows(df)
        has_eqh = len(eqh_eql['eqh_levels']) > 0
        has_eql = len(eqh_eql['eql_levels']) > 0

        # 🔥 NEW: Killzone
        killzone = self._is_in_killzone(current_time)
        in_killzone = killzone['in_killzone']

        # 🔥 NEW: ATR Regime
        atr_regime = self._check_atr_regime(df)
        atr_ok = atr_regime['is_suitable']

        # 🔥 NEW: SMT Divergence (placeholder for now)
        smt = self._detect_smt_divergence(df)

        # 1. Structure
        has_bos_bull = bos_choch_data.get('bos_bullish', False) and bos_choch_data.get('bos_recent', False)
        has_bos_bear = bos_choch_data.get('bos_bearish', False) and bos_choch_data.get('bos_recent', False)
        has_choch_bull = bos_choch_data.get('choch_to_bullish', False)
        has_choch_bear = bos_choch_data.get('choch_to_bearish', False)

        # 🔥 NEW: Calculate Market Structure Quality
        bull_ms_quality = 0
        bear_ms_quality = 0
        if has_bos_bull or has_choch_bull:
            bull_ms_quality = self._calculate_bos_choch_quality(
                df, len(df) - 1, 'BOS_BULL' if has_bos_bull else 'CHOCH_BULL'
            )
        if has_bos_bear or has_choch_bear:
            bear_ms_quality = self._calculate_bos_choch_quality(
                df, len(df) - 1, 'BOS_BEAR' if has_bos_bear else 'CHOCH_BEAR'
            )

        # 2. Price Action with Quality Scoring
        bull_ob = None
        bear_ob = None
        bull_fvg = None
        bear_fvg = None
        bull_ob_quality = 0
        bear_ob_quality = 0
        bull_fvg_quality = 0
        bear_fvg_quality = 0

        # Find OB with quality
        for ob in self.bullish_obs:
            if not ob.is_mitigated and ob.bottom <= current_low <= ob.top:
                bull_ob = ob
                bull_ob_quality = ob.quality_score if hasattr(ob, 'quality_score') else 0
                break

        for ob in self.bearish_obs:
            if not ob.is_mitigated and ob.bottom <= current_high <= ob.top:
                bear_ob = ob
                bear_ob_quality = ob.quality_score if hasattr(ob, 'quality_score') else 0
                break

        # Find FVG with quality
        for fvg in self.bullish_fvgs:
            if not fvg.is_filled and fvg.bottom <= current_price <= fvg.top:
                bull_fvg = fvg
                bull_fvg_quality = fvg.quality_score if hasattr(fvg, 'quality_score') else 0
                break

        for fvg in self.bearish_fvgs:
            if not fvg.is_filled and fvg.bottom <= current_price <= fvg.top:
                bear_fvg = fvg
                bear_fvg_quality = fvg.quality_score if hasattr(fvg, 'quality_score') else 0
                break

        at_bullish_ob = bull_ob is not None
        at_bearish_ob = bear_ob is not None
        at_bullish_fvg = bull_fvg is not None
        at_bearish_fvg = bear_fvg is not None

        # 3. Fibonacci
        fib_data = self._calculate_fibonacci_levels(df)
        bull_fib_score = 0
        bear_fib_score = 0

        if fib_data['bullish_level']:
            is_golden = fib_data['is_golden_zone']
            bull_fib_score = self.confluence_scorer.WEIGHTS['FIB_SINGLE_TF']
            if is_golden:
                bull_fib_score += self.confluence_scorer.WEIGHTS['GOLDEN_POCKET']

        if fib_data['bearish_level']:
            is_golden = fib_data['is_golden_zone']
            bear_fib_score = self.confluence_scorer.WEIGHTS['FIB_SINGLE_TF']
            if is_golden:
                bear_fib_score += self.confluence_scorer.WEIGHTS['GOLDEN_POCKET']

        # Log Fibonacci
        if bull_fib_score > 0:
            level = fib_data.get('bullish_level', 'N/A')
            price = fib_data.get('bullish_price', 0)
            is_golden = fib_data.get('is_golden_zone', False)
            logger.debug(f"🟢 Bull Fibonacci Score: {bull_fib_score} (level: {level}@{price:.5f}, golden: {is_golden})")
        if bear_fib_score > 0:
            level = fib_data.get('bearish_level', 'N/A')
            price = fib_data.get('bearish_price', 0)
            is_golden = fib_data.get('is_golden_zone', False)
            logger.debug(f"🔴 Bear Fibonacci Score: {bear_fib_score} (level: {level}@{price:.5f}, golden: {is_golden})")

        # 4. Liquidity with Internal/External classification
        bull_sweep, bear_sweep = self._detect_liquidity_sweeps(df)
        stop_hunt = self._detect_stop_hunt(df)

        # 🔥 NEW: Classify liquidity type
        bull_liq_type = "NONE"
        bear_liq_type = "NONE"

        if bull_sweep and self.swing_lows:
            last_low = self.swing_lows[-1].price
            liq_type = self._check_internal_vs_external_liquidity(last_low, df)
            bull_liq_type = liq_type

        if bear_sweep and self.swing_highs:
            last_high = self.swing_highs[-1].price
            liq_type = self._check_internal_vs_external_liquidity(last_high, df)
            bear_liq_type = liq_type

        # 5. Volume
        delta_vol_bull = self._check_volume_confirmation(df, "BUY")
        delta_vol_bear = self._check_volume_confirmation(df, "SELL")
        has_volume_spike = df.iloc[-1]['volume_spike']

        # 6. POC
        poc_trend = self._calculate_vp_trend()
        at_poc = self.poc_level and abs(current_price - self.poc_level) < atr * 0.5
        poc_rising = poc_trend == "RISING"
        poc_falling = poc_trend == "FALLING"

        # 7. HTF Alignment
        htf_bull = self.higher_tf_trend == "BULLISH"
        htf_bear = self.higher_tf_trend == "BEARISH"

        # 8. Zones
        pd_zone = self._get_premium_discount_zone(df)
        in_discount = pd_zone['zone'] == 'DISCOUNT'
        in_premium = pd_zone['zone'] == 'PREMIUM'

        # 9. Session Levels
        near_session_levels = self._check_session_level_proximity(current_price, atr)
        at_session_low = any('low' in level for level in near_session_levels) if near_session_levels else False
        at_session_high = any('high' in level for level in near_session_levels) if near_session_levels else False

        # ===== SCORE BULLISH SIGNALS =====

        bull_continuation = None
        bull_reversal = None

        # Bullish CONTINUATION (BOS + retracement)
        if has_bos_bull or self.trend_bullish:
            bull_continuation = self.confluence_scorer.score_continuation(
                has_bos=has_bos_bull,
                at_ob=at_bullish_ob,
                at_fvg=at_bullish_fvg,
                fib_score=bull_fib_score,
                has_delta_volume=delta_vol_bull,
                has_volume_spike=has_volume_spike,
                at_poc=at_poc,
                poc_rising=poc_rising,
                htf_aligned=htf_bull,
                in_discount_zone=in_discount,
                at_session_level=at_session_low,
                # 🔥 NEW PARAMETERS
                has_displacement=has_bull_displacement,
                ob_quality=bull_ob_quality,
                fvg_quality=bull_fvg_quality,
                ms_quality=bull_ms_quality,
                has_eqh_eql=has_eql,
                in_killzone=in_killzone,
                atr_regime_ok=atr_ok,
                htf_imbalance=False,  # TODO: implement HTF imbalance detection
                liquidity_type=bull_liq_type
            )

        # Bullish REVERSAL (CHoCH + liquidity grab)
        if has_choch_bull:
            bull_reversal = self.confluence_scorer.score_reversal(
                has_choch=has_choch_bull,
                at_ob=at_bullish_ob,
                at_fvg=at_bullish_fvg,
                fib_score=bull_fib_score,
                has_liquidity_sweep=bull_sweep,
                has_stop_hunt=stop_hunt.get('bull_stop_hunt', False),
                has_delta_volume=delta_vol_bull,
                htf_aligned=htf_bull,
                in_correct_zone=in_discount,
                # 🔥 NEW PARAMETERS
                has_displacement=has_bull_displacement,
                ob_quality=bull_ob_quality,
                fvg_quality=bull_fvg_quality,
                ms_quality=bull_ms_quality,
                has_eqh_eql=has_eql,
                in_killzone=in_killzone,
                atr_regime_ok=atr_ok,
                htf_imbalance=False,
                liquidity_type=bull_liq_type
            )

        # ===== SCORE BEARISH SIGNALS =====

        bear_continuation = None
        bear_reversal = None

        # Bearish CONTINUATION (BOS + retracement)
        if has_bos_bear or (not self.trend_bullish):
            bear_continuation = self.confluence_scorer.score_continuation(
                has_bos=has_bos_bear,
                at_ob=at_bearish_ob,
                at_fvg=at_bearish_fvg,
                fib_score=bear_fib_score,
                has_delta_volume=delta_vol_bear,
                has_volume_spike=has_volume_spike,
                at_poc=at_poc,
                poc_rising=poc_falling,
                htf_aligned=htf_bear,
                in_discount_zone=in_premium,
                at_session_level=at_session_high,
                # 🔥 NEW PARAMETERS
                has_displacement=has_bear_displacement,
                ob_quality=bear_ob_quality,
                fvg_quality=bear_fvg_quality,
                ms_quality=bear_ms_quality,
                has_eqh_eql=has_eqh,
                in_killzone=in_killzone,
                atr_regime_ok=atr_ok,
                htf_imbalance=False,
                liquidity_type=bear_liq_type
            )

        # Bearish REVERSAL (CHoCH + liquidity grab)
        if has_choch_bear:
            bear_reversal = self.confluence_scorer.score_reversal(
                has_choch=has_choch_bear,
                at_ob=at_bearish_ob,
                at_fvg=at_bearish_fvg,
                fib_score=bear_fib_score,
                has_liquidity_sweep=bear_sweep,
                has_stop_hunt=stop_hunt.get('bear_stop_hunt', False),
                has_delta_volume=delta_vol_bear,
                htf_aligned=htf_bear,
                in_correct_zone=in_premium,
                # 🔥 NEW PARAMETERS
                has_displacement=has_bear_displacement,
                ob_quality=bear_ob_quality,
                fvg_quality=bear_fvg_quality,
                ms_quality=bear_ms_quality,
                has_eqh_eql=has_eqh,
                in_killzone=in_killzone,
                atr_regime_ok=atr_ok,
                htf_imbalance=False,
                liquidity_type=bear_liq_type
            )

        # ===== PICK BEST VALID SIGNAL =====

        all_signals = []
        min_score = self.min_confluence_score  # From config

        # Check bull continuation
        if bull_continuation:
            is_valid, reason = bull_continuation.is_valid(min_score_override=min_score)
            logger.debug(f"🔵 Bull CONTINUATION: score={bull_continuation.total_score}, valid={is_valid}, reason={reason}, factors={bull_continuation.factors}")
            if is_valid:
                all_signals.append({
                    'type': 'BUY',
                    'trade_type': 'CONTINUATION',
                    'score': bull_continuation.total_score,
                    'breakdown': bull_continuation
                })

        # Check bull reversal
        if bull_reversal:
            is_valid, reason = bull_reversal.is_valid(min_score_override=min_score)
            logger.debug(f"🔵 Bull REVERSAL: score={bull_reversal.total_score}, valid={is_valid}, reason={reason}, factors={bull_reversal.factors}")
            if is_valid:
                all_signals.append({
                    'type': 'BUY',
                    'trade_type': 'REVERSAL',
                    'score': bull_reversal.total_score,
                    'breakdown': bull_reversal
                })

        # Check bear continuation
        if bear_continuation:
            is_valid, reason = bear_continuation.is_valid(min_score_override=min_score)
            logger.debug(f"🔴 Bear CONTINUATION: score={bear_continuation.total_score}, valid={is_valid}, reason={reason}, factors={bear_continuation.factors}")
            if is_valid:
                all_signals.append({
                    'type': 'SELL',
                    'trade_type': 'CONTINUATION',
                    'score': bear_continuation.total_score,
                    'breakdown': bear_continuation
                })

        # Check bear reversal
        if bear_reversal:
            is_valid, reason = bear_reversal.is_valid(min_score_override=min_score)
            logger.debug(f"🔴 Bear REVERSAL: score={bear_reversal.total_score}, valid={is_valid}, reason={reason}, factors={bear_reversal.factors}")
            if is_valid:
                all_signals.append({
                    'type': 'SELL',
                    'trade_type': 'REVERSAL',
                    'score': bear_reversal.total_score,
                    'breakdown': bear_reversal
                })

        # Pick highest score
        if not all_signals:
            return {
                'bull_score': 0,
                'bear_score': 0,
                'bias': 'NEUTRAL',
                'signals': [],
                'bull_breakdown': {},
                'bear_breakdown': {},
                'fib_data': fib_data,
                'bos_choch_data': bos_choch_data
            }

        # Sort by score descending
        all_signals.sort(key=lambda x: x['score'], reverse=True)
        best_signal = all_signals[0]

        # Extract scores and breakdowns
        bull_score = 0
        bear_score = 0
        bull_breakdown = {}
        bear_breakdown = {}

        if bull_continuation and bull_continuation.is_valid(min_score_override=min_score)[0]:
            bull_score = bull_continuation.total_score
            bull_breakdown = bull_continuation.factors
        if bull_reversal and bull_reversal.is_valid(min_score_override=min_score)[0]:
            bull_score = max(bull_score, bull_reversal.total_score)
            if bull_reversal.total_score > bull_continuation.total_score if bull_continuation else 0:
                bull_breakdown = bull_reversal.factors

        if bear_continuation and bear_continuation.is_valid(min_score_override=min_score)[0]:
            bear_score = bear_continuation.total_score
            bear_breakdown = bear_continuation.factors
        if bear_reversal and bear_reversal.is_valid(min_score_override=min_score)[0]:
            bear_score = max(bear_score, bear_reversal.total_score)
            if bear_reversal.total_score > bear_continuation.total_score if bear_continuation else 0:
                bear_breakdown = bear_reversal.factors

        return {
            'bull_score': bull_score,
            'bear_score': bear_score,
            'bias': best_signal['type'],
            'signals': all_signals,
            'best_signal': best_signal,
            'bull_breakdown': bull_breakdown,
            'bear_breakdown': bear_breakdown,
            'fib_data': fib_data,
            'bos_choch_data': bos_choch_data
        }


    def _calculate_fibonacci_levels(self, df: pd.DataFrame) -> Dict:
        """
        Calculate Fibonacci retracement levels based on recent swings
        FIXED: More lenient tolerance and better swing detection
        """
        if not self.swing_highs or not self.swing_lows:
            return {
                'bullish_level': None,
                'bearish_level': None,
                'is_golden_zone': False,
                'bullish_price': None,
                'bearish_price': None,
                'extensions': {}
            }

        current_price = df.iloc[-1]['close']
        atr = df.iloc[-1]['atr']

        # Sort all swings by time to find the last leg
        all_swings = sorted(self.swing_highs + self.swing_lows, key=lambda x: x.bar_index)

        if len(all_swings) < 2:
            return {
                'bullish_level': None,
                'bearish_level': None,
                'is_golden_zone': False,
                'bullish_price': None,
                'bearish_price': None,
                'extensions': {}
            }

        last_swing = all_swings[-1]
        prev_swing = all_swings[-2]

        result = {
            'bullish_level': None,
            'bearish_level': None,
            'is_golden_zone': False,
            'bullish_price': None,
            'bearish_price': None,
            'nearest_level': None,
            'extensions': {}
        }

        # RELAXED tolerance: 1 ATR around Fib level (was 0.5 ATR)
        tolerance = atr * 1.0

        # Log swing analysis
        logger.debug(
            f"📊 Fibonacci Analysis: price={current_price:.5f}, "
            f"last_swing={'HIGH' if last_swing.is_high else 'LOW'}@{last_swing.price:.5f}, "
            f"prev_swing={'HIGH' if prev_swing.is_high else 'LOW'}@{prev_swing.price:.5f}, "
            f"tolerance={tolerance:.5f}"
        )

        # Identify the last leg direction
        # If last swing was a High, the leg was Up (Low -> High). We look for Bullish Retracement (Dip).
        if last_swing.is_high:
            # Leg: Low -> High (Uptrend leg)
            # Retracement: Downwards
            high_price = last_swing.price
            low_price = prev_swing.price

            # Validate it was actually a low before
            if not prev_swing.is_high:
                range_price = high_price - low_price

                # Retracement levels
                fib_levels = {
                    '0.382': high_price - (range_price * 0.382),
                    '0.5': high_price - (range_price * 0.5),
                    '0.618': high_price - (range_price * 0.618),
                    '0.786': high_price - (range_price * 0.786)
                }

                # Extension levels for TP targets
                result['extensions'] = {
                    '1.272': high_price + (range_price * 0.272),
                    '1.414': high_price + (range_price * 0.414),
                    '1.618': high_price + (range_price * 0.618),
                    '2.0': high_price + range_price,
                    '2.618': high_price + (range_price * 1.618)
                }

                # Log calculated levels
                logger.debug(f"📊 Bullish Fib Levels: {', '.join([f'{k}={v:.5f}' for k, v in fib_levels.items()])}")

                # Check proximity (RELAXED tolerance)
                for level_name, price in fib_levels.items():
                    if abs(current_price - price) < tolerance:
                        result['bullish_level'] = level_name
                        result['bullish_price'] = price
                        if level_name in ['0.618', '0.786']:
                            result['is_golden_zone'] = True
                        logger.debug(f"✅ Bullish Fibonacci MATCH: {level_name} @ {price:.5f} (current: {current_price:.5f}, diff: {abs(current_price - price):.5f}, tolerance: {tolerance:.5f})")
                        break

                # Log if no match found
                if not result['bullish_level']:
                    nearest = min(fib_levels.items(), key=lambda x: abs(current_price - x[1]))
                    logger.debug(f"❌ No Bullish Fib match. Nearest: {nearest[0]}@{nearest[1]:.5f}, diff={abs(current_price - nearest[1]):.5f} > tolerance={tolerance:.5f}")

        # If last swing was a Low, the leg was Down (High -> Low). We look for Bearish Retracement (Rally).
        else:
            # Leg: High -> Low (Downtrend leg)
            # Retracement: Upwards
            low_price = last_swing.price
            high_price = prev_swing.price

            # Validate it was actually a high before
            if prev_swing.is_high:
                range_price = high_price - low_price

                # Retracement levels
                fib_levels = {
                    '0.382': low_price + (range_price * 0.382),
                    '0.5': low_price + (range_price * 0.5),
                    '0.618': low_price + (range_price * 0.618),
                    '0.786': low_price + (range_price * 0.786)
                }

                # Extension levels for TP targets
                result['extensions'] = {
                    '1.272': low_price - (range_price * 0.272),
                    '1.414': low_price - (range_price * 0.414),
                    '1.618': low_price - (range_price * 0.618),
                    '2.0': low_price - range_price,
                    '2.618': low_price - (range_price * 1.618)
                }

                # Log calculated levels
                logger.debug(f"📊 Bearish Fib Levels: {', '.join([f'{k}={v:.5f}' for k, v in fib_levels.items()])}")

                # Check proximity (RELAXED tolerance)
                for level_name, price in fib_levels.items():
                    if abs(current_price - price) < tolerance:
                        result['bearish_level'] = level_name
                        result['bearish_price'] = price
                        if level_name in ['0.618', '0.786']:
                            result['is_golden_zone'] = True
                        logger.debug(f"✅ Bearish Fibonacci MATCH: {level_name} @ {price:.5f} (current: {current_price:.5f}, diff: {abs(current_price - price):.5f}, tolerance: {tolerance:.5f})")
                        break

                # Log if no match found
                if not result['bearish_level']:
                    nearest = min(fib_levels.items(), key=lambda x: abs(current_price - x[1]))
                    logger.debug(f"❌ No Bearish Fib match. Nearest: {nearest[0]}@{nearest[1]:.5f}, diff={abs(current_price - nearest[1]):.5f} > tolerance={tolerance:.5f}")

        return result


    def _calculate_dynamic_sl(self, signal_type: str, entry_price: float, atr: float) -> float:
        """
        Calculate Dynamic Stop Loss based on Market Structure
        Fallback to ATR if no structure found
        """
        sl_price = None
        
        # Search range for structure (e.g., max 3 ATR away)
        max_dist = atr * 3.0
        min_dist = atr * 0.5 # Minimum breathing room
        
        if signal_type == "BUY":
            # 1. Look for nearest Swing Low below entry
            valid_swings = [s.price for s in self.swing_lows if s.price < entry_price and (entry_price - s.price) < max_dist]
            if valid_swings:
                # Use the highest of the valid swing lows (nearest support)
                structure_sl = max(valid_swings)
                sl_price = structure_sl - (atr * 0.2) # Small buffer below swing
                
            # 2. Look for Bullish OB bottom
            if not sl_price:
                valid_obs = [ob.bottom for ob in self.bullish_obs if ob.bottom < entry_price and (entry_price - ob.bottom) < max_dist]
                if valid_obs:
                    structure_sl = max(valid_obs)
                    sl_price = structure_sl - (atr * 0.2)
                    
            # Fallback: ATR
            if not sl_price or (entry_price - sl_price) < min_dist:
                sl_price = entry_price - (atr * 1.5)
                
        else: # SELL
            # 1. Look for nearest Swing High above entry
            valid_swings = [s.price for s in self.swing_highs if s.price > entry_price and (s.price - entry_price) < max_dist]
            if valid_swings:
                # Use the lowest of the valid swing highs (nearest resistance)
                structure_sl = min(valid_swings)
                sl_price = structure_sl + (atr * 0.2) # Small buffer above swing
                
            # 2. Look for Bearish OB top
            if not sl_price:
                valid_obs = [ob.top for ob in self.bearish_obs if ob.top > entry_price and (ob.top - entry_price) < max_dist]
                if valid_obs:
                    structure_sl = min(valid_obs)
                    sl_price = structure_sl + (atr * 0.2)
            
            # Fallback: ATR
            if not sl_price or (sl_price - entry_price) < min_dist:
                sl_price = entry_price + (atr * 1.5)
                
        return sl_price


    def _calculate_limit_entry(self, signal_type: str, current_price: float, atr: float) -> Tuple[float, str]:
        """
        Calculate optimal entry price (Limit vs Market)
        Returns (entry_price, order_type)
        """
        # Default to Market
        entry_price = current_price
        order_type = "MARKET" # Will be converted to BUY/SELL later
        
        # Check for unmitigated Order Blocks nearby
        if signal_type == "BUY":
            # Look for OB below current price but close (within 1 ATR)
            nearby_obs = [ob for ob in self.bullish_obs if ob.top < current_price and (current_price - ob.top) < atr]
            if nearby_obs:
                # Entry at OB Top (Retest)
                best_ob = nearby_obs[-1] # Most recent
                entry_price = best_ob.top
                order_type = "BUY_LIMIT"
                return entry_price, order_type
                
            # Check for FVG
            nearby_fvgs = [fvg for fvg in self.bullish_fvgs if fvg.top < current_price and (current_price - fvg.top) < atr]
            if nearby_fvgs:
                # Entry at FVG Top or Midpoint
                best_fvg = nearby_fvgs[-1]
                entry_price = best_fvg.top # Aggressive entry at top of gap
                order_type = "BUY_LIMIT"
                return entry_price, order_type

        else: # SELL
            # Look for OB above current price
            nearby_obs = [ob for ob in self.bearish_obs if ob.bottom > current_price and (ob.bottom - current_price) < atr]
            if nearby_obs:
                best_ob = nearby_obs[-1]
                entry_price = best_ob.bottom
                order_type = "SELL_LIMIT"
                return entry_price, order_type
                
            # Check for FVG
            nearby_fvgs = [fvg for fvg in self.bearish_fvgs if fvg.bottom > current_price and (fvg.bottom - current_price) < atr]
            if nearby_fvgs:
                best_fvg = nearby_fvgs[-1]
                entry_price = best_fvg.bottom
                order_type = "SELL_LIMIT"
                return entry_price, order_type
                
        return entry_price, order_type


    def _generate_signals(self, df: pd.DataFrame, confluence_data: Dict) -> List[TradingSignal]:
        """Generate trading signals based on confluence"""
        signals = []

        bull_score = confluence_data['bull_score']
        bear_score = confluence_data['bear_score']
        current_price = df.iloc[-1]['close']
        atr = df.iloc[-1]['atr']

        # Multi-timeframe filter: only take signals aligned with higher TF trend
        higher_tf_allows_buy = True
        higher_tf_allows_sell = True

        if self.use_multi_timeframe and self.higher_tf_trend:
            if self.higher_tf_trend == "BEARISH":
                higher_tf_allows_buy = False
                logger.info("Skipping BUY signals - Higher TF is BEARISH")
            elif self.higher_tf_trend == "BULLISH":
                higher_tf_allows_sell = False
                logger.info("Skipping SELL signals - Higher TF is BULLISH")

        # Phase 1: BOS/CHoCH filter - only generate signals with structure confirmation
        bos_choch_data = confluence_data.get('bos_choch_data', {})
        bos_allows_buy = bos_choch_data.get('bos_bullish', False) and bos_choch_data.get('bos_recent', False)
        choch_allows_buy = bos_choch_data.get('choch_to_bullish', False)
        bos_allows_sell = bos_choch_data.get('bos_bearish', False) and bos_choch_data.get('bos_recent', False)
        choch_allows_sell = bos_choch_data.get('choch_to_bearish', False)

        # Bull Signal  
        # RELAXED: Removed strict (bos_allows_buy or choch_allows_buy) requirement
        # Now allows trades if Score is high AND (Trend is Bullish OR it's a CHoCH Reversal)
        # This allows OB retests where BOS happened a while ago
        is_valid_bull_context = self.trend_bullish or choch_allows_buy
        
        if bull_score >= self.min_confluence_score and higher_tf_allows_buy and is_valid_bull_context:
            # Calculate Limit Entry
            entry_price, order_type = self._calculate_limit_entry("BUY", current_price, atr)
            
            # Calculate Dynamic SL
            stop_loss = self._calculate_dynamic_sl("BUY", entry_price, atr)
            risk = entry_price - stop_loss
            
            logger.info(f"DEBUG SL CALC: Entry={entry_price}, Type={order_type}, SL={stop_loss}, Risk={risk}")

            signal = TradingSignal(
                signal_type="BUY",
                entry_price=entry_price,
                stop_loss=stop_loss,
                take_profit_1=entry_price + (risk * 1.5),
                take_profit_2=entry_price + (risk * 3.0),
                take_profit_3=entry_price + (risk * 5.0),
                confluence_score=bull_score,
                score_breakdown=confluence_data['bull_breakdown'],
                timestamp=df.iloc[-1]['time'],
                symbol=self.config.get('symbol', 'UNKNOWN'),
                timeframe=self.config.get('timeframe', 'UNKNOWN'),
                risk_reward_ratio=3.0,
                fib_level=confluence_data['fib_data']['bullish_level'],
                fib_zone="GOLDEN" if confluence_data['fib_data']['is_golden_zone'] else None,
                order_type=order_type
            )

            # Add AI confidence prediction
            if ML_AVAILABLE:
                try:
                    predictor = get_predictor()
                    signal_data = {
                        'signal_type': 'BUY',
                        'confluence_score': bull_score,
                        'score_breakdown': confluence_data['bull_breakdown'],
                        'entry_price': entry_price,
                        'stop_loss': stop_loss,
                        'take_profit_1': signal.take_profit_1
                    }
                    market_data = {
                        'current_price': current_price,
                        'atr': atr,
                        'higher_tf_trend': self.higher_tf_trend,
                        'volatility_percentile': 50,
                        'active_order_blocks': len([ob for ob in self.bullish_obs + self.bearish_obs if not ob.is_mitigated]),
                        'active_fvgs': len([fvg for fvg in self.bullish_fvgs + self.bearish_fvgs if not fvg.is_filled]),
                        'near_poc': abs(current_price - self.poc_level) < atr if self.poc_level else False,
                        'in_value_area': self.val_level <= current_price <= self.vah_level if self.val_level and self.vah_level else False,
                        'zone': self._get_premium_discount_zone(df)
                    }

                    ai_confidence, ai_recommendation = predictor.predict(signal_data, market_data)
                    signal.ai_confidence = ai_confidence
                    signal.ai_recommendation = ai_recommendation

                    trade_type_info = f" [{confluence_data.get('bull_trade_type', '')}]" if 'bull_trade_type' in confluence_data else ""
                    logger.info("✅ BUY signal generated{} - Confluence: {}/10, AI: {:.1f}% ({})",
                               trade_type_info, bull_score, ai_confidence, ai_recommendation)
                except Exception as e:
                    logger.error("AI prediction error: {}", e)
            else:
                trade_type_info = f" [{confluence_data.get('bull_trade_type', '')}]" if 'bull_trade_type' in confluence_data else ""
                logger.info("✅ BUY signal generated{} with higher TF confirmation", trade_type_info)

            signals.append(signal)

        # Bear Signal
        # RELAXED: Removed strict (bos_allows_sell or choch_allows_sell) requirement
        is_valid_bear_context = (not self.trend_bullish) or choch_allows_sell
        
        if bear_score >= self.min_confluence_score and higher_tf_allows_sell and is_valid_bear_context:
            # Calculate Limit Entry
            entry_price, order_type = self._calculate_limit_entry("SELL", current_price, atr)
            
            # Calculate Dynamic SL
            stop_loss = self._calculate_dynamic_sl("SELL", entry_price, atr)
            risk = stop_loss - entry_price
            
            logger.info(f"DEBUG SL CALC (SELL): Entry={entry_price}, Type={order_type}, SL={stop_loss}, Risk={risk}")

            signal = TradingSignal(
                signal_type="SELL",
                entry_price=entry_price,
                stop_loss=stop_loss,
                take_profit_1=entry_price - (risk * 1.5),
                take_profit_2=entry_price - (risk * 3.0),
                take_profit_3=entry_price - (risk * 5.0),
                confluence_score=bear_score,
                score_breakdown=confluence_data['bear_breakdown'],
                timestamp=df.iloc[-1]['time'],
                symbol=self.config.get('symbol', 'UNKNOWN'),
                timeframe=self.config.get('timeframe', 'UNKNOWN'),
                risk_reward_ratio=3.0,
                fib_level=confluence_data['fib_data']['bearish_level'],
                fib_zone="GOLDEN" if confluence_data['fib_data']['is_golden_zone'] else None,
                order_type=order_type
            )

            # Add AI confidence prediction
            if ML_AVAILABLE:
                try:
                    predictor = get_predictor()
                    signal_data = {
                        'signal_type': 'SELL',
                        'confluence_score': bear_score,
                        'score_breakdown': confluence_data['bear_breakdown'],
                        'entry_price': current_price,
                        'stop_loss': stop_loss,
                        'take_profit_1': signal.take_profit_1
                    }
                    market_data = {
                        'current_price': current_price,
                        'atr': atr,
                        'higher_tf_trend': self.higher_tf_trend,
                        'volatility_percentile': 50,
                        'active_order_blocks': len([ob for ob in self.bullish_obs + self.bearish_obs if not ob.is_mitigated]),
                        'active_fvgs': len([fvg for fvg in self.bullish_fvgs + self.bearish_fvgs if not fvg.is_filled]),
                        'near_poc': abs(current_price - self.poc_level) < atr if self.poc_level else False,
                        'in_value_area': self.val_level <= current_price <= self.vah_level if self.val_level and self.vah_level else False,
                        'zone': self._get_premium_discount_zone(df)
                    }

                    ai_confidence, ai_recommendation = predictor.predict(signal_data, market_data)
                    signal.ai_confidence = ai_confidence
                    signal.ai_recommendation = ai_recommendation

                    logger.info("✅ SELL signal generated - Confluence: {}/10, AI: {:.1f}% ({})",
                               bear_score, ai_confidence, ai_recommendation)
                except Exception as e:
                    logger.error("AI prediction error: {}", e)
            else:
                logger.info("✅ SELL signal generated with higher TF confirmation")

            signals.append(signal)

        return signals
