"""
============================================================================
Confluence v2.0 - Weighted Multi-Timeframe Bias Scoring
============================================================================
Institutional-grade confluence system using weighted timeframe bias.

Instead of boolean filters (trade/no-trade), this system calculates
a continuous score from -1.0 (strong bearish) to +1.0 (strong bullish).

Formula:
    Score = H1_bias * W_H1 + H4_bias * W_H4 + D1_bias * W_D1

Default weights:
    H1: 0.5 (most responsive)
    H4: 0.3 (medium-term context)
    D1: 0.2 (macro trend)
"""

import pandas as pd
import numpy as np
from typing import Dict, Tuple, Optional
from loguru import logger
from ta.trend import EMAIndicator


class ConfluenceV2:
    """
    Weighted multi-TF bias scoring for institutional trading.
    Replaces boolean confirmation with continuous score.
    """
    
    def __init__(self, config: Dict):
        """
        Initialize with slot configuration.
        
        Args:
            config: Slot config dict with:
                - confluence_h1_weight: float (default 0.5)
                - confluence_h4_weight: float (default 0.3)
                - confluence_d1_weight: float (default 0.2)
                - min_confluence_bias: float (default 0.3)
        """
        self.h1_weight = config.get('confluence_h1_weight', 0.5)
        self.h4_weight = config.get('confluence_h4_weight', 0.3)
        self.d1_weight = config.get('confluence_d1_weight', 0.2)
        self.min_bias = config.get('min_confluence_bias', 0.3)
        
        # EMA periods for bias detection
        self.ema_fast = 20
        self.ema_slow = 50
        self.ema_trend = 200
    
    def _calculate_bias(self, df: pd.DataFrame) -> float:
        """
        Calculate bias for a single timeframe.
        
        Returns:
            Float from -1.0 to +1.0:
            - Positive = Bullish
            - Negative = Bearish
            - Near zero = Neutral/Ranging
        """
        if df is None or len(df) < 200:
            return 0.0
        
        # Calculate EMAs
        df = df.copy()
        df['ema_fast'] = EMAIndicator(close=df['close'], window=self.ema_fast).ema_indicator()
        df['ema_slow'] = EMAIndicator(close=df['close'], window=self.ema_slow).ema_indicator()
        df['ema_trend'] = EMAIndicator(close=df['close'], window=self.ema_trend).ema_indicator()
        
        current = df.iloc[-1]
        
        # Get values
        price = current['close']
        ema_fast = current['ema_fast']
        ema_slow = current['ema_slow']
        ema_trend = current['ema_trend']
        
        # Handle NaN
        if pd.isna(ema_fast) or pd.isna(ema_slow) or pd.isna(ema_trend):
            return 0.0
        
        # Point-based scoring
        score = 0.0
        
        # Price vs EMA200 (strongest signal)
        if price > ema_trend:
            score += 0.4
        elif price < ema_trend:
            score -= 0.4
        
        # EMA alignment (EMA20 > EMA50 = bullish)
        if ema_fast > ema_slow:
            score += 0.3
        elif ema_fast < ema_slow:
            score -= 0.3
        
        # EMA50 vs EMA200 (trend direction)
        if ema_slow > ema_trend:
            score += 0.3
        elif ema_slow < ema_trend:
            score -= 0.3
        
        # Clamp to [-1, 1]
        return max(-1.0, min(1.0, score))
    
    def calculate_confluence_score(
        self, 
        df_h1: Optional[pd.DataFrame] = None,
        df_h4: Optional[pd.DataFrame] = None,
        df_d1: Optional[pd.DataFrame] = None
    ) -> Dict:
        """
        Calculate combined confluence score from all timeframes.
        
        Returns:
            Dict with:
                - score: float (-1.0 to 1.0)
                - h1_bias: float
                - h4_bias: float
                - d1_bias: float
                - direction: str ('BULLISH', 'BEARISH', 'NEUTRAL')
                - tradeable: bool
                - details: str
        """
        h1_bias = self._calculate_bias(df_h1) if df_h1 is not None else 0.0
        h4_bias = self._calculate_bias(df_h4) if df_h4 is not None else 0.0
        d1_bias = self._calculate_bias(df_d1) if df_d1 is not None else 0.0
        
        # Weighted score
        total_weight = self.h1_weight + self.h4_weight + self.d1_weight
        if total_weight == 0:
            total_weight = 1.0
        
        # Normalize weights if they don't sum to 1
        w_h1 = self.h1_weight / total_weight
        w_h4 = self.h4_weight / total_weight
        w_d1 = self.d1_weight / total_weight
        
        combined_score = (h1_bias * w_h1) + (h4_bias * w_h4) + (d1_bias * w_d1)
        
        # Determine direction
        if combined_score >= self.min_bias:
            direction = 'BULLISH'
        elif combined_score <= -self.min_bias:
            direction = 'BEARISH'
        else:
            direction = 'NEUTRAL'
        
        # Check if tradeable
        tradeable = abs(combined_score) >= self.min_bias
        
        return {
            'score': round(combined_score, 3),
            'h1_bias': round(h1_bias, 3),
            'h4_bias': round(h4_bias, 3),
            'd1_bias': round(d1_bias, 3),
            'direction': direction,
            'tradeable': tradeable,
            'details': f"Score={combined_score:.2f} (H1:{h1_bias:.2f}×{w_h1:.1f} + H4:{h4_bias:.2f}×{w_h4:.1f} + D1:{d1_bias:.2f}×{w_d1:.1f})"
        }
    
    def should_trade(
        self, 
        signal_direction: str,
        df_h1: Optional[pd.DataFrame] = None,
        df_h4: Optional[pd.DataFrame] = None,
        df_d1: Optional[pd.DataFrame] = None
    ) -> Tuple[bool, str, Dict]:
        """
        Gating function for the engine.
        
        Args:
            signal_direction: 'BUY' or 'SELL'
            df_h1, df_h4, df_d1: Higher TF dataframes
        
        Returns:
            Tuple of (can_trade: bool, reason: str, confluence_data: Dict)
        """
        confluence = self.calculate_confluence_score(df_h1, df_h4, df_d1)
        
        # Check alignment with signal direction
        if signal_direction == 'BUY':
            if confluence['score'] < 0:
                reason = f"❌ Confluence BEARISH for BUY: {confluence['details']}"
                return False, reason, confluence
            if not confluence['tradeable']:
                reason = f"⏸️ Confluence too weak for BUY: {confluence['details']}"
                return False, reason, confluence
                
        elif signal_direction == 'SELL':
            if confluence['score'] > 0:
                reason = f"❌ Confluence BULLISH for SELL: {confluence['details']}"
                return False, reason, confluence
            if not confluence['tradeable']:
                reason = f"⏸️ Confluence too weak for SELL: {confluence['details']}"
                return False, reason, confluence
        
        return True, f"✅ Confluence aligned: {confluence['details']}", confluence
    
    def boost_score(self, base_score: int, confluence: Dict) -> int:
        """
        Boost or penalize signal confluence score based on MTF alignment.
        
        Args:
            base_score: Original signal score (e.g., 85)
            confluence: Result from calculate_confluence_score()
        
        Returns:
            Adjusted score (capped at 100)
        """
        mtf_score = abs(confluence['score'])
        
        # Strong alignment bonus
        if mtf_score >= 0.7:
            boost = 10
        elif mtf_score >= 0.5:
            boost = 5
        elif mtf_score >= 0.3:
            boost = 2
        else:
            boost = 0
        
        return min(100, base_score + boost)
