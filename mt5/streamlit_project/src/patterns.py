import pandas as pd
from typing import List, Dict

class PatternGeneric:
    def __init__(self, trades: pd.DataFrame):
        self.trades = trades

    def analyze_patterns(self) -> pd.DataFrame:
        """
        Analyzes trades to determine performance by pattern.
        Currently uses 'comment' field as a proxy for pattern if available, 
        or dummy logic for demonstration until Pattern Signal is integrated.
        """
        if self.trades.empty:
            return pd.DataFrame()

        # Assuming 'comment' might contain pattern info like "M-Pattern", "Breakout", etc.
        # If comments are empty, we might simulate or return empty.
        
        # Let's extract potential tags from comments
        # Example comments: "Strateg: M-Pattern", "Setup: FVG"
        
        df = self.trades.copy()
        
        # Simple extraction: Use the first word of comment or a default
        df['details_pattern'] = df['comment'].fillna("Unknown")
        
        # Group by Pattern
        stats = df.groupby('details_pattern').agg({
            'profit': ['count', 'sum', 'mean'],
            'ticket': 'count'
        })
        
        # Flatten columns
        stats.columns = ['_'.join(col).strip() for col in stats.columns.values]
        stats = stats.rename(columns={
            'profit_count': 'trades',
            'profit_sum': 'total_pnl',
            'profit_mean': 'avg_pnl'
        })
        
        stats['win_rate'] = df.groupby('details_pattern').apply(
            lambda x: (x[x['profit'] > 0].shape[0] / x.shape[0]) * 100
        )
        
        return stats.reset_index()
