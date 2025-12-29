"""
Market Regime Detector

Detects current market regime to adapt trading strategies accordingly.
Based on concepts from "Quantitative Trading" by Dr. Ernest P. Chan.

Regime Types:
- TRENDING (Momentum): Market shows persistent directional movement
- MEAN_REVERTING: Market oscillates around a mean value
- NEUTRAL: No clear regime detected

Volatility Regimes:
- HIGH: Above-average volatility (2+ standard deviations)
- NORMAL: Average volatility
- LOW: Below-average volatility
"""

import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
from loguru import logger
from datetime import datetime


class MarketRegime(str, Enum):
    """Market regime types"""
    TRENDING_BULL = "TRENDING_BULL"
    TRENDING_BEAR = "TRENDING_BEAR"
    MEAN_REVERTING = "MEAN_REVERTING"
    NEUTRAL = "NEUTRAL"


class VolatilityRegime(str, Enum):
    """Volatility regime types"""
    HIGH = "HIGH"
    NORMAL = "NORMAL"
    LOW = "LOW"


@dataclass
class RegimeResult:
    """Result of regime detection"""
    regime: MarketRegime
    volatility: VolatilityRegime
    regime_confidence: float          # 0-100%
    volatility_percentile: float      # Current volatility percentile
    trend_strength: float             # -1 (strong bear) to +1 (strong bull)
    mean_reversion_score: float       # 0-1, higher = more mean-reverting
    regime_duration_bars: int         # How long current regime has lasted
    hurst_exponent: Optional[float]   # H < 0.5 = mean-reverting, H > 0.5 = trending
    recommendation: str               # Trading recommendation based on regime
    analysis_details: Dict            # Additional analysis data


class RegimeDetector:
    """
    Detect market regimes using multiple indicators.
    
    Uses:
    1. Hurst Exponent: H < 0.5 = mean reverting, H > 0.5 = trending
    2. ADX (Average Directional Index): Trend strength
    3. Variance Ratio Test: Mean reversion detection
    4. GARCH volatility: Volatility regime
    """
    
    # Default lookback periods
    DEFAULT_LOOKBACK = 100
    VOLATILITY_LOOKBACK = 20
    TREND_LOOKBACK = 14
    
    @staticmethod
    def detect_regime(
        prices: pd.Series,
        high: Optional[pd.Series] = None,
        low: Optional[pd.Series] = None,
        lookback: int = DEFAULT_LOOKBACK
    ) -> RegimeResult:
        """
        Main regime detection function.
        
        Args:
            prices: Series of closing prices
            high: Series of high prices (for ATR/ADX)
            low: Series of low prices (for ATR/ADX)
            lookback: Number of bars to analyze
            
        Returns:
            RegimeResult with detected regime and analysis
        """
        if len(prices) < lookback:
            lookback = len(prices)
        
        if lookback < 20:
            return RegimeResult(
                regime=MarketRegime.NEUTRAL,
                volatility=VolatilityRegime.NORMAL,
                regime_confidence=0.0,
                volatility_percentile=50.0,
                trend_strength=0.0,
                mean_reversion_score=0.0,
                regime_duration_bars=0,
                hurst_exponent=None,
                recommendation="Insufficient data for regime detection",
                analysis_details={}
            )
        
        # Take recent data
        recent_prices = prices.tail(lookback).values
        
        # Calculate returns
        returns = np.diff(np.log(recent_prices))
        
        # 1. Calculate Hurst Exponent
        hurst = RegimeDetector._calculate_hurst_exponent(recent_prices)
        
        # 2. Calculate trend strength (simplified ADX-like metric)
        trend_strength = RegimeDetector._calculate_trend_strength(recent_prices)
        
        # 3. Calculate mean reversion score (variance ratio)
        mr_score = RegimeDetector._calculate_mean_reversion_score(returns)
        
        # 4. Calculate volatility regime
        volatility_regime, vol_percentile = RegimeDetector._calculate_volatility_regime(returns)
        
        # 5. Determine regime based on multiple signals
        regime, confidence = RegimeDetector._determine_regime(
            hurst=hurst,
            trend_strength=trend_strength,
            mr_score=mr_score,
            returns=returns
        )
        
        # 6. Calculate regime duration
        regime_duration = RegimeDetector._calculate_regime_duration(
            prices=recent_prices,
            current_regime=regime
        )
        
        # 7. Generate recommendation
        recommendation = RegimeDetector._generate_recommendation(
            regime=regime,
            volatility=volatility_regime,
            trend_strength=trend_strength
        )
        
        return RegimeResult(
            regime=regime,
            volatility=volatility_regime,
            regime_confidence=round(confidence, 2),
            volatility_percentile=round(vol_percentile, 2),
            trend_strength=round(trend_strength, 4),
            mean_reversion_score=round(mr_score, 4),
            regime_duration_bars=regime_duration,
            hurst_exponent=round(hurst, 4) if hurst else None,
            recommendation=recommendation,
            analysis_details={
                "hurst_interpretation": "trending" if (hurst and hurst > 0.5) else "mean-reverting",
                "volatility_state": volatility_regime.value,
                "lookback_used": lookback,
                "current_price": float(recent_prices[-1]),
                "price_change_pct": float((recent_prices[-1] / recent_prices[0] - 1) * 100)
            }
        )
    
    @staticmethod
    def _calculate_hurst_exponent(prices: np.ndarray, max_lag: int = 20) -> Optional[float]:
        """
        Calculate Hurst Exponent using R/S analysis.
        
        H < 0.5: Mean-reverting (anti-persistent)
        H = 0.5: Random walk
        H > 0.5: Trending (persistent)
        """
        try:
            n = len(prices)
            if n < max_lag * 2:
                return None
            
            lags = range(2, max_lag)
            rs_list = []
            
            for lag in lags:
                # Split into subseries
                subseries_count = n // lag
                rs_values = []
                
                for i in range(subseries_count):
                    subseries = prices[i * lag:(i + 1) * lag]
                    
                    # Calculate returns for subseries
                    returns = np.diff(np.log(subseries))
                    if len(returns) < 2:
                        continue
                    
                    # Mean-adjusted returns
                    mean_return = np.mean(returns)
                    adjusted_returns = returns - mean_return
                    
                    # Cumulative deviation
                    cumsum = np.cumsum(adjusted_returns)
                    
                    # Range
                    r = np.max(cumsum) - np.min(cumsum)
                    
                    # Standard deviation
                    s = np.std(returns, ddof=1)
                    
                    if s > 0:
                        rs_values.append(r / s)
                
                if rs_values:
                    rs_list.append(np.mean(rs_values))
            
            if len(rs_list) < 5:
                return None
            
            # Log-log regression
            log_lags = np.log(list(lags)[:len(rs_list)])
            log_rs = np.log(rs_list)
            
            # Fit line: log(R/S) = H * log(lag) + c
            slope, _ = np.polyfit(log_lags, log_rs, 1)
            
            return max(0.0, min(1.0, slope))  # Clamp between 0 and 1
            
        except Exception as e:
            logger.debug(f"Hurst calculation error: {e}")
            return None
    
    @staticmethod
    def _calculate_trend_strength(prices: np.ndarray, period: int = 14) -> float:
        """
        Calculate trend strength as a value between -1 (strong bear) and +1 (strong bull).
        
        Uses a simplified ADX-like calculation.
        """
        if len(prices) < period + 1:
            return 0.0
        
        # Calculate directional movement
        price_changes = np.diff(prices)
        
        # Positive and negative moves
        pos_moves = np.where(price_changes > 0, price_changes, 0)
        neg_moves = np.where(price_changes < 0, -price_changes, 0)
        
        # Smooth with EMA
        def ema(data, period):
            alpha = 2 / (period + 1)
            result = np.zeros_like(data)
            result[0] = data[0]
            for i in range(1, len(data)):
                result[i] = alpha * data[i] + (1 - alpha) * result[i-1]
            return result
        
        smoothed_pos = ema(pos_moves, period)
        smoothed_neg = ema(neg_moves, period)
        
        # Calculate DI+ and DI-
        total_move = smoothed_pos + smoothed_neg
        total_move = np.where(total_move == 0, 1, total_move)  # Avoid division by zero
        
        di_plus = smoothed_pos / total_move
        di_minus = smoothed_neg / total_move
        
        # Trend strength: difference between DI+ and DI-
        trend_strength = np.mean(di_plus[-period:]) - np.mean(di_minus[-period:])
        
        return max(-1.0, min(1.0, trend_strength))
    
    @staticmethod
    def _calculate_mean_reversion_score(returns: np.ndarray, lag: int = 2) -> float:
        """
        Calculate mean reversion score using Variance Ratio test.
        
        VR < 1: Mean-reverting
        VR = 1: Random walk
        VR > 1: Trending
        
        Returns a score 0-1 where higher = more mean-reverting.
        """
        if len(returns) < lag * 10:
            return 0.5  # Neutral
        
        # Variance of single-period returns
        var_1 = np.var(returns, ddof=1)
        
        if var_1 == 0:
            return 0.5
        
        # Calculate lag-period returns
        lag_returns = np.array([
            np.sum(returns[i:i+lag]) 
            for i in range(len(returns) - lag + 1)
        ])
        
        # Variance of lag-period returns
        var_lag = np.var(lag_returns, ddof=1)
        
        # Variance ratio
        vr = var_lag / (lag * var_1)
        
        # Convert to mean reversion score
        # VR < 1 means mean-reverting, so score = 1 - VR (clamped)
        if vr < 1:
            # Mean-reverting: score increases as VR decreases
            score = 1 - vr
        else:
            # Trending: score decreases as VR increases
            score = 1 / vr
        
        return max(0.0, min(1.0, score))
    
    @staticmethod
    def _calculate_volatility_regime(
        returns: np.ndarray,
        lookback: int = 20
    ) -> Tuple[VolatilityRegime, float]:
        """
        Determine volatility regime based on historical volatility percentile.
        """
        if len(returns) < lookback * 2:
            return VolatilityRegime.NORMAL, 50.0
        
        # Calculate rolling volatility
        rolling_vol = []
        for i in range(lookback, len(returns) + 1):
            window_returns = returns[i-lookback:i]
            rolling_vol.append(np.std(window_returns, ddof=1))
        
        rolling_vol = np.array(rolling_vol)
        current_vol = rolling_vol[-1]
        
        # Calculate percentile
        percentile = (np.sum(rolling_vol < current_vol) / len(rolling_vol)) * 100
        
        # Determine regime
        if percentile >= 80:
            regime = VolatilityRegime.HIGH
        elif percentile <= 20:
            regime = VolatilityRegime.LOW
        else:
            regime = VolatilityRegime.NORMAL
        
        return regime, percentile
    
    @staticmethod
    def _determine_regime(
        hurst: Optional[float],
        trend_strength: float,
        mr_score: float,
        returns: np.ndarray
    ) -> Tuple[MarketRegime, float]:
        """
        Combine multiple signals to determine the overall market regime.
        """
        # Scoring system
        trending_score = 0
        reverting_score = 0
        
        # Hurst exponent contribution
        if hurst is not None:
            if hurst > 0.55:
                trending_score += (hurst - 0.5) * 2  # Weight trending
            elif hurst < 0.45:
                reverting_score += (0.5 - hurst) * 2  # Weight reverting
        
        # Trend strength contribution
        if abs(trend_strength) > 0.3:
            trending_score += abs(trend_strength)
        else:
            reverting_score += 0.3 - abs(trend_strength)
        
        # Mean reversion score contribution
        if mr_score > 0.6:
            reverting_score += mr_score
        elif mr_score < 0.4:
            trending_score += (1 - mr_score)
        
        # Determine regime
        total_score = trending_score + reverting_score
        if total_score == 0:
            return MarketRegime.NEUTRAL, 50.0
        
        # Calculate confidence
        max_score = max(trending_score, reverting_score)
        confidence = (max_score / total_score) * 100
        
        if trending_score > reverting_score:
            # Trending - determine direction
            if trend_strength > 0:
                return MarketRegime.TRENDING_BULL, confidence
            else:
                return MarketRegime.TRENDING_BEAR, confidence
        elif reverting_score > trending_score:
            return MarketRegime.MEAN_REVERTING, confidence
        else:
            return MarketRegime.NEUTRAL, 50.0
    
    @staticmethod
    def _calculate_regime_duration(prices: np.ndarray, current_regime: MarketRegime) -> int:
        """
        Estimate how long the current regime has been in effect.
        """
        # Simplified: count bars since last significant regime change
        # Using price relative to short-term SMA as proxy
        
        if len(prices) < 20:
            return len(prices)
        
        sma = np.convolve(prices, np.ones(10)/10, mode='valid')
        
        if len(sma) < 5:
            return len(prices)
        
        # Count bars where price has been consistently above/below SMA
        recent_prices = prices[-len(sma):]
        
        if current_regime in [MarketRegime.TRENDING_BULL, MarketRegime.TRENDING_BEAR]:
            # Count consistent trend bars
            if current_regime == MarketRegime.TRENDING_BULL:
                consistent = recent_prices > sma
            else:
                consistent = recent_prices < sma
            
            # Find first False from the end
            duration = 0
            for i in range(len(consistent) - 1, -1, -1):
                if consistent[i]:
                    duration += 1
                else:
                    break
            return duration
        else:
            # Mean-reverting: count oscillations
            crossovers = np.diff((recent_prices > sma).astype(int))
            last_cross = np.where(crossovers != 0)[0]
            
            if len(last_cross) > 0:
                return len(sma) - last_cross[-1] - 1
            return len(sma)
    
    @staticmethod
    def _generate_recommendation(
        regime: MarketRegime,
        volatility: VolatilityRegime,
        trend_strength: float
    ) -> str:
        """
        Generate trading recommendation based on regime.
        """
        recommendations = {
            MarketRegime.TRENDING_BULL: {
                VolatilityRegime.HIGH: "Strong uptrend with high volatility. Use momentum strategies, trail stops aggressively.",
                VolatilityRegime.NORMAL: "Healthy uptrend. Favor buy-the-dip entries and trailing stops.",
                VolatilityRegime.LOW: "Grinding uptrend. Be patient with entries, expect slow moves."
            },
            MarketRegime.TRENDING_BEAR: {
                VolatilityRegime.HIGH: "Strong downtrend with high volatility. Use momentum shorts, manage risk carefully.",
                VolatilityRegime.NORMAL: "Sustained downtrend. Favor sell-the-rally entries.",
                VolatilityRegime.LOW: "Slow bleed lower. Be patient, volatility expansion likely."
            },
            MarketRegime.MEAN_REVERTING: {
                VolatilityRegime.HIGH: "Range-bound with high volatility. Fade extremes, use tight stops.",
                VolatilityRegime.NORMAL: "Classic mean-reversion environment. Buy support, sell resistance.",
                VolatilityRegime.LOW: "Compressed range. Watch for breakout, reduce position size."
            },
            MarketRegime.NEUTRAL: {
                VolatilityRegime.HIGH: "Unclear regime with high volatility. Reduce exposure, wait for clarity.",
                VolatilityRegime.NORMAL: "No clear regime. Trade selectively, use smaller size.",
                VolatilityRegime.LOW: "Low volatility consolidation. Wait for directional move."
            }
        }
        
        return recommendations.get(regime, {}).get(volatility, "Analyze further before trading.")


# Convenience function for API
def detect_market_regime(
    close_prices: List[float],
    high_prices: Optional[List[float]] = None,
    low_prices: Optional[List[float]] = None,
    lookback: int = 100
) -> Dict:
    """
    Convenience function to detect market regime from price lists.
    
    Args:
        close_prices: List of closing prices
        high_prices: Optional list of high prices
        low_prices: Optional list of low prices  
        lookback: Analysis lookback period
        
    Returns:
        Dictionary with regime analysis
    """
    prices = pd.Series(close_prices)
    high = pd.Series(high_prices) if high_prices else None
    low = pd.Series(low_prices) if low_prices else None
    
    result = RegimeDetector.detect_regime(
        prices=prices,
        high=high,
        low=low,
        lookback=lookback
    )
    
    return {
        "regime": result.regime.value,
        "volatility": result.volatility.value,
        "regime_confidence": result.regime_confidence,
        "volatility_percentile": result.volatility_percentile,
        "trend_strength": result.trend_strength,
        "mean_reversion_score": result.mean_reversion_score,
        "regime_duration_bars": result.regime_duration_bars,
        "hurst_exponent": result.hurst_exponent,
        "recommendation": result.recommendation,
        "analysis_details": result.analysis_details
    }
