"""
Kelly Criterion Optimizer

Implements the Kelly Formula for optimal position sizing and capital allocation.
Based on concepts from "Quantitative Trading" by Dr. Ernest P. Chan.

The Kelly formula maximizes long-term compounded growth rate:
    f* = m / σ²

Where:
    f* = optimal fraction of capital to wager
    m  = mean excess return
    σ² = variance of returns

For multi-strategy allocation:
    F* = C⁻¹ × M

Where:
    F* = optimal allocation vector
    C  = covariance matrix of returns
    M  = mean returns vector
"""

import numpy as np
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from loguru import logger


@dataclass
class KellyResult:
    """Result of Kelly calculation"""
    optimal_leverage: float           # Optimal f* multiplier
    half_kelly: float                 # Conservative half-Kelly
    quarter_kelly: float              # Very conservative quarter-Kelly
    recommended_leverage: float       # Recommended (usually half-Kelly)
    expected_growth_rate: float       # g = r + S²/2
    sharpe_ratio: float               # Annual Sharpe ratio
    win_rate: float                   # Win rate percentage
    avg_win: float                    # Average winning trade
    avg_loss: float                   # Average losing trade
    risk_reward_ratio: float          # R:R ratio
    optimal_position_dollars: float   # Calculated position size in $
    max_risk_dollars: float           # Max $ to risk per trade
    warnings: List[str]               # Any warnings for the user


class KellyOptimizer:
    """
    Calculate optimal position sizing using the Kelly Criterion.
    
    The Kelly Criterion provides the mathematically optimal fraction of 
    capital to allocate to maximize long-term wealth growth.
    """
    
    # Risk-free rate (annualized, 4% default)
    DEFAULT_RISK_FREE_RATE = 0.04
    
    # Maximum leverage warning threshold
    MAX_SAFE_LEVERAGE = 4.0
    
    # Trading periods per year (252 trading days)
    TRADING_DAYS_PER_YEAR = 252
    
    @staticmethod
    def calculate_kelly_from_trades(
        pnl_list: List[float],
        account_balance: float = 10000.0,
        risk_free_rate: float = DEFAULT_RISK_FREE_RATE,
        use_half_kelly: bool = True
    ) -> KellyResult:
        """
        Calculate optimal Kelly leverage from a list of trade P&L values.
        
        This is the main method for calculating position sizing from historical trades.
        
        Args:
            pnl_list: List of P&L values from trades (in dollars)
            account_balance: Current account balance
            risk_free_rate: Annual risk-free rate (default 4%)
            use_half_kelly: If True, recommend half-Kelly for safety
            
        Returns:
            KellyResult with all calculated values
        """
        warnings = []
        
        if len(pnl_list) < 10:
            warnings.append("Warning: Less than 10 trades - Kelly estimate may be unreliable")
        
        if not pnl_list:
            return KellyResult(
                optimal_leverage=0.0,
                half_kelly=0.0,
                quarter_kelly=0.0,
                recommended_leverage=0.0,
                expected_growth_rate=0.0,
                sharpe_ratio=0.0,
                win_rate=0.0,
                avg_win=0.0,
                avg_loss=0.0,
                risk_reward_ratio=0.0,
                optimal_position_dollars=0.0,
                max_risk_dollars=0.0,
                warnings=["No trades provided"]
            )
        
        pnl_array = np.array(pnl_list)
        
        # Calculate base statistics
        wins = pnl_array[pnl_array > 0]
        losses = pnl_array[pnl_array < 0]
        
        win_rate = len(wins) / len(pnl_array) * 100 if len(pnl_array) > 0 else 0
        avg_win = np.mean(wins) if len(wins) > 0 else 0
        avg_loss = abs(np.mean(losses)) if len(losses) > 0 else 0
        risk_reward = avg_win / avg_loss if avg_loss > 0 else 0
        
        # Convert P&L to returns (percentage of balance)
        # Note: This assumes each trade used the full balance
        # For better accuracy, use actual position sizes
        returns = pnl_array / account_balance
        
        # Mean return and standard deviation
        mean_return = np.mean(returns)
        std_return = np.std(returns, ddof=1) if len(returns) > 1 else 1
        
        # Variance
        variance = std_return ** 2
        
        # Kelly Formula: f* = m / σ²
        if variance > 0 and mean_return > 0:
            optimal_f = mean_return / variance
        else:
            optimal_f = 0.0
            if mean_return <= 0:
                warnings.append("Negative or zero mean return - Kelly suggests no allocation")
        
        # Half and Quarter Kelly for safety
        half_kelly = optimal_f / 2
        quarter_kelly = optimal_f / 4
        
        # Recommended leverage
        recommended = half_kelly if use_half_kelly else optimal_f
        
        # Safety checks
        if optimal_f > KellyOptimizer.MAX_SAFE_LEVERAGE:
            warnings.append(f"Optimal leverage ({optimal_f:.2f}x) exceeds safe threshold ({KellyOptimizer.MAX_SAFE_LEVERAGE}x)")
        
        if optimal_f < 0:
            warnings.append("Negative Kelly suggests strategy has negative expectancy")
            optimal_f = 0.0
            half_kelly = 0.0
            quarter_kelly = 0.0
            recommended = 0.0
        
        # Calculate Sharpe Ratio (annualized)
        # Assuming returns are per-trade, estimate trades per year
        if std_return > 0:
            sharpe_per_trade = mean_return / std_return
            # Annualize based on estimated trades per year
            # Conservative estimate: 100 trades per year
            estimated_trades_per_year = min(len(pnl_array), 100)
            sharpe_annual = sharpe_per_trade * np.sqrt(estimated_trades_per_year)
        else:
            sharpe_annual = 0.0
        
        # Expected compounded growth rate: g = r + S²/2
        # This is the maximum achievable with optimal Kelly leverage
        expected_growth = risk_free_rate + (sharpe_annual ** 2) / 2
        
        # Calculate optimal position size in dollars
        optimal_position = recommended * account_balance
        
        # Maximum risk per trade (assuming 2% max risk default)
        max_risk = min(account_balance * 0.02, optimal_position * 0.1)
        
        return KellyResult(
            optimal_leverage=round(optimal_f, 4),
            half_kelly=round(half_kelly, 4),
            quarter_kelly=round(quarter_kelly, 4),
            recommended_leverage=round(recommended, 4),
            expected_growth_rate=round(expected_growth * 100, 2),  # As percentage
            sharpe_ratio=round(sharpe_annual, 4),
            win_rate=round(win_rate, 2),
            avg_win=round(avg_win, 2),
            avg_loss=round(avg_loss, 2),
            risk_reward_ratio=round(risk_reward, 2),
            optimal_position_dollars=round(optimal_position, 2),
            max_risk_dollars=round(max_risk, 2),
            warnings=warnings
        )
    
    @staticmethod
    def calculate_kelly_from_winrate(
        win_rate: float,
        avg_win: float,
        avg_loss: float,
        account_balance: float = 10000.0
    ) -> KellyResult:
        """
        Calculate Kelly from win rate and average win/loss.
        
        Uses the discrete Kelly formula:
            f* = (bp - q) / b
            
        Where:
            b = odds received (avg_win / avg_loss)
            p = probability of winning (win_rate)
            q = probability of losing (1 - p)
            
        Args:
            win_rate: Win rate as percentage (e.g., 60 for 60%)
            avg_win: Average winning trade in dollars
            avg_loss: Average losing trade in dollars (positive number)
            account_balance: Current account balance
            
        Returns:
            KellyResult
        """
        warnings = []
        
        # Convert to decimal
        p = win_rate / 100
        q = 1 - p
        
        # Odds ratio (b)
        if avg_loss > 0:
            b = avg_win / avg_loss
        else:
            warnings.append("Average loss is zero - cannot calculate Kelly")
            return KellyResult(
                optimal_leverage=0.0, half_kelly=0.0, quarter_kelly=0.0,
                recommended_leverage=0.0, expected_growth_rate=0.0,
                sharpe_ratio=0.0, win_rate=win_rate, avg_win=avg_win,
                avg_loss=avg_loss, risk_reward_ratio=0.0,
                optimal_position_dollars=0.0, max_risk_dollars=0.0,
                warnings=warnings
            )
        
        # Kelly formula: f* = (bp - q) / b
        optimal_f = (b * p - q) / b
        
        # Alternatively: f* = p - (q / b)
        # Both formulas are equivalent
        
        if optimal_f < 0:
            warnings.append("Negative Kelly suggests unprofitable strategy - reconsider parameters")
            optimal_f = 0.0
        
        half_kelly = optimal_f / 2
        quarter_kelly = optimal_f / 4
        recommended = half_kelly  # Default to half-Kelly for safety
        
        if optimal_f > KellyOptimizer.MAX_SAFE_LEVERAGE:
            warnings.append(f"High leverage warning: {optimal_f:.2f}x exceeds {KellyOptimizer.MAX_SAFE_LEVERAGE}x")
        
        # Estimate Sharpe from win rate and R:R
        # Expectancy = p * avg_win - q * avg_loss
        expectancy = p * avg_win - q * avg_loss
        
        # Approximate variance (simplified)
        estimated_variance = (p * avg_win**2 + q * avg_loss**2 - expectancy**2)
        estimated_std = np.sqrt(estimated_variance) if estimated_variance > 0 else 1
        
        # Approximate Sharpe (per trade)
        sharpe_per_trade = expectancy / estimated_std if estimated_std > 0 else 0
        sharpe_annual = sharpe_per_trade * np.sqrt(100)  # Assume 100 trades/year
        
        # Expected growth rate
        expected_growth = 0.04 + (sharpe_annual ** 2) / 2
        
        # Position sizing
        optimal_position = recommended * account_balance
        max_risk = min(account_balance * 0.02, optimal_position * avg_loss / avg_win) if avg_win > 0 else 0
        
        return KellyResult(
            optimal_leverage=round(optimal_f, 4),
            half_kelly=round(half_kelly, 4),
            quarter_kelly=round(quarter_kelly, 4),
            recommended_leverage=round(recommended, 4),
            expected_growth_rate=round(expected_growth * 100, 2),
            sharpe_ratio=round(sharpe_annual, 4),
            win_rate=round(win_rate, 2),
            avg_win=round(avg_win, 2),
            avg_loss=round(avg_loss, 2),
            risk_reward_ratio=round(b, 2),
            optimal_position_dollars=round(optimal_position, 2),
            max_risk_dollars=round(max_risk, 2),
            warnings=warnings
        )
    
    @staticmethod
    def calculate_multi_strategy_allocation(
        strategy_returns: List[List[float]],
        strategy_names: Optional[List[str]] = None,
        risk_free_rate: float = DEFAULT_RISK_FREE_RATE
    ) -> Dict:
        """
        Calculate optimal capital allocation across multiple strategies.
        
        Uses the matrix formula: F* = C⁻¹ × M
        
        Where:
            F* = optimal allocation vector
            C  = covariance matrix of strategy returns
            M  = mean returns vector
            
        Args:
            strategy_returns: List of return lists, one per strategy
            strategy_names: Optional names for each strategy
            risk_free_rate: Annual risk-free rate
            
        Returns:
            Dict with allocation percentages and analysis
        """
        n_strategies = len(strategy_returns)
        
        if n_strategies == 0:
            return {"error": "No strategies provided", "allocations": {}}
        
        if strategy_names is None:
            strategy_names = [f"Strategy_{i+1}" for i in range(n_strategies)]
        
        # Convert to numpy arrays
        returns_matrix = []
        min_length = min(len(r) for r in strategy_returns)
        
        for returns in strategy_returns:
            # Truncate to common length
            returns_matrix.append(np.array(returns[:min_length]))
        
        returns_matrix = np.array(returns_matrix)
        
        # Calculate mean excess returns for each strategy
        mean_returns = np.mean(returns_matrix, axis=1) - risk_free_rate / 252  # Daily risk-free rate
        
        # Calculate covariance matrix
        covariance_matrix = np.cov(returns_matrix)
        
        # Handle single strategy case
        if n_strategies == 1:
            variance = np.var(returns_matrix[0], ddof=1)
            if variance > 0 and mean_returns[0] > 0:
                optimal_f = mean_returns[0] / variance
            else:
                optimal_f = 0.0
            
            return {
                "allocations": {strategy_names[0]: round(optimal_f, 4)},
                "total_leverage": round(optimal_f, 4),
                "sharpe_portfolio": 0.0,
                "expected_growth": 0.0,
                "correlation_matrix": [[1.0]]
            }
        
        try:
            # F* = C⁻¹ × M
            cov_inverse = np.linalg.inv(covariance_matrix)
            optimal_allocations = np.dot(cov_inverse, mean_returns)
        except np.linalg.LinAlgError:
            # Singular matrix - strategies are too correlated
            logger.warning("Covariance matrix is singular - strategies may be highly correlated")
            # Fall back to equal weight
            optimal_allocations = np.ones(n_strategies) / n_strategies
        
        # Calculate portfolio metrics
        total_leverage = np.sum(np.abs(optimal_allocations))
        
        # Portfolio Sharpe: S = sqrt(F*' × C × F*)
        portfolio_variance = np.dot(optimal_allocations.T, np.dot(covariance_matrix, optimal_allocations))
        portfolio_sharpe = np.sqrt(portfolio_variance) if portfolio_variance > 0 else 0
        
        # Expected growth rate: g = r + S²/2
        expected_growth = risk_free_rate + (portfolio_sharpe ** 2) / 2
        
        # Correlation matrix
        std_devs = np.sqrt(np.diag(covariance_matrix))
        correlation_matrix = covariance_matrix / np.outer(std_devs, std_devs)
        
        # Build result
        allocations = {}
        for i, name in enumerate(strategy_names):
            allocations[name] = {
                "optimal_f": round(optimal_allocations[i], 4),
                "half_kelly": round(optimal_allocations[i] / 2, 4),
                "mean_return": round(mean_returns[i] * 252 * 100, 2),  # Annualized %
                "std_dev": round(std_devs[i] * np.sqrt(252) * 100, 2)  # Annualized %
            }
        
        return {
            "allocations": allocations,
            "total_leverage": round(total_leverage, 4),
            "half_kelly_total": round(total_leverage / 2, 4),
            "sharpe_portfolio": round(portfolio_sharpe * np.sqrt(252), 4),  # Annualized
            "expected_growth": round(expected_growth * 100, 2),  # As percentage
            "correlation_matrix": correlation_matrix.tolist(),
            "warnings": [] if total_leverage < KellyOptimizer.MAX_SAFE_LEVERAGE else 
                       [f"Total leverage {total_leverage:.2f}x exceeds safe threshold"]
        }
    
    @staticmethod
    def calculate_position_size(
        kelly_result: KellyResult,
        account_balance: float,
        entry_price: float,
        stop_loss_pips: float,
        pip_value: float = 10.0,  # Standard lot pip value for forex
        use_kelly_fraction: str = "half"  # "full", "half", "quarter"
    ) -> Dict:
        """
        Calculate specific position size for a trade using Kelly.
        
        Args:
            kelly_result: Result from Kelly calculation
            account_balance: Current account balance
            entry_price: Entry price for the trade
            stop_loss_pips: Stop loss distance in pips
            pip_value: Dollar value per pip per lot
            use_kelly_fraction: Which Kelly fraction to use
            
        Returns:
            Dict with lot size, risk amount, etc.
        """
        # Select Kelly fraction
        if use_kelly_fraction == "full":
            leverage = kelly_result.optimal_leverage
        elif use_kelly_fraction == "quarter":
            leverage = kelly_result.quarter_kelly
        else:
            leverage = kelly_result.half_kelly  # default to half
        
        # Maximum position value based on Kelly
        max_position_value = account_balance * leverage
        
        # Risk per trade (based on stop loss)
        risk_per_lot = stop_loss_pips * pip_value
        
        # Calculate lot size
        if risk_per_lot > 0:
            # Method 1: Based on Kelly allocation
            kelly_lot_size = max_position_value / (entry_price * 100000)  # Forex standard lot
            
            # Method 2: Based on risk tolerance (2% max default)
            max_risk = account_balance * 0.02  # 2% risk
            risk_based_lot_size = max_risk / risk_per_lot
            
            # Use the smaller of the two for safety
            recommended_lot_size = min(kelly_lot_size, risk_based_lot_size)
        else:
            recommended_lot_size = 0.01  # Minimum lot
        
        # Round to valid lot size
        recommended_lot_size = max(0.01, round(recommended_lot_size, 2))
        
        # Calculate actual risk
        actual_risk = recommended_lot_size * risk_per_lot
        risk_percent = (actual_risk / account_balance) * 100
        
        return {
            "recommended_lots": recommended_lot_size,
            "kelly_fraction_used": use_kelly_fraction,
            "leverage_used": round(leverage, 4),
            "max_position_value": round(max_position_value, 2),
            "risk_amount": round(actual_risk, 2),
            "risk_percent": round(risk_percent, 2),
            "stop_loss_pips": stop_loss_pips,
            "pip_value_per_lot": pip_value
        }


# Convenience functions for API
def calculate_kelly(
    pnl_list: Optional[List[float]] = None,
    win_rate: Optional[float] = None,
    avg_win: Optional[float] = None,
    avg_loss: Optional[float] = None,
    account_balance: float = 10000.0
) -> Dict:
    """
    Convenience function to calculate Kelly from either trades or statistics.
    
    Provide either pnl_list OR (win_rate, avg_win, avg_loss).
    """
    if pnl_list is not None:
        result = KellyOptimizer.calculate_kelly_from_trades(
            pnl_list=pnl_list,
            account_balance=account_balance
        )
    elif all(v is not None for v in [win_rate, avg_win, avg_loss]):
        result = KellyOptimizer.calculate_kelly_from_winrate(
            win_rate=win_rate,
            avg_win=avg_win,
            avg_loss=avg_loss,
            account_balance=account_balance
        )
    else:
        return {"error": "Provide either pnl_list or (win_rate, avg_win, avg_loss)"}
    
    # Convert dataclass to dict
    return {
        "optimal_leverage": result.optimal_leverage,
        "half_kelly": result.half_kelly,
        "quarter_kelly": result.quarter_kelly,
        "recommended_leverage": result.recommended_leverage,
        "expected_growth_rate": result.expected_growth_rate,
        "sharpe_ratio": result.sharpe_ratio,
        "win_rate": result.win_rate,
        "avg_win": result.avg_win,
        "avg_loss": result.avg_loss,
        "risk_reward_ratio": result.risk_reward_ratio,
        "optimal_position_dollars": result.optimal_position_dollars,
        "max_risk_dollars": result.max_risk_dollars,
        "warnings": result.warnings
    }
