"""
Event Bus
Simple event system for signal and trade events.
"""

from dataclasses import dataclass
from typing import Callable, Dict, List, Any
from enum import Enum
from datetime import datetime


class EventType(Enum):
    """Event types."""
    SIGNAL = "signal"
    TRADE_OPEN = "trade_open"
    TRADE_CLOSE = "trade_close"
    PARTIAL_CLOSE = "partial_close"
    STOP_MOVED = "stop_moved"
    NEW_BAR = "new_bar"
    RISK_CHANGE = "risk_change"
    PORTFOLIO_UPDATE = "portfolio_update"


@dataclass
class Event:
    """Event data container."""
    type: EventType
    timestamp: datetime
    symbol: str = ""
    data: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.data is None:
            self.data = {}


class EventBus:
    """
    Simple pub/sub event bus for trading events.
    
    Usage:
        bus = EventBus()
        bus.subscribe(EventType.SIGNAL, my_handler)
        bus.publish(Event(EventType.SIGNAL, datetime.now(), "XAUUSD", {...}))
    """
    
    def __init__(self):
        self._subscribers: Dict[EventType, List[Callable]] = {}
        self._history: List[Event] = []
        self._max_history = 1000
    
    def subscribe(self, event_type: EventType, handler: Callable[[Event], None]):
        """
        Subscribe to an event type.
        
        Args:
            event_type: Type of event to subscribe to
            handler: Callback function (receives Event)
        """
        if event_type not in self._subscribers:
            self._subscribers[event_type] = []
        
        if handler not in self._subscribers[event_type]:
            self._subscribers[event_type].append(handler)
    
    def unsubscribe(self, event_type: EventType, handler: Callable):
        """Unsubscribe from an event type."""
        if event_type in self._subscribers:
            if handler in self._subscribers[event_type]:
                self._subscribers[event_type].remove(handler)
    
    def publish(self, event: Event):
        """
        Publish an event to all subscribers.
        
        Args:
            event: Event to publish
        """
        # Store in history
        self._history.append(event)
        if len(self._history) > self._max_history:
            self._history.pop(0)
        
        # Notify subscribers
        if event.type in self._subscribers:
            for handler in self._subscribers[event.type]:
                try:
                    handler(event)
                except Exception as e:
                    print(f"Error in event handler: {e}")
    
    def get_history(self, event_type: EventType = None, limit: int = 100) -> List[Event]:
        """Get recent event history."""
        if event_type:
            events = [e for e in self._history if e.type == event_type]
        else:
            events = self._history
        
        return events[-limit:]
    
    def clear_history(self):
        """Clear event history."""
        self._history.clear()
    
    def clear_subscribers(self):
        """Clear all subscribers."""
        self._subscribers.clear()
