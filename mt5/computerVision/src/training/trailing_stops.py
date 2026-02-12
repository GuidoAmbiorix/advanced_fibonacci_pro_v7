"""
Adaptive Trailing Stop Loss and Take Profit System

Implements ATR-based trailing stops that adapt to:
1. Market volatility (ATR)
2. Model confidence (ML probabilities)
3. Time in trade (tighten as trade ages)
"""

import numpy as np
import pandas as pd
from typing import Tuple, Optional
import talib


class AdaptiveTrailingStops:
    """
    Implements sophisticated trailing stop logic for ML trading systems.

    Key Features:
    - ATR-based trailing distance (adapts to volatility)
    - ML confidence-based adjustment (tighter for high confidence)
    - Time-based tightening (protect profits near prediction horizon)
    - Separate trailing SL and trailing TP
    """

    def __init__(
        self,
        atr_multiplier_sl: float = 3.0,
        atr_multiplier_tp: float = 6.0,
        confidence_adjustment: bool = True,
        time_based_tightening: bool = True,
        prediction_horizon: int = 24
    ):
        """
        Args:
            atr_multiplier_sl: Base ATR multiplier for stop loss trail
            atr_multiplier_tp: Base ATR multiplier for take profit trail
            confidence_adjustment: Adjust trail based on ML confidence
            time_based_tightening: Tighten trail as trade ages
            prediction_horizon: Bars until prediction expires
        """
        self.atr_mult_sl = atr_multiplier_sl
        self.atr_mult_tp = atr_multiplier_tp
        self.use_confidence = confidence_adjustment
        self.use_time_tightening = time_based_tightening
        self.horizon = prediction_horizon

    def calculate_trailing_stops(
        self,
        prices: pd.Series,
        entries: pd.Series,
        atr: pd.Series,
        probabilities: Optional[np.ndarray] = None
    ) -> Tuple[pd.Series, pd.Series]:
        """
        Calculate adaptive trailing stop and take profit levels.

        Args:
            prices: Close prices
            entries: Entry signals (boolean)
            atr: Average True Range series
            probabilities: ML confidence scores (optional)

        Returns:
            Tuple of (trailing_sl_exits, trailing_tp_exits)
        """
        n = len(prices)

        # Initialize output arrays
        sl_exits = np.zeros(n, dtype=bool)
        tp_exits = np.zeros(n, dtype=bool)

        # Track position state
        in_position = False
        entry_bar = 0
        entry_price = 0.0
        highest_price = 0.0
        trailing_sl_level = 0.0
        trailing_tp_level = 0.0

        for i in range(n):
            # Entry logic
            if entries.iloc[i] and not in_position:
                in_position = True
                entry_bar = i
                entry_price = prices.iloc[i]
                highest_price = entry_price

                # Initial SL: entry - (ATR * multiplier)
                initial_sl_distance = atr.iloc[i] * self.atr_mult_sl
                trailing_sl_level = entry_price - initial_sl_distance

                # Initial TP: entry + (ATR * multiplier)
                initial_tp_distance = atr.iloc[i] * self.atr_mult_tp
                trailing_tp_level = entry_price + initial_tp_distance

                continue

            # Position management
            if in_position:
                current_price = prices.iloc[i]
                bars_in_trade = i - entry_bar

                # Update highest price
                if current_price > highest_price:
                    highest_price = current_price

                # Calculate adaptive ATR multipliers
                sl_mult = self._get_adaptive_multiplier(
                    base_mult=self.atr_mult_sl,
                    bars_in_trade=bars_in_trade,
                    entry_prob=probabilities[entry_bar] if probabilities is not None else 0.5,
                    is_stop_loss=True
                )

                tp_mult = self._get_adaptive_multiplier(
                    base_mult=self.atr_mult_tp,
                    bars_in_trade=bars_in_trade,
                    entry_prob=probabilities[entry_bar] if probabilities is not None else 0.5,
                    is_stop_loss=False
                )

                # Calculate new trailing levels
                current_atr = atr.iloc[i]

                # Trailing SL: follows highest price
                new_sl = highest_price - (current_atr * sl_mult)
                trailing_sl_level = max(trailing_sl_level, new_sl)  # Can only go up

                # CRITICAL FIX: Remove trailing TP - it was buggy and conflicting with trailing SL
                # Strategy: Only use trailing SL + time-based exit
                # The trailing SL protects profits as price moves up
                # If price reaches the initial TP target, that's handled by the trailing SL being high enough

                # Keep TP as a FIXED maximum profit target (don't trail it)
                # This provides an upper bound but lets trailing SL do the work

                # Check if stops hit
                if current_price <= trailing_sl_level:
                    sl_exits[i] = True
                    in_position = False
                    continue

                if current_price >= trailing_tp_level:
                    # Hit the fixed TP target - take profit
                    tp_exits[i] = True
                    in_position = False
                    continue

                # Time-based exit: close at prediction horizon
                if bars_in_trade >= self.horizon:
                    # Exit at market (don't wait for stops)
                    sl_exits[i] = True  # Use SL exit array for time-based exits
                    in_position = False
                    continue

        return pd.Series(sl_exits, index=prices.index), pd.Series(tp_exits, index=prices.index)

    def _get_adaptive_multiplier(
        self,
        base_mult: float,
        bars_in_trade: int,
        entry_prob: float,
        is_stop_loss: bool
    ) -> float:
        """
        Calculate adaptive ATR multiplier based on confidence and time.

        Args:
            base_mult: Base multiplier
            bars_in_trade: Bars since entry
            entry_prob: ML confidence at entry
            is_stop_loss: Whether this is for SL (True) or TP (False)

        Returns:
            Adjusted multiplier
        """
        mult = base_mult

        # Confidence adjustment
        if self.use_confidence:
            # High confidence (>0.3) → tighter stops to lock profit
            # Low confidence (<0.2) → wider stops to allow development
            if entry_prob > 0.3:
                conf_factor = 0.8  # Tighten by 20%
            elif entry_prob < 0.2:
                conf_factor = 1.2  # Widen by 20%
            else:
                conf_factor = 1.0

            mult *= conf_factor

        # Time-based tightening (only for SL, not TP)
        if self.use_time_tightening and is_stop_loss:
            # First 6 bars: use full multiplier (let trade develop)
            # Bars 6-12: tighten to 85%
            # Bars 12-18: tighten to 70%
            # Bars 18+: tighten to 60% (protect profits near horizon)
            horizon_thirds = self.horizon / 3

            if bars_in_trade < horizon_thirds:
                time_factor = 1.0  # Full width
            elif bars_in_trade < 2 * horizon_thirds:
                time_factor = 0.85  # Tighten 15%
            elif bars_in_trade < self.horizon:
                time_factor = 0.70  # Tighten 30%
            else:
                time_factor = 0.60  # Tighten 40%

            mult *= time_factor

        return mult


def calculate_trailing_stop_exits(
    prices: pd.Series,
    entries: pd.Series,
    highs: pd.Series,
    lows: pd.Series,
    closes: pd.Series,
    atr_period: int = 14,
    sl_multiplier: float = 3.0,
    tp_multiplier: float = 6.0,
    probabilities: Optional[np.ndarray] = None,
    prediction_horizon: int = 24
) -> Tuple[pd.Series, pd.Series]:
    """
    Convenience function to calculate trailing stops with ATR.

    Args:
        prices: Close prices for backtest
        entries: Entry signals
        highs, lows, closes: OHLC data for ATR calculation
        atr_period: ATR lookback period
        sl_multiplier: ATR multiplier for stop loss trail
        tp_multiplier: ATR multiplier for take profit trail
        probabilities: ML confidence scores
        prediction_horizon: Bars until prediction expires

    Returns:
        Tuple of (sl_exits, tp_exits) boolean series
    """
    # Calculate ATR
    atr = talib.ATR(
        highs.values,
        lows.values,
        closes.values,
        timeperiod=atr_period
    )
    atr_series = pd.Series(atr, index=closes.index)

    # Create trailing stop calculator
    calculator = AdaptiveTrailingStops(
        atr_multiplier_sl=sl_multiplier,
        atr_multiplier_tp=tp_multiplier,
        confidence_adjustment=True,
        time_based_tightening=True,
        prediction_horizon=prediction_horizon
    )

    # Calculate exits
    sl_exits, tp_exits = calculator.calculate_trailing_stops(
        prices=prices,
        entries=entries,
        atr=atr_series,
        probabilities=probabilities
    )

    return sl_exits, tp_exits


if __name__ == '__main__':
    # Example usage
    print("Adaptive Trailing Stops Module")
    print("=" * 50)
    print("\nFeatures:")
    print("  - ATR-based adaptive distance")
    print("  - ML confidence adjustment")
    print("  - Time-based tightening")
    print("  - Separate SL and TP trailing")
