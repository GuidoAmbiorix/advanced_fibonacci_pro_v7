
import aiohttp
from loguru import logger
from typing import Optional

class TelegramService:
    """
    Service for sending Telegram notifications
    """
    def __init__(self, bot_token: str, chat_id: str):
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.base_url = f"https://api.telegram.org/bot{bot_token}"

    async def send_message(self, message: str) -> bool:
        """
        Send a text message to the configured chat
        """
        if not self.bot_token or not self.chat_id:
            logger.warning("Telegram credentials not configured")
            return False

        try:
            url = f"{self.base_url}/sendMessage"
            payload = {
                "chat_id": self.chat_id,
                "text": message,
                "parse_mode": "HTML"
            }

            async with aiohttp.ClientSession() as session:
                async with session.post(url, json=payload) as response:
                    if response.status == 200:
                        logger.info("Telegram message sent successfully")
                        return True
                    else:
                        error_text = await response.text()
                        logger.error(f"Failed to send Telegram message: {error_text}")
                        return False

        except Exception as e:
            logger.error(f"Error sending Telegram message: {e}")
            return False

    async def send_trade_notification(self, trade_data: dict):
        """
        Format and send a trade notification
        """
        emoji = "🟢" if trade_data.get('type') == 'BUY' else "🔴"
        
        message = (
            f"{emoji} <b>New Trade Executed</b>\n\n"
            f"<b>Symbol:</b> {trade_data.get('symbol')}\n"
            f"<b>Type:</b> {trade_data.get('type')}\n"
            f"<b>Entry:</b> {trade_data.get('entry_price')}\n"
            f"<b>SL:</b> {trade_data.get('stop_loss')}\n"
            f"<b>TP1:</b> {trade_data.get('take_profit')}\n"
            f"<b>Volume:</b> {trade_data.get('volume')}\n"
            f"<b>Confluence:</b> {trade_data.get('confluence_score')}/10\n"
            f"<b>Time:</b> {trade_data.get('time')}\n"
        )
        
        await self.send_message(message)
