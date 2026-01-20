"""
MT5 Bridge
Python wrapper for MetaTrader 5 API for live trading execution.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime
from enum import IntEnum

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    print("Warning: MetaTrader5 package not installed. Run: pip install MetaTrader5")


class OrderType(IntEnum):
    """MT5 order types."""
    BUY = 0
    SELL = 1
    BUY_LIMIT = 2
    SELL_LIMIT = 3
    BUY_STOP = 4
    SELL_STOP = 5


@dataclass
class MT5Position:
    """Open position data."""
    ticket: int
    symbol: str
    type: int  # 0=buy, 1=sell
    volume: float
    price_open: float
    price_current: float
    sl: float
    tp: float
    profit: float
    swap: float
    time: datetime
    magic: int
    comment: str


@dataclass
class MT5Order:
    """Pending order data."""
    ticket: int
    symbol: str
    type: int
    volume: float
    price: float
    sl: float
    tp: float
    time: datetime
    magic: int
    comment: str


class MT5Bridge:
    """
    Bridge for MT5 API communication.
    
    Handles:
    - Connection management
    - Account info
    - Position reading/modification
    - Order execution
    - History retrieval
    """
    
    def __init__(self, magic_number: int = 100000):
        """
        Initialize MT5 bridge.
        
        Args:
            magic_number: Base magic number for this EA
        """
        if not MT5_AVAILABLE:
            raise ImportError("MetaTrader5 package is required")
        
        self.magic_number = magic_number
        self.connected = False
        self._account_info = None
    
    def connect(self, login: int = None, password: str = None, server: str = None) -> bool:
        """
        Connect to MT5 terminal.
        
        Args:
            login: Account login (optional if already logged in)
            password: Account password
            server: Broker server name
            
        Returns:
            True if connected successfully
        """
        # Initialize MT5
        if not mt5.initialize():
            error = mt5.last_error()
            print(f"MT5 initialization failed: {error}")
            return False
        
        # Login if credentials provided
        if login and password and server:
            if not mt5.login(login, password, server):
                error = mt5.last_error()
                print(f"MT5 login failed: {error}")
                return False
        
        self.connected = True
        self._account_info = mt5.account_info()
        
        print(f"Connected to MT5: {self._account_info.name} ({self._account_info.server})")
        return True
    
    def disconnect(self):
        """Disconnect from MT5."""
        mt5.shutdown()
        self.connected = False
    
    def get_account_info(self) -> Dict[str, Any]:
        """Get account information."""
        if not self.connected:
            return {}
        
        info = mt5.account_info()
        if info is None:
            return {}
        
        return {
            'login': info.login,
            'balance': info.balance,
            'equity': info.equity,
            'margin': info.margin,
            'free_margin': info.margin_free,
            'profit': info.profit,
            'leverage': info.leverage,
            'currency': info.currency,
            'server': info.server,
            'name': info.name,
        }
    
    def get_symbol_info(self, symbol: str) -> Dict[str, Any]:
        """Get symbol information."""
        info = mt5.symbol_info(symbol)
        if info is None:
            return {}
        
        return {
            'name': info.name,
            'point': info.point,
            'digits': info.digits,
            'spread': info.spread,
            'tick_size': info.trade_tick_size,
            'tick_value': info.trade_tick_value,
            'min_lot': info.volume_min,
            'max_lot': info.volume_max,
            'lot_step': info.volume_step,
            'ask': info.ask,
            'bid': info.bid,
        }
    
    def get_positions(self, symbol: str = None) -> List[MT5Position]:
        """
        Get open positions.
        
        Args:
            symbol: Filter by symbol (optional)
            
        Returns:
            List of MT5Position objects
        """
        if symbol:
            positions = mt5.positions_get(symbol=symbol)
        else:
            positions = mt5.positions_get()
        
        if positions is None:
            return []
        
        # Filter by magic number
        result = []
        for pos in positions:
            if pos.magic == self.magic_number or self.magic_number == 0:
                result.append(MT5Position(
                    ticket=pos.ticket,
                    symbol=pos.symbol,
                    type=pos.type,
                    volume=pos.volume,
                    price_open=pos.price_open,
                    price_current=pos.price_current,
                    sl=pos.sl,
                    tp=pos.tp,
                    profit=pos.profit,
                    swap=pos.swap,
                    time=datetime.fromtimestamp(pos.time),
                    magic=pos.magic,
                    comment=pos.comment,
                ))
        
        return result
    
    def place_order(
        self,
        symbol: str,
        order_type: OrderType,
        volume: float,
        price: float = 0,
        sl: float = 0,
        tp: float = 0,
        comment: str = "",
        deviation: int = 10
    ) -> Tuple[bool, int, str]:
        """
        Place a trade order.
        
        Args:
            symbol: Trading symbol
            order_type: Order type (BUY, SELL, etc.)
            volume: Lot size
            price: Price (0 for market orders)
            sl: Stop loss price
            tp: Take profit price
            comment: Order comment
            deviation: Maximum deviation in points
            
        Returns:
            (success, ticket, message)
        """
        # Get current prices
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            return False, 0, "Failed to get tick"
        
        # Set price for market orders
        if price == 0:
            if order_type == OrderType.BUY:
                price = tick.ask
            elif order_type == OrderType.SELL:
                price = tick.bid
        
        # Determine action type
        if order_type in [OrderType.BUY, OrderType.SELL]:
            action = mt5.TRADE_ACTION_DEAL
        else:
            action = mt5.TRADE_ACTION_PENDING
        
        # Build request
        request = {
            "action": action,
            "symbol": symbol,
            "volume": volume,
            "type": int(order_type),
            "price": price,
            "sl": sl,
            "tp": tp,
            "deviation": deviation,
            "magic": self.magic_number,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        
        # Send order
        result = mt5.order_send(request)
        
        if result is None:
            return False, 0, "Order send failed - no result"
        
        if result.retcode != mt5.TRADE_RETCODE_DONE:
            return False, 0, f"Order failed: {result.comment}"
        
        return True, result.order, "OK"
    
    def modify_position(
        self,
        ticket: int,
        sl: float = None,
        tp: float = None
    ) -> Tuple[bool, str]:
        """
        Modify an open position.
        
        Args:
            ticket: Position ticket
            sl: New stop loss (None to keep current)
            tp: New take profit (None to keep current)
            
        Returns:
            (success, message)
        """
        # Get position
        position = mt5.positions_get(ticket=ticket)
        if not position:
            return False, "Position not found"
        
        pos = position[0]
        
        # Use current values if not specified
        new_sl = sl if sl is not None else pos.sl
        new_tp = tp if tp is not None else pos.tp
        
        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "symbol": pos.symbol,
            "position": ticket,
            "sl": new_sl,
            "tp": new_tp,
        }
        
        result = mt5.order_send(request)
        
        if result is None:
            return False, "Modify failed - no result"
        
        if result.retcode != mt5.TRADE_RETCODE_DONE:
            return False, f"Modify failed: {result.comment}"
        
        return True, "OK"
    
    def close_position(
        self,
        ticket: int,
        volume: float = None,
        deviation: int = 10
    ) -> Tuple[bool, str]:
        """
        Close a position (fully or partially).
        
        Args:
            ticket: Position ticket
            volume: Volume to close (None for full close)
            deviation: Maximum deviation
            
        Returns:
            (success, message)
        """
        # Get position
        position = mt5.positions_get(ticket=ticket)
        if not position:
            return False, "Position not found"
        
        pos = position[0]
        close_volume = volume if volume else pos.volume
        
        # Get current price
        tick = mt5.symbol_info_tick(pos.symbol)
        if tick is None:
            return False, "Failed to get tick"
        
        # Determine close price
        if pos.type == 0:  # Buy -> close at bid
            close_price = tick.bid
            close_type = mt5.ORDER_TYPE_SELL
        else:  # Sell -> close at ask
            close_price = tick.ask
            close_type = mt5.ORDER_TYPE_BUY
        
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": pos.symbol,
            "volume": close_volume,
            "type": close_type,
            "position": ticket,
            "price": close_price,
            "deviation": deviation,
            "magic": self.magic_number,
            "comment": "Close",
        }
        
        result = mt5.order_send(request)
        
        if result is None:
            return False, "Close failed - no result"
        
        if result.retcode != mt5.TRADE_RETCODE_DONE:
            return False, f"Close failed: {result.comment}"
        
        return True, "OK"
    
    def get_ohlcv(
        self,
        symbol: str,
        timeframe: str = 'M15',
        count: int = 500,
        start: datetime = None
    ) -> Optional[Any]:
        """
        Get OHLCV data from MT5.
        
        Args:
            symbol: Symbol name
            timeframe: Timeframe string (M1, M5, M15, H1, H4, D1)
            count: Number of bars
            start: Start datetime (optional)
            
        Returns:
            pandas DataFrame with OHLCV data
        """
        import pandas as pd
        
        # Map timeframe string to MT5 constant
        tf_map = {
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
        
        tf = tf_map.get(timeframe.upper(), mt5.TIMEFRAME_M15)
        
        # Get rates
        if start:
            rates = mt5.copy_rates_from(symbol, tf, start, count)
        else:
            rates = mt5.copy_rates_from_pos(symbol, tf, 0, count)
        
        if rates is None or len(rates) == 0:
            return None
        
        # Convert to DataFrame
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df = df.set_index('time')
        
        return df
    
    def get_history(
        self,
        start: datetime,
        end: datetime = None,
        symbol: str = None
    ) -> List[Dict]:
        """
        Get trade history.
        
        Args:
            start: Start datetime
            end: End datetime (default: now)
            symbol: Filter by symbol
            
        Returns:
            List of trade dictionaries
        """
        if end is None:
            end = datetime.now()
        
        # Get deals
        if symbol:
            deals = mt5.history_deals_get(start, end, group=symbol)
        else:
            deals = mt5.history_deals_get(start, end)
        
        if deals is None:
            return []
        
        result = []
        for deal in deals:
            if deal.magic == self.magic_number or self.magic_number == 0:
                result.append({
                    'ticket': deal.ticket,
                    'order': deal.order,
                    'time': datetime.fromtimestamp(deal.time),
                    'symbol': deal.symbol,
                    'type': deal.type,
                    'volume': deal.volume,
                    'price': deal.price,
                    'profit': deal.profit,
                    'commission': deal.commission,
                    'swap': deal.swap,
                    'magic': deal.magic,
                    'comment': deal.comment,
                })
        
        return result
