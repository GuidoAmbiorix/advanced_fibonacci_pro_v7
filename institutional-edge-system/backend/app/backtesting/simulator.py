"""
Order Execution Simulator
Simulates realistic order fills with slippage and commission
"""

import pandas as pd
from datetime import datetime
from typing import Optional, Dict
from loguru import logger

from app.backtesting.models import BacktestTrade


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
        min_hold_hours: float = 4.0
    ):
        """
        Initialize simulator

        Args:
            slippage_pips: Slippage in pips (default 1 pip)
            commission_per_lot: Commission per lot roundtrip (default $7)
            enable_trailing_stop: Enable trailing stop loss (default False)
            min_hold_hours: Minimum hold time in hours (default 4.0)
        """
        self.slippage_pips = slippage_pips
        self.commission_per_lot = commission_per_lot
        self.enable_trailing_stop = enable_trailing_stop
        self.min_hold_hours = min_hold_hours

        logger.info(
            f"OrderSimulator initialized - "
            f"Slippage: {slippage_pips} pips, "
            f"Commission: ${commission_per_lot}/lot, "
            f"Trailing Stop: {enable_trailing_stop}, "
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

            # Apply slippage (worse fill price)
            slippage_amount = self.slippage_pips * 0.0001  # Convert pips to price
            if signal_type == "BUY":
                entry_price += slippage_amount  # Buy at higher price
            else:  # SELL
                entry_price -= slippage_amount  # Sell at lower price

            # Calculate position size
            sl_distance = abs(entry_price - stop_loss)
            if sl_distance == 0:
                logger.warning("SL distance is zero, cannot calculate position size")
                return None

            # Calculate lot size based on risk
            risk_amount = account_balance * (risk_percent / 100)
            volume = risk_amount / (100000 * sl_distance)  # Forex standard lot

            # Round to 0.001 (micro lot precision)
            volume = round(volume, 3)

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

    def _update_trailing_stop(self, trade: BacktestTrade, current_price: float) -> bool:
        """
        Update trailing stop based on current profit - OPTIMIZED FOR WIN RATE

        Trailing Logic (More Aggressive):
        - At 0.8R profit: Move SL to breakeven + 0.1R buffer
        - At 1.5R profit: Move SL to +0.8R (lock partial profit)
        - At 2R profit: Move SL to +1.2R (lock 1.2R profit)

        Args:
            trade: Open trade
            current_price: Current market price

        Returns:
            True if SL was moved, False otherwise
        """
        if not self.enable_trailing_stop:
            return False

        initial_risk = abs(trade.entry_price - trade.initial_stop_loss)
        if initial_risk == 0:
            return False

        # Calculate current profit in R
        if trade.signal_type == "BUY":
            profit_r = (current_price - trade.entry_price) / initial_risk

            # Move SL only if it's better than current
            new_sl = None
            if profit_r >= 2.0:
                # Lock +1.2R profit
                new_sl = trade.entry_price + (initial_risk * 1.2)
            elif profit_r >= 1.5:
                # Lock +0.8R profit
                new_sl = trade.entry_price + (initial_risk * 0.8)
            elif profit_r >= 0.8:
                # Move to breakeven with small buffer
                new_sl = trade.entry_price + (initial_risk * 0.1)

            # Only move SL up, never down
            if new_sl and new_sl > trade.stop_loss:
                old_sl = trade.stop_loss
                trade.stop_loss = new_sl
                logger.debug(f"Trailing SL updated: {old_sl:.5f} → {new_sl:.5f} (Profit: {profit_r:.2f}R)")
                return True

        else:  # SELL
            profit_r = (trade.entry_price - current_price) / initial_risk

            # Move SL only if it's better than current
            new_sl = None
            if profit_r >= 2.0:
                # Lock +1.2R profit
                new_sl = trade.entry_price - (initial_risk * 1.2)
            elif profit_r >= 1.5:
                # Lock +0.8R profit
                new_sl = trade.entry_price - (initial_risk * 0.8)
            elif profit_r >= 0.8:
                # Move to breakeven with small buffer
                new_sl = trade.entry_price - (initial_risk * 0.1)

            # Only move SL down (better for SELL), never up
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
                # Apply slippage (worse exit)
                exit_price -= self.slippage_pips * 0.0001

                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="SL"
                )
                logger.debug(f"BUY trade {trade.ticket} hit SL @ {exit_price:.5f}")
                return "CLOSED_SL"

            # Check TP
            if bar_high >= trade.take_profit:
                # TP hit
                exit_price = trade.take_profit
                # Apply slippage (worse exit)
                exit_price -= self.slippage_pips * 0.0001

                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="TP"
                )
                logger.debug(f"BUY trade {trade.ticket} hit TP @ {exit_price:.5f}, P&L: ${trade.pnl:.2f}")
                return "CLOSED_TP"

        else:  # SELL
            # Check SL first
            if bar_high >= trade.stop_loss:
                # SL hit
                exit_price = trade.stop_loss
                # Apply slippage (worse exit)
                exit_price += self.slippage_pips * 0.0001

                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="SL"
                )
                logger.debug(f"SELL trade {trade.ticket} hit SL @ {exit_price:.5f}")
                return "CLOSED_SL"

            # Check TP
            if bar_low <= trade.take_profit:
                # TP hit
                exit_price = trade.take_profit
                # Apply slippage (worse exit)
                exit_price += self.slippage_pips * 0.0001

                trade.close(
                    exit_time=current_bar['time'],
                    exit_price=exit_price,
                    exit_reason="TP"
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

        # Apply slippage
        if trade.signal_type == "BUY":
            exit_price -= self.slippage_pips * 0.0001
        else:
            exit_price += self.slippage_pips * 0.0001

        trade.close(
            exit_time=current_bar['time'],
            exit_price=exit_price,
            exit_reason=reason
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
