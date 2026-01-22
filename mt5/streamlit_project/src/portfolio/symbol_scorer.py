"""
Symbol Scorer - Dynamic scoring for each trading symbol.
Calculates score 0-100 based on market conditions and symbol characteristics.
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Optional
from datetime import datetime
from enum import Enum
import MetaTrader5 as mt5

from .symbol_metadata import (
    SYMBOL_METADATA, 
    Session, 
    VolatilityLevel,
    RiskProfile,
    get_all_symbols
)


class TrendDirection(Enum):
    """Trend classification."""
    BULLISH = "bullish"
    BEARISH = "bearish"
    NEUTRAL = "neutral"


class SymbolScorer:
    """
    Dynamic symbol scoring engine.
    
    Score components (0-100 total):
    - Session Activity (0-20): Is symbol's preferred session active?
    - Trend Alignment (0-25): HTF trend clarity
    - Spread Quality (0-15): Current spread vs max acceptable
    - Volatility Match (0-15): Is current volatility appropriate?
    - Historical Performance (0-25): Win rate from past trades
    """
    
    # Session time ranges (UTC)
    SESSION_TIMES = {
        Session.ASIAN: (0, 8),      # 00:00 - 08:00 UTC
        Session.LONDON: (7, 16),    # 07:00 - 16:00 UTC  
        Session.NY: (13, 22),       # 13:00 - 22:00 UTC
    }
    
    # Max acceptable spreads per symbol (in points)
    MAX_SPREADS = {
        "EURUSD": 15, "GBPUSD": 20, "USDJPY": 15, "USDCHF": 18,
        "USDCAD": 20, "AUDUSD": 18, "NZDUSD": 22, "EURJPY": 25,
        "GBPJPY": 30, "CADJPY": 28, "CHFJPY": 25, "NZDJPY": 28,
        "AUDJPY": 25, "EURAUD": 30, "EURCHF": 20, "EURGBP": 18,
        "GBPAUD": 35, "XAUUSD": 35, "XAGUSD": 40, "US30": 40,
    }
    
    def __init__(self, performance_data: Optional[pd.DataFrame] = None):
        """
        Initialize symbol scorer.
        
        Args:
            performance_data: DataFrame with historical trade performance
        """
        self.performance_data = performance_data
        self._cached_scores: Dict[str, float] = {}
        self._last_calculation: Optional[datetime] = None
    
    def _get_current_session(self) -> List[Session]:
        """Get currently active trading sessions."""
        now = datetime.utcnow()
        hour = now.hour
        
        active = []
        for session, (start, end) in self.SESSION_TIMES.items():
            if start <= hour < end:
                active.append(session)
        
        return active
    
    def _score_session_activity(self, symbol: str) -> float:
        """
        Score based on session activity (0-20).
        
        Full score if symbol's preferred session is active.
        """
        info = SYMBOL_METADATA.get(symbol)
        if not info:
            return 0.0
        
        active_sessions = self._get_current_session()
        
        if not active_sessions:
            return 5.0  # Off-hours, neutral score
        
        # Check if any of symbol's preferred sessions is active
        for session in info.sessions:
            if session in active_sessions:
                return 20.0  # Full score
        
        return 5.0  # Symbol's session not active
    
    def _score_trend_alignment(self, symbol: str) -> float:
        """
        Score based on trend clarity (0-25).
        
        Uses EMA slope and price position relative to EMA.
        """
        try:
            # Fetch H4 data for trend analysis
            rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_H4, 0, 50)
            
            if rates is None or len(rates) < 50:
                return 12.5  # Neutral if no data
            
            df = pd.DataFrame(rates)
            closes = df['close'].values
            
            # Calculate 20 EMA
            ema20 = pd.Series(closes).ewm(span=20, adjust=False).mean().values
            
            # Current price vs EMA
            current_price = closes[-1]
            current_ema = ema20[-1]
            
            # EMA slope (last 5 periods)
            ema_slope = (ema20[-1] - ema20[-5]) / ema20[-5] * 100
            
            score = 12.5  # Base neutral
            
            # Price above EMA = bullish, below = bearish
            price_vs_ema = (current_price - current_ema) / current_ema * 100
            
            # Strong trend alignment
            if abs(price_vs_ema) > 0.5 and abs(ema_slope) > 0.1:
                # Price and slope aligned
                if (price_vs_ema > 0 and ema_slope > 0) or (price_vs_ema < 0 and ema_slope < 0):
                    score = 25.0  # Strong aligned trend
                else:
                    score = 8.0   # Divergence
            elif abs(ema_slope) > 0.05:
                score = 18.0  # Moderate trend
            
            return score
            
        except Exception as e:
            return 12.5  # Neutral on error
    
    def _score_spread_quality(self, symbol: str) -> float:
        """
        Score based on current spread (0-15).
        
        Lower spread = higher score.
        """
        try:
            tick = mt5.symbol_info_tick(symbol)
            symbol_info = mt5.symbol_info(symbol)
            
            if not tick or not symbol_info:
                return 7.5  # Neutral
            
            # Calculate spread in points
            spread = (tick.ask - tick.bid) / symbol_info.point
            max_spread = self.MAX_SPREADS.get(symbol, 30)
            
            if spread <= max_spread * 0.5:
                return 15.0  # Excellent spread
            elif spread <= max_spread * 0.75:
                return 12.0  # Good spread
            elif spread <= max_spread:
                return 8.0   # Acceptable spread
            else:
                return 2.0   # Poor spread
                
        except Exception:
            return 7.5  # Neutral on error
    
    def _score_volatility_match(self, symbol: str) -> float:
        """
        Score based on current volatility vs expected (0-15).
        
        ATR within normal range = high score.
        """
        try:
            info = SYMBOL_METADATA.get(symbol)
            if not info:
                return 7.5
            
            # Fetch H1 data
            rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_H1, 0, 20)
            
            if rates is None or len(rates) < 20:
                return 7.5
            
            df = pd.DataFrame(rates)
            
            # Calculate ATR
            high = df['high'].values
            low = df['low'].values
            close = df['close'].values
            
            tr = np.maximum(
                high[1:] - low[1:],
                np.maximum(
                    abs(high[1:] - close[:-1]),
                    abs(low[1:] - close[:-1])
                )
            )
            atr = np.mean(tr[-14:])
            avg_atr = np.mean(tr)
            
            # Compare current ATR to average
            atr_ratio = atr / avg_atr if avg_atr > 0 else 1
            
            # Expected volatility based on symbol profile
            if info.volatility == VolatilityLevel.VERY_HIGH:
                # Expect high volatility
                if 0.8 <= atr_ratio <= 1.5:
                    return 15.0
                elif atr_ratio < 0.5:
                    return 5.0  # Too quiet
            elif info.volatility == VolatilityLevel.HIGH:
                if 0.7 <= atr_ratio <= 1.3:
                    return 15.0
            elif info.volatility == VolatilityLevel.MEDIUM:
                if 0.6 <= atr_ratio <= 1.4:
                    return 15.0
            else:  # LOW
                if 0.5 <= atr_ratio <= 1.2:
                    return 15.0
            
            return 10.0  # Moderate match
            
        except Exception:
            return 7.5
    
    def _score_historical_performance(self, symbol: str) -> float:
        """
        Score based on historical win rate (0-25).
        
        Uses performance data if available.
        """
        if self.performance_data is None or self.performance_data.empty:
            return 12.5  # Neutral if no data
        
        try:
            symbol_trades = self.performance_data[
                self.performance_data['symbol'] == symbol
            ]
            
            if len(symbol_trades) < 10:
                return 12.5  # Not enough data
            
            # Calculate win rate
            wins = len(symbol_trades[symbol_trades['profit'] > 0])
            total = len(symbol_trades)
            win_rate = wins / total * 100
            
            if win_rate >= 65:
                return 25.0
            elif win_rate >= 55:
                return 20.0
            elif win_rate >= 45:
                return 15.0
            elif win_rate >= 35:
                return 10.0
            else:
                return 5.0
                
        except Exception:
            return 12.5
    
    def calculate_symbol_score(self, symbol: str) -> Dict:
        """
        Calculate complete score for a symbol.
        
        Returns dict with total score and component breakdown.
        """
        session_score = self._score_session_activity(symbol)
        trend_score = self._score_trend_alignment(symbol)
        spread_score = self._score_spread_quality(symbol)
        volatility_score = self._score_volatility_match(symbol)
        performance_score = self._score_historical_performance(symbol)
        
        total = session_score + trend_score + spread_score + volatility_score + performance_score
        
        return {
            "symbol": symbol,
            "total_score": round(total, 1),
            "session_score": round(session_score, 1),
            "trend_score": round(trend_score, 1),
            "spread_score": round(spread_score, 1),
            "volatility_score": round(volatility_score, 1),
            "performance_score": round(performance_score, 1),
            "timestamp": datetime.now()
        }
    
    def get_all_symbol_scores(self, symbols: Optional[List[str]] = None) -> pd.DataFrame:
        """
        Calculate scores for all symbols.
        
        Returns DataFrame with all scores and components.
        """
        symbols = symbols or get_all_symbols()
        
        scores = []
        for symbol in symbols:
            score_data = self.calculate_symbol_score(symbol)
            
            # Add metadata
            info = SYMBOL_METADATA.get(symbol)
            if info:
                score_data["class"] = info.symbol_class.value
                score_data["risk_profile"] = info.risk_profile.value
                score_data["volatility"] = info.volatility.value
            
            scores.append(score_data)
        
        df = pd.DataFrame(scores)
        self._cached_scores = {row['symbol']: row['total_score'] for _, row in df.iterrows()}
        self._last_calculation = datetime.now()
        
        return df.sort_values('total_score', ascending=False)
    
    def get_top_symbols(self, n: int = 10) -> List[str]:
        """Get top N symbols by score."""
        df = self.get_all_symbol_scores()
        return df.head(n)['symbol'].tolist()
    
    def get_score(self, symbol: str) -> float:
        """Get cached score for a symbol, or calculate if not cached."""
        if symbol in self._cached_scores:
            return self._cached_scores[symbol]
        return self.calculate_symbol_score(symbol)['total_score']
