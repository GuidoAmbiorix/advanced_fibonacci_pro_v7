# Implementation Plan - RabbitMQ Integration

## Goal
Integrate RabbitMQ to decouple the **Analysis** phase (TradingBot) from the **Execution** phase (TradeExecutor). This improves scalability and reliability.

## User Review Required
> [!IMPORTANT]
> **Dependency**: We will install `aio_pika` for async RabbitMQ communication.
> **Infrastructure**: A new Docker container `rabbitmq` will be added. You will need to run `start_all.bat` (or `docker-compose up -d`) to start it.

## Proposed Changes

### [Infrastructure] Docker
#### [MODIFY] [docker-compose.yml](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/docker-compose.yml)
- Add `rabbitmq` service using `rabbitmq:3-management-alpine` image.
- Expose ports `5672` (AMQP) and `15672` (Management UI).

### [Configuration]
#### [MODIFY] [config.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/core/config.py)
- Add `RABBITMQ_HOST`, `RABBITMQ_PORT`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD`.

### [Backend] RabbitMQ Service
#### [NEW] [rabbitmq_service.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/services/rabbitmq_service.py)
- Class `RabbitMQService` using `aio_pika`.
- Method `connect()`: Establishes connection.
- Method `publish_signal(signal_data)`: Publishes to `trade_signals` queue.
- Method `consume_signals(callback)`: Listens to `trade_signals` queue.

### [Backend] Trading Bot (Producer)
#### [MODIFY] [trading_bot.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/services/trading_bot.py)
- Initialize `RabbitMQService`.
- Instead of calling `_execute_signal` directly, call `await self.rabbitmq.publish_signal(signal)`.
- *Note*: For this phase, we will keep direct execution as a fallback or option, but the primary path will be via queue.

### [Backend] Trade Executor (Consumer)
#### [NEW] [worker.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/worker.py)
- A standalone script that:
    1.  Connects to RabbitMQ.
    2.  Connects to MT5.
    3.  Consumes signals.
    4.  Executes trades using `MT5Connector`.

## Verification Plan
1.  **Start RabbitMQ**: Run `docker-compose up -d rabbitmq`.
2.  **Check UI**: Visit `http://localhost:15672` (guest/guest).
3.  **Run Worker**: Start `python worker.py`.
4.  **Run Bot**: Start the bot and verify signals appear in the queue and are consumed by the worker.
