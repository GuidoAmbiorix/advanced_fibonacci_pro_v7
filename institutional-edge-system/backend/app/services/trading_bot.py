"""
============================================================================
Automated Trading Bot Service
============================================================================
Runs continuous market analysis and executes trades automatically
"""

import asyncio
from typing import Dict, Optional
from datetime import datetime
from loguru import logger

from app.core.trading_engine import TradingEngine
from app.core.mt5_connector import MT5Connector
from app.services.trade_manager import TradeManager
from app.models.database import BotConfig, Trade, Signal
from app.api.database import SessionLocal


from app.services.rabbitmq_service import RabbitMQService
from app.core.config import settings

class TradingBot:
    """
    Automated trading bot that runs continuously
    """

    def __init__(self, bot_config_id: int, mt5_connector: MT5Connector, sio):
        """
        Initialize trading bot

        Args:
            bot_config_id: Database ID of bot configuration
            mt5_connector: MT5 connector instance
            sio: Socket.IO server instance
        """
        self.bot_config_id = bot_config_id
        self.mt5_connector = mt5_connector
        self.sio = sio
        self.rabbitmq = RabbitMQService()
        
        self.is_running = False
        self.config: Optional[BotConfig] = None
        self.trading_engine: Optional[TradingEngine] = None
        self.trade_manager: Optional[TradeManager] = None
        self.last_analysis_time: Optional[datetime] = None
        self.open_positions_count = 0

        logger.info("Trading bot initialized for config ID: {}", bot_config_id)

    async def start(self):
        """Start the trading bot"""
        self.is_running = True
        logger.info("Starting trading bot {}", self.bot_config_id)

        # Connect to RabbitMQ
        await self.rabbitmq.connect()

        # Load configuration
        self._load_config()

        # Initialize trading engine
        self._init_trading_engine()
        
        # Initialize trade manager with config
        self.trade_manager = TradeManager(self.mt5_connector)
        self.trade_manager.be_trigger_r = self.config.be_trigger
        self.trade_manager.use_trailing_sl = self.config.trailing_sl
        self.trade_manager.trailing_step_r = self.config.trailing_step
        self.trade_manager.trailing_distance_r = self.config.trailing_distance
        
        # Advanced TSL Config
        self.trade_manager.tsl_mode = self.config.tsl_mode
        self.trade_manager.tsl_activation_r = self.config.tsl_activation_r
        self.trade_manager.tsl_atr_period = self.config.tsl_atr_period
        self.trade_manager.tsl_atr_multiplier = self.config.tsl_atr_multiplier
        self.trade_manager.timeframe = self.config.timeframe
        
        self.trade_manager.partial_tp_on = self.config.partial_tp_on
        self.trade_manager.partial_tp_amount = self.config.partial_tp_amount

        # Start main loop
        await self._run_loop()

    async def stop(self):
        """Stop the trading bot"""
        self.is_running = False
        await self.rabbitmq.close()
        logger.info("Stopping trading bot {}", self.bot_config_id)

    # ... (rest of methods) ...

    async def _execute_signal(self, signal):
        """Execute a trading signal"""
        
        # ... (checks) ...

        # Publish to RabbitMQ for execution
        signal_data = {
            "symbol": signal.symbol,
            "signal_type": signal.signal_type,
            "entry_price": signal.entry_price,
            "stop_loss": signal.stop_loss,
            "take_profit": signal.take_profit_1,
            "risk_percent": self.config.risk_percent,
            "confluence_score": signal.confluence_score
        }
        
        await self.rabbitmq.publish_signal(signal_data)
        
        # Also execute locally for now (Hybrid Mode) until Worker is fully tested
        # ... (existing execution logic) ...

    def _load_config(self):
        """Load bot configuration from database"""
        db = SessionLocal()
        try:
            self.config = db.query(BotConfig).filter(
                BotConfig.id == self.bot_config_id
            ).first()

            if not self.config:
                raise ValueError(f"Bot config {self.bot_config_id} not found")

            logger.info("Loaded config: {} - {} {}",
                       self.config.name, self.config.symbol, self.config.timeframe)
        finally:
            db.close()

    def _init_trading_engine(self):
        """Initialize the trading engine with config"""
        engine_config = {
            'symbol': self.config.symbol,
            'timeframe': self.config.timeframe,
            'swing_length': self.config.swing_length,
            'ob_lookback': self.config.ob_lookback,
            'fvg_min_size': self.config.fvg_min_size,
            'min_confluence_score': self.config.min_confluence_score,
            'vp_lookback': self.config.vp_lookback,
        }

        self.trading_engine = TradingEngine(engine_config)
        logger.info("Trading engine initialized")

    async def _run_loop(self):
        """Main trading loop"""
        while self.is_running:
            try:
                # Check if bot is still active in DB
                if not self._is_bot_active():
                    logger.info("Bot {} is no longer active, stopping", self.bot_config_id)
                    break

                # Update open positions count
                self._update_positions_count()
                
                # Manage existing trades (BE, Trailing SL)
                if self.mt5_connector and self.mt5_connector.connected:
                    positions = self.mt5_connector.get_open_positions(self.config.symbol)
                    self.trade_manager.update_trades(positions)

                # Run market analysis
                await self._analyze_market()

                # Wait before next iteration (1 minute for lower timeframes, 5 minutes for higher)
                wait_time = 60 if self.config.timeframe in ['M1', 'M5', 'M15'] else 300
                await asyncio.sleep(wait_time)

            except Exception as e:
                logger.exception("Error in trading bot loop: {}", e)
                await asyncio.sleep(60)  # Wait 1 minute on error

    def _is_bot_active(self) -> bool:
        """Check if bot is still active in database"""
        db = SessionLocal()
        try:
            config = db.query(BotConfig).filter(
                BotConfig.id == self.bot_config_id
            ).first()
            return config and config.is_active
        finally:
            db.close()

    def _update_positions_count(self):
        """Update count of open positions"""
        if not self.mt5_connector or not self.mt5_connector.connected:
            return

        positions = self.mt5_connector.get_open_positions(self.config.symbol)
        self.open_positions_count = len(positions)

    async def _analyze_market(self):
        """Analyze market and execute trades if signals found"""
        if not self.mt5_connector or not self.mt5_connector.connected:
            await self._log_activity("MT5 not connected, skipping analysis", "warning")
            return

        # Get market data for current timeframe
        df = self.mt5_connector.get_ohlcv_data(
            self.config.symbol,
            self.config.timeframe,
            bars=500
        )

        if df is None or len(df) == 0:
            logger.warning("No market data available for {}", self.config.symbol)
            return

        # Get higher timeframe data for multi-timeframe analysis (H4 if on H1, D1 if on H4)
        df_higher_tf = None
        if self.config.timeframe == "H1":
            df_higher_tf = self.mt5_connector.get_ohlcv_data(
                self.config.symbol,
                "H4",
                bars=200
            )
        elif self.config.timeframe == "M15":
            df_higher_tf = self.mt5_connector.get_ohlcv_data(
                self.config.symbol,
                "H1",
                bars=200
            )

        # Run analysis with multi-timeframe data
        analysis = self.trading_engine.analyze(df, df_higher_tf)

        if 'error' in analysis:
            logger.error("Analysis error: {}", analysis['error'])
            return

        # Log analysis results
        await self._log_activity(
            "Analysis complete - H TF: {}, Bull: {}/10, Bear: {}/10, Signals: {}".format(
                analysis.get('higher_tf_trend', 'N/A'),
                analysis['bull_confluence_score'],
                analysis['bear_confluence_score'],
                len(analysis['signals'])
            )
        )

        # Save signals to database
        await self._save_signals(analysis['signals'])

        # Execute trades if conditions are met
        for signal in analysis['signals']:
            # Check AI confidence threshold (if available)
            ai_confidence = getattr(signal, 'ai_confidence', 0)
            ai_recommendation = getattr(signal, 'ai_recommendation', 'UNCERTAIN')

            # Minimum AI confidence threshold (45% = cautious threshold)
            min_ai_confidence = 45.0

            if ai_confidence > 0 and ai_confidence < min_ai_confidence:
                await self._log_activity(
                    "Skipping signal - AI confidence too low: {:.1f}% ({})".format(ai_confidence, ai_recommendation),
                    "warning"
                )
                continue

            await self._execute_signal(signal)

        # Update last analysis time in DB
        self._update_last_analysis_time()

    async def _save_signals(self, signals: list):
        """Save trading signals to database"""
        if not signals:
            return

        db = SessionLocal()
        try:
            for sig in signals:
                signal = Signal(
                    symbol=sig.symbol,
                    timeframe=sig.timeframe,
                    signal_type=sig.signal_type,
                    price=sig.entry_price,
                    stop_loss=sig.stop_loss,
                    take_profit=sig.take_profit_2,
                    confluence_score=sig.confluence_score,
                    score_breakdown=sig.score_breakdown,
                    ai_confidence=sig.ai_confidence,
                    ai_recommendation=sig.ai_recommendation,
                    trend=self.trading_engine.trend_bullish and "BULLISH" or "BEARISH",
                    poc_level=self.trading_engine.poc_level,
                    was_executed=False
                )
                db.add(signal)

            db.commit()
            logger.info("Saved {} signals to database", len(signals))
            
            # Emit event
            for sig in signals:
                await self.sio.emit('signal_generated', {
                    'symbol': sig.symbol,
                    'signal_type': sig.signal_type,
                    'price': sig.entry_price,
                    'stop_loss': sig.stop_loss,
                    'take_profit': sig.take_profit_2,
                    'confluence_score': sig.confluence_score,
                    'created_at': datetime.utcnow().isoformat()
                })
                
        except Exception as e:
            logger.exception("Error saving signals: {}", e)
            db.rollback()
        finally:
            db.close()

    async def _execute_signal(self, signal):
        """Execute a trading signal"""
        # 0. Check Existing Position
        existing_positions = self.mt5_connector.get_open_positions(symbol=signal.symbol)
        if existing_positions:
            await self._log_activity(f"Position already exists for {signal.symbol}, skipping signal", "warning")
            return

        # 1. Check Max Trades
        if self.open_positions_count >= self.config.max_trades:
            await self._log_activity(f"Max trades ({self.config.max_trades}) reached, skipping signal", "warning")
            return

        # 2. Check Spread
        if not self._check_spread(signal.symbol):
            await self._log_activity(f"Spread too high for {signal.symbol}, skipping", "warning")
            return

        # 3. Check Trading Hours
        if not self._check_trading_hours():
            await self._log_activity("Outside trading hours, skipping", "warning")
            return

        # 4. Check Daily Risk
        if not self._check_daily_risk():
            await self._log_activity("Daily risk limit reached, skipping", "warning")
            return

        # Publish to RabbitMQ (Decoupled Execution)
        await self.rabbitmq.publish_signal({
            "symbol": signal.symbol,
            "signal_type": signal.signal_type,
            "entry_price": signal.entry_price,
            "stop_loss": signal.stop_loss,
            "take_profit": signal.take_profit_1,
            "risk_percent": self.config.risk_percent,
            "confluence_score": signal.confluence_score,
            "bot_config_id": self.bot_config_id
        })

        # Get account info for position sizing
        account_info = self.mt5_connector.get_account_info()
        if not account_info:
            logger.error("Failed to get account info")
            return

        # Calculate position size
        sl_distance = abs(signal.entry_price - signal.stop_loss)
        lot_size = self.mt5_connector.calculate_lot_size(
            symbol=signal.symbol,
            risk_percent=self.config.risk_percent,
            sl_distance=sl_distance,
            account_balance=account_info['balance']
        )

        await self._log_activity(
            "Opening {} position: {} lots @ {} (SL: {}, TP: {})".format(
                signal.signal_type, lot_size, signal.entry_price, signal.stop_loss, signal.take_profit_1
            )
        )

        # Open position
        result = self.mt5_connector.open_position(
            symbol=signal.symbol,
            order_type=signal.order_type, # Use the order type from signal (MARKET/LIMIT/STOP)
            volume=lot_size,
            stop_loss=signal.stop_loss,
            take_profit=signal.take_profit_1,
            price=signal.entry_price, # Pass entry price for pending orders
            comment=f"IEP Bot - Conf: {signal.confluence_score}/10"
        )

        if result and result.get('success'):
            # Save trade to database
            trade_id = await self._save_trade(signal, result, lot_size)
            self.open_positions_count += 1
            await self._log_activity(f"✅ Trade opened successfully - Ticket: {result['ticket']}", "success")
        else:
            error_msg = result.get('error', 'Unknown error') if result else 'Unknown error'
            await self._log_activity(f"❌ Failed to open trade: {error_msg}", "error")

    async def _log_activity(self, message: str, level: str = "info"):
        """Log activity and emit event"""
        # Log to console/file
        if level == "error":
            logger.error(message)
        elif level == "warning":
            logger.warning(message)
        else:
            logger.info(message)
            
        # Emit to frontend
        try:
            await self.sio.emit('bot_activity', {
                'bot_id': self.bot_config_id,
                'message': message,
                'level': level,
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            logger.error(f"Failed to emit activity log: {e}")



    async def _save_trade(self, signal, result: Dict, lot_size: float) -> int:
        """Save executed trade to database"""
        db = SessionLocal()
        try:
            trade = Trade(
                user_id=self.config.user_id,
                ticket=result['ticket'],
                symbol=signal.symbol,
                trade_type=signal.signal_type,
                entry_price=result['price'],
                stop_loss=signal.stop_loss,
                take_profit_1=signal.take_profit_1,
                take_profit_2=signal.take_profit_2,
                take_profit_3=signal.take_profit_3,
                volume=lot_size,
                risk_percent=self.config.risk_percent,
                confluence_score=signal.confluence_score,
                score_breakdown=signal.score_breakdown,
                status="OPEN"
            )

            db.add(trade)
            db.commit()
            db.refresh(trade)
            db.refresh(trade)
            logger.info("Trade saved to database - ID: {}", trade.id)
            
            # Emit event
            await self.sio.emit('trade_opened', {
                'ticket': trade.ticket,
                'symbol': trade.symbol,
                'type': trade.trade_type,
                'volume': trade.volume,
                'entry': trade.entry_price,
                'sl': trade.stop_loss,
                'tp': trade.take_profit_1,
                'pnl': 0.0
            })
            
            return trade.id
        except Exception as e:
            logger.exception("Error saving trade: {}", e)
            db.rollback()
            return None
        finally:
            db.close()

    def _update_last_analysis_time(self):
        """Update last analysis time in config"""
        db = SessionLocal()
        try:
            config = db.query(BotConfig).filter(
                BotConfig.id == self.bot_config_id
            ).first()

            if config:
                config.last_signal_time = datetime.utcnow()
                db.commit()
        except Exception as e:
            logger.exception("Error updating last analysis time: {}", e)
            db.rollback()
        finally:
            db.close()


    def _check_spread(self, symbol: str) -> bool:
        """Check if spread is within limits"""
        price_info = self.mt5_connector.get_current_price(symbol)
        if not price_info:
            return False
        
        # Calculate spread in pips/points
        # Default to standard Forex pip (0.0001)
        pip_size = 0.0001
        if "JPY" in symbol:
            pip_size = 0.01
        
        spread_val = price_info['spread'] / pip_size
        
        # Check if spread is reasonable for Forex (e.g. < 100 pips)
        # If it's huge (like 5000), it's likely Crypto or Index priced in USD
        # In that case, switch to percentage check
        
        is_valid = spread_val <= self.config.max_spread
        
        # Fallback: If spread in pips is high, check percentage
        # Allow if spread is less than 0.1% of price (configurable later)
        if not is_valid:
            spread_percent = (price_info['spread'] / price_info['ask']) * 100
            if spread_percent < 0.1: # 0.1% spread is reasonable for Crypto
                is_valid = True
            else:
                # Log the actual values to help debugging
                logger.warning(f"Spread too high for {symbol}: {spread_val:.1f} pips / {spread_percent:.3f}% > Limit")
            
        return is_valid

    def _check_trading_hours(self) -> bool:
        """Check if current time is within trading hours"""
        now = datetime.utcnow().strftime("%H:%M")
        return self.config.trading_hours_start <= now <= self.config.trading_hours_end

    def _check_daily_risk(self) -> bool:
        """Check if daily loss limit has been reached"""
        # Calculate daily PnL from closed trades today
        db = SessionLocal()
        try:
            today = datetime.utcnow().date()
            trades = db.query(Trade).filter(
                Trade.user_id == self.config.user_id,
                Trade.closed_at >= datetime.combine(today, datetime.min.time())
            ).all()
            
            daily_pnl = sum(t.profit_loss for t in trades)
            
            # Get account balance to calculate %
            account_info = self.mt5_connector.get_account_info()
            if not account_info:
                return True # Fail safe
                
            balance = account_info['balance']
            daily_pnl_percent = (daily_pnl / balance) * 100
            
            # If loss is greater than limit (e.g. -4% < -3%)
            if daily_pnl_percent < -self.config.daily_loss_limit_percent:
                return False
                
            return True
        finally:
            db.close()


class BotManager:
    """
    Manages multiple trading bots
    """

    def __init__(self, mt5_connector: MT5Connector, sio):
        self.mt5_connector = mt5_connector
        self.sio = sio
        self.bots: Dict[int, TradingBot] = {}
        self.tasks: Dict[int, asyncio.Task] = {}

    async def start_bot(self, bot_config_id: int):
        """Start a trading bot"""
        if bot_config_id in self.bots:
            logger.warning("Bot {} already running", bot_config_id)
            return

        bot = TradingBot(bot_config_id, self.mt5_connector, self.sio)
        self.bots[bot_config_id] = bot

        # Run bot in background task
        task = asyncio.create_task(bot.start())
        self.tasks[bot_config_id] = task

        logger.info("Bot {} started", bot_config_id)

    async def stop_bot(self, bot_config_id: int):
        """Stop a trading bot"""
        if bot_config_id not in self.bots:
            logger.warning("Bot {} not running", bot_config_id)
            return

        bot = self.bots[bot_config_id]
        await bot.stop()

        # Cancel task
        if bot_config_id in self.tasks:
            self.tasks[bot_config_id].cancel()
            del self.tasks[bot_config_id]

        del self.bots[bot_config_id]
        logger.info("Bot {} stopped", bot_config_id)

    async def stop_all(self):
        """Stop all running bots"""
        for bot_id in list(self.bots.keys()):
            await self.stop_bot(bot_id)

    def get_running_bots(self) -> list:
        """Get list of running bot IDs"""
        return list(self.bots.keys())
