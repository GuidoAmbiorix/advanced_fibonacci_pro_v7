import asyncio
import os
from dotenv import load_dotenv

# Load .env explicitly
load_dotenv()

from app.services.discord_service import DiscordService
from loguru import logger

async def main():
    logger.info("Testing Discord Service...")
    
    # Debug: Check env var (masked)
    webhook = os.getenv("DISCORD_WEBHOOK_URL")
    if webhook:
        masked = webhook[:10] + "..." + webhook[-5:]
        logger.info(f"Found Webhook URL: {masked}")
    else:
        logger.error("DISCORD_WEBHOOK_URL not found in environment variables!")
        logger.info(f"Current CWD: {os.getcwd()}")
        logger.info(f".env exists? {os.path.exists('.env')}")

    discord = DiscordService()
    
    if not discord.enabled:
        logger.warning("Discord is DISABLED. Please check DISCORD_WEBHOOK_URL in .env")
        return

    # 1. Test Message
    logger.info("Sending test message...")
    await discord.send_message(content="🔔 **Test Notification**\nThis is a test message from Institutional Edge Pro.")

    # 2. Test Signal Embed
    logger.info("Sending test signal...")
    await discord.send_signal_alert({
        'symbol': 'EURUSD',
        'direction': 'BUY',
        'strategy_type': 'INSTITUTIONAL_SWEEP',
        'entry_price': 1.0500,
        'stop_loss': 1.0480,
        'take_profit': 1.0540,
        'confidence': 0.95,
        'score': 9.8,
        'timestamp': '12:00:00'
    })

    # 3. Test Trade Embed
    logger.info("Sending test trade...")
    await discord.send_trade_alert({
        'symbol': 'EURUSD',
        'type': 'BUY',
        'volume': 1.0,
        'entry': 1.0500,
        'ticket': 12345678
    })

    logger.info("Test complete.")

if __name__ == "__main__":
    asyncio.run(main())
