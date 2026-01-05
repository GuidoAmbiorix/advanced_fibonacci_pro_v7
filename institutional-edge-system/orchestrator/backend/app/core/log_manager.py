from typing import Deque, Dict, Any, List
from collections import deque
from loguru import logger
from app.core.socket_server import sio
import asyncio

class LogManager:
    """
    Manages system logs:
    1. Buffers last N logs in memory
    2. Streams new logs via WebSocket (system_log event)
    """
    def __init__(self, max_len: int = 1000):
        self.buffer: Deque[Dict[str, Any]] = deque(maxlen=max_len)
    
    async def sink(self, message):
        """
        Async sink for loguru.
        Receives the message object from loguru which contains the .record dict.
        """
        try:
            record = message.record
            
            # Format log entry
            log_entry = {
                "timestamp": record["time"].isoformat(),
                "level": record["level"].name,
                "message": record["message"],
                "module": record["module"],
                "line": record["line"],
                "function": record["function"],
                "process": record["process"].name,
                "thread": record["thread"].name
            }
            
            # 1. Store in buffer
            self.buffer.append(log_entry)
            
            # 2. Stream to clients (fire and forget to avoid modifying log flow)
            # We use emit without await if possible or ensure it doesn't block logging significantly
            # Since this is an async sink, 'await' is expected.
            await sio.emit('system_log', log_entry)
            
        except Exception as e:
            # Fallback for safety - print to raw stderr if needed, but avoid recursion
            pass

# Singleton instance
log_manager = LogManager()
