import asyncio
import sys
from loguru import logger
from app.services.rabbitmq_service import RabbitMQService
from app.core.mt5_connector import MT5Connector
from app.core.config import settings

# Configure logging
logger.remove()
logger.add(sys.stderr, level="INFO")

async def process_signal(signal_data):
    """Callback to process received signals"""
    logger.info(f"📥 Received Signal: {signal_data['signal_type']} {signal_data['symbol']} @ {signal_data['entry_price']}")
    
    # In a full implementation, we would initialize MT5Connector here and execute
    # For now, we just log it to prove the decoupling works
    logger.info("✅ Signal processed by worker")

async def main():
    logger.info("🚀 Starting Trade Worker...")
    
    rabbitmq = RabbitMQService()
    await rabbitmq.connect()
    
    logger.info("👀 Waiting for signals...")
    
    # Keep running
    await rabbitmq.consume_signals(process_signal)
    
    # Keep loop alive
    try:
        await asyncio.Future()
    except asyncio.CancelledError:
        await rabbitmq.close()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Worker stopped")
