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
    
    def execute_trade(self, prediction: dict, account_balance: float):
        """
        Execute a trade based on ML prediction.
        
        Args:
            prediction: Prediction dictionary from database
            account_balance: Current account balance
        """
        symbol = prediction['symbol']
        direction = prediction['prediction_direction']
        confidence = prediction['confidence']
        
        self.logger.info(f"Processing signal: {direction} {symbol} (confidence: {confidence:.2%})")
        
        # Risk check
        can_trade, reason = self.risk_manager.can_open_position(symbol, confidence, account_balance)
        if not can_trade:
            self.logger.warning(f"Trade rejected: {reason}")
            self.db.log('WARNING', 'TRADER', f'Trade rejected: {reason}', 
                       {'symbol': symbol, 'direction': direction, 'confidence': confidence})
            return
        
        # Calculate position size
        lot_size = self.risk_manager.calculate_position_size(symbol, account_balance)
        
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
        entry_price = 1.1000  # Placeholder - should get from bridge
        
        # Calculate SL/TP
        action = "BUY" if direction == "UP ▲" else "SELL"
        sl, tp = self.risk_manager.calculate_sl_tp(symbol, entry_price, action)
        
        # Execute trade via bridge
        try:
            trade_request = {
                "symbol": symbol,
                "action": action,
                "volume": lot_size,
                "stop_loss": sl,
                "take_profit": tp,
                "comment": f"ML Signal ({confidence:.1%})"
            }
            
            response = requests.post(f"{self.bridge_url}/trade/open", json=trade_request)
            
            if response.status_code == 200:
                result = response.json()
                self.logger.info(f"Trade executed: {result}")
                self.db.log('INFO', 'TRADER', f'Trade executed: {action} {lot_size} {symbol}',
                           {'ticket': result.get('ticket'), 'price': result.get('price')})
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
        if not self.config['auto_trader']['enabled']:
            return
        
        account_balance = self.get_account_balance()
        if account_balance == 0:
            self.logger.warning("Could not get account balance")
            return
        
        # Check each symbol
        for symbol in self.config['auto_trader']['symbols']:
            prediction = self.db.get_latest_prediction(symbol)
            
            if prediction:
                # Check if prediction is recent (within last 5 minutes)
                pred_time = datetime.fromisoformat(prediction['timestamp'])
                age_seconds = (datetime.now() - pred_time).total_seconds()
                
                if age_seconds < 300:  # 5 minutes
                    self.execute_trade(prediction, account_balance)
    
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
