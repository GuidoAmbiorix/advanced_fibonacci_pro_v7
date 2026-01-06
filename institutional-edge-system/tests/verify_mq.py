import asyncio
import os
import json
import uuid
from datetime import datetime
import aio_pika
from loguru import logger

# Config
RABBITMQ_HOST = "localhost" # Assuming port forward or local
RABBITMQ_PORT = 5672
QUEUE_NAME = "trade_signals"

async def main():
    logger.info("🧪 STARTING RABBITMQ VERIFICATION TEST")
    
    # 1. Connect
    try:
        connection = await aio_pika.connect_robust(
            host=RABBITMQ_HOST,
            port=RABBITMQ_PORT
        )
        channel = await connection.channel()
        queue = await channel.declare_queue(QUEUE_NAME, durable=True)
        
        # 2. Publish Mock Signal
        signal = { # mocking trade_data from trading.py
            'action': 'OPEN',
            'ticket': 12345678,
            'symbol': 'XAUUSD',
            'type': 'BUY',
            'volume': 1.0,
            'entry_price': 2000.0,
            'stop_loss': 1990.0,
            'take_profit': 2020.0,
            'session_id': 'test-session',
            'opened_at': datetime.utcnow().isoformat(),
            'master_account_id': 1
        }
        
        logger.info(f"📤 Publishing Test Signal: {signal}")
        
        await channel.default_exchange.publish(
            aio_pika.Message(body=json.dumps(signal).encode()),
            routing_key=QUEUE_NAME
        )
        
        logger.success("✅ Test Signal Published!")
        await connection.close()
        
    except Exception as e:
        logger.error(f"❌ Connection Failed (Is RabbitMQ running?): {e}")

if __name__ == "__main__":
    asyncio.run(main())
