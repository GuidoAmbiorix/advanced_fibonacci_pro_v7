from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from app.api import database
from app.models.database import ExecutionLog

router = APIRouter()

@router.get("/")
async def get_logs(limit: int = 100, symbol: str = None, db: Session = Depends(database.get_db)):
    query = db.query(ExecutionLog)
    if symbol:
        query = query.filter(ExecutionLog.symbol == symbol)
    
    logs = query.order_by(ExecutionLog.timestamp.desc()).limit(limit).all()
    return logs

@router.get("/system")
async def get_system_logs():
    """Get recent system logs (stdout/stderr) from memory buffer"""
    from app.core.log_manager import log_manager
    # Convert deque to list
    return list(log_manager.buffer)
