import investpy
import datetime
import json
import os
from loguru import logger
from typing import List, Dict, Optional

class NewsFilter:
    def __init__(self, cache_file: str = "news_cache.json", cache_duration_minutes: int = 60):
        self.cache_file = cache_file
        self.cache_duration = datetime.timedelta(minutes=cache_duration_minutes)
        self.high_impact_events = []
        self.last_update = None
        self._load_cache()

    def _load_cache(self):
        """Load news from local JSON cache if valid"""
        if not os.path.exists(self.cache_file):
            return

        try:
            with open(self.cache_file, 'r') as f:
                data = json.load(f)
                
            last_update = datetime.datetime.fromisoformat(data['last_update'])
            if datetime.datetime.now() - last_update < self.cache_duration:
                self.high_impact_events = data['events']
                self.last_update = last_update
                logger.info(f"Loaded {len(self.high_impact_events)} news events from cache.")
            else:
                logger.info("News cache expired.")
        except Exception as e:
            logger.error(f"Failed to load news cache: {e}")

    def _save_cache(self):
        """Save current events to JSON cache"""
        try:
            data = {
                'last_update': datetime.datetime.now().isoformat(),
                'events': self.high_impact_events
            }
            with open(self.cache_file, 'w') as f:
                json.dump(data, f, default=str)
        except Exception as e:
            logger.error(f"Failed to save news cache: {e}")

    def fetch_calendar(self, target_date: Optional[datetime.date] = None):
        """Fetch high impact news for a specific date using investpy"""
        if target_date is None:
            target_date = datetime.date.today()
            
        date_str = target_date.strftime("%d/%m/%Y")
        
        # Calculate next day for to_date (investpy requires distinct dates)
        next_day = target_date + datetime.timedelta(days=1)
        next_day_str = next_day.strftime("%d/%m/%Y")
        
        # Check if we already have data for this date in memory (simple optimization)
        if hasattr(self, '_current_date_cache') and self._current_date_cache == date_str and self.high_impact_events:
            return

        try:
            # Fetch calendar
            # ERR#0032 Fix: to_date must be > from_date
            df = investpy.news.economic_calendar(
                countries=['United States', 'Euro Zone'],
                importances=['high'],
                from_date=date_str,
                to_date=next_day_str
            )
            
            if df is not None and not df.empty:
                # Filter to only keep events for the target date
                df = df[df['date'] == date_str]
                
                self.high_impact_events = df.to_dict('records')
                self._current_date_cache = date_str
                logger.info(f"Fetched {len(self.high_impact_events)} events for {date_str}")
            else:
                self.high_impact_events = []
                self._current_date_cache = date_str

        except Exception as e:
            logger.error(f"Error fetching calendar for {date_str}: {e}")
            self.high_impact_events = [] # Safety

    def is_event_imminent(self, minutes_threshold: int = 30, current_time: Optional[datetime.datetime] = None) -> bool:
        """Check if a high impact event is within threshold minutes"""
        if current_time is None:
            current_time = datetime.datetime.now()

        # Update calendar for the target date
        self.fetch_calendar(current_time.date())
        
        now_time = current_time.time()
        
        for event in self.high_impact_events:
            try:
                event_time_str = event.get('time', '')
                if not event_time_str: continue

                # Parse event time (HH:MM)
                event_time = datetime.datetime.strptime(event_time_str, "%H:%M").time()
                
                # Combine with correct date
                event_dt = datetime.datetime.combine(current_time.date(), event_time)
                
                # Check absolute difference
                diff = abs((event_dt - current_time).total_seconds()) / 60.0
                
                if diff <= minutes_threshold:
                    logger.warning(f"🚨 NEWS FILTER: {event['event']} at {event_time_str} (Current: {now_time})")
                    return True
            except Exception as e:
                continue
                
        return False

    def should_block_trade(self, current_time: Optional[datetime.datetime] = None) -> bool:
        """Alias for convenience"""
        return self.is_event_imminent(minutes_threshold=30, current_time=current_time)
