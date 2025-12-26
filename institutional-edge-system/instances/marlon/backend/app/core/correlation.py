"""
Correlation Calculator for Portfolio Bot

Calculates correlation matrix between symbols to optimize diversification.
Low correlation = better diversification.
"""

import numpy as np
import pandas as pd
from typing import Dict, List, Optional
from loguru import logger


class CorrelationCalculator:
    """Calculate and analyze correlations between trading symbols"""
    
    def __init__(self, mt5_connector):
        self.mt5 = mt5_connector
        self.cache = {}  # Cache correlation data
        self.cache_ttl = 300  # 5 minutes TTL
    
    def calculate_correlation_matrix(
        self, 
        symbols: List[str], 
        timeframe: str = 'H1',
        bars: int = 500
    ) -> Dict:
        """
        Calculate correlation matrix between multiple symbols.
        
        Args:
            symbols: List of symbol names (e.g., ['EURUSD', 'GBPUSD', 'USDJPY'])
            timeframe: Timeframe for data (H1 recommended for stability)
            bars: Number of bars to use for calculation
            
        Returns:
            Dict with correlation matrix and metadata
        """
        if len(symbols) < 2:
            return {'matrix': {}, 'warnings': [], 'diversification_score': 1.0}
        
        # Fetch returns for each symbol
        returns_data = {}
        for symbol in symbols:
            try:
                df = self.mt5.get_ohlcv_data(symbol, timeframe, bars)
                if df is not None and not df.empty:
                    # Calculate log returns
                    df['returns'] = np.log(df['close'] / df['close'].shift(1))
                    returns_data[symbol] = df['returns'].dropna()
            except Exception as e:
                logger.warning(f"Could not fetch data for {symbol}: {e}")
        
        if len(returns_data) < 2:
            return {'matrix': {}, 'warnings': ['Not enough data'], 'diversification_score': 1.0}
        
        # Create DataFrame with aligned returns
        returns_df = pd.DataFrame(returns_data)
        
        # Calculate correlation matrix
        corr_matrix = returns_df.corr()
        
        # Convert to dict for JSON serialization
        matrix_dict = {}
        for sym1 in symbols:
            if sym1 in corr_matrix.columns:
                matrix_dict[sym1] = {}
                for sym2 in symbols:
                    if sym2 in corr_matrix.columns:
                        corr_value = corr_matrix.loc[sym1, sym2]
                        matrix_dict[sym1][sym2] = round(float(corr_value), 3) if not np.isnan(corr_value) else 0
        
        # Analyze correlations
        warnings = self._analyze_correlations(matrix_dict, symbols)
        diversification_score = self._calculate_diversification_score(corr_matrix)
        
        return {
            'matrix': matrix_dict,
            'warnings': warnings,
            'diversification_score': round(diversification_score, 2),
            'symbols': symbols,
            'timeframe': timeframe,
            'bars_used': bars
        }
    
    def _analyze_correlations(self, matrix: Dict, symbols: List[str], threshold: float = 0.7) -> List[str]:
        """
        Analyze correlation matrix for high correlations.
        
        Returns list of warnings for highly correlated pairs.
        """
        warnings = []
        checked = set()
        
        for sym1 in symbols:
            for sym2 in symbols:
                if sym1 == sym2:
                    continue
                pair_key = tuple(sorted([sym1, sym2]))
                if pair_key in checked:
                    continue
                checked.add(pair_key)
                
                if sym1 in matrix and sym2 in matrix[sym1]:
                    corr = matrix[sym1][sym2]
                    if abs(corr) >= threshold:
                        if corr > 0:
                            warnings.append(f"⚠️ {sym1} & {sym2} highly correlated ({corr:.2f}) - Similar risk exposure")
                        else:
                            warnings.append(f"📊 {sym1} & {sym2} negatively correlated ({corr:.2f}) - Potential hedge")
        
        return warnings
    
    def _calculate_diversification_score(self, corr_matrix: pd.DataFrame) -> float:
        """
        Calculate overall diversification score.
        
        Score ranges from 0 (perfectly correlated, no diversification)
        to 1 (no correlation, perfect diversification).
        """
        if corr_matrix.empty:
            return 1.0
        
        # Get off-diagonal correlations (exclude self-correlation)
        n = len(corr_matrix)
        if n < 2:
            return 1.0
        
        # Calculate average absolute correlation (excluding diagonal)
        total_corr = 0
        count = 0
        for i in range(n):
            for j in range(n):
                if i != j:
                    total_corr += abs(corr_matrix.iloc[i, j])
                    count += 1
        
        avg_corr = total_corr / count if count > 0 else 0
        
        # Score: 1 - avg_correlation (higher is better)
        return 1 - avg_corr
    
    def get_correlation_level(self, correlation: float) -> str:
        """Get human-readable correlation level"""
        abs_corr = abs(correlation)
        if abs_corr < 0.3:
            return 'LOW'
        elif abs_corr < 0.7:
            return 'MODERATE'
        else:
            return 'HIGH'
    
    def get_correlation_color(self, correlation: float) -> str:
        """Get color for UI display"""
        abs_corr = abs(correlation)
        if abs_corr < 0.3:
            return 'green'
        elif abs_corr < 0.7:
            return 'yellow'
        else:
            return 'red'
