import aiohttp
import asyncio
import logging
from datetime import datetime
from app.core.config import settings

logger = logging.getLogger(__name__)

class AlertService:
    """
    Service for sending asynchronous alerts to Discord via webhooks.
    Designed to be fire-and-forget to not block the main trading loop.
    """
    
    LEVEL_COLORS = {
        "INFO": 3447003,      # Blue
        "SUCCESS": 5763719,   # Green
        "WARNING": 16776960,  # Yellow
        "CRITICAL": 15158332, # Red
        "ERROR": 15158332     # Red
    }

    def __init__(self, webhook_url: str = None):
        self.webhook_url = webhook_url or settings.DISCORD_WEBHOOK_URL
        self.session = None

    async def _get_session(self):
        if self.session is None or self.session.closed:
            self.session = aiohttp.ClientSession()
        return self.session

    async def send_alert(self, title: str, message: str, level: str = "INFO", fields: list = None):
        """
        Send an alert to Discord.
        
        Args:
            title: Title of the embed
            message: Main content description
            level: INFO, SUCCESS, WARNING, CRITICAL
            fields: Optional list of dicts [{'name': 'X', 'value': 'Y', 'inline': True}]
        """
        if not self.webhook_url:
            logger.warning("Discord Webhook URL not set - skipping alert")
            return

        try:
            payload = {
                "username": f"{settings.APP_NAME} Bot",
                "embeds": [{
                    "title": f"[{level}] {title}",
                    "description": message,
                    "color": self.LEVEL_COLORS.get(level.upper(), 3447003),
                    "timestamp": datetime.utcnow().isoformat(),
                    "footer": {"text": f"Instance: {settings.INSTANCE_NAME}"}
                }]
            }
            
            if fields:
                payload["embeds"][0]["fields"] = fields

            session = await self._get_session()
            async with session.post(self.webhook_url, json=payload) as response:
                if response.status not in [200, 204]:
                    logger.error(f"Failed to send Discord alert: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error sending Discord alert: {e}")

    async def close(self):
        if self.session and not self.session.closed:
            await self.session.close()

# Global instance
alert_service = AlertService()
