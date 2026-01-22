"""
Group Generator - Generate valid 4-symbol combinations.
Applies correlation and diversity rules to filter candidates.
"""

from itertools import combinations
from typing import List, Dict, Set, Optional
import pandas as pd

from .symbol_metadata import (
    SYMBOL_METADATA,
    SymbolClass,
    RiskProfile,
    get_all_symbols,
    get_primary_driver
)
from .correlation_engine import CorrelationEngine


class GroupGenerator:
    """
    Generates valid trading groups (4 symbols each).
    
    Rules:
    - Maximum 2 symbols with same primary driver
    - Maximum 1 high correlation (>0.75) pair per group
    - Must include at least 2 different asset classes
    - Should have mix of Risk-On and Risk-Off
    """
    
    # Generation rules
    MAX_SAME_DRIVER = 2
    MAX_HIGH_CORRELATION = 0.75
    MIN_ASSET_CLASSES = 2
    
    def __init__(
        self, 
        correlation_engine: Optional[CorrelationEngine] = None,
        symbols: Optional[List[str]] = None
    ):
        """
        Initialize group generator.
        
        Args:
            correlation_engine: Engine for real-time correlations
            symbols: List of available symbols (defaults to all 20)
        """
        self.symbols = symbols or get_all_symbols()
        self.correlation_engine = correlation_engine or CorrelationEngine()
    
    def _get_symbol_drivers(self, symbols: List[str]) -> Dict[str, int]:
        """Count symbols by primary driver."""
        driver_counts: Dict[str, int] = {}
        
        for symbol in symbols:
            driver = get_primary_driver(symbol)
            driver_counts[driver] = driver_counts.get(driver, 0) + 1
        
        return driver_counts
    
    def _get_symbol_classes(self, symbols: List[str]) -> Set[SymbolClass]:
        """Get unique asset classes in group."""
        classes = set()
        
        for symbol in symbols:
            info = SYMBOL_METADATA.get(symbol)
            if info:
                classes.add(info.symbol_class)
        
        return classes
    
    def _get_risk_profiles(self, symbols: List[str]) -> Dict[RiskProfile, int]:
        """Count symbols by risk profile."""
        profiles: Dict[RiskProfile, int] = {}
        
        for symbol in symbols:
            info = SYMBOL_METADATA.get(symbol)
            if info:
                profiles[info.risk_profile] = profiles.get(info.risk_profile, 0) + 1
        
        return profiles
    
    def _check_driver_rule(self, symbols: List[str]) -> bool:
        """Check if group passes driver diversity rule."""
        drivers = self._get_symbol_drivers(symbols)
        
        # No driver should have more than MAX_SAME_DRIVER symbols
        return all(count <= self.MAX_SAME_DRIVER for count in drivers.values())
    
    def _check_correlation_rule(self, symbols: List[str]) -> bool:
        """Check if group passes correlation rule."""
        max_corr = self.correlation_engine.get_group_max_correlation(symbols)
        return max_corr <= self.MAX_HIGH_CORRELATION
    
    def _check_class_diversity_rule(self, symbols: List[str]) -> bool:
        """Check if group has minimum asset class diversity."""
        classes = self._get_symbol_classes(symbols)
        return len(classes) >= self.MIN_ASSET_CLASSES
    
    def _calculate_risk_balance(self, symbols: List[str]) -> float:
        """
        Calculate risk balance score (0-1).
        
        1.0 = perfect balance of Risk-On and Risk-Off
        0.0 = all same risk profile
        """
        profiles = self._get_risk_profiles(symbols)
        
        risk_on = profiles.get(RiskProfile.RISK_ON, 0)
        risk_off = profiles.get(RiskProfile.RISK_OFF, 0)
        neutral = profiles.get(RiskProfile.NEUTRAL, 0)
        
        total = len(symbols)
        
        # Ideal: 1-2 Risk-On, 1-2 Risk-Off, rest Neutral
        if risk_on >= 1 and risk_off >= 1:
            return 1.0  # Has both
        elif risk_on >= 1 or risk_off >= 1:
            return 0.6  # Has one type
        else:
            return 0.3  # Only neutral
    
    def is_valid_group(self, symbols: List[str]) -> bool:
        """
        Check if a group passes all rules.
        """
        if len(symbols) != 4:
            return False
        
        # Check all rules
        if not self._check_driver_rule(symbols):
            return False
        
        if not self._check_class_diversity_rule(symbols):
            return False
        
        if not self._check_correlation_rule(symbols):
            return False
        
        return True
    
    def generate_all_combinations(self, group_size: int = 4) -> List[List[str]]:
        """
        Generate all possible combinations of given size.
        
        Returns all C(n, k) combinations without filtering.
        """
        return [list(combo) for combo in combinations(self.symbols, group_size)]
    
    def generate_valid_groups(
        self, 
        group_size: int = 4,
        max_groups: Optional[int] = None
    ) -> List[Dict]:
        """
        Generate valid groups that pass all rules.
        
        Args:
            group_size: Number of symbols per group (default 4)
            max_groups: Maximum groups to return (None = all)
            
        Returns:
            List of dicts with group info and metrics
        """
        valid_groups = []
        all_combos = self.generate_all_combinations(group_size)
        
        for combo in all_combos:
            if self.is_valid_group(combo):
                # Calculate group metrics
                group_info = {
                    "symbols": combo,
                    "max_correlation": self.correlation_engine.get_group_max_correlation(combo),
                    "avg_correlation": self.correlation_engine.get_group_avg_correlation(combo),
                    "risk_balance": self._calculate_risk_balance(combo),
                    "classes": [c.value for c in self._get_symbol_classes(combo)],
                    "drivers": self._get_symbol_drivers(combo)
                }
                
                valid_groups.append(group_info)
                
                if max_groups and len(valid_groups) >= max_groups:
                    break
        
        return valid_groups
    
    def filter_by_correlation(
        self, 
        groups: List[Dict], 
        max_correlation: float = 0.7
    ) -> List[Dict]:
        """
        Filter groups by maximum correlation threshold.
        """
        return [g for g in groups if g["max_correlation"] <= max_correlation]
    
    def filter_by_risk_balance(
        self, 
        groups: List[Dict], 
        min_balance: float = 0.5
    ) -> List[Dict]:
        """
        Filter groups by minimum risk balance.
        """
        return [g for g in groups if g["risk_balance"] >= min_balance]
    
    def get_valid_groups_df(self, group_size: int = 4) -> pd.DataFrame:
        """
        Get valid groups as DataFrame.
        """
        groups = self.generate_valid_groups(group_size)
        
        if not groups:
            return pd.DataFrame()
        
        # Flatten for DataFrame
        rows = []
        for i, g in enumerate(groups):
            rows.append({
                "group_id": i,
                "symbols": ", ".join(g["symbols"]),
                "symbol_1": g["symbols"][0],
                "symbol_2": g["symbols"][1],
                "symbol_3": g["symbols"][2],
                "symbol_4": g["symbols"][3],
                "max_correlation": g["max_correlation"],
                "avg_correlation": g["avg_correlation"],
                "risk_balance": g["risk_balance"],
                "classes": ", ".join(g["classes"]),
                "num_classes": len(g["classes"])
            })
        
        return pd.DataFrame(rows)
    
    @property
    def total_possible_combinations(self) -> int:
        """Calculate total possible 4-symbol combinations."""
        n = len(self.symbols)
        # C(n, 4) = n! / (4! * (n-4)!)
        from math import factorial
        return factorial(n) // (factorial(4) * factorial(n - 4))
