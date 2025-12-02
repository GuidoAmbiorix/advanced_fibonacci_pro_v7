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
