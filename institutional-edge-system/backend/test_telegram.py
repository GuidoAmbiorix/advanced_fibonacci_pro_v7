import asyncio
from app.services.telegram_service import TelegramService
from loguru import logger

async def main():
    logger.info("Testing Telegram Service...")
    telegram = TelegramService()
    
    if not telegram.enabled:
        logger.warning("Telegram is DISABLED. Please check TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in .env")
        return

    # 1. Test Message
    logger.info("Sending test message...")
    await telegram.send_message("🔔 **Test Notification**\nThis is a test message from Institutional Edge Pro.")

    # 2. Test Signal
    logger.info("Sending test signal...")
    await telegram.send_signal_alert({
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

    # 3. Test Trade
    logger.info("Sending test trade...")
    await telegram.send_trade_alert({
        'symbol': 'EURUSD',
        'type': 'BUY',
        'volume': 1.0,
        'entry': 1.0500,
        'ticket': 12345678
    })

    logger.info("Test complete.")

if __name__ == "__main__":
    asyncio.run(main())
