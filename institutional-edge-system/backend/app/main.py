"""
============================================================================
INSTITUTIONAL EDGE PRO - FastAPI Main Application
============================================================================
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from typing import List, Dict
import asyncio
from datetime import datetime, timedelta
from loguru import logger

from app.core.config import settings
from app.core.trading_engine import TradingEngine
from app.core.mt5_connector import MT5Connector
from app.schemas import schemas
from app.models.database import Base, User, BotConfig, Trade
from app.api import database

# ============================================================================
# APPLICATION SETUP
# ============================================================================

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Professional Trading System with Smart Money Concepts",
)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# OAuth2
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# Global instances
mt5_connector: MT5Connector = None
trading_engines: Dict[int, TradingEngine] = {}  # bot_config_id -> TradingEngine
active_websockets: List[WebSocket] = []

# ============================================================================
# STARTUP & SHUTDOWN
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """Initialize on startup"""
    logger.info("Starting Institutional Edge Pro API...")

    # Create database tables
    database.init_db()

    # Initialize MT5 connector
    global mt5_connector
    mt5_config = {
        'mt5_login': settings.MT5_LOGIN,
        'mt5_password': settings.MT5_PASSWORD,
        'mt5_server': settings.MT5_SERVER,
        'mt5_path': settings.MT5_PATH,
    }

    mt5_connector = MT5Connector(mt5_config)

    if settings.MT5_LOGIN:
        connected = mt5_connector.connect()
        if connected:
            logger.info("MT5 connected successfully")
        else:
            logger.warning("MT5 connection failed - running in demo mode")

    logger.info("API started successfully on {}:{}", settings.HOST, settings.PORT)


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("Shutting down...")

    if mt5_connector:
        mt5_connector.disconnect()

    logger.info("Shutdown complete")


# ============================================================================
# HEALTH CHECK
# ============================================================================

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running",
        "mt5_connected": mt5_connector.connected if mt5_connector else False,
    }


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow(),
        "mt5_status": "connected" if (mt5_connector and mt5_connector.connected) else "disconnected",
    }


# ============================================================================
# MT5 ENDPOINTS
# ============================================================================

@app.get("/api/mt5/account", response_model=schemas.AccountInfoResponse)
async def get_account_info():
    """Get MT5 account information"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    account_info = mt5_connector.get_account_info()
    if not account_info:
        raise HTTPException(status_code=500, detail="Failed to get account info")

    return account_info


@app.get("/api/mt5/price/{symbol}")
async def get_current_price(symbol: str):
    """Get current price for symbol"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    price_data = mt5_connector.get_current_price(symbol)
    if not price_data:
        raise HTTPException(status_code=404, detail=f"Symbol {symbol} not found")

    return price_data


@app.get("/api/mt5/positions")
async def get_open_positions(symbol: str = None):
    """Get open positions"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    positions = mt5_connector.get_open_positions(symbol)
    return {"positions": positions, "count": len(positions)}


# ============================================================================
# TRADING ANALYSIS ENDPOINTS
# ============================================================================

@app.get("/api/analysis/{symbol}/{timeframe}", response_model=schemas.AnalysisResponse)
async def analyze_market(symbol: str, timeframe: str):
    """
    Analyze market and get trading signals

    Example: /api/analysis/EURUSD/H1
    """
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    # Get OHLCV data
    df = mt5_connector.get_ohlcv_data(symbol, timeframe, bars=500)
    if df is None or len(df) == 0:
        raise HTTPException(status_code=404, detail=f"No data available for {symbol}")

    # Create trading engine config
    config = {
        'symbol': symbol,
        'timeframe': timeframe,
        'swing_length': 10,
        'ob_lookback': 50,
        'fvg_min_size': 0.3,
        'min_confluence_score': settings.MIN_CONFLUENCE_SCORE,
        'vp_lookback': 100,
        'vp_rows': 24,
        'value_area_percent': 70,
    }

    # Analyze
    engine = TradingEngine(config)
    analysis = engine.analyze(df)

    if 'error' in analysis:
        raise HTTPException(status_code=400, detail=analysis['error'])

    return analysis


# ============================================================================
# BOT CONTROL ENDPOINTS
# ============================================================================

@app.post("/api/bot/start")
async def start_bot(request: schemas.BotStartRequest, db: Session = Depends(database.get_db)):
    """Start trading bot"""
    # Get bot config from database
    bot_config = db.query(BotConfig).filter(BotConfig.id == request.bot_config_id).first()
    if not bot_config:
        raise HTTPException(status_code=404, detail="Bot configuration not found")

    # Mark as active
    bot_config.is_active = True
    db.commit()

    logger.info("Bot {} started for symbol {} {}", bot_config.name, bot_config.symbol, bot_config.timeframe)

    return {
        "success": True,
        "message": f"Bot {bot_config.name} started successfully",
        "bot_config_id": bot_config.id,
    }


@app.post("/api/bot/stop")
async def stop_bot(request: schemas.BotStopRequest, db: Session = Depends(database.get_db)):
    """Stop trading bot"""
    bot_config = db.query(BotConfig).filter(BotConfig.id == request.bot_config_id).first()
    if not bot_config:
        raise HTTPException(status_code=404, detail="Bot configuration not found")

    bot_config.is_active = False
    db.commit()

    logger.info("Bot {} stopped", bot_config.name)

    return {
        "success": True,
        "message": f"Bot {bot_config.name} stopped successfully",
        "bot_config_id": bot_config.id,
    }


@app.get("/api/bot/status/{bot_config_id}", response_model=schemas.BotStatusResponse)
async def get_bot_status(bot_config_id: int, db: Session = Depends(database.get_db)):
    """Get bot status"""
    bot_config = db.query(BotConfig).filter(BotConfig.id == bot_config_id).first()
    if not bot_config:
        raise HTTPException(status_code=404, detail="Bot configuration not found")

    # Get current price
    current_price = None
    if mt5_connector and mt5_connector.connected:
        price_data = mt5_connector.get_current_price(bot_config.symbol)
        if price_data:
            current_price = price_data['bid']

    # Get open positions count
    open_positions = 0
    if mt5_connector and mt5_connector.connected:
        positions = mt5_connector.get_open_positions(bot_config.symbol)
        open_positions = len(positions)

    # Get today's trades
    today = datetime.utcnow().date()
    trades_today = db.query(Trade).filter(
        Trade.user_id == bot_config.user_id,
        Trade.opened_at >= today
    ).all()

    pnl_today = sum(trade.profit_loss for trade in trades_today)

    return {
        "bot_config_id": bot_config.id,
        "is_active": bot_config.is_active,
        "symbol": bot_config.symbol,
        "timeframe": bot_config.timeframe,
        "current_price": current_price,
        "open_positions": open_positions,
        "total_trades_today": len(trades_today),
        "pnl_today": pnl_today,
        "last_signal_time": bot_config.last_signal_time,
    }


# ============================================================================
# TRADE ENDPOINTS
# ============================================================================

@app.get("/api/trades", response_model=List[schemas.TradeResponse])
async def get_trades(
    limit: int = 50,
    status: str = None,
    db: Session = Depends(database.get_db)
):
    """Get trade history"""
    query = db.query(Trade)

    if status:
        query = query.filter(Trade.status == status)

    trades = query.order_by(Trade.opened_at.desc()).limit(limit).all()
    return trades


@app.post("/api/trades/open")
async def open_trade(request: schemas.TradeCreate, db: Session = Depends(database.get_db)):
    """Open a new trade"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    # Calculate lot size
    account_info = mt5_connector.get_account_info()
    if not account_info:
        raise HTTPException(status_code=500, detail="Failed to get account info")

    # Open position
    result = mt5_connector.open_position(
        symbol=request.symbol,
        order_type=request.trade_type,
        volume=request.volume,
        stop_loss=request.stop_loss,
        take_profit=request.take_profit_1,
    )

    if not result or not result.get('success'):
        raise HTTPException(status_code=500, detail="Failed to open trade")

    # Save to database
    trade = Trade(
        user_id=1,  # TODO: Get from authenticated user
        ticket=result['ticket'],
        symbol=request.symbol,
        trade_type=request.trade_type,
        entry_price=result['price'],
        stop_loss=request.stop_loss,
        take_profit_1=request.take_profit_1,
        take_profit_2=request.take_profit_2,
        take_profit_3=request.take_profit_3,
        volume=request.volume,
        risk_percent=request.risk_percent,
        confluence_score=request.confluence_score,
        score_breakdown=request.score_breakdown,
        status="OPEN",
    )

    db.add(trade)
    db.commit()
    db.refresh(trade)

    return {"success": True, "trade_id": trade.id, "ticket": result['ticket']}


# ============================================================================
# WEBSOCKET ENDPOINT
# ============================================================================

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket for real-time updates"""
    await websocket.accept()
    active_websockets.append(websocket)

    try:
        while True:
            # Send periodic updates
            if mt5_connector and mt5_connector.connected:
                # Get current prices
                account_info = mt5_connector.get_account_info()

                message = {
                    "type": "account_update",
                    "data": account_info,
                    "timestamp": datetime.utcnow().isoformat(),
                }

                await websocket.send_json(message)

            await asyncio.sleep(2)  # Update every 2 seconds

    except WebSocketDisconnect:
        active_websockets.remove(websocket)
        logger.info("WebSocket client disconnected")


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

async def broadcast_to_websockets(message: Dict):
    """Broadcast message to all connected WebSocket clients"""
    for websocket in active_websockets:
        try:
            await websocket.send_json(message)
        except:
            pass


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower()
    )
