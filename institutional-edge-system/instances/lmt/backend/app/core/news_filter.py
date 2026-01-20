# import investpy # Disabled
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

    def update_using_mt5(self, mt5_connector):
        """
        Update high impact events using MT5 Connector.
        Should be called periodically (e.g., hourly).
        """
        try:
            # Fetch events for next 24 hours
            start_dt = datetime.datetime.utcnow()
            end_dt = start_dt + datetime.timedelta(hours=24)
            
            logger.info(f"📰 NewsFilter: Fetching calendar events from {start_dt} to {end_dt}")
            events = mt5_connector.get_calendar_events(start_dt, end_dt)
            
            if not events:
                logger.warning("📰 NewsFilter: No calendar events returned (MT5 calendar may not be supported)")
                return

            # Filter for High Impact (Importance >= 3 or specific logic)
            # MT5 Importance: 0=None, 1=Low, 2=Moderate, 3=High
            high_impact = [e for e in events if e.get('importance', 0) >= 3]
            
            self.high_impact_events = high_impact
            self.last_update = datetime.datetime.now()
            self._save_cache()
            
            if high_impact:
                logger.info(f"📰 NewsFilter: Cached {len(high_impact)} high impact events via MT5")
                for event in high_impact[:3]:  # Log first 3
                    logger.info(f"   - {event.get('title')} ({event.get('currency')}) @ {event.get('time')}")
            else:
                logger.info(f"📰 NewsFilter: {len(events)} events found, 0 high impact")
                
        except Exception as e:
            logger.error(f"📰 NewsFilter update failed: {e}")

    def fetch_calendar(self, target_date: Optional[datetime.date] = None):
        """Legacy method (Disabled)"""
        pass

    def is_event_imminent(self, minutes_threshold: int = 30, current_time: Optional[datetime.datetime] = None) -> bool:
        """Check if a high impact event is within threshold minutes"""
        if current_time is None:
            current_time = datetime.datetime.utcnow()

        if not self.high_impact_events:
            return False
        
        # Ensure we have datetime objects
        # MT5 events use datetime objects for 'time'
        
        for event in self.high_impact_events:
            try:
                event_time = event.get('time')
                
                # Handle legacy string format if cache is old
                if isinstance(event_time, str):
                    try:
                        # Reset legacy cache if found
                        self.high_impact_events = [] 
                        return False
                    except:
                        continue
                        
                if not isinstance(event_time, datetime.datetime):
                    continue
                    
                # Time difference in minutes
                diff_seconds = (event_time - current_time).total_seconds()
                diff_minutes = abs(diff_seconds) / 60.0
                
                # Check if imminent (future event within threshold OR past event within small window?)
                # Usually we block BEFORE event.
                # If event is in 10 mins -> Block.
                # If event was 5 mins ago -> Maybe Unblock?
                # User usually wants "30 mins before".
                
                # If event is in the future (within threshold)
                if 0 <= diff_seconds <= (minutes_threshold * 60):
                    logger.warning(f"🚨 NEWS FILTER: {event.get('title')} ({event.get('currency')}) in {diff_minutes:.1f} min")
                    return True
                    
                # Strict Mode: Also block if event was just released (volatility) e.g. 5 mins after
                if -300 <= diff_seconds < 0:
                     logger.warning(f"🚨 NEWS FILTER: {event.get('title')} Released! Volatility Warning.")
                     return True
                     
            except Exception as e:
                continue
                
        return False

    def should_block_trade(self, current_time: Optional[datetime.datetime] = None) -> bool:
        """Alias for convenience"""
        return self.is_event_imminent(minutes_threshold=30, current_time=current_time)

