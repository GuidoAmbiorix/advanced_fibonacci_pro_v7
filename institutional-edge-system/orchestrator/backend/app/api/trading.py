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
from app.core.mt5_connector import MT5Connector
from app.engines.golden.core import GoldenEngine
from app.engines.factory import EngineFactory
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
    enable_trailing_stop: bool = True
    # Engine Config
    engine_type: str = "ADAPTIVE"
    trading_session: str = "ALL" # session override
    engine_config: Optional[Dict] = {}
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
        # Initialize trading engine (Golden Engine)
        golden_config = config.copy()
        
        # Merge explicit JSON config from slot (engine_config)
        if 'engine_config' in config and isinstance(config['engine_config'], dict):
            golden_config.update(config['engine_config'])
            
        # Map generic flat config to Golden Engine structure
        # Risk Module
        if 'risk' not in golden_config:
            golden_config['risk'] = {}
        # Ensure we use the latest values from the UI/Slot config
        golden_config['risk']['risk_percent'] = config.get('risk_percent', 1.0)
        golden_config['risk']['atr_sl_multiplier'] = config.get('sl_atr_multiplier', 1.5)
        golden_config['risk']['tp1_ratio'] = config.get('tp_ratio', 1.5)
        
        # Pass Account Balance for Sizing
        golden_config['balance'] = account.starting_balance
        
        # Structure Module defaults
        if 'structure' not in golden_config:
             golden_config['structure'] = {}
        golden_config['structure']['zigzag_lookback'] = 5 # Default
        
        # Determine Engine Type
        engine_type = config.get('engine_type', 'golden').upper()
        
        # FIX: XAU_PRO specific config mapping (Match BacktestEngine logic)
        if engine_type == 'XAU_PRO' or engine_type in ['SILVER', 'BRONZE', 'PLATINUM', 'ADAPTIVE']:
            # InstitutionalGoldEngine expects these at root level
            golden_config['rr_ratio'] = config.get('tp_ratio', 2.0)
            golden_config['sl_atr_multiplier'] = config.get('sl_atr_multiplier', 1.5)
            # RSI Thresholds mapping
            golden_config['rsi_buy_threshold'] = config.get('rsi_oversold', 40)
            golden_config['rsi_sell_threshold'] = config.get('rsi_overbought', 60)
            
            # Ensure SMC params are passed if present in root config
            golden_config['enable_order_blocks'] = config.get('enable_order_blocks', True)
            golden_config['ob_lookback'] = config.get('ob_lookback', 20)
            golden_config['enable_liquidity_sweep'] = config.get('enable_liquidity_sweep', True)
            golden_config['sweep_lookback'] = config.get('sweep_lookback', 10)
            golden_config['enable_fvg'] = config.get('enable_fvg', True)
            golden_config['fvg_min_size_atr'] = config.get('fvg_min_size_atr', 0.5)
            
            # CRITICAL LOOP FIX: Pass Session Mode to Engine
            # 'trading_session' (Frontend) -> 'session_mode' (Engine)
            golden_config['session_mode'] = config.get('trading_session', 'ALL') 
            
            logger.info(f"✅ Live Session: Mapped XAU_PRO config (RR: {golden_config['rr_ratio']}, Session: {golden_config['session_mode']})")

        self.engine = EngineFactory.create_engine(engine_type, golden_config)
    
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
                        # TODO: Implement News Service. MT5Connector does not provide news.
                        self.engine.update_news([]) 
                        last_news_update = datetime.utcnow()
                    except Exception as e:
                        logger.error(f"Failed to update news: {e}")

                # 0. Check kill switch
                if self.risk_controls.is_kill_switch_active():
                    logger.warning(f"⛔ {self.session_id}: Kill switch active - pausing")
                    await asyncio.sleep(10)
                    continue

                # 1. Trading hours check - DISABLED (24/7 trading enabled)
                # utc_now = datetime.utcnow()
                # local_now = utc_now - timedelta(hours=4)
                # if not (0 <= local_now.hour < 12):
                #     logger.debug(f"⛔ {self.session_id}: Outside trading hours")
                #     await asyncio.sleep(60)
                #     continue

                # 1.5 Session Filter (ASIA, LONDON, NY, ALL)
                utc_now = datetime.utcnow()
                trading_session = self.config.get('trading_session', 'ALL')
                session_end_action = self.config.get('session_end_action', 'HOLD')
                
                in_session = self._is_in_trading_session(utc_now.hour, trading_session)
                
                if not in_session and session_end_action == 'DISABLE_NEW':
                    logger.info(f"⛔ {self.session_id}: Outside {trading_session} session (UTC {utc_now.hour}:00) - No New Entries")
                    # Still manage existing positions
                    await self._manage_open_positions()
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
                
                # Dynamic Spread Thresholds
                max_spread = 50.0 # Default High
                if 'BTC' in symbol or 'ETH' in symbol:
                    max_spread = 15000.0 # Crypto (Raw points often huge)
                elif 'XAU' in symbol or 'GOLD' in symbol:
                    max_spread = 100.0   # Gold (10-30 pips normal)
                else: 
                    max_spread = 20.0    # Forex (2 pips = 20 points usually)
                    
                if spread and spread > max_spread:
                    logger.warning(f"⛔ {self.session_id}: High spread: {spread:.1f} > {max_spread}")
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

                # 6.6 Get Confirmation Timeframe data (Multi-TF Analysis)
                df_higher_tf = None
                confirmation_tf = self.config.get('confirmation_timeframe')
                if confirmation_tf:
                    df_higher_tf = self.mt5.get_ohlcv_data(symbol, confirmation_tf, bars=200)
                    if df_higher_tf is None or len(df_higher_tf) < 50:
                        logger.warning(f"{self.session_id}: {confirmation_tf} data missing for confirmation")

                # 7. Analyze for signals
                analysis = self.engine.analyze(df, df_higher_tf=df_higher_tf, df_daily=df_daily)
                signals = analysis.get('signals', [])
                
                if signals:
                    logger.info(f"{self.session_id}: Found {len(signals)} signals")
                    
                    from types import SimpleNamespace
                    for signal_data in signals:
                        # Convert dict to object for compatibility
                        if isinstance(signal_data, dict):
                            # Handle 'price' vs 'entry_price' mapping
                            if 'entry_price' not in signal_data and 'price' in signal_data:
                                signal_data['entry_price'] = signal_data['price']
                            signal = SimpleNamespace(**signal_data)
                            if not hasattr(signal, 'confluence_score'):
                                signal.confluence_score = 10 
                        else:
                            signal = signal_data
                        # Direction filter
                        if direction != 'BOTH':
                            if direction == 'BUY_ONLY' and signal.signal_type != 'BUY':
                                continue
                            if direction == 'SELL_ONLY' and signal.signal_type != 'SELL':
                                continue
                        
                        # Confluence filter
                        # signal is a dictionary or object? In GoldenEngine it's a dict. 
                        # But code accesses signal.confluence_score (object attribute access).
                        # GoldenEngine returns dicts (line 194 core.py).
                        # Accessing defaults if missing to avoid attribute error if it's a dict.
                        if hasattr(signal, 'confluence_score') and signal.confluence_score < self.config['min_confluence_score']:
                            continue
                        
                        # Check existing positions
                        positions = self.mt5.get_open_positions(symbol)
                        if positions:
                            logger.info(f"{self.session_id}: Position already open for {symbol}")
                            continue
                            
                        # Execute trade
                        await self._execute_trade(signal, account_info)

                else:
                    try:
                        struct = analysis.get('structure') or {} # Handle None explicitly
                        trend = struct.trend if hasattr(struct, 'trend') else struct.get('trend', 'Unknown')
                    except Exception as e:
                        logger.error(f"Trend extraction error: {e}, StructType: {type(analysis.get('structure'))}")
                        trend = 'Unknown'
                    
                    if trend == 'Unknown':
                         s = analysis.get('structure')
                         logger.warning(f"Trend is Unknown. Struct Type: {type(s)}, Content: {s}")

                    debug_info = analysis.get('debug_info', {})
                    logger.info(
                        f"Analysis complete: No signals found for {symbol}. "
                        f"Session: {trading_session}. "
                        f"Structure: {trend}. "
                        f"Debug: RSI={debug_info.get('rsi', 'N/A')}, "
                        f"SMC={debug_info.get('smc', 'N/A')}, "
                        f"Zone={debug_info.get('in_zone', 'N/A')}, "
                        f"Conf={debug_info.get('indicators_aligned', 'N/A')}"
                    )

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
        
        # Prepare trade comment with slot identification
        slot_id = self.config.get('slot_id', 0)
        magic_number = self.config.get('magic_number', 0)
        trade_comment = f"Slot{slot_id}-M{magic_number}" if magic_number else f"Live-{self.session_id}"
        
        result = self.mt5.open_position(
            symbol=symbol,
            order_type=signal.signal_type,
            volume=lot_size,
            stop_loss=signal.stop_loss,
            take_profit=signal.take_profit_1,
            comment=trade_comment
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
                'action': 'OPEN', # Added for Worker compatibility
                'ticket': ticket,
                'symbol': symbol,
                'type': signal.signal_type,
                'volume': lot_size,
                'entry_price': signal.entry_price,
                'stop_loss': signal.stop_loss,
                'take_profit': signal.take_profit_1,
                'session_id': self.session_id,
                'opened_at': datetime.utcnow().isoformat(),
                'master_account_id': self.account.id # Identification for Copier
            }
            self.trades.append(trade_data)
            
            # 1. Emit WebSocket (Frontend)
            try:
                await sio.emit('live_trade_opened', trade_data)
            except Exception as e:
                logger.warning(f"Could not emit trade event: {e}")

            # 2. Publish to RabbitMQ (Worker Nodes / Slaves)
            try:
                from app.services.rabbitmq_service import RabbitMQService
                # Use a lightweight instance or shared service
                rmq = RabbitMQService() 
                await rmq.publish_signal(trade_data)
                # Note: creating new instance every time might be inefficient but works for now.
                # Ideally, pass rmq instance in __init__
            except Exception as e:
                logger.error(f"Failed to publish signal to RabbitMQ: {e}")

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
            # Check activation condition: breakeven moved AND profit >= tsl_activation_r
            tsl_activation_r = self.config.get('tsl_activation_r', 0.0)
            sl_distance = abs(entry_price - managed['stop_loss']) if managed['stop_loss'] else 0
            current_r_profit = (profit_points * self.mt5.get_symbol_point(pos['symbol']) / sl_distance) if sl_distance > 0 else 0
            
            tsl_activated = managed['breakeven_moved'] and current_r_profit >= tsl_activation_r
            
            if self.config.get('enable_trailing_stop', True) and tsl_activated:
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
    
    def _is_in_trading_session(self, utc_hour: int, session: str) -> bool:
        """
        Check if current UTC hour is within the configured trading session.
        
        Session times (UTC):
        - ASIA: 00:00 - 07:00
        - LONDON: 07:00 - 16:00
        - NY: 12:00 - 21:00
        - ASIA_LONDON: 00:00 - 16:00
        - LONDON_NY: 07:00 - 21:00
        - ALL: Always True
        """
        if session == 'ALL':
            return True
        
        session_times = {
            'ASIA': (0, 7),
            'LONDON': (6, 15), # 2:00 AM RD (UTC-4) = 6:00 UTC
            'NY': (12, 21),    # 8:00 AM RD (UTC-4) = 12:00 UTC
            'ASIA_LONDON': (0, 15),
            'LONDON_NY': (6, 21),
        }
        
        if session in session_times:
            start, end = session_times[session]
            return start <= utc_hour < end
        
        # Unknown session = allow trading
        return True
    
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
    slot = None
    
    if request.slot_id:
        slot = db.query(BotSlot).filter(BotSlot.id == request.slot_id).first()
        if not slot:
            raise HTTPException(status_code=404, detail=f"Slot {request.slot_id} not found")
    elif request.symbol:
        # Auto-detect slot by symbol to enforce DB config (e.g. Killzones)
        stripped_symbol = request.symbol.strip()
        logger.info(f"🔍 DEBUG: Attempting auto-detect for symbol: '{request.symbol}' (Stripped: '{stripped_symbol}')")
        
        slot = db.query(BotSlot).filter(
            BotSlot.symbol == stripped_symbol, 
            BotSlot.enabled == True
        ).first()
        
        if slot:
            logger.info(f"✨ Auto-detected Slot {slot.id} for {request.symbol} - Loading DB Config")
        else:
            logger.warning(f"⚠️ DEBUG: Auto-detect FAILED for symbol: '{stripped_symbol}'. No enabled slot found in DB.")


    if slot:
        if not slot.enabled:
            raise HTTPException(status_code=400, detail=f"Slot {slot.id} is disabled")

        
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
            # Enhanced Params (Adaptive Engine)
            'use_adx_filter': slot.use_adx_filter,
            'use_h1_trend_filter': slot.use_h1_trend_filter,
            'stoch_k_period': slot.stoch_k_period,
            'stoch_d_period': slot.stoch_d_period,
            'vwap_use_trend_filter': slot.vwap_use_trend_filter,
            'use_daily_bias': slot.use_daily_bias,
            # Session Control
            'trading_session': slot.trading_session,
            'session_end_action': slot.session_end_action,
            # Multi-Timeframe
            'confirmation_timeframe': slot.confirmation_timeframe,
            # TSL Advanced
            'tsl_activation_r': slot.tsl_activation_r,
            # MT5 Tracking
            'magic_number': slot.magic_number,
            # TradingView Integration
            'respect_user_zones': slot.respect_user_zones,
            # Engine Configuration
            'engine_type': slot.engine_type,
            'engine_config': slot.engine_config,
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


@router.get("/sessions")
async def get_active_sessions():
    """Get all active trading sessions"""
    sessions_data = []
    for s_id, session in active_sessions.items():
        # Calculate approximate PnL from closed trades in session
        session_pnl = sum(t.get('pnl', 0.0) for t in session.trades)
        
        sessions_data.append({
            "id": s_id,
            "symbol": session.config.get('symbol'),
            "pnl": round(session_pnl, 2),
            "status": "RUNNING" if session.is_running else "STOPPED",
            "startTime": session.managed_positions[next(iter(session.managed_positions))]['opened_at'].isoformat() if session.managed_positions else "N/A"
        })
    return sessions_data

@router.get("/risk-status-details/{account_id}")
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
