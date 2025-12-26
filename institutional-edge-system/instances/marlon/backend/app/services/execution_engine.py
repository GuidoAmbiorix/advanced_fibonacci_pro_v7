import asyncio
from sqlalchemy.orm import Session
from app.core.mt5_connector import MT5Connector
from app.models.database import ExecutionLog, Trade
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class ExecutionEngine:
    """
    Robust Execution Engine for MT5.
    Handles:
    - Order Execution with Retries
    - Duplicate Check
    - Logging
    - Slippage Control
    """

    def __init__(self, mt5_connector: MT5Connector, db: Session, sio=None):
        self.mt5 = mt5_connector
        self.db = db
        self.sio = sio

    async def execute_order(self, symbol: str, order_type: str, volume: float, sl: float, tp: float, deviation: int = 10, max_retries: int = 3):
        """
        Execute an order with retry logic.
        """
        # 1. Duplicate Check (Simple check: do we have an open trade for this symbol created < 1 min ago?)
        # This prevents double firing on same signal
        recent_trade = self.db.query(Trade).filter(
            Trade.symbol == symbol,
            Trade.status == "OPEN",
            Trade.opened_at >= datetime.utcnow() - asyncio.timedelta(minutes=1)
        ).first()
        
        if recent_trade:
            logger.warning(f"Skipping duplicate order for {symbol}")
            return {"success": False, "error": "Duplicate order detected"}

        attempt = 0
        while attempt < max_retries:
            try:
                result = self.mt5.open_position(
                    symbol=symbol,
                    order_type=order_type,
                    volume=volume,
                    stop_loss=sl,
                    take_profit=tp,
                    deviation=deviation
                )
                
                if result and result.get('success'):
                    await self._log_execution(symbol, "OPEN", f"Order executed successfully: {result['ticket']}", result)
                    return result
                
                error_msg = result.get('error') if result else "Unknown error"
                logger.warning(f"Order execution failed (Attempt {attempt+1}/{max_retries}): {error_msg}")
                await self._log_execution(symbol, "ERROR", f"Execution failed: {error_msg}", result)
                
            except Exception as e:
                logger.error(f"Exception during execution: {e}")
                await self._log_execution(symbol, "ERROR", f"Exception: {str(e)}")
            
            attempt += 1
            await asyncio.sleep(1) # Wait before retry
            
        return {"success": False, "error": "Max retries exceeded"}

    async def _log_execution(self, symbol: str, action: str, message: str, details: dict = None):
        """Log execution details to DB and Socket"""
        try:
            log = ExecutionLog(
                symbol=symbol,
                action=action,
                message=message,
                details=details,
                timestamp=datetime.utcnow()
            )
            self.db.add(log)
            self.db.commit()
            
            # Emit to socket
            if self.sio:
                await self.sio.emit('bot_activity', {
                    'timestamp': log.timestamp.isoformat(),
                    'level': 'error' if action == 'ERROR' else 'success' if action == 'OPEN' else 'info',
                    'message': f"[{symbol}] {message}"
                })
                
        except Exception as e:
            logger.error(f"Failed to write execution log: {e}")
