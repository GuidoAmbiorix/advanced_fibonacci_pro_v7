import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from loguru import logger

class RequestIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Generate or get correlation ID (X-Request-ID header)
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        
        # Attach to request logger context
        with logger.contextualize(request_id=request_id):
            response = await call_next(request)
            
            # Return ID in response header
            response.headers["X-Request-ID"] = request_id
            return response
