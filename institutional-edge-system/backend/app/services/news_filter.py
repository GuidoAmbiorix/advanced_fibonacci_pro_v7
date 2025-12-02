import httpx
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from app.models.database import NewsEvent
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)

class NewsFilterService:
    """
    Fetches economic news and checks for trading restrictions.
    """

    def __init__(self, db: Session):
        self.db = db

    async def fetch_news(self):
        """
        Fetch news from external API (e.g., Financial Modeling Prep or similar).
        For now, we'll use a placeholder or a free endpoint if available.
        """
        # Placeholder for FMP API or similar
        # url = f"https://financialmodelingprep.com/api/v3/economic_calendar?apikey={settings.FMP_API_KEY}"
        
        # Mock implementation for now to avoid external dependencies in this step
        # In production, implement actual API call
        logger.info("Fetching news (Mock)...")
        return []

    def check_news_impact(self, symbol: str) -> dict:
        """
        Check if there are high-impact news events near now.
        Returns: {"allowed": bool, "reason": str}
        """
        now = datetime.utcnow()
        lookahead = timedelta(minutes=30)
        lookback = timedelta(minutes=15)
        
        # currencies involved in symbol (e.g. EURUSD -> EUR, USD)
        currencies = self._get_currencies_from_symbol(symbol)
        
        # Query DB for high impact news for these currencies
        events = self.db.query(NewsEvent).filter(
            NewsEvent.impact == 'HIGH',
            NewsEvent.currency.in_(currencies),
            NewsEvent.date >= now - lookback,
            NewsEvent.date <= now + lookahead
        ).all()
        
        if events:
            event_names = ", ".join([e.title for e in events])
            return {
                "allowed": False,
                "reason": f"High Impact News: {event_names}"
            }
            
        return {"allowed": True, "reason": "No News"}

    def _get_currencies_from_symbol(self, symbol: str) -> list:
        """Extract currencies from symbol string"""
        # Simple logic for Forex
        if len(symbol) == 6:
            return [symbol[:3], symbol[3:]]
        # Crypto
        if "USD" in symbol:
            return ["USD"]
        return []

    async def update_calendar(self):
        """
        Periodic task to update local DB with latest news.
        """
        # Implementation to fetch from API and upsert to DB
        pass
