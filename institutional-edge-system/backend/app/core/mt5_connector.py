"""
============================================================================
INSTITUTIONAL EDGE PRO - MT5 Integration Layer (Enhanced)
============================================================================
Handles all MetaTrader 5 connections and operations with improved execution
============================================================================
Supports:
- Local Windows MT5 via MetaTrader5 package
- Remote Docker MT5 via mt5linux (gmag11/metatrader5_vnc)
============================================================================
"""

import pandas as pd
from typing import Optional, List, Dict, Tuple
from datetime import datetime, timedelta
from loguru import logger
import time
import os
from app.core.config import settings

# Global RPyC configuration to prevent timeouts during MT5 initialization
try:
    import rpyc
    # Set default timeout to 600s (10m) to allow for slow MT5 startup
    if hasattr(rpyc.core.protocol, 'DEFAULT_CONFIG'):
        rpyc.core.protocol.DEFAULT_CONFIG['sync_request_timeout'] = 600
        rpyc.core.protocol.DEFAULT_CONFIG['allow_pickle'] = True
except ImportError:
    pass


# MT5 module - will be set based on connection type
mt5 = None

def get_local_mt5():
    """Try to import local MetaTrader5 package"""
    try:
        import MetaTrader5
        return MetaTrader5
    except ImportError:
        return None

def get_remote_mt5(host: str, port: int):
    """
    Create remote MetaTrader5 connection using RPyC directly.
    Simulates mt5linux behavior without the package dependency.
    """
    try:
        import rpyc
        # Connect to RPyC server (without config arg which fails on older versions)
        conn = rpyc.classic.connect(host, port)
        
        # Enhanced for Stability: Set timeout after connection
        if hasattr(conn, '_config'):
            conn._config['sync_request_timeout'] = 300  # 5 minutes
            conn._config['allow_pickle'] = True

        # Verify connection
        if conn.closed:
             logger.error("❌ RPyC connection immediately closed")
             return None

        # Return the remote MetaTrader5 module proxy
        return conn.modules.MetaTrader5
    except Exception as e:
        logger.error(f"❌ Failed to connect to remote MT5 via RPyC: {e}")
        return None


class MT5Connector:
    """
    MetaTrader 5 Connection and Data Management
    Enhanced with slippage control, retry logic, and partial closes.
    """

    def __init__(self, config: Dict):
        """
        Initialize MT5 Connector

        Args:
            config: Configuration dictionary with MT5 credentials
        """
        self.config = config
        self.login = config.get('mt5_login')
        self.password = config.get('mt5_password')
        self.server = config.get('mt5_server')
        self.path = config.get('mt5_path')
        self.connected = False
        
        # ============ ENHANCED EXECUTION SETTINGS ============
        self.max_slippage_pips = config.get('max_slippage_pips', 3.0)
        self.max_retries = config.get('max_order_retries', 3)
        self.retry_delay_ms = config.get('retry_delay_ms', 500)

        # Timeframe mapping (only if MT5 is available)
        if mt5 is not None:
            self.timeframe_map = {
                'M1': mt5.TIMEFRAME_M1,
                'M5': mt5.TIMEFRAME_M5,
                'M15': mt5.TIMEFRAME_M15,
                'M30': mt5.TIMEFRAME_M30,
                'H1': mt5.TIMEFRAME_H1,
                'H4': mt5.TIMEFRAME_H4,
                'D1': mt5.TIMEFRAME_D1,
                'W1': mt5.TIMEFRAME_W1,
                'MN1': mt5.TIMEFRAME_MN1,
            }
        else:
            self.timeframe_map = {
                'M1': 1, 'M5': 5, 'M15': 15, 'M30': 30,
                'H1': 60, 'H4': 240, 'D1': 1440, 'W1': 10080, 'MN1': 43200,
            }

    def _normalize_symbol(self, symbol: str) -> str:
        """Normalize symbol name by handling broker suffixes."""
        if not self.connected:
            return symbol
            
        if mt5.symbol_info(symbol) is not None:
            return symbol
            
        suffix = settings.MT5_SYMBOL_SUFFIX
        if suffix and not symbol.endswith(suffix):
            suffixed_symbol = f"{symbol}{suffix}"
            info = mt5.symbol_info(suffixed_symbol)
            if info is not None:
                logger.info(f"Symbol {symbol} resolved to {suffixed_symbol}")
                return suffixed_symbol
                
        logger.warning(f"Could not normalize symbol {symbol}. Suffix: {suffix}")
        return symbol

    def normalize_symbol(self, symbol: str, symbol_type: str = "forex") -> str:
        """Public method to normalize symbol name."""
        return self._normalize_symbol(symbol)

    def _normalize_price(self, symbol: str, price: float) -> float:
        """
        Normalize price to symbol's tick size and decimal digits.
        This prevents MT5 error 10013 (Invalid Request) due to price precision issues.
        """
        if not self.connected or price is None or price <= 0:
            return price
        
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                return price
            
            digits = symbol_info.digits
            tick_size = symbol_info.trade_tick_size
            
            # Align price to tick size, then round to correct decimal places
            if tick_size > 0:
                normalized = round(round(price / tick_size) * tick_size, digits)
            else:
                normalized = round(price, digits)
            
            return normalized
        except Exception as e:
            logger.warning(f"Price normalization failed for {symbol}: {e}")
            return price

    def _validate_stop_levels(
        self, 
        symbol: str, 
        order_type: str, 
        entry_price: float, 
        stop_loss: float, 
        take_profit: float
    ) -> tuple:
        """
        Validate and adjust SL/TP to meet broker's minimum stop level requirements.
        Returns adjusted (stop_loss, take_profit) tuple.
        """
        if not self.connected:
            return stop_loss, take_profit
        
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                return stop_loss, take_profit
            
            # Get minimum stop level in points
            stop_level = symbol_info.trade_stops_level
            point = symbol_info.point
            
            # Minimum distance = stop_level * point + safety buffer (2 points)
            min_distance = (stop_level + 2) * point
            
            is_buy = order_type.upper() in ["BUY", "BUY_LIMIT", "BUY_STOP"]
            
            # Validate Stop Loss
            if stop_loss and stop_loss > 0:
                sl_distance = abs(entry_price - stop_loss)
                if sl_distance < min_distance:
                    old_sl = stop_loss
                    if is_buy:
                        stop_loss = entry_price - min_distance
                    else:
                        stop_loss = entry_price + min_distance
                    stop_loss = self._normalize_price(symbol, stop_loss)
                    logger.warning(
                        f"⚠️ SL adjusted for {symbol}: {old_sl:.5f} → {stop_loss:.5f} "
                        f"(min distance: {min_distance:.5f})"
                    )
            
            # Validate Take Profit
            if take_profit and take_profit > 0:
                tp_distance = abs(entry_price - take_profit)
                if tp_distance < min_distance:
                    old_tp = take_profit
                    if is_buy:
                        take_profit = entry_price + min_distance
                    else:
                        take_profit = entry_price - min_distance
                    take_profit = self._normalize_price(symbol, take_profit)
                    logger.warning(
                        f"⚠️ TP adjusted for {symbol}: {old_tp:.5f} → {take_profit:.5f} "
                        f"(min distance: {min_distance:.5f})"
                    )
            
            return stop_loss, take_profit
            
        except Exception as e:
            logger.warning(f"Stop level validation failed for {symbol}: {e}")
            return stop_loss, take_profit

    def connect(self) -> bool:
        """Connect to local dedicated MetaTrader 5 via RPyC"""
        try:
            global mt5
            
            # Dedicated MT5 Connection
            mt5_host = os.getenv("MT5_HOST", "mt5")
            mt5_port = int(os.getenv("MT5_PORT", 8001))
            
            logger.info(f"🔌 Connecting to dedicated MT5 at {mt5_host}:{mt5_port}...")
            
            try:
                import rpyc
                # Establish connection
                conn = rpyc.classic.connect(mt5_host, mt5_port)
                
                # Store connection for later use (deliver dictionaries)
                self.rpyc_conn = conn
                
                # Force update instance config as a fallback
                if hasattr(conn, '_config'):
                     conn._config['sync_request_timeout'] = 600
                
                mt5 = conn.modules.MetaTrader5
                
                # Define remote helper functions to handle dict casting
                # This ensures MT5 receives a native dict, not an RPyC netref
                conn.execute("""
import MetaTrader5 as mt5_remote
def proxy_order_check(req):
    return mt5_remote.order_check(dict(req))
def proxy_order_send(req):
    return mt5_remote.order_send(dict(req))
""")
                self.proxy_order_check = conn.namespace['proxy_order_check']
                self.proxy_order_send = conn.namespace['proxy_order_send']

                # Re-initialize timeframe map with LOCALLY DEFINED constants 
                # to avoid blocking RPyC calls on property access during startup
                self.timeframe_map = {
                    'M1': 1, 'M5': 5, 'M15': 15,
                    'M30': 30, 'H1': 16385, 'H4': 16388,
                    'D1': 16408, 'W1': 32769, 'MN1': 49153,
                }
                logger.info("✅ RPyC connection established and proxies defined")
                
            except Exception as e:
                logger.error(f"❌ Failed to connect via RPyC: {e}")
                return False

            # Initialize MT5
            # This call may block for a while if MT5 is starting up
            if not mt5.initialize():
                err_code = mt5.last_error()
                logger.error(f"❌ MT5 initialize() failed: {err_code}")
                return False
            
            logger.info("✅ MT5 initialized successfully")
            
            # Login
            if self.login and self.password and self.server:
                logger.info(f"🔐 Logging into account {self.login} on server {self.server}...")
                authorized = mt5.login(
                    login=int(self.login),
                    password=self.password,
                    server=self.server
                )
                if not authorized:
                    err_code = mt5.last_error()
                    logger.error(f"❌ MT5 login failed for account {self.login}: {err_code}")
                    return False
                logger.info(f"✅ Successfully logged into {self.login}")
            else:
                logger.warning("⚠️ No MT5 credentials provided - using current terminal session")

            self.connected = True
            
            # Verify connection status
            try:
                account_info = mt5.account_info()
                if account_info:
                    logger.info(f"📊 Account {account_info.login} | Balance: ${account_info.balance:.2f}")
                else:
                    logger.warning("⚠️ Connected but Account Info unavailable")
            except:
                pass 
                
            return True

        except Exception as e:
            logger.error(f"CRITICAL ERROR in connect(): {e}")
            return False

    def disconnect(self):
        """Disconnect from MT5"""
        if self.connected:
            mt5.shutdown()
            self.connected = False
            logger.info("MT5 connection closed")

    def switch_account(self, login: int, password: str, server: str) -> bool:
        """
        Switch MT5 to a different account (for shared MT5 architecture).
        
        Args:
            login: MT5 account number
            password: Account password
            server: Broker server name
            
        Returns:
            bool: True if switch successful, False otherwise
        """
        if not self.connected:
            logger.error("MT5 not connected - cannot switch account")
            return False
        
        try:
            authorized = mt5.login(login=login, password=password, server=server)
            if not authorized:
                err_code = mt5.last_error()
                logger.error(f"❌ Failed to switch to account {login}: {err_code}")
                return False
            
            # Update internal state
            self.login = str(login)
            self.password = password
            self.server = server
            
            account_info = mt5.account_info()
            if account_info:
                logger.info(f"✅ Switched to account {login} | Balance: ${account_info.balance:.2f}")
            else:
                logger.warning(f"⚠️ Switched to account {login} but account_info unavailable")
            
            return True
            
        except Exception as e:
            logger.exception(f"Error switching to account {login}: {e}")
            return False

    def ensure_account(self) -> bool:
        """
        Ensure we're logged into the correct account before trading.
        This is critical for the shared MT5 architecture where multiple
        backends may be using the same MT5 terminal.
        
        Returns:
            bool: True if correct account is active, False otherwise
        """
        if not self.connected:
            logger.info("Not connected, attempting to connect...")
            return self.connect()
        
        if not self.login:
            logger.warning("No login configured for this instance")
            return True  # No specific account required
        
        try:
            account_info = mt5.account_info()
            if account_info and str(account_info.login) == str(self.login):
                return True  # Already on correct account
            
            # Need to switch accounts
            logger.info(f"Account mismatch: Current={account_info.login if account_info else 'None'}, Required={self.login}")
            return self.switch_account(int(self.login), self.password, self.server)
            
        except Exception as e:
            logger.exception(f"Error ensuring account: {e}")
            return False

    def get_ohlcv_data(self, symbol: str, timeframe: str, bars: int = 500) -> Optional[pd.DataFrame]:
        """Get OHLCV data from MT5"""
        if not self.connected:
            logger.error("Not connected to MT5")
            return None

        symbol = self._normalize_symbol(symbol)
        try:
            mt5_timeframe = self.timeframe_map.get(timeframe)
            if not mt5_timeframe:
                logger.error("Invalid timeframe: {}", timeframe)
                return None

            rates = mt5.copy_rates_from_pos(symbol, mt5_timeframe, 0, bars)
            if rates is None or len(rates) == 0:
                logger.error("Failed to get rates for {}, error: {}", symbol, mt5.last_error())
                return None

            df = pd.DataFrame(rates)
            df['time'] = pd.to_datetime(df['time'], unit='s')
            df = df.rename(columns={'tick_volume': 'volume'})
            logger.debug("Fetched {} bars for {} {}", len(df), symbol, timeframe)
            return df[['time', 'open', 'high', 'low', 'close', 'volume']]

        except Exception as e:
            logger.exception("Error fetching OHLCV data: {}", e)
            return None

    def get_current_price(self, symbol: str) -> Optional[Dict]:
        """Get current price for symbol"""
        if not self.connected:
            return None

        symbol = self._normalize_symbol(symbol)
        try:
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                if mt5.symbol_select(symbol, True):
                    tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                info = mt5.symbol_info(symbol)
                if info is None:
                    logger.error(f"Symbol {symbol} not found in MT5")
                else:
                    logger.error(f"Failed to get tick for {symbol} (Market might be closed)")
                return None

            return {
                'symbol': symbol,
                'bid': tick.bid,
                'ask': tick.ask,
                'last': tick.last,
                'time': datetime.fromtimestamp(tick.time),
                'spread': tick.ask - tick.bid
            }
        except Exception as e:
            logger.exception("Error getting current price: {}", e)
            return None

    def get_account_info(self) -> Optional[Dict]:
        """Get account information"""
        if not self.connected:
            return None
        try:
            account = mt5.account_info()
            if account is None:
                return None
            return {
                'login': account.login,
                'balance': account.balance,
                'equity': account.equity,
                'margin': account.margin,
                'margin_free': account.margin_free,
                'margin_level': account.margin_level,
                'profit': account.profit,
                'currency': account.currency,
                'leverage': account.leverage,
            }
        except Exception as e:
            logger.exception("Error getting account info: {}", e)
            return None

    def _get_filling_mode(self, symbol: str) -> int:
        """Determine the correct filling mode for the symbol"""
        if not self.connected:
            return mt5.ORDER_FILLING_IOC  # IOC is usually safest fallback
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                logger.warning(f"No symbol info for {symbol}, using IOC")
                return mt5.ORDER_FILLING_IOC
            
            filling = symbol_info.filling_mode
            logger.info(f"📊 Symbol {symbol} filling_mode flags: {filling} (binary: {bin(filling)})")
            
            # Try filling modes in order of typical broker compatibility
            # IOC (2) is usually most compatible, then RETURN (4), then FOK (1)
            if filling & 2:  # IOC
                logger.info(f"✅ Using ORDER_FILLING_IOC for {symbol}")
                return mt5.ORDER_FILLING_IOC
            if filling & 1:  # FOK
                logger.info(f"✅ Using ORDER_FILLING_FOK for {symbol}")
                return mt5.ORDER_FILLING_FOK
            
            # If zero or only RETURN, try IOC as default
            logger.warning(f"Filling mode {filling} unclear for {symbol}, trying IOC")
            return mt5.ORDER_FILLING_IOC
        except Exception as e:
            logger.error(f"Error determining filling mode: {e}")
            return mt5.ORDER_FILLING_IOC

    def _check_slippage(self, expected_price: float, actual_price: float, symbol: str) -> bool:
        """
        Check if slippage is within acceptable limits.
        
        Returns:
            True if slippage is acceptable, False otherwise
        """
        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            return True  # Can't check, allow
            
        point = symbol_info.point
        slippage_points = abs(actual_price - expected_price) / point
        slippage_pips = slippage_points / 10  # For 5-digit brokers
        
        if slippage_pips > self.max_slippage_pips:
            logger.warning(f"Excessive slippage: {slippage_pips:.1f} pips > {self.max_slippage_pips} max")
            return False
        return True

    def open_position(
        self,
        symbol: str,
        order_type: str,
        volume: float,
        stop_loss: Optional[float] = None,
        take_profit: Optional[float] = None,
        price: Optional[float] = None,
        comment: str = "Institutional Edge Pro",
        use_limit: bool = False
    ) -> Optional[Dict]:
        """
        Open a trading position with enhanced execution.
        
        Args:
            symbol: Trading symbol
            order_type: BUY, SELL, BUY_LIMIT, SELL_LIMIT, BUY_STOP, SELL_STOP
            volume: Lot size
            stop_loss: Stop loss price
            take_profit: Take profit price
            price: Entry price (required for pending, optional for market)
            comment: Order comment
            use_limit: If True, use limit order instead of market
        
        Returns:
            Result dict with success status and order details
        """
        if not self.connected:
            logger.error("Not connected to MT5")
            return None
        
        # CRITICAL: Ensure correct account before trading (shared MT5 architecture)
        if not self.ensure_account():
            logger.error("Failed to ensure correct account is active")
            return None

        # HARD VALIDATION: Check for valid account state (Balance > 0)
        # This catches "No money" errors caused by disconnected/unauthenticated terminals
        acc = mt5.account_info()
        if acc is None:
             logger.critical("❌ MT5 ACCOUNT INVALID: account_info() returned None (Not logged in?)")
             return {"success": False, "error": "MT5 Terminal not authenticated"}
        
        if acc.balance <= 0 or acc.equity <= 0:
             logger.critical(
                 f"❌ MT5 ACCOUNT UNFUNDED/INVALID: Login={acc.login}, "
                 f"Balance={acc.balance}, Equity={acc.equity}"
             )
             return {"success": False, "error": "MT5 account has zero balance/equity"}

        symbol = self._normalize_symbol(symbol)

        for attempt in range(self.max_retries):
            try:
                symbol_info = mt5.symbol_info(symbol)
                if symbol_info is None:
                    return None

                # Log symbol trading specs for debugging
                logger.info(
                    f"📋 Symbol {symbol} specs: "
                    f"volume_min={symbol_info.volume_min}, "
                    f"volume_max={symbol_info.volume_max}, "
                    f"volume_step={symbol_info.volume_step}, "
                    f"trade_mode={symbol_info.trade_mode}, "
                    f"trade_contract_size={symbol_info.trade_contract_size}"
                )

                if not symbol_info.visible:
                    if not mt5.symbol_select(symbol, True):
                        logger.error("Failed to select symbol {}", symbol)
                        return None

                tick = mt5.symbol_info_tick(symbol)
                if tick is None:
                    logger.error("Failed to get tick for {}", symbol)
                    return None
                
                # Validate tick prices
                if tick.ask <= 0 or tick.bid <= 0:
                    logger.error(f"Invalid tick prices for {symbol}: ask={tick.ask}, bid={tick.bid}. Market may be closed or symbol not found.")
                    return {"success": False, "error": f"Invalid tick prices for {symbol}. Market may be closed."}

                logger.info(f"📊 Tick for {symbol}: bid={tick.bid}, ask={tick.ask}")

                # Map order types
                order_type_map = {
                    "BUY": mt5.ORDER_TYPE_BUY,
                    "SELL": mt5.ORDER_TYPE_SELL,
                    "BUY_LIMIT": mt5.ORDER_TYPE_BUY_LIMIT,
                    "SELL_LIMIT": mt5.ORDER_TYPE_SELL_LIMIT,
                    "BUY_STOP": mt5.ORDER_TYPE_BUY_STOP,
                    "SELL_STOP": mt5.ORDER_TYPE_SELL_STOP
                }
                
                # Handle use_limit flag
                effective_order_type = order_type
                if use_limit and order_type == "BUY":
                    effective_order_type = "BUY_LIMIT"
                elif use_limit and order_type == "SELL":
                    effective_order_type = "SELL_LIMIT"
                
                order_type_mt5 = order_type_map.get(effective_order_type)
                if order_type_mt5 is None:
                    logger.error("Invalid order type: {}", order_type)
                    return None

                is_pending = "LIMIT" in effective_order_type or "STOP" in effective_order_type
                
                if is_pending:
                    if price is None:
                        # Use current price for limit orders
                        price = tick.ask if "BUY" in effective_order_type else tick.bid
                    execution_price = price
                    action = mt5.TRADE_ACTION_PENDING
                else:
                    execution_price = tick.ask if order_type == "BUY" else tick.bid
                    action = mt5.TRADE_ACTION_DEAL

                filling_mode = self._get_filling_mode(symbol)
                
                # Calculate deviation based on max_slippage_pips
                point = symbol_info.point
                deviation = int(self.max_slippage_pips * 10)  # Convert pips to points

                # ============ PRICE NORMALIZATION ============
                # Normalize execution price to symbol's tick size
                execution_price = self._normalize_price(symbol, execution_price)
                
                # Normalize and validate SL/TP
                if stop_loss:
                    stop_loss = self._normalize_price(symbol, stop_loss)
                if take_profit:
                    take_profit = self._normalize_price(symbol, take_profit)
                
                # Validate stop levels meet broker minimums
                stop_loss, take_profit = self._validate_stop_levels(
                    symbol, order_type, execution_price, stop_loss, take_profit
                )
                
                # ============ VOLUME NORMALIZATION ============
                # Round volume to broker's volume step
                volume = round(volume / symbol_info.volume_step) * symbol_info.volume_step
                volume = max(symbol_info.volume_min, min(volume, symbol_info.volume_max))

                # Use larger deviation for crypto and volatile instruments
                if 'BTC' in symbol or 'ETH' in symbol or 'XAU' in symbol:
                    deviation = 100  # Much larger deviation for volatile instruments

                # CRITICAL: Ensure all values are native Python types (for RPyC serialization)
                request = {
                    "action": int(action),
                    "symbol": str(symbol),
                    "volume": float(volume),
                    "type": int(order_type_mt5),
                    "price": float(execution_price),
                    "deviation": int(deviation),
                    "magic": int(234000),
                    "comment": str(comment),
                    "type_time": int(mt5.ORDER_TIME_GTC),
                    "type_filling": int(filling_mode),
                }

                if stop_loss:
                    request["sl"] = float(stop_loss)
                if take_profit:
                    request["tp"] = float(take_profit)

                # Log full request for debugging
                logger.info(f"📤 Sending order request: {request}")

                # USE REMOTE PROXY FUNCTIONS IF AVAILABLE
                # These wrappers strictly cast the input to dict() on the remote side
                if hasattr(self, 'proxy_order_check'):
                     check_result = self.proxy_order_check(request)
                else:
                     check_result = mt5.order_check(request)

                if check_result is None:
                    logger.error(f"❌ order_check returned None! last_error: {mt5.last_error()}")
                    return {"success": False, "error": "Order check failed (None)"}
                elif check_result.retcode != 0:
                    logger.error(
                        f"❌ Pre-Order Validation Failed: retcode={check_result.retcode}, "
                        f"comment='{check_result.comment}', "
                        f"margin_free={check_result.margin_free}"
                    )
                    return {
                        "success": False, 
                        "error": f"Order Validation Failed: {check_result.comment} ({check_result.retcode})"
                    }
                else:
                    logger.info(f"✅ order_check passed: margin_free={check_result.margin_free}")
                
                if hasattr(self, 'proxy_order_send'):
                    result = self.proxy_order_send(request)
                else:
                    result = mt5.order_send(request)

                if result is None:
                    logger.error("Order send failed, error: {}", mt5.last_error())
                    if attempt < self.max_retries - 1:
                        time.sleep(self.retry_delay_ms / 1000)
                        continue
                    return None

                if result.retcode != mt5.TRADE_RETCODE_DONE:
                    # Check for requote
                    if result.retcode == mt5.TRADE_RETCODE_REQUOTE:
                        logger.warning(f"Requote received, retry {attempt + 1}/{self.max_retries}")
                        time.sleep(self.retry_delay_ms / 1000)
                        continue
                    
                    # Detailed error logging for debugging
                    logger.error(
                        f"❌ Order Failed - Request Details:\n"
                        f"  Symbol: {symbol}\n"
                        f"  Type: {order_type} (MT5: {order_type_mt5})\n"
                        f"  Volume: {volume}\n"
                        f"  Price: {execution_price}\n"
                        f"  SL: {stop_loss}\n"
                        f"  TP: {take_profit}\n"
                        f"  Filling: {filling_mode}\n"
                        f"  Deviation: {deviation}\n"
                        f"  Result: {result.retcode} - {result.comment}"
                    )
                    return {
                        "success": False,
                        "error": f"MT5 Error: {result.comment} ({result.retcode})"
                    }

                # Check slippage on market orders
                if not is_pending:
                    if not self._check_slippage(execution_price, result.price, symbol):
                        logger.warning(f"Order filled with high slippage: expected {execution_price}, got {result.price}")
                        # Still return success but log the warning

                logger.info("Order opened successfully: {} {} {} lots @ {}",
                           order_type, symbol, volume, result.price)

                return {
                    "success": True,
                    "ticket": result.order,
                    "volume": result.volume,
                    "price": result.price,
                    "expected_price": execution_price,
                    "slippage_points": abs(result.price - execution_price) / symbol_info.point if not is_pending else 0,
                    "order_type": order_type,
                    "symbol": symbol,
                }

            except Exception as e:
                logger.exception("Error opening position: {}", e)
                if attempt < self.max_retries - 1:
                    time.sleep(self.retry_delay_ms / 1000)
                    continue
                return None
        
        return {"success": False, "error": "Max retries exceeded"}

    def close_position(self, ticket: int) -> bool:
        """Close a position by ticket (full close)"""
        return self.close_partial_position(ticket, volume=None)

    def close_partial_position(self, ticket: int, volume: Optional[float] = None) -> bool:
        """
        Close a position (fully or partially).
        
        Args:
            ticket: Position ticket
            volume: Volume to close (None = close all)
            
        Returns:
            True if successful
        """
        if not self.connected:
            return False
        
        # CRITICAL: Ensure correct account before trading (shared MT5 architecture)
        if not self.ensure_account():
            logger.error("Failed to ensure correct account is active for close")
            return False

        try:
            position = mt5.positions_get(ticket=ticket)
            if position is None or len(position) == 0:
                logger.error("Position {} not found", ticket)
                return False

            position = position[0]
            close_volume = volume if volume else position.volume
            
            # Validate partial volume
            if volume and volume > position.volume:
                logger.warning(f"Requested volume {volume} exceeds position volume {position.volume}")
                close_volume = position.volume

            order_type = mt5.ORDER_TYPE_SELL if position.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
            tick = mt5.symbol_info_tick(position.symbol)
            if tick is None:
                logger.error(f"Cannot get tick for {position.symbol}")
                return False
                
            price = tick.bid if position.type == mt5.ORDER_TYPE_BUY else tick.ask
            filling_mode = self._get_filling_mode(position.symbol)

            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": position.symbol,
                "volume": close_volume,
                "type": order_type,
                "position": ticket,
                "price": price,
                "deviation": 20,
                "magic": 234000,
                "comment": "Partial Close" if volume else "IEP Close",
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": filling_mode,
            }

            result = mt5.order_send(request)

            if result is None:
                error = mt5.last_error()
                logger.error(f"Failed to send close order for {ticket}. Error: {error}")
                return False

            if result.retcode != mt5.TRADE_RETCODE_DONE:
                logger.error(f"Failed to close position {ticket}, retcode: {result.retcode}, comment: {result.comment}")
                return False

            logger.info("Position {} closed (Vol: {}) successfully", ticket, close_volume)
            return True

        except Exception as e:
            logger.exception("Error closing position: {}", e)
            return False

    def modify_position(self, ticket: int, stop_loss: Optional[float] = None, take_profit: Optional[float] = None) -> bool:
        """
        Modify an existing position's SL/TP.
        
        Args:
            ticket: Position ticket
            stop_loss: New stop loss (None = keep current)
            take_profit: New take profit (None = keep current)
            
        Returns:
            True if successful
        """
        if not self.connected:
            return False

        try:
            position = mt5.positions_get(ticket=ticket)
            if position is None or len(position) == 0:
                logger.error("Position {} not found", ticket)
                return False

            position = position[0]
            
            request = {
                "action": mt5.TRADE_ACTION_SLTP,
                "symbol": position.symbol,
                "position": ticket,
                "sl": stop_loss if stop_loss else position.sl,
                "tp": take_profit if take_profit else position.tp,
            }

            result = mt5.order_send(request)

            if result is None:
                logger.error(f"Failed to modify position {ticket}: {mt5.last_error()}")
                return False

            if result.retcode != mt5.TRADE_RETCODE_DONE:
                logger.error(f"Modify failed for {ticket}: {result.comment}")
                return False

            logger.info(f"Position {ticket} modified: SL={stop_loss}, TP={take_profit}")
            return True

        except Exception as e:
            logger.exception("Error modifying position: {}", e)
            return False

    def get_open_positions(self, symbol: Optional[str] = None) -> List[Dict]:
        """Get all open positions"""
        if not self.connected:
            return []

        try:
            if symbol:
                positions = mt5.positions_get(symbol=symbol)
            else:
                positions = mt5.positions_get()

            if positions is None:
                return []

            result = []
            for pos in positions:
                result.append({
                    'ticket': pos.ticket,
                    'symbol': pos.symbol,
                    'type': 'BUY' if pos.type == mt5.ORDER_TYPE_BUY else 'SELL',
                    'volume': pos.volume,
                    'price_open': pos.price_open,
                    'price_current': pos.price_current,
                    'sl': pos.sl,
                    'tp': pos.tp,
                    'profit': pos.profit,
                    'time': datetime.fromtimestamp(pos.time),
                    'comment': pos.comment,
                })
            return result

        except Exception as e:
            logger.exception("Error getting positions: {}", e)
            return []

    def get_position(self, ticket: int) -> Optional[Dict]:
        """Get a specific position by ticket"""
        if not self.connected:
            return None
        try:
            positions = mt5.positions_get(ticket=ticket)
            if positions is None or len(positions) == 0:
                return None
            pos = positions[0]
            return {
                'ticket': pos.ticket,
                'symbol': pos.symbol,
                'type': 'BUY' if pos.type == mt5.ORDER_TYPE_BUY else 'SELL',
                'volume': pos.volume,
                'price_open': pos.price_open,
                'price_current': pos.price_current,
                'sl': pos.sl,
                'tp': pos.tp,
                'profit': pos.profit,
                'time': datetime.fromtimestamp(pos.time),
                'comment': pos.comment,
            }
        except Exception as e:
            logger.error(f"Error getting position {ticket}: {e}")
            return None

    def get_symbol_point(self, symbol: str) -> float:
        """Get point size for a symbol"""
        if not self.connected:
            return 0.00001
        symbol = self._normalize_symbol(symbol)
        try:
            info = mt5.symbol_info(symbol)
            if info:
                return info.point
            return 0.00001
        except Exception:
            return 0.00001

    def get_spread(self, symbol: str) -> Optional[float]:
        """Get current spread in pips"""
        price = self.get_current_price(symbol)
        if price:
            point = self.get_symbol_point(symbol)
            spread_points = price['spread'] / point
            return spread_points / 10  # Convert to pips for 5-digit
        return None

    def calculate_lot_size(
        self,
        symbol: str,
        risk_percent: float,
        sl_distance: float,
        account_balance: float,
        kelly_fraction: float = None,
        kelly_mode: str = "HALF"  # FULL, HALF, QUARTER
    ) -> float:
        """
        Calculate lot size based on risk percentage and stop loss distance.
        
        Args:
            symbol: Trading symbol
            risk_percent: Base risk percentage (1.0 = 1%)
            sl_distance: Stop loss distance in price
            account_balance: Account balance in USD
            kelly_fraction: Optional Kelly optimal fraction (0-1). 
                           If provided, risk_percent will be adjusted to min(risk_percent, kelly_adjusted)
            kelly_mode: FULL (100% Kelly), HALF (50% Kelly), QUARTER (25% Kelly)
        
        Returns:
            Calculated lot size
        """
        symbol = self._normalize_symbol(symbol)

        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                logger.error(f"Symbol info not found for {symbol}")
                return 0.01

            # ================================================================
            # KELLY-ADJUSTED RISK (from Dr. Chan's Quantitative Trading)
            # If Kelly fraction is provided, cap risk at Kelly-recommended level
            # ================================================================
            # ================================================================
            # SAFETY CLAMP: Minimum SL Distance (3.0 pips)
            # Aligns with Backtest logic to prevent massive lots on noise
            # ================================================================
            point = symbol_info.point
            # 1 pip = 10 points (standard for 5-digit brokers)
            min_sl_distance = 3.0 * (point * 10) 
            
            if sl_distance < min_sl_distance:
                logger.warning(
                    f"⚠️ SL Clamp: {symbol} SL {sl_distance:.5f} < {min_sl_distance:.5f} (3.0 pips). "
                    f"Using clamped value for safety."
                )
                sl_distance = min_sl_distance

            effective_risk_percent = risk_percent
            
            if kelly_fraction is not None and kelly_fraction > 0:
                # Apply Kelly mode scaling
                kelly_multiplier = {
                    "FULL": 1.0,
                    "HALF": 0.5,
                    "QUARTER": 0.25
                }.get(kelly_mode, 0.5)
                
                kelly_risk = kelly_fraction * kelly_multiplier * 100  # Convert to percent
                
                # Don't exceed the configured risk, but can reduce based on Kelly
                if kelly_risk < risk_percent:
                    effective_risk_percent = kelly_risk
                    logger.info(
                        f"🎯 Kelly Adjustment: Base risk {risk_percent}% → {effective_risk_percent:.2f}% "
                        f"(f*={kelly_fraction:.3f}, mode={kelly_mode})"
                    )
                else:
                    logger.debug(
                        f"Kelly allows higher risk ({kelly_risk:.2f}%), using configured {risk_percent}%"
                    )

            risk_amount = account_balance * (effective_risk_percent / 100)
            tick_size = symbol_info.trade_tick_size
            tick_value = symbol_info.trade_tick_value
            
            if tick_size == 0 or tick_value == 0:
                logger.error(f"Invalid tick data for {symbol}: size={tick_size}, value={tick_value}")
                return 0.01
                
            ticks_at_risk = sl_distance / tick_size
            risk_per_lot = ticks_at_risk * tick_value
            
            # FIX: Sanity check for XAUUSD (Gold)
            # Some brokers report weird tick_values (e.g. 0.01 instead of 1.0 for 100oz contract)
            if ("XAU" in symbol or "GOLD" in symbol) and sl_distance > 0.5:
                # Standard Lot (100oz) pays $100 per $1 move
                # Mini Lot (10oz) pays $10 per $1 move
                # Micro Lot (10oz) pays $1 per $1 move
                
                # If calculated risk_per_lot is wildly different from Contract Size calculation
                contract_risk = sl_distance * symbol_info.trade_contract_size
                
                if risk_per_lot < (contract_risk * 0.1): # If it's < 10% of expected (e.g. $2.85 vs $285)
                     logger.warning(
                         f"⚠️ Tick Value anomaly detected for {symbol}. "
                         f"TickVal: {tick_value}, Risk/Lot: {risk_per_lot:.2f}. "
                         f"Using Contract Size ({symbol_info.trade_contract_size}) fallback: {contract_risk:.2f}"
                     )
                     risk_per_lot = contract_risk

            if risk_per_lot == 0:
                return 0.01

            lot_size = risk_amount / risk_per_lot
            volume_step = symbol_info.volume_step
            lot_size = round(lot_size / volume_step) * volume_step
            
            # Check if we are forcing up to min volume
            if lot_size < symbol_info.volume_min:
                logger.warning(
                    f"⚠️ Small Account Warning: Calculated lots ({lot_size}) < Min lots ({symbol_info.volume_min}). "
                    f"Forcing trade size to {symbol_info.volume_min} lots. Risk % will be exceeded!"
                )
            
            lot_size = max(symbol_info.volume_min, min(lot_size, symbol_info.volume_max))

            logger.debug(
                "Calculated lot size for {}: {:.2f} (Risk: ${:.2f} @ {}%, Dist: {:.5f}, Risk/Lot: ${:.2f})", 
                symbol, lot_size, risk_amount, effective_risk_percent, sl_distance, risk_per_lot
            )
            return lot_size

        except Exception as e:
            logger.exception("Error calculating lot size: {}", e)
            return 0.01

    def is_market_open(self, symbol: str) -> bool:
        """Check if market is open for trading"""
        if not self.connected:
            return False
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                return False
            return symbol_info.trade_mode == mt5.SYMBOL_TRADE_MODE_FULL
        except Exception as e:
            logger.exception("Error checking market status: {}", e)
            return False

    def get_all_symbols(self) -> List[Dict]:
        """Get all symbols available in the terminal"""
        if not self.connected:
            return []
        try:
            symbols = mt5.symbols_get()
            if symbols is None:
                return []
            result = []
            for s in symbols:
                result.append({
                    "symbol": s.name,
                    "path": s.path,
                    "description": s.description,
                    "type": self._determine_symbol_type(s.path, s.name)
                })
            return result
        except Exception as e:
            logger.error(f"Error getting all symbols: {e}")
            return []

    def get_calendar_events(self, start: datetime = None, end: datetime = None) -> List[Dict]:
        """
        Fetch economic calendar events with importance and names.
        Joins calendar_get (schedule) with calendar_event_by_id (details).
        """
        if not self.connected: 
            return []
        
        try:
            if start is None: start = datetime.utcnow()
            if end is None: end = start + timedelta(hours=24)
            
            # 1. Get Scheduled Events (Values)
            try:
                values = mt5.calendar_get(start, end)
            except AttributeError:
                logger.warning("Remote MT5 package is outdated and does not support calendar_get. News Filter disabled.")
                return []
                
            if values is None:
                return []
                
            # 2. Get Event Details (Names, Importance)
            # We cache event details to avoid thousands of calls
            # Use a static cache on the class or instance if possible, 
            # here we fetch purely necessary ones.
            # To optimize, we might fetch ALL events once? 
            # mt5.calendar_events() returns thousands.
            # Better to fetch one by one and cache locally in this method? 
            # Or just fetch needed ones.
            
            # Simple approach: Fetch details for unique event_ids in the window
            event_ids = set(v.event_id for v in values)
            event_details = {}
            
            for eid in event_ids:
                details = mt5.calendar_event_by_id(eid)
                if details:
                    event_details[eid] = details
            
            # 3. Join and Format
            result = []
            for v in values:
                details = event_details.get(v.event_id)
                if not details: continue
                
                # Check currency (optional, filtering usually happened later)
                # But typically we want high impact
                
                # Convert importance enum to int (0=None, 1=Low, 2=Moderate, 3=High)
                importance = details.importance
                
                # Timestamp conversion
                # v.time is timestamp int or datetime?
                # MT5 python lib usually returns namedtuple with raw types.
                # 'time' is usually int (seconds).
                event_time = datetime.fromtimestamp(v.time)
                
                result.append({
                    "id": v.id,
                    "event_id": v.event_id,
                    "title": details.name,
                    "country": details.country_id, # Can map to 'USD', 'EUR' later
                    "time": event_time,
                    "importance": importance,
                    "currency": details.currency.upper() if details.currency else "",
                    "forecast": v.forecast,
                    "previous": v.prev_value
                })
                
            return result
            
        except Exception as e:
            logger.error(f"Error fetching calendar: {e}")
            return []
