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


@dataclass
class OrderBlock:
    """Order Block structure"""
    top: float
    bottom: float
    start_time: datetime
    is_bullish: bool
    is_mitigated: bool
    volume: float
    bar_index: int


@dataclass
class FairValueGap:
    """Fair Value Gap structure"""
    top: float
    bottom: float
    start_time: datetime
    is_bullish: bool
    is_filled: bool
    bar_index: int


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

        # Phase 1: BOS/CHoCH tracking
        self.last_bos_type: Optional[str] = None
        self.last_bos_bar_index: Optional[int] = None

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
        confluence_data = self._calculate_confluence(df, bos_choch_data)
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
        """Calculate technical indicators"""
        # ATR
        df['atr'] = self._calculate_atr(df, 14)

        # Average Volume
        df['avg_volume'] = df['volume'].rolling(window=20).mean()

        # Volume spike
        df['volume_spike'] = df['volume'] > (df['avg_volume'] * 1.5)

        return df


    def _calculate_atr(self, df: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculate Average True Range"""
        high = df['high']
        low = df['low']
        close = df['close']

        tr1 = high - low
        tr2 = abs(high - close.shift())
        tr3 = abs(low - close.shift())

        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(window=period).mean()

        return atr


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
            # Bullish OB: down candle followed by strong up move
            if (df.iloc[i]['close'] < df.iloc[i]['open'] and  # Down candle
                df.iloc[i+1]['close'] > df.iloc[i+1]['open'] and  # Up candle
                df.iloc[i+2]['close'] > df.iloc[i]['high'] and  # Break high
                df.iloc[i]['volume'] > df.iloc[i]['avg_volume']):  # Volume confirmation

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
                df.iloc[i]['volume'] > df.iloc[i]['avg_volume']):  # Volume confirmation

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

        fvg_min_size = df.iloc[-1]['atr'] * self.fvg_min_size_atr

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
        
        # Bullish BOS: Price breaks above most recent swing high (continuation in uptrend)
        if current_high > last_swing_high.price:
            result['bos_bullish'] = True
            self.last_bos_type = "BULLISH"
            self.last_bos_bar_index = current_bar
            logger.info("🔵 Bullish BOS detected - Price broke above {:.5f}", last_swing_high.price)
            
        # Bearish BOS: Price breaks below most recent swing low (continuation in downtrend)
        if current_low < last_swing_low.price:
            result['bos_bearish'] = True
            self.last_bos_type = "BEARISH"
            self.last_bos_bar_index = current_bar
            logger.info("🔴 Bearish BOS detected - Price broke below {:.5f}", last_swing_low.price)
            
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
        """Calculate confluence scores for both directions"""
        bull_score = 0
        bear_score = 0
        bull_breakdown = {}
        bear_breakdown = {}

        current_price = df.iloc[-1]['close']
        current_low = df.iloc[-1]['low']
        current_high = df.iloc[-1]['high']
        atr = df.iloc[-1]['atr']

        # 1. Order Block (+2)
        at_bullish_ob = any(ob.bottom <= current_low <= ob.top for ob in self.bullish_obs if not ob.is_mitigated)
        at_bearish_ob = any(ob.bottom <= current_high <= ob.top for ob in self.bearish_obs if not ob.is_mitigated)

        if at_bullish_ob:
            bull_score += 2
            bull_breakdown['Order Block'] = 2
        if at_bearish_ob:
            bear_score += 2
            bear_breakdown['Order Block'] = 2

        # 2. FVG (+2)
        at_bullish_fvg = any(fvg.bottom <= current_price <= fvg.top for fvg in self.bullish_fvgs if not fvg.is_filled)
        at_bearish_fvg = any(fvg.bottom <= current_price <= fvg.top for fvg in self.bearish_fvgs if not fvg.is_filled)

        if at_bullish_fvg:
            bull_score += 2
            bull_breakdown['FVG'] = 2
        if at_bearish_fvg:
            bear_score += 2
            bear_breakdown['FVG'] = 2

        # 3. Market Structure (+2)
        if self.trend_bullish:
            bull_score += 2
            bull_breakdown['Trend'] = 2
        else:
            bear_score += 2
            bear_breakdown['Trend'] = 2

        # 4. Premium/Discount Zone (+2)
        pd_zone = self._get_premium_discount_zone(df)
        if pd_zone['zone'] == 'DISCOUNT':
            bull_score += 2
            bull_breakdown['Discount Zone'] = 2
        elif pd_zone['zone'] == 'PREMIUM':
            bear_score += 2
            bear_breakdown['Premium Zone'] = 2

        # 5. Liquidity Sweep (+2)
        bull_sweep, bear_sweep = self._detect_liquidity_sweeps(df)
        if bull_sweep:
            bull_score += 2
            bull_breakdown['Liquidity Sweep'] = 2
        if bear_sweep:
            bear_score += 2
            bear_breakdown['Liquidity Sweep'] = 2

        # 6. POC Proximity (+1)
        if self.poc_level and abs(current_price - self.poc_level) < atr * 0.5:
            bull_score += 1
            bear_score += 1
            bull_breakdown['Near POC'] = 1
            bear_breakdown['Near POC'] = 1

        # 7. Volume (+1)
        if df.iloc[-1]['volume_spike']:
            if df.iloc[-1]['close'] > df.iloc[-1]['open']:
                bull_score += 1
                bull_breakdown['Volume'] = 1
            else:
                bear_score += 1
                bear_breakdown['Volume'] = 1

        # 8. Fibonacci Confluence (+2 for Golden Zone, +1 for other levels)
        fib_data = self._calculate_fibonacci_levels(df)
        
        # Bullish Fib (Retracement from High to Low for buying dip? No, Bullish Retracement is Low to High, buying the pull back)
        # Wait, standard fib retracement:
        # Uptrend: Draw from Low to High. Price retraces down to levels.
        # Downtrend: Draw from High to Low. Price retraces up to levels.
        
        if fib_data['bullish_level']:
            score = 2 if fib_data['is_golden_zone'] else 1
            bull_score += score
            bull_breakdown[f'Fib {fib_data["bullish_level"]}'] = score
            
        if fib_data['bearish_level']:
            score = 2 if fib_data['is_golden_zone'] else 1
            bear_score += score
            bear_breakdown[f'Fib {fib_data["bearish_level"]}'] = score

        # 9. BOS/CHoCH Confluence (+2 for BOS, +3 for CHoCH)
        from app.core.phase1_config import BOS_CONFLUENCE_POINTS, CHOCH_CONFLUENCE_POINTS
        
        # Bullish BOS: Recent break above structure
        if bos_choch_data['bos_bullish'] and bos_choch_data['bos_recent']:
            bull_score += BOS_CONFLUENCE_POINTS
            bull_breakdown['BOS Bullish'] = BOS_CONFLUENCE_POINTS
            
        # Bearish BOS: Recent break below structure
        if bos_choch_data['bos_bearish'] and bos_choch_data['bos_recent']:
            bear_score += BOS_CONFLUENCE_POINTS
            bear_breakdown['BOS Bearish'] = BOS_CONFLUENCE_POINTS
            
        # CHoCH to Bullish: High-quality reversal setup
        if bos_choch_data['choch_to_bullish']:
            bull_score += CHOCH_CONFLUENCE_POINTS
            bull_breakdown['CHoCH Reversal'] = CHOCH_CONFLUENCE_POINTS
            
        # CHoCH to Bearish: High-quality reversal setup
        if bos_choch_data['choch_to_bearish']:
            bear_score += CHOCH_CONFLUENCE_POINTS
            bear_breakdown['CHoCH Reversal'] = CHOCH_CONFLUENCE_POINTS

        # Normalize to 0-10 (allow going over 10 slightly with extra confluence, but cap at 10 for standardizing)
        bull_score = min(bull_score, 10)
        bear_score = min(bear_score, 10)

        return {
            'bull_score': bull_score,
            'bear_score': bear_score,
            'bull_breakdown': bull_breakdown,
            'bear_breakdown': bear_breakdown,
            'fib_data': fib_data,
            'bos_choch_data': bos_choch_data
        }


    def _calculate_fibonacci_levels(self, df: pd.DataFrame) -> Dict:
        """
        Calculate Fibonacci retracement levels based on recent swings
        Returns dictionary with active levels and zones
        """
        if not self.swing_highs or not self.swing_lows:
            return {'bullish_level': None, 'bearish_level': None, 'is_golden_zone': False}

        current_price = df.iloc[-1]['close']
        
        # Find most recent significant swing points
        # For Bullish setup (buying a dip): We need a recent Low -> High move
        last_low = self.swing_lows[-1].price
        last_high = self.swing_highs[-1].price
        
        # Ensure the high came after the low for a valid bullish leg
        # But swing points are stored in lists, we need to check their indices/times
        # Let's just take the most recent high and low for simplicity first, 
        # but ideally we want the defined "Trend Leg"
        
        # Simple approach: Use the range of the last N bars or the detected swings
        # Let's use the last confirmed swing high and low
        
        result = {
            'bullish_level': None, 
            'bearish_level': None, 
            'is_golden_zone': False,
            'nearest_level': None
        }

        # Check Bullish Retracement (Price coming down from High)
        # Range: Low -> High
        if last_high > last_low:
            range_price = last_high - last_low
            fib_levels = {
                '0.382': last_high - (range_price * 0.382),
                '0.5': last_high - (range_price * 0.5),
                '0.618': last_high - (range_price * 0.618),
                '0.786': last_high - (range_price * 0.786)
            }
            
            # Check if current price is near any level
            for level_name, price in fib_levels.items():
                # Tolerance: 0.1% of price
                tolerance = current_price * 0.001
                if abs(current_price - price) < tolerance:
                    result['bullish_level'] = level_name
                    if level_name in ['0.5', '0.618']:
                        result['is_golden_zone'] = True
                    break

        # Check Bearish Retracement (Price going up from Low)
        # Range: High -> Low
        # Note: If we are in a downtrend, the last swing might be a Lower High and Lower Low
        # We need the move from High down to Low
        
        # Let's look at the last 2 swings to define the range
        # If we are looking for a SELL, we expect price to retrace UP
        # So we need a previous High -> Low move
        
        # For now, let's just check proximity to levels calculated from the recent range
        # regardless of trend direction, as the confluence score handles the trend filter
        
        if last_high > last_low:
            # This is an uptrend leg, so we look for bullish retracements (dips)
            pass 
        else:
            # This is a downtrend leg (High -> Low), we look for bearish retracements (rallies)
            range_price = last_high - last_low
            fib_levels = {
                '0.382': last_low + (range_price * 0.382),
                '0.5': last_low + (range_price * 0.5),
                '0.618': last_low + (range_price * 0.618),
                '0.786': last_low + (range_price * 0.786)
            }
            
            for level_name, price in fib_levels.items():
                tolerance = current_price * 0.001
                if abs(current_price - price) < tolerance:
                    result['bearish_level'] = level_name
                    if level_name in ['0.5', '0.618']:
                        result['is_golden_zone'] = True
                    break
                    
        return result


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
        if bull_score >= self.min_confluence_score and self.trend_bullish and higher_tf_allows_buy and (bos_allows_buy or choch_allows_buy):
            stop_loss = current_price - (atr * 1.5)
            risk = current_price - stop_loss
            
            logger.info(f"DEBUG SL CALC: Price={current_price}, ATR={atr}, SL={stop_loss}, Risk={risk}")

            signal = TradingSignal(
                signal_type="BUY",
                entry_price=current_price,
                stop_loss=stop_loss,
                take_profit_1=current_price + (risk * 1.5),
                take_profit_2=current_price + (risk * 3.0),
                take_profit_3=current_price + (risk * 5.0),
                confluence_score=bull_score,
                score_breakdown=confluence_data['bull_breakdown'],
                timestamp=df.iloc[-1]['time'],
                symbol=self.config.get('symbol', 'UNKNOWN'),
                timeframe=self.config.get('timeframe', 'UNKNOWN'),
                risk_reward_ratio=3.0,
                fib_level=confluence_data['fib_data']['bullish_level'],
                fib_zone="GOLDEN" if confluence_data['fib_data']['is_golden_zone'] else None
            )

            # Add AI confidence prediction
            if ML_AVAILABLE:
                try:
                    predictor = get_predictor()
                    signal_data = {
                        'signal_type': 'BUY',
                        'confluence_score': bull_score,
                        'score_breakdown': confluence_data['bull_breakdown'],
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

                    logger.info("✅ BUY signal generated - Confluence: {}/10, AI: {:.1f}% ({})",
                               bull_score, ai_confidence, ai_recommendation)
                except Exception as e:
                    logger.error("AI prediction error: {}", e)
            else:
                logger.info("✅ BUY signal generated with higher TF confirmation")

            signals.append(signal)

        # Bear Signal
        if bear_score >= self.min_confluence_score and not self.trend_bullish and higher_tf_allows_sell and (bos_allows_sell or choch_allows_sell):
            stop_loss = current_price + (atr * 1.5)
            risk = stop_loss - current_price
            
            logger.info(f"DEBUG SL CALC (SELL): Price={current_price}, ATR={atr}, SL={stop_loss}, Risk={risk}")

            signal = TradingSignal(
                signal_type="SELL",
                entry_price=current_price,
                stop_loss=stop_loss,
                take_profit_1=current_price - (risk * 1.5),
                take_profit_2=current_price - (risk * 3.0),
                take_profit_3=current_price - (risk * 5.0),
                confluence_score=bear_score,
                score_breakdown=confluence_data['bear_breakdown'],
                timestamp=df.iloc[-1]['time'],
                symbol=self.config.get('symbol', 'UNKNOWN'),
                timeframe=self.config.get('timeframe', 'UNKNOWN'),
                risk_reward_ratio=3.0,
                fib_level=confluence_data['fib_data']['bearish_level'],
                fib_zone="GOLDEN" if confluence_data['fib_data']['is_golden_zone'] else None
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
