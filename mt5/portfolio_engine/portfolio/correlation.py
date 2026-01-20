"""
Correlation Manager
Manages correlation groups to prevent over-exposure to correlated assets.
"""

from typing import Dict, Optional
from enum import Enum


class CorrelationGroup(Enum):
    """Correlation group categories."""
    USD = "USD"
    JPY = "JPY"
    GBP = "GBP"
    EUR = "EUR"
    AUD = "AUD"
    CAD = "CAD"
    METALS = "METALS"
    INDICES = "INDICES"
    CRYPTO = "CRYPTO"
    OTHER = "OTHER"


# Symbol to correlation group mapping
SYMBOL_GROUPS: Dict[str, CorrelationGroup] = {
    # USD group
    'EURUSD': CorrelationGroup.USD,
    'GBPUSD': CorrelationGroup.USD,
    'USDJPY': CorrelationGroup.USD,
    'USDCHF': CorrelationGroup.USD,
    'USDCAD': CorrelationGroup.USD,
    'AUDUSD': CorrelationGroup.USD,
    'NZDUSD': CorrelationGroup.USD,
    
    # JPY group (cross pairs)
    'EURJPY': CorrelationGroup.JPY,
    'GBPJPY': CorrelationGroup.JPY,
    'AUDJPY': CorrelationGroup.JPY,
    'CADJPY': CorrelationGroup.JPY,
    'CHFJPY': CorrelationGroup.JPY,
    
    # GBP group
    'EURGBP': CorrelationGroup.GBP,
    'GBPCAD': CorrelationGroup.GBP,
    'GBPCHF': CorrelationGroup.GBP,
    'GBPAUD': CorrelationGroup.GBP,
    'GBPNZD': CorrelationGroup.GBP,
    
    # Metals
    'XAUUSD': CorrelationGroup.METALS,
    'XAGUSD': CorrelationGroup.METALS,
    'GOLD': CorrelationGroup.METALS,
    'SILVER': CorrelationGroup.METALS,
    
    # Indices
    'NAS100': CorrelationGroup.INDICES,
    'US30': CorrelationGroup.INDICES,
    'SP500': CorrelationGroup.INDICES,
    'US500': CorrelationGroup.INDICES,
    'USTEC': CorrelationGroup.INDICES,
    'DAX40': CorrelationGroup.INDICES,
    'DAX': CorrelationGroup.INDICES,
    'FTSE100': CorrelationGroup.INDICES,
    
    # Crypto
    'BTCUSD': CorrelationGroup.CRYPTO,
    'ETHUSD': CorrelationGroup.CRYPTO,
}


class CorrelationManager:
    """
    Manages symbol correlation groups.
    
    Prevents over-exposure to correlated assets by grouping
    related symbols together.
    """
    
    def __init__(self):
        self.symbol_groups = SYMBOL_GROUPS.copy()
    
    def get_group(self, symbol: str) -> str:
        """
        Get correlation group for a symbol.
        
        Args:
            symbol: Trading symbol
            
        Returns:
            Group name as string
        """
        symbol = symbol.upper()
        
        if symbol in self.symbol_groups:
            return self.symbol_groups[symbol].value
        
        # Try to infer from symbol name
        return self._infer_group(symbol)
    
    def _infer_group(self, symbol: str) -> str:
        """Infer group from symbol name patterns."""
        symbol = symbol.upper()
        
        # Metals
        if 'XAU' in symbol or 'GOLD' in symbol:
            return CorrelationGroup.METALS.value
        if 'XAG' in symbol or 'SILVER' in symbol:
            return CorrelationGroup.METALS.value
        
        # Indices
        if any(idx in symbol for idx in ['NAS', 'US30', 'SP500', 'DAX', 'FTSE']):
            return CorrelationGroup.INDICES.value
        
        # Crypto
        if any(crypto in symbol for crypto in ['BTC', 'ETH', 'XRP', 'LTC']):
            return CorrelationGroup.CRYPTO.value
        
        # Forex - check for JPY pairs
        if 'JPY' in symbol:
            return CorrelationGroup.JPY.value
        
        # Forex - check for GBP pairs
        if 'GBP' in symbol:
            return CorrelationGroup.GBP.value
        
        # Forex - check for USD pairs
        if 'USD' in symbol:
            return CorrelationGroup.USD.value
        
        return CorrelationGroup.OTHER.value
    
    def add_symbol(self, symbol: str, group: CorrelationGroup):
        """Add or update symbol group mapping."""
        self.symbol_groups[symbol.upper()] = group
    
    def get_group_symbols(self, group: CorrelationGroup) -> list:
        """Get all symbols in a group."""
        return [sym for sym, grp in self.symbol_groups.items() if grp == group]
    
    def are_correlated(self, symbol1: str, symbol2: str) -> bool:
        """Check if two symbols are in the same correlation group."""
        return self.get_group(symbol1) == self.get_group(symbol2)
