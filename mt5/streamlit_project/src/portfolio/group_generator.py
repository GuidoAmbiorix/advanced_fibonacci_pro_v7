"""
Group Generator - Generate valid 4-symbol combinations.
Applies correlation and diversity rules to filter candidates.
Supports parallel processing for performance optimization.
"""

from itertools import combinations
from typing import List, Dict, Set, Optional
import pandas as pd
from concurrent.futures import ThreadPoolExecutor, as_completed
import streamlit as st

from ..config import config
from ..logger import get_logger, LogContext
from .symbol_metadata import (
    SYMBOL_METADATA,
    SymbolClass,
    RiskProfile,
    get_all_symbols,
    get_primary_driver
)
from .correlation_engine import CorrelationEngine

logger = get_logger(__name__)


class GroupGenerator:
    """
    Generates valid trading groups (4 symbols each).

    Rules:
    - Maximum N symbols with same primary driver (configurable)
    - Maximum correlation threshold (configurable)
    - Must include at least N different asset classes (configurable)
    - Should have mix of Risk-On and Risk-Off
    """

    def __init__(
        self,
        correlation_engine: Optional[CorrelationEngine] = None,
        symbols: Optional[List[str]] = None,
        use_parallel: bool = True
    ):
        """
        Initialize group generator.

        Args:
            correlation_engine: Engine for real-time correlations
            symbols: List of available symbols (defaults to all 20)
            use_parallel: Enable parallel processing for group generation
        """
        self.symbols = symbols or get_all_symbols()
        self.correlation_engine = correlation_engine or CorrelationEngine()
        self.use_parallel = use_parallel

        # Load rules from config
        self.MAX_SAME_DRIVER = config.MAX_SAME_DRIVER
        self.MAX_HIGH_CORRELATION = config.CORRELATION_HIGH_THRESHOLD
        self.MIN_ASSET_CLASSES = config.MIN_ASSET_CLASSES
        self.GROUP_SIZE = config.GROUP_SIZE

        logger.info(
            f"GroupGenerator initialized: {len(self.symbols)} symbols, "
            f"parallel={use_parallel}"
        )
    
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
    
    def _process_combination(self, combo: tuple) -> Optional[Dict]:
        """
        Process a single combination and return group info if valid.

        Args:
            combo: Tuple of symbols

        Returns:
            Group info dict or None if invalid
        """
        combo_list = list(combo)

        if not self.is_valid_group(combo_list):
            return None

        # Calculate group metrics
        return {
            "symbols": combo_list,
            "max_correlation": self.correlation_engine.get_group_max_correlation(combo_list),
            "avg_correlation": self.correlation_engine.get_group_avg_correlation(combo_list),
            "risk_balance": self._calculate_risk_balance(combo_list),
            "classes": [c.value for c in self._get_symbol_classes(combo_list)],
            "drivers": self._get_symbol_drivers(combo_list)
        }

    def generate_valid_groups(
        self,
        group_size: Optional[int] = None,
        max_groups: Optional[int] = None
    ) -> List[Dict]:
        """
        Generate valid groups that pass all rules.
        Supports parallel processing for better performance.

        Args:
            group_size: Number of symbols per group (defaults to config.GROUP_SIZE)
            max_groups: Maximum groups to return (None = all)

        Returns:
            List of dicts with group info and metrics
        """
        group_size = group_size or self.GROUP_SIZE

        try:
            with LogContext(logger, f"generate_valid_groups (size={group_size})"):
                all_combos = list(combinations(self.symbols, group_size))
                total_combos = len(all_combos)

                logger.info(f"Checking {total_combos} possible combinations")

                valid_groups = []

                if self.use_parallel and total_combos > 100:
                    # Use parallel processing for large combination sets
                    logger.info("Using parallel processing for group generation")

                    with ThreadPoolExecutor(max_workers=4) as executor:
                        # Submit all combinations for processing
                        futures = {
                            executor.submit(self._process_combination, combo): combo
                            for combo in all_combos
                        }

                        # Collect results as they complete
                        for future in as_completed(futures):
                            if max_groups and len(valid_groups) >= max_groups:
                                # Cancel remaining futures
                                for f in futures:
                                    f.cancel()
                                break

                            try:
                                result = future.result()
                                if result:
                                    valid_groups.append(result)
                            except Exception as e:
                                logger.warning(f"Error processing combination: {e}")

                else:
                    # Sequential processing for smaller sets
                    logger.info("Using sequential processing for group generation")

                    for combo in all_combos:
                        result = self._process_combination(combo)
                        if result:
                            valid_groups.append(result)

                            if max_groups and len(valid_groups) >= max_groups:
                                break

                logger.info(
                    f"Found {len(valid_groups)} valid groups out of "
                    f"{total_combos} combinations ({len(valid_groups)/total_combos*100:.1f}%)"
                )

                return valid_groups

        except Exception as e:
            logger.error(f"Error generating valid groups: {e}", exc_info=True)
            return []
    
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
