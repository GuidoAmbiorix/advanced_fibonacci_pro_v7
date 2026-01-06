import os
import asyncio
import json
import socket
from datetime import datetime
import aio_pika
from loguru import logger

# Configuration
WORKER_ID = os.getenv("WORKER_ID", "worker-1")
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "guest")
RABBITMQ_PASS = os.getenv("RABBITMQ_PASSWORD", "guest")
QUEUE_NAME = "trade_signals"

async def process_signal(message: aio_pika.IncomingMessage):
    """
    Process incoming trade signal
    """
    async with message.process():
        try:
            data = json.loads(message.body.decode())
            action = data.get('action')
            symbol = data.get('symbol')
            # volume = data.get('volume', 0.01)
            
            logger.info(f"⚡ [WORKER {WORKER_ID}] RECEIVED SIGNAL: {action} {symbol} | Data: {data}")
            
            # SIMULATE EXECUTION
            # In real system, this calls RPyC to MT5 terminal
            logger.info(f"⚙️ [WORKER {WORKER_ID}] Executing {action} on {symbol}...")
            await asyncio.sleep(0.5) # Simulate network/api delay
            logger.success(f"✅ [WORKER {WORKER_ID}] EXECUTION COMPLETE: {action} {symbol}")
            
        except Exception as e:
            logger.error(f"❌ [WORKER {WORKER_ID}] Error processing signal: {e}")

async def main():
    logger.info(f"🚀 Worker {WORKER_ID} starting up on {socket.gethostname()}...")
    
    # Retry Loop for RabbitMQ Connection
    connection = None
    while True:
        try:
            logger.info(f"🔄 Connecting to RabbitMQ at {RABBITMQ_HOST}:{RABBITMQ_PORT}...")
            connection = await aio_pika.connect_robust(
                host=RABBITMQ_HOST,
                port=RABBITMQ_PORT,
                login=RABBITMQ_USER,
                password=RABBITMQ_PASS
            )
            logger.info("✅ Connected to RabbitMQ Broker")
            break
        except Exception as e:
            logger.warning(f"⚠️ Connection failed: {e}. Retrying in 5s...")
            await asyncio.sleep(5)

    # Channel & Queue
    channel = await connection.channel()
    await channel.set_qos(prefetch_count=1)
    
    queue = await channel.declare_queue(QUEUE_NAME, durable=True)
    logger.info(f"🎧 Listening for signals on queue: '{QUEUE_NAME}'...")

    # Consume
    await queue.consume(process_signal)

    try:
        # Keep alive
        await asyncio.Future()
    except asyncio.CancelledError:
        logger.info("Worker stopping...")
        await connection.close()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Worker interrupted by user.")
