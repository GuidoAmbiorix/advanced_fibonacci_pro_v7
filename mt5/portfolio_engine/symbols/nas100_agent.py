"""
NAS100 (NASDAQ 100) Agent
Index-specific trading agent focused on US session.
"""

from datetime import datetime
from typing import Dict, Any
from .base_agent import BaseAgent


class NAS100Agent(BaseAgent):
    """
    NASDAQ 100 trading agent.
    
    NAS100-specific considerations:
    - Best during US session only
    - Higher volatility requirements
    - Correlates with tech sector
    """
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__('NAS100', config)
        
        self.correlation_group = 'INDICES'
        
        # US session times (UTC)
        self.ny_start = config.get('ny_start', 13)
        self.ny_end = config.get('ny_end', 21)
        
        self.session_filter = config.get('session_filter', 'NY_ONLY')
        
        # Index-specific: higher displacement requirement
        self.displacement_atr = config.get('displacement_atr', 1.5)
    
    def check_session(self) -> bool:
        """
        Check if current time is within NAS100 trading session.
        Indices trade best during their home session.
        """
        if self.session_filter == 'ALL':
            return True
        
        now = datetime.utcnow()
        utc_hour = now.hour
        
        in_ny = self.ny_start <= utc_hour < self.ny_end
        
        if self.session_filter in ['NY_ONLY', 'NY']:
            return in_ny
        
        return True
    
    def get_pip_value(self) -> float:
        """NAS100 typically uses 0.1 as pip value."""
        return 0.1
