"""
Telegram Notification Service
Sends real-time alerts for signals, trades, and backtest results.
"""

import httpx
import asyncio
from typing import Dict, Optional
from loguru import logger
from app.core.config import settings

class TelegramService:
    def __init__(self):
        self.token = settings.TELEGRAM_BOT_TOKEN
        self.chat_id = settings.TELEGRAM_CHAT_ID
        self.base_url = f"https://api.telegram.org/bot{self.token}"
        self.enabled = bool(self.token and self.chat_id)

        if not self.enabled:
            logger.warning("Telegram Service disabled: Missing token or chat_id")
        else:
            logger.info("Telegram Service initialized")

    async def send_message(self, text: str):
        """Send a raw text message to Telegram"""
        if not self.enabled:
            return

        try:
            async with httpx.AsyncClient() as client:
                payload = {
                    "chat_id": self.chat_id,
                    "text": text,
                    "parse_mode": "Markdown"
                }
                response = await client.post(f"{self.base_url}/sendMessage", json=payload)
                response.raise_for_status()
        except Exception as e:
            logger.error(f"Failed to send Telegram message: {e}")

    async def send_signal_alert(self, signal: Dict):
        """Send a formatted alert for a new trading signal"""
        if not self.enabled:
            return

        # Emoji based on direction
        icon = "🟢" if signal.get('direction') == "BUY" else "🔴"
        
        message = (
            f"{icon} **NEW SIGNAL: {signal.get('symbol')}**\n"
            f"Type: {signal.get('direction')} ({signal.get('strategy_type')})\n"
            f"Entry: `{signal.get('entry_price')}`\n"
            f"SL: `{signal.get('stop_loss')}`\n"
            f"TP: `{signal.get('take_profit')}`\n"
            f"Confidence: {signal.get('confidence', 0)*100:.1f}%\n"
            f"Score: {signal.get('score', 0)}/10\n"
            f"Time: {signal.get('timestamp')}"
        )
        await self.send_message(message)

    async def send_trade_alert(self, trade: Dict):
        """Send a formatted alert for an executed trade"""
        if not self.enabled:
            return

        icon = "🚀"
        message = (
            f"{icon} **TRADE EXECUTED**\n"
            f"Symbol: {trade.get('symbol')}\n"
            f"Type: {trade.get('type')}\n"
            f"Volume: {trade.get('volume')} lots\n"
            f"Price: `{trade.get('entry')}`\n"
            f"Ticket: `{trade.get('ticket')}`"
        )
        await self.send_message(message)

    async def send_backtest_summary(self, metrics):
        """Send a summary of backtest results"""
        if not self.enabled:
            return

        icon = "✅" if metrics.net_profit > 0 else "❌"
        message = (
            f"{icon} **BACKTEST COMPLETE**\n"
            f"Net Profit: ${metrics.net_profit:.2f}\n"
            f"Win Rate: {metrics.win_rate:.1f}%\n"
            f"Profit Factor: {metrics.profit_factor:.2f}\n"
            f"Drawdown: {metrics.max_drawdown_percent:.1f}%\n"
            f"Total Trades: {metrics.total_trades}"
        )
        await self.send_message(message)
