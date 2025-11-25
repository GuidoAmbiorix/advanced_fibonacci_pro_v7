"""
============================================================================
Trade Manager
============================================================================
Manages open positions: Break Even, Trailing SL, Partial Close
"""

from typing import Dict, Optional, List
from loguru import logger
from app.core.mt5_connector import MT5Connector
from app.models.database import Trade
from app.api.database import SessionLocal

class TradeManager:
    """
    Manages active trades:
    - Moves Stop Loss to Break Even
    - Trails Stop Loss
    - Takes Partial Profits
    """

    def __init__(self, mt5_connector: MT5Connector):
        self.mt5_connector = mt5_connector
        
        # Default settings (can be overridden by config)
        self.be_trigger_r = 1.0  # Move to BE when price moves 1R (Risk unit)
        self.be_offset_pips = 2  # Pips to add to BE (to cover commissions)
        self.use_trailing_sl = False
        self.trailing_step_r = 1.0 # Trail every 1R
        self.partial_tp_on = False
        self.partial_tp_amount = 0.5 # 50%
        
    def update_trades(self, active_trades: List[Dict]):
        """
        Update all active trades
        
        Args:
            active_trades: List of trade dictionaries from MT5
        """
        if not active_trades:
            return

        for trade in active_trades:
            self._manage_trade(trade)

    def _manage_trade(self, trade: Dict):
        """Manage a single trade"""
        try:
            symbol = trade['symbol']
            ticket = trade['ticket']
            entry_price = trade['price_open']
            current_price = trade['price_current']
            sl = trade['sl']
            tp = trade['tp']
            trade_type = trade['type'] # 0=Buy, 1=Sell
            
            # Calculate R (Risk)
            if sl == 0:
                return # No SL, cannot calculate R
                
            risk_pips = abs(entry_price - sl)
            if risk_pips == 0:
                return
                
            # Calculate current profit in R
            if trade_type == 0: # Buy
                profit_pips = current_price - entry_price
                r_multiple = profit_pips / risk_pips
            else: # Sell
                profit_pips = entry_price - current_price
                r_multiple = profit_pips / risk_pips
                
            # 1. Break Even Logic
            # If we are above Trigger R and SL is still at original risk level
            if r_multiple >= self.be_trigger_r:
                self._check_and_move_to_be(trade, r_multiple, risk_pips)

            # 2. Trailing Stop Loss
            if self.use_trailing_sl:
                self._check_and_trail_sl(trade, r_multiple, risk_pips)

            # 3. Partial Take Profit
            if self.partial_tp_on:
                self._check_and_partial_close(trade, r_multiple)
                
        except Exception as e:
            logger.error(f"Error managing trade {trade.get('ticket')}: {e}")

    def _check_and_move_to_be(self, trade: Dict, r_multiple: float, risk_pips: float):
        """Check if we need to move SL to Break Even"""
        ticket = trade['ticket']
        entry_price = trade['price_open']
        sl = trade['sl']
        trade_type = trade['type']
        
        # Calculate BE price with offset
        point = self.mt5_connector.get_symbol_point(trade['symbol']) or 0.00001
        offset = self.be_offset_pips * point * 10 # Assuming point is 0.00001, pip is 0.0001
        
        new_sl = 0.0
        if trade_type == 0: # Buy
            new_sl = entry_price + offset
            # Only move if current SL is below BE
            if sl < new_sl:
                self._modify_position(ticket, new_sl, trade['tp'])
        else: # Sell
            new_sl = entry_price - offset
            # Only move if current SL is above BE
            if sl > new_sl or sl == 0:
                self._modify_position(ticket, new_sl, trade['tp'])

    def _check_and_trail_sl(self, trade: Dict, r_multiple: float, risk_pips: float):
        """Check and update Trailing Stop Loss"""
        ticket = trade['ticket']
        sl = trade['sl']
        trade_type = trade['type']
        current_price = trade['price_current']
        
        # Only trail if we are in profit by at least 1 step
        if r_multiple < self.trailing_step_r:
            return

        # Calculate new SL distance (e.g. 1.5R behind price)
        trail_distance = risk_pips * 1.5 
        
        new_sl = 0.0
        if trade_type == 0: # Buy
            new_sl = current_price - trail_distance
            # Only move SL up
            if new_sl > sl:
                self._modify_position(ticket, new_sl, trade['tp'])
        else: # Sell
            new_sl = current_price + trail_distance
            # Only move SL down
            if new_sl < sl or sl == 0:
                self._modify_position(ticket, new_sl, trade['tp'])

    def _check_and_partial_close(self, trade: Dict, r_multiple: float):
        """Check and execute Partial Take Profit"""
        # Trigger at 1.5R (or configurable)
        if r_multiple < 1.5:
            return

        ticket = trade['ticket']
        
        # Check DB state
        db = SessionLocal()
        try:
            db_trade = db.query(Trade).filter(Trade.ticket == ticket).first()
            if not db_trade:
                return
                
            if db_trade.is_partially_closed:
                return # Already closed partials
                
            # Execute Partial Close
            volume_to_close = trade['volume'] * self.partial_tp_amount
            # Round to 2 decimals or step
            volume_to_close = round(volume_to_close, 2)
            
            if volume_to_close < 0.01:
                return

            logger.info(f"Executing Partial Close for {ticket}: {volume_to_close} lots")
            
            # We need a partial close method in MT5Connector, but close_position closes all.
            # We need to implement partial close in MT5Connector or use close_position with volume.
            # Assuming close_position handles volume or we create a new method.
            # Let's use a new method `close_partial_position` in MT5Connector (need to add it)
            # OR modify close_position to accept volume.
            
            # For now, let's assume we added close_partial to MT5Connector
            if self.mt5_connector.close_partial_position(ticket, volume_to_close):
                db_trade.is_partially_closed = True
                db.commit()
                logger.info(f"✅ Partial close successful for {ticket}")
                
                # Move SL to BE immediately after partial
                self._check_and_move_to_be(trade, r_multiple, 0) # Force BE check
                
        except Exception as e:
            logger.error(f"Error in partial close for {ticket}: {e}")
        finally:
            db.close() 

    def _modify_position(self, ticket: int, sl: float, tp: float):
        """Modify trade position"""
        logger.info(f"Moving SL for trade {ticket} to {sl}")
        result = self.mt5_connector.modify_position(ticket, sl, tp)
        if result:
            logger.info(f"✅ SL moved for trade {ticket}")
        else:
            logger.error(f"❌ Failed to move SL for trade {ticket}")

