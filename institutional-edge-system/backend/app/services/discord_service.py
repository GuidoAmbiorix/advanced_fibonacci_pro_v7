"""
Discord Notification Service
Sends real-time rich alerts via Discord Webhooks.
"""

import httpx
import asyncio
from typing import Dict, Optional
from loguru import logger
from datetime import datetime
from app.core.config import settings

class DiscordService:
    def __init__(self):
        self.webhook_url = settings.DISCORD_WEBHOOK_URL
        self.signals_webhook_url = settings.DISCORD_WEBHOOK_SIGNALS_URL or self.webhook_url
        
        self.enabled = bool(self.webhook_url)

        if not self.enabled:
            logger.warning("Discord Service disabled: Missing DISCORD_WEBHOOK_URL")
        else:
            logger.info("Discord Service initialized")
            if self.signals_webhook_url != self.webhook_url:
                logger.info("✅ Separate Signals Channel Configured")

    async def send_message(self, content: str = None, embed: Dict = None, webhook_url: str = None):
        """Send a message to Discord"""
        if not self.enabled:
            return

        target_url = webhook_url or self.webhook_url

        try:
            async with httpx.AsyncClient() as client:
                payload = {}
                if content:
                    payload["content"] = content
                if embed:
                    payload["embeds"] = [embed]

                response = await client.post(target_url, json=payload)
                response.raise_for_status()
        except Exception as e:
            logger.error(f"Failed to send Discord message: {e}")

    async def send_signal_alert(self, signal: Dict):
        """Send a rich embed for a new trading signal"""
        if not self.enabled:
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
            "title": "📊 BACKTEST COMPLETE",
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
        """Send a rich embed with current market status"""
        if not self.enabled:
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
            "title": "📊 MARKET STATUS UPDATE",
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
