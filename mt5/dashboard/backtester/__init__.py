"""
Enhanced Python Backtester Package

Implements MT5's 30-point confluence scoring system for accurate parameter optimization.

Modules:
- technical_indicators: Core indicators (RSI, EMA, ATR, etc.)
- smc_modules: Smart Money Concepts (Structure breaks, Order blocks, FVG, Liquidity)
- institutional_concepts: ICT concepts (Breaker blocks, Macro windows, Power of 3, Wyckoff)
- advanced_confluence: Advanced analysis (Volume profile, Divergence, MTF, Fibonacci)
- confluence_engine: Main orchestrator for confluence scoring
"""

__version__ = "1.0.0"

from .confluence_engine import ConfluenceEngine
from .technical_indicators import TechnicalIndicators

__all__ = ['ConfluenceEngine', 'TechnicalIndicators']
