import asyncio
import os
from dotenv import load_dotenv

# Load .env explicitly
load_dotenv()

from app.services.discord_service import DiscordService
from loguru import logger

async def main():
    logger.info("Testing Discord Channels...")
    
    # Debug: Check env vars
    webhook = os.getenv("DISCORD_WEBHOOK_URL")
    signals_webhook = os.getenv("DISCORD_WEBHOOK_SIGNALS_URL")
    
    if webhook:
        logger.info(f"Found Execution Webhook: {webhook[:10]}...")
    else:
        logger.error("Missing DISCORD_WEBHOOK_URL")

    if signals_webhook:
        logger.info(f"Found Signals Webhook: {signals_webhook[:10]}...")
    else:
        logger.warning("Missing DISCORD_WEBHOOK_SIGNALS_URL (Will fallback to default)")

    discord = DiscordService()
    
    if not discord.enabled:
        logger.warning("Discord Service Disabled")
        return

    # 1. Test Signal (Should go to Signals Channel)
    logger.info("Sending Signal Alert (Check Signals Channel)...")
    await discord.send_signal_alert({
        'symbol': 'EURUSD',
        'direction': 'BUY',
        'strategy_type': 'TEST_SIGNAL',
        'entry_price': 1.0500,
        'stop_loss': 1.0480,
        'take_profit': 1.0540,
        'confidence': 0.99,
        'score': 10.0,
        'timestamp': '12:00:00'
    })

    # 2. Test Trade (Should go to Executions Channel)
    logger.info("Sending Trade Alert (Check Executions Channel)...")
    await discord.send_trade_alert({
        'symbol': 'EURUSD',
        'type': 'BUY',
        'volume': 1.0,
        'entry': 1.0500,
        'ticket': 99999999
    })

    logger.info("Test complete.")

if __name__ == "__main__":
    asyncio.run(main())
