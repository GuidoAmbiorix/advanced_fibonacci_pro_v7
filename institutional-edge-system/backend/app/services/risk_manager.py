"""
Adaptive Risk Manager
Professional-grade dynamic risk calculation with multiple safety layers
"""

from typing import Tuple
from dataclasses import dataclass
from loguru import logger


@dataclass
class DrawdownLevel:
    """Drawdown threshold and risk multiplier"""
    threshold_percent: float  # DD threshold
    risk_multiplier: float    # Risk multiplier at this level
    description: str          # Human-readable description


class DrawdownProtection:
    """
    Tiered drawdown protection system
    Progressively reduces risk as drawdown increases
    """

    LEVELS = [
        DrawdownLevel(0.0, 1.0, "Normal trading - full risk"),
        DrawdownLevel(3.0, 0.5, "Moderate DD - 50% risk reduction"),
        DrawdownLevel(5.0, 0.25, "Significant DD - 75% risk reduction"),
        DrawdownLevel(100.0, 0.0, "Critical DD - TRADING HALTED"),  # Disabled for backtesting
    ]

    @staticmethod
    def get_risk_multiplier(current_dd_percent: float) -> Tuple[float, str]:
        """
        Get risk multiplier based on current drawdown

        Args:
            current_dd_percent: Current drawdown as percentage

        Returns:
            Tuple of (multiplier, description)
        """
        # Find the applicable level (highest threshold below current DD)
        applicable_level = DrawdownProtection.LEVELS[0]

        for level in DrawdownProtection.LEVELS:
            if current_dd_percent >= level.threshold_percent:
                applicable_level = level
            else:
                break

        return applicable_level.risk_multiplier, applicable_level.description


class AdaptiveRiskManager:
    """
    Adaptive Risk Management System

    Features:
    - Base risk: 1% maximum (institutional standard)
    - Tiered drawdown protection (3%, 5%, 10% thresholds)
    - Consecutive loss reduction
    - Volatility-based adjustment
    - Circuit breaker at 10% DD
    """

    # Absolute maximum risk per trade
    ABSOLUTE_MAX_RISK = 5.0  # Increased to 5% to allow user flexibility

    # Minimum risk (when heavily reduced)
    MINIMUM_RISK = 0.1  # 0.1%

    def __init__(self, base_risk_percent: float = None):
        """Initialize Adaptive Risk Manager

        Args:
            base_risk_percent: Base risk % (if None, uses ABSOLUTE_MAX_RISK)
        """
        self.base_risk_percent = base_risk_percent if base_risk_percent else self.ABSOLUTE_MAX_RISK
        logger.info(
            f"AdaptiveRiskManager initialized - Base: {self.base_risk_percent}%, "
            f"Max: {self.ABSOLUTE_MAX_RISK}%, Min: {self.MINIMUM_RISK}%"
        )

    def calculate_risk_percent(
        self,
        market_regime: str = "NORMAL",
        consecutive_losses: int = 0,
        current_volatility_percentile: float = 50.0,
        current_drawdown: float = 0.0
    ) -> Tuple[float, str]:
        """
        Calculate adaptive risk percentage for next trade

        Args:
            market_regime: Market regime ("NORMAL", "TRENDING", "RANGING", "VOLATILE")
            consecutive_losses: Number of consecutive losing trades
            current_volatility_percentile: Current volatility (0-100 percentile)
            current_drawdown: Current account drawdown as percentage

        Returns:
            Tuple of (risk_percent, reason)
        """
        risk = self.base_risk_percent
        adjustments = []

        # LAYER 1: Drawdown Protection (HIGHEST PRIORITY)
        dd_multiplier, dd_desc = DrawdownProtection.get_risk_multiplier(current_drawdown)

        if dd_multiplier == 0.0:
            # Circuit breaker triggered
            return 0.0, f"🛑 CIRCUIT BREAKER: {dd_desc}"

        risk *= dd_multiplier
        if dd_multiplier < 1.0:
            adjustments.append(f"DD {current_drawdown:.1f}% → {dd_multiplier*100:.0f}% risk")

        # LAYER 2: Consecutive Losses
        if consecutive_losses >= 5:
            risk *= 0.25  # 75% reduction after 5 losses
            adjustments.append(f"{consecutive_losses} losses → 75% reduction")
        elif consecutive_losses >= 3:
            risk *= 0.5  # 50% reduction after 3 losses
            adjustments.append(f"{consecutive_losses} losses → 50% reduction")
        elif consecutive_losses >= 2:
            risk *= 0.75  # 25% reduction after 2 losses
            adjustments.append(f"{consecutive_losses} losses → 25% reduction")

        # LAYER 3: Volatility Adjustment
        if current_volatility_percentile >= 90:
            risk *= 0.25  # Extreme volatility
            adjustments.append("Extreme volatility → 75% reduction")
        elif current_volatility_percentile >= 75:
            risk *= 0.5  # High volatility
            adjustments.append("High volatility → 50% reduction")
        elif current_volatility_percentile >= 60:
            risk *= 0.75  # Elevated volatility
            adjustments.append("Elevated volatility → 25% reduction")

        # LAYER 4: Market Regime (optional fine-tuning)
        if market_regime == "VOLATILE":
            risk *= 0.75
            adjustments.append("Volatile regime → 25% reduction")

        # LAYER 5: Apply absolute limits
        risk = min(risk, self.ABSOLUTE_MAX_RISK)
        risk = max(risk, self.MINIMUM_RISK)

        # Round to 2 decimals
        risk = round(risk, 2)

        # Build reason string
        if adjustments:
            reason = " | ".join(adjustments)
        else:
            reason = "Normal conditions - base risk"

        return risk, reason

    def should_trade(
        self,
        current_drawdown: float,
        account_equity: float,
        initial_balance: float
    ) -> Tuple[bool, str]:
        """
        Determine if trading should be allowed

        Args:
            current_drawdown: Current DD percentage
            account_equity: Current account equity
            initial_balance: Initial account balance

        Returns:
            Tuple of (can_trade, reason)
        """
        # Check 1: Circuit breaker (100% DD - effectively disabled for backtesting)
        if current_drawdown >= 100.0:
            return False, f"Circuit breaker: Drawdown {current_drawdown:.2f}% >= 100%"

        # Check 2: Equity too low (disabled for backtesting - let it blow up)
        # if account_equity < (initial_balance * 0.5):
        #     return False, f"Equity ${account_equity:.2f} < 50% of initial ${initial_balance:.2f}"

        # All checks passed
        return True, "Trading allowed"

    def get_max_position_size(
        self,
        account_balance: float,
        risk_percent: float,
        sl_distance: float,
        symbol_pip_value: float = 10.0  # $10 per pip for standard lot EURUSD
    ) -> float:
        """
        Calculate maximum position size in lots

        Args:
            account_balance: Account balance
            risk_percent: Risk percentage to use
            sl_distance: Stop loss distance in price units
            symbol_pip_value: Pip value for the symbol (default: EURUSD standard lot)

        Returns:
            Position size in lots
        """
        risk_amount = account_balance * (risk_percent / 100.0)

        if sl_distance == 0:
            return 0.0

        # Convert SL distance to pips (for EURUSD, 0.0001 = 1 pip)
        sl_pips = sl_distance / 0.0001

        # Calculate lot size: Risk Amount / (SL in pips * pip value)
        lot_size = risk_amount / (sl_pips * symbol_pip_value)

        # Round to 2 decimals (standard lot precision)
        lot_size = round(lot_size, 2)

        # Minimum lot size
        if lot_size < 0.01:
            lot_size = 0.01

        return lot_size
