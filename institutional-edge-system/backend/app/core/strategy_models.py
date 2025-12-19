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
