"""
============================================================================
Trading API - Enhanced Live Trading with Risk Controls
============================================================================
Features:
- Integrated risk controls (circuit breakers, kill switch)
- Partial profit taking (TP1 at 50%, rest to TP2/TP3)
- ATR-based trailing stops
- Market condition filters
- Real-time WebSocket updates
"""

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, Dict, List
from datetime import datetime, timedelta
from loguru import logger
import uuid
import asyncio

from app.api.database import get_db
from app.models.database import MT5Account, BotSlot
from app.core.crypto import decrypt_password
from app.core.prop_firm_manager import PropFirmManager
from app.core.mt5_connector import MT5Connector
from app.core.mt5_connector import MT5Connector
from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine
from app.core.risk_controls import get_risk_controls, RiskControls
from app.core.socket_server import sio

router = APIRouter()

# Store active trading sessions
active_sessions: Dict[str, 'LiveTradingSession'] = {}

# Global MT5 connector
_mt5_connector: Optional[MT5Connector] = None


class TradingStartRequest(BaseModel):
    account_id: int
    slot_id: Optional[int] = None  # If provided, load config from DB
    # Manual config (used if slot_id not provided)
    symbol: Optional[str] = "EURUSD"
    direction_filter: str = "BOTH"
    risk_percent: float = 1.0
    tp_ratio: float = 2.0
    sl_atr_multiplier: float = 1.5
    tsl_mode: str = "TIERED"
    timeframe: str = "M5"
    max_trade_duration_hours: int = 2
    min_confluence_score: int = 7
    # Enhanced options
    enable_partial_tp: bool = True
    partial_tp_percent: float = 50.0
    enable_trailing_stop: bool = True
    enable_partial_tp: bool = True
    partial_tp_percent: float = 50.0
    enable_trailing_stop: bool = True
    trailing_stop_atr: float = 1.5
    # Institutional
    use_daily_bias: bool = False


class RiskConfigRequest(BaseModel):
    max_daily_loss_pct: float = 2.0
    max_consecutive_losses: int = 3
    max_drawdown_pct: float = 5.0


class LiveTradingSession:
    """
    Enhanced live trading session with risk controls and partial TPs.
    """
    
    def __init__(
        self,
        session_id: str,
        config: dict,
        account: MT5Account,
        mt5: MT5Connector,
        risk_controls: RiskControls
    ):
        self.session_id = session_id
        self.config = config
        self.account = account
        self.mt5 = mt5
        self.risk_controls = risk_controls
        self.is_running = False
        self.trades = []
        self.managed_positions: Dict[int, Dict] = {}  # ticket -> position info
        
        # Initialize prop firm manager
        self.prop_manager = PropFirmManager(
            max_drawdown_percent=account.max_drawdown_percent,
            max_daily_dd_percent=account.max_daily_dd_percent,
            starting_balance=account.starting_balance
        )
        
        # Initialize trading engine
        is_scalping = config['timeframe'] in ['M1', 'M5', 'M15']
        # Initialize trading engine (Adaptive Multi-Strategy)
        engine_config = config.copy()
        engine_config['initial_balance'] = account.starting_balance
        engine_config['max_risk_per_trade'] = config['risk_percent']
        
        self.engine = AdaptiveMultiStrategyEngine(engine_config)
    
    async def run(self):
        """Main trading loop with enhanced features"""
        self.is_running = True
        symbol = self.config['symbol']
        timeframe = self.config['timeframe']
        direction = self.config['direction_filter']
        account_id = str(self.account.id)
        
        logger.info(f"🔴 LIVE SESSION {self.session_id}: Starting for {symbol} ({timeframe})")
        
        last_news_update = datetime.min
        
        while self.is_running:
            try:
                # Update News Filter (Hourly)
                if (datetime.utcnow() - last_news_update).total_seconds() > 3600:
                    try:
                        self.engine.update_news(self.mt5)
                        last_news_update = datetime.utcnow()
                    except Exception as e:
                        logger.error(f"Failed to update news: {e}")

                # 0. Check kill switch
                if self.risk_controls.is_kill_switch_active():
                    logger.warning(f"⛔ {self.session_id}: Kill switch active - pausing")
                    await asyncio.sleep(10)
                    continue

                # 1. Trading hours check (00:00 - 12:00 local)
                utc_now = datetime.utcnow()
                local_now = utc_now - timedelta(hours=4)
                
                if not (0 <= local_now.hour < 12):
                    logger.debug(f"⛔ {self.session_id}: Outside trading hours")
                    await asyncio.sleep(60)
                    continue

                # 2. Get account info for risk checks
                account_info = self.mt5.get_account_info()
                if not account_info:
                    await asyncio.sleep(60)
                    continue
                
                current_balance = account_info['balance']
                current_equity = account_info['equity']
                starting_balance = self.account.starting_balance

                # 3. Check risk controls before new trades
                can_trade, reason = self.risk_controls.can_open_trade(
                    account_id=account_id,
                    symbol=symbol,
                    current_balance=current_balance,
                    starting_balance=starting_balance,
                    current_equity=current_equity
                )
                
                if not can_trade:
                    logger.warning(f"🛑 {self.session_id}: {reason}")
                    # Still manage existing positions
                    await self._manage_open_positions()
                    await asyncio.sleep(60)
                    continue

                # 4. Check prop firm limits
                can_trade_prop, prop_reason = self.prop_manager.check_can_trade(current_balance)
                if not can_trade_prop:
                    logger.error(f"🛑 {self.session_id}: Prop Firm - {prop_reason}")
                    break

                # 5. Market condition checks
                spread = self.mt5.get_spread(symbol)
                if spread and spread > 5.0:  # Max 5 pips spread
                    logger.warning(f"⛔ {self.session_id}: High spread: {spread:.1f} pips")
                    await asyncio.sleep(30)
                    continue

                # 6. Get market data
                df = self.mt5.get_ohlcv_data(symbol, timeframe, bars=500)
                if df is None or len(df) == 0:
                    logger.warning(f"{self.session_id}: No data for {symbol}")
                    await asyncio.sleep(60)
                    continue

                # 6.5 Get D1 data for Bias (Institutional)
                df_daily = None
                if self.config.get('use_daily_bias', False):
                    df_daily = self.mt5.get_ohlcv_data(symbol, 'D1', bars=100)
                    if df_daily is None or len(df_daily) < 50:
                         logger.warning(f"{self.session_id}: D1 data missing for Daily Bias")

                # 7. Analyze for signals
                analysis = self.engine.analyze(df, df_daily=df_daily)
                signals = analysis.get('signals', [])
                
                if signals:
                    logger.info(f"{self.session_id}: Found {len(signals)} signals")
                    
                    for signal in signals:
                        # Direction filter
                        if direction != 'BOTH':
                            if direction == 'BUY_ONLY' and signal.signal_type != 'BUY':
                                continue
                            if direction == 'SELL_ONLY' and signal.signal_type != 'SELL':
                                continue
                        
                        # Confluence filter
                        if signal.confluence_score < self.config['min_confluence_score']:
                            continue
                        
                        # Check existing positions
                        positions = self.mt5.get_open_positions(symbol)
                        if positions:
                            logger.info(f"{self.session_id}: Position already open for {symbol}")
                            continue
                        
                        # Execute trade
                        await self._execute_trade(signal, account_info)

                # 8. Manage open positions (partial TPs, trailing stops)
                await self._manage_open_positions()

                # 9. Wait interval
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
        account_id = str(self.account.id)
        
        sl_distance = abs(signal.entry_price - signal.stop_loss)
        lot_size = self.mt5.calculate_lot_size(
            symbol=symbol,
            risk_percent=risk_percent,
            sl_distance=sl_distance,
            account_balance=account_info['balance']
        )
        
        logger.info(f"📈 {self.session_id}: Opening {signal.signal_type} {lot_size} lots @ {signal.entry_price}")
        
        result = self.mt5.open_position(
            symbol=symbol,
            order_type=signal.signal_type,
            volume=lot_size,
            stop_loss=signal.stop_loss,
            take_profit=signal.take_profit_1,
            comment=f"Live-{self.session_id}"
        )
        
        if result and result.get('success'):
            ticket = result['ticket']
            logger.info(f"✅ {self.session_id}: Trade opened - Ticket {ticket}")
            
            # Register with risk controls
            self.risk_controls.register_position_opened(account_id, symbol)
            
            # Track for partial TP management
            self.managed_positions[ticket] = {
                'symbol': symbol,
                'type': signal.signal_type,
                'entry_price': signal.entry_price,
                'original_volume': lot_size,
                'current_volume': lot_size,
                'stop_loss': signal.stop_loss,
                'take_profit_1': signal.take_profit_1,
                'take_profit_2': signal.take_profit_2,
                'take_profit_3': signal.take_profit_3,
                'partial_taken': False,
                'breakeven_moved': False,
                'opened_at': datetime.utcnow()
            }
            
            trade_data = {
                'ticket': ticket,
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
            
            # Emit WebSocket event
            try:
                await sio.emit('live_trade_opened', trade_data)
            except Exception as e:
                logger.warning(f"Could not emit trade event: {e}")
        else:
            error = result.get('error', 'Unknown') if result else 'No response'
            logger.error(f"❌ {self.session_id}: Trade failed - {error}")

    async def _manage_open_positions(self):
        """Manage open positions: partial TPs, trailing stops, time-based exits"""
        if not self.config.get('enable_partial_tp', True):
            return
            
        account_id = str(self.account.id)
        positions = self.mt5.get_open_positions()
        
        for pos in positions:
            ticket = pos['ticket']
            if ticket not in self.managed_positions:
                continue
                
            managed = self.managed_positions[ticket]
            current_price = pos['price_current']
            entry_price = managed['entry_price']
            is_buy = managed['type'] == 'BUY'
            
            # Calculate profit in pips
            point = self.mt5.get_symbol_point(pos['symbol'])
            profit_points = (current_price - entry_price) / point if is_buy else (entry_price - current_price) / point
            
            # ============ PARTIAL TP LOGIC ============
            if not managed['partial_taken'] and managed['take_profit_1']:
                tp1 = managed['take_profit_1']
                hit_tp1 = (is_buy and current_price >= tp1) or (not is_buy and current_price <= tp1)
                
                if hit_tp1:
                    partial_volume = managed['original_volume'] * (self.config['partial_tp_percent'] / 100)
                    partial_volume = round(partial_volume, 2)
                    
                    if partial_volume >= 0.01:
                        logger.info(f"📊 Taking partial profit: {partial_volume} lots @ {current_price}")
                        if self.mt5.close_partial_position(ticket, partial_volume):
                            managed['partial_taken'] = True
                            managed['current_volume'] -= partial_volume
                            
                            # Move SL to breakeven
                            if not managed['breakeven_moved']:
                                self.mt5.modify_position(
                                    ticket,
                                    stop_loss=entry_price,
                                    take_profit=managed['take_profit_2']
                                )
                                managed['breakeven_moved'] = True
                                logger.info(f"🛡️ Moved SL to breakeven for ticket {ticket}")
                            
                            await sio.emit('partial_tp_taken', {
                                'ticket': ticket,
                                'volume_closed': partial_volume,
                                'price': current_price
                            })
            
            # ============ TRAILING STOP LOGIC ============
            if self.config.get('enable_trailing_stop', True) and managed['breakeven_moved']:
                # Get ATR for trailing distance
                df = self.mt5.get_ohlcv_data(pos['symbol'], self.config['timeframe'], 20)
                if df is not None and len(df) > 0:
                    # Simple ATR calculation
                    df['tr'] = df['high'] - df['low']
                    atr = df['tr'].iloc[-14:].mean()
                    trail_distance = atr * self.config.get('trailing_stop_atr', 1.5)
                    
                    if is_buy:
                        new_sl = current_price - trail_distance
                        if new_sl > pos['sl']:
                            self.mt5.modify_position(ticket, stop_loss=new_sl)
                            logger.debug(f"📈 Trailing SL moved to {new_sl:.5f}")
                            # Emit trailing stop event
                            await sio.emit('trailing_stop_moved', {
                                'session_id': self.session_id,
                                'ticket': ticket,
                                'symbol': pos['symbol'],
                                'old_sl': pos['sl'],
                                'new_sl': new_sl,
                                'direction': 'BUY'
                            })
                    else:
                        new_sl = current_price + trail_distance
                        if new_sl < pos['sl']:
                            self.mt5.modify_position(ticket, stop_loss=new_sl)
                            logger.debug(f"📉 Trailing SL moved to {new_sl:.5f}")
                            # Emit trailing stop event
                            await sio.emit('trailing_stop_moved', {
                                'session_id': self.session_id,
                                'ticket': ticket,
                                'symbol': pos['symbol'],
                                'old_sl': pos['sl'],
                                'new_sl': new_sl,
                                'direction': 'SELL'
                            })
            
            # ============ TIME-BASED EXIT ============
            max_hours = self.config.get('max_trade_duration_hours', 0)
            if max_hours > 0:
                opened_at = managed['opened_at']
                duration = datetime.utcnow() - opened_at
                if duration > timedelta(hours=max_hours):
                    logger.info(f"⏰ Time exit: closing position {ticket} after {duration}")
                    pnl = pos['profit']
                    if self.mt5.close_position(ticket):
                        self.risk_controls.register_position_closed(
                            account_id, pos['symbol'], pnl, self.account.starting_balance
                        )
                        # Emit trade closed event
                        await sio.emit('live_trade_closed', {
                            'session_id': self.session_id,
                            'ticket': ticket,
                            'symbol': pos['symbol'],
                            'pnl': pnl,
                            'close_reason': 'TIME_EXIT',
                            'closed_at': datetime.utcnow().isoformat()
                        })
                        del self.managed_positions[ticket]
    
    def stop(self):
        """Stop the trading session"""
        self.is_running = False


def get_mt5_connector(account: MT5Account) -> MT5Connector:
    """Get or create MT5 connector for an account"""
    global _mt5_connector
    
    password = decrypt_password(account.password_encrypted)
    config = {
        "mt5_login": int(account.login),
        "mt5_password": password,
        "mt5_server": account.server
    }
    
    if _mt5_connector is None:
        _mt5_connector = MT5Connector(config)
    else:
        # Update credentials just in case account changed
        _mt5_connector.config.update(config)
        _mt5_connector.login = config['mt5_login']
        _mt5_connector.password = config['mt5_password']
        _mt5_connector.server = config['mt5_server']
    
    if not _mt5_connector.connected:
        try:
            if _mt5_connector.connect():
                logger.info(f"✅ MT5 connected via Connector as {account.login}")
            else:
                logger.error("Failed to connect to MT5 via Connector")
        except Exception as e:
            logger.error(f"MT5 connection exception: {e}")
    
    return _mt5_connector


async def run_trading_session(session: LiveTradingSession):
    """Background task to run a trading session"""
    await session.run()


# ==================== API ENDPOINTS ====================

@router.post("/start")
async def start_trading(
    request: TradingStartRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """Start live trading for a symbol. Can load config from slot_id."""
    
    account = db.query(MT5Account).filter(MT5Account.id == request.account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    if not account.is_active:
        raise HTTPException(status_code=400, detail="Account is not active")
    
    mt5 = get_mt5_connector(account)
    if not mt5.connected:
        raise HTTPException(status_code=500, detail="Failed to connect to MT5")
    
    # Build config - either from slot or from request
    if request.slot_id:
        slot = db.query(BotSlot).filter(BotSlot.id == request.slot_id).first()
        if not slot:
            raise HTTPException(status_code=404, detail=f"Slot {request.slot_id} not found")
        if not slot.enabled:
            raise HTTPException(status_code=400, detail=f"Slot {request.slot_id} is disabled")
        
        # Load config from slot
        config = {
            'symbol': slot.symbol,
            'direction_filter': slot.direction_filter,
            'risk_percent': slot.risk_percent,
            'tp_ratio': slot.tp_ratio,
            'sl_atr_multiplier': slot.sl_atr_multiplier,
            'tsl_mode': slot.tsl_mode,
            'timeframe': slot.timeframe,
            'max_trade_duration_hours': slot.max_trade_duration_hours,
            'min_confluence_score': slot.min_confluence_score,
            'account_id': request.account_id,
            'slot_id': slot.id,
            'enable_partial_tp': slot.partial_tp_on,
            'partial_tp_percent': slot.partial_tp_amount * 100,
            'enable_trailing_stop': slot.tsl_mode != 'OFF',
            'trailing_stop_atr': slot.sl_atr_multiplier,
            # Strategy flags
            'enable_vwap_strategy': slot.enable_vwap_strategy,
            'enable_stoch_strategy': slot.enable_stoch_strategy,
            'enable_institutional_strategy': slot.enable_institutional_strategy,
            'enable_fibonacci_strategy': slot.enable_fibonacci_strategy,
            'rsi_period': slot.rsi_period,
            'rsi_overbought': slot.rsi_overbought,
            'rsi_oversold': slot.rsi_oversold,
            'rsi_period': slot.rsi_period,
            'rsi_overbought': slot.rsi_overbought,
            'rsi_oversold': slot.rsi_oversold,
            # Enhanced Params (Adaptive Engine)
            'use_adx_filter': slot.use_adx_filter,
            'use_h1_trend_filter': slot.use_h1_trend_filter,
            'stoch_k_period': slot.stoch_k_period,
            'stoch_d_period': slot.stoch_d_period,
            'vwap_use_trend_filter': slot.vwap_use_trend_filter,
            'use_daily_bias': slot.use_daily_bias,
        }
        logger.info(f"📦 Loaded slot {slot.id} config for {slot.symbol}")
    else:
        config = request.dict()
    
    risk_controls = get_risk_controls()
    
    session_id = str(uuid.uuid4())[:8]
    session = LiveTradingSession(
        session_id=session_id,
        config=config,
        account=account,
        mt5=mt5,
        risk_controls=risk_controls
    )
    active_sessions[session_id] = session
    
    background_tasks.add_task(run_trading_session, session)
    
    logger.info(f"🔴 LIVE TRADING STARTED: Session {session_id}")
    
    return {
        "success": True,
        "session_id": session_id,
        "message": f"Live trading started for {config['symbol']}",
        "config": config
    }


@router.post("/stop/{session_id}")
async def stop_trading(session_id: str):
    """Stop a live trading session"""
    if session_id not in active_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = active_sessions[session_id]
    session.stop()
    del active_sessions[session_id]
    
    logger.info(f"🛑 LIVE TRADING STOPPED: Session {session_id}")
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


@router.post("/kill-switch/activate")
async def activate_kill_switch(reason: str = "Manual activation"):
    """Activate emergency kill switch"""
    risk_controls = get_risk_controls()
    risk_controls.activate_kill_switch(reason)
    return {"success": True, "message": "Kill switch activated"}


@router.post("/kill-switch/deactivate")
async def deactivate_kill_switch():
    """Deactivate kill switch"""
    risk_controls = get_risk_controls()
    risk_controls.deactivate_kill_switch()
    return {"success": True, "message": "Kill switch deactivated"}


@router.get("/risk-status/{account_id}")
async def get_risk_status(account_id: int, db: Session = Depends(get_db)):
    """Get current risk status for an account"""
    account = db.query(MT5Account).filter(MT5Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    risk_controls = get_risk_controls()
    return risk_controls.get_status(str(account_id), account.starting_balance)


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
                "managed_positions": len(s.managed_positions),
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
        "trades": session.trades[-10:],
        "managed_positions": list(session.managed_positions.keys()),
        "config": session.config
    }
