from dataclasses import dataclass
from datetime import datetime
from typing import Optional

@dataclass
class Trade:
    ticket: int
    symbol: str
    direction: str  # "BUY" or "SELL"
    entry_time: datetime
    exit_time: datetime
    entry_price: float
    exit_price: float
    volume: float
    profit: float
    commission: float
    swap: float
    
    # Analytics (Calculated later)
    duration_minutes: float = 0.0
    risk_r: float = 0.0
    mfe: float = 0.0  # Maximum Favorable Excursion
    mae: float = 0.0  # Maximum Adverse Excursion
    
    # Pattern / Metadata
    strategy: Optional[str] = None
    comment: Optional[str] = None
    magic: Optional[int] = None

    @property
    def total_profit(self) -> float:
        return self.profit + self.commission + self.swap
