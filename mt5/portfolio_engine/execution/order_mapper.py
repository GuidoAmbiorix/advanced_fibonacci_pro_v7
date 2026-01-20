"""
Order Mapper
Maps signals from symbol agents to MT5 orders.
"""

from dataclasses import dataclass
from typing import Optional, Dict, Any
from datetime import datetime

from symbols.base_agent import Signal, SignalType
from .mt5_bridge import MT5Bridge, OrderType


@dataclass
class OrderRequest:
    """Order request for MT5 execution."""
    symbol: str
    order_type: OrderType
    volume: float
    entry_price: float
    stop_loss: float
    take_profit: float
    comment: str
    risk_amount: float
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'symbol': self.symbol,
            'order_type': self.order_type.name,
            'volume': self.volume,
            'entry_price': self.entry_price,
            'stop_loss': self.stop_loss,
            'take_profit': self.take_profit,
            'comment': self.comment,
            'risk_amount': self.risk_amount,
        }


class OrderMapper:
    """
    Maps trading signals to MT5 order requests.
    
    Handles:
    - Signal to order conversion
    - Position sizing calculation
    - Risk-based volume calculation
    """
    
    def __init__(self, mt5_bridge: MT5Bridge):
        """
        Initialize order mapper.
        
        Args:
            mt5_bridge: MT5 bridge instance
        """
        self.mt5 = mt5_bridge
    
    def signal_to_order(
        self,
        signal: Signal,
        equity: float,
        risk_multiplier: float = 1.0,
        tp_r: float = 0
    ) -> Optional[OrderRequest]:
        """
        Convert a trading signal to an order request.
        
        Args:
            signal: Trading signal from agent
            equity: Current account equity
            risk_multiplier: Portfolio governor risk multiplier
            tp_r: Take profit in R-multiples (0 = no TP)
            
        Returns:
            OrderRequest or None if conversion fails
        """
        if signal.type == SignalType.NONE:
            return None
        
        # Get symbol info
        symbol_info = self.mt5.get_symbol_info(signal.symbol)
        if not symbol_info:
            print(f"Failed to get symbol info for {signal.symbol}")
            return None
        
        # Calculate risk amount
        adjusted_risk = signal.risk_percent * risk_multiplier
        risk_amount = equity * (adjusted_risk / 100)
        
        # Calculate SL distance in points
        sl_distance = abs(signal.price - signal.stop_loss)
        
        # Calculate volume based on risk
        tick_value = symbol_info.get('tick_value', 10)
        tick_size = symbol_info.get('tick_size', 0.00001)
        
        if tick_size > 0 and tick_value > 0:
            points = sl_distance / tick_size
            volume = risk_amount / (points * tick_value)
        else:
            volume = 0.01  # Default minimum
        
        # Round to lot step
        lot_step = symbol_info.get('lot_step', 0.01)
        volume = max(symbol_info.get('min_lot', 0.01), 
                    min(symbol_info.get('max_lot', 100),
                        round(volume / lot_step) * lot_step))
        
        # Calculate TP
        if tp_r > 0:
            tp_distance = sl_distance * tp_r
            if signal.type == SignalType.BUY:
                take_profit = signal.price + tp_distance
            else:
                take_profit = signal.price - tp_distance
        else:
            take_profit = 0
        
        # Create order request
        order_type = OrderType.BUY if signal.type == SignalType.BUY else OrderType.SELL
        
        return OrderRequest(
            symbol=signal.symbol,
            order_type=order_type,
            volume=volume,
            entry_price=signal.price,
            stop_loss=signal.stop_loss,
            take_profit=take_profit,
            comment=f"{signal.label}|S{signal.confluence_score}",
            risk_amount=risk_amount,
        )
    
    def calculate_volume(
        self,
        symbol: str,
        risk_amount: float,
        sl_distance: float
    ) -> float:
        """
        Calculate position volume based on risk.
        
        Args:
            symbol: Symbol name
            risk_amount: Amount to risk in account currency
            sl_distance: Stop loss distance in price
            
        Returns:
            Position volume (lots)
        """
        symbol_info = self.mt5.get_symbol_info(symbol)
        if not symbol_info:
            return 0.01
        
        tick_value = symbol_info.get('tick_value', 10)
        tick_size = symbol_info.get('tick_size', 0.00001)
        
        if tick_size > 0 and tick_value > 0:
            points = sl_distance / tick_size
            if points > 0:
                volume = risk_amount / (points * tick_value)
            else:
                volume = 0.01
        else:
            volume = 0.01
        
        # Apply lot constraints
        lot_step = symbol_info.get('lot_step', 0.01)
        min_lot = symbol_info.get('min_lot', 0.01)
        max_lot = symbol_info.get('max_lot', 100)
        
        volume = max(min_lot, min(max_lot, round(volume / lot_step) * lot_step))
        
        return volume
    
    def execute_signal(
        self,
        signal: Signal,
        equity: float,
        risk_multiplier: float = 1.0,
        tp_r: float = 0,
        deviation: int = 10
    ) -> tuple:
        """
        Execute a trading signal through MT5.
        
        Args:
            signal: Trading signal
            equity: Current equity
            risk_multiplier: Risk multiplier from governor
            tp_r: Take profit in R-multiples
            deviation: Max price deviation
            
        Returns:
            (success, ticket, message)
        """
        # Convert to order
        order = self.signal_to_order(signal, equity, risk_multiplier, tp_r)
        if order is None:
            return False, 0, "Failed to create order"
        
        # Execute through MT5
        success, ticket, message = self.mt5.place_order(
            symbol=order.symbol,
            order_type=order.order_type,
            volume=order.volume,
            sl=order.stop_loss,
            tp=order.take_profit,
            comment=order.comment,
            deviation=deviation,
        )
        
        if success:
            print(f"✅ Order executed: {order.symbol} {order.order_type.name} {order.volume} lots")
        else:
            print(f"❌ Order failed: {message}")
        
        return success, ticket, message
