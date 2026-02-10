"""
Multi-Timeframe Analysis Module

Extracts features from multiple timeframes to capture:
- Higher timeframe trend direction
- Key support/resistance levels
- Momentum alignment across timeframes
- Volatility context from higher TFs
"""

import pandas as pd
import numpy as np
from typing import Dict, Optional, Tuple
import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))

try:
    import talib
    TALIB_AVAILABLE = True
except ImportError:
    TALIB_AVAILABLE = False


class MTFAnalyzer:
    """
    Multi-Timeframe Analysis System
    
    Analyzes multiple timeframes to provide confluence signals.
    """
    
    # Timeframe hierarchy (in minutes)
    TIMEFRAME_MAP = {
        'M1': 1,
        'M5': 5,
        'M15': 15,
        'M30': 30,
        'H1': 60,
        'H4': 240,
        'D1': 1440,
        'W1': 10080,
    }
    
    def __init__(self, db_manager=None):
        """
        Initialize MTF Analyzer.
        
        Args:
            db_manager: DatabaseManager instance for fetching data
        """
        self.db = db_manager
    
    def get_higher_timeframes(self, base_timeframe: str, count: int = 3) -> list:
        """
        Get higher timeframes for analysis.

        Args:
            base_timeframe: Base timeframe (e.g., 'M15')
            count: Number of higher timeframes to return

        Returns:
            List of higher timeframe strings
        """
        base_minutes = self.TIMEFRAME_MAP.get(base_timeframe, 15)

        # Get all higher timeframes
        higher_tfs = [
            (tf, minutes) for tf, minutes in self.TIMEFRAME_MAP.items()
            if minutes > base_minutes
        ]

        # Sort by minutes and take first 'count'
        higher_tfs.sort(key=lambda x: x[1])
        return [tf for tf, _ in higher_tfs[:count]]
    
    def calculate_trend_direction(self, df: pd.DataFrame) -> int:
        """
        Calculate trend direction for a timeframe.
        
        Returns:
            1: Uptrend
            -1: Downtrend
            0: Ranging/Neutral
        """
        if len(df) < 50:
            return 0
        
        if not TALIB_AVAILABLE:
            # Simple fallback: compare current price to MA
            close = df['close'].iloc[-1]
            ma_20 = df['close'].rolling(20).mean().iloc[-1]
            return 1 if close > ma_20 else -1
        
        close_prices = df['close'].astype('float64').values
        high_prices = df['high'].astype('float64').values
        low_prices = df['low'].astype('float64').values
        
        # Use multiple indicators for trend determination
        
        # 1. ADX for trend strength
        adx = talib.ADX(high_prices, low_prices, close_prices, timeperiod=14)
        adx_current = adx[-1] if len(adx) > 0 else 0
        
        # 2. Directional Movement
        plus_di = talib.PLUS_DI(high_prices, low_prices, close_prices, timeperiod=14)
        minus_di = talib.MINUS_DI(high_prices, low_prices, close_prices, timeperiod=14)
        
        plus_di_current = plus_di[-1] if len(plus_di) > 0 else 0
        minus_di_current = minus_di[-1] if len(minus_di) > 0 else 0
        
        # 3. Moving Average slope
        sma_20 = talib.SMA(close_prices, timeperiod=20)
        sma_50 = talib.SMA(close_prices, timeperiod=50)
        
        sma_20_current = sma_20[-1] if len(sma_20) > 0 else close_prices[-1]
        sma_50_current = sma_50[-1] if len(sma_50) > 0 else close_prices[-1]
        
        # Determine trend
        if adx_current < 20:
            # Weak trend = ranging
            return 0
        
        # Strong trend detected
        if plus_di_current > minus_di_current and sma_20_current > sma_50_current:
            return 1  # Uptrend
        elif minus_di_current > plus_di_current and sma_20_current < sma_50_current:
            return -1  # Downtrend
        else:
            return 0  # Mixed signals
    
    def calculate_momentum_score(self, df: pd.DataFrame) -> float:
        """
        Calculate momentum score (-1 to 1).
        
        Returns:
            Positive: Bullish momentum
            Negative: Bearish momentum
        """
        if len(df) < 14:
            return 0.0
        
        if not TALIB_AVAILABLE:
            # Simple momentum
            return (df['close'].iloc[-1] - df['close'].iloc[-10]) / df['close'].iloc[-10]
        
        close_prices = df['close'].astype('float64').values
        high_prices = df['high'].astype('float64').values
        low_prices = df['low'].astype('float64').values
        
        # RSI (normalized to -1 to 1)
        rsi = talib.RSI(close_prices, timeperiod=14)
        rsi_score = (rsi[-1] - 50) / 50 if len(rsi) > 0 else 0
        
        # MACD
        macd, signal, hist = talib.MACD(close_prices)
        macd_score = np.sign(hist[-1]) if len(hist) > 0 else 0
        
        # Stochastic
        stoch_k, stoch_d = talib.STOCH(high_prices, low_prices, close_prices)
        stoch_score = (stoch_k[-1] - 50) / 50 if len(stoch_k) > 0 else 0
        
        # Average momentum score
        momentum = (rsi_score + macd_score + stoch_score) / 3
        
        return np.clip(momentum, -1, 1)
    
    def calculate_volatility_context(self, df: pd.DataFrame) -> Dict[str, float]:
        """
        Calculate volatility metrics for context.
        
        Returns:
            Dict with ATR, volatility percentile, etc.
        """
        if len(df) < 20:
            return {'atr': 0, 'volatility_percentile': 50}
        
        if not TALIB_AVAILABLE:
            # Simple range-based volatility
            atr = (df['high'] - df['low']).rolling(14).mean().iloc[-1]
            return {'atr': atr, 'volatility_percentile': 50}
        
        high_prices = df['high'].astype('float64').values
        low_prices = df['low'].astype('float64').values
        close_prices = df['close'].astype('float64').values
        
        # ATR
        atr = talib.ATR(high_prices, low_prices, close_prices, timeperiod=14)
        current_atr = atr[-1] if len(atr) > 0 else 0
        
        # ATR percentile (where is current ATR relative to last 100 bars)
        if len(atr) >= 100:
            atr_percentile = (atr[-100:] < current_atr).sum() / 100 * 100
        else:
            atr_percentile = 50
        
        return {
            'atr': current_atr,
            'volatility_percentile': atr_percentile
        }
    
    def get_mtf_features(self, symbol: str, base_timeframe: str, 
                         higher_timeframes: Optional[list] = None) -> Dict[str, any]:
        """
        Get multi-timeframe features for a symbol.
        
        Args:
            symbol: Trading symbol
            base_timeframe: Base timeframe for trading
            higher_timeframes: List of higher TFs to analyze (auto-detected if None)
            
        Returns:
            Dictionary of MTF features
        """
        if higher_timeframes is None:
            higher_timeframes = self.get_higher_timeframes(base_timeframe, count=3)
        
        features = {}
        
        # Analyze each higher timeframe
        for i, htf in enumerate(higher_timeframes):
            # Get data for this timeframe
            if self.db:
                query = """
                    SELECT * FROM market_data 
                    WHERE symbol = ? AND timeframe = ?
                    ORDER BY timestamp DESC
                    LIMIT 200
                """
                with self.db.get_connection() as conn:
                    df = pd.read_sql_query(query, conn, params=(symbol, htf))
                
                if len(df) < 50:
                    continue
                
                df = df.sort_values('timestamp')
                
                # Calculate features for this timeframe
                trend = self.calculate_trend_direction(df)
                momentum = self.calculate_momentum_score(df)
                volatility = self.calculate_volatility_context(df)
                
                # Add to features dict
                prefix = f'HTF{i+1}'  # HTF1, HTF2, HTF3
                features[f'{prefix}_trend'] = trend
                features[f'{prefix}_momentum'] = momentum
                features[f'{prefix}_atr'] = volatility['atr']
                features[f'{prefix}_volatility_pct'] = volatility['volatility_percentile']
        
        # Calculate alignment scores
        if len(features) > 0:
            # Trend alignment: all trends pointing same direction?
            trend_keys = [k for k in features.keys() if k.endswith('_trend')]
            trends = [features[k] for k in trend_keys]
            
            if len(trends) > 0:
                # All same sign = aligned
                features['trend_alignment'] = 1 if all(t == trends[0] for t in trends) else 0
                features['trend_strength'] = abs(sum(trends)) / len(trends)
            
            # Momentum alignment
            momentum_keys = [k for k in features.keys() if k.endswith('_momentum')]
            momentums = [features[k] for k in momentum_keys]
            
            if len(momentums) > 0:
                features['momentum_alignment'] = np.mean(momentums)
        
        return features
    
    def should_trade_with_mtf(self, mtf_features: Dict[str, any], 
                              signal_direction: str) -> Tuple[bool, str]:
        """
        Determine if trade should be taken based on MTF analysis.
        
        Args:
            mtf_features: MTF features from get_mtf_features()
            signal_direction: 'BUY' or 'SELL'
            
        Returns:
            (should_trade, reason)
        """
        if not mtf_features:
            return True, "No MTF data available"
        
        # Get trend alignment
        trend_alignment = mtf_features.get('trend_alignment', 0)
        trend_strength = mtf_features.get('trend_strength', 0)
        
        # Get HTF1 (highest timeframe) trend
        htf1_trend = mtf_features.get('HTF1_trend', 0)
        
        # Convert signal to direction
        signal_value = 1 if signal_direction == 'BUY' else -1
        
        # Rule 1: HTF1 must agree with signal (or be neutral)
        if htf1_trend != 0 and htf1_trend != signal_value:
            return False, f"HTF1 trend ({htf1_trend}) conflicts with signal ({signal_direction})"
        
        # Rule 2: If trends are aligned, they should match signal
        if trend_alignment == 1 and trend_strength > 0:
            # All trends aligned
            htf_direction = 1 if mtf_features.get('HTF1_trend', 0) > 0 else -1
            if htf_direction != signal_value:
                return False, f"All HTF trends aligned against signal"
        
        # Rule 3: Check momentum alignment
        momentum_alignment = mtf_features.get('momentum_alignment', 0)
        if abs(momentum_alignment) > 0.5:
            # Strong momentum detected
            if np.sign(momentum_alignment) != signal_value:
                return False, f"HTF momentum ({momentum_alignment:.2f}) conflicts with signal"
        
        return True, "MTF analysis confirms signal"


def create_mtf_features_for_training(symbol: str, base_timeframe: str, 
                                     db_manager) -> pd.DataFrame:
    """
    Create MTF features for model training.
    
    This adds HTF features to the base timeframe data.
    """
    analyzer = MTFAnalyzer(db_manager)
    
    # Get base timeframe data
    query = """
        SELECT * FROM market_data 
        WHERE symbol = ? AND timeframe = ?
        ORDER BY timestamp ASC
    """
    with db_manager.get_connection() as conn:
        df = pd.read_sql_query(query, conn, params=(symbol, base_timeframe))
    
    if len(df) == 0:
        return df
    
    # Get MTF features (this will be the same for all rows, but in production
    # you'd calculate this for each timestamp)
    mtf_features = analyzer.get_mtf_features(symbol, base_timeframe)
    
    # Add MTF features as columns
    for key, value in mtf_features.items():
        df[key] = value
    
    return df
