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
from app.core.socket_server import sio
from loguru import logger
import asyncio

router = APIRouter()

# --- Schemas ---
class BacktestRequest(BaseModel):
    symbol: str
    timeframe: str
    confirmation_timeframe: Optional[str] = None  # Higher TF for trend confirmation (auto-set if None)
    start_date: datetime
    end_date: datetime
    initial_balance: float = 100000.0
    risk_percent: float = 1.0
    strategy_mode: str = "SWING" # SWING, SCALP
    direction_filter: str = "BOTH"  # "BOTH", "BUY_ONLY", "SELL_ONLY"
    use_adx_filter: bool = True
    # Strategy Selection
    enable_vwap_strategy: bool = True
    enable_stoch_strategy: bool = True
    enable_institutional_strategy: bool = True
    enable_fibonacci_strategy: bool = True
    enable_strategy_3_29_162: bool = True
    # RSI Settings
    rsi_period: int = 14
    rsi_overbought: int = 70
    rsi_oversold: int = 30
    # Trailing Stop Loss Settings
    enable_trailing_stop: bool = False
    tsl_mode: str = "TIERED"  # FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
    tsl_activation_r: float = 0.0
    # Advanced TSL Parameters
    tsl_atr_period: int = 14
    tsl_atr_multiplier: float = 1.5
    tsl_chandelier_period: int = 22
    tsl_chandelier_mult: float = 3.0
    tsl_swing_lookback: int = 10
    tsl_swing_buffer_atr: float = 0.5
    tsl_psar_af_start: float = 0.02
    tsl_psar_af_increment: float = 0.02
    tsl_psar_af_max: float = 0.20
    # Partial Take Profit
    partial_tp_on: bool = False
    partial_tp_amount: float = 0.5
    # Scalping TP/SL Configuration
    tp_ratio: float = 1.5  # Use 1.0-1.2 for faster scalping
    sl_atr_multiplier: float = 1.5  # Use 1.0 for tighter SL
    max_trade_duration_hours: float = 0.0  # 0 = disabled, 0.5-2 for scalping
    # Signal Quality
    min_confluence_score: int = 7  # 3-10, higher = stronger signals only
    
    # Institutional Control
    use_daily_bias: bool = False
    
    # Engine Config
    engine_type: str = "XAU_PRO"
    engine_config: Optional[dict] = {}

class BacktestResponse(BaseModel):
    session_id: int
    status: str
    message: str
    metrics: Optional[dict] = None
    equity_curve: Optional[List[float]] = None

@router.post("/run", response_model=BacktestResponse)
async def run_backtest(
    request: BacktestRequest, 
    background_tasks: BackgroundTasks,
    db: Session = Depends(database.get_db)
):
    """Start a new backtest session (Synchronous for UI Simplicity)"""
    
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
    
    try:
        # Run Synchronously for MVP
        # ... (Duplicate logic or reuse function? reusing logic inline for speed)
        
        htf_map = {'M1': 'M5', 'M5': 'M15', 'M15': 'H1', 'H1': 'H4', 'H4': 'D1', 'D1': 'W1'}
        confirmation_tf = request.confirmation_timeframe or htf_map.get(request.timeframe, 'H4')

        config = BacktestConfig(
            symbol=request.symbol,
            timeframe=request.timeframe,
            confirmation_timeframe=confirmation_tf,
            start_date=request.start_date,
            end_date=request.end_date,
            initial_balance=request.initial_balance,
            risk_percent=request.risk_percent,
            scalping_mode=(request.strategy_mode == "SCALP"),
            direction_filter=request.direction_filter,
            engine_type=request.engine_type,
            engine_config=request.engine_config or {},
            use_adx_filter=request.use_adx_filter,
            enable_vwap_strategy=request.enable_vwap_strategy,
            enable_stoch_strategy=request.enable_stoch_strategy,
            enable_institutional_strategy=request.enable_institutional_strategy,
            enable_fibonacci_strategy=request.enable_fibonacci_strategy,
            enable_strategy_3_29_162=request.enable_strategy_3_29_162,
            rsi_period=request.rsi_period,
            rsi_overbought=request.rsi_overbought,
            rsi_oversold=request.rsi_oversold,
            enable_trailing_stop=request.enable_trailing_stop,
            tsl_mode=request.tsl_mode,
            tsl_activation_r=request.tsl_activation_r,
            min_confluence_score=request.min_confluence_score,
            use_daily_bias=request.use_daily_bias,
            max_trades=100  # Higher limit for backtest
        )
        
        engine = BacktestEngine(config)
        results = engine.run() # Sync call
        
        # Update DB
        new_session.final_balance = config.initial_balance + results.metrics.net_profit
        new_session.net_profit = results.metrics.net_profit
        new_session.total_trades = results.metrics.total_trades
        new_session.win_rate = results.metrics.win_rate
        new_session.max_drawdown = results.metrics.max_drawdown_percent
        new_session.status = "COMPLETED"
        db.commit()
        
        return {
            "session_id": new_session.id,
            "status": "COMPLETED",
            "message": "Backtest finished successfully",
            "metrics": {
                "netProfit": results.metrics.net_profit,
                "winRate": results.metrics.win_rate,
                "maxDrawdown": results.metrics.max_drawdown_percent,
                "totalTrades": results.metrics.total_trades
            },
            "equity_curve": results.equity_curve
        }
        
    except Exception as e:
        logger.error(f"Backtest Error: {e}")
        new_session.status = "FAILED"
        db.commit()
        raise HTTPException(status_code=500, detail=str(e))

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
    
    # Sanitize for JSON (handle infinity from DB)
    sanitized_sessions = []
    for s in sessions:
        # Convert to dict to avoid SQLAlchemy state issues if we modified objects directly
        # But we can try modifying if detached or just careful. 
        # Safest is to handle at serialization or just patch the object if it's transient here.
        if s.profit_factor == float('inf'):
            s.profit_factor = 999.0
        if s.profit_factor == float('-inf'): # unlikely for PF
            s.profit_factor = 0.0
            
        sanitized_sessions.append(s)
        
    return sanitized_sessions

@router.get("/{session_id}")
async def get_backtest_details(session_id: int, db: Session = Depends(database.get_db)):
    """Get full details of a backtest session including trades"""
    session = db.query(BacktestSession).filter(BacktestSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Backtest session not found")
        
    if session.profit_factor == float('inf'):
         session.profit_factor = 999.0
         
    return {
        "session": session,
        "trades": session.trades
    }
