"""
Auto-Trader - Main trading loop that executes ML-based trades

NEW FLOW with Signal Confirmation System:
1. Generate predictions
2. Register signals for validation
3. Validate pending signals (MTF, momentum, volume, trend)
4. Execute only confirmed signals (with cooldown checks)
"""

import logging
import time
import yaml
import requests
from pathlib import Path
import sys
from datetime import datetime

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))
from src.database import DatabaseManager
from src.trading.risk_manager import RiskManager
from src.trading.prediction_service import PredictionService
from src.trading.killzone_manager import KillzoneManager
from src.trading.exit_manager import ExitManager
from src.trading.signal_validator import SignalValidator
from src.trading.cooldown_manager import CooldownManager
from src.trading.signal_confirmation_manager import SignalConfirmationManager

class AutoTrader:
    """Automated trading engine based on ML predictions."""
    
    def __init__(self, config_path: str = "src/trading/config.yaml"):
        """Initialize auto-trader."""
        # Load config
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('logs/auto_trader.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Initialize components
        self.db = DatabaseManager()
        self.risk_manager = RiskManager(self.config, self.db)
        self.prediction_service = PredictionService(self.db)
        self.bridge_url = self.config['bridge']['url']
        self.running = False
        
        # Initialize killzone manager
        self.killzone_manager = KillzoneManager(self.config)
        
        # Initialize exit manager
        self.exit_manager = ExitManager(self.config, self.bridge_url)

        # Pass killzone manager to risk manager
        self.risk_manager.killzone_manager = self.killzone_manager

        # Initialize Signal Confirmation System
        self.signal_validator = SignalValidator(self.db, self.config, self.bridge_url)
        self.cooldown_manager = CooldownManager(self.db, self.config)
        self.confirmation_manager = SignalConfirmationManager(
            self.db, self.config, self.signal_validator, self.cooldown_manager
        )

        # Prediction regeneration tracking
        self.last_prediction_time = {}  # Track last prediction time per symbol
        self.prediction_interval = self.config.get('prediction', {}).get('regeneration_interval_seconds', 300)

        # Check if confirmation system is enabled
        confirmation_enabled = self.config.get('signal_confirmation', {}).get('enabled', True)

        self.logger.info("🚀 Auto-Trader initialized with Signal Confirmation System")
        self.logger.info(f"  ├─ Killzone Management: {'✓' if self.killzone_manager else '✗'}")
        self.logger.info(f"  ├─ Exit Strategies: {'✓' if self.exit_manager else '✗'}")
        self.logger.info(f"  ├─ Signal Confirmation: {'✓' if confirmation_enabled else '✗ (disabled)'}")
        self.logger.info(f"  ├─ Cooldown System: {'✓' if self.cooldown_manager.enabled else '✗ (disabled)'}")
        self.logger.info(f"  └─ Prediction interval: {self.prediction_interval}s")
    
    def get_account_balance(self) -> float:
        """Get current account balance from MT5."""
        try:
            response = requests.get(f"{self.bridge_url}/status")
            if response.status_code == 200:
                data = response.json()
                if data.get('account_info'):
                    return data['account_info']['balance']
        except Exception as e:
            self.logger.error(f"Error getting account balance: {e}")
        return 0.0
    
    def execute_trade(self, prediction: dict, capital_base: float):
        """
        Execute a trade based on ML prediction.
        
        Args:
            prediction: Prediction dictionary from database
            capital_base: Capital base to use for position sizing (Account Balance or Allocated Capital)
        """
        symbol = prediction['symbol']
        direction = prediction['prediction_direction']
        confidence = prediction['confidence']
        model_name = prediction.get('model_name', 'Unknown')
        
        self.logger.info(f"Processing signal: {direction} {symbol} (confidence: {confidence:.2%})")
        
        # Risk check
        # We pass full account balance for risk checks (e.g. max daily loss), 
        # but use capital_base for sizing if it's different.
        account_balance = self.get_account_balance()
        
        can_trade, reason = self.risk_manager.can_open_position(symbol, confidence, account_balance)
        if not can_trade:
            self.logger.warning(f"Trade rejected: {reason}")
            self.db.log('WARNING', 'TRADER', f'Trade rejected: {reason}', 
                       {'symbol': symbol, 'direction': direction, 'confidence': confidence})
            return
        
        # Get current price for SL/TP calculation
        try:
            response = requests.get(f"{self.bridge_url}/status")
            if response.status_code != 200:
                self.logger.error("Failed to get market price")
                return
        except Exception as e:
            self.logger.error(f"Error connecting to bridge: {e}")
            return
        
        # Estimate entry price (in production, get from tick data)
        # We fetch real-time price from bridge to ensure accurate SL/TP calculation
        entry_price = 0.0
        try:
            response = requests.get(f"{self.bridge_url}/symbols/{symbol}/info", timeout=5)
            if response.status_code == 200:
                info = response.json()
                # Use ASK for BUY, BID for SELL
                if direction == "UP ▲" or direction == "BUY":
                    entry_price = info.get('ask', 0.0)
                else:
                    entry_price = info.get('bid', 0.0)
                
                if entry_price <= 0:
                     self.logger.warning(f"Bridge returned invalid price {entry_price} for {symbol}, using fallback")
                     entry_price = 1.0 # Should ideally fail here, but keeping fallback for safety
            else:
                 self.logger.error(f"Failed to get symbol info for {symbol}: {response.text}")
                 entry_price = 1.0
        except Exception as e:
            self.logger.error(f"Error fetching symbol info: {e}")
            entry_price = 1.0
            
        self.logger.info(f"Using entry price: {entry_price} for {symbol} {direction}")
        
        # Get timeframe from database config (set in dashboard)
        timeframe = self.db.get_config('trading_timeframe', 'H1')
        
        # Calculate SL/TP FIRST (needed for risk-based position sizing)
        action = "BUY" if direction == "UP ▲" or direction == "BUY" else "SELL"
        sl, tp = self.risk_manager.calculate_sl_tp(symbol, entry_price, action, timeframe=timeframe)
        
        # NOW calculate position size based on SL distance (for risk-based method)
        # Pass entry_price and stop_loss for risk-based calculation
        base_lot_size = self.risk_manager.calculate_position_size(
            symbol=symbol,
            account_balance=account_balance,
            entry_price=entry_price,
            stop_loss=sl
        )
        
        # Adjust for allocation weight
        allocation_ratio = capital_base / account_balance if account_balance > 0 else 0
        lot_size = max(0.01, round(base_lot_size * allocation_ratio, 2))
        
        # Execute trade via bridge
        try:
            trade_request = {
                "symbol": symbol,
                "action": action,
                "volume": lot_size,
                "stop_loss": sl,
                "take_profit": tp,
                "comment": f"ML {confidence:.0%}"[:31]  # MT5 limit: 31 chars
            }
            
            response = requests.post(f"{self.bridge_url}/trade/open", json=trade_request)
            
            if response.status_code == 200:
                result = response.json()
                self.logger.info(f"Trade executed: {result}")
                self.db.log('INFO', 'TRADER', f'Trade executed: {action} {lot_size} {symbol}',
                           {'ticket': result.get('ticket'), 'price': result.get('price'), 'model': model_name})
            else:
                error = response.json().get('error', 'Unknown error')
                self.logger.error(f"Trade execution failed: {error}")
                self.db.log('ERROR', 'TRADER', f'Trade execution failed: {error}',
                           {'symbol': symbol, 'action': action})
        
        except Exception as e:
            self.logger.error(f"Error executing trade: {e}")
            self.db.log('ERROR', 'TRADER', f'Error executing trade: {e}')

    def ensure_fresh_predictions(self):
        """
        Ensure fresh predictions are available for all active symbols.
        Regenerates predictions if they're older than prediction_interval.
        """
        current_time = datetime.now()
        
        # Get active symbols based on portfolio or config
        active_portfolio_id = self.db.get_config('active_portfolio_id')
        
        if active_portfolio_id:
            # Portfolio mode: get allocated symbols
            allocations = self.db.get_allocations(int(active_portfolio_id))
            symbols_to_update = [(a['symbol'], a['model_id']) for a in allocations if a['weight'] > 0]
        else:
            # Legacy mode: get symbols from config
            symbols = self.config.get('auto_trader', {}).get('symbols', [])
            symbols_to_update = [(symbol, None) for symbol in symbols]
        
        # Check each symbol and regenerate if needed
        for symbol, model_id in symbols_to_update:
            last_time = self.last_prediction_time.get(symbol)
            
            # Regenerate if: never generated OR interval elapsed
            if last_time is None or (current_time - last_time).total_seconds() > self.prediction_interval:
                try:
                    if active_portfolio_id:
                        # Generate for specific portfolio
                        self.prediction_service.generate_predictions_for_portfolio(int(active_portfolio_id))
                        self.logger.info(f"🔄 Regenerated predictions for portfolio {active_portfolio_id}")
                    else:
                        # For legacy mode, we'd need to call prediction service differently
                        # For now, log that we need a prediction
                        self.logger.warning(f"⚠️ Legacy mode: prediction regeneration not fully implemented for {symbol}")
                    
                    # Update timestamp for all symbols in this batch
                    for sym, _ in symbols_to_update:
                        self.last_prediction_time[sym] = current_time
                    
                    break  # Only regenerate once per check cycle
                    
                except Exception as e:
                    self.logger.error(f"❌ Failed to regenerate predictions: {e}")
    
    def check_signals(self):
        """
        NEW 3-PHASE SIGNAL FLOW:
        1. Generate predictions & register new signals for validation
        2. Process and validate pending signals
        3. Execute only confirmed signals
        """
        # Check global enable switch
        if self.db.get_config('auto_trading_enabled') != 'true':
            return

        account_balance = self.get_account_balance()
        if account_balance == 0:
            self.logger.warning("Could not get account balance")
            return

        # PHASE 1: Generate predictions & register new signals
        self._register_new_signals(account_balance)

        # PHASE 2: Process and validate pending signals
        self.confirmation_manager.process_pending_signals()

        # PHASE 3: Execute confirmed signals
        self._execute_confirmed_signals(account_balance)

    def _register_new_signals(self, account_balance: float):
        """
        PHASE 1: Generate predictions and register them for validation.
        This replaces immediate trade execution with signal registration.
        """
        # Check for Active Portfolio
        active_portfolio_id = self.db.get_config('active_portfolio_id')

        if active_portfolio_id:
            self.logger.info(f"📁 Portfolio mode: Active portfolio ID = {active_portfolio_id}")

            # Portfolio mode: generate predictions for portfolio
            try:
                self.prediction_service.generate_predictions_for_portfolio(int(active_portfolio_id))
            except Exception as e:
                self.logger.error(f"Error generating predictions: {e}")
                return

            # Register signals from portfolio allocations
            allocations = self.db.get_allocations(int(active_portfolio_id))
            self.logger.info(f"📊 Found {len(allocations)} allocation(s) in portfolio")

            for alloc in allocations:
                if alloc['weight'] <= 0:
                    self.logger.debug(f"Skipping {alloc['symbol']} - weight is 0")
                    continue

                symbol = alloc['symbol']
                model_id = alloc['model_id']
                self.logger.info(f"🔍 Processing {symbol} (model_id={model_id}, weight={alloc['weight']})")

                # Get latest prediction
                prediction = self.db.get_latest_prediction(symbol, model_id=model_id)

                if not prediction:
                    self.logger.warning(f"⚠️  {symbol}: No prediction found for model_id={model_id}")
                    continue

                if not self._is_prediction_fresh(prediction):
                    self.logger.info(f"⏰ {symbol}: Prediction is stale")
                    continue

                self.logger.info(f"✅ {symbol}: Fresh prediction found - {prediction['prediction_direction']} ({prediction['confidence']:.1%})")

                if prediction and self._is_prediction_fresh(prediction):
                    # Check killzone before registering signal
                    is_allowed, reason = self.killzone_manager.is_trading_allowed(symbol=symbol)

                    if not is_allowed:
                        self.logger.info(f"⏸️  {symbol}: Outside killzone - {reason}")
                        self.db.log('INFO', 'AUTO_TRADER', f'{symbol}: Signal skipped - {reason}')
                        continue

                    # Check if signal already registered
                    if not self._is_signal_already_registered(prediction['id']):
                        # Get trading timeframe from config
                        trading_timeframe = self.db.get_config('trading_timeframe', 'H1')

                        # Register signal for validation
                        signal_id = self.confirmation_manager.register_new_signal(
                            prediction, trading_timeframe
                        )

                        if signal_id:
                            self.logger.info(f"📝 Registered signal #{signal_id} for {symbol} {prediction['prediction_direction']}")
                            self.db.log('INFO', 'AUTO_TRADER', f'Signal registered: {symbol} {prediction["prediction_direction"]} (confidence: {prediction["confidence"]:.1%})')

        else:
            # Legacy mode: generate predictions from config symbols
            self.logger.warning("⚠️ Legacy mode active - consider creating a portfolio for better management")
            # TODO: Implement legacy mode signal registration if needed

    def _is_signal_already_registered(self, prediction_id: int) -> bool:
        """Check if prediction already has a signal confirmation entry."""
        try:
            query = """
                SELECT COUNT(*) as count FROM signal_confirmations
                WHERE prediction_id = %s
                AND status IN ('PENDING', 'CONFIRMED')
            """

            with self.db.get_connection() as conn:
                row = conn.execute(query, (prediction_id,)).fetchone()
                return row['count'] > 0 if row else False

        except Exception as e:
            self.logger.error(f"Error checking signal registration: {e}")
            return False

    def _execute_confirmed_signals(self, account_balance: float):
        """
        PHASE 3: Execute trades for signals that passed validation.
        This replaces immediate execution with confirmation-gated execution.
        """
        # Get confirmed signals ready for execution
        confirmed_signals = self.confirmation_manager.get_confirmed_signals()

        if not confirmed_signals:
            return

        self.logger.info(f"🎯 Processing {len(confirmed_signals)} confirmed signal(s)")

        for signal in confirmed_signals:
            symbol = signal['symbol']
            direction = signal['prediction_direction']
            signal_id = signal['id']
            prediction_id = signal['prediction_id']

            # Final gate: check cooldown and other conditions
            can_execute, reason = self.confirmation_manager.can_execute_signal(signal)

            if not can_execute:
                self.logger.warning(f"⛔ Cannot execute signal #{signal_id} for {symbol}: {reason}")
                continue

            # Get full prediction details
            prediction = self.db.get_latest_prediction(symbol)

            if not prediction:
                self.logger.error(f"❌ Prediction not found for signal #{signal_id}")
                continue

            # Get portfolio allocation (if using portfolio mode)
            active_portfolio_id = self.db.get_config('active_portfolio_id')

            if active_portfolio_id:
                allocations = self.db.get_allocations(int(active_portfolio_id))
                alloc = next((a for a in allocations if a['symbol'] == symbol), None)

                if alloc:
                    allocated_capital = account_balance * alloc['weight']
                    prediction['model_name'] = alloc.get('strategy_name', 'Portfolio Strategy')
                else:
                    allocated_capital = account_balance
            else:
                allocated_capital = account_balance

            # Execute the trade
            self.logger.info(f"🚀 Executing confirmed signal: {direction} {symbol} (score: {signal['confirmation_score']:.1f})")

            try:
                self.execute_trade(prediction, allocated_capital)

                # Mark signal as executed
                self.confirmation_manager.mark_signal_executed(signal_id)

                # Set cooldown
                self.cooldown_manager.set_cooldown(symbol, reason='TRADE_EXECUTED', direction=direction)

            except Exception as e:
                self.logger.error(f"❌ Error executing signal #{signal_id}: {e}")

    def _trade_portfolio(self, portfolio_id: int, account_balance: float):
        """Execute trades based on portfolio allocations."""
        allocations = self.db.get_allocations(portfolio_id)
        
        if not allocations:
            return

        for alloc in allocations:
            symbol = alloc['symbol']
            model_id = alloc['model_id']
            weight = alloc['weight']
            
            if weight <= 0:
                continue

            # Get latest prediction specifically for this model
            prediction = self.db.get_latest_prediction(symbol, model_id=model_id)
            
            if prediction and self._is_prediction_fresh(prediction):
                # Calculate allocated capital
                allocated_capital = account_balance * weight
                
                # Enrich prediction with model name for logging
                prediction['model_name'] = alloc.get('strategy_name', 'Portfolio Strategy')
                
                self.execute_trade(prediction, allocated_capital)

    def _trade_legacy_config(self, account_balance: float):
        """Execute trades based on legacy config.yaml symbols (global fallback)."""
        # Check each symbol in config
        symbols = self.config.get('auto_trader', {}).get('symbols', [])
        for symbol in symbols:
            # Get ANY latest prediction for symbol (compatible with old logic)
            prediction = self.db.get_latest_prediction(symbol)
            
            if prediction and self._is_prediction_fresh(prediction):
                # Use full account balance as base (legacy behavior)
                self.execute_trade(prediction, account_balance)

    def _is_prediction_fresh(self, prediction: dict, max_age_seconds: int = 300) -> bool:
        """Check if prediction is fresh enough to trade."""
        try:
            # Handle both datetime objects (PostgreSQL) and strings (SQLite)
            pred_time = prediction['timestamp']
            if isinstance(pred_time, str):
                pred_time = datetime.fromisoformat(pred_time)
            elif not isinstance(pred_time, datetime):
                self.logger.warning(f"Unexpected timestamp type: {type(pred_time)}")
                return False

            # Check if naive (no timezone) and make sure we compare correctly
            # Assuming DB stores UTC or consistent local time
            age_seconds = (datetime.now() - pred_time).total_seconds()
            is_fresh = age_seconds < max_age_seconds

            if not is_fresh:
                self.logger.debug(f"Prediction age: {age_seconds:.1f}s (max: {max_age_seconds}s)")

            return is_fresh
        except Exception as e:
            self.logger.error(f"Error checking prediction freshness: {e}")
            return False
    
    def monitor_positions(self):
        """Monitor open positions and apply exit strategies."""
        try:
            # Get all open positions from bridge
            response = requests.get(f"{self.bridge_url}/positions", timeout=5)
            if response.status_code != 200:
                return
            
            positions = response.json()
            
            # Sync with local database (clear closed positions)
            open_tickets = [p['ticket'] for p in positions]
            self.db.sync_open_positions(open_tickets)
            
            for position in positions:
                symbol = position['symbol']
                ticket = position['ticket']
                
                # Get current price
                tick_response = requests.get(f"{self.bridge_url}/symbols/{symbol}/info", timeout=5)
                if tick_response.status_code != 200:
                    continue
                
                tick_data = tick_response.json()
                # MT5 positions use 'type': 0=BUY, 1=SELL (not 'direction')
                position_type = position.get('type', position.get('direction', 0))
                is_sell = position_type == 1 or position_type == 'SELL'
                current_price = tick_data['bid'] if is_sell else tick_data['ask']
                
                # Get ATR
                atr = self.exit_manager.get_atr(symbol)
                
                # Check exit conditions
                should_exit, reason, modification = self.exit_manager.check_exit_conditions(
                    position, current_price, atr
                )
                
                if should_exit:
                    self.logger.info(f"{symbol} exit trigger: {reason}")
                    
                    if modification is None:
                        # Full close
                        self._close_position(ticket, reason)
                        
                    elif modification['action'] == 'modify':
                        # Modify SL/TP
                        self._modify_position(ticket, modification['new_sl'], modification['new_tp'])
                        
                        # Update position metadata
                        if modification.get('breakeven_set'):
                            position['breakeven_set'] = True
                        
                    elif modification['action'] == 'partial_close':
                        # Partial close
                        self._close_partial(ticket, modification['close_percent'])
                        position['partial_taken'] = True
                        
        except Exception as e:
            self.logger.error(f"Error monitoring positions: {e}")
    
    def _modify_position(self, ticket: int, new_sl: float, new_tp: float):
        """Modify position SL/TP via bridge."""
        try:
            response = requests.post(
                f"{self.bridge_url}/trade/modify",
                json={'ticket': ticket, 'sl': new_sl, 'tp': new_tp},
                timeout=10
            )
            if response.status_code == 200:
                self.logger.info(f"Modified position {ticket}")
            else:
                self.logger.error(f"Failed to modify {ticket}: {response.text}")
        except Exception as e:
            self.logger.error(f"Error modifying position: {e}")
    
    def _close_partial(self, ticket: int, close_percent: float):
        """Close partial position via bridge."""
        try:
            response = requests.post(
                f"{self.bridge_url}/trade/close_partial",
                json={'ticket': ticket, 'close_percent': close_percent},
                timeout=10
            )
            if response.status_code == 200:
                self.logger.info(f"Closed {close_percent*100}% of {ticket}")
            else:
                self.logger.error(f"Failed to close partial {ticket}: {response.text}")
        except Exception as e:
            self.logger.error(f"Error closing partial: {e}")
    
    def _close_position(self, ticket: int, reason: str):
        """Close position completely via bridge."""
        try:
            response = requests.post(
                f"{self.bridge_url}/trade/close",
                json={'ticket': ticket},
                timeout=10
            )
            if response.status_code == 200:
                self.logger.info(f"Closed position {ticket}: {reason}")
            else:
                self.logger.error(f"Failed to close {ticket}: {response.text}")
        except Exception as e:
            self.logger.error(f"Error closing position: {e}")
    
    def run(self):
        """Main trading loop with Signal Confirmation System."""
        self.running = True
        self.logger.info("🚀 Auto-Trader started with Signal Confirmation System")
        self.db.log('INFO', 'TRADER', 'Auto-Trader started with Signal Confirmation')

        check_interval = self.config['auto_trader']['check_interval_seconds']

        try:
            while self.running:
                # STEP 1: Ensure fresh predictions are available
                self.ensure_fresh_predictions()

                # STEP 2: Process signals (3-phase flow: register → validate → execute)
                self.check_signals()

                # STEP 3: Monitor existing positions for exits
                self.monitor_positions()

                # STEP 4: Cleanup expired cooldowns and old signals
                self.cooldown_manager.cleanup_expired_cooldowns()
                self.confirmation_manager.cleanup_old_signals(days=7)

                time.sleep(check_interval)

        except KeyboardInterrupt:
            self.logger.info("Auto-Trader stopped by user")
        except Exception as e:
            self.logger.error(f"Auto-Trader error: {e}")
            self.db.log('ERROR', 'TRADER', f'Auto-Trader error: {e}')
            import traceback
            self.logger.error(traceback.format_exc())
        finally:
            self.running = False
            self.logger.info("Auto-Trader stopped")
            self.db.log('INFO', 'TRADER', 'Auto-Trader stopped')
    
    def stop(self):
        """Stop the trading loop."""
        self.running = False

if __name__ == '__main__':
    trader = AutoTrader()
    trader.run()
