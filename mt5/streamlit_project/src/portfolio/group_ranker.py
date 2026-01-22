"""
Group Ranker - Rank and select optimal trading groups.
Combines symbol scores, correlation diversity, and risk balance.
"""

from typing import List, Dict, Optional
import pandas as pd
import numpy as np

from .group_generator import GroupGenerator
from .symbol_scorer import SymbolScorer
from .correlation_engine import CorrelationEngine
from .symbol_metadata import get_all_symbols, Session, SYMBOL_METADATA


class GroupRanker:
    """
    Ranks trading groups to select the best candidates.
    
    Ranking factors:
    - Average symbol score (40%)
    - Correlation diversity - lower is better (30%)
    - Risk mix balance (20%)
    - Session coverage (10%)
    """
    
    # Ranking weights
    WEIGHT_AVG_SCORE = 0.40
    WEIGHT_CORRELATION = 0.30
    WEIGHT_RISK_BALANCE = 0.20
    WEIGHT_SESSION = 0.10
    
    def __init__(
        self,
        symbol_scorer: Optional[SymbolScorer] = None,
        group_generator: Optional[GroupGenerator] = None,
        correlation_engine: Optional[CorrelationEngine] = None
    ):
        """
        Initialize group ranker.
        
        Args:
            symbol_scorer: Scorer for individual symbols
            group_generator: Generator for valid groups
            correlation_engine: Engine for correlation data
        """
        self.correlation_engine = correlation_engine or CorrelationEngine()
        self.symbol_scorer = symbol_scorer or SymbolScorer()
        self.group_generator = group_generator or GroupGenerator(
            correlation_engine=self.correlation_engine
        )
        
        self._ranked_groups: Optional[pd.DataFrame] = None
        self._symbol_scores: Dict[str, float] = {}
    
    def _refresh_symbol_scores(self) -> None:
        """Refresh scores for all symbols."""
        scores_df = self.symbol_scorer.get_all_symbol_scores()
        self._symbol_scores = {
            row['symbol']: row['total_score'] 
            for _, row in scores_df.iterrows()
        }
    
    def _calculate_avg_score(self, symbols: List[str]) -> float:
        """Calculate average symbol score for a group."""
        if not self._symbol_scores:
            self._refresh_symbol_scores()
        
        scores = [self._symbol_scores.get(s, 50) for s in symbols]
        return np.mean(scores)
    
    def _calculate_correlation_score(self, avg_correlation: float) -> float:
        """
        Convert correlation to score (lower correlation = higher score).
        
        Returns 0-100 score.
        """
        # Ideal: correlation < 0.3
        # Acceptable: correlation < 0.5
        # Poor: correlation > 0.7
        
        if avg_correlation <= 0.2:
            return 100
        elif avg_correlation <= 0.3:
            return 90
        elif avg_correlation <= 0.4:
            return 75
        elif avg_correlation <= 0.5:
            return 60
        elif avg_correlation <= 0.6:
            return 40
        elif avg_correlation <= 0.7:
            return 20
        else:
            return 5
    
    def _calculate_session_coverage(self, symbols: List[str]) -> float:
        """
        Calculate session coverage score.
        
        Higher score if group covers multiple sessions.
        Returns 0-100.
        """
        sessions_covered = set()
        
        for symbol in symbols:
            info = SYMBOL_METADATA.get(symbol)
            if info:
                sessions_covered.update(info.sessions)
        
        # Score based on number of sessions covered
        coverage = len(sessions_covered) / 3  # 3 main sessions
        return coverage * 100
    
    def calculate_group_rank(self, group: Dict) -> Dict:
        """
        Calculate composite rank for a single group.
        
        Args:
            group: Dict with symbols and metrics from GroupGenerator
            
        Returns:
            Dict with ranking details
        """
        symbols = group["symbols"]
        
        # Calculate component scores
        avg_symbol_score = self._calculate_avg_score(symbols)
        correlation_score = self._calculate_correlation_score(group["avg_correlation"])
        risk_balance_score = group["risk_balance"] * 100
        session_score = self._calculate_session_coverage(symbols)
        
        # Calculate weighted composite score
        composite = (
            self.WEIGHT_AVG_SCORE * avg_symbol_score +
            self.WEIGHT_CORRELATION * correlation_score +
            self.WEIGHT_RISK_BALANCE * risk_balance_score +
            self.WEIGHT_SESSION * session_score
        )
        
        return {
            "symbols": symbols,
            "symbols_str": ", ".join(symbols),
            "composite_score": round(composite, 2),
            "avg_symbol_score": round(avg_symbol_score, 1),
            "correlation_score": round(correlation_score, 1),
            "max_correlation": round(group["max_correlation"], 3),
            "avg_correlation": round(group["avg_correlation"], 3),
            "risk_balance_score": round(risk_balance_score, 1),
            "session_coverage_score": round(session_score, 1),
            "classes": group["classes"],
            "drivers": group["drivers"]
        }
    
    def rank_groups(self, groups: Optional[List[Dict]] = None) -> pd.DataFrame:
        """
        Rank all valid groups and return sorted DataFrame.
        
        Args:
            groups: Optional list of groups (generates if not provided)
            
        Returns:
            DataFrame with ranked groups
        """
        # Refresh symbol scores
        self._refresh_symbol_scores()
        
        # Generate groups if not provided
        if groups is None:
            groups = self.group_generator.generate_valid_groups()
        
        if not groups:
            return pd.DataFrame()
        
        # Rank each group
        ranked = [self.calculate_group_rank(g) for g in groups]
        
        # Convert to DataFrame and sort
        df = pd.DataFrame(ranked)
        df = df.sort_values("composite_score", ascending=False)
        df["rank"] = range(1, len(df) + 1)
        
        # Reorder columns
        cols = ["rank", "symbols_str", "composite_score", "avg_symbol_score", 
                "correlation_score", "avg_correlation", "max_correlation",
                "risk_balance_score", "session_coverage_score", "symbols"]
        df = df[[c for c in cols if c in df.columns]]
        
        self._ranked_groups = df
        
        return df
    
    def get_top_groups(self, n: int = 5) -> List[Dict]:
        """
        Get top N ranked groups.
        
        Returns list of dicts with group details.
        """
        if self._ranked_groups is None or self._ranked_groups.empty:
            self.rank_groups()
        
        if self._ranked_groups is None or self._ranked_groups.empty:
            return []
        
        top_df = self._ranked_groups.head(n)
        
        return [
            {
                "group_id": i,
                "rank": row["rank"],
                "symbols": row["symbols"],
                "composite_score": row["composite_score"],
                "avg_symbol_score": row["avg_symbol_score"],
                "correlation_score": row["correlation_score"],
                "avg_correlation": row["avg_correlation"],
                "max_correlation": row["max_correlation"],
                "risk_balance_score": row["risk_balance_score"],
                "session_coverage_score": row["session_coverage_score"]
            }
            for i, (_, row) in enumerate(top_df.iterrows())
        ]
    
    def get_best_group(self) -> Optional[Dict]:
        """Get the single best group."""
        top = self.get_top_groups(1)
        return top[0] if top else None
    
    def get_group_comparison(self, group_ids: List[int]) -> pd.DataFrame:
        """
        Compare specific groups side by side.
        """
        if self._ranked_groups is None:
            self.rank_groups()
        
        if self._ranked_groups is None:
            return pd.DataFrame()
        
        return self._ranked_groups[
            self._ranked_groups["rank"].isin([i + 1 for i in group_ids])
        ]
    
    def refresh(self) -> None:
        """Force refresh all data and rankings."""
        self.correlation_engine.refresh(force=True)
        self._refresh_symbol_scores()
        self.rank_groups()
    
    @property
    def total_valid_groups(self) -> int:
        """Get total number of valid groups."""
        if self._ranked_groups is None:
            self.rank_groups()
        return len(self._ranked_groups) if self._ranked_groups is not None else 0
