"""
============================================================================
INSTITUTIONAL EDGE PRO - MT5 Integration Layer (Enhanced)
============================================================================
Handles all MetaTrader 5 connections and operations with improved execution
"""

import pandas as pd
from typing import Optional, List, Dict, Tuple
from datetime import datetime, timedelta
from loguru import logger
import time
import os
from app.core.config import settings

try:
    import MetaTrader5 as mt5
except ImportError:
    mt5 = None
    logger.warning("MetaTrader5 package not found. Running in headless/mock mode.")


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

    def connect(self) -> bool:
        """Connect to MetaTrader 5"""
        try:
            # RPyC Connection Logic
            mt5_host = os.getenv("MT5_HOST")
            if mt5_host:
                try:
                    import rpyc
                    mt5_port = int(os.getenv("MT5_PORT", 18812))
                    logger.info(f"Connecting to remote MT5 at {mt5_host}:{mt5_port}...")
                    conn = rpyc.classic.connect(mt5_host, mt5_port)
                    global mt5
                    mt5 = conn.modules.MetaTrader5
                    
                    # Re-initialize timeframe map with remote constants
                    self.timeframe_map = {
                        'M1': mt5.TIMEFRAME_M1, 'M5': mt5.TIMEFRAME_M5, 'M15': mt5.TIMEFRAME_M15,
                        'M30': mt5.TIMEFRAME_M30, 'H1': mt5.TIMEFRAME_H1, 'H4': mt5.TIMEFRAME_H4,
                        'D1': mt5.TIMEFRAME_D1, 'W1': mt5.TIMEFRAME_W1, 'MN1': mt5.TIMEFRAME_MN1,
                    }
                except Exception as e:
                    logger.error(f"Failed to connect via RPyC: {e}")
                    return False

            if mt5 is None:
                logger.error("MetaTrader5 package is not installed and RPyC connection failed")
                return False

            if self.path and not mt5_host: # Only check path if local
                if os.path.isdir(self.path):
                    self.path = os.path.join(self.path, "terminal64.exe")
                if not mt5.initialize(path=self.path):
                    logger.error("MT5 initialize() failed, error code: {}", mt5.last_error())
                    return False
            else:
                # Initialize with explicit login parameters to ensure session
                logger.info(f"Attempting MT5 initialize with: Login={self.login}, Server={self.server}")
                login_id = int(self.login) if self.login and str(self.login).isdigit() else 0
                
                # Try initialize
                if not mt5.initialize(
                    login=login_id,
                    password=self.password or "",
                    server=self.server or ""
                ):
                    err_code = mt5.last_error()
                    logger.error(f"❌ MT5 initialize() failed, error code: {err_code}")
                    return False
            
            # Additional explicit login to be safe
            if self.login and self.password and self.server:
                authorized = mt5.login(
                    login=int(self.login),
                    password=self.password,
                    server=self.server
                )
                if not authorized:
                    err_code = mt5.last_error()
                    logger.error(f"❌ MT5 login failed, error code: {err_code}")
                    return False
                logger.info("✅ Successfully logged in to MT5 account: {}", self.login)

            self.connected = True
            logger.info("✅ MT5 connection established")

            account_info = mt5.account_info()
            if account_info:
                logger.info("Account balance: ${:.2f}, Equity: ${:.2f}",
                          account_info.balance, account_info.equity)
            return True

        except Exception as e:
            logger.exception("Error connecting to MT5: {}", e)
            return False

    def disconnect(self):
        """Disconnect from MT5"""
        if self.connected:
            mt5.shutdown()
            self.connected = False
            logger.info("MT5 connection closed")

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
            return mt5.ORDER_FILLING_FOK
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                return mt5.ORDER_FILLING_FOK
            filling = symbol_info.filling_mode
            if filling & 1:
                return mt5.ORDER_FILLING_FOK
            if filling & 2:
                return mt5.ORDER_FILLING_IOC
            return mt5.ORDER_FILLING_RETURN
        except Exception as e:
            logger.error(f"Error determining filling mode: {e}")
            return mt5.ORDER_FILLING_FOK

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

        symbol = self._normalize_symbol(symbol)

        for attempt in range(self.max_retries):
            try:
                symbol_info = mt5.symbol_info(symbol)
                if symbol_info is None:
                    return None

                if not symbol_info.visible:
                    if not mt5.symbol_select(symbol, True):
                        logger.error("Failed to select symbol {}", symbol)
                        return None

                tick = mt5.symbol_info_tick(symbol)
                if tick is None:
                    logger.error("Failed to get tick for {}", symbol)
                    return None

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

                request = {
                    "action": action,
                    "symbol": symbol,
                    "volume": volume,
                    "type": order_type_mt5,
                    "price": execution_price,
                    "deviation": deviation,
                    "magic": 234000,
                    "comment": comment,
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": filling_mode,
                }

                if stop_loss:
                    request["sl"] = stop_loss
                if take_profit:
                    request["tp"] = take_profit

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
                    
                    logger.error("Order failed, retcode: {}, description: {}",
                               result.retcode, result.comment)
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
        account_balance: float
    ) -> float:
        """Calculate lot size based on risk percentage and stop loss distance"""
        symbol = self._normalize_symbol(symbol)

        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                logger.error(f"Symbol info not found for {symbol}")
                return 0.01

            risk_amount = account_balance * (risk_percent / 100)
            tick_size = symbol_info.trade_tick_size
            tick_value = symbol_info.trade_tick_value
            
            if tick_size == 0 or tick_value == 0:
                logger.error(f"Invalid tick data for {symbol}: size={tick_size}, value={tick_value}")
                return 0.01
                
            ticks_at_risk = sl_distance / tick_size
            risk_per_lot = ticks_at_risk * tick_value
            
            if risk_per_lot == 0:
                return 0.01

            lot_size = risk_amount / risk_per_lot
            volume_step = symbol_info.volume_step
            lot_size = round(lot_size / volume_step) * volume_step
            lot_size = max(symbol_info.volume_min, min(lot_size, symbol_info.volume_max))

            logger.debug(
                "Calculated lot size for {}: {:.2f} (Risk: ${:.2f}, Dist: {:.5f}, Risk/Lot: ${:.2f})", 
                symbol, lot_size, risk_amount, sl_distance, risk_per_lot
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
