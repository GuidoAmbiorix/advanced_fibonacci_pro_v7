"""
Portfolio Tracker - Track and analyze portfolio group performance over time.
Provides historical analysis, correlation drift detection, and performance attribution.
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Optional, Tuple
from datetime import datetime, timedelta

from ..database import get_database
from ..logger import get_logger, LogContext
from .symbol_metadata import SYMBOL_METADATA

logger = get_logger(__name__)


class PortfolioTracker:
    """
    Tracks portfolio group performance and provides analytics.

    Features:
    - Group performance history
    - Correlation drift detection
    - Performance attribution by symbol
    - Win rate and Sharpe ratio tracking
    - Group lifetime analysis
    """

    def __init__(self):
        self.db = get_database()
        logger.info("PortfolioTracker initialized")

    def track_group_selection(
        self,
        symbols: List[str],
        composite_score: float,
        avg_correlation: float,
        max_correlation: float,
        risk_balance: float,
        notes: Optional[str] = None
    ) -> int:
        """
        Track a new portfolio group selection.

        Args:
            symbols: List of symbols
            composite_score: Group score
            avg_correlation: Average correlation
            max_correlation: Maximum correlation
            risk_balance: Risk balance score
            notes: Optional notes

        Returns:
            Group ID
        """
        try:
            with LogContext(logger, "track_group_selection"):
                group_id = self.db.save_portfolio_group(
                    symbols=symbols,
                    composite_score=composite_score,
                    avg_correlation=avg_correlation,
                    max_correlation=max_correlation,
                    risk_balance=risk_balance,
                    notes=notes
                )

                logger.info(f"Tracked new group selection: {symbols}")
                return group_id

        except Exception as e:
            logger.error(f"Error tracking group selection: {e}", exc_info=True)
            return 0

    def update_active_group_performance(self, trades_df: pd.DataFrame):
        """
        Update performance metrics for the currently active group.

        Args:
            trades_df: DataFrame of all trades
        """
        try:
            active_group = self.db.get_active_portfolio_group()

            if not active_group:
                logger.debug("No active group to update")
                return

            group_symbols = active_group['symbols']
            group_id = active_group['id']
            selected_at = active_group['selected_at']

            # Filter trades for this group's symbols and time period
            if not trades_df.empty:
                group_trades = trades_df[
                    (trades_df['symbol'].isin(group_symbols)) &
                    (trades_df['exit_time'] >= selected_at)
                ].copy()

                if not group_trades.empty:
                    self.db.update_group_performance(group_id, group_trades)
                    logger.debug(f"Updated group {group_id} with {len(group_trades)} trades")

        except Exception as e:
            logger.error(f"Error updating active group performance: {e}", exc_info=True)

    def get_group_performance_history(self, days: int = 30) -> pd.DataFrame:
        """
        Get historical performance of portfolio groups.

        Args:
            days: Number of days of history

        Returns:
            DataFrame with group performance metrics
        """
        try:
            df = self.db.get_portfolio_group_history(days=days)

            if df.empty:
                return df

            # Calculate additional metrics
            df['win_rate'] = df.apply(
                lambda row: (row['winning_trades'] / row['trades_count'] * 100)
                if row['trades_count'] > 0 else 0,
                axis=1
            )

            df['net_profit'] = df['total_profit'] + df['total_commission'] + df['total_swap']

            df['lifetime_hours'] = df.apply(
                lambda row: (
                    (row['deselected_at'] if pd.notna(row['deselected_at']) else datetime.now())
                    - row['selected_at']
                ).total_seconds() / 3600,
                axis=1
            )

            df['profit_per_day'] = df.apply(
                lambda row: row['net_profit'] / (row['lifetime_hours'] / 24)
                if row['lifetime_hours'] > 0 else 0,
                axis=1
            )

            # Add symbol count
            df['symbol_count'] = df['symbols'].apply(len)

            return df

        except Exception as e:
            logger.error(f"Error getting group performance history: {e}", exc_info=True)
            return pd.DataFrame()

    def get_active_group_details(self) -> Optional[Dict]:
        """
        Get detailed information about currently active group.

        Returns:
            Dict with group details and performance
        """
        try:
            active = self.db.get_active_portfolio_group()

            if not active:
                return None

            # Calculate additional metrics
            lifetime = datetime.now() - active['selected_at']

            win_rate = (
                (active['winning_trades'] / active['trades_count'] * 100)
                if active['trades_count'] > 0 else 0
            )

            net_profit = (
                active['total_profit'] +
                active.get('total_commission', 0) +
                active.get('total_swap', 0)
            )

            profit_per_day = (
                net_profit / (lifetime.total_seconds() / 86400)
                if lifetime.total_seconds() > 0 else 0
            )

            # Get symbol metadata
            symbol_details = []
            for symbol in active['symbols']:
                info = SYMBOL_METADATA.get(symbol)
                symbol_details.append({
                    'symbol': symbol,
                    'class': info.symbol_class.value if info else 'Unknown',
                    'risk_profile': info.risk_profile.value if info else 'Unknown'
                })

            return {
                **active,
                'lifetime_hours': lifetime.total_seconds() / 3600,
                'lifetime_days': lifetime.total_seconds() / 86400,
                'win_rate': win_rate,
                'net_profit': net_profit,
                'profit_per_day': profit_per_day,
                'symbol_details': symbol_details
            }

        except Exception as e:
            logger.error(f"Error getting active group details: {e}", exc_info=True)
            return None

    def compare_groups(
        self,
        group_ids: Optional[List[int]] = None,
        days: int = 30
    ) -> pd.DataFrame:
        """
        Compare performance of multiple groups.

        Args:
            group_ids: Specific group IDs to compare (None = all recent)
            days: Days of history if group_ids not specified

        Returns:
            DataFrame comparing group metrics
        """
        try:
            if group_ids:
                # Fetch specific groups
                # Would need additional database method
                logger.warning("Specific group comparison not yet implemented")
                return pd.DataFrame()
            else:
                # Compare recent groups
                return self.get_group_performance_history(days=days)

        except Exception as e:
            logger.error(f"Error comparing groups: {e}", exc_info=True)
            return pd.DataFrame()

    def get_symbol_performance_attribution(
        self,
        group_id: Optional[int] = None
    ) -> pd.DataFrame:
        """
        Analyze performance attribution by symbol within a group.

        Args:
            group_id: Specific group ID (None = active group)

        Returns:
            DataFrame with per-symbol performance
        """
        try:
            # Get group info
            if group_id is None:
                group = self.db.get_active_portfolio_group()
            else:
                # Would need database method to get specific group
                logger.warning("Specific group attribution not yet implemented")
                return pd.DataFrame()

            if not group:
                return pd.DataFrame()

            symbols = group['symbols']
            selected_at = group['selected_at']

            # Get trades for this group
            trades_df = self.db.get_trades(from_date=selected_at)

            if trades_df.empty:
                return pd.DataFrame()

            # Filter to group symbols
            group_trades = trades_df[trades_df['symbol'].isin(symbols)].copy()

            if group_trades.empty:
                return pd.DataFrame()

            # Calculate per-symbol metrics
            attribution = []

            for symbol in symbols:
                symbol_trades = group_trades[group_trades['symbol'] == symbol]

                if len(symbol_trades) == 0:
                    attribution.append({
                        'symbol': symbol,
                        'trades_count': 0,
                        'total_profit': 0,
                        'win_rate': 0,
                        'avg_profit': 0,
                        'contribution_pct': 0
                    })
                    continue

                winning = len(symbol_trades[symbol_trades['profit'] > 0])
                total_profit = symbol_trades['profit'].sum()

                attribution.append({
                    'symbol': symbol,
                    'trades_count': len(symbol_trades),
                    'total_profit': total_profit,
                    'win_rate': (winning / len(symbol_trades) * 100),
                    'avg_profit': symbol_trades['profit'].mean(),
                    'max_profit': symbol_trades['profit'].max(),
                    'max_loss': symbol_trades['profit'].min(),
                    'contribution_pct': 0  # Will calculate below
                })

            df = pd.DataFrame(attribution)

            # Calculate contribution percentage
            total_group_profit = df['total_profit'].sum()
            if total_group_profit != 0:
                df['contribution_pct'] = (df['total_profit'] / total_group_profit * 100)

            return df.sort_values('total_profit', ascending=False)

        except Exception as e:
            logger.error(f"Error calculating attribution: {e}", exc_info=True)
            return pd.DataFrame()

    def detect_correlation_drift(
        self,
        current_correlations: pd.DataFrame,
        group_id: Optional[int] = None,
        threshold: float = 0.15
    ) -> List[Dict]:
        """
        Detect significant changes in correlation since group selection.

        Args:
            current_correlations: Current correlation matrix
            group_id: Group ID to check (None = active)
            threshold: Alert threshold for correlation change

        Returns:
            List of drifts detected
        """
        try:
            # Get group info
            if group_id is None:
                group = self.db.get_active_portfolio_group()
            else:
                return []  # Not implemented yet

            if not group:
                return []

            symbols = group['symbols']
            original_avg_corr = group['avg_correlation']
            original_max_corr = group['max_correlation']

            # Calculate current correlations for group symbols
            if current_correlations.empty:
                return []

            # Filter to group symbols
            group_corr = current_correlations.loc[symbols, symbols]

            # Calculate current metrics
            mask = np.triu(np.ones_like(group_corr, dtype=bool), k=1)
            correlations = group_corr.where(mask)

            current_avg = correlations.stack().mean()
            current_max = correlations.stack().max()

            drifts = []

            # Check average correlation drift
            avg_drift = abs(current_avg - original_avg_corr)
            if avg_drift >= threshold:
                drifts.append({
                    'type': 'average_correlation',
                    'original': original_avg_corr,
                    'current': current_avg,
                    'drift': avg_drift,
                    'severity': 'high' if avg_drift >= threshold * 2 else 'medium'
                })

            # Check max correlation drift
            max_drift = abs(current_max - original_max_corr)
            if max_drift >= threshold:
                drifts.append({
                    'type': 'max_correlation',
                    'original': original_max_corr,
                    'current': current_max,
                    'drift': max_drift,
                    'severity': 'high' if max_drift >= threshold * 2 else 'medium'
                })

            if drifts:
                logger.warning(f"Detected {len(drifts)} correlation drifts for active group")

            return drifts

        except Exception as e:
            logger.error(f"Error detecting correlation drift: {e}", exc_info=True)
            return []

    def get_group_lifecycle_analysis(self, days: int = 90) -> Dict:
        """
        Analyze portfolio group lifecycle patterns.

        Args:
            days: Days of history to analyze

        Returns:
            Dict with lifecycle insights
        """
        try:
            history_df = self.get_group_performance_history(days=days)

            if history_df.empty:
                return {}

            # Calculate aggregate metrics
            total_groups = len(history_df)
            profitable_groups = len(history_df[history_df['net_profit'] > 0])
            avg_lifetime_hours = history_df['lifetime_hours'].mean()
            avg_trades_per_group = history_df['trades_count'].mean()
            best_group = history_df.nlargest(1, 'net_profit').iloc[0] if len(history_df) > 0 else None
            worst_group = history_df.nsmallest(1, 'net_profit').iloc[0] if len(history_df) > 0 else None

            # Correlation analysis
            avg_starting_corr = history_df['avg_correlation'].mean()
            avg_max_corr = history_df['max_correlation'].mean()

            return {
                'total_groups': total_groups,
                'profitable_groups': profitable_groups,
                'profitable_rate': (profitable_groups / total_groups * 100) if total_groups > 0 else 0,
                'avg_lifetime_hours': avg_lifetime_hours,
                'avg_lifetime_days': avg_lifetime_hours / 24,
                'avg_trades_per_group': avg_trades_per_group,
                'avg_starting_correlation': avg_starting_corr,
                'avg_max_correlation': avg_max_corr,
                'best_group': {
                    'symbols': best_group['symbols'],
                    'profit': best_group['net_profit'],
                    'trades': best_group['trades_count']
                } if best_group is not None else None,
                'worst_group': {
                    'symbols': worst_group['symbols'],
                    'profit': worst_group['net_profit'],
                    'trades': worst_group['trades_count']
                } if worst_group is not None else None,
                'total_net_profit': history_df['net_profit'].sum(),
                'avg_win_rate': history_df['win_rate'].mean()
            }

        except Exception as e:
            logger.error(f"Error in lifecycle analysis: {e}", exc_info=True)
            return {}

    def generate_group_performance_report(
        self,
        group_id: Optional[int] = None
    ) -> Dict:
        """
        Generate comprehensive performance report for a group.

        Args:
            group_id: Group ID (None = active)

        Returns:
            Dict with complete group report
        """
        try:
            details = self.get_active_group_details() if group_id is None else None

            if not details:
                return {}

            attribution = self.get_symbol_performance_attribution(group_id)

            return {
                'group_details': details,
                'symbol_attribution': attribution.to_dict('records') if not attribution.empty else [],
                'generated_at': datetime.now().isoformat()
            }

        except Exception as e:
            logger.error(f"Error generating report: {e}", exc_info=True)
            return {}
