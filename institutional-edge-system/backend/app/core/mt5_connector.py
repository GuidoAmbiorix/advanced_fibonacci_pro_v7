"""
============================================================================
INSTITUTIONAL EDGE PRO - MT5 Integration Layer
============================================================================
Handles all MetaTrader 5 connections and operations
"""

import pandas as pd
from typing import Optional, List, Dict, Tuple
from datetime import datetime, timedelta
from loguru import logger
import time
import os

try:
    import MetaTrader5 as mt5
except ImportError:
    mt5 = None
    logger.warning("MetaTrader5 package not found. Running in headless/mock mode.")


class MT5Connector:
    """
    MetaTrader 5 Connection and Data Management
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
            # Mock timeframe mapping for headless mode
            self.timeframe_map = {
                'M1': 1,
                'M5': 5,
                'M15': 15,
                'M30': 30,
                'H1': 60,
                'H4': 240,
                'D1': 1440,
                'W1': 10080,
                'MN1': 43200,
            }

    def normalize_symbol(self, symbol: str, symbol_type: str = "forex") -> str:
        """
        Normalize symbol based on type
        For crypto symbols, ensure they have # prefix

        Args:
            symbol: Raw symbol name (e.g., "BTCUSD" or "#BTCUSD")
            symbol_type: Type of symbol ("forex" or "crypto")

        Returns:
            Normalized symbol for MT5
        """
        if symbol_type == "crypto":
            # Add # prefix if not present
            if not symbol.startswith("#"):
                return f"#{symbol}"
        return symbol


    def connect(self) -> bool:
        """
        Connect to MetaTrader 5

        Returns:
            True if connected successfully, False otherwise
        """
        try:
            if mt5 is None:
                logger.error("MetaTrader5 package is not installed")
                return False

            # Initialize MT5
            if self.path:
                # Auto-correct path if it's a directory
                if os.path.isdir(self.path):
                    logger.info(f"MT5 path is a directory, appending terminal64.exe: {self.path}")
                    self.path = os.path.join(self.path, "terminal64.exe")

                if not mt5.initialize(path=self.path):
                    logger.error("MT5 initialize() failed, error code: {}", mt5.last_error())
                    return False
            else:
                if not mt5.initialize():
                    logger.error("MT5 initialize() failed, error code: {}", mt5.last_error())
                    return False

            # Login if credentials provided
            if self.login and self.password and self.server:
                authorized = mt5.login(
                    login=int(self.login),
                    password=self.password,
                    server=self.server
                )

                if not authorized:
                    logger.error("MT5 login failed, error code: {}", mt5.last_error())
                    mt5.shutdown()
                    return False

                logger.info("Successfully logged in to MT5 account: {}", self.login)

            self.connected = True
            logger.info("MT5 connection established")

            # Log account info
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


    def get_ohlcv_data(
        self,
        symbol: str,
        timeframe: str,
        bars: int = 500
    ) -> Optional[pd.DataFrame]:
        """
        Get OHLCV data from MT5

        Args:
            symbol: Trading symbol (e.g., "EURUSD")
            timeframe: Timeframe string (e.g., "H1")
            bars: Number of bars to fetch

        Returns:
            DataFrame with columns: time, open, high, low, close, volume
        """
        if not self.connected:
            logger.error("Not connected to MT5")
            return None

        try:
            # Get MT5 timeframe constant
            mt5_timeframe = self.timeframe_map.get(timeframe)
            if not mt5_timeframe:
                logger.error("Invalid timeframe: {}", timeframe)
                return None

            # Fetch data
            rates = mt5.copy_rates_from_pos(symbol, mt5_timeframe, 0, bars)

            if rates is None or len(rates) == 0:
                logger.error("Failed to get rates for {}, error: {}", symbol, mt5.last_error())
                return None

            # Convert to DataFrame
            df = pd.DataFrame(rates)
            df['time'] = pd.to_datetime(df['time'], unit='s')

            # Rename columns to match our standard
            df = df.rename(columns={'tick_volume': 'volume'})

            logger.debug("Fetched {} bars for {} {}", len(df), symbol, timeframe)

            return df[['time', 'open', 'high', 'low', 'close', 'volume']]

        except Exception as e:
            logger.exception("Error fetching OHLCV data: {}", e)
            return None


    def get_current_price(self, symbol: str) -> Optional[Dict]:
        """
        Get current price for symbol

        Args:
            symbol: Trading symbol

        Returns:
            Dictionary with bid, ask, last prices
        """
        if not self.connected:
            return None

        try:
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                logger.error("Failed to get tick for {}", symbol)
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
        """
        Get account information

        Returns:
            Dictionary with account details
        """
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
        """
        Determine the correct filling mode for the symbol
        """
        if not self.connected:
            return mt5.ORDER_FILLING_FOK
            
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                return mt5.ORDER_FILLING_FOK

            filling = symbol_info.filling_mode
            
            # Check flags (prioritize FOK > IOC > RETURN)
            # SYMBOL_FILLING_FOK = 1, SYMBOL_FILLING_IOC = 2
            if filling & 1:
                return mt5.ORDER_FILLING_FOK
            
            if filling & 2:
                return mt5.ORDER_FILLING_IOC
                
            return mt5.ORDER_FILLING_RETURN
            
        except Exception as e:
            logger.error(f"Error determining filling mode: {e}")
            return mt5.ORDER_FILLING_FOK


    def open_position(
        self,
        symbol: str,
        order_type: str,
        volume: float,
        stop_loss: Optional[float] = None,
        take_profit: Optional[float] = None,
        comment: str = "Institutional Edge Pro"
    ) -> Optional[Dict]:
        """
        Open a trading position

        Args:
            symbol: Trading symbol
            order_type: "BUY" or "SELL"
            volume: Lot size
            stop_loss: Stop loss price (optional)
            take_profit: Take profit price (optional)
            comment: Order comment

        Returns:
            Dictionary with order result
        """
        if not self.connected:
            logger.error("Not connected to MT5")
            return None

        try:
            # Get symbol info
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                logger.error("Symbol {} not found", symbol)
                return None

            if not symbol_info.visible:
                if not mt5.symbol_select(symbol, True):
                    logger.error("Failed to select symbol {}", symbol)
                    return None

            # Get current price
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                logger.error("Failed to get tick for {}", symbol)
                return None

            # Prepare request
            order_type_mt5 = mt5.ORDER_TYPE_BUY if order_type == "BUY" else mt5.ORDER_TYPE_SELL
            price = tick.ask if order_type == "BUY" else tick.bid

            # Determine filling mode
            filling_mode = self._get_filling_mode(symbol)

            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": symbol,
                "volume": volume,
                "type": order_type_mt5,
                "price": price,
                "deviation": 20,
                "magic": 234000,
                "comment": comment,
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": filling_mode,
            }

            # Add SL/TP if provided
            if stop_loss:
                request["sl"] = stop_loss
            if take_profit:
                request["tp"] = take_profit

            # Send order
            result = mt5.order_send(request)

            if result is None:
                logger.error("Order send failed, error: {}", mt5.last_error())
                return None

            if result.retcode != mt5.TRADE_RETCODE_DONE:
                logger.error("Order failed, retcode: {}, description: {}",
                           result.retcode, result.comment)
                return {
                    "success": False,
                    "error": f"MT5 Error: {result.comment} ({result.retcode})"
                }

            logger.info("Order opened successfully: {} {} {} lots @ {}",
                       order_type, symbol, volume, result.price)

            return {
                "success": True,
                "ticket": result.order,
                "volume": result.volume,
                "price": result.price,
                "order_type": order_type,
                "symbol": symbol,
            }

        except Exception as e:
            logger.exception("Error opening position: {}", e)
            return None


    def close_position(self, ticket: int) -> bool:
        """
        Close a position by ticket
        
        Args:
            ticket: Position ticket number
            
        Returns:
            True if closed successfully
        """
        return self.close_partial_position(ticket, volume=None)

    def close_partial_position(self, ticket: int, volume: Optional[float] = None) -> bool:
        """
        Close a position (fully or partially)
        
        Args:
            ticket: Position ticket number
            volume: Volume to close (None for full close)
            
        Returns:
            True if closed successfully
        """
        if not self.connected:
            return False

        try:
            position = mt5.positions_get(ticket=ticket)
            if position is None or len(position) == 0:
                logger.error("Position {} not found", ticket)
                return False

            position = position[0]
            
            # Determine volume to close
            close_volume = volume if volume else position.volume

            # Prepare close request
            order_type = mt5.ORDER_TYPE_SELL if position.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
            price = mt5.symbol_info_tick(position.symbol).bid if position.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(position.symbol).ask

            # Determine filling mode
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


    def get_open_positions(self, symbol: Optional[str] = None) -> List[Dict]:
        """
        Get all open positions

        Args:
            symbol: Filter by symbol (optional)

        Returns:
            List of position dictionaries
        """
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


    def calculate_lot_size(
        self,
        symbol: str,
        risk_percent: float,
        sl_distance: float,
        account_balance: float
    ) -> float:
        """
        Calculate lot size based on risk percentage and stop loss distance
        
        Args:
            symbol: Trading symbol
            risk_percent: Risk percentage (e.g., 2.0 for 2%)
            sl_distance: Distance from entry to stop loss in price units
            account_balance: Account balance

        Returns:
            Calculated lot size
        """
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is None:
                logger.error(f"Symbol info not found for {symbol}")
                return 0.01

            risk_amount = account_balance * (risk_percent / 100)
            
            # Get tick value and size
            tick_size = symbol_info.trade_tick_size
            tick_value = symbol_info.trade_tick_value
            
            if tick_size == 0 or tick_value == 0:
                logger.error(f"Invalid tick data for {symbol}: size={tick_size}, value={tick_value}")
                return 0.01
                
            # Calculate money risk for 1 lot
            # Formula: (SL Distance / Tick Size) * Tick Value
            ticks_at_risk = sl_distance / tick_size
            risk_per_lot = ticks_at_risk * tick_value
            
            if risk_per_lot == 0:
                return 0.01

            lot_size = risk_amount / risk_per_lot

            # Round to symbol's volume step
            volume_step = symbol_info.volume_step
            lot_size = round(lot_size / volume_step) * volume_step

            # Ensure within limits
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
        """
        Get all symbols available in the terminal
        """
        if not self.connected:
            return []

        try:
            symbols = mt5.symbols_get()
            if symbols is None:
                return []

            result = []
            for s in symbols:
                # Basic filtering to avoid clutter (optional)
                # if not s.visible: continue 
                
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

    def _determine_symbol_type(self, path: str, name: str) -> str:
        """Helper to guess symbol type from path or name"""
        path_lower = path.lower()
        name_lower = name.lower()
        
        if "crypto" in path_lower or "crypto" in name_lower or "btc" in name_lower:
            return "crypto"
        if "forex" in path_lower or "fx" in path_lower:
            return "forex"
        if "index" in path_lower or "indices" in path_lower or "us30" in name_lower or "nas100" in name_lower:
            return "index"
        if "metal" in path_lower or "gold" in name_lower or "xau" in name_lower:
            return "commodity"
        if "stock" in path_lower or "share" in path_lower:
            return "stock"
            
        return "forex" # Default
