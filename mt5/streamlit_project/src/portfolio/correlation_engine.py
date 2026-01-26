"""
Correlation Engine - Real-time correlation calculation from MT5 price data.
Fetches historical closes and calculates Pearson correlation matrix.
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Optional
from datetime import datetime
from src.mt5_compat import mt5, MT5_AVAILABLE
import streamlit as st

from .symbol_metadata import get_all_symbols


class CorrelationEngine:
    """
    Real-time correlation calculator using MT5 price data.
    
    Caches results to avoid excessive API calls.
    """
    
    # MT5 Timeframe constants
    TIMEFRAME_MAP = {
        "M1": mt5.TIMEFRAME_M1,
        "M5": mt5.TIMEFRAME_M5,
        "M15": mt5.TIMEFRAME_M15,
        "M30": mt5.TIMEFRAME_M30,
        "H1": mt5.TIMEFRAME_H1,
        "H4": mt5.TIMEFRAME_H4,
        "D1": mt5.TIMEFRAME_D1,
    }
    
    def __init__(
        self,
        symbols: Optional[List[str]] = None,
        timeframe: str = "H1",
        bars: int = 100,
        cache_ttl_minutes: int = 15
    ):
        """
        Initialize correlation engine.
        
        Args:
            symbols: List of symbols to track (defaults to all 20)
            timeframe: MT5 timeframe for correlation calc
            bars: Number of bars to use for correlation
            cache_ttl_minutes: Cache time-to-live in minutes
        """
        self.symbols = symbols or get_all_symbols()
        self.timeframe = self.TIMEFRAME_MAP.get(timeframe, mt5.TIMEFRAME_H1)
        self.bars = bars
        self.cache_ttl = cache_ttl_minutes
        
        # Cache storage
        self._correlation_matrix: Optional[pd.DataFrame] = None
        self._closes_df: Optional[pd.DataFrame] = None
        self._last_update: Optional[datetime] = None
    
    def fetch_symbol_closes(self) -> pd.DataFrame:
        """
        Fetch historical close prices for all symbols.
        
        Returns DataFrame with symbol columns and datetime index.
        """
        closes = {}
        
        for symbol in self.symbols:
            try:
                # Attempt to fetch rates
                rates = mt5.copy_rates_from_pos(symbol, self.timeframe, 0, self.bars)
                
                if rates is not None and len(rates) > 0:
                    df = pd.DataFrame(rates)
                    df['time'] = pd.to_datetime(df['time'], unit='s')
                    closes[symbol] = df.set_index('time')['close']
                else:
                    # Skip symbols without data
                    pass
            except Exception as e:
                print(f"Error fetching {symbol}: {e}")
                continue
        
        if not closes:
            return pd.DataFrame()
        
        # Combine all closes into single DataFrame
        closes_df = pd.DataFrame(closes)
        
        # Forward fill missing values (for symbols with different trading hours)
        closes_df = closes_df.ffill().bfill()
        
        return closes_df
    
    def calculate_correlation_matrix(self, closes_df: Optional[pd.DataFrame] = None) -> pd.DataFrame:
        """
        Calculate Pearson correlation matrix from close prices.
        
        Args:
            closes_df: Optional DataFrame of closes (fetches if not provided)
            
        Returns:
            DataFrame with symbol-to-symbol correlations
        """
        if closes_df is None:
            closes_df = self.fetch_symbol_closes()
        
        if closes_df.empty:
            return pd.DataFrame()
        
        # Calculate returns (correlations on returns are more meaningful)
        returns = closes_df.pct_change().dropna()
        
        if len(returns) < 10:
            # Not enough data points
            return pd.DataFrame()
        
        # Calculate correlation matrix
        corr_matrix = returns.corr()
        
        return corr_matrix
    
    def refresh(self, force: bool = False) -> bool:
        """
        Refresh correlation data if cache is stale.
        
        Args:
            force: Force refresh even if cache is valid
            
        Returns:
            True if refresh was performed
        """
        now = datetime.now()
        
        # Check cache validity
        if not force and self._last_update:
            elapsed = (now - self._last_update).total_seconds() / 60
            if elapsed < self.cache_ttl:
                return False
        
        # Fetch and calculate
        self._closes_df = self.fetch_symbol_closes()
        self._correlation_matrix = self.calculate_correlation_matrix(self._closes_df)
        self._last_update = now
        
        return True
    
    def get_correlation(self, symbol1: str, symbol2: str) -> float:
        """
        Get correlation between two symbols.
        
        Returns 0.0 if not available.
        """
        self.refresh()
        
        if self._correlation_matrix is None or self._correlation_matrix.empty:
            return 0.0
        
        try:
            return float(self._correlation_matrix.loc[symbol1, symbol2])
        except KeyError:
            return 0.0
    
    def get_group_max_correlation(self, symbols: List[str]) -> float:
        """
        Get maximum absolute correlation within a group of symbols.
        
        This is used to filter groups with high internal correlation.
        """
        self.refresh()
        
        if self._correlation_matrix is None or self._correlation_matrix.empty:
            return 0.0
        
        max_corr = 0.0
        
        # Check all pairs within the group
        for i, sym1 in enumerate(symbols):
            for sym2 in symbols[i+1:]:
                try:
                    corr = abs(float(self._correlation_matrix.loc[sym1, sym2]))
                    max_corr = max(max_corr, corr)
                except KeyError:
                    continue
        
        return max_corr
    
    def get_group_avg_correlation(self, symbols: List[str]) -> float:
        """
        Get average absolute correlation within a group of symbols.
        """
        self.refresh()
        
        if self._correlation_matrix is None or self._correlation_matrix.empty:
            return 0.0
        
        correlations = []
        
        for i, sym1 in enumerate(symbols):
            for sym2 in symbols[i+1:]:
                try:
                    corr = abs(float(self._correlation_matrix.loc[sym1, sym2]))
                    correlations.append(corr)
                except KeyError:
                    continue
        
        if not correlations:
            return 0.0
        
        return float(np.mean(correlations))
    
    def get_correlation_heatmap_data(self, symbols: Optional[List[str]] = None) -> pd.DataFrame:
        """
        Get correlation matrix formatted for heatmap visualization.
        
        Args:
            symbols: Optional subset of symbols (defaults to all)
            
        Returns:
            DataFrame with correlations for heatmap
        """
        self.refresh()
        
        if self._correlation_matrix is None or self._correlation_matrix.empty:
            return pd.DataFrame()
        
        if symbols:
            # Filter to requested symbols
            available = [s for s in symbols if s in self._correlation_matrix.columns]
            return self._correlation_matrix.loc[available, available]
        
        return self._correlation_matrix.copy()
    
    @property
    def is_cached(self) -> bool:
        """Check if we have valid cached data."""
        return self._correlation_matrix is not None and not self._correlation_matrix.empty
    
    @property
    def last_update(self) -> Optional[datetime]:
        """Get last update timestamp."""
        return self._last_update
    
    @property 
    def cache_age_minutes(self) -> float:
        """Get cache age in minutes."""
        if not self._last_update:
            return float('inf')
        return (datetime.now() - self._last_update).total_seconds() / 60


@st.cache_data(ttl=900)  # 15 minute cache
def get_cached_correlation_matrix(symbols: tuple, timeframe: str, bars: int) -> pd.DataFrame:
    """
    Streamlit-cached correlation matrix.
    
    Note: symbols must be tuple for hashability.
    """
    engine = CorrelationEngine(
        symbols=list(symbols),
        timeframe=timeframe,
        bars=bars
    )
    engine.refresh(force=True)
    return engine.get_correlation_heatmap_data()
