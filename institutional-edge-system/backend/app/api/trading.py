"""
============================================================================
Trading API - Live Trading with Full MT5 Execution
============================================================================
"""

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, Dict
from datetime import datetime, timedelta
from loguru import logger
import uuid
import asyncio

from app.api.database import get_db
from app.models.database import MT5Account
from app.core.crypto import decrypt_password
from app.core.prop_firm_manager import PropFirmManager
from app.core.mt5_connector import MT5Connector
from app.core.trading_engine import TradingEngine
from app.core.socket_server import sio  # Socket.IO for real-time updates

router = APIRouter()

# Store active trading sessions
active_sessions: Dict[str, 'LiveTradingSession'] = {}


class TradingStartRequest(BaseModel):
    symbol: str
    direction_filter: str = "BOTH"
    risk_percent: float = 1.0
    tp_ratio: float = 2.0
    sl_atr_multiplier: float = 1.5
    tsl_mode: str = "TIERED"
    timeframe: str = "M5"
    max_trade_duration_hours: int = 2
    min_confluence_score: int = 5
    account_id: int


class LiveTradingSession:
    """
    Live trading session for a single symbol slot.
    Uses TradingEngine for signals and MT5Connector for execution.
    """
    
    def __init__(self, session_id: str, config: dict, account: MT5Account, mt5: MT5Connector):
        self.session_id = session_id
        self.config = config
        self.account = account
        self.mt5 = mt5
        self.is_running = False
        self.trades = []
        self.last_signal_time = None
        
        # Initialize prop firm manager
        self.prop_manager = PropFirmManager(
            max_drawdown_percent=account.max_drawdown_percent,
            max_daily_dd_percent=account.max_daily_dd_percent,
            starting_balance=account.starting_balance
        )
        
        # Initialize trading engine
        is_scalping = config['timeframe'] in ['M1', 'M5', 'M15']
        self.engine = TradingEngine({
            'symbol': config['symbol'],
            'timeframe': config['timeframe'],
            'initial_balance': account.starting_balance,
            'max_risk_per_trade': config['risk_percent'],
            'scalping_mode': is_scalping,
            'min_confluence_score': config['min_confluence_score'],
            'tp_ratio': config['tp_ratio'],
            'sl_atr_multiplier': config['sl_atr_multiplier'],
        })
    
    async def run(self):
        """Main trading loop"""
        self.is_running = True
        symbol = self.config['symbol']
        timeframe = self.config['timeframe']
        direction = self.config['direction_filter']
        
        logger.info(f"🔴 LIVE SESSION {self.session_id}: Starting for {symbol} ({timeframe})")
        
        while self.is_running:
            try:
                # 0. Check Trading Hours (UTC-4: 00:00 - 12:00)
                utc_now = datetime.utcnow()
                local_now = utc_now - timedelta(hours=4)
                
                if not (0 <= local_now.hour < 12):
                    # Log every loop (1 min) so user can see it
                    logger.warning(f"⛔ {self.session_id}: Outside Trading Hours: {local_now.strftime('%H:%M')} (Limit 00-12 Local)")
                    
                    # Wait and skip
                    await asyncio.sleep(60)
                    continue

                # 1. Check prop firm limits
                account_info = self.mt5.get_account_info()
                if account_info:
                    current_balance = account_info['balance']
                    can_trade, reason = self.prop_manager.check_can_trade(current_balance)
                    
                    if not can_trade:
                        logger.error(f"🛑 {self.session_id}: {reason}")
                        break
                
                # 2. Get market data
                df = self.mt5.get_ohlcv_data(symbol, timeframe, bars=500)
                if df is None or len(df) == 0:
                    logger.warning(f"{self.session_id}: No data for {symbol}")
                    await asyncio.sleep(60)
                    continue
                
                # 3. Analyze for signals
                analysis = self.engine.analyze(df)
                signals = analysis.get('signals', [])
                
                if signals:
                    logger.info(f"{self.session_id}: Found {len(signals)} signals")
                    
                    for signal in signals:
                        # Check direction filter
                        if direction != 'BOTH':
                            if direction == 'BUY_ONLY' and signal.signal_type != 'BUY':
                                continue
                            if direction == 'SELL_ONLY' and signal.signal_type != 'SELL':
                                continue
                        
                        # Check confluence score
                        if signal.confluence_score < self.config['min_confluence_score']:
                            continue
                        
                        # Check if no open position for this symbol
                        positions = self.mt5.get_open_positions(symbol)
                        if positions:
                            logger.info(f"{self.session_id}: Position already open for {symbol}")
                            continue
                        
                        # Execute trade!
                        await self._execute_trade(signal, account_info)
                
                # 4. Wait before next check
                wait_time = 60 if timeframe in ['M1', 'M5', 'M15'] else 300
                await asyncio.sleep(wait_time)
                
            except Exception as e:
                logger.exception(f"{self.session_id}: Error in loop: {e}")
                await asyncio.sleep(60)
        
        logger.info(f"🛑 LIVE SESSION {self.session_id}: Stopped")
    
    async def _execute_trade(self, signal, account_info):
        """Execute a trading signal"""
        symbol = self.config['symbol']
        risk_percent = self.config['risk_percent']
        
        # Calculate lot size
        sl_distance = abs(signal.entry_price - signal.stop_loss)
        lot_size = self.mt5.calculate_lot_size(
            symbol=symbol,
            risk_percent=risk_percent,
            sl_distance=sl_distance,
            account_balance=account_info['balance']
        )
        
        logger.info(f"📈 {self.session_id}: Opening {signal.signal_type} {lot_size} lots @ {signal.entry_price}")
        
        # Open position
        result = self.mt5.open_position(
            symbol=symbol,
            order_type=signal.signal_type,
            volume=lot_size,
            stop_loss=signal.stop_loss,
            take_profit=signal.take_profit_1,
            comment=f"Live-{self.session_id}"
        )
        
        if result and result.get('success'):
            logger.info(f"✅ {self.session_id}: Trade opened - Ticket {result['ticket']}")
            trade_data = {
                'ticket': result['ticket'],
                'symbol': symbol,
                'type': signal.signal_type,
                'volume': lot_size,
                'entry_price': signal.entry_price,
                'stop_loss': signal.stop_loss,
                'take_profit': signal.take_profit_1,
                'session_id': self.session_id,
                'opened_at': datetime.utcnow().isoformat()
            }
            self.trades.append(trade_data)
            
            # Emit to frontend for real-time updates
            try:
                await sio.emit('live_trade_opened', trade_data)
                logger.info(f"📡 Emitted live_trade_opened for {symbol}")
            except Exception as e:
                logger.warning(f"Could not emit trade event: {e}")
        else:
            error = result.get('error', 'Unknown') if result else 'No response'
            logger.error(f"❌ {self.session_id}: Trade failed - {error}")
    
    def stop(self):
        """Stop the trading session"""
        self.is_running = False


# Global MT5 connector (will be set on first use)
_mt5_connector: Optional[MT5Connector] = None


def get_mt5_connector(account: MT5Account) -> MT5Connector:
    """Get or create MT5 connector for an account"""
    global _mt5_connector
    
    if _mt5_connector is None:
        _mt5_connector = MT5Connector({})
    
    # Connect with account credentials
    if not _mt5_connector.connected:
        try:
            import MetaTrader5 as mt5
            
            password = decrypt_password(account.password_encrypted)
            
            if not mt5.initialize():
                logger.error("Failed to initialize MT5")
                return _mt5_connector
            
            if mt5.login(int(account.login), password, account.server):
                logger.info(f"✅ MT5 connected as {account.login}")
                _mt5_connector.connected = True
            else:
                logger.error(f"MT5 login failed: {mt5.last_error()}")
        except Exception as e:
            logger.error(f"MT5 connection error: {e}")
    
    return _mt5_connector


async def run_trading_session(session: LiveTradingSession):
    """Background task to run a trading session"""
    await session.run()


@router.post("/start")
async def start_trading(
    request: TradingStartRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """Start live trading for a symbol"""
    
    # Get account
    account = db.query(MT5Account).filter(MT5Account.id == request.account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    if not account.is_active:
        raise HTTPException(status_code=400, detail="Account is not active. Connect first.")
    
    # Check prop firm limits before starting
    prop_manager = PropFirmManager(
        max_drawdown_percent=account.max_drawdown_percent,
        max_daily_dd_percent=account.max_daily_dd_percent,
        starting_balance=account.starting_balance
    )
    
    can_trade, reason = prop_manager.check_can_trade(account.starting_balance)
    if not can_trade:
        raise HTTPException(status_code=400, detail=f"Cannot start trading: {reason}")
    
    # Get MT5 connector
    mt5 = get_mt5_connector(account)
    if not mt5.connected:
        raise HTTPException(status_code=500, detail="Failed to connect to MT5")
    
    # Create session
    session_id = str(uuid.uuid4())[:8]
    
    session = LiveTradingSession(
        session_id=session_id,
        config=request.dict(),
        account=account,
        mt5=mt5
    )
    active_sessions[session_id] = session
    
    # Start trading in background
    background_tasks.add_task(run_trading_session, session)
    
    logger.info(f"🔴 LIVE TRADING STARTED: Session {session_id}")
    logger.info(f"   Symbol: {request.symbol}")
    logger.info(f"   Account: {account.name} ({account.login})")
    logger.info(f"   Risk: {request.risk_percent}%")
    logger.info(f"   Direction: {request.direction_filter}")
    
    return {
        "success": True,
        "session_id": session_id,
        "message": f"Live trading started for {request.symbol}",
        "config": request.dict()
    }


@router.post("/stop/{session_id}")
async def stop_trading(session_id: str):
    """Stop a live trading session"""
    
    if session_id not in active_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = active_sessions[session_id]
    session.stop()
    
    logger.info(f"🛑 LIVE TRADING STOPPED: Session {session_id}")
    
    # Remove from active sessions
    del active_sessions[session_id]
    
    return {"success": True, "message": f"Session {session_id} stopped"}


@router.post("/stop-all")
async def stop_all_trading():
    """Stop all active trading sessions"""
    
    count = len(active_sessions)
    for session_id, session in list(active_sessions.items()):
        session.stop()
        del active_sessions[session_id]
    
    logger.info(f"🛑 STOPPED ALL {count} TRADING SESSIONS")
    return {"success": True, "message": f"Stopped {count} sessions"}


@router.get("/sessions")
async def list_sessions():
    """List all active trading sessions"""
    
    return {
        "sessions": [
            {
                "session_id": s.session_id,
                "symbol": s.config.get("symbol"),
                "is_running": s.is_running,
                "trades_count": len(s.trades),
                "account": s.account.name
            }
            for s in active_sessions.values()
        ]
    }


@router.get("/status/{session_id}")
async def get_session_status(session_id: str):
    """Get status of a trading session"""
    
    if session_id not in active_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = active_sessions[session_id]
    
    return {
        "session_id": session_id,
        "is_running": session.is_running,
        "symbol": session.config.get("symbol"),
        "trades_count": len(session.trades),
        "trades": session.trades[-10:],  # Last 10 trades
        "config": session.config
    }
