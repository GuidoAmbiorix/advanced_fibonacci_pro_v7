from enum import Enum
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from datetime import datetime

class MarketRegime(Enum):
    """Market regime classification"""
    TRENDING = "TRENDING"
    RANGING = "RANGING"
    BREAKOUT = "BREAKOUT"
    VOLATILE = "VOLATILE"


class StrategyType(Enum):
    """Available trading strategies"""
    TREND_FOLLOWING = "TREND_FOLLOWING"
    RANGE_SCALPING = "RANGE_SCALPING"
    BREAKOUT_MOMENTUM = "BREAKOUT_MOMENTUM"


@dataclass
class GridLevel:
    """Grid recovery level"""
    price: float
    distance_atr: float
    filled: bool = False
    entry_time: Optional[datetime] = None
    metadata: Dict = field(default_factory=dict)


@dataclass
class AdaptiveSignal:
    """Trading signal with strategy context"""
    symbol: str
    timeframe: str
    entry_price: float
    stop_loss: float
    take_profit: float
    direction: str  # "BUY" or "SELL"
    strategy_type: StrategyType
    market_regime: MarketRegime
    score: float
    confidence: float  # 0-1

    # Grid recovery
    enable_grid: bool = False
    grid_levels: List[GridLevel] = field(default_factory=list)

    # Risk
    risk_percent: float = 1.0
    position_size: float = 0.0

    # Context
    timestamp: datetime = None
    metadata: Dict = field(default_factory=dict)

    @property
    def signal_type(self) -> str:
        """Alias for direction to match TradingBot expectation"""
        return self.direction

    @property
    def confluence_score(self) -> float:
        """Alias for score to match TradingBot expectation"""
        return self.score

    @property
    def take_profit_1(self) -> float:
        """Alias for take_profit"""
        return self.take_profit

    @property
    def take_profit_2(self) -> float:
        """Get TP2 from metadata or fall back to TP1"""
        return self.metadata.get('tp2', self.take_profit)

    @property
    def take_profit_3(self) -> float:
        """Get TP3 from metadata or fall back to TP1"""
        return self.metadata.get('tp3', self.take_profit)
