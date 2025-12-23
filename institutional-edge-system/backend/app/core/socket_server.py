import socketio
from loguru import logger

# Initialize Socket.IO server
sio = socketio.AsyncServer(
    async_mode='asgi', 
    cors_allowed_origins='*',
    logger=True,
    engineio_logger=True
)

@sio.event
async def connect(sid, environ):
    logger.info(f"Socket connected: {sid}")

@sio.event
async def disconnect(sid):
    logger.info(f"Socket disconnected: {sid}")

@sio.event
async def ping(sid):
    """Heartbeat handler - respond with pong"""
    await sio.emit('pong', room=sid)

