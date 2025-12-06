"""
============================================================================
INSTITUTIONAL EDGE PRO - FastAPI Main Application
============================================================================
"""

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from typing import List, Dict
import asyncio
from datetime import datetime, timedelta
from loguru import logger

from app.core.config import settings
from app.models.database import Base, User, BotConfig, Trade
from app.api import database, auth, stats, fundamentals, settings as settings_api, news, logs, backtest
from app.core.mt5_connector import MT5Connector
from app.core.trading_engine import TradingEngine
from app.schemas import schemas

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

# Include Routers
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(stats.router, prefix="/api/stats", tags=["stats"])
app.include_router(fundamentals.router, prefix="/api/fundamentals", tags=["fundamentals"])
app.include_router(settings_api.router, prefix="/api/settings", tags=["settings"])
app.include_router(news.router, prefix="/api/news", tags=["news"])
app.include_router(logs.router, prefix="/api/logs", tags=["logs"])
app.include_router(backtest.router, prefix="/api/backtest", tags=["backtest"])

# Socket.IO Setup
import socketio
from app.core.socket import sio

# ============================================================================
# STARTUP & SHUTDOWN
# ============================================================================

# Background Task for Real-time Updates
async def broadcast_market_data():
    """
    Periodically broadcast market data (Account, Positions, PnL) to all clients
    This replaces frontend polling.
    """
    while True:
        try:
            if mt5_connector and mt5_connector.connected:
                # 1. Get Account Info
                account = mt5_connector.get_account_info()
                
                # 2. Get Open Positions
                positions = mt5_connector.get_open_positions()
                
                # 3. Get Current Prices for Running Bots
                prices = {}
                if bot_manager:
                    running_bots = bot_manager.get_running_bots()
                    # We need to get symbols for these bots. 
                    # Since bot_manager might not store config details directly accessible here without DB,
                    # we can iterate unique symbols from open positions or just get all available symbols prices.
                    # A better approach: Get all symbols from DB that are active.
                    # For simplicity/performance, let's just get prices for symbols in open positions + selected symbol (if we knew it).
                    # Let's just get prices for ALL symbols defined in BotConfig (active ones).
                    
                    # For now, let's just send prices for symbols that have open positions to ensure PnL updates are smooth,
                    # and maybe we can accept a client event to subscribe to a specific symbol's price.
                    # But to keep it simple: Broadcast prices for all symbols in open positions.
                    
                    # Get symbols from open positions
                    symbols_to_fetch = set(p['symbol'] for p in positions)
                    
                    # ALSO get symbols from running bots
                    if bot_manager:
                        for bot_id, bot_instance in bot_manager.bots.items():
                            if hasattr(bot_instance, 'config') and hasattr(bot_instance.config, 'symbol'):
                                symbols_to_fetch.add(bot_instance.config.symbol)

                    # Broadcast prices for all relevant symbols
                    for symbol in symbols_to_fetch:
                        tick = mt5_connector.get_current_price(symbol)
                        if tick:
                            prices[symbol] = tick
                            
                    # Debug log to verify broadcast
                    # logger.debug(f"Broadcasting prices for: {list(prices.keys())}")

                # 4. Broadcast
                if account:
                    # Convert datetime objects in positions to strings
                    serializable_positions = []
                    for pos in positions:
                        pos_dict = pos.copy()
                        for k, v in pos_dict.items():
                            if isinstance(v, datetime):
                                pos_dict[k] = v.isoformat()
                        serializable_positions.append(pos_dict)
                    
                    # Serialize prices
                    serializable_prices = {}
                    for sym, tick in prices.items():
                        tick_dict = tick.copy()
                        if isinstance(tick_dict.get('time'), datetime):
                            tick_dict['time'] = tick_dict['time'].isoformat()
                        serializable_prices[sym] = tick_dict

                    # logger.info(f"Broadcasting market data. Positions: {len(serializable_positions)}") 
                    await sio.emit('market_update', {
                        'account': account,
                        'positions': serializable_positions,
                        'prices': serializable_prices,
                        'timestamp': datetime.utcnow().isoformat()
                    })
            else:
                logger.warning("MT5 Not Connected - Skipping Broadcast")
                    
        except Exception as e:
            logger.error(f"Error in broadcast loop: {e}")
            
        # Wait 1 second (Real-time feel without overloading)
        await asyncio.sleep(1)

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
    
    # Always attempt to connect (use active terminal if no creds)
    connected = mt5_connector.connect()
    if connected:
        logger.info("MT5 connected successfully")
    else:
        logger.warning("MT5 connection failed - running in demo/mock mode")

    # Initialize bot manager
    global bot_manager
    from app.services.trading_bot import BotManager
    bot_manager = BotManager(mt5_connector, sio)
    logger.info("Bot manager initialized")
    
    # Start Broadcast Loop
    asyncio.create_task(broadcast_market_data())

    logger.info("API started successfully on {}:{}", settings.HOST, settings.PORT)


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("Shutting down...")

    # Stop all bots
    if bot_manager:
        await bot_manager.stop_all()

    # Disconnect MT5
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


@app.post("/api/mt5/reconnect")
async def reconnect_mt5():
    """Reconnect to MT5"""
    global mt5_connector

    if not mt5_connector:
        raise HTTPException(status_code=500, detail="MT5 connector not initialized")

    # Disconnect if connected
    if mt5_connector.connected:
        mt5_connector.disconnect()

    # Reconnect
    connected = mt5_connector.connect()

    return {
        "success": connected,
        "mt5_connected": connected,
        "message": "MT5 connected successfully" if connected else "MT5 connection failed - check logs"
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


@app.get("/api/mt5/symbols/available")
async def get_available_mt5_symbols():
    """Get all available symbols from MT5 terminal"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    symbols = mt5_connector.get_all_symbols()
    return {"symbols": symbols, "count": len(symbols)}


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
async def analyze_market(symbol: str, timeframe: str, symbol_type: str = "forex"):
    """
    Analyze market and get trading signals

    Example: /api/analysis/EURUSD/H1 or /api/analysis/BTCUSD/H1?symbol_type=crypto
    """
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    # Normalize symbol based on type
    normalized_symbol = mt5_connector.normalize_symbol(symbol, symbol_type)

    # Get OHLCV data
    df = mt5_connector.get_ohlcv_data(normalized_symbol, timeframe, bars=500)
    if df is None or len(df) == 0:
        raise HTTPException(status_code=404, detail=f"No data available for {symbol}")

    # Create trading engine config
    config = {
        'symbol': normalized_symbol,
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


@app.get("/api/market/history/{symbol}/{timeframe}", response_model=schemas.OHLCVResponse)
async def get_market_history(symbol: str, timeframe: str, bars: int = 100, symbol_type: str = "forex"):
    """Get historical OHLCV data for charts"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    logger.info(f"Fetching market history for {symbol} {timeframe}")

    # Normalize symbol based on type
    normalized_symbol = mt5_connector.normalize_symbol(symbol, symbol_type)

    df = mt5_connector.get_ohlcv_data(normalized_symbol, timeframe, bars=bars)
    if df is None or len(df) == 0:
        raise HTTPException(status_code=404, detail=f"No data available for {symbol}")

    # Convert to list of dicts
    data = df.to_dict(orient='records')

    return {
        "symbol": symbol,
        "timeframe": timeframe,
        "data": data
    }


# ============================================================================
# BOT CONTROL ENDPOINTS
# ============================================================================

@app.get("/api/symbols")
async def get_available_symbols(db: Session = Depends(database.get_db)):
    """Get all available trading symbols from bot configurations"""
    try:
        bots = db.query(BotConfig).all()

        symbols = []
        for bot in bots:
            symbol_data = {
                "symbol": bot.symbol,
                "symbol_type": bot.symbol_type or "forex",
                "name": bot.name,
                "timeframe": bot.timeframe
            }
            # Only add if not already in list (avoid duplicates)
            if not any(s['symbol'] == bot.symbol for s in symbols):
                symbols.append(symbol_data)

        return {"symbols": symbols}
    except Exception as e:
        logger.error(f"Error getting symbols: {e}")
        logger.exception(e)
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@app.get("/api/bots", response_model=List[schemas.BotConfigResponse])
async def get_all_bots(db: Session = Depends(database.get_db)):
    """Get all bot configurations"""
    bots = db.query(BotConfig).order_by(BotConfig.id).all()
    return bots


@app.post("/api/bot/create")
async def create_bot_config(request: schemas.BotConfigCreate, db: Session = Depends(database.get_db)):
    """Create a new bot configuration"""
    # Check if exists
    existing = db.query(BotConfig).filter(
        BotConfig.user_id == request.user_id,
        BotConfig.symbol == request.symbol
    ).first()
    
    if existing:
        return existing

    new_config = BotConfig(
        user_id=request.user_id,
        name=f"{request.symbol} Bot",
        symbol=request.symbol,
        symbol_type=request.symbol_type,
        timeframe=request.timeframe or "H1",
        risk_percent=2.0,
        min_confluence_score=6,
        max_trades=3
    )
    
    db.add(new_config)
    db.commit()
    db.refresh(new_config)
    
    return new_config


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

    # Start the automated bot
    if bot_manager:
        await bot_manager.start_bot(request.bot_config_id)
        logger.info("âœ… Bot {} started for symbol {} {}", bot_config.name, bot_config.symbol, bot_config.timeframe)
    else:
        logger.warning("Bot manager not available")

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

    # Mark as inactive in database
    bot_config.is_active = False
    db.commit()

    # Stop the automated bot
    if bot_manager:
        await bot_manager.stop_bot(request.bot_config_id)
        logger.info("ðŸ›‘ Bot {} stopped", bot_config.name)
    else:
        logger.warning("Bot manager not available")

    return {
        "success": True,
        "message": f"Bot {bot_config.name} stopped successfully",
        "bot_config_id": bot_config.id,
    }


@app.get("/api/bot/status/{bot_config_id}", response_model=schemas.BotStatusResponse)
async def get_bot_status(bot_config_id: int, db: Session = Depends(database.get_db)):
    """Get bot status"""
    try:
        bot_config = db.query(BotConfig).filter(BotConfig.id == bot_config_id).first()
        if not bot_config:
            raise HTTPException(status_code=404, detail="Bot configuration not found")

        # Check if bot is actually running (not just DB flag)
        is_running = False
        if bot_manager:
            is_running = bot_config_id in bot_manager.get_running_bots()

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

        # Handle None values in profit_loss
        pnl_today = sum(trade.profit_loss or 0.0 for trade in trades_today)

        return {
            "bot_config_id": bot_config.id,
            "is_active": bot_config.is_active,
            "is_running": is_running,
            "symbol": bot_config.symbol,
            "timeframe": bot_config.timeframe,
            "current_price": current_price,
            "open_positions": open_positions,
            "total_trades_today": len(trades_today),
            "pnl_today": pnl_today,
            "last_signal_time": bot_config.last_signal_time,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting bot status for bot {bot_config_id}: {e}")
        logger.exception(e)
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/api/bots/running")
async def get_running_bots():
    """Get list of all running bot IDs"""
    if not bot_manager:
        return {"running_bots": [], "count": 0}

    running_bot_ids = bot_manager.get_running_bots()
    return {
        "running_bots": running_bot_ids,
        "count": len(running_bot_ids)
    }


@app.get("/api/bot-config/{bot_config_id}", response_model=schemas.BotConfigResponse)
async def get_bot_config(bot_config_id: int, db: Session = Depends(database.get_db)):
    """Get bot configuration details"""
    bot_config = db.query(BotConfig).filter(BotConfig.id == bot_config_id).first()
    if not bot_config:
        raise HTTPException(status_code=404, detail="Bot configuration not found")
    return bot_config


@app.put("/api/bot-config/{bot_config_id}", response_model=schemas.BotConfigResponse)
async def update_bot_config(
    bot_config_id: int, 
    config_update: schemas.BotConfigUpdate, 
    db: Session = Depends(database.get_db)
):
    """Update bot configuration"""
    bot_config = db.query(BotConfig).filter(BotConfig.id == bot_config_id).first()
    if not bot_config:
        raise HTTPException(status_code=404, detail="Bot configuration not found")

    # Update fields
    update_data = config_update.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(bot_config, key, value)

    db.commit()
    db.refresh(bot_config)

    # Restart bot if running to apply changes
    if bot_manager and bot_config_id in bot_manager.get_running_bots():
        logger.info("Config updated for running bot {}, restarting...", bot_config_id)
        await bot_manager.stop_bot(bot_config_id)
        await bot_manager.start_bot(bot_config_id)

    return bot_config


# ============================================================================
# TRADE ENDPOINTS
# ============================================================================

@app.get("/api/signals")
async def get_signals(
    limit: int = 50,
    symbol: str = None,
    executed_only: bool = False,
    db: Session = Depends(database.get_db)
):
    """Get trading signals from database"""
    try:
        from app.models.database import Signal

        query = db.query(Signal)

        if symbol:
            query = query.filter(Signal.symbol == symbol)

        if executed_only:
            query = query.filter(Signal.was_executed == True)

        signals = query.order_by(Signal.created_at.desc()).limit(limit).all()

        return {
            "signals": [
                {
                    "id": s.id,
                    "symbol": s.symbol,
                    "timeframe": s.timeframe,
                    "signal_type": s.signal_type,
                    "price": s.price,
                    "stop_loss": s.stop_loss,
                    "take_profit": s.take_profit,
                    "confluence_score": s.confluence_score,
                    "score_breakdown": s.score_breakdown,
                    "trend": s.trend,
                    "poc_level": s.poc_level,
                    "zone": s.zone,
                    "was_executed": s.was_executed,
                    "created_at": s.created_at.isoformat() if s.created_at else None,
                    "ai_confidence": getattr(s, 'ai_confidence', 0),
                    "ai_recommendation": getattr(s, 'ai_recommendation', 'UNCERTAIN')
                }
                for s in signals
            ],
            "count": len(signals)
        }
    except Exception as e:
        logger.error(f"Error getting signals: {e}")
        logger.exception(e)
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


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
    import traceback
    try:
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
            error_msg = result.get('error') if result else "Failed to open trade"
            raise HTTPException(status_code=500, detail=error_msg)

        # Get user
        user = db.query(User).first()
        if not user:
            raise HTTPException(status_code=500, detail="No user found")

        # Save to database
        trade = Trade(
            user_id=user.id,
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
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error opening trade: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.post("/api/trades/close/{ticket}")
async def close_trade(ticket: int, db: Session = Depends(database.get_db)):
    """Close a trade by ticket"""
    try:
        if not mt5_connector or not mt5_connector.connected:
            raise HTTPException(status_code=503, detail="MT5 not connected")

        # Close position in MT5
        success = mt5_connector.close_position(ticket)
        if not success:
            raise HTTPException(status_code=500, detail="Failed to close position in MT5")

        # Update database
        trade = db.query(Trade).filter(Trade.ticket == ticket).first()
        if trade:
            trade.status = "CLOSED"
            trade.closed_at = datetime.utcnow()
            # PnL should be updated by a separate sync process or here if we fetch history
            db.commit()

        return {"success": True, "message": f"Trade {ticket} closed"}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error closing trade: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.post("/api/trades/be/{ticket}")
async def move_to_be(ticket: int, db: Session = Depends(database.get_db)):
    """Move trade SL to Break Even"""
    try:
        if not mt5_connector or not mt5_connector.connected:
            raise HTTPException(status_code=503, detail="MT5 not connected")

        # Get position info
        positions = mt5_connector.get_open_positions()
        position = next((p for p in positions if p['ticket'] == ticket), None)
        
        if not position:
            raise HTTPException(status_code=404, detail="Position not found")

        # Calculate BE level (Entry price)
        new_sl = position['price_open']
        
        # Modify position
        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "position": ticket,
            "sl": new_sl,
            "tp": position['tp']
        }
        
        result = mt5.order_send(request)
        
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
             raise HTTPException(status_code=500, detail=f"Failed to move to BE. Retcode: {result.retcode if result else 'None'}")

        return {"success": True, "message": f"Trade {ticket} moved to BE"}

    except Exception as e:
        logger.error(f"Error moving to BE: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.post("/api/trades/trail/{ticket}")
async def manual_trail_sl(ticket: int, distance: float = 1.5, db: Session = Depends(database.get_db)):
    """Manually trail SL for a trade"""
    try:
        if not mt5_connector or not mt5_connector.connected:
            raise HTTPException(status_code=503, detail="MT5 not connected")

        # We need a TradeManager instance. 
        # Ideally, we should use the one from the running bot if available, or create a temporary one.
        # Since TradeManager is stateless regarding connection (uses connector), we can create one.
        from app.services.trade_manager import TradeManager
        tm = TradeManager(mt5_connector)
        
        success = tm.manual_trail_sl(ticket, distance)
        
        if not success:
             raise HTTPException(status_code=500, detail="Failed to trail SL (check logs)")

        return {"success": True, "message": f"Trade {ticket} SL trailed"}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error trailing SL: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.delete("/api/signals")
async def clear_signals(db: Session = Depends(database.get_db)):
    """Clear all signals"""
    try:
        from app.models.database import Signal
        # Delete all signals or just mark them? User asked to "clear".
        # Let's delete non-executed ones or all? Usually "Clear" means clear the view.
        # Let's delete all signals from DB to be sure.
        db.query(Signal).delete()
        db.commit()
        
        # Emit event to clear frontend
        await sio.emit('signals_cleared')
        
        return {"success": True, "message": "Signals cleared"}
    except Exception as e:
        logger.error(f"Error clearing signals: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/api/account/summary")
async def get_account_summary():
    """Get live account summary from MT5"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")
        
    info = mt5_connector.get_account_info()
    if not info:
        raise HTTPException(status_code=500, detail="Failed to get account info")
        
    return info


@app.get("/api/trades/live")
async def get_live_trades():
    """Get live open positions from MT5"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")
        
    positions = mt5_connector.get_open_positions()
    return positions


# Wrap FastAPI app with Socket.IO at the end, after all routes are defined
app = socketio.ASGIApp(sio, app)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower()
    )

