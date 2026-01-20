"""
GBPJPY Agent
Cross pair trading agent active in London and Tokyo overlap.
"""

from datetime import datetime
from typing import Dict, Any
from .base_agent import BaseAgent


class GBPJPYAgent(BaseAgent):
    """
    GBP/JPY trading agent.
    
    GBPJPY-specific considerations:
    - High volatility pair ("Dragon")
    - Active during London-Tokyo and London-NY overlaps
    - Part of JPY correlation group
    """
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__('GBPJPY', config)
        
        self.correlation_group = 'JPY'
        
        # Session times (UTC)
        self.london_start = config.get('london_start', 7)
        self.london_end = config.get('london_end', 16)
        self.ny_start = config.get('ny_start', 12)
        self.ny_end = config.get('ny_end', 21)
        
        self.session_filter = config.get('session_filter', 'LONDON_NY')
    
    def check_session(self) -> bool:
        """
        Check if current time is within GBPJPY trading session.
        """
        if self.session_filter == 'ALL':
            return True
        
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
        """GBPJPY uses 0.01 as pip value (3 decimal for JPY pairs)."""
        return 0.01
