"""
Killzone Manager - Controls trading based on time windows
"""
import logging
from datetime import datetime, time, timedelta
import pytz
from typing import List, Dict, Optional, Set

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
        
        # Phase 6: Advanced features
        self.holidays: Set[str] = set(config.get('killzones', {}).get('holidays', []))  # YYYY-MM-DD format
        self.max_spread_pips = config.get('killzones', {}).get('max_spread_pips', 3.0)
        self.symbol_overrides = config.get('killzones', {}).get('symbol_overrides', {})
        
        if self.enabled:
            self.logger.info(f"Killzone filtering enabled with {len(self.windows)} windows in {tz_str}")
            if self.holidays:
                self.logger.info(f"Holiday calendar loaded: {len(self.holidays)} dates")
        else:
            self.logger.info("Killzone filtering disabled")
        
    def is_trading_allowed(self, symbol: Optional[str] = None, spread_pips: Optional[float] = None) -> tuple[bool, Optional[str]]:
        """
        Check if current time is within an active killzone.
        
        Args:
            symbol: Trading symbol (for per-symbol overrides)
            spread_pips: Current spread in pips (for spread filtering)
        
        Returns:
            (allowed, reason) tuple
        """
        if not self.enabled:
            return True, "Killzones disabled"
        
        # Phase 6: Check for symbol-specific override
        if symbol and symbol in self.symbol_overrides:
            override = self.symbol_overrides[symbol]
            if not override.get('enabled', True):
                return False, f"Symbol {symbol} disabled in killzone settings"
            # Use symbol-specific windows if provided
            windows = override.get('windows', self.windows)
        else:
            windows = self.windows
            
        now = datetime.now(self.timezone)
        
        # Phase 6: Check if today is a holiday
        today_str = now.strftime("%Y-%m-%d")
        if today_str in self.holidays:
            return False, f"Holiday: {today_str}"
        
        # Phase 6: Check spread filter
        if spread_pips is not None and spread_pips > self.max_spread_pips:
            return False, f"Spread too high: {spread_pips:.1f} pips > {self.max_spread_pips:.1f} pips"
        
        current_time = now.time()
        current_day = now.weekday()  # 0=Monday, 6=Sunday
        
        for window in windows:
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
        """
        Phase 6: Calculate when the next trading window opens.
        
        Returns:
            Human-readable string with next window time and countdown
        """
        current_day = current_time.weekday()
        current_time_only = current_time.time()
        
        # Check windows for today (after current time)
        for window in self.windows:
            if current_day not in window.get('days', []):
                continue
            
            start = datetime.strptime(window['start'], "%H:%M").time()
            
            if start > current_time_only:
                # Found a window later today
                next_datetime = datetime.combine(current_time.date(), start)
                next_datetime = self.timezone.localize(next_datetime)
                time_until = next_datetime - current_time
                hours = int(time_until.total_seconds() // 3600)
                minutes = int((time_until.total_seconds() % 3600) // 60)
                return f"{window.get('name', 'Window')} in {hours}h {minutes}m"
        
        # Check windows for upcoming days (next 7 days)
        for days_ahead in range(1, 8):
            check_day = (current_day + days_ahead) % 7
            
            for window in self.windows:
                if check_day not in window.get('days', []):
                    continue
                
                # Found next window
                next_date = current_time.date() + timedelta(days=days_ahead)
                start = datetime.strptime(window['start'], "%H:%M").time()
                next_datetime = datetime.combine(next_date, start)
                next_datetime = self.timezone.localize(next_datetime)
                
                time_until = next_datetime - current_time
                hours = int(time_until.total_seconds() // 3600)
                minutes = int((time_until.total_seconds() % 3600) // 60)
                
                day_names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                return f"{window.get('name', 'Window')} on {day_names[check_day]} in {hours}h {minutes}m"
        
        return "No upcoming windows"
    
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
