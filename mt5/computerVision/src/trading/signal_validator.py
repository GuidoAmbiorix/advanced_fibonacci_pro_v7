"""
Signal Validator - Enhanced Multi-Factor Signal Confirmation System

Validates trading signals using 7 factors:
- Multi-timeframe alignment (leverages MTFAnalyzer)
- Momentum confirmation (RSI, MACD, Stochastic)
- Volume validation (OBV, volume ratio)
- Trend strength (ADX, DI)
- Fibonacci alignment (OTE zones, confluence) ✨ NEW
- Smart Money Concepts (Order Blocks, FVG, BOS, CHoCH) ✨ NEW
- Model confidence

Returns confirmation scores (0-100) and detailed validation breakdown.
"""

import logging
import requests
from typing import Dict, Tuple, Optional
from datetime import datetime
import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))

from src.features.mtf_analyzer import MTFAnalyzer
from src.features.fibonacci_analyzer import FibonacciAnalyzer
from src.features.smc_analyzer import SMCAnalyzer

try:
    import talib
    import pandas as pd
    import numpy as np
    TALIB_AVAILABLE = True
except ImportError:
    TALIB_AVAILABLE = False


class SignalValidator:
    """
    Validates trading signals using multiple confirmation methods.
    Heavily leverages existing MTFAnalyzer for most validation logic.
    """

    def __init__(self, db_manager, config: Dict, bridge_url: str = "http://10.0.0.4:5000"):
        """
        Initialize Signal Validator.

        Args:
            db_manager: DatabaseManager instance
            config: Configuration dictionary with validation settings
            bridge_url: MT5 Bridge URL for fetching market data
        """
        self.db = db_manager
        self.config = config
        self.bridge_url = bridge_url
        self.logger = logging.getLogger(__name__)

        # Initialize analyzers
        self.mtf_analyzer = MTFAnalyzer(db_manager)
        self.fibonacci_analyzer = FibonacciAnalyzer(db_manager, config)
        self.smc_analyzer = SMCAnalyzer(db_manager, config)

        # Get validation settings
        self.validation_config = config.get('signal_confirmation', {})
        self.enabled = self.validation_config.get('enabled', True)
        self.min_confirmation_score = self.validation_config.get('min_confirmation_score', 70)

        # Enhanced validation weights (7 factors, sum to 100)
        weights_config = self.validation_config.get('weights', {})
        self.weights = {
            'mtf_alignment': weights_config.get('mtf_alignment', 25),
            'momentum_confluence': weights_config.get('momentum_confluence', 20),
            'volume_confirmation': weights_config.get('volume_confirmation', 15),
            'trend_strength': weights_config.get('trend_strength', 12),
            'model_confidence': weights_config.get('model_confidence', 8),
            'fibonacci_alignment': weights_config.get('fibonacci_alignment', 12),
            'smc_confluence': weights_config.get('smc_confluence', 8)
        }

        # Check if Fibonacci and SMC are enabled
        self.fibonacci_enabled = self.validation_config.get('fibonacci_validation', {}).get('enabled', True)
        self.smc_enabled = self.validation_config.get('smc_validation', {}).get('enabled', True)

    def validate_signal(self, prediction: dict, trading_timeframe: str = 'H1') -> Tuple[bool, float, Dict]:
        """
        Validate a trading signal using multiple confirmation methods.

        Args:
            prediction: Prediction dictionary from database
            trading_timeframe: Trading timeframe (e.g., 'H1')

        Returns:
            (is_valid, confirmation_score, validation_details)
        """
        if not self.enabled:
            return True, 100.0, {'reason': 'Validation disabled'}

        symbol = prediction['symbol']
        direction = prediction['prediction_direction']
        confidence = prediction['confidence']

        self.logger.info(f"🔍 Validating signal: {direction} {symbol} (ML confidence: {confidence:.1%})")

        validation_details = {
            'symbol': symbol,
            'direction': direction,
            'ml_confidence': confidence,
            'timestamp': datetime.now().isoformat()
        }

        # Component scores (0-100)
        scores = {}

        # 1. Multi-Timeframe Alignment (30% weight)
        mtf_valid, mtf_score, mtf_details = self.check_mtf_alignment(symbol, direction, trading_timeframe)
        scores['mtf_alignment'] = mtf_score
        validation_details['mtf'] = mtf_details

        # 2. Momentum Confluence (25% weight)
        momentum_valid, momentum_score, momentum_details = self.check_momentum_confluence(symbol, direction)
        scores['momentum_confluence'] = momentum_score
        validation_details['momentum'] = momentum_details

        # 3. Volume Confirmation (20% weight)
        volume_valid, volume_score, volume_details = self.check_volume_confirmation(symbol, direction)
        scores['volume_confirmation'] = volume_score
        validation_details['volume'] = volume_details

        # 4. Trend Strength (15% weight)
        trend_valid, trend_score, trend_details = self.check_trend_strength(symbol, direction)
        scores['trend_strength'] = trend_score
        validation_details['trend'] = trend_details

        # 5. Model Confidence (8% weight)
        model_score = min(confidence * 100, 100)  # Convert to 0-100 scale
        scores['model_confidence'] = model_score

        # 6. Fibonacci Alignment (12% weight) ✨
        if self.fibonacci_enabled:
            fib_valid, fib_score, fib_details = self.check_fibonacci_alignment(symbol, direction)
            scores['fibonacci_alignment'] = fib_score
            validation_details['fibonacci'] = fib_details
        else:
            scores['fibonacci_alignment'] = 50  # Neutral if disabled
            validation_details['fibonacci'] = {'disabled': True}

        # 7. Smart Money Concepts (8% weight) ✨
        if self.smc_enabled:
            smc_valid, smc_score, smc_details = self.check_smc_confluence(symbol, direction)
            scores['smc_confluence'] = smc_score
            validation_details['smc'] = smc_details
        else:
            scores['smc_confluence'] = 50  # Neutral if disabled
            validation_details['smc'] = {'disabled': True}

        # Calculate weighted confirmation score
        confirmation_score = self.calculate_confirmation_score(scores)

        validation_details['scores'] = scores
        validation_details['confirmation_score'] = confirmation_score
        validation_details['threshold'] = self.min_confirmation_score

        # Determine if signal is valid
        is_valid = confirmation_score >= self.min_confirmation_score

        if is_valid:
            self.logger.info(f"✅ Signal CONFIRMED: {symbol} {direction} (score: {confirmation_score:.1f}/100)")
        else:
            self.logger.warning(f"❌ Signal REJECTED: {symbol} {direction} (score: {confirmation_score:.1f}/100, needed: {self.min_confirmation_score})")

        return is_valid, confirmation_score, validation_details

    def check_mtf_alignment(self, symbol: str, direction: str,
                           base_timeframe: str = 'H1') -> Tuple[bool, float, Dict]:
        """
        Check multi-timeframe alignment using existing MTFAnalyzer.

        Returns:
            (is_valid, score, details)
        """
        try:
            # Get MTF features (leverages existing code!)
            mtf_features = self.mtf_analyzer.get_mtf_features(symbol, base_timeframe)

            if not mtf_features:
                return False, 0, {'error': 'No MTF data available'}

            # Check if trade should be taken based on MTF
            should_trade, reason = self.mtf_analyzer.should_trade_with_mtf(mtf_features, direction)

            # Calculate alignment score
            trend_alignment = mtf_features.get('trend_alignment', 0)
            trend_strength = mtf_features.get('trend_strength', 0)
            momentum_alignment = mtf_features.get('momentum_alignment', 0)

            # Score components
            alignment_score = trend_alignment * 40  # 40 points for full alignment
            strength_score = trend_strength * 30    # 30 points for trend strength
            momentum_score = (abs(momentum_alignment) * 30) if np.sign(momentum_alignment) == (1 if direction == 'BUY' else -1) else 0

            total_score = alignment_score + strength_score + momentum_score

            details = {
                'should_trade': should_trade,
                'reason': reason,
                'trend_alignment': trend_alignment,
                'trend_strength': trend_strength,
                'momentum_alignment': momentum_alignment,
                'score': total_score
            }

            return should_trade, total_score, details

        except Exception as e:
            self.logger.error(f"Error in MTF validation: {e}")
            return False, 0, {'error': str(e)}

    def check_momentum_confluence(self, symbol: str, direction: str) -> Tuple[bool, float, Dict]:
        """
        Validate signal with RSI, MACD, Stochastic alignment.

        Returns:
            (is_valid, score, details)
        """
        if not TALIB_AVAILABLE:
            return True, 50, {'note': 'TA-Lib not available, skipping momentum check'}

        try:
            # Fetch recent data from bridge
            response = requests.get(
                f"{self.bridge_url}/indicators/momentum",
                params={'symbol': symbol},
                timeout=5
            )

            if response.status_code != 200:
                # Fallback: fetch from database
                return self._momentum_from_db(symbol, direction)

            data = response.json()

            # RSI check (30-70 range, direction aligned)
            rsi = data.get('rsi', 50)
            rsi_aligned = (direction == 'BUY' and 30 < rsi < 70 and rsi > 50) or \
                         (direction == 'SELL' and 30 < rsi < 70 and rsi < 50)
            rsi_score = 33 if rsi_aligned else 0

            # MACD check (histogram direction)
            macd_hist = data.get('macd_hist', 0)
            macd_aligned = (direction == 'BUY' and macd_hist > 0) or \
                          (direction == 'SELL' and macd_hist < 0)
            macd_score = 34 if macd_aligned else 0

            # Stochastic check (K and D position)
            stoch_k = data.get('stoch_k', 50)
            stoch_aligned = (direction == 'BUY' and 20 < stoch_k < 80 and stoch_k > 50) or \
                           (direction == 'SELL' and 20 < stoch_k < 80 and stoch_k < 50)
            stoch_score = 33 if stoch_aligned else 0

            total_score = rsi_score + macd_score + stoch_score
            is_valid = total_score >= 33  # At least 1 indicator must align

            details = {
                'rsi': rsi,
                'rsi_aligned': rsi_aligned,
                'macd_hist': macd_hist,
                'macd_aligned': macd_aligned,
                'stoch_k': stoch_k,
                'stoch_aligned': stoch_aligned,
                'score': total_score,
                'aligned_count': sum([rsi_aligned, macd_aligned, stoch_aligned])
            }

            return is_valid, total_score, details

        except Exception as e:
            self.logger.error(f"Error in momentum validation: {e}")
            return True, 50, {'error': str(e), 'note': 'Defaulting to neutral'}

    def _momentum_from_db(self, symbol: str, direction: str) -> Tuple[bool, float, Dict]:
        """Fallback: calculate momentum from database data."""
        try:
            query = """
                SELECT * FROM market_data
                WHERE symbol = ? AND timeframe = 'H1'
                ORDER BY timestamp DESC
                LIMIT 100
            """
            with self.db.get_connection() as conn:
                df = pd.read_sql_query(query, conn, params=(symbol,))

            if len(df) < 50:
                return True, 50, {'note': 'Insufficient data'}

            df = df.sort_values('timestamp')
            close = df['close'].astype('float64').values
            high = df['high'].astype('float64').values
            low = df['low'].astype('float64').values

            # Calculate indicators
            rsi = talib.RSI(close, timeperiod=14)[-1]
            macd, signal, hist = talib.MACD(close)
            macd_hist = hist[-1]
            stoch_k, _ = talib.STOCH(high, low, close)
            stoch_k_val = stoch_k[-1]

            # Score
            rsi_aligned = (direction == 'BUY' and 30 < rsi < 70 and rsi > 50) or \
                         (direction == 'SELL' and 30 < rsi < 70 and rsi < 50)
            macd_aligned = (direction == 'BUY' and macd_hist > 0) or \
                          (direction == 'SELL' and macd_hist < 0)
            stoch_aligned = (direction == 'BUY' and stoch_k_val > 50) or \
                           (direction == 'SELL' and stoch_k_val < 50)

            score = sum([rsi_aligned, macd_aligned, stoch_aligned]) * 33

            return score >= 33, score, {
                'rsi': rsi, 'macd_hist': macd_hist, 'stoch_k': stoch_k_val,
                'aligned_count': sum([rsi_aligned, macd_aligned, stoch_aligned])
            }

        except Exception as e:
            self.logger.error(f"Error in DB momentum calc: {e}")
            return True, 50, {'error': str(e)}

    def check_volume_confirmation(self, symbol: str, direction: str) -> Tuple[bool, float, Dict]:
        """
        Verify volume supports the price movement.

        Returns:
            (is_valid, score, details)
        """
        try:
            # Fetch volume data from database
            query = """
                SELECT tick_volume, close, timestamp FROM market_data
                WHERE symbol = ? AND timeframe = 'H1'
                ORDER BY timestamp DESC
                LIMIT 20
            """
            with self.db.get_connection() as conn:
                df = pd.read_sql_query(query, conn, params=(symbol,))

            if len(df) < 10:
                return True, 50, {'note': 'Insufficient volume data'}

            # Data already sorted by timestamp DESC from query
            # df = df.sort_values('timestamp', ascending=False)

            # Volume ratio (current vs average)
            current_volume = df['tick_volume'].iloc[0]
            avg_volume = df['tick_volume'].iloc[1:11].mean()

            volume_ratio = current_volume / avg_volume if avg_volume > 0 else 1.0

            # Score based on volume ratio
            min_ratio = self.validation_config.get('volume_validation', {}).get('min_volume_ratio', 1.2)

            if volume_ratio >= min_ratio:
                score = 100
            elif volume_ratio >= min_ratio * 0.8:
                score = 70
            else:
                score = 40

            is_valid = volume_ratio >= (min_ratio * 0.8)  # 80% of threshold

            details = {
                'current_volume': float(current_volume),
                'avg_volume': float(avg_volume),
                'volume_ratio': float(volume_ratio),
                'threshold': min_ratio,
                'score': score
            }

            return is_valid, score, details

        except Exception as e:
            self.logger.error(f"Error in volume validation: {e}")
            return True, 50, {'error': str(e)}

    def check_trend_strength(self, symbol: str, direction: str) -> Tuple[bool, float, Dict]:
        """
        Validate trend strength using ADX and DI.

        Returns:
            (is_valid, score, details)
        """
        if not TALIB_AVAILABLE:
            return True, 50, {'note': 'TA-Lib not available'}

        try:
            # Fetch data from database
            query = """
                SELECT high, low, close, timestamp FROM market_data
                WHERE symbol = ? AND timeframe = 'H1'
                ORDER BY timestamp DESC
                LIMIT 50
            """
            with self.db.get_connection() as conn:
                df = pd.read_sql_query(query, conn, params=(symbol,))

            if len(df) < 30:
                return True, 50, {'note': 'Insufficient data'}

            df = df.sort_values('timestamp')
            high = df['high'].astype('float64').values
            low = df['low'].astype('float64').values
            close = df['close'].astype('float64').values

            # Calculate ADX and DI
            adx = talib.ADX(high, low, close, timeperiod=14)[-1]
            plus_di = talib.PLUS_DI(high, low, close, timeperiod=14)[-1]
            minus_di = talib.MINUS_DI(high, low, close, timeperiod=14)[-1]

            # Check trend strength and direction
            min_adx = self.validation_config.get('trend_validation', {}).get('min_adx', 20)

            # ADX score
            if adx >= min_adx:
                adx_score = min(100, (adx / min_adx) * 50)
            else:
                adx_score = (adx / min_adx) * 50

            # DI alignment score
            require_di = self.validation_config.get('trend_validation', {}).get('require_di_alignment', True)

            if require_di:
                di_aligned = (direction == 'BUY' and plus_di > minus_di) or \
                            (direction == 'SELL' and minus_di > plus_di)
                di_score = 50 if di_aligned else 0
            else:
                di_score = 50  # Don't penalize if not required

            total_score = adx_score + di_score
            is_valid = adx >= (min_adx * 0.8) and (not require_di or di_aligned)

            details = {
                'adx': float(adx),
                'plus_di': float(plus_di),
                'minus_di': float(minus_di),
                'min_adx': min_adx,
                'di_aligned': di_aligned if require_di else None,
                'score': total_score
            }

            return is_valid, total_score, details

        except Exception as e:
            self.logger.error(f"Error in trend validation: {e}")
            return True, 50, {'error': str(e)}

    def check_fibonacci_alignment(self, symbol: str, direction: str) -> Tuple[bool, float, Dict]:
        """
        Validate signal with Fibonacci retracements, OTE zones, and confluence.

        Scoring breakdown:
        - OTE zone alignment: up to 40 points
        - Fibonacci confluence: up to 30 points
        - Near key retracement: up to 20 points
        - Swing structure quality: up to 10 points

        Returns:
            (is_valid, score, details)
        """
        try:
            # Fetch price data from database
            query = """
                SELECT open, high, low, close, timestamp FROM market_data
                WHERE symbol = ? AND timeframe = 'H1'
                ORDER BY timestamp DESC
                LIMIT 100
            """
            with self.db.get_connection() as conn:
                df = pd.read_sql_query(query, conn, params=(symbol,))

            if len(df) < 50:
                return True, 50, {'note': 'Insufficient data for Fibonacci analysis'}

            # Sort by timestamp ascending
            df = df.sort_values('timestamp')
            current_price = df['close'].iloc[-1]

            # Score Fibonacci alignment
            fib_score, fib_details = self.fibonacci_analyzer.score_fibonacci_alignment(
                direction, current_price, df
            )

            # Consider valid if score >= 40 (at least OTE zone or good confluence)
            is_valid = fib_score >= 40

            details = {
                'score': fib_score,
                'current_price': float(current_price),
                **fib_details
            }

            return is_valid, fib_score, details

        except Exception as e:
            self.logger.error(f"Error in Fibonacci validation: {e}")
            return True, 50, {'error': str(e), 'note': 'Defaulting to neutral'}

    def check_smc_confluence(self, symbol: str, direction: str) -> Tuple[bool, float, Dict]:
        """
        Validate signal with Smart Money Concepts (Order Blocks, FVG, BOS, CHoCH).

        Scoring breakdown:
        - Order Block alignment: up to 30 points
        - Fair Value Gap: up to 25 points
        - Break of Structure: up to 20 points
        - Premium/Discount zone: up to 15 points
        - Change of Character: up to 10 points

        Returns:
            (is_valid, score, details)
        """
        try:
            # Fetch price data from database
            query = """
                SELECT open, high, low, close, timestamp FROM market_data
                WHERE symbol = ? AND timeframe = 'H1'
                ORDER BY timestamp DESC
                LIMIT 100
            """
            with self.db.get_connection() as conn:
                df = pd.read_sql_query(query, conn, params=(symbol,))

            if len(df) < 50:
                return True, 50, {'note': 'Insufficient data for SMC analysis'}

            # Sort by timestamp ascending
            df = df.sort_values('timestamp')
            current_price = df['close'].iloc[-1]

            # Score SMC alignment
            smc_score, smc_details = self.smc_analyzer.score_smc_alignment(
                direction, current_price, df
            )

            # Consider valid if score >= 40 (strong SMC confluence)
            is_valid = smc_score >= 40

            details = {
                'score': smc_score,
                'current_price': float(current_price),
                **smc_details
            }

            return is_valid, smc_score, details

        except Exception as e:
            self.logger.error(f"Error in SMC validation: {e}")
            return True, 50, {'error': str(e), 'note': 'Defaulting to neutral'}

    def calculate_confirmation_score(self, scores: Dict[str, float]) -> float:
        """
        Aggregate individual validation scores into overall confidence.

        Score components with weights (7 factors):
        - MTF alignment: 25%
        - Momentum confluence: 20%
        - Volume confirmation: 15%
        - Trend strength: 12%
        - Fibonacci alignment: 12% ✨
        - Model confidence: 8%
        - Smart Money Concepts: 8% ✨

        Args:
            scores: Dictionary of component scores (0-100)

        Returns:
            Overall confirmation score (0-100)
        """
        weighted_score = 0.0
        total_weight = 0.0

        for component, weight in self.weights.items():
            if component in scores:
                weighted_score += (scores[component] * weight / 100)
                total_weight += weight

        # Normalize to 0-100 scale
        final_score = (weighted_score / total_weight * 100) if total_weight > 0 else 0

        return min(100.0, max(0.0, final_score))
