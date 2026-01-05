"""
============================================================================
Performance Statistics Endpoints
============================================================================
Provides aggregated performance metrics and trade history
"""

from typing import List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.api import database
from app.models.database import Trade, User
from app.schemas import schemas
from app.core import security

router = APIRouter()

@router.get("/performance", response_model=schemas.PerformanceMetricsResponse)
def get_performance_metrics(
    days: int = 30,
    db: Session = Depends(database.get_db)
):
    """
    Get aggregated performance metrics for the specified period
    """
    # Calculate start date
    start_date = datetime.utcnow() - timedelta(days=days)
    
    # Query trades
    trades = db.query(Trade).filter(
        Trade.opened_at >= start_date,
        Trade.status == "CLOSED"
    ).all()
    
    total_trades = len(trades)
    if total_trades == 0:
        return {
            "date": datetime.utcnow(),
            "total_trades": 0,
            "winning_trades": 0,
            "losing_trades": 0,
            "win_rate": 0.0,
            "net_profit": 0.0,
            "profit_factor": 0.0,
            "largest_win": 0.0,
            "largest_loss": 0.0
        }
        
    winning_trades = [t for t in trades if t.profit_loss > 0]
    losing_trades = [t for t in trades if t.profit_loss <= 0]
    
    total_win_amount = sum(t.profit_loss for t in winning_trades)
    total_loss_amount = abs(sum(t.profit_loss for t in losing_trades))
    
    win_rate = (len(winning_trades) / total_trades) * 100
    net_profit = total_win_amount - total_loss_amount
    
    profit_factor = 0.0
    if total_loss_amount > 0:
        profit_factor = total_win_amount / total_loss_amount
    elif total_win_amount > 0:
        profit_factor = 99.9 # Infinite
        
    largest_win = max([t.profit_loss for t in winning_trades]) if winning_trades else 0.0
    largest_loss = min([t.profit_loss for t in losing_trades]) if losing_trades else 0.0
    
    return {
        "date": datetime.utcnow(),
        "total_trades": total_trades,
        "winning_trades": len(winning_trades),
        "losing_trades": len(losing_trades),
        "win_rate": round(win_rate, 2),
        "net_profit": round(net_profit, 2),
        "profit_factor": round(profit_factor, 2),
        "largest_win": round(largest_win, 2),
        "largest_loss": round(largest_loss, 2)
    }

@router.get("/history", response_model=List[schemas.TradeResponse])
def get_trade_history(
    limit: int = 100,
    offset: int = 0,
    symbol: Optional[str] = None,
    db: Session = Depends(database.get_db)
):
    """
    Get paginated trade history
    """
    query = db.query(Trade).filter(Trade.status == "CLOSED")
    
    if symbol:
        query = query.filter(Trade.symbol == symbol)
        
    trades = query.order_by(Trade.closed_at.desc()).offset(offset).limit(limit).all()
    return trades
