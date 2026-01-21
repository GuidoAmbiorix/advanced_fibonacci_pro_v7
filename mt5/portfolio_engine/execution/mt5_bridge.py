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
    Supports both local MetaTrader5 package and RPyC connection to Docker sidecar.
    """
    
    def __init__(self, magic_number: int = 100000):
        """
        Initialize MT5 bridge.
        
        Args:
            magic_number: Base magic number for this EA
        """
        self.magic_number = magic_number
        self.connected = False
        self._account_info = None
        self.use_rpyc = False
        self.rpc_conn = None
        self.mt5 = None  # The MT5 module (local or proxied)

        # Check for RPyC environment
        import os
        if os.environ.get('MT5_HOST'):
            self.use_rpyc = True
            print(f"MT5Bridge: Configured for RPyC connection to {os.environ.get('MT5_HOST')}")
        elif MT5_AVAILABLE:
            self.mt5 = mt5
        else:
            print("Warning: Local MetaTrader5 not installed and no RPyC host configured.")

    def connect(self, login: int = None, password: str = None, server: str = None) -> bool:
        """
        Connect to MT5 terminal.
        """
        if self.use_rpyc:
            return self._connect_rpyc()
        
        if not self.mt5:
            return False

        # Initialize local MT5
        if not self.mt5.initialize():
            print(f"MT5 initialization failed: {self.mt5.last_error()}")
            return False
        
        # Login if credentials provided
        if login and password and server:
            if not self.mt5.login(login, password, server):
                print(f"MT5 login failed: {self.mt5.last_error()}")
                return False
        
        self.connected = True
        self._account_info = self.mt5.account_info()
        print(f"Connected to Local MT5: {self._account_info.name} ({self._account_info.server})")
        return True

    def _connect_rpyc(self) -> bool:
        """Establish RPyC connection to sidecar with enhanced robustness."""
        import rpyc
        import os
        import time

        host = os.environ.get('MT5_HOST', 'localhost')
        port = int(os.environ.get('MT5_PORT', 8002))
        
        print(f"Connecting to MT5 Sidecar at {host}:{port}...")
        
        try:
            # Retry loop for Docker startup race conditions
            for i in range(10):
                try:
                    self.rpc_conn = rpyc.classic.connect(host, port)
                    break
                except Exception as e:
                    print(f"Connection attempt {i+1} failed: {e}")
                    time.sleep(3)
            
            if not self.rpc_conn:
                return False

            # Get the mt5 proxy from our sidecar's get_mt5_proxy()
            print("Fetching MT5 Proxy from Sidecar...")
            self.mt5 = self.rpc_conn.modules.__main__.get_mt5_proxy()
            
            if self.mt5 is None:
                print("Error: Sidecar failed to initialize mt5linux proxy.")
                return False
            
            # Link Proxy Functions from sidecar
            print("Linking sidecar proxy functions...")
            self.proxy_order_check = self.rpc_conn.modules.__main__.order_check
            self.proxy_order_send = self.rpc_conn.modules.__main__.order_send
            
            # Check initialization on remote
            if not self.mt5.initialize():
                 print(f"Remote MT5 not initialized: {self.mt5.last_error()}")
                 return False

            self.connected = True
            try:
                self._account_info = self.mt5.account_info()
                if self._account_info:
                     print(f"Connected to Remote MT5 (Sidecar): {self._account_info.login}")
            except:
                print("Connected, but failed to get account info")
                
            return True

        except Exception as e:
            print(f"RPyC connection error: {e}")
            return False

    def disconnect(self):
        """Disconnect from MT5."""
        if self.mt5:
            self.mt5.shutdown()
        
        if self.rpc_conn:
            self.rpc_conn.close()
            
        self.connected = False
    
    def get_account_info(self) -> Dict[str, Any]:
        """Get account information."""
        if not self.connected or not self.mt5:
            return {}
        
        info = self.mt5.account_info()
        if info is None:
            return {}
        
        return {
            'login': info.login,
            'balance': info.balance,
            'equity': info.equity,
            'margin': info.margin,
            'margin_free': info.margin_free,
            'profit': info.profit,
            'leverage': info.leverage,
            'currency': info.currency,
            'server': info.server,
            'name': info.name,
        }

    def get_global_variable(self, name: str) -> float:
        """Get a global variable value via sidecar safe helper."""
        if not self.use_rpyc or not self.rpc_conn: return 0.0
        try:
            return float(self.rpc_conn.modules.__main__.safe_get_global_variable(name))
        except:
            return 0.0

    def get_governor_status(self) -> Dict[str, Any]:
        """Read Portfolio Governor state from Global Variables."""
        return {
            'active': self.get_global_variable("GV_GOVERNOR_ACTIVE"),
            'risk_mult': self.get_global_variable("GV_RISK_MULTIPLIER"),
            'drawdown': self.get_global_variable("GV_CURRENT_DD"),
            'exposure': self.get_global_variable("GV_TOTAL_EXPOSURE"),
            'rolling_pf': self.get_global_variable("GV_ROLLING_PF"),
            'group_usd': self.get_global_variable("GV_GROUP_USD_RISK"),
        }

    def set_global_variable(self, name: str, value: float) -> bool:
        """Set a global variable value in MT5."""
        if not self.mt5: return False
        try:
            return self.mt5.global_variable_set(name, value)
        except:
            return False

    def set_governor_status(self, active: bool) -> bool:
        """Enable or Disable the Portfolio Governor."""
        val = 1.0 if active else 0.0
        return self.set_global_variable("GV_GOVERNOR_ACTIVE", val)

    def run_backtest(self, config_content: str) -> str:
        """Invokes the remote backtest runner."""
        if not self.use_rpyc or not self.rpc_conn:
            return "Error: RPyC not connected"
        try:
            # Call the function defined in the server's __main__ scope
            return self.rpc_conn.modules.__main__.run_backtest(config_content)
        except Exception as e:
            return f"RPC Error: {e}"

    def launch_bot(self, symbol: str = "XAUUSD") -> str:
        """Invokes the remote bot launch (chart open + template)."""
        if not self.use_rpyc or not self.rpc_conn:
            return "Error: RPyC not connected"
        try:
            return self.rpc_conn.modules.__main__.open_chart_with_ea(symbol)
        except Exception as e:
            return f"RPC Error: {e}"
    
    def get_symbol_info(self, symbol: str) -> Dict[str, Any]:
        """Get symbol information."""
        if not self.mt5: return {}
        
        info = self.mt5.symbol_info(symbol)
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
        """Get open positions."""
        if not self.mt5: return []

        if symbol:
            positions = self.mt5.positions_get(symbol=symbol)
        else:
            positions = self.mt5.positions_get()
        
        if positions is None:
            return []
        
        # When using RPyC, 'positions' is a netref tuple of netref objects.
        # Iterating it is slow over network.
        # Ideally we fetch by value, but for simplicity we iterate.
        # Optimization: Use rpyc.utils.classic.obtain(positions) if RPyC
        
        if self.use_rpyc:
            import rpyc
            # Fetch the whole structure at once
            positions = rpyc.utils.classic.obtain(positions)

        # Filter by magic number
        result = []
        for pos in positions:
            # Handle RPyC object vs Local namedtuple
            # The 'obtain' above converts them to local dicts/tuples usually, or we access fields
            try:
                p_magic = pos.magic
            except AttributeError:
                # If obtained as dict or struct
                p_magic = getattr(pos, 'magic', 0)

            if p_magic == self.magic_number or self.magic_number == 0:
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
        """Place a trade order."""
        if not self.mt5: return False, 0, "Not connected"

        # Get current prices
        tick = self.mt5.symbol_info_tick(symbol)
        if tick is None:
            return False, 0, "Failed to get tick"
        
        # Set price for market orders
        if price == 0:
            if order_type == OrderType.BUY:
                price = tick.ask
            elif order_type == OrderType.SELL:
                price = tick.bid
        
        # MT5 constants needed. If RPyC, we need to access them from the remote module
        # or use hardcoded values if we are sure they match.
        # Safe way: get them from self.mt5 module
        TRADE_ACTION_DEAL = self.mt5.TRADE_ACTION_DEAL if self.use_rpyc else mt5.TRADE_ACTION_DEAL
        TRADE_ACTION_PENDING = self.mt5.TRADE_ACTION_PENDING if self.use_rpyc else mt5.TRADE_ACTION_PENDING
        ORDER_TIME_GTC = self.mt5.ORDER_TIME_GTC if self.use_rpyc else mt5.ORDER_TIME_GTC
        ORDER_FILLING_IOC = self.mt5.ORDER_FILLING_IOC if self.use_rpyc else mt5.ORDER_FILLING_IOC
        TRADE_RETCODE_DONE = self.mt5.TRADE_RETCODE_DONE if self.use_rpyc else mt5.TRADE_RETCODE_DONE

        # Determine action type
        if order_type in [OrderType.BUY, OrderType.SELL]:
            action = TRADE_ACTION_DEAL
        else:
            action = TRADE_ACTION_PENDING
        
        # Build request
        request = {
            "action": action,
            "symbol": symbol,
            "volume": volume,
            "type": int(order_type),
            "price": price,
            "sl": float(sl), # RPyC picky about types sometimes
            "tp": float(tp),
            "deviation": deviation,
            "magic": self.magic_number,
            "comment": comment,
            "type_time": ORDER_TIME_GTC,
            "type_filling": ORDER_FILLING_IOC,
        }
        
        # Send order
        if self.use_rpyc and hasattr(self, 'proxy_order_send'):
             result = self.proxy_order_send(request)
        else:
             result = self.mt5.order_send(request)
        
        if result is None:
            return False, 0, "Order send failed - no result"
        
        if result.retcode != TRADE_RETCODE_DONE:
            return False, 0, f"Order failed: {result.comment}"
        
        return True, result.order, "OK"
    
    def modify_position(
        self,
        ticket: int,
        sl: float = None,
        tp: float = None
    ) -> Tuple[bool, str]:
        """Modify an open position."""
        if not self.mt5: return False, "Not connected"

        # Get position
        position = self.mt5.positions_get(ticket=ticket)
        if not position:
            return False, "Position not found"
        
        pos = position[0]
        
        # Use current values if not specified
        new_sl = sl if sl is not None else pos.sl
        new_tp = tp if tp is not None else pos.tp
        
        TRADE_ACTION_SLTP = self.mt5.TRADE_ACTION_SLTP if self.use_rpyc else mt5.TRADE_ACTION_SLTP
        TRADE_RETCODE_DONE = self.mt5.TRADE_RETCODE_DONE if self.use_rpyc else mt5.TRADE_RETCODE_DONE

        request = {
            "action": TRADE_ACTION_SLTP,
            "symbol": pos.symbol,
            "position": ticket,
            "sl": float(new_sl),
            "tp": float(new_tp),
        }
        
        if self.use_rpyc and hasattr(self, 'proxy_order_send'):
             result = self.proxy_order_send(request)
        else:
             result = self.mt5.order_send(request)
        
        if result is None:
            return False, "Modify failed - no result"
        
        if result.retcode != TRADE_RETCODE_DONE:
            return False, f"Modify failed: {result.comment}"
        
        return True, "OK"
    
    def close_position(
        self,
        ticket: int,
        volume: float = None,
        deviation: int = 10
    ) -> Tuple[bool, str]:
        """Close a position."""
        if not self.mt5: return False, "Not connected"

        position = self.mt5.positions_get(ticket=ticket)
        if not position:
            return False, "Position not found"
        
        pos = position[0]
        close_volume = volume if volume else pos.volume
        
        tick = self.mt5.symbol_info_tick(pos.symbol)
        if tick is None:
            return False, "Failed to get tick"
        
        ORDER_TYPE_SELL = self.mt5.ORDER_TYPE_SELL if self.use_rpyc else mt5.ORDER_TYPE_SELL
        ORDER_TYPE_BUY = self.mt5.ORDER_TYPE_BUY if self.use_rpyc else mt5.ORDER_TYPE_BUY
        TRADE_ACTION_DEAL = self.mt5.TRADE_ACTION_DEAL if self.use_rpyc else mt5.TRADE_ACTION_DEAL
        TRADE_RETCODE_DONE = self.mt5.TRADE_RETCODE_DONE if self.use_rpyc else mt5.TRADE_RETCODE_DONE

        if pos.type == 0:  # Buy -> close at bid
            close_price = tick.bid
            close_type = ORDER_TYPE_SELL
        else:  # Sell -> close at ask
            close_price = tick.ask
            close_type = ORDER_TYPE_BUY
        
        request = {
            "action": TRADE_ACTION_DEAL,
            "symbol": pos.symbol,
            "volume": close_volume,
            "type": close_type,
            "position": ticket,
            "price": close_price,
            "deviation": deviation,
            "magic": self.magic_number,
            "comment": "Close",
        }
        
        if self.use_rpyc and hasattr(self, 'proxy_order_send'):
             result = self.proxy_order_send(request)
        else:
             result = self.mt5.order_send(request)
        
        if result is None:
            return False, "Close failed - no result"
        
        if result.retcode != TRADE_RETCODE_DONE:
            return False, f"Close failed: {result.comment}"
        
        return True, "OK"
    
    def get_ohlcv(
        self,
        symbol: str,
        timeframe: str = 'M15',
        count: int = 500,
        start: datetime = None
    ) -> Optional[Any]:
        """Get OHLCV data (delegated to sidecar for RPyC)."""
        if self.use_rpyc and self.rpc_conn:
            try:
                rates = self.rpc_conn.modules.__main__.get_ohlcv(symbol, timeframe, count)
                if rates is not None and len(rates) > 0:
                    import pandas as pd
                    try:
                        # 'rates' is a numpy structured array (via obtain) or list of tuples
                        # pd.DataFrame(rates) handles structured arrays by using field names as columns
                        df = pd.DataFrame(rates)
                        
                        # Ensure 'time' column exists
                        if 'time' not in df.columns and 0 in df.columns:
                            # Fallback if it came as tuples without names
                             columns = ['time', 'open', 'high', 'low', 'close', 'tick_volume', 'spread', 'real_volume']
                             if df.shape[1] == 8:
                                  df.columns = columns
                    
                        if 'time' in df.columns:
                            df['time'] = pd.to_datetime(df['time'], unit='s')
                            df.set_index('time', inplace=True)
                            return df
                    except Exception as e:
                         print(f"Data conversion error: {e}")
                         return None
                    else:
                        print("RPyC OHLCV Error: 'time' column missing from dataframe")
                        return None
            except Exception as e:
                print(f"RPyC OHLCV Error: {e}")
            return None
            
        if not self.mt5: return None
        import pandas as pd
        
        # Helper to get attr from local or remote module
        def get_attr(name):
             return getattr(self.mt5, name) if self.use_rpyc else getattr(mt5, name)

        tf_map = {
            'M1': get_attr('TIMEFRAME_M1'),
            'M5': get_attr('TIMEFRAME_M5'),
            'M15': get_attr('TIMEFRAME_M15'),
            'M30': get_attr('TIMEFRAME_M30'),
            'H1': get_attr('TIMEFRAME_H1'),
            'H4': get_attr('TIMEFRAME_H4'),
            'D1': get_attr('TIMEFRAME_D1'),
            'W1': get_attr('TIMEFRAME_W1'),
            'MN1': get_attr('TIMEFRAME_MN1'),
        }
        
        tf = tf_map.get(timeframe.upper(), get_attr('TIMEFRAME_M15'))
        
        # Get rates
        if start:
            rates = self.mt5.copy_rates_from(symbol, tf, start, count)
        else:
            rates = self.mt5.copy_rates_from_pos(symbol, tf, 0, count)
        
        if rates is None or len(rates) == 0:
            return None
            
        # Optimization: Fetch numpy array by value if RPyC
        if self.use_rpyc:
             import rpyc
             rates = rpyc.utils.classic.obtain(rates)
        
        # Convert to DataFrame
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df = df.set_index('time')
        
        return df
    
    def get_history(self, start: datetime, end: datetime = None, symbol: str = None) -> List[Dict]:
        """Get trade history."""
        if not self.mt5: return []
        if end is None:
            end = datetime.now()
        
        # Get deals
        if symbol:
            deals = self.mt5.history_deals_get(start, end, group=symbol)
        else:
            deals = self.mt5.history_deals_get(start, end)
            
        if deals is None:
            return []
            
        if self.use_rpyc:
             import rpyc
             deals = rpyc.utils.classic.obtain(deals)
        
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
