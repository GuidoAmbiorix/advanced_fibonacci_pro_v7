"""
Portfolio Governor - Main state manager for intelligent portfolio selection.
Orchestrates all components and manages active trading group.
"""

from typing import List, Dict, Optional
from datetime import datetime
from enum import Enum
import pandas as pd
from pathlib import Path

from ..config import config
from .symbol_metadata import get_all_symbols, SYMBOL_METADATA
from .set_parser import parse_all_sets
from .correlation_engine import CorrelationEngine
from .symbol_scorer import SymbolScorer
from .group_generator import GroupGenerator
from .group_ranker import GroupRanker
from .ea_communicator import EACommunicator


class GovernorMode(Enum):
    """Portfolio Governor operating modes."""
    AUTO = "auto"          # Automatically select best group
    MANUAL = "manual"      # User selects group
    LOCKED = "locked"      # Group locked for session (no changes)


class PortfolioGovernor:
    """
    Main Portfolio Governor - Orchestrates portfolio selection.

    Manages:
    - Symbol universe (20 symbols from .set files)
    - Real-time scoring and correlation
    - Group generation and ranking
    - Active group selection
    - MT5 EA communication
    """

    DEFAULT_SETS_PATH = config.MT5_SETS_PATH
    
    def __init__(
        self,
        sets_path: Optional[Path] = None,
        performance_data: Optional[pd.DataFrame] = None
    ):
        """
        Initialize Portfolio Governor.
        
        Args:
            sets_path: Path to .set files directory
            performance_data: Historical trade data for scoring
        """
        self.sets_path = sets_path or self.DEFAULT_SETS_PATH
        
        # Load symbol universe
        self.available_symbols = get_all_symbols()
        self.sets_data = parse_all_sets(self.sets_path)
        
        # Initialize engines
        self.correlation_engine = CorrelationEngine(
            symbols=self.available_symbols,
            timeframe=config.CORRELATION_TIMEFRAME,
            bars=config.CORRELATION_BARS
        )
        self.symbol_scorer = SymbolScorer(performance_data=performance_data)
        self.group_generator = GroupGenerator(
            correlation_engine=self.correlation_engine,
            symbols=self.available_symbols
        )
        self.group_ranker = GroupRanker(
            symbol_scorer=self.symbol_scorer,
            group_generator=self.group_generator,
            correlation_engine=self.correlation_engine
        )
        self.ea_communicator = EACommunicator()
        
        # State
        self.mode = GovernorMode.AUTO
        self.active_group: Optional[List[str]] = None
        self.active_group_id: int = 0
        self.candidate_groups: List[Dict] = []
        self.symbol_scores: Dict[str, float] = {}
        
        # Timestamps
        self.last_refresh: Optional[datetime] = None
        self.lock_time: Optional[datetime] = None
    
    def refresh_scores(self) -> pd.DataFrame:
        """
        Refresh all symbol scores.
        
        Returns DataFrame with scores.
        """
        scores_df = self.symbol_scorer.get_all_symbol_scores(self.available_symbols)
        self.symbol_scores = {
            row['symbol']: row['total_score']
            for _, row in scores_df.iterrows()
        }
        return scores_df
    
    def refresh_correlations(self, force: bool = False) -> pd.DataFrame:
        """
        Refresh correlation matrix.
        
        Returns correlation DataFrame.
        """
        self.correlation_engine.refresh(force=force)
        return self.correlation_engine.get_correlation_heatmap_data()
    
    def generate_groups(self, top_n: int = 5) -> List[Dict]:
        """
        Generate and rank candidate groups.
        
        Args:
            top_n: Number of top groups to keep
            
        Returns:
            List of top group dicts
        """
        self.group_ranker.refresh()
        self.candidate_groups = self.group_ranker.get_top_groups(n=top_n)
        return self.candidate_groups
    
    def select_group(self, group_id: int) -> bool:
        """
        Select a group as active.
        
        Args:
            group_id: Index of group in candidate_groups
            
        Returns:
            True if selection successful
        """
        if self.mode == GovernorMode.LOCKED:
            return False  # Cannot change while locked
        
        if group_id < 0 or group_id >= len(self.candidate_groups):
            return False
        
        self.active_group_id = group_id
        self.active_group = self.candidate_groups[group_id]["symbols"]
        
        return True
    
    def select_best_group(self) -> bool:
        """
        Auto-select the best ranked group.
        """
        if not self.candidate_groups:
            self.generate_groups()
        
        if self.candidate_groups:
            return self.select_group(0)  # First is best
        
        return False
    
    def lock_group(self) -> bool:
        """
        Lock current group for the session.
        
        Prevents any changes until unlocked.
        """
        if not self.active_group:
            return False
        
        self.mode = GovernorMode.LOCKED
        self.lock_time = datetime.now()
        return True
    
    def unlock_group(self) -> None:
        """Unlock the group, return to previous mode."""
        self.mode = GovernorMode.AUTO
        self.lock_time = None
    
    def set_mode(self, mode: GovernorMode) -> None:
        """Set governor operating mode."""
        if mode != GovernorMode.LOCKED:
            self.mode = mode
            self.lock_time = None
    
    def sync_with_mt5(self) -> Dict:
        """
        Sync active group with MT5 EAs.
        
        Returns sync result dict.
        """
        if not self.active_group:
            return {"success": False, "error": "No active group selected"}
        
        return self.ea_communicator.sync_with_mt5(
            active_group=self.active_group,
            all_symbols=self.available_symbols
        )
    
    def refresh_all(self) -> Dict:
        """
        Full refresh of all data.
        
        Returns summary dict.
        """
        # Refresh correlations
        self.refresh_correlations(force=True)
        
        # Refresh scores
        scores_df = self.refresh_scores()
        
        # Generate groups
        groups = self.generate_groups()
        
        # Auto-select if in AUTO mode
        if self.mode == GovernorMode.AUTO and groups:
            self.select_best_group()
        
        self.last_refresh = datetime.now()
        
        return {
            "symbols_count": len(self.available_symbols),
            "groups_count": len(groups),
            "active_group": self.active_group,
            "top_score": groups[0]["composite_score"] if groups else 0,
            "last_refresh": self.last_refresh
        }
    
    def get_state(self) -> Dict:
        """
        Get current governor state.
        
        Returns complete state dict for UI.
        """
        return {
            "mode": self.mode.value,
            "available_symbols": self.available_symbols,
            "symbol_scores": self.symbol_scores,
            "candidate_groups": self.candidate_groups,
            "active_group": self.active_group,
            "active_group_id": self.active_group_id,
            "is_locked": self.mode == GovernorMode.LOCKED,
            "lock_time": self.lock_time,
            "last_refresh": self.last_refresh,
            "total_valid_groups": self.group_ranker.total_valid_groups,
            "sets_loaded": len(self.sets_data)
        }
    
    def get_currency_exposure(self) -> Dict[str, float]:
        """
        Calculate currency exposure from active group.
        
        Returns dict mapping currency to net exposure.
        Positive = long, Negative = short
        """
        if not self.active_group:
            return {}
        
        exposure: Dict[str, float] = {}
        
        for symbol in self.active_group:
            info = SYMBOL_METADATA.get(symbol)
            if info:
                # Add exposure (assuming 1 lot each for simplicity)
                base = info.base_currency
                quote = info.quote_currency
                
                # Long base, short quote
                exposure[base] = exposure.get(base, 0) + 1
                exposure[quote] = exposure.get(quote, 0) - 1
        
        return exposure
    
    def get_group_details(self, group_id: int) -> Optional[Dict]:
        """
        Get detailed info for a specific group.
        """
        if group_id < 0 or group_id >= len(self.candidate_groups):
            return None
        
        group = self.candidate_groups[group_id]
        
        # Add individual symbol scores
        symbol_details = []
        for symbol in group["symbols"]:
            info = SYMBOL_METADATA.get(symbol)
            symbol_details.append({
                "symbol": symbol,
                "score": self.symbol_scores.get(symbol, 0),
                "class": info.symbol_class.value if info else "",
                "risk": info.risk_profile.value if info else "",
                "volatility": info.volatility.value if info else ""
            })
        
        return {
            **group,
            "symbol_details": symbol_details,
            "is_active": group_id == self.active_group_id
        }
    
    def get_symbol_score_details(self, symbol: str) -> Dict:
        """Get detailed score breakdown for a symbol."""
        return self.symbol_scorer.calculate_symbol_score(symbol)
