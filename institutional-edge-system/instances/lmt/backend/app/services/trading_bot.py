"""
============================================================================
Automated Trading Bot Service
============================================================================
Runs continuous market analysis and executes trades automatically
"""

import asyncio
from typing import Dict, Optional
from datetime import datetime, timedelta
from loguru import logger

from app.engines.factory import EngineFactory
from app.core.mt5_connector import MT5Connector
from app.services.trade_manager import TradeManager
# from app.services.risk_manager import AdaptiveRiskManager # Deleted
from app.services.portfolio_manager import PortfolioManager
from app.services.discord_service import DiscordService
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
        self.sio = sio

        self.rabbitmq = RabbitMQService()
        self.discord = DiscordService()
        
        self.is_running = False
        self.config: Optional[BotConfig] = None
        
        # Multi-Account Workers
        self.workers = {} # {account_id: {'process': Process, 'queues': (cmd, resp)}}
        
        self.trading_engine = None # Assigned by Factory
        self.trade_manager: Optional[TradeManager] = None
        # self.risk_manager: Optional[AdaptiveRiskManager] = None # Removed
        self.portfolio_manager: Optional[PortfolioManager] = None
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



        # Initialize trade manager (Primary for Analysis context)
        # Note: In multi-account, TradeManager primarily tracks 'Master' or aggregates data
        self.trade_manager = TradeManager(self.mt5_connector)
        # ... (rest of init kept for backward compat or master logic)
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
        
        self.trade_manager._init_tsl_manager()
        logger.info(f"Trade Manager configured: TSL={self.config.tsl_mode}")

        # Risk Manager Removed as per request
        # self.risk_manager = AdaptiveRiskManager()
        
        # Initialize Portfolio Manager
        self.portfolio_manager = PortfolioManager()

        # Start main loop
        # Start main loop or Slave Listener
        role = settings.INSTANCE_ROLE.upper()
        if role == "SLAVE":
            logger.info("⚔️ SLAVE MODE: Listening for signals...")
            await self.rabbitmq.consume_signals(self._on_slave_signal)
        else:
            logger.info(f"👑 {role} MODE: Starting Analysis Engine...")
            self._init_trading_engine()
            self._init_workers()
            await self._run_loop()

    async def stop(self):
        """Stop the trading bot"""
        self.is_running = False
        await self.rabbitmq.close()
        
        # Stop Workers
        self._stop_workers()
        
        logger.info("Stopping trading bot {}", self.bot_config_id)
        
    async def _on_slave_signal(self, signal_data: dict):
        """Callback for Slave Mode: Execute incoming Master signal"""
        try:
            # 1. Validation
            symbol = signal_data.get('symbol')
            if not symbol: 
                return
            
            # --- FILTERING LOGIC ---
            
            # A) Exclusion Check (FundingPips Requirement: Exclude XAUUSD etc.)
            excluded = getattr(self.config, 'excluded_symbols', []) or []
            if symbol in excluded:
                logger.info(f"🛡️ SLAVE IGNORE: {symbol} is in excluded list.")
                return

            # B) Inclusion Check (Universal vs Strict)
            # If config.symbol is "ALL" or "COPY_MASTER", we accept everything (unless excluded above)
            # Otherwise, we enforce strict 1-to-1 matching.
            configured_symbol = self.config.symbol
            is_universal_slave = configured_symbol in ["ALL", "COPY_MASTER", "*"]
            
            if not is_universal_slave and symbol != configured_symbol:
                 # Strict mode: mismatch
                 return

            logger.info(f"📥 SLAVE EVENT: {signal_data['signal_type']} {symbol} @ {signal_data['entry_price']}")

            # 2. Execution (Zero-Latency mode)
            # We use our OWN risk settings, but copy the levels (SL/TP)
            result = self.mt5_connector.open_position(
                symbol=symbol,
                order_type=signal_data['signal_type'], # "BUY" or "SELL"
                stop_loss=signal_data['stop_loss'],
                take_profit=signal_data['take_profit'],
                # Volume will be calculated by connector based on OUR account balance & config risk
                # If we passed 'volume' it would force it. Passing None/0 triggers calc.
            )
            
            if result and result.get('success'):
                logger.info(f"✅ SLAVE COPIED: Ticket {result['ticket']}")
            else:
                logger.error(f"❌ SLAVE FAILED: {result.get('error')}")

        except Exception as e:
            logger.error(f"Slave Signal Error: {e}")

    def _init_workers(self):
        """Spawn AccountWorker processes for each linked account"""
        from app.services.account_worker import AccountWorker
        import multiprocessing
        
        db = SessionLocal()
        try:
            # Refresh config to get accounts
            config = db.query(BotConfig).filter(BotConfig.id == self.bot_config_id).first()
            if not config.accounts:
                logger.warning("No accounts linked to this bot! Running in Analysis-Only mode.")
                return

            for account in config.accounts:
                worker_id = f"Bot{self.bot_config_id}-Acc{account.id}"
                
                # Setup Communication Queues
                cmd_q = multiprocessing.Queue()
                resp_q = multiprocessing.Queue()
                
                # Account Config Payload
                acc_config = {
                    "login": account.login,
                    "password": account.password_encrypted, # Decrypt if needed
                    "server": account.server,
                    "terminal_path": account.terminal_path
                }
                
                # Spawn Process
                p = AccountWorker(worker_id, acc_config, cmd_q, resp_q)
                p.start()
                
                self.workers[account.id] = {
                    "process": p,
                    "cmd": cmd_q,
                    "resp": resp_q
                }
                logger.info(f"Spawned Worker for Account {account.login} (PID: {p.pid})")
                
        except Exception as e:
            logger.error(f"Failed to init workers: {e}")
        finally:
            db.close()

    def _stop_workers(self):
        """Gracefully stop all workers"""
        for acc_id, w_data in self.workers.items():
            try:
                w_data['cmd'].put({'type': 'STOP'})
                w_data['process'].join(timeout=3)
                if w_data['process'].is_alive():
                    w_data['process'].terminate()
            except Exception as e:
                logger.error(f"Error stopping worker {acc_id}: {e}")
        self.workers.clear()

    async def _execute_signal(self, signal):
        """Execute a trading signal on ALL connected accounts"""
        
        # ... (checks) ...

        await self._log_activity(f"Broadcasting Signal {signal.direction} to {len(self.workers)} accounts...")

        # Construct Command Payload
        sl_pips = abs(signal.entry_price - signal.stop_loss) * 100 # Approx, cleaner logic needed per symbol
        
        trade_cmd = {
            "type": "OPEN_TRADE",
            "payload": {
                "symbol": signal.symbol,
                "type": signal.direction, # BUY/SELL
                "sl": signal.stop_loss,
                "tp": signal.take_profit_1,
                "risk_percent": self.config.risk_percent,
                "sl_pips": sl_pips 
            }
        }
        
        # Broadcast to all workers
        for acc_id, w_data in self.workers.items():
            try:
                w_data['cmd'].put(trade_cmd)
                await self._log_activity(f"Signal sent to Account {acc_id}")
            except Exception as e:
                logger.error(f"Failed to send command to worker {acc_id}: {e}")

        # ... (rest of logic like Notifications) ...

    def _load_config(self):
        """Load bot configuration from database"""
        from sqlalchemy.orm import joinedload
        db = SessionLocal()
        try:
            self.config = db.query(BotConfig).options(
                joinedload(BotConfig.slots)
            ).filter(
                BotConfig.id == self.bot_config_id
            ).first()

            if not self.config:
                raise ValueError(f"Bot config {self.bot_config_id} not found")

            # Access slots to ensure they are loaded before session close (redundant with joinedload but safe)
            if self.config.slots:
                logger.info(f"Loaded {len(self.config.slots)} slots configuration")

            logger.info("Loaded config: {} - {} {}",
                       self.config.name, self.config.symbol, self.config.timeframe)
        finally:
            db.close()

    def _init_trading_engine(self):
        """Initialize the trading engine with config"""
        
        # Infer scalping mode from timeframe
        is_scalping = self.config.timeframe in ['M1', 'M5', 'M15']
        
        engine_config = {
            'symbol': self.config.symbol,
            'timeframe': self.config.timeframe,
            'initial_balance': 1000.0, # Default for live bot internal tracking
            'max_risk_per_trade': self.config.risk_percent,
            'enable_grid_recovery': True, # Default enabled for now
            'grid_levels': 3,
            'scalping_mode': is_scalping,
            
            # Legacy params mapping (if needed by Adaptive Engine internals)
            'swing_length': self.config.swing_length,
            'ob_lookback': self.config.ob_lookback,
            'fvg_min_size': self.config.fvg_min_size,
            'min_confluence_score': self.config.min_confluence_score,
            'vp_lookback': self.config.vp_lookback,
            
            # Strategy Selection (NEW)
            'use_adx_filter': self.config.use_adx_filter,
            'enable_vwap_strategy': self.config.enable_vwap_strategy,
            'enable_stoch_strategy': self.config.enable_stoch_strategy,
            'enable_institutional_strategy': self.config.enable_institutional_strategy,
            'enable_institutional_strategy': self.config.enable_institutional_strategy,
            'enable_fibonacci_strategy': self.config.enable_fibonacci_strategy,
            
            # RSI Settings
            'rsi_period': self.config.rsi_period,
            'rsi_overbought': self.config.rsi_overbought,
            'rsi_oversold': self.config.rsi_oversold,
        }

        # --- SLOT OVERRIDE (CRITICAL FIX) ---
        # If slots are enabled, we must prefer the Slot configuration (Session Mode, Risk, etc.)
        # over the bare BotConfig. Currently we only Support Single-Slot per Bot Instance in this engine.
        if self.config.slots:
             # Find first enabled slot
             active_slot = next((s for s in self.config.slots if s.enabled), None)
             if active_slot:
                 logger.info(f"🎰 Loaded Slot Config: {active_slot.symbol} | Session: {active_slot.session_mode}")
                 
                 # 1. Override Session Mode (Fixes "SKIP KZ" Issue)
                 engine_config['session_mode'] = active_slot.session_mode
                 
                 # 2. Override Risk
                 engine_config['max_risk_per_trade'] = active_slot.risk_percent
                 engine_config['tp_ratio'] = active_slot.tp_ratio
                 engine_config['sl_atr_multiplier'] = active_slot.sl_atr_multiplier
                 
                 # 3. Override Indicators
                 engine_config['rsi_period'] = active_slot.rsi_period
                 engine_config['macd_fast'] = active_slot.macd_fast
                 engine_config['macd_slow'] = active_slot.macd_slow
                 engine_config['macd_signal'] = active_slot.macd_signal
                 
                 # 4. Override Strategies
                 engine_config['use_adx_filter'] = active_slot.use_adx_filter
                 engine_config['enable_vwap_strategy'] = active_slot.enable_vwap_strategy
                 engine_config['enable_stoch_strategy'] = active_slot.enable_stoch_strategy
                 
                 # 5. SMC
                 engine_config['enable_order_blocks'] = active_slot.enable_order_blocks
                 engine_config['ob_lookback'] = active_slot.ob_lookback
                 engine_config['enable_liquidity_sweep'] = active_slot.enable_liquidity_sweep
                 engine_config['sweep_lookback'] = active_slot.sweep_lookback
                 engine_config['enable_fvg'] = active_slot.enable_fvg
                 
                 # 6. Timeframe (Ideally)
                 # self.config.timeframe is already set, but if slot differs, we might need to note it.
                 # For now, we assume BotConfig matches Slot, or we just use Engine params.


        engine_type = getattr(self.config, 'engine_type', 'golden')
        self.trading_engine = EngineFactory.create_engine(engine_type, engine_config)
        logger.info(f"Trading Engine initialized: {engine_type} (Scalping: {is_scalping})")

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

        # Get higher timeframe data for multi-timeframe analysis (Confirmation)
        # Default logic: M1/M5/M15 -> H1, H1 -> H4, H4 -> D1
        confirmation_tf = "H1"
        if self.config.timeframe in ["H1", "H4"]:
            confirmation_tf = "D1"
        elif self.config.timeframe == "D1":
            confirmation_tf = "W1"
            
        df_higher_tf = self.mt5_connector.get_ohlcv_data(
            self.config.symbol,
            confirmation_tf,
            bars=200
        )

        # Get Macro timeframe data (Bias)
        # Default to D1, unless we are already on D1/W1
        macro_tf = "D1"
        if self.config.timeframe in ["D1", "W1", "MN1"]:
            macro_tf = "MN1" # Weekly/Monthly bias for long term
            
        df_macro = self.mt5_connector.get_ohlcv_data(
            self.config.symbol,
            macro_tf,
            bars=200
        )

        # Run analysis with multi-timeframe data
        # Passing df_macro as the third argument (was df_daily in some signatures)
        analysis = self.trading_engine.analyze(df, df_higher_tf, df_macro)

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

        # Send Market Status Update to Discord
        await self.discord.send_market_status_update(analysis)

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
                    signal_type=sig.direction,  # Mapped from direction
                    price=sig.entry_price,
                    stop_loss=sig.stop_loss,
                    take_profit=sig.take_profit, # Mapped from take_profit
                    confluence_score=sig.score,  # Mapped from score
                    score_breakdown=sig.metadata, # Mapped from metadata
                    ai_confidence=sig.confidence,
                    ai_recommendation="TRADE" if sig.confidence > 0.7 else "HOLD",
                    trend=self.trading_engine.current_regime.value, # Use regime instead of trend_bullish
                    poc_level=self.trading_engine.poc_level,
                    status="CREATED",
                    was_executed=False
                )
                db.add(signal)

            db.commit()
            logger.info("Saved {} signals to database", len(signals))
            
            # Emit event
            for sig in signals:
                await self.sio.emit('signal_generated', {
                    'symbol': sig.symbol,
                    'signal_type': sig.direction, # Fixed
                    'price': sig.entry_price,
                    'stop_loss': sig.stop_loss,
                    'take_profit': sig.take_profit, # Fixed
                    'confluence_score': sig.score, # Fixed
                    'created_at': datetime.utcnow().isoformat()
                })

                # Send Discord Alert
                await self.discord.send_signal_alert({
                    'symbol': sig.symbol,
                    'direction': sig.direction, # Fixed
                    'strategy_type': sig.strategy_type.value if sig.strategy_type else 'UNKNOWN',
                    'entry_price': sig.entry_price,
                    'stop_loss': sig.stop_loss,
                    'take_profit': sig.take_profit, # Fixed
                    'confidence': sig.confidence, # Fixed
                    'score': sig.score, # Fixed
                    'timestamp': datetime.utcnow().strftime("%H:%M:%S")
                })
                
        except Exception as e:
            logger.exception("Error saving signals: {}", e)
            db.rollback()
        finally:
            db.close()

    async def _execute_signal(self, signal):
        """Execute a trading signal"""
        # 0. Check Existing Position or Pending Order
        existing_positions = self.mt5_connector.get_open_positions(symbol=signal.symbol)
        pending_orders = self.mt5_connector.get_pending_orders(symbol=signal.symbol)
        
        if existing_positions:
            await self._log_activity(f"Position already exists for {signal.symbol}, skipping signal", "warning")
            return

        if pending_orders:
            await self._log_activity(f"Pending order already exists for {signal.symbol}, skipping signal", "warning")
            return

        # 0.1 Check DB for Active/Pending Signals
        db = SessionLocal()
        try:
            active_signal = db.query(Signal).filter(
                Signal.symbol == signal.symbol,
                Signal.status.in_(["PENDING", "ACTIVE"])
            ).first()
            
            if active_signal:
                await self._log_activity(f"Signal already active/pending for {signal.symbol} (Status: {active_signal.status}), skipping", "warning")
                return
        finally:
            db.close()

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

        # 5. Check Total Drawdown (Account Protection)
        if not self._check_total_drawdown():
            await self._log_activity("Max total drawdown limit reached, skipping", "warning")
            return

        # 5. Check Cooldown
        if not self._check_cooldown(signal.symbol):
            # Log handled inside _check_cooldown
            return

        # Publish to RabbitMQ (Only MASTER or SOLO)
        role = settings.INSTANCE_ROLE.upper()
        if role in ["MASTER", "SOLO"]:
            await self.rabbitmq.publish_signal({
                "symbol": signal.symbol,
                "signal_type": signal.direction, # Fixed
                "entry_price": signal.entry_price,
                "stop_loss": signal.stop_loss,
                "take_profit": signal.take_profit, # Fixed
                "risk_percent": self.config.risk_percent,
                "confluence_score": signal.score, # Fixed
                "bot_config_id": self.bot_config_id
            })

        # Get account info for position sizing
        account_info = self.mt5_connector.get_account_info()
        if not account_info:
            logger.error("Failed to get account info")
            return

        account_balance = account_info['balance']
        account_equity = account_info['equity']

        # STEP 1: Check portfolio-level risk with PortfolioManager
        # Calculate proposed risk for this trade
        sl_distance = abs(signal.entry_price - signal.stop_loss)
        base_risk_percent = self.config.risk_percent  # From config (e.g., 1%)

        # Get current open positions for portfolio check
        open_positions = self.mt5_connector.get_open_positions()

        # Update portfolio manager with current positions
        self.portfolio_manager.positions.clear()
        for pos in open_positions:
            from app.services.portfolio_manager import Position
            self.portfolio_manager.positions.append(Position(
                symbol=pos['symbol'],
                volume=pos['volume'],
                risk_percent=(pos.get('initial_risk_percent', base_risk_percent))
            ))

        # Check if can open new position
        can_open, reason = self.portfolio_manager.can_open_position(
            symbol=signal.symbol,
            proposed_risk=base_risk_percent,
            account_balance=account_balance
        )

        if not can_open:
            await self._log_activity(
                f"🚫 Portfolio Manager blocked trade: {reason}",
                "warning"
            )
            return

        # STEP 2: Calculate adaptive risk using AdaptiveRiskManager
        # Get drawdown info
        peak_balance = account_info.get('peak_balance', account_balance)
        current_dd = ((peak_balance - account_equity) / peak_balance * 100) if peak_balance > 0 else 0.0

        # Get consecutive losses from recent trades
        consecutive_losses = await self._get_consecutive_losses()

        # Calculate risk percentage (Fixed from config now, since adaptive is removed)
        adaptive_risk_percent = self.config.risk_percent
        risk_reason = "Fixed Risk"
        # adaptive_risk_percent, risk_reason = self.risk_manager.calculate_risk_percent(
        #     market_regime="NORMAL",
        #     consecutive_losses=consecutive_losses,
        #     current_volatility_percentile=50,
        #     current_drawdown=current_dd
        # )

        if adaptive_risk_percent == 0:
            await self._log_activity(
                f"🛑 CIRCUIT BREAKER: {risk_reason}",
                "error"
            )
            return

        # STEP 3: Calculate Kelly fraction for optimal sizing
        # Uses recent trade history to determine optimal position size
        kelly_fraction = await self._calculate_kelly_from_history()
        kelly_mode = getattr(self.config, 'kelly_mode', 'HALF')  # Default to conservative Half-Kelly
        
        # STEP 4: Calculate lot size with adaptive risk AND Kelly adjustment
        lot_size = self.mt5_connector.calculate_lot_size(
            symbol=signal.symbol,
            risk_percent=adaptive_risk_percent,  # Use adaptive risk instead of config
            sl_distance=sl_distance,
            account_balance=account_balance,
            kelly_fraction=kelly_fraction,  # Pass Kelly for optimal sizing
            kelly_mode=kelly_mode
        )

        # Log risk adjustment
        if adaptive_risk_percent != base_risk_percent:
            logger.warning(
                f"⚠️ Risk adjusted: {base_risk_percent}% → {adaptive_risk_percent}% ({risk_reason})"
            )

        await self._log_activity(
            "Opening {} position: {} lots @ {} (SL: {}, TP: {})".format(
                signal.direction, lot_size, signal.entry_price, signal.stop_loss, signal.take_profit
            )
        )

        # Determine correct order type for MT5
        # If signal says "MARKET", we use the signal direction (BUY/SELL)
        mt5_order_type = signal.direction

        # Open position
        result = self.mt5_connector.open_position(
            symbol=signal.symbol,
            order_type=mt5_order_type,
            volume=lot_size,
            stop_loss=signal.stop_loss,
            take_profit=signal.take_profit,
            price=signal.entry_price, # Pass entry price for pending orders
            comment=f"IEP Bot - Conf: {signal.score}/10"
        )

        if result and result.get('success'):
            # Determine status based on order type
            new_status = "PENDING" if "LIMIT" in mt5_order_type or "STOP" in mt5_order_type else "ACTIVE"
            
            # Update Signal status in DB
            db = SessionLocal()
            try:
                # Find the CREATED signal to update
                # We match by symbol and recent creation time (last 5 mins)
                db_signal = db.query(Signal).filter(
                    Signal.symbol == signal.symbol,
                    Signal.status == "CREATED",
                    Signal.created_at >= datetime.utcnow() - timedelta(minutes=5)
                ).order_by(Signal.created_at.desc()).first()
                
                if db_signal:
                    db_signal.status = new_status
                    db_signal.was_executed = True
                    db_signal.trade_id = result['ticket'] # Store ticket temporarily or link to Trade ID later
                    db.commit()
            except Exception as e:
                logger.error(f"Failed to update signal status: {e}")
            finally:
                db.close()

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

            # Send Discord Alert
            await self.discord.send_trade_alert({
                'symbol': trade.symbol,
                'type': trade.trade_type,
                'volume': trade.volume,
                'entry': trade.entry_price,
                'ticket': trade.ticket
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
        """Check if current day is a weekday (Monday-Friday) and within trading ours (00:00 - 12:00) LOCAL TIME (UTC-4)."""
        # Align with User's Local Time (UTC-4)
        utc_now = datetime.utcnow()
        local_now = utc_now - timedelta(hours=4)
        
        # Log for verification
        # logger.info(f"🕒 Time Check: UTC={utc_now.strftime('%H:%M')} | Local(UTC-4)={local_now.strftime('%H:%M')}")
        
        # Monday=0, Tuesday=1, ..., Friday=4, Saturday=5, Sunday=6
        is_weekday = local_now.weekday() < 5  # 0-4 are weekdays
        
        # Check time: 00:00 (12 AM) to 12:00 (12 PM)
        is_within_hours = 0 <= local_now.hour < 12
        
        if is_within_hours and is_weekday:
             return True
             
        # Fallback Log
        if not is_within_hours:
             # Only log warning if hours are completely wrong (e.g. trading attempted)
             # logger.warning(f"⛔ Outside Trading Hours: {local_now.strftime('%H:%M')} (Limit 00-12)")
             pass
             
        return False


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
        except Exception as e:
            logger.error(f"Error checking daily risk: {e}")
            return False
        finally:
            db.close()

    def _check_total_drawdown(self) -> bool:
        """
        Check if Total Drawdown Limit is reached.
        Uses Equity vs Balance (Open Drawdown) check.
        Values from settings.MAX_DRAWDOWN_PERCENT (default 7.0).
        """
        account_info = self.mt5_connector.get_account_info()
        if not account_info:
            return True # Fail safe

        balance = account_info['balance']
        equity = account_info['equity']
        
        if balance <= 0:
            return True

        # Calculate current open drawdown percentage
        # (Balance - Equity) / Balance * 100
        # If Equity > Balance, DD is 0
        current_dd_percent = max(0.0, (balance - equity) / balance * 100)
        
        limit = getattr(settings, "MAX_DRAWDOWN_PERCENT", 7.0)
        
        if current_dd_percent >= limit:
            logger.warning(f"Total Drawdown {current_dd_percent:.2f}% >= Limit {limit}%")
            return False
            
        return True

    def _check_cooldown(self, symbol: str) -> bool:
        """
        Check if cooldown period has passed since last closed trade
        Returns True if safe to trade, False if in cooldown
        """
        db = SessionLocal()
        try:
            # Get last closed trade for this symbol and user
            last_trade = db.query(Trade).filter(
                Trade.user_id == self.config.user_id,
                Trade.symbol == symbol,
                Trade.status == "CLOSED"
            ).order_by(Trade.closed_at.desc()).first()

            if not last_trade or not last_trade.closed_at:
                return True

            # Calculate time difference
            now = datetime.utcnow()
            time_since_close = now - last_trade.closed_at
            cooldown_delta = timedelta(minutes=self.config.cooldown_minutes)

            if time_since_close < cooldown_delta:
                remaining = cooldown_delta - time_since_close
                minutes = int(remaining.total_seconds() // 60)
                seconds = int(remaining.total_seconds() % 60)
                
                logger.info(f"Cooldown active for {symbol}: Wait {minutes}m {seconds}s")
                return False

            return True
        except Exception as e:
            logger.error(f"Error checking cooldown: {e}")
            return True
        finally:
            db.close()

    async def _get_consecutive_losses(self) -> int:
        """
        Get count of consecutive losing trades
        Used by AdaptiveRiskManager to reduce risk after losing streaks
        """
        db = SessionLocal()
        try:
            # Get recent closed trades ordered by close time descending
            recent_trades = db.query(Trade).filter(
                Trade.user_id == self.config.user_id,
                Trade.status == "CLOSED"
            ).order_by(Trade.closed_at.desc()).limit(10).all()

            if not recent_trades:
                return 0

            consecutive_losses = 0
            for trade in recent_trades:
                if trade.profit_loss < 0:  # Loss
                    consecutive_losses += 1
                else:  # Win or breakeven
                    break  # Stop counting at first win

            return consecutive_losses

        except Exception as e:
            logger.exception(f"Error getting consecutive losses: {e}")
            return 0  # Safe default
        finally:
            db.close()

    async def _calculate_kelly_from_history(self) -> float:
        """
        Calculate Kelly optimal fraction from recent trade history.
        
        Uses the formula: f* = (bp - q) / b
        where:
            p = win rate
            q = 1 - p = loss rate  
            b = avg_win / avg_loss (profit factor approximation)
        
        Returns:
            Kelly fraction (0.0 - 1.0), or None if insufficient data
        """
        db = SessionLocal()
        try:
            # Get recent closed trades (minimum 20 for statistical significance)
            min_trades = 20
            recent_trades = db.query(Trade).filter(
                Trade.user_id == self.config.user_id,
                Trade.status == "CLOSED"
            ).order_by(Trade.closed_at.desc()).limit(100).all()

            if len(recent_trades) < min_trades:
                logger.debug(f"Insufficient trades for Kelly ({len(recent_trades)}/{min_trades})")
                return None  # Not enough data, skip Kelly adjustment

            # Calculate win rate and average win/loss
            wins = [t for t in recent_trades if t.profit_loss > 0]
            losses = [t for t in recent_trades if t.profit_loss < 0]

            if len(wins) == 0 or len(losses) == 0:
                return None  # Need both wins and losses

            win_rate = len(wins) / len(recent_trades)  # p
            loss_rate = 1 - win_rate  # q
            
            avg_win = sum(t.profit_loss for t in wins) / len(wins)
            avg_loss = abs(sum(t.profit_loss for t in losses) / len(losses))
            
            if avg_loss == 0:
                return None

            b = avg_win / avg_loss  # Profit factor approximation
            
            # Kelly formula: f* = (bp - q) / b
            kelly_fraction = (b * win_rate - loss_rate) / b
            
            # Cap at reasonable bounds (0 to 0.25 for safety)
            kelly_fraction = max(0.0, min(kelly_fraction, 0.25))
            
            logger.info(
                f"📊 Kelly Analysis: WR={win_rate*100:.1f}%, AvgW=${avg_win:.0f}, "
                f"AvgL=${avg_loss:.0f}, b={b:.2f}, f*={kelly_fraction:.4f}"
            )
            
            return kelly_fraction if kelly_fraction > 0 else None

        except Exception as e:
            logger.exception(f"Error calculating Kelly: {e}")
            return None
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
