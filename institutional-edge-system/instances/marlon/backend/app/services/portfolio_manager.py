"""
Portfolio Manager
Manages multi-position risk and correlation
"""

from typing import List, Tuple, Dict
from dataclasses import dataclass
from loguru import logger


@dataclass
class Position:
    """Represents an open position"""
    symbol: str
    volume: float
    risk_percent: float  # Risk % for this position


class PortfolioManager:
    """
    Portfolio-level risk management

    Features:
    - Maximum total portfolio risk limit
    - Correlation-based position blocking
    - Position concentration limits
    """

    # Correlation matrix for major pairs
    # Values range from -1 (inverse) to +1 (same direction)
    CORRELATION_MATRIX = {
        ('EURUSD', 'GBPUSD'): 0.85,   # High positive correlation
        ('EURUSD', 'USDCHF'): -0.92,  # High negative correlation
        ('EURUSD', 'USDJPY'): -0.65,
        ('GBPUSD', 'USDCHF'): -0.88,
        ('GBPUSD', 'USDJPY'): -0.60,
        ('USDCHF', 'USDJPY'): 0.72,
        ('AUDUSD', 'NZDUSD'): 0.88,   # Commodity currencies
        ('EURUSD', 'AUDUSD'): 0.68,
        ('EURUSD', 'NZDUSD'): 0.65,
        ('GBPUSD', 'AUDUSD'): 0.70,
        ('GBPUSD', 'NZDUSD'): 0.68,
    }

    def __init__(
        self,
        max_portfolio_risk: float = 6.0,  # Maximum total portfolio risk %
        max_positions_per_symbol: int = 2,  # Max concurrent positions per symbol
        correlation_threshold: float = 0.7  # Block if correlation > this
    ):
        """
        Initialize Portfolio Manager

        Args:
            max_portfolio_risk: Maximum total portfolio risk as percentage
            max_positions_per_symbol: Maximum number of positions allowed per symbol
            correlation_threshold: Correlation threshold for blocking (0-1)
        """
        self.max_portfolio_risk = max_portfolio_risk
        self.max_positions_per_symbol = max_positions_per_symbol
        self.correlation_threshold = correlation_threshold

        # Current positions
        self.positions: List[Position] = []

        logger.info(
            f"PortfolioManager initialized - Max Risk: {max_portfolio_risk}%, "
            f"Max Pos/Symbol: {max_positions_per_symbol}, "
            f"Correlation Threshold: {correlation_threshold}"
        )

    def can_open_position(
        self,
        symbol: str,
        proposed_risk: float,
        account_balance: float
    ) -> Tuple[bool, str]:
        """
        Check if a new position can be opened

        Args:
            symbol: Symbol to trade
            proposed_risk: Risk percentage for new position
            account_balance: Current account balance

        Returns:
            Tuple of (can_open: bool, reason: str)
        """
        # Check 1: Total portfolio risk
        current_total_risk = sum(pos.risk_percent for pos in self.positions)
        new_total_risk = current_total_risk + proposed_risk

        if new_total_risk > self.max_portfolio_risk:
            return False, (
                f"Portfolio risk would be {new_total_risk:.2f}% "
                f"(max: {self.max_portfolio_risk}%)"
            )

        # Check 2: Max positions per symbol
        symbol_count = sum(1 for pos in self.positions if pos.symbol == symbol)
        if symbol_count >= self.max_positions_per_symbol:
            return False, (
                f"Already have {symbol_count} position(s) on {symbol} "
                f"(max: {self.max_positions_per_symbol})"
            )

        # Check 3: Correlation blocking
        for position in self.positions:
            correlation = self._get_correlation(symbol, position.symbol)

            if abs(correlation) > self.correlation_threshold:
                return False, (
                    f"High correlation ({correlation:.2f}) with open position on {position.symbol}"
                )

        # All checks passed
        return True, "OK"

    def add_position(self, symbol: str, volume: float, risk_percent: float):
        """
        Add a position to the portfolio

        Args:
            symbol: Symbol traded
            volume: Lot size
            risk_percent: Risk percentage for this position
        """
        position = Position(
            symbol=symbol,
            volume=volume,
            risk_percent=risk_percent
        )
        self.positions.append(position)

        total_risk = sum(pos.risk_percent for pos in self.positions)
        logger.info(
            f"Position added: {symbol} ({risk_percent}%) | "
            f"Total portfolio risk: {total_risk:.2f}%"
        )

    def remove_position(self, symbol: str, volume: float = None):
        """
        Remove a position from the portfolio

        Args:
            symbol: Symbol to remove
            volume: Specific volume to remove (optional, removes first match if None)
        """
        for i, pos in enumerate(self.positions):
            if pos.symbol == symbol:
                if volume is None or pos.volume == volume:
                    removed = self.positions.pop(i)
                    total_risk = sum(p.risk_percent for p in self.positions)
                    logger.info(
                        f"Position removed: {symbol} ({removed.risk_percent}%) | "
                        f"Total portfolio risk: {total_risk:.2f}%"
                    )
                    return

    def get_total_risk(self) -> float:
        """Get current total portfolio risk percentage"""
        return sum(pos.risk_percent for pos in self.positions)

    def get_position_count(self, symbol: str = None) -> int:
        """
        Get position count

        Args:
            symbol: If provided, count for specific symbol. Otherwise total.

        Returns:
            Number of positions
        """
        if symbol:
            return sum(1 for pos in self.positions if pos.symbol == symbol)
        return len(self.positions)

    def _get_correlation(self, symbol1: str, symbol2: str) -> float:
        """
        Get correlation between two symbols

        Args:
            symbol1: First symbol
            symbol2: Second symbol

        Returns:
            Correlation coefficient (-1 to 1), or 0 if not in matrix
        """
        if symbol1 == symbol2:
            return 1.0  # Perfect correlation with self

        # Try both orderings
        pair = (symbol1, symbol2)
        reverse_pair = (symbol2, symbol1)

        if pair in self.CORRELATION_MATRIX:
            return self.CORRELATION_MATRIX[pair]
        elif reverse_pair in self.CORRELATION_MATRIX:
            return self.CORRELATION_MATRIX[reverse_pair]
        else:
            # Not in matrix, assume no correlation
            return 0.0

    def get_correlated_symbols(self, symbol: str) -> Dict[str, float]:
        """
        Get all symbols correlated with given symbol

        Args:
            symbol: Symbol to check

        Returns:
            Dict of {symbol: correlation}
        """
        correlated = {}

        for (sym1, sym2), correlation in self.CORRELATION_MATRIX.items():
            if sym1 == symbol:
                correlated[sym2] = correlation
            elif sym2 == symbol:
                correlated[sym1] = correlation

        return correlated

    def clear(self):
        """Clear all positions (for backtesting reset)"""
        self.positions.clear()

    def get_portfolio_summary(self) -> Dict:
        """
        Get portfolio summary

        Returns:
            Dict with portfolio statistics
        """
        total_risk = self.get_total_risk()

        # Group by symbol
        by_symbol = {}
        for pos in self.positions:
            if pos.symbol not in by_symbol:
                by_symbol[pos.symbol] = {'count': 0, 'total_volume': 0, 'total_risk': 0}
            by_symbol[pos.symbol]['count'] += 1
            by_symbol[pos.symbol]['total_volume'] += pos.volume
            by_symbol[pos.symbol]['total_risk'] += pos.risk_percent

        return {
            'total_positions': len(self.positions),
            'total_risk_percent': total_risk,
            'risk_utilization': (total_risk / self.max_portfolio_risk) * 100,
            'positions_by_symbol': by_symbol,
            'max_portfolio_risk': self.max_portfolio_risk,
            'max_positions_per_symbol': self.max_positions_per_symbol
        }
