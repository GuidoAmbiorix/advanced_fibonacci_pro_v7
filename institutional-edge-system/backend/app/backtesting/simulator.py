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
        commission_per_lot: float = 7.0
    ):
        """
        Initialize simulator

        Args:
            slippage_pips: Slippage in pips (default 1 pip)
            commission_per_lot: Commission per lot roundtrip (default $7)
        """
        self.slippage_pips = slippage_pips
        self.commission_per_lot = commission_per_lot

        logger.info(
            f"OrderSimulator initialized - "
            f"Slippage: {slippage_pips} pips, "
            f"Commission: ${commission_per_lot}/lot"
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
            take_profit = signal['take_profit_1']  # Use first TP
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

            # Round to 0.01 (standard lot precision)
            volume = round(volume, 2)

            # Minimum 0.01 lot
            if volume < 0.01:
                volume = 0.01

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

        # Check if SL or TP hit
        bar_high = current_bar['high']
        bar_low = current_bar['low']

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
