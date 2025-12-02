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
        self.trailing_distance_r = 1.5 # Default distance
        
        # Advanced TSL Settings
        self.tsl_mode = "FIXED" # FIXED, ATR, SWING
        self.tsl_activation_r = 0.0 # Profit R required to activate
        self.tsl_atr_period = 14
        self.tsl_atr_multiplier = 1.5
        self.timeframe = "H1" # Default timeframe for ATR
        
        self.partial_tp_on = False
        self.partial_tp_amount = 0.5 # 50%

        # Secure Profit Settings (Break Even Plus)
        self.secure_profit_trigger = 100 # Points (e.g. 10 pips)
        self.secure_profit_lock = 10 # Points to lock (e.g. 1 pip)
        
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
            # Fix type check to handle string 'BUY'/'SELL' from MT5Connector
            is_buy = trade_type == 'BUY' or trade_type == 0
            
            if is_buy: # Buy
                profit_pips = current_price - entry_price
                r_multiple = profit_pips / risk_pips
            else: # Sell
                profit_pips = entry_price - current_price
                r_multiple = profit_pips / risk_pips
                
            # 1. Secure Profit (Break Even Plus)
            # Calculate profit in points
            point = self.mt5_connector.get_symbol_point(symbol) or 0.00001
            profit_points = profit_pips / point
            
            if self.secure_profit_trigger > 0 and profit_points >= self.secure_profit_trigger:
                self._check_and_secure_profit(trade, profit_points, point)

            # 2. Break Even Logic (R-based)
            # If we are above Trigger R and SL is still at original risk level
            if r_multiple >= self.be_trigger_r:
                self._check_and_move_to_be(trade, r_multiple, risk_pips)

            # 3. Trailing Stop Loss
            if self.use_trailing_sl:
                self._check_and_trail_sl(trade, r_multiple, risk_pips)

            # 4. Partial Take Profit
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
        is_buy = trade_type == 'BUY' or trade_type == 0
        
        if is_buy: # Buy
            new_sl = entry_price + offset
            # Only move if current SL is below BE
            if sl < new_sl:
                self._modify_position(ticket, new_sl, trade['tp'])
        else: # Sell
            new_sl = entry_price - offset
            # Only move if current SL is above BE
            if sl > new_sl or sl == 0:
                self._modify_position(ticket, new_sl, trade['tp'])

    def _check_and_secure_profit(self, trade: Dict, profit_points: float, point: float):
        """
        Secure profit if threshold reached.
        Example: If profit > 100 points, move SL to Entry + 10 points
        """
        ticket = trade['ticket']
        entry_price = trade['price_open']
        sl = trade['sl']
        trade_type = trade['type']
        
        lock_amount = self.secure_profit_lock * point
        
        new_sl = 0.0
        is_buy = trade_type == 'BUY' or trade_type == 0
        
        if is_buy:
            new_sl = entry_price + lock_amount
            # Only move if new SL is better than current SL
            if new_sl > sl:
                logger.info(f"Securing profit for {ticket}: Profit {profit_points} pts > {self.secure_profit_trigger}. Moving SL to {new_sl}")
                self._modify_position(ticket, new_sl, trade['tp'])
        else:
            new_sl = entry_price - lock_amount
            # Only move if new SL is better than current SL (lower for sell)
            if sl == 0 or new_sl < sl:
                logger.info(f"Securing profit for {ticket}: Profit {profit_points} pts > {self.secure_profit_trigger}. Moving SL to {new_sl}")
                self._modify_position(ticket, new_sl, trade['tp'])

    def manual_trail_sl(self, ticket: int, distance_r: float = 1.5) -> bool:
        """
        Manually trail SL for a specific trade
        """
        if not self.mt5_connector.connected:
            return False

        # Use get_position instead of iterating all positions
        trade = self.mt5_connector.get_position(ticket)
        
        if not trade:
            logger.error(f"Trade {ticket} not found for manual TSL")
            return False

        db = SessionLocal()
        try:
            db_trade = db.query(Trade).filter(Trade.ticket == ticket).first()
            if not db_trade:
                logger.error(f"Trade {ticket} not found in DB")
                return False
                
            entry_price = db_trade.entry_price
            initial_sl = db_trade.stop_loss
            
            if not initial_sl:
                 logger.error(f"Trade {ticket} has no initial SL, cannot calc R")
                 return False
                 
            risk_pips = abs(entry_price - initial_sl)
            
            # Calculate new SL
            current_price = trade['price_current']
            trade_type = trade['type']
            
            trail_distance = risk_pips * distance_r
            
            new_sl = 0.0
            is_buy = trade_type == 'BUY' or trade_type == 0
            
            if is_buy:
                new_sl = current_price - trail_distance
                if new_sl > trade['sl']:
                    return self.mt5_connector.modify_position(ticket, new_sl, trade['tp'])
            else:
                new_sl = current_price + trail_distance
                if new_sl < trade['sl'] or trade['sl'] == 0:
                    return self.mt5_connector.modify_position(ticket, new_sl, trade['tp'])
                    
            return False
            
        except Exception as e:
            logger.error(f"Error in manual TSL for {ticket}: {e}")
            return False
        finally:
            db.close()

    def _calculate_atr(self, symbol: str) -> float:
        """Calculate ATR for the symbol"""
        try:
            # Get sufficient bars for ATR calculation
            bars_needed = self.tsl_atr_period + 10
            df = self.mt5_connector.get_ohlcv_data(symbol, self.timeframe, bars_needed)
            
            if df is None or len(df) < bars_needed:
                logger.warning(f"Not enough data for ATR calculation on {symbol}")
                return 0.0
                
            # Calculate TR
            df['h-l'] = df['high'] - df['low']
            df['h-pc'] = abs(df['high'] - df['close'].shift(1))
            df['l-pc'] = abs(df['low'] - df['close'].shift(1))
            df['tr'] = df[['h-l', 'h-pc', 'l-pc']].max(axis=1)
            
            # Calculate ATR
            atr = df['tr'].rolling(window=self.tsl_atr_period).mean().iloc[-1]
            return atr
            
        except Exception as e:
            logger.error(f"Error calculating ATR: {e}")
            return 0.0

    def _check_and_trail_sl(self, trade: Dict, r_multiple: float, risk_pips: float):
        """
        Check and update Trailing Stop Loss (Trigger + Step Logic)
        """
        ticket = trade['ticket']
        sl = trade['sl']
        trade_type = trade['type']
        current_price = trade['price_current']
        symbol = trade['symbol']
        entry_price = trade['price_open']
        
        # 1. Check Activation (Trigger)
        # If we haven't activated yet, we check if we reached the trigger
        # We can infer if we activated if SL is better than initial SL? 
        # Or just strictly follow the rules:
        
        # Rule: Activate trailing when profit >= Activation R (e.g. 150 pips)
        if r_multiple < self.tsl_activation_r:
            return

        # 2. Calculate Target SL
        # Logic: If Profit >= Trigger, Move SL to (Current Price - Distance)
        # OR Logic: If Profit >= Trigger, Move SL to Fixed Step (e.g. +100 pips)
        
        # The user requested: "Trigger + Step Trailing Stop"
        # Example: Trigger +150 -> Move SL to +100.
        # Then as price moves, keep SL at distance? Or move in steps?
        # User said: "Luego el SL sigue moviéndose cada vez que el precio avanza más."
        # "Este tipo de trailing mantiene siempre aprox. 50 pips de distancia"
        
        # So effectively:
        # Distance = Trigger - Step (e.g. 150 - 100 = 50 pips distance)
        # Once triggered, we maintain this distance.
        
        # Let's calculate the implied distance from config if possible, or use trailing_distance_r
        # If user sets Trigger=1.5R and Step=1.0R (move to +1R), the distance is 0.5R.
        
        # However, we have self.trailing_distance_r in config.
        # Let's use that as the "Distance to maintain" after trigger.
        
        trail_distance = 0.0
        
        if self.tsl_mode == "ATR":
            atr = self._calculate_atr(symbol)
            if atr > 0:
                trail_distance = atr * self.tsl_atr_multiplier
            else:
                trail_distance = risk_pips * self.trailing_distance_r
        else:
            # FIXED Mode
            # If we want to strictly follow "Trigger 150 -> SL 100", the distance is 50.
            # We should probably use trailing_distance_r as the "distance behind price".
            trail_distance = risk_pips * self.trailing_distance_r
        
        new_sl = 0.0
        is_buy = trade_type == 'BUY' or trade_type == 0
        
        if is_buy: # Buy
            # Target SL = Current Price - Distance
            potential_new_sl = current_price - trail_distance
            
            # Ensure we lock in at least the "Step" profit if we just triggered
            # (This is implicitly handled if CurrentPrice - Distance >= Entry + Step)
            
            # Only move SL up
            if potential_new_sl > sl:
                # Optional: Check if change is significant enough (to avoid spamming modify calls)
                # e.g. only move if > 1 pip difference
                point = self.mt5_connector.get_symbol_point(symbol)
                if (potential_new_sl - sl) > (point * 10): # 1 pip
                    self._modify_position(ticket, potential_new_sl, trade['tp'])
                    
        else: # Sell
            potential_new_sl = current_price + trail_distance
            
            # Only move SL down
            if sl == 0 or potential_new_sl < sl:
                point = self.mt5_connector.get_symbol_point(symbol)
                if sl == 0 or (sl - potential_new_sl) > (point * 10):
                    self._modify_position(ticket, potential_new_sl, trade['tp'])

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

