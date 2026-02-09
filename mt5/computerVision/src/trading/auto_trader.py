"""
Auto-Trader - Main trading loop that executes ML-based trades
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
        
        self.logger.info("Auto-Trader initialized")
    
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
        
        # Calculate position size based on CAPITAL BASE (Allocated amount)
        # Risk manager usually takes total balance, so we scale it?
        # A simple approach: 
        # position_size = (capital_base * risk_per_trade) / stop_loss_dist
        # For now, let's use the risk manager but pretend capital_base is the balance 
        # IF we want to restrict risk to that allocation.
        # BETTER: risk_manager.calculate_position_size uses config['default_lot_size'] or % risk.
        # We should probably scale the result by (capital_base / account_balance)
        
        base_lot_size = self.risk_manager.calculate_position_size(symbol, account_balance)
        
        # Adjust for allocation weight
        allocation_ratio = capital_base / account_balance if account_balance > 0 else 0
        lot_size = max(0.01, round(base_lot_size * allocation_ratio, 2))
        
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
        
        # Calculate SL/TP
        action = "BUY" if direction == "UP ▲" or direction == "BUY" else "SELL"
        sl, tp = self.risk_manager.calculate_sl_tp(symbol, entry_price, action)
        
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

    def check_signals(self):
        """Check for new ML signals and execute trades."""
        # Check global enable switch
        if self.db.get_config('auto_trading_enabled') != 'true':
            return
            
        account_balance = self.get_account_balance()
        if account_balance == 0:
            self.logger.warning("Could not get account balance")
            return

        # Check for Active Portfolio
        active_portfolio_id = self.db.get_config('active_portfolio_id')
        
        if active_portfolio_id:
            # First, generate fresh predictions for this portfolio
            try:
                self.prediction_service.generate_predictions_for_portfolio(int(active_portfolio_id))
            except Exception as e:
                self.logger.error(f"Error generating predictions: {e}")
            
            # Then execute trades based on predictions
            self._trade_portfolio(int(active_portfolio_id), account_balance)
        else:
            self._trade_legacy_config(account_balance)

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
            pred_time = datetime.fromisoformat(prediction['timestamp'])
            # Check if naive (no timezone) and make sure we compare correctly
            # Assuming DB stores UTC or consistent local time
            age_seconds = (datetime.now() - pred_time).total_seconds()
            return age_seconds < max_age_seconds
        except Exception:
            return False
    
    def run(self):
        """Main trading loop."""
        self.running = True
        self.logger.info("Auto-Trader started")
        self.db.log('INFO', 'TRADER', 'Auto-Trader started')
        
        check_interval = self.config['auto_trader']['check_interval_seconds']
        
        try:
            while self.running:
                self.check_signals()
                time.sleep(check_interval)
        except KeyboardInterrupt:
            self.logger.info("Auto-Trader stopped by user")
        except Exception as e:
            self.logger.error(f"Auto-Trader error: {e}")
            self.db.log('ERROR', 'TRADER', f'Auto-Trader error: {e}')
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
