"""
Portfolio-Level Performance Metrics

Calculates portfolio-wide performance metrics including:
- Portfolio Sharpe ratio
- Correlation matrix and average correlation
- Diversification ratio
- Worst-case symbol performance
- Risk-adjusted returns
"""

import numpy as np
import pandas as pd
from typing import Dict, List, Tuple
import logging

logger = logging.getLogger("PortfolioMetrics")


class PortfolioMetrics:
    """Portfolio-level performance calculations."""

    @staticmethod
    def calculate_portfolio_sharpe(symbol_returns: Dict[str, np.ndarray],
                                   symbol_weights: Dict[str, float] = None) -> float:
        """
        Calculate portfolio Sharpe ratio.

        Args:
            symbol_returns: Dict of {symbol: array of returns}
            symbol_weights: Dict of {symbol: weight}. If None, equal weights.

        Returns:
            Portfolio Sharpe ratio
        """
        if not symbol_returns:
            return 0.0

        symbols = list(symbol_returns.keys())
        n_symbols = len(symbols)

        # Default to equal weights
        if symbol_weights is None:
            symbol_weights = {s: 1.0 / n_symbols for s in symbols}

        # Align returns to same length (use minimum length)
        min_length = min(len(returns) for returns in symbol_returns.values())
        aligned_returns = {s: returns[:min_length] for s, returns in symbol_returns.items()}

        # Calculate portfolio returns
        portfolio_returns = np.zeros(min_length)
        for symbol in symbols:
            weight = symbol_weights.get(symbol, 0)
            portfolio_returns += aligned_returns[symbol] * weight

        # Calculate Sharpe
        if len(portfolio_returns) < 2:
            return 0.0

        mean_return = np.mean(portfolio_returns)
        std_return = np.std(portfolio_returns)

        if std_return == 0:
            return 0.0

        sharpe = mean_return / (std_return + 1e-6)
        return sharpe

    @staticmethod
    def calculate_correlation_matrix(symbol_returns: Dict[str, np.ndarray]) -> pd.DataFrame:
        """
        Calculate correlation matrix between symbols.

        Args:
            symbol_returns: Dict of {symbol: array of returns}

        Returns:
            Correlation matrix as DataFrame
        """
        if not symbol_returns or len(symbol_returns) < 2:
            return pd.DataFrame()

        # Align returns to same length
        min_length = min(len(returns) for returns in symbol_returns.values())
        symbols = list(symbol_returns.keys())

        # Create DataFrame
        returns_df = pd.DataFrame({
            symbol: returns[:min_length]
            for symbol, returns in symbol_returns.items()
        })

        # Calculate correlation
        corr_matrix = returns_df.corr()
        return corr_matrix

    @staticmethod
    def calculate_average_correlation(symbol_returns: Dict[str, np.ndarray]) -> float:
        """
        Calculate average pairwise correlation.

        Args:
            symbol_returns: Dict of {symbol: array of returns}

        Returns:
            Average correlation (0 to 1)
        """
        corr_matrix = PortfolioMetrics.calculate_correlation_matrix(symbol_returns)

        if corr_matrix.empty:
            return 0.0

        # Get upper triangle (excluding diagonal)
        n = len(corr_matrix)
        if n < 2:
            return 0.0

        upper_triangle = []
        for i in range(n):
            for j in range(i + 1, n):
                upper_triangle.append(corr_matrix.iloc[i, j])

        avg_corr = np.mean(np.abs(upper_triangle))  # Absolute correlation
        return avg_corr

    @staticmethod
    def calculate_diversification_ratio(symbol_returns: Dict[str, np.ndarray],
                                       symbol_weights: Dict[str, float] = None) -> float:
        """
        Calculate diversification ratio.

        Diversification Ratio = (Weighted Avg Volatility) / (Portfolio Volatility)
        Higher is better (more diversified).

        Args:
            symbol_returns: Dict of {symbol: array of returns}
            symbol_weights: Dict of {symbol: weight}. If None, equal weights.

        Returns:
            Diversification ratio (typically 1.0 to sqrt(n))
        """
        if not symbol_returns:
            return 1.0

        symbols = list(symbol_returns.keys())
        n_symbols = len(symbols)

        # Default to equal weights
        if symbol_weights is None:
            symbol_weights = {s: 1.0 / n_symbols for s in symbols}

        # Calculate individual volatilities
        symbol_vols = {}
        for symbol, returns in symbol_returns.items():
            if len(returns) > 1:
                symbol_vols[symbol] = np.std(returns)
            else:
                symbol_vols[symbol] = 0.0

        # Weighted average volatility
        weighted_avg_vol = sum(symbol_weights.get(s, 0) * symbol_vols[s] for s in symbols)

        # Portfolio volatility
        min_length = min(len(returns) for returns in symbol_returns.values())
        portfolio_returns = np.zeros(min_length)
        for symbol in symbols:
            weight = symbol_weights.get(symbol, 0)
            portfolio_returns += symbol_returns[symbol][:min_length] * weight

        portfolio_vol = np.std(portfolio_returns) if len(portfolio_returns) > 1 else 0.0

        if portfolio_vol == 0:
            return 1.0

        div_ratio = weighted_avg_vol / (portfolio_vol + 1e-6)
        return div_ratio

    @staticmethod
    def calculate_worst_symbol_sharpe(symbol_sharpes: Dict[str, float]) -> float:
        """
        Get the worst (lowest) Sharpe ratio across symbols.

        This ensures robustness - we don't want one symbol to be terrible.

        Args:
            symbol_sharpes: Dict of {symbol: sharpe}

        Returns:
            Worst Sharpe ratio
        """
        if not symbol_sharpes:
            return 0.0

        return min(symbol_sharpes.values())

    @staticmethod
    def calculate_portfolio_metrics(symbol_results: Dict[str, Dict],
                                    symbol_weights: Dict[str, float] = None) -> Dict:
        """
        Calculate comprehensive portfolio metrics.

        Args:
            symbol_results: Dict of {symbol: {'returns': array, 'sharpe': float, ...}}
            symbol_weights: Optional weights for each symbol

        Returns:
            Dictionary with portfolio metrics
        """
        if not symbol_results:
            return {
                'portfolio_sharpe': 0.0,
                'avg_correlation': 0.0,
                'diversification_ratio': 1.0,
                'worst_symbol_sharpe': 0.0,
                'n_symbols': 0,
            }

        # Extract returns and sharpes
        symbol_returns = {s: r['returns'] for s, r in symbol_results.items() if 'returns' in r}
        symbol_sharpes = {s: r.get('sharpe', 0.0) for s, r in symbol_results.items()}

        # Calculate metrics
        portfolio_sharpe = PortfolioMetrics.calculate_portfolio_sharpe(
            symbol_returns, symbol_weights
        )

        avg_correlation = PortfolioMetrics.calculate_average_correlation(symbol_returns)

        diversification_ratio = PortfolioMetrics.calculate_diversification_ratio(
            symbol_returns, symbol_weights
        )

        worst_symbol_sharpe = PortfolioMetrics.calculate_worst_symbol_sharpe(symbol_sharpes)

        # Average symbol Sharpe
        avg_symbol_sharpe = np.mean(list(symbol_sharpes.values())) if symbol_sharpes else 0.0

        return {
            'portfolio_sharpe': portfolio_sharpe,
            'avg_correlation': avg_correlation,
            'diversification_ratio': diversification_ratio,
            'worst_symbol_sharpe': worst_symbol_sharpe,
            'avg_symbol_sharpe': avg_symbol_sharpe,
            'n_symbols': len(symbol_results),
            'symbol_sharpes': symbol_sharpes,
        }


class PortfolioObjective:
    """
    Portfolio-level objective function with penalties.

    Combines multiple metrics into a single objective for optimization.
    """

    def __init__(self, weights: Dict[str, float] = None, penalties: Dict[str, float] = None):
        """
        Initialize portfolio objective.

        Args:
            weights: Weights for each metric component
            penalties: Penalty weights for constraint violations
        """
        self.weights = weights or {
            'portfolio_sharpe': 0.50,
            'diversification_ratio': 0.20,
            'worst_symbol_sharpe': 0.15,
            'avg_correlation': -0.15,  # Negative = minimize
        }

        self.penalties = penalties or {
            'insufficient_trades': 0.5,
            'excessive_drawdown': 3.0,
            'high_correlation': 2.0,
            'parameter_instability': 1.0,
        }

    def calculate_objective(self, portfolio_metrics: Dict, penalty_info: Dict = None) -> float:
        """
        Calculate portfolio objective value.

        Args:
            portfolio_metrics: Portfolio metrics from calculate_portfolio_metrics()
            penalty_info: Optional dict with penalty information

        Returns:
            Objective value (higher is better)
        """
        # Base objective from weighted metrics
        objective = 0.0

        # Portfolio Sharpe
        objective += self.weights.get('portfolio_sharpe', 0) * portfolio_metrics.get('portfolio_sharpe', 0)

        # Diversification ratio
        objective += self.weights.get('diversification_ratio', 0) * portfolio_metrics.get('diversification_ratio', 0)

        # Worst symbol Sharpe (robustness)
        objective += self.weights.get('worst_symbol_sharpe', 0) * portfolio_metrics.get('worst_symbol_sharpe', 0)

        # Average correlation (minimize - negative weight)
        objective += self.weights.get('avg_correlation', 0) * portfolio_metrics.get('avg_correlation', 0)

        # Apply penalties
        if penalty_info:
            total_penalty = 0.0

            # Insufficient trades penalty
            if 'missing_trades' in penalty_info:
                total_penalty += self.penalties['insufficient_trades'] * penalty_info['missing_trades']

            # Excessive drawdown penalty
            if 'excess_drawdown' in penalty_info:
                total_penalty += self.penalties['excessive_drawdown'] * penalty_info['excess_drawdown']

            # High correlation penalty
            if 'correlation_penalty' in penalty_info:
                total_penalty += self.penalties['high_correlation'] * penalty_info['correlation_penalty']

            # Parameter instability penalty
            if 'param_instability' in penalty_info:
                total_penalty += self.penalties['parameter_instability'] * penalty_info['param_instability']

            objective -= total_penalty

        return objective

    def calculate_penalties(self, symbol_results: Dict[str, Dict],
                          portfolio_metrics: Dict,
                          min_trades_per_symbol: int = 5,
                          max_drawdown: float = 0.25,
                          max_correlation: float = 0.75) -> Dict:
        """
        Calculate penalties for constraint violations.

        Args:
            symbol_results: Dict of symbol results
            portfolio_metrics: Portfolio metrics
            min_trades_per_symbol: Minimum required trades per symbol
            max_drawdown: Maximum allowed drawdown
            max_correlation: Maximum allowed average correlation

        Returns:
            Dictionary with penalty components
        """
        penalties = {}

        # 1. Insufficient trades penalty
        missing_trades = 0
        for symbol, result in symbol_results.items():
            n_trades = result.get('n_trades', 0)
            if n_trades < min_trades_per_symbol:
                missing_trades += (min_trades_per_symbol - n_trades)
        penalties['missing_trades'] = missing_trades

        # 2. Excessive drawdown penalty
        max_dd_observed = 0.0
        for symbol, result in symbol_results.items():
            dd = result.get('max_drawdown', 0.0)
            max_dd_observed = max(max_dd_observed, dd)

        if max_dd_observed > max_drawdown:
            penalties['excess_drawdown'] = (max_dd_observed - max_drawdown)
        else:
            penalties['excess_drawdown'] = 0.0

        # 3. High correlation penalty
        avg_corr = portfolio_metrics.get('avg_correlation', 0.0)
        if avg_corr > max_correlation:
            penalties['correlation_penalty'] = (avg_corr - max_correlation)
        else:
            penalties['correlation_penalty'] = 0.0

        # 4. Parameter instability (placeholder - requires tracking across trials)
        penalties['param_instability'] = 0.0

        return penalties


def format_portfolio_report(portfolio_metrics: Dict, symbol_results: Dict = None) -> str:
    """
    Format portfolio metrics into a readable report.

    Args:
        portfolio_metrics: Portfolio metrics dictionary
        symbol_results: Optional individual symbol results

    Returns:
        Formatted report string
    """
    report = []
    report.append("=" * 70)
    report.append("PORTFOLIO PERFORMANCE REPORT")
    report.append("=" * 70)

    # Overall metrics
    report.append(f"\n📊 Portfolio Metrics:")
    report.append(f"   Portfolio Sharpe:        {portfolio_metrics['portfolio_sharpe']:.3f}")
    report.append(f"   Avg Correlation:         {portfolio_metrics['avg_correlation']:.3f}")
    report.append(f"   Diversification Ratio:   {portfolio_metrics['diversification_ratio']:.3f}")
    report.append(f"   Worst Symbol Sharpe:     {portfolio_metrics['worst_symbol_sharpe']:.3f}")
    report.append(f"   Avg Symbol Sharpe:       {portfolio_metrics['avg_symbol_sharpe']:.3f}")
    report.append(f"   Number of Symbols:       {portfolio_metrics['n_symbols']}")

    # Individual symbol performance
    if symbol_results:
        report.append(f"\n📈 Individual Symbol Performance:")
        for symbol, result in sorted(symbol_results.items()):
            sharpe = result.get('sharpe', 0.0)
            trades = result.get('n_trades', 0)
            dd = result.get('max_drawdown', 0.0)
            report.append(f"   {symbol:8s}: Sharpe={sharpe:6.3f}, Trades={trades:3d}, MaxDD={dd*100:5.1f}%")

    report.append("=" * 70)

    return "\n".join(report)
