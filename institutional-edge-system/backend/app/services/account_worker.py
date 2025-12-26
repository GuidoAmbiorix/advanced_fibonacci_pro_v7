import time
import multiprocessing
# import MetaTrader5 as mt5 # REMOVED for Docker
mt5 = None # Global placeholder
import rpyc
import os
from typing import Dict, Optional
from loguru import logger
from datetime import datetime

class AccountWorker(multiprocessing.Process):
    """
    Worker process to manage a SINGLE MT5 account in an isolated process.
    """
    def __init__(self, 
                 worker_id: str, 
                 account_config: Dict, 
                 command_queue: multiprocessing.Queue, 
                 response_queue: multiprocessing.Queue):
        
        super().__init__(name=f"Worker-{worker_id}")
        self.worker_id = worker_id
        self.account_config = account_config
        self.command_queue = command_queue
        self.response_queue = response_queue
        self.is_running = True
        self.connected = False
        
        # Determine Path
        self.terminal_path = account_config.get('terminal_path')
        # Logic for path is irrelevant in RPyC mode usually, but keeping it for compat

    def run(self):
        """Main loop for the worker process"""
        logger.info(f"[{self.name}] Starting worker process...")
        
        if not self._connect_mt5():
            self._send_response("FATAL_ERROR", {"error": "Failed to connect to MT5"})
            return

        self._send_response("STARTED", {"status": "Connected"})
        
        while self.is_running:
            try:
                # Non-blocking check for commands
                if not self.command_queue.empty():
                    command = self.command_queue.get()
                    self._process_command(command)
                
                # Keep connection alive / Check connection
                if mt5 and not mt5.terminal_info():
                    logger.warning(f"[{self.name}] Connection lost, attempting reconnect...")
                    self._connect_mt5()
                
                time.sleep(0.1) # efficient sleep

            except Exception as e:
                logger.error(f"[{self.name}] Error in loop: {e}")
                self._send_response("ERROR", {"error": str(e)})
                time.sleep(1)

        self._disconnect_mt5()
        logger.info(f"[{self.name}] Worker process stopped.")

    def _connect_mt5(self) -> bool:
        """Initialize connection to specific terminal via RPyC"""
        global mt5
        try:
            mt5_host = os.getenv("MT5_HOST", "mt5")
            mt5_port = int(os.getenv("MT5_PORT", 18812))
            
            logger.info(f"[{self.name}] Connecting to MT5 Service at {mt5_host}:{mt5_port}...")
            conn = rpyc.classic.connect(mt5_host, mt5_port)
            mt5 = conn.modules.MetaTrader5


            # Login
            login = int(self.account_config['login'])
            password = self.account_config['password']
            server = self.account_config['server']
            
            authorized = mt5.login(login=login, password=password, server=server)
            if authorized:
                logger.info(f"[{self.name}] Logged in to {login} on {server}")
                self.connected = True
                return True
            else:
                 logger.error(f"[{self.name}] Login failed: {mt5.last_error()}")
                 return False

        except Exception as e:
            logger.exception(f"[{self.name}] Connection Exception: {e}")
            return False

    def _disconnect_mt5(self):
        mt5.shutdown()
        self.connected = False

    def _process_command(self, cmd: Dict):
        """Handle incoming commands"""
        c_type = cmd.get('type')
        payload = cmd.get('payload', {})
        
        if c_type == 'STOP':
            self.is_running = False
            
        elif c_type == 'OPEN_TRADE':
            self._execute_trade(payload)
            
        elif c_type == 'CLOSE_TRADE':
            self._close_trade(payload)
            
        elif c_type == 'GET_INFO':
            self._get_account_info()

    def _execute_trade(self, signal: Dict):
        """Execute trade on this account"""
        if not self.connected:
            return

        symbol = signal.get('symbol')
        order_type_str = signal.get('type') # BUY/SELL
        
        # Check balance for Lot Size Calculation
        account_info = mt5.account_info()
        if not account_info:
            return
            
        balance = account_info.balance
        risk_percent = signal.get('risk_percent', 1.0)
        sl_dist_pips = signal.get('sl_pips', 0)
        
        # TODO: Implement robust Lot Calc logic here or helper
        # For MVP, let's use a safe default or simple calc
        volume = 0.01 
        
        # Map Order Type
        mt5_type = mt5.ORDER_TYPE_BUY if order_type_str == 'BUY' else mt5.ORDER_TYPE_SELL
        price = mt5.symbol_info_tick(symbol).ask if order_type_str == 'BUY' else mt5.symbol_info_tick(symbol).bid
        
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume,
            "type": mt5_type,
            "price": price,
            "sl": signal.get('sl'),
            "tp": signal.get('tp'),
            "comment": "MultiBot Worker",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            self._send_response("TRADE_OPENED", {"ticket": result.order, "symbol": symbol})
        else:
            self._send_response("TRADE_FAILED", {"error": result.comment})

    def _close_trade(self, payload):
        ticket = payload.get('ticket') 
        # Logic to close ticket...
        pass

    def _get_account_info(self):
        info = mt5.account_info()
        if info:
            data = {"balance": info.balance, "equity": info.equity}
            self._send_response("INFO_UPDATE", data)

    def _send_response(self, r_type: str, data: Dict):
        """Send data back to Master"""
        self.response_queue.put({
            "worker_id": self.worker_id,
            "type": r_type,
            "data": data,
            "timestamp": datetime.utcnow().isoformat()
        })
