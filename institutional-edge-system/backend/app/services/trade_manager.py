"""
============================================================================
Trade Manager
============================================================================
Manages open positions: Break Even, Trailing SL, Partial Close
"""

from typing import Dict, Optional, List
import pandas as pd
from loguru import logger
from app.core.mt5_connector import MT5Connector
from app.core.adaptive_multi_strategy_engine import (
    DynamicTrailingStopManager, 
    TrailingStopConfig, 
    TrailingStopMode
)
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
        self.tsl_mode = "FIXED" # FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
        self.tsl_activation_r = 0.0 # Profit R required to activate
        self.tsl_atr_period = 14
        self.tsl_atr_multiplier = 1.5
        self.timeframe = "H1" # Default timeframe for ATR
        
        # Chandelier Exit settings
        self.tsl_chandelier_period = 22
        self.tsl_chandelier_mult = 3.0
        
        # Swing-based settings
        self.tsl_swing_lookback = 10
        self.tsl_swing_buffer_atr = 0.5
        
        # Parabolic SAR settings
        self.tsl_psar_af_start = 0.02
        self.tsl_psar_af_increment = 0.02
        self.tsl_psar_af_max = 0.20
        
        self.partial_tp_on = False
        self.partial_tp_amount = 0.5 # 50%

        # Secure Profit Settings (Break Even Plus)
        self.secure_profit_trigger = 100 # Points (e.g. 10 pips)
        self.secure_profit_lock = 10 # Points to lock (e.g. 1 pip)
        
        # Initialize Dynamic Trailing Stop Manager
        self._init_tsl_manager()
        
    def _init_tsl_manager(self):
        """Initialize the Dynamic Trailing Stop Manager with current config"""
        try:
            mode_map = {
                "FIXED": TrailingStopMode.FIXED,
                "ATR": TrailingStopMode.ATR,
                "CHANDELIER": TrailingStopMode.CHANDELIER,
                "TIERED": TrailingStopMode.TIERED,
                "SWING": TrailingStopMode.SWING,
                "PSAR": TrailingStopMode.PSAR,
            }
            tsl_mode = mode_map.get(self.tsl_mode.upper(), TrailingStopMode.FIXED)
            
            config = TrailingStopConfig(
                mode=tsl_mode,
                activation_r=self.tsl_activation_r,
                atr_period=self.tsl_atr_period,
                atr_multiplier=self.tsl_atr_multiplier,
                chandelier_period=self.tsl_chandelier_period,
                chandelier_atr_mult=self.tsl_chandelier_mult,
                swing_lookback=self.tsl_swing_lookback,
                swing_buffer_atr=self.tsl_swing_buffer_atr,
                psar_af_start=self.tsl_psar_af_start,
                psar_af_increment=self.tsl_psar_af_increment,
                psar_af_max=self.tsl_psar_af_max,
            )
            self.tsl_manager = DynamicTrailingStopManager(config)
            logger.info(f"TSL Manager initialized with mode: {tsl_mode.value}")
        except Exception as e:
            logger.error(f"Error initializing TSL Manager: {e}")
            self.tsl_manager = DynamicTrailingStopManager()
        
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

            # 5. DYNAMIC TP EXTENSION (Smart Runner)
            # If enabled (via ATR mode) and price is near TP, extend it!
            if self.tsl_mode == "ATR":
                 self._check_tp_extension(trade, risk_pips)
                
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
        Check and update Trailing Stop Loss using DynamicTrailingStopManager
        
        Supports modes: FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
        """
        ticket = trade['ticket']
        sl = trade['sl']
        trade_type = trade['type']
        current_price = trade['price_current']
        symbol = trade['symbol']
        entry_price = trade['price_open']
        
        # Determine direction
        is_buy = trade_type == 'BUY' or trade_type == 0
        direction = "BUY" if is_buy else "SELL"
        
        # Get OHLCV data for advanced trailing modes
        df = self._get_ohlcv_with_atr(symbol)
        if df is None:
            # Fallback to simple fixed trailing if no data
            return self._fallback_fixed_trail(trade, r_multiple, risk_pips)
        
        # Get initial SL from database for accurate R calculation
        initial_sl = self._get_initial_sl(ticket, entry_price, sl, direction)
        
        # Calculate new SL using the advanced manager
        new_sl = self.tsl_manager.calculate_new_stop_loss(
            df=df,
            entry_price=entry_price,
            current_price=current_price,
            current_sl=sl,
            direction=direction,
            initial_sl=initial_sl
        )
        
        if new_sl is not None:
            # Check minimum pip difference to avoid spam
            point = self.mt5_connector.get_symbol_point(symbol) or 0.00001
            min_diff = point * 10  # 1 pip minimum change
            
            if is_buy:
                if (new_sl - sl) > min_diff:
                    logger.info(f"📈 TSL [{self.tsl_mode}] BUY: Moving SL {sl:.5f} → {new_sl:.5f}")
                    self._modify_position(ticket, new_sl, trade['tp'])
            else:
                if sl == 0 or (sl - new_sl) > min_diff:
                    logger.info(f"📉 TSL [{self.tsl_mode}] SELL: Moving SL {sl:.5f} → {new_sl:.5f}")
                    self._modify_position(ticket, new_sl, trade['tp'])
    
    def _get_ohlcv_with_atr(self, symbol: str):
        """Get OHLCV data with ATR calculated for TSL manager"""
        try:
            # Get enough bars for Chandelier (22), ATR (14), and swing (10) calculations
            bars_needed = max(self.tsl_chandelier_period, self.tsl_atr_period, self.tsl_swing_lookback) + 20
            df = self.mt5_connector.get_ohlcv_data(symbol, self.timeframe, bars_needed)
            
            if df is None or len(df) < 20:
                return None
                
            # Calculate ATR if not present
            if 'atr' not in df.columns:
                df['tr'] = pd.DataFrame({
                    'h-l': df['high'] - df['low'],
                    'h-pc': abs(df['high'] - df['close'].shift(1)),
                    'l-pc': abs(df['low'] - df['close'].shift(1))
                }).max(axis=1)
                df['atr'] = df['tr'].rolling(window=self.tsl_atr_period).mean()
                
            return df
            
        except Exception as e:
            logger.error(f"Error getting OHLCV data for TSL: {e}")
            return None
    
    def _get_initial_sl(self, ticket: int, entry_price: float, current_sl: float, direction: str) -> float:
        """Get initial stop loss from database for R calculations"""
        try:
            db = SessionLocal()
            db_trade = db.query(Trade).filter(Trade.ticket == ticket).first()
            db.close()
            
            if db_trade and db_trade.stop_loss:
                return db_trade.stop_loss
        except Exception as e:
            logger.debug(f"Could not get initial SL from DB: {e}")
            
        return current_sl
    
    def _fallback_fixed_trail(self, trade: Dict, r_multiple: float, risk_pips: float):
        """Fallback to simple fixed trailing when OHLCV data unavailable"""
        if r_multiple < self.tsl_activation_r:
            return
            
        ticket = trade['ticket']
        sl = trade['sl']
        trade_type = trade['type']
        current_price = trade['price_current']
        symbol = trade['symbol']
        
        trail_distance = risk_pips * self.trailing_distance_r
        is_buy = trade_type == 'BUY' or trade_type == 0
        
        if is_buy:
            new_sl = current_price - trail_distance
            if new_sl > sl:
                point = self.mt5_connector.get_symbol_point(symbol)
                if (new_sl - sl) > (point * 10):
                    self._modify_position(ticket, new_sl, trade['tp'])
        else:
            new_sl = current_price + trail_distance
            if sl == 0 or new_sl < sl:
                point = self.mt5_connector.get_symbol_point(symbol)
                if sl == 0 or (sl - new_sl) > (point * 10):
                    self._modify_position(ticket, new_sl, trade['tp'])

    def _check_and_partial_close(self, trade: Dict, r_multiple: float):
        """Check and execute Partial Take Profit"""
        # Trigger at 1.0R (Aligned with Backtest)
        if r_multiple < 1.0:
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

    def _check_tp_extension(self, trade: Dict, risk_pips: float):
        """
        Check if we should extend TP (Smart Runner Mode)
        
        Logic:
        - If price is within 10% of TP distance
        - Extend TP by 1R
        - Tighten SL to lock gains
        """
        try:
            ticket = trade['ticket']
            current_price = trade['price_current']
            entry_price = trade['price_open']
            tp = trade['tp']
            sl = trade['sl']
            trade_type = trade['type']
            
            if tp == 0: return
            
            is_buy = trade_type == 'BUY' or trade_type == 0
            
            # Calculate distance to TP
            if is_buy:
                dist_to_tp = tp - current_price
                full_tp_dist = tp - entry_price
            else:
                dist_to_tp = current_price - tp
                full_tp_dist = entry_price - tp
                
            if full_tp_dist <= 0: return # Should not happen
            
            pct_remaining = dist_to_tp / full_tp_dist
            
            # If we are within 10% of TP (90% of move done)
            if 0 < pct_remaining < 0.10:
                logger.info(f"🚀 Trade {ticket} approaching TP! (90% done). Activating Smart Runner extension.")
                
                point = self.mt5_connector.get_symbol_point(trade['symbol']) or 0.00001
                risk_amt = risk_pips * point if hasattr(self, 'risk_pips') else abs(entry_price - sl) # Approximate risk amount price diff
                
                # Extend TP by 1.0R (Risk Amount)
                # But risk_pips is in PIPS, need PRICE
                # Let's use the risk price distance we calculated: risk_pips * point
                # Wait, risk_pips passed in is actually PRICE DIFFERENCE (see line 128: abs(entry-sl))
                # So risk_pips IS the price difference.
                risk_price_dist = risk_pips 
                
                new_tp = 0.0
                if is_buy:
                    new_tp = tp + risk_price_dist
                    # Tighten SL to previous TP - buffer? Or just force TSL update.
                    # Standard TSL logic will catch up SL.
                else:
                    new_tp = tp - risk_price_dist
                    
                logger.info(f"🚀 Extending TP from {tp} to {new_tp} to catching more trend.")
                self._modify_position(ticket, sl, new_tp)
                
        except Exception as e:
            logger.error(f"Error in TP extension for {trade.get('ticket')}: {e}")


