import pandas as pd
import numpy as np
from ta.trend import ADXIndicator, EMAIndicator
from ta.volatility import AverageTrueRange
from app.models.database import MarketRegime
from datetime import datetime

class MarketRegimeDetector:
    """
    Detects the current market regime:
    - TRENDING (Bullish/Bearish)
    - RANGING
    - HIGH_VOLATILITY
    """

    def __init__(self, df: pd.DataFrame):
        self.df = df
        self._calculate_indicators()

    def _calculate_indicators(self):
        """Calculate necessary indicators for regime detection"""
        # ADX for Trend Strength
        adx = ADXIndicator(self.df['high'], self.df['low'], self.df['close'], window=14)
        self.df['adx'] = adx.adx()
        self.df['di_plus'] = adx.adx_pos()
        self.df['di_minus'] = adx.adx_neg()

        # EMAs for Trend Direction
        ema_fast = EMAIndicator(self.df['close'], window=20)
        ema_slow = EMAIndicator(self.df['close'], window=50)
        self.df['ema_fast'] = ema_fast.ema_indicator()
        self.df['ema_slow'] = ema_slow.ema_indicator()

        # ATR for Volatility
        atr = AverageTrueRange(self.df['high'], self.df['low'], self.df['close'], window=14)
        self.df['atr'] = atr.average_true_range()
        
        # ATR MA for Relative Volatility
        self.df['atr_ma'] = self.df['atr'].rolling(window=50).mean()

    def detect_regime(self) -> dict:
        """
        Analyze the latest candle to determine regime.
        """
        if len(self.df) < 50:
            return {
                "regime": "UNCERTAIN",
                "trend": "NEUTRAL",
                "volatility": "NORMAL",
                "details": {}
            }

        current = self.df.iloc[-1]
        
        # 1. Volatility Detection
        volatility_level = "NORMAL"
        if current['atr'] > current['atr_ma'] * 1.5:
            volatility_level = "HIGH"
        elif current['atr'] < current['atr_ma'] * 0.7:
            volatility_level = "LOW"
            
        # 2. Trend Detection (ADX)
        regime_type = "RANGING"
        trend_direction = "NEUTRAL"
        
        if current['adx'] > 25:
            regime_type = "TRENDING"
            if current['di_plus'] > current['di_minus'] and current['ema_fast'] > current['ema_slow']:
                trend_direction = "BULLISH"
            elif current['di_minus'] > current['di_plus'] and current['ema_fast'] < current['ema_slow']:
                trend_direction = "BEARISH"
        
        # 3. Special Case: Extreme Volatility overrides Trend?
        # Usually we want to know both. But if volatility is EXTREME, maybe we flag it.
        if current['atr'] > current['atr_ma'] * 2.5:
            volatility_level = "EXTREME"

        return {
            "regime": regime_type,
            "trend": trend_direction,
            "volatility": volatility_level,
            "details": {
                "adx": round(current['adx'], 2),
                "atr": round(current['atr'], 5),
                "atr_ratio": round(current['atr'] / current['atr_ma'], 2) if current['atr_ma'] else 0
            }
        }

    def get_db_model(self, symbol: str, timeframe: str) -> MarketRegime:
        """Return SQLAlchemy model instance"""
        result = self.detect_regime()
        return MarketRegime(
            symbol=symbol,
            timeframe=timeframe,
            regime_type=result['regime'],
            trend_direction=result['trend'],
            volatility_level=result['volatility'],
            details=result['details'],
            created_at=datetime.utcnow()
        )
