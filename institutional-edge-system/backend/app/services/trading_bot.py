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
from app.models.database import BotConfig, Trade, Signal
from app.api.database import SessionLocal


class TradingBot:
    """
    Automated trading bot that runs continuously
    """

    def __init__(self, bot_config_id: int, mt5_connector: MT5Connector):
        """
        Initialize trading bot

        Args:
            bot_config_id: Database ID of bot configuration
            mt5_connector: MT5 connector instance
        """
        self.bot_config_id = bot_config_id
        self.mt5_connector = mt5_connector
        self.is_running = False
        self.config: Optional[BotConfig] = None
        self.trading_engine: Optional[TradingEngine] = None
        self.last_analysis_time: Optional[datetime] = None
        self.open_positions_count = 0

        logger.info("Trading bot initialized for config ID: {}", bot_config_id)

    async def start(self):
        """Start the trading bot"""
        self.is_running = True
        logger.info("Starting trading bot {}", self.bot_config_id)

        # Load configuration
        self._load_config()

        # Initialize trading engine
        self._init_trading_engine()

        # Start main loop
        await self._run_loop()

    async def stop(self):
        """Stop the trading bot"""
        self.is_running = False
        logger.info("Stopping trading bot {}", self.bot_config_id)

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
            logger.warning("MT5 not connected, skipping analysis")
            return

        # Get market data
        df = self.mt5_connector.get_ohlcv_data(
            self.config.symbol,
            self.config.timeframe,
            bars=500
        )

        if df is None or len(df) == 0:
            logger.warning("No market data available for {}", self.config.symbol)
            return

        # Run analysis
        analysis = self.trading_engine.analyze(df)

        if 'error' in analysis:
            logger.error("Analysis error: {}", analysis['error'])
            return

        # Log analysis results
        logger.info("Analysis complete - Bull: {}/10, Bear: {}/10, Signals: {}",
                   analysis['bull_confluence_score'],
                   analysis['bear_confluence_score'],
                   len(analysis['signals']))

        # Save signals to database
        self._save_signals(analysis['signals'])

        # Execute trades if conditions are met
        for signal in analysis['signals']:
            await self._execute_signal(signal)

        # Update last analysis time in DB
        self._update_last_analysis_time()

    def _save_signals(self, signals: list):
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
                    trend=self.trading_engine.trend_bullish and "BULLISH" or "BEARISH",
                    poc_level=self.trading_engine.poc_level,
                    was_executed=False
                )
                db.add(signal)

            db.commit()
            logger.info("Saved {} signals to database", len(signals))
        except Exception as e:
            logger.exception("Error saving signals: {}", e)
            db.rollback()
        finally:
            db.close()

    async def _execute_signal(self, signal):
        """Execute a trading signal"""
        # Check if we've reached max trades
        if self.open_positions_count >= self.config.max_trades:
            logger.info("Max trades ({}) reached, skipping signal", self.config.max_trades)
            return

        # Get account info for position sizing
        account_info = self.mt5_connector.get_account_info()
        if not account_info:
            logger.error("Failed to get account info")
            return

        # Calculate position size
        stop_loss_pips = abs(signal.entry_price - signal.stop_loss) / 0.0001
        lot_size = self.mt5_connector.calculate_lot_size(
            symbol=signal.symbol,
            risk_percent=self.config.risk_percent,
            stop_loss_pips=stop_loss_pips,
            account_balance=account_info['balance']
        )

        logger.info("Opening {} position: {} lots @ {} (SL: {}, TP: {})",
                   signal.signal_type,
                   lot_size,
                   signal.entry_price,
                   signal.stop_loss,
                   signal.take_profit_1)

        # Open position
        result = self.mt5_connector.open_position(
            symbol=signal.symbol,
            order_type=signal.signal_type,
            volume=lot_size,
            stop_loss=signal.stop_loss,
            take_profit=signal.take_profit_1,
            comment=f"IEP Bot - Conf: {signal.confluence_score}/10"
        )

        if result and result.get('success'):
            # Save trade to database
            self._save_trade(signal, result, lot_size)
            self.open_positions_count += 1
            logger.info("✅ Trade opened successfully - Ticket: {}", result['ticket'])
        else:
            logger.error("❌ Failed to open trade")

    def _save_trade(self, signal, result: Dict, lot_size: float):
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
            logger.info("Trade saved to database - ID: {}", trade.id)
        except Exception as e:
            logger.exception("Error saving trade: {}", e)
            db.rollback()
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


class BotManager:
    """
    Manages multiple trading bots
    """

    def __init__(self, mt5_connector: MT5Connector):
        self.mt5_connector = mt5_connector
        self.bots: Dict[int, TradingBot] = {}
        self.tasks: Dict[int, asyncio.Task] = {}

    async def start_bot(self, bot_config_id: int):
        """Start a trading bot"""
        if bot_config_id in self.bots:
            logger.warning("Bot {} already running", bot_config_id)
            return

        bot = TradingBot(bot_config_id, self.mt5_connector)
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
