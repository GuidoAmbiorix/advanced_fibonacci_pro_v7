import aio_pika
import json
import asyncio
from loguru import logger
from app.core.config import settings

class RabbitMQService:
    def __init__(self):
        self.connection = None
        self.channel = None
        self.exchange = None
        self.queue_name = "trade_signals"

    async def connect(self, max_retries=5, retry_delay=2):
        """Connect to RabbitMQ with retry logic"""
        for attempt in range(max_retries):
            try:
                logger.info(f"🔄 Connecting to RabbitMQ (attempt {attempt + 1}/{max_retries})...")
                self.connection = await aio_pika.connect_robust(
                    host=settings.RABBITMQ_HOST,
                    port=settings.RABBITMQ_PORT,
                    login=settings.RABBITMQ_USER,
                    password=settings.RABBITMQ_PASSWORD
                )
                self.channel = await self.connection.channel()

                # Declare queue
                self.queue = await self.channel.declare_queue(
                    self.queue_name,
                    durable=True
                )

                logger.info("✅ Connected to RabbitMQ")
                return
            except Exception as e:
                logger.warning(f"⚠️ RabbitMQ Connection attempt {attempt + 1} failed: {e}")
                if attempt < max_retries - 1:
                    await asyncio.sleep(retry_delay)
                else:
                    logger.error(f"❌ RabbitMQ Connection Failed after {max_retries} attempts")
                    # Don't raise, just log. We might be running without RMQ in dev.

    async def publish_signal(self, signal_data: dict):
        """Publish a signal to the queue"""
        if not self.channel:
            await self.connect()
            
        if not self.channel:
            logger.warning("RabbitMQ not connected, skipping publish")
            return

        try:
            message = aio_pika.Message(
                body=json.dumps(signal_data).encode(),
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT
            )
            
            await self.channel.default_exchange.publish(
                message,
                routing_key=self.queue_name
            )
            logger.info(f"📤 Published signal to {self.queue_name}")
        except Exception as e:
            logger.error(f"Failed to publish signal: {e}")

    async def consume_signals(self, callback):
        """Consume signals from the queue"""
        if not self.channel:
            await self.connect()
            
        if not self.channel:
            return

        async with self.queue.iterator() as queue_iter:
            async for message in queue_iter:
                async with message.process():
                    data = json.loads(message.body.decode())
                    await callback(data)

    async def close(self):
        if self.connection:
            await self.connection.close()
