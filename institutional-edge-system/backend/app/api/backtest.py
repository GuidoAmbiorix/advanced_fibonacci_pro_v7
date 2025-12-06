from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from fastapi.encoders import jsonable_encoder
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel

from app.api import database
from app.models.database import BacktestSession, BacktestTrade
from app.backtesting.engine import BacktestEngine
from app.backtesting.models import BacktestConfig
from app.core.socket import sio
from loguru import logger
import asyncio

router = APIRouter()

# --- Schemas ---
class BacktestRequest(BaseModel):
    symbol: str
    timeframe: str
    start_date: datetime
    end_date: datetime
    initial_balance: float = 1000.0
    risk_percent: float = 1.0
    strategy_mode: str = "SWING" # SWING, SCALP
    use_adx_filter: bool = True
    
class BacktestResponse(BaseModel):
    session_id: int
    status: str
    message: str

# --- Background Task ---
def run_backtest_task(session_id: int, request: BacktestRequest, db: Session, loop: asyncio.AbstractEventLoop):
    try:
        logger.info(f"Starting backtest session {session_id} for {request.symbol}")
        
        # Define Callbacks
        def on_progress(pct, stats):
            asyncio.run_coroutine_threadsafe(
                sio.emit('backtest_progress', {
                    'session_id': session_id,
                    'progress': pct,
                    'stats': stats
                }),
                loop
            )

        def on_trade(trade_data):
            asyncio.run_coroutine_threadsafe(
                sio.emit('backtest_trade', {
                    'session_id': session_id,
                    'trade': trade_data
                }),
                loop
            )

        # 1. Update status to RUNNING
        session = db.query(BacktestSession).filter(BacktestSession.id == session_id).first()
        if not session:
            return
            
        # 2. Configure Engine
        config = BacktestConfig(
            symbol=request.symbol,
            timeframe=request.timeframe,
            start_date=request.start_date,
            end_date=request.end_date,
            initial_balance=request.initial_balance,
            risk_percent=request.risk_percent,
            scalping_mode=(request.strategy_mode == "SCALP"),
            # Add other defaults
            min_confluence_score=7,
            max_trades=3 if request.strategy_mode == "SWING" else 5
        )
        
        engine = BacktestEngine(config)
        
        # 3. Run Backtest
        results = engine.run(
            on_progress=on_progress,
            on_trade=on_trade
        )
        
        # 4. Save Results to DB
        # Calculate final balance
        final_balance = config.initial_balance + results.metrics.net_profit
        
        session.final_balance = final_balance
        session.total_trades = results.metrics.total_trades
        session.win_rate = results.metrics.win_rate
        session.profit_factor = results.metrics.profit_factor
        session.max_drawdown = results.metrics.max_drawdown_percent
        session.net_profit = results.metrics.net_profit
        session.status = "COMPLETED"
        
        # Save Trades
        for trade in results.trades:
            db_trade = BacktestTrade(
                session_id=session.id,
                symbol=trade.symbol,
                trade_type=trade.signal_type,
                entry_time=trade.entry_time,
                exit_time=trade.exit_time,
                entry_price=trade.entry_price,
                exit_price=trade.exit_price,
                stop_loss=trade.stop_loss,
                take_profit=trade.take_profit,
                volume=trade.volume,
                profit=trade.pnl,
                balance_after=trade.balance_after,
                confluence_score=trade.confluence_score
            )
            db.add(db_trade)
            
        db.commit()
        logger.info(f"Backtest session {session_id} completed successfully")
        
        # Emit completion event
        asyncio.run_coroutine_threadsafe(
            sio.emit('backtest_complete', {
                'session_id': session_id,
                'results': {
                    'net_profit': results.metrics.net_profit,
                    'win_rate': results.metrics.win_rate,
                    'profit_factor': results.metrics.profit_factor,
                    'max_drawdown': results.metrics.max_drawdown_percent,
                    'total_trades': results.metrics.total_trades
                }
            }),
            loop
        )
        
        
    except Exception as e:
        logger.exception(f"Backtest session {session_id} failed: {e}")
        session = db.query(BacktestSession).filter(BacktestSession.id == session_id).first()
        if session:
            session.status = "FAILED"
            db.commit()

# --- Endpoints ---

@router.post("/run", response_model=BacktestResponse)
async def run_backtest(
    request: BacktestRequest, 
    background_tasks: BackgroundTasks,
    db: Session = Depends(database.get_db)
):
    """Start a new backtest session"""
    
    # Create Session Record
    new_session = BacktestSession(
        symbol=request.symbol,
        timeframe=request.timeframe,
        start_date=request.start_date,
        end_date=request.end_date,
        initial_balance=request.initial_balance,
        strategy_config=jsonable_encoder(request.dict()),
        status="PENDING"
    )
    
    db.add(new_session)
    db.commit()
    db.refresh(new_session)
    
    # Start Background Task
    # We need a new DB session for the background task to avoid threading issues
    # But for simplicity in this setup, we'll let the task create its own or pass the ID
    # Ideally, use a proper task queue (Celery/RabbitMQ), but BackgroundTasks works for simple cases
    
    # Note: Passing 'db' here is risky if the request closes. 
    # Better to create a new session inside the task.
    # We will modify the task to create its own session.
    
    # Get current event loop to pass to background task
    loop = asyncio.get_running_loop()
    
    background_tasks.add_task(run_backtest_wrapper, new_session.id, request, loop)
    
    return {
        "session_id": new_session.id,
        "status": "PENDING",
        "message": "Backtest started in background"
    }

def run_backtest_wrapper(session_id: int, request: BacktestRequest, loop: asyncio.AbstractEventLoop):
    """Wrapper to handle DB session for background task"""
    db = database.SessionLocal()
    try:
        run_backtest_task(session_id, request, db, loop)
    finally:
        db.close()

@router.get("/history")
async def get_backtest_history(limit: int = 20, db: Session = Depends(database.get_db)):
    """Get recent backtest sessions"""
    sessions = db.query(BacktestSession).order_by(BacktestSession.created_at.desc()).limit(limit).all()
    return sessions

@router.get("/{session_id}")
async def get_backtest_details(session_id: int, db: Session = Depends(database.get_db)):
    """Get full details of a backtest session including trades"""
    session = db.query(BacktestSession).filter(BacktestSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Backtest session not found")
        
    return {
        "session": session,
        "trades": session.trades
    }
