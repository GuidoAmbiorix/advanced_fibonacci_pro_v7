"""
Discord Notification Service
Sends real-time rich alerts via Discord Webhooks.
Includes rate limiting to avoid 429 errors.
"""

import httpx
import asyncio
from typing import Dict, Optional
from loguru import logger
from datetime import datetime
from app.core.config import settings

class DiscordService:
    # Rate limiting settings
    MIN_MESSAGE_INTERVAL = 5.0  # Minimum seconds between messages
    MAX_RETRIES = 3
    RETRY_BASE_DELAY = 2.0  # Base delay for exponential backoff
    MIN_SIGNAL_SCORE = 7  # Only send signals with score >= 7

    def __init__(self):
        self.webhook_url = settings.DISCORD_WEBHOOK_URL
        self.signals_webhook_url = settings.DISCORD_WEBHOOK_SIGNALS_URL or self.webhook_url
        
        self.enabled = bool(self.webhook_url)
        self._last_message_time: float = 0  # Track last message time

        if not self.enabled:
            logger.warning("Discord Service disabled: Missing DISCORD_WEBHOOK_URL")
        else:
            logger.info("Discord Service initialized (Rate limit: 1 msg per {}s)".format(self.MIN_MESSAGE_INTERVAL))
            if self.signals_webhook_url != self.webhook_url:
                logger.info("R Separate Signals Channel Configured")

    async def _wait_for_rate_limit(self):
        """Wait if we're sending messages too fast"""
        import time
        now = time.time()
        elapsed = now - self._last_message_time
        if elapsed < self.MIN_MESSAGE_INTERVAL:
            wait_time = self.MIN_MESSAGE_INTERVAL - elapsed
            logger.debug(f"Rate limiting: waiting {wait_time:.1f}s before Discord message")
            await asyncio.sleep(wait_time)
        self._last_message_time = time.time()

    async def send_message(self, content: str = None, embed: Dict = None, webhook_url: str = None):
        """Send a message to Discord with rate limiting and retry logic"""
        if not self.enabled:
            return

        target_url = webhook_url or self.webhook_url

        # Apply rate limiting
        await self._wait_for_rate_limit()

        for attempt in range(self.MAX_RETRIES):
            try:
                async with httpx.AsyncClient() as client:
                    payload = {}
                    if content:
                        payload["content"] = content
                    if embed:
                        payload["embeds"] = [embed]

                    response = await client.post(target_url, json=payload)
                    
                    # Handle rate limiting (429)
                    if response.status_code == 429:
                        retry_after = float(response.headers.get("Retry-After", self.RETRY_BASE_DELAY * (2 ** attempt)))
                        logger.warning(f"Discord rate limited (429). Retry after {retry_after}s (attempt {attempt + 1}/{self.MAX_RETRIES})")
                        await asyncio.sleep(retry_after)
                        continue
                    
                    response.raise_for_status()
                    return  # Success

            except httpx.HTTPStatusError as e:
                if e.response.status_code == 429:
                    # Already handled above, but just in case
                    await asyncio.sleep(self.RETRY_BASE_DELAY * (2 ** attempt))
                    continue
                logger.error(f"Discord HTTP error: {e}")
                break
            except Exception as e:
                logger.error(f"Failed to send Discord message: {e}")
                break

    async def send_signal_alert(self, signal: Dict):
        """Send a rich embed for a new trading signal (only high-quality signals)"""
        if not self.enabled:
            return

        # Only send alerts for high-quality signals (score >= MIN_SIGNAL_SCORE)
        score = signal.get('score', 0)
        if score < self.MIN_SIGNAL_SCORE:
            logger.debug(f"Skipping Discord alert for low-score signal: {score}/10 < {self.MIN_SIGNAL_SCORE}")
            return

        # Color: Green for BUY, Red for SELL
        color = 0x00FF00 if signal.get('direction') == "BUY" else 0xFF0000
        
        embed = {
            "title": f"⚡ NEW SIGNAL: {signal.get('symbol')}",
            "description": f"**{signal.get('direction')}** ({signal.get('strategy_type')})",
            "color": color,
            "fields": [
                {"name": "Entry", "value": f"`{signal.get('entry_price')}`", "inline": True},
                {"name": "Stop Loss", "value": f"`{signal.get('stop_loss')}`", "inline": True},
                {"name": "Take Profit", "value": f"`{signal.get('take_profit')}`", "inline": True},
                {"name": "Confidence", "value": f"{signal.get('confidence', 0)*100:.1f}%", "inline": True},
                {"name": "Score", "value": f"{signal.get('score', 0)}/10", "inline": True},
                {"name": "Time", "value": f"{signal.get('timestamp')}", "inline": True}
            ],
            "footer": {"text": "Institutional Edge Pro"}
        }
        # Use signals webhook
        await self.send_message(embed=embed, webhook_url=self.signals_webhook_url)

    async def send_trade_alert(self, trade: Dict):
        """Send a rich embed for an executed trade"""
        if not self.enabled:
            return

        # Color: Blue for Execution
        color = 0x0099FF
        
        embed = {
            "title": "🚀 TRADE EXECUTED",
            "description": f"Opened **{trade.get('type')}** on **{trade.get('symbol')}**",
            "color": color,
            "fields": [
                {"name": "Price", "value": f"`{trade.get('entry')}`", "inline": True},
                {"name": "Volume", "value": f"{trade.get('volume')} lots", "inline": True},
                {"name": "Ticket", "value": f"`{trade.get('ticket')}`", "inline": True}
            ],
            "footer": {"text": "Institutional Edge Pro"}
        }
        await self.send_message(embed=embed)

    async def send_backtest_summary(self, metrics):
        """Send a rich embed for backtest results"""
        if not self.enabled:
            return

        # Color: Gold for Profit, Grey for Loss
        color = 0xFFD700 if metrics.net_profit > 0 else 0x808080
        
        embed = {
            "title": "R BACKTEST COMPLETE",
            "description": f"Results for **{metrics.total_trades}** trades",
            "color": color,
            "fields": [
                {"name": "Net Profit", "value": f"${metrics.net_profit:.2f}", "inline": True},
                {"name": "Win Rate", "value": f"{metrics.win_rate:.1f}%", "inline": True},
                {"name": "Profit Factor", "value": f"{metrics.profit_factor:.2f}", "inline": True},
                {"name": "Drawdown", "value": f"{metrics.max_drawdown_percent:.1f}%", "inline": True},
                {"name": "Avg R:R", "value": f"{metrics.average_rr:.2f}", "inline": True}
            ],
            "footer": {"text": "Institutional Edge Pro"}
        }
        await self.send_message(embed=embed)

    async def send_market_status_update(self, analysis: Dict):
        """Send a rich embed with current market status (only when signals exist)"""
        if not self.enabled:
            return

        # Only send market status if there are signals to reduce spam
        signals = analysis.get('signals', [])
        if len(signals) == 0:
            logger.debug("Skipping market status update - no signals")
            return

        # Color: Grey (Neutral) by default
        color = 0x808080
        
        bull_score = analysis.get('bull_confluence_score', 0)
        bear_score = analysis.get('bear_confluence_score', 0)
        
        # Determine color based on dominant bias
        if bull_score > bear_score and bull_score >= 5.0:
            color = 0x00FF00 # Green
        elif bear_score > bull_score and bear_score >= 5.0:
            color = 0xFF0000 # Red

        embed = {
            "title": "R MARKET STATUS UPDATE",
            "description": f"Analysis for **{analysis.get('symbol', 'UNKNOWN')}** ({analysis.get('timeframe', 'UNKNOWN')})",
            "color": color,
            "fields": [
                {"name": "Regime", "value": f"{analysis.get('market_regime', 'UNKNOWN')}", "inline": True},
                {"name": "Trend (H4)", "value": f"{analysis.get('higher_tf_trend', 'UNKNOWN')}", "inline": True},
                {"name": "\u200b", "value": "\u200b", "inline": True}, # Spacer
                {"name": "Bull Score", "value": f"**{bull_score:.1f}/10**", "inline": True},
                {"name": "Bear Score", "value": f"**{bear_score:.1f}/10**", "inline": True},
                {"name": "Signals", "value": f"{len(analysis.get('signals', []))}", "inline": True}
            ],
            "footer": {"text": f"Institutional Edge Pro • {datetime.utcnow().strftime('%H:%M UTC')}"}
        }
        # Send to main webhook (not signals channel)
        await self.send_message(embed=embed)
