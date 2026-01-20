"""
Exposure Tracker
Tracks open positions and exposure across symbols and groups.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional
from datetime import datetime
from collections import defaultdict


@dataclass
class OpenPosition:
    """Tracked open position."""
    ticket: int
    symbol: str
    direction: int
    entry_price: float
    stop_loss: float
    volume: float
    risk_percent: float
    group: str
    entry_time: datetime


class ExposureTracker:
    """
    Tracks portfolio exposure across symbols and groups.
    
    Maintains real-time view of:
    - Total portfolio exposure
    - Per-symbol exposure
    - Per-group exposure
    - Position counts
    """
    
    def __init__(self):
        self.positions: Dict[int, OpenPosition] = {}  # ticket -> position
        self._symbol_exposure: Dict[str, float] = defaultdict(float)
        self._group_exposure: Dict[str, float] = defaultdict(float)
    
    def add_position(self, position: OpenPosition):
        """
        Add a new position to tracking.
        
        Args:
            position: OpenPosition object
        """
        self.positions[position.ticket] = position
        self._symbol_exposure[position.symbol] += position.risk_percent
        self._group_exposure[position.group] += position.risk_percent
    
    def remove_position(self, ticket: int) -> Optional[OpenPosition]:
        """
        Remove a position from tracking.
        
        Args:
            ticket: Position ticket number
            
        Returns:
            Removed position or None
        """
        if ticket not in self.positions:
            return None
        
        position = self.positions.pop(ticket)
        self._symbol_exposure[position.symbol] -= position.risk_percent
        self._group_exposure[position.group] -= position.risk_percent
        
        # Clean up zero values
        if self._symbol_exposure[position.symbol] <= 0:
            del self._symbol_exposure[position.symbol]
        if self._group_exposure[position.group] <= 0:
            del self._group_exposure[position.group]
        
        return position
    
    def update_position(self, ticket: int, new_risk: float):
        """Update risk for a position (e.g., after partial close)."""
        if ticket not in self.positions:
            return
        
        position = self.positions[ticket]
        old_risk = position.risk_percent
        risk_diff = new_risk - old_risk
        
        position.risk_percent = new_risk
        self._symbol_exposure[position.symbol] += risk_diff
        self._group_exposure[position.group] += risk_diff
    
    def get_total_exposure(self) -> float:
        """Get total portfolio exposure percentage."""
        return sum(p.risk_percent for p in self.positions.values())
    
    def get_symbol_exposure(self, symbol: str) -> float:
        """Get exposure for a specific symbol."""
        return self._symbol_exposure.get(symbol, 0.0)
    
    def get_group_exposure(self, group: str) -> float:
        """Get exposure for a correlation group."""
        return self._group_exposure.get(group, 0.0)
    
    def get_all_group_exposures(self) -> Dict[str, float]:
        """Get all group exposures."""
        return dict(self._group_exposure)
    
    def get_symbol_positions(self, symbol: str) -> List[OpenPosition]:
        """Get all positions for a symbol."""
        return [p for p in self.positions.values() if p.symbol == symbol]
    
    def get_symbol_position_count(self, symbol: str) -> int:
        """Get position count for a symbol."""
        return len(self.get_symbol_positions(symbol))
    
    def get_total_positions(self) -> int:
        """Get total number of open positions."""
        return len(self.positions)
    
    def get_group_positions(self, group: str) -> List[OpenPosition]:
        """Get all positions in a correlation group."""
        return [p for p in self.positions.values() if p.group == group]
    
    def clear(self):
        """Clear all tracked positions."""
        self.positions.clear()
        self._symbol_exposure.clear()
        self._group_exposure.clear()
    
    def get_summary(self) -> str:
        """Get exposure summary string."""
        lines = [
            "═══════ EXPOSURE SUMMARY ═══════",
            f"Total Positions: {self.get_total_positions()}",
            f"Total Exposure: {self.get_total_exposure():.2f}%",
            "",
            "By Symbol:"
        ]
        
        for symbol, exposure in sorted(self._symbol_exposure.items()):
            count = self.get_symbol_position_count(symbol)
            lines.append(f"  {symbol}: {exposure:.2f}% ({count} pos)")
        
        lines.append("")
        lines.append("By Group:")
        
        for group, exposure in sorted(self._group_exposure.items()):
            count = len(self.get_group_positions(group))
            lines.append(f"  {group}: {exposure:.2f}% ({count} pos)")
        
        lines.append("═════════════════════════════════")
        
        return "\n".join(lines)
