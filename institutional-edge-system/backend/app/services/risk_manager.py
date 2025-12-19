"""
Risk Manager
Simplified risk calculation - user controls risk directly
"""

from typing import Tuple
from loguru import logger


class AdaptiveRiskManager:
    """
    Simplified Risk Management System

    Features:
    - Uses configured base risk directly
    - Consecutive loss reduction (safety feature)
    - No automatic volatility or drawdown adjustments
    """

    # Absolute maximum risk per trade
    ABSOLUTE_MAX_RISK = 5.0  # 5% max

    # Minimum risk (when heavily reduced) - lowered for backtesting flexibility
    MINIMUM_RISK = 0.001  # 0.001%

    def __init__(self, base_risk_percent: float = None):
        """Initialize Risk Manager

        Args:
            base_risk_percent: Base risk % (if None, uses ABSOLUTE_MAX_RISK)
        """
        self.base_risk_percent = base_risk_percent if base_risk_percent else self.ABSOLUTE_MAX_RISK
        logger.info(
            f"RiskManager initialized - Base: {self.base_risk_percent}%, "
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
        Calculate risk percentage for next trade

        Args:
            market_regime: Market regime (unused, kept for API compatibility)
            consecutive_losses: Number of consecutive losing trades
            current_volatility_percentile: Unused (kept for API compatibility)
            current_drawdown: Unused (kept for API compatibility)

        Returns:
            Tuple of (risk_percent, reason)
        """
        risk = self.base_risk_percent
        adjustments = []

        # Only apply consecutive losses reduction (basic safety)
        if consecutive_losses >= 5:
            risk *= 0.25  # 75% reduction after 5 losses
            adjustments.append(f"{consecutive_losses} losses → 75% reduction")
        elif consecutive_losses >= 3:
            risk *= 0.5  # 50% reduction after 3 losses
            adjustments.append(f"{consecutive_losses} losses → 50% reduction")
        elif consecutive_losses >= 2:
            risk *= 0.75  # 25% reduction after 2 losses
            adjustments.append(f"{consecutive_losses} losses → 25% reduction")

        # Apply absolute limits
        risk = min(risk, self.ABSOLUTE_MAX_RISK)
        risk = max(risk, self.MINIMUM_RISK)

        # Round to 2 decimals
        risk = round(risk, 2)

        # Build reason string
        if adjustments:
            reason = " | ".join(adjustments)
        else:
            reason = "Base risk - no adjustments"

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
        symbol: str = "EURUSD"
    ) -> float:
        """
        Calculate maximum position size in lots using symbol-specific parameters.

        Args:
            account_balance: Account balance
            risk_percent: Risk percentage to use
            sl_distance: Stop loss distance in price units
            symbol: Trading symbol (determines pip size and value)

        Returns:
            Position size in lots
        """
        from app.core.instrument_config import get_instrument_profile
        
        profile = get_instrument_profile(symbol)
        pip_size = profile.pip_size
        pip_value = profile.pip_value_per_lot
        
        # Apply risk multiplier for high-volatility instruments
        adjusted_risk = risk_percent * profile.risk_multiplier
        risk_amount = account_balance * (adjusted_risk / 100.0)

        if sl_distance == 0:
            return 0.0

        # Convert SL distance to pips using symbol-specific pip size
        sl_pips = sl_distance / pip_size

        # Calculate lot size: Risk Amount / (SL in pips * pip value)
        lot_size = risk_amount / (sl_pips * pip_value)

        # Round to 2 decimals (standard lot precision)
        lot_size = round(lot_size, 2)

        # Minimum lot size
        if lot_size < 0.01:
            lot_size = 0.01

        return lot_size

    def get_adjusted_risk_for_symbol(
        self,
        base_risk: float,
        symbol: str
    ) -> float:
        """
        Get risk percentage adjusted for symbol volatility.
        
        Args:
            base_risk: Base risk percentage from config
            symbol: Trading symbol
            
        Returns:
            Adjusted risk percentage
        """
        from app.core.instrument_config import get_instrument_profile
        
        profile = get_instrument_profile(symbol)
        adjusted_risk = base_risk * profile.risk_multiplier
        
        # Round to 2 decimals
        return round(adjusted_risk, 2)

