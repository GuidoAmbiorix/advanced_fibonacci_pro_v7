"""
============================================================================
Volatility Analyzer v1.0
============================================================================
Market regime detection using ADX + ATR.
Prevents trading in "garbage conditions" (low volatility chop).

Regimes:
- LOW: ADX < threshold, avoid trading
- NORMAL: ADX >= threshold, stable conditions
- HIGH: ADX > 40, strong trend
- EXTREME: ADX > 50 + ATR spike, volatile breakout
"""

import pandas as pd
import numpy as np
from typing import Dict, Tuple
from loguru import logger
from ta.trend import ADXIndicator
from ta.volatility import AverageTrueRange


class VolatilityAnalyzer:
    """
    Market-aware filter for institutional trading.
    Uses ADX for trend strength and ATR for volatility context.
    """
    
    # Regime definitions
    REGIMES = {
        'LOW': {'min_adx': 0, 'max_adx': 20, 'tradeable': False},
        'NORMAL': {'min_adx': 20, 'max_adx': 40, 'tradeable': True},
        'HIGH': {'min_adx': 40, 'max_adx': 50, 'tradeable': True},
        'EXTREME': {'min_adx': 50, 'max_adx': 100, 'tradeable': True}
    }
    
    def __init__(self, config: Dict):
        """
        Initialize with slot configuration.
        
        Args:
            config: Slot config dict with:
                - enable_volatility_filter: bool
                - adx_period: int (default 14)
                - adx_threshold: float (default 25.0)
                - volatility_regime: str (allowed regimes)
        """
        self.enabled = config.get('enable_volatility_filter', True)
        self.adx_period = config.get('adx_period', 14)
        self.adx_threshold = config.get('adx_threshold', 25.0)
        self.atr_period = config.get('atr_period', 14)
        
        # Parse allowed regimes (comma-separated or single)
        allowed = config.get('volatility_regime', 'NORMAL,HIGH')
        if isinstance(allowed, str):
            self.allowed_regimes = [r.strip().upper() for r in allowed.split(',')]
        else:
            self.allowed_regimes = ['NORMAL', 'HIGH']
    
    def calculate_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Add ADX and ATR indicators to dataframe.
        Returns the df with new columns.
        """
        if len(df) < self.adx_period + 10:
            return df
        
        # ADX Indicator
        adx_ind = ADXIndicator(
            high=df['high'], 
            low=df['low'], 
            close=df['close'], 
            window=self.adx_period
        )
        df['adx'] = adx_ind.adx()
        df['adx_pos'] = adx_ind.adx_pos()  # +DI
        df['adx_neg'] = adx_ind.adx_neg()  # -DI
        
        # ATR for volatility context
        if 'atr' not in df.columns:
            atr_ind = AverageTrueRange(
                high=df['high'], 
                low=df['low'], 
                close=df['close'],
                window=self.atr_period
            )
            df['atr'] = atr_ind.average_true_range()
        
        # ATR percentile (for regime detection)
        df['atr_percentile'] = df['atr'].rolling(50).apply(
            lambda x: pd.Series(x).rank(pct=True).iloc[-1] * 100 if len(x) > 0 else 50,
            raw=False
        )
        
        return df
    
    def get_regime(self, df: pd.DataFrame) -> Dict:
        """
        Detect current market regime.
        
        Returns:
            Dict with:
                - regime: str (LOW, NORMAL, HIGH, EXTREME)
                - adx: float (current ADX value)
                - atr_percentile: float (0-100)
                - tradeable: bool
                - details: str (human-readable description)
        """
        if not self.enabled:
            return {
                'regime': 'NORMAL',
                'adx': 0,
                'atr_percentile': 50,
                'tradeable': True,
                'details': 'Volatility filter disabled'
            }
        
        # Ensure indicators are calculated
        if 'adx' not in df.columns:
            df = self.calculate_indicators(df)
        
        if 'adx' not in df.columns or len(df) < 2:
            return {
                'regime': 'NORMAL',
                'adx': 0,
                'atr_percentile': 50,
                'tradeable': True,
                'details': 'Insufficient data for ADX'
            }
        
        current_adx = df['adx'].iloc[-1]
        atr_pct = df['atr_percentile'].iloc[-1] if 'atr_percentile' in df.columns else 50
        
        # Handle NaN
        if pd.isna(current_adx):
            current_adx = 0
        if pd.isna(atr_pct):
            atr_pct = 50
        
        # Determine regime
        if current_adx >= 50 and atr_pct > 80:
            regime = 'EXTREME'
        elif current_adx >= 40:
            regime = 'HIGH'
        elif current_adx >= self.adx_threshold:
            regime = 'NORMAL'
        else:
            regime = 'LOW'
        
        # Check if tradeable based on allowed regimes
        tradeable = regime in self.allowed_regimes
        
        return {
            'regime': regime,
            'adx': round(float(current_adx), 2),
            'atr_percentile': round(float(atr_pct), 1),
            'tradeable': tradeable,
            'details': f"ADX={current_adx:.1f}, ATR%={atr_pct:.0f}, Regime={regime}"
        }
    
    def should_trade(self, df: pd.DataFrame, direction: str = None) -> Tuple[bool, str]:
        """
        Gating function for the engine.
        
        Args:
            df: OHLCV DataFrame
            direction: 'BUY' or 'SELL' (optional, for future directional filters)
        
        Returns:
            Tuple of (can_trade: bool, reason: str)
        """
        if not self.enabled:
            return True, "Volatility filter disabled"
        
        regime_info = self.get_regime(df)
        
        if not regime_info['tradeable']:
            reason = f"⏸️ LOW VOLATILITY: {regime_info['details']} — Regime '{regime_info['regime']}' not in allowed list"
            logger.warning(reason)
            return False, reason
        
        return True, f"✅ Regime OK: {regime_info['details']}"
    
    def get_trend_direction(self, df: pd.DataFrame) -> str:
        """
        Use +DI/-DI to determine trend direction.
        
        Returns:
            'BULLISH', 'BEARISH', or 'NEUTRAL'
        """
        if 'adx_pos' not in df.columns or 'adx_neg' not in df.columns:
            df = self.calculate_indicators(df)
        
        if 'adx_pos' not in df.columns:
            return 'NEUTRAL'
        
        di_plus = df['adx_pos'].iloc[-1]
        di_minus = df['adx_neg'].iloc[-1]
        
        if pd.isna(di_plus) or pd.isna(di_minus):
            return 'NEUTRAL'
        
        if di_plus > di_minus + 5:  # +5 buffer for noise
            return 'BULLISH'
        elif di_minus > di_plus + 5:
            return 'BEARISH'
        else:
            return 'NEUTRAL'
