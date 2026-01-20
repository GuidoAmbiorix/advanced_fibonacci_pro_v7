"""
Portfolio Module
Contains portfolio governor and management logic.
"""

from .governor import PortfolioGovernor
from .metrics import (
    calculate_profit_factor,
    calculate_max_drawdown,
    calculate_sharpe_ratio,
    calculate_expectancy,
)
from .correlation import CorrelationManager
from .exposure import ExposureTracker

__all__ = [
    'PortfolioGovernor',
    'calculate_profit_factor',
    'calculate_max_drawdown',
    'calculate_sharpe_ratio',
    'calculate_expectancy',
    'CorrelationManager',
    'ExposureTracker',
]
