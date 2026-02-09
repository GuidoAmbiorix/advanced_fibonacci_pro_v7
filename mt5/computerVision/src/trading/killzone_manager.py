"""
Killzone Manager - Controls trading based on time windows
"""
import logging
from datetime import datetime, time
import pytz
from typing import List, Dict, Optional

class KillzoneManager:
    """Manages trading time windows (killzones)."""
    
    def __init__(self, config: dict):
        self.config = config
        self.logger = logging.getLogger(__name__)
        self.enabled = config.get('killzones', {}).get('enabled', False)
        
        # Get timezone
        tz_str = config.get('killzones', {}).get('timezone', 'UTC')
        try:
            self.timezone = pytz.timezone(tz_str)
        except pytz.exceptions.UnknownTimeZoneError:
            self.logger.warning(f"Unknown timezone '{tz_str}', defaulting to UTC")
            self.timezone = pytz.UTC
            
        self.windows = config.get('killzones', {}).get('windows', [])
        
        if self.enabled:
            self.logger.info(f"Killzone filtering enabled with {len(self.windows)} windows in {tz_str}")
        else:
            self.logger.info("Killzone filtering disabled")
        
    def is_trading_allowed(self) -> tuple[bool, Optional[str]]:
        """
        Check if current time is within an active killzone.
        
        Returns:
            (allowed, reason) tuple
        """
        if not self.enabled:
            return True, "Killzones disabled"
            
        now = datetime.now(self.timezone)
        current_time = now.time()
        current_day = now.weekday()  # 0=Monday, 6=Sunday
        
        for window in self.windows:
            # Check if today is an active day
            if current_day not in window.get('days', []):
                continue
                
            # Parse window times
            start = datetime.strptime(window['start'], "%H:%M").time()
            end = datetime.strptime(window['end'], "%H:%M").time()
            
            # Check if current time is within window
            if start <= current_time <= end:
                window_name = window.get('name', 'Active Window')
                self.logger.debug(f"Trading allowed: {window_name}")
                return True, f"Inside {window_name}"
        
        # No active window found
        next_window = self._get_next_window(now)
        reason = f"Outside killzones. Next: {next_window}"
        self.logger.debug(reason)
        return False, reason
    
    def _get_next_window(self, current_time: datetime) -> str:
        """Calculate when the next trading window opens."""
        # Simple implementation - just return generic message
        # TODO: Calculate actual next window time
        return "check schedule"
    
    def get_active_window(self) -> Optional[Dict]:
        """Get details of the current active window."""
        if not self.enabled:
            return None
            
        now = datetime.now(self.timezone)
        current_time = now.time()
        current_day = now.weekday()
        
        for window in self.windows:
            if current_day not in window.get('days', []):
                continue
                
            start = datetime.strptime(window['start'], "%H:%M").time()
            end = datetime.strptime(window['end'], "%H:%M").time()
            
            if start <= current_time <= end:
                return window
        
        return None
