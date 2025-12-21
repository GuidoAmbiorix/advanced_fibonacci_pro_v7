"""
Order Execution Simulator
Simulates realistic order fills with slippage and commission
"""

import pandas as pd
from datetime import datetime
from typing import Optional, Dict
from loguru import logger
from app.backtesting.models import BacktestTrade
from app.core.instrument_config import get_instrument_profile
from app.core.adaptive_multi_strategy_engine import (
    DynamicTrailingStopManager,
    TrailingStopConfig,
    TrailingStopMode
)


class OrderSimulator:
    """
    Simulates realistic order execution

    Features:
    - Slippage modeling
    - Commission calculation
    - Realistic SL/TP execution (next bar)
    - Position sizing
    """

    def __init__(
        self,
        slippage_pips: float = 1.0,
        commission_per_lot: float = 7.0,
        enable_trailing_stop: bool = False,
        min_hold_hours: float = 4.0,
        tsl_mode: str = "TIERED",  # FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
        tsl_activation_r: float = 0.0,
        tsl_atr_multiplier: float = 1.5,
        tsl_chandelier_period: int = 22,
        tsl_chandelier_mult: float = 3.0,
        tsl_swing_lookback: int = 10,
        tsl_psar_af_start: float = 0.02,
        tsl_psar_af_max: float = 0.20,
        partial_tp_on: bool = False,
        partial_tp_amount: float = 0.5
    ):
        """
        Initialize simulator

        Args:
            slippage_pips: Slippage in pips (default 1 pip)
            commission_per_lot: Commission per lot roundtrip (default $7)
            enable_trailing_stop: Enable trailing stop loss (default False)
            min_hold_hours: Minimum hold time in hours (default 4.0)
            tsl_mode: Trailing stop mode - FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
            tsl_activation_r: R-profit required to activate trailing (0 = immediate)
            tsl_atr_multiplier: ATR multiplier for ATR mode
            tsl_chandelier_period: Lookback period for Chandelier Exit
            tsl_chandelier_mult: ATR multiplier for Chandelier Exit
            tsl_swing_lookback: Lookback bars for Swing-based trailing
            tsl_psar_af_start: Initial acceleration factor for Parabolic SAR
            tsl_psar_af_max: Maximum acceleration factor for Parabolic SAR
            partial_tp_on: Enable partial take profit
            partial_tp_amount: Amount to close (0.1 - 1.0)
        """
        self.slippage_pips = slippage_pips
        self.commission_per_lot = commission_per_lot
        self.enable_trailing_stop = enable_trailing_stop
        self.min_hold_hours = min_hold_hours
        self.tsl_mode = tsl_mode
        self.partial_tp_on = partial_tp_on
        self.partial_tp_amount = partial_tp_amount

        # Initialize Dynamic Trailing Stop Manager
        mode_map = {
            "FIXED": TrailingStopMode.FIXED,
            "ATR": TrailingStopMode.ATR,
            "CHANDELIER": TrailingStopMode.CHANDELIER,
            "TIERED": TrailingStopMode.TIERED,
            "SWING": TrailingStopMode.SWING,
            "PSAR": TrailingStopMode.PSAR,
        }
        
        config = TrailingStopConfig(
            mode=mode_map.get(tsl_mode.upper(), TrailingStopMode.TIERED),
            activation_r=tsl_activation_r,
            atr_multiplier=tsl_atr_multiplier,
            chandelier_period=tsl_chandelier_period,
            chandelier_atr_mult=tsl_chandelier_mult,
            swing_lookback=tsl_swing_lookback,
            psar_af_start=tsl_psar_af_start,
            psar_af_max=tsl_psar_af_max,
        )
        self.tsl_manager = DynamicTrailingStopManager(config)

        logger.info(
            f"OrderSimulator initialized - "
            f"Slippage: {slippage_pips} pips, "
            f"Commission: ${commission_per_lot}/lot, "
            f"Trailing Stop: {enable_trailing_stop} ({tsl_mode}), "
            f"Min Hold: {min_hold_hours}h"
        )

    def execute_entry(
        self,
        signal: Dict,
        current_bar: pd.Series,
        account_balance: float,
        risk_percent: float = 1.0
    ) -> Optional[BacktestTrade]:
        """
        Execute entry order based on signal

        Args:
            signal: Signal dict from trading engine
            current_bar: Current price bar
            account_balance: Current account balance
            risk_percent: Risk percentage for position sizing

        Returns:
            BacktestTrade object or None if couldn't execute
        """
        try:
            # Extract signal details
            symbol = signal.get('symbol', 'EURUSD')
            signal_type = signal['signal_type']  # "BUY" or "SELL"
            entry_price = signal['entry_price']
            stop_loss = signal['stop_loss']
            take_profit = signal['take_profit_1']  # Use first TP (1.5R target)
            confluence_score = signal.get('confluence_score', 0)

            # Get symbol-specific profile for pip size and lot sizing
            profile = get_instrument_profile(symbol)
            pip_size = profile.pip_size

            # Apply slippage (worse fill price)
            slippage_amount = self.slippage_pips * pip_size  # Use symbol-specific pip size
            if signal_type == "BUY":
                entry_price += slippage_amount  # Buy at higher price
            else:  # SELL
                entry_price -= slippage_amount  # Sell at lower price

            # Calculate position size
            sl_distance = abs(entry_price - stop_loss)
            
            # Enforce minimum SL distance for calculation (safety clamp)
            # Prevent massive volume on tiny ATRs (e.g. < 3 pips)
            min_sl_pips = 3.0
            min_sl_distance = min_sl_pips * pip_size
            
            calc_sl_distance = max(sl_distance, min_sl_distance)

            # Apply risk multiplier for high-volatility instruments (e.g., Gold)
            adjusted_risk = risk_percent * profile.risk_multiplier
            risk_amount = account_balance * (adjusted_risk / 100)
            
            # Calculate lot size using symbol-specific parameters
            # Formula: Risk$ / (SL_pips * pip_value_per_lot)
            sl_pips = calc_sl_distance / pip_size
            volume = risk_amount / (sl_pips * profile.pip_value_per_lot)

            # Round to 0.001 (micro lot precision)
            volume = round(volume, 3)
            
            # DEBUG JPY CALC
            if "JPY" in symbol:
                logger.info(f"JPY CALC: Risk%={risk_percent}, Risk$={risk_amount}, SL_dist={sl_distance}, Clamped_SL={calc_sl_distance}, SL_pips={sl_pips}, Vol={volume}")
                
            # Minimum 0.001 lot (micro lot)
            if volume < 0.001:
                volume = 0.001

            # Calculate commission
            commission = volume * self.commission_per_lot

            # Create trade
            trade = BacktestTrade(
                entry_time=current_bar['time'],
                entry_price=entry_price,
                signal_type=signal_type,
                volume=volume,
                stop_loss=stop_loss,
                take_profit=take_profit,
                symbol=symbol,
                confluence_score=confluence_score,
                commission=commission,
                slippage_pips=self.slippage_pips,
                risk_percent=risk_percent,  # Store the risk % used
                status="OPEN"
            )

            logger.debug(
                f"Opened {signal_type} {symbol} @ {entry_price:.5f}, "
                f"SL: {stop_loss:.5f}, TP: {take_profit:.5f}, "
                f"Volume: {volume} lots, Risk: {risk_percent}%"
            )

            return trade

        except Exception as e:
            logger.error(f"Error executing entry: {e}")
            return None

    def _update_trailing_stop(
        self, 
        trade: BacktestTrade, 
        current_price: float,
        df: pd.DataFrame = None
    ) -> bool:
        """
        Update trailing stop using DynamicTrailingStopManager
        
        Supports modes: FIXED, ATR, CHANDELIER, TIERED, SWING, PSAR
        
        Args:
            trade: Open trade
            current_price: Current market price
            df: Optional OHLCV DataFrame for advanced modes (Chandelier, Swing, PSAR)

        Returns:
            True if SL was moved, False otherwise
        """
        if not self.enable_trailing_stop:
            return False

        initial_risk = abs(trade.entry_price - trade.initial_stop_loss)
        if initial_risk == 0:
            return False
            
        direction = trade.signal_type  # "BUY" or "SELL"
        
        # If we have a DataFrame, use advanced trailing modes
        if df is not None and len(df) > 0:
            new_sl = self.tsl_manager.calculate_new_stop_loss(
                df=df,
                entry_price=trade.entry_price,
                current_price=current_price,
                current_sl=trade.stop_loss,
                direction=direction,
                initial_sl=trade.initial_stop_loss
            )
            
            if new_sl is not None:
                if direction == "BUY" and new_sl > trade.stop_loss:
                    old_sl = trade.stop_loss
                    trade.stop_loss = new_sl
                    logger.debug(f"TSL [{self.tsl_mode}] BUY: {old_sl:.5f} → {new_sl:.5f}")
                    return True
                elif direction == "SELL" and (trade.stop_loss == 0 or new_sl < trade.stop_loss):
                    old_sl = trade.stop_loss
                    trade.stop_loss = new_sl
                    logger.debug(f"TSL [{self.tsl_mode}] SELL: {old_sl:.5f} → {new_sl:.5f}")
                    return True
            return False
        
        # Fallback to legacy tiered trailing when no DataFrame available
        return self._legacy_tiered_trail(trade, current_price, initial_risk, direction)
    
    def _legacy_tiered_trail(
        self, 
        trade: BacktestTrade, 
        current_price: float,
        initial_risk: float,
        direction: str
    ) -> bool:
        """Legacy tiered trailing stop (used when no DataFrame available)"""
        if direction == "BUY":
            profit_r = (current_price - trade.entry_price) / initial_risk

            new_sl = None
            if profit_r >= 2.0:
                new_sl = trade.entry_price + (initial_risk * 1.2)
            elif profit_r >= 1.5:
                new_sl = trade.entry_price + (initial_risk * 0.5)
            elif profit_r >= 1.0:
                new_sl = trade.entry_price + (initial_risk * 0.1)

            if new_sl and new_sl > trade.stop_loss:
                old_sl = trade.stop_loss
                trade.stop_loss = new_sl
                logger.debug(f"Trailing SL updated: {old_sl:.5f} → {new_sl:.5f} (Profit: {profit_r:.2f}R)")
                return True

        else:  # SELL
            profit_r = (trade.entry_price - current_price) / initial_risk

            new_sl = None
            if profit_r >= 2.0:
                new_sl = trade.entry_price - (initial_risk * 1.2)
            elif profit_r >= 1.5:
                new_sl = trade.entry_price - (initial_risk * 0.8)
            elif profit_r >= 0.8:
                new_sl = trade.entry_price - (initial_risk * 0.1)

            if new_sl and new_sl < trade.stop_loss:
                old_sl = trade.stop_loss
                trade.stop_loss = new_sl
                logger.debug(f"Trailing SL updated: {old_sl:.5f} → {new_sl:.5f} (Profit: {profit_r:.2f}R)")
                return True

        return False

    def update_position(
        self,
        trade: BacktestTrade,
        current_bar: pd.Series
    ) -> str:
        """
        Update open position and check for SL/TP hit

        Args:
            trade: Open trade
            current_bar: Current price bar

        Returns:
            Status: "OPEN", "CLOSED_SL", "CLOSED_TP"
        """
        if trade.status != "OPEN":
            return trade.status

        # Calculate time in trade
        time_in_trade_hours = (current_bar['time'] - trade.entry_time).total_seconds() / 3600

        # Update trailing stop if enabled
        current_price = current_bar['close']
        self._update_trailing_stop(trade, current_price)

        # ============================================
        # PARTIAL TP (Configurable)
        # Close X% at +0.5R, move SL to BE, let runner continue
        # ============================================
        if self.partial_tp_on and not trade.partial_tp_taken:
            initial_risk = abs(trade.entry_price - trade.initial_stop_loss)
            if initial_risk > 0:
                if trade.signal_type == "BUY":
                    profit_r = (current_price - trade.entry_price) / initial_risk
                else:  # SELL
                    profit_r = (trade.entry_price - current_price) / initial_risk
                
                # If profit reaches 1.0R (Improved trigger to let trade develop), take partial!
                if profit_r >= 1.0:
                    # Store original volume for tracking
                    if trade.original_volume == 0:
                        trade.original_volume = trade.volume
                    
                    # Calculate partial PnL using correct instrument profile (fixes JPY scaling issue)
                    profile = get_instrument_profile(trade.symbol)
                    partial_pips = abs(current_price - trade.entry_price) / profile.pip_size
                    partial_pnl = partial_pips * profile.pip_value_per_lot * partial_volume
                    trade.partial_tp_pnl = partial_pnl
                    
                    # Reduce volume by partial amount (runner continues)
                    trade.volume = trade.volume * (1.0 - self.partial_tp_amount)
                    
                    # Move SL to breakeven (entry + small buffer for spread)
                    if trade.signal_type == "BUY":
                        new_sl = trade.entry_price + (initial_risk * 0.05)  # Entry + 5% buffer
                        if new_sl > trade.stop_loss:
                            trade.stop_loss = new_sl
                    else:  # SELL
                        new_sl = trade.entry_price - (initial_risk * 0.05)  # Entry - 5% buffer
                        if new_sl < trade.stop_loss:
                            trade.stop_loss = new_sl
                    
                    trade.partial_tp_taken = True
                    logger.info(f"🎯 PARTIAL TP @ +0.5R: Closed {self.partial_tp_amount*100:.0f}%, PnL=${partial_pnl:.2f}, SL→BE")

        # Check if SL or TP hit (but respect minimum hold time)
        bar_high = current_bar['high']
        bar_low = current_bar['low']

        # Skip SL check if below minimum hold time (let trade breathe)
        if time_in_trade_hours < self.min_hold_hours:
            # Still open - update floating P&L
            trade.update_open_pnl(current_price)
            return "OPEN"

        if trade.signal_type == "BUY":
            # Check SL first (more conservative)
            if bar_low <= trade.stop_loss:
                # SL hit
                exit_price = trade.stop_loss
                # Apply slippage (worse exit) using symbol-specific pip size
                profile = get_instrument_profile(trade.symbol)
                exit_price -= self.slippage_pips * profile.pip_size

                # Use symbol profile for PnL calc
                profile = get_instrument_profile(trade.symbol)
                
                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="SL",
                    pip_size=profile.pip_size,
                    pip_value=profile.pip_value_per_lot
                )
                logger.debug(f"BUY trade {trade.ticket} hit SL @ {exit_price:.5f}")
                return "CLOSED_SL"

            # Check TP
            if bar_high >= trade.take_profit:
                # TP hit
                exit_price = trade.take_profit
                # Apply slippage (worse exit) using symbol-specific pip size
                profile = get_instrument_profile(trade.symbol)
                exit_price -= self.slippage_pips * profile.pip_size

                # Use symbol profile for PnL calc
                profile = get_instrument_profile(trade.symbol)
                
                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="TP",
                    pip_size=profile.pip_size,
                    pip_value=profile.pip_value_per_lot
                )
                logger.debug(f"BUY trade {trade.ticket} hit TP @ {exit_price:.5f}, P&L: ${trade.pnl:.2f}")
                return "CLOSED_TP"

        else:  # SELL
            # Check SL first
            if bar_high >= trade.stop_loss:
                # SL hit
                exit_price = trade.stop_loss
                # Apply slippage (worse exit) using symbol-specific pip size
                profile = get_instrument_profile(trade.symbol)
                exit_price += self.slippage_pips * profile.pip_size

                # Use symbol profile for PnL calc
                profile = get_instrument_profile(trade.symbol)

                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="SL",
                    pip_size=profile.pip_size,
                    pip_value=profile.pip_value_per_lot
                )
                logger.debug(f"SELL trade {trade.ticket} hit SL @ {exit_price:.5f}")
                return "CLOSED_SL"

            # Check TP
            if bar_low <= trade.take_profit:
                # TP hit
                exit_price = trade.take_profit
                # Apply slippage (worse exit) using symbol-specific pip size
                profile = get_instrument_profile(trade.symbol)
                exit_price += self.slippage_pips * profile.pip_size

                # Use symbol profile for PnL calc
                profile = get_instrument_profile(trade.symbol)

                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="TP",
                    pip_size=profile.pip_size,
                    pip_value=profile.pip_value_per_lot
                )
                logger.debug(f"SELL trade {trade.ticket} hit TP @ {exit_price:.5f}, P&L: ${trade.pnl:.2f}")
                return "CLOSED_TP"

        # Still open - update floating P&L
        current_price = current_bar['close']
        trade.update_open_pnl(current_price)

        return "OPEN"

    def force_close(
        self,
        trade: BacktestTrade,
        current_bar: pd.Series,
        reason: str = "END_OF_DATA"
    ) -> None:
        """
        Force close a trade (e.g., at end of backtest)

        Args:
            trade: Trade to close
            current_bar: Current bar
            reason: Reason for closing
        """
        if trade.status != "OPEN":
            return

        exit_price = current_bar['close']

        # Apply slippage using symbol-specific pip size
        # Apply slippage using symbol-specific pip size
        profile = get_instrument_profile(trade.symbol)
        if trade.signal_type == "BUY":
            exit_price -= self.slippage_pips * profile.pip_size
        else:
            exit_price += self.slippage_pips * profile.pip_size

        trade.close(
            exit_time=current_bar['time'],
            exit_price=exit_price,
            exit_reason=reason,
            pip_size=profile.pip_size,
            pip_value=profile.pip_value_per_lot
        )

        logger.debug(f"Force closed trade {trade.ticket} @ {exit_price:.5f}, Reason: {reason}")

    def get_trade_stats(self, trade: BacktestTrade) -> Dict:
        """Get detailed stats for a trade"""
        if trade.status != "CLOSED":
            return {}

        duration = (trade.exit_time - trade.entry_time).total_seconds() / 3600  # hours

        return {
            'ticket': trade.ticket,
            'symbol': trade.symbol,
            'type': trade.signal_type,
            'entry_time': trade.entry_time,
            'exit_time': trade.exit_time,
            'duration_hours': duration,
            'entry_price': trade.entry_price,
            'exit_price': trade.exit_price,
            'exit_reason': trade.exit_reason,
            'pnl': trade.pnl,
            'pnl_pips': trade.pnl_pips,
            'return_r': trade.return_r,
            'volume': trade.volume,
            'confluence_score': trade.confluence_score,
            'commission': trade.commission,
            'slippage_pips': trade.slippage_pips,
        }
