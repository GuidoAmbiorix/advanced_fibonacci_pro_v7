"""
XAUUSD (Gold) Agent
Gold-specific trading agent with tailored parameters.
"""

from datetime import datetime
from typing import Dict, Any
from .base_agent import BaseAgent


class XAUUSDAgent(BaseAgent):
    """
    Gold trading agent.
    
    Gold-specific considerations:
    - Higher volatility (wider ATR)
    - Best during London and NY sessions
    - Often moves inverse to USD
    """
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__('XAUUSD', config)
        
        # Gold-specific overrides
        self.correlation_group = 'METALS'
        
        # Session times (UTC)
        self.london_start = config.get('london_start', 7)
        self.london_end = config.get('london_end', 16)
        self.ny_start = config.get('ny_start', 12)
        self.ny_end = config.get('ny_end', 21)
        
        # Session filter mode
        self.session_filter = config.get('session_filter', 'LONDON_NY')
        
        # Broker UTC offset
        self.broker_offset = config.get('broker_utc_offset', 2)
    
    def check_session(self) -> bool:
        """
        Check if current time is within Gold trading session.
        Gold trades best during London and NY sessions.
        """
        if self.session_filter == 'ALL':
            return True
        
        # Get current hour in UTC
        now = datetime.utcnow()
        utc_hour = now.hour
        
        in_london = self.london_start <= utc_hour < self.london_end
        in_ny = self.ny_start <= utc_hour < self.ny_end
        
        if self.session_filter == 'LONDON_NY':
            return in_london or in_ny
        elif self.session_filter == 'LONDON':
            return in_london
        elif self.session_filter == 'NY':
            return in_ny
        
        return True
    
    def get_pip_value(self) -> float:
        """Gold uses 0.01 as pip value."""
        return 0.01
