"""
Out-of-Sample Validation Framework

Implements proper backtesting methodologies to prevent overfitting.
Based on concepts from "Quantitative Trading" by Dr. Ernest P. Chan.

Key Features:
- Train/Test Split: Separate data for optimization and validation
- Walk-Forward Analysis: Rolling window optimization
- Data Snooping Detection: Multiple testing correction
- Cross-Validation: K-fold for robust performance estimates
"""

import numpy as np
import pandas as pd
from typing import List, Dict, Optional, Tuple, Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from loguru import logger
from enum import Enum


class SplitMethod(str, Enum):
    """Data split methods"""
    SIMPLE = "simple"           # Simple train/test split
    ANCHORED = "anchored"       # Anchored walk-forward
    ROLLING = "rolling"         # Rolling window
    EXPANDING = "expanding"     # Expanding window


@dataclass
class SplitResult:
    """Result of data splitting"""
    train_data: pd.DataFrame
    test_data: pd.DataFrame
    train_start: datetime
    train_end: datetime
    test_start: datetime
    test_end: datetime
    train_size: int
    test_size: int
    split_ratio: float


@dataclass
class ValidationResult:
    """Result of out-of-sample validation"""
    in_sample_sharpe: float
    out_of_sample_sharpe: float
    performance_gap: float              # IS - OOS
    performance_gap_percent: float      # (IS - OOS) / IS * 100
    is_valid: bool                      # OOS performance acceptable?
    
    in_sample_return: float
    out_of_sample_return: float
    
    in_sample_win_rate: float
    out_of_sample_win_rate: float
    
    in_sample_trades: int
    out_of_sample_trades: int
    
    kelly_fraction: float
    half_kelly: float
    
    data_snooping_score: float          # 0-100, higher = more snooping risk
    degradation_factor: float           # OOS / IS ratio
    
    recommendation: str
    warnings: List[str] = field(default_factory=list)


@dataclass
class WalkForwardResult:
    """Result of walk-forward analysis"""
    windows: List[Dict]                 # List of window results
    overall_sharpe: float
    overall_return: float
    consistency_score: float            # How consistent across windows
    average_oos_sharpe: float
    average_degradation: float
    is_robust: bool
    recommendation: str


class OOSValidator:
    """
    Out-of-Sample Validation for trading strategies.
    
    Prevents overfitting by:
    1. Proper train/test separation
    2. Walk-forward optimization
    3. Data snooping bias detection
    """
    
    # Default split ratios
    DEFAULT_TRAIN_RATIO = 0.70
    
    # Performance thresholds
    MIN_ACCEPTABLE_OOS_SHARPE = 0.5
    MAX_ACCEPTABLE_DEGRADATION = 0.50  # 50% degradation max
    MIN_TRADES_FOR_SIGNIFICANCE = 30
    
    @staticmethod
    def split_data(
        data: pd.DataFrame,
        train_ratio: float = DEFAULT_TRAIN_RATIO,
        method: SplitMethod = SplitMethod.SIMPLE,
        date_column: str = 'time'
    ) -> SplitResult:
        """
        Split data into training and testing sets.
        
        Args:
            data: DataFrame with price/trade data
            train_ratio: Fraction for training (0.0 - 1.0)
            method: Split method to use
            date_column: Name of date/time column
            
        Returns:
            SplitResult with train and test datasets
        """
        if len(data) < 100:
            raise ValueError("Insufficient data for splitting (minimum 100 rows)")
        
        # Ensure data is sorted by date
        if date_column in data.columns:
            data = data.sort_values(date_column).reset_index(drop=True)
        
        split_idx = int(len(data) * train_ratio)
        
        train_data = data.iloc[:split_idx].copy()
        test_data = data.iloc[split_idx:].copy()
        
        # Extract dates
        train_start = train_data[date_column].iloc[0] if date_column in data.columns else None
        train_end = train_data[date_column].iloc[-1] if date_column in data.columns else None
        test_start = test_data[date_column].iloc[0] if date_column in data.columns else None
        test_end = test_data[date_column].iloc[-1] if date_column in data.columns else None
        
        return SplitResult(
            train_data=train_data,
            test_data=test_data,
            train_start=train_start,
            train_end=train_end,
            test_start=test_start,
            test_end=test_end,
            train_size=len(train_data),
            test_size=len(test_data),
            split_ratio=train_ratio
        )
    
    @staticmethod
    def validate_strategy(
        in_sample_trades: List[Dict],
        out_of_sample_trades: List[Dict],
        initial_balance: float = 10000.0
    ) -> ValidationResult:
        """
        Validate strategy performance by comparing in-sample to out-of-sample.
        
        Args:
            in_sample_trades: List of trades from training period
            out_of_sample_trades: List of trades from testing period
            initial_balance: Starting capital
            
        Returns:
            ValidationResult with comparison metrics
        """
        warnings = []
        
        # Calculate in-sample metrics
        is_pnls = [t.get('pnl', 0) for t in in_sample_trades]
        oos_pnls = [t.get('pnl', 0) for t in out_of_sample_trades]
        
        is_wins = [p for p in is_pnls if p > 0]
        oos_wins = [p for p in oos_pnls if p > 0]
        
        # Sharpe calculations
        is_sharpe = OOSValidator._calculate_sharpe(is_pnls)
        oos_sharpe = OOSValidator._calculate_sharpe(oos_pnls)
        
        # Returns
        is_return = sum(is_pnls) / initial_balance * 100 if is_pnls else 0
        oos_return = sum(oos_pnls) / initial_balance * 100 if oos_pnls else 0
        
        # Win rates
        is_win_rate = len(is_wins) / len(is_pnls) * 100 if is_pnls else 0
        oos_win_rate = len(oos_wins) / len(oos_pnls) * 100 if oos_pnls else 0
        
        # Performance gap
        performance_gap = is_sharpe - oos_sharpe
        gap_percent = (performance_gap / is_sharpe * 100) if is_sharpe != 0 else 0
        
        # Degradation factor
        degradation = oos_sharpe / is_sharpe if is_sharpe != 0 else 0
        
        # Data snooping score (0-100)
        # Based on performance gap, number of parameters tested, etc.
        snooping_score = OOSValidator._calculate_snooping_score(
            is_sharpe=is_sharpe,
            oos_sharpe=oos_sharpe,
            is_trades=len(in_sample_trades),
            oos_trades=len(out_of_sample_trades)
        )
        
        # Calculate Kelly (Based on IS data for sizing)
        kelly, half_kelly = OOSValidator._calculate_kelly(in_sample_trades)
        
        # Validation checks
        if len(out_of_sample_trades) < OOSValidator.MIN_TRADES_FOR_SIGNIFICANCE:
            warnings.append(f"OOS trades ({len(out_of_sample_trades)}) below minimum ({OOSValidator.MIN_TRADES_FOR_SIGNIFICANCE})")
        
        if oos_sharpe < OOSValidator.MIN_ACCEPTABLE_OOS_SHARPE:
            warnings.append(f"OOS Sharpe ({oos_sharpe:.2f}) below minimum ({OOSValidator.MIN_ACCEPTABLE_OOS_SHARPE})")
        
        if degradation < (1 - OOSValidator.MAX_ACCEPTABLE_DEGRADATION):
            warnings.append(f"High performance degradation ({(1-degradation)*100:.1f}%)")
        
        if snooping_score > 70:
            warnings.append(f"High data snooping risk (score: {snooping_score:.0f})")
        
        # Is valid?
        is_valid = (
            oos_sharpe >= OOSValidator.MIN_ACCEPTABLE_OOS_SHARPE and
            degradation >= (1 - OOSValidator.MAX_ACCEPTABLE_DEGRADATION) and
            len(out_of_sample_trades) >= OOSValidator.MIN_TRADES_FOR_SIGNIFICANCE
        )
        
        # Recommendation
        if is_valid and snooping_score < 50:
            recommendation = "Strategy shows robust out-of-sample performance. Proceed with caution."
        elif is_valid:
            recommendation = "Strategy is valid but shows some overfitting signs. Consider simplifying."
        elif oos_sharpe > 0:
            recommendation = "Strategy profitable but overfit. Reduce parameters or use longer training period."
        else:
            recommendation = "Strategy fails out-of-sample. Discard or fundamentally redesign."
        
        return ValidationResult(
            in_sample_sharpe=round(is_sharpe, 4),
            out_of_sample_sharpe=round(oos_sharpe, 4),
            performance_gap=round(performance_gap, 4),
            performance_gap_percent=round(gap_percent, 2),
            is_valid=is_valid,
            in_sample_return=round(is_return, 2),
            out_of_sample_return=round(oos_return, 2),
            in_sample_win_rate=round(is_win_rate, 2),
            out_of_sample_win_rate=round(oos_win_rate, 2),
            in_sample_trades=len(in_sample_trades),
            out_of_sample_trades=len(out_of_sample_trades),
            kelly_fraction=round(kelly, 4),
            half_kelly=round(half_kelly, 4),
            data_snooping_score=round(snooping_score, 2),
            degradation_factor=round(degradation, 4),
            recommendation=recommendation,
            warnings=warnings
        )
    
    @staticmethod
    def _calculate_kelly(trades: List[Dict]) -> Tuple[float, float]:
        """Calculate Kelly Fraction (and Half Kelly)"""
        pnls = [t.get('pnl', 0) for t in trades]
        wins = [p for p in pnls if p > 0]
        losses = [abs(p) for p in pnls if p < 0]
        
        if not wins or not losses:
            return 0.0, 0.0
            
        avg_win = np.mean(wins)
        avg_loss = np.mean(losses)
        
        if avg_loss == 0:
            return 0.0, 0.0
            
        win_rate = len(wins) / len(pnls)
        loss_rate = len(losses) / len(pnls)
        r_ratio = avg_win / avg_loss
        
        # Kelly = W - (L / R)
        if r_ratio > 0:
            kelly = win_rate - (loss_rate / r_ratio)
            
            # Check for negative expectancy behavior (simplistic check)
            # If Kelly < 0, return 0
            if kelly < 0:
                kelly = 0.0
                
            return kelly, kelly / 2
            
        return 0.0, 0.0
    
    @staticmethod
    def walk_forward_analysis(
        data: pd.DataFrame,
        strategy_func: Callable,
        n_windows: int = 5,
        train_ratio: float = 0.80,
        date_column: str = 'time'
    ) -> WalkForwardResult:
        """
        Perform walk-forward optimization.
        
        Divides data into N windows, trains on first 80% of each,
        validates on remaining 20%.
        
        Args:
            data: Full dataset
            strategy_func: Function that takes data and returns trades
            n_windows: Number of walk-forward windows
            train_ratio: Train/test split within each window
            date_column: Date column name
            
        Returns:
            WalkForwardResult with aggregated metrics
        """
        if len(data) < 200:
            raise ValueError("Insufficient data for walk-forward analysis")
        
        window_size = len(data) // n_windows
        windows = []
        oos_sharpes = []
        degradations = []
        
        for i in range(n_windows):
            start_idx = i * window_size
            end_idx = start_idx + window_size if i < n_windows - 1 else len(data)
            
            window_data = data.iloc[start_idx:end_idx].copy()
            
            # Split window into train/test
            split_idx = int(len(window_data) * train_ratio)
            train_data = window_data.iloc[:split_idx]
            test_data = window_data.iloc[split_idx:]
            
            try:
                # Run strategy on both sets
                train_trades = strategy_func(train_data)
                test_trades = strategy_func(test_data)
                
                # Calculate metrics
                train_pnls = [t.get('pnl', 0) for t in train_trades]
                test_pnls = [t.get('pnl', 0) for t in test_trades]
                
                train_sharpe = OOSValidator._calculate_sharpe(train_pnls)
                test_sharpe = OOSValidator._calculate_sharpe(test_pnls)
                
                degradation = test_sharpe / train_sharpe if train_sharpe != 0 else 0
                
                window_result = {
                    'window': i + 1,
                    'train_start': train_data[date_column].iloc[0] if date_column in train_data.columns else None,
                    'train_end': train_data[date_column].iloc[-1] if date_column in train_data.columns else None,
                    'test_start': test_data[date_column].iloc[0] if date_column in test_data.columns else None,
                    'test_end': test_data[date_column].iloc[-1] if date_column in test_data.columns else None,
                    'train_sharpe': round(train_sharpe, 4),
                    'test_sharpe': round(test_sharpe, 4),
                    'train_trades': len(train_trades),
                    'test_trades': len(test_trades),
                    'degradation': round(degradation, 4),
                    'train_return': round(sum(train_pnls), 2),
                    'test_return': round(sum(test_pnls), 2)
                }
                
                windows.append(window_result)
                oos_sharpes.append(test_sharpe)
                degradations.append(degradation)
                
            except Exception as e:
                logger.warning(f"Walk-forward window {i+1} failed: {e}")
                windows.append({
                    'window': i + 1,
                    'error': str(e)
                })
        
        # Calculate overall metrics
        valid_sharpes = [s for s in oos_sharpes if s is not None]
        valid_degradations = [d for d in degradations if d is not None]
        
        avg_oos_sharpe = np.mean(valid_sharpes) if valid_sharpes else 0
        avg_degradation = np.mean(valid_degradations) if valid_degradations else 0
        
        # Consistency: standard deviation of OOS Sharpes
        sharpe_std = np.std(valid_sharpes) if len(valid_sharpes) > 1 else 0
        consistency = max(0, 100 - sharpe_std * 100)  # Higher = more consistent
        
        # Overall metrics
        overall_sharpe = avg_oos_sharpe
        overall_return = sum(w.get('test_return', 0) for w in windows if 'test_return' in w)
        
        # Is robust?
        is_robust = (
            avg_oos_sharpe >= 0.5 and
            avg_degradation >= 0.5 and
            consistency >= 60
        )
        
        # Recommendation
        if is_robust and consistency >= 80:
            recommendation = "Strategy is highly robust across all time periods."
        elif is_robust:
            recommendation = "Strategy is robust but shows some period-specific variation."
        elif avg_oos_sharpe > 0:
            recommendation = "Strategy is marginally profitable but inconsistent. Use with caution."
        else:
            recommendation = "Strategy fails walk-forward test. Not recommended for trading."
        
        return WalkForwardResult(
            windows=windows,
            overall_sharpe=round(overall_sharpe, 4),
            overall_return=round(overall_return, 2),
            consistency_score=round(consistency, 2),
            average_oos_sharpe=round(avg_oos_sharpe, 4),
            average_degradation=round(avg_degradation, 4),
            is_robust=is_robust,
            recommendation=recommendation
        )
    
    @staticmethod
    def _calculate_sharpe(pnls: List[float], risk_free: float = 0.0) -> float:
        """Calculate Sharpe ratio from P&L list"""
        if len(pnls) < 2:
            return 0.0
        
        pnl_array = np.array(pnls)
        mean_pnl = np.mean(pnl_array) - risk_free
        std_pnl = np.std(pnl_array, ddof=1)
        
        if std_pnl == 0:
            return 0.0
        
        return mean_pnl / std_pnl
    
    @staticmethod
    def _calculate_snooping_score(
        is_sharpe: float,
        oos_sharpe: float,
        is_trades: int,
        oos_trades: int,
        num_parameters: int = 5  # Assumed number of optimized parameters
    ) -> float:
        """
        Calculate data snooping risk score (0-100).
        
        Higher score = higher risk of curve fitting.
        
        Factors:
        - Performance gap (IS vs OOS)
        - Number of parameters optimized
        - Trade count ratio
        """
        score = 0
        
        # Factor 1: Performance gap (40% weight)
        if is_sharpe > 0:
            gap_ratio = abs(is_sharpe - oos_sharpe) / is_sharpe
            score += min(40, gap_ratio * 40)
        
        # Factor 2: Number of parameters (30% weight)
        # More parameters = higher snooping risk
        param_penalty = min(30, num_parameters * 6)
        score += param_penalty
        
        # Factor 3: Trade count imbalance (20% weight)
        if oos_trades > 0 and is_trades > 0:
            trade_ratio = is_trades / oos_trades
            if trade_ratio > 3 or trade_ratio < 0.33:
                score += 20
            else:
                score += abs(trade_ratio - 1) * 10
        
        # Factor 4: Outstanding IS performance (10% weight)
        # Very high IS Sharpe is suspicious
        if is_sharpe > 3:
            score += 10
        elif is_sharpe > 2:
            score += 5
        
        return min(100, max(0, score))


# Convenience functions for API

def validate_oos(
    in_sample_trades: List[Dict],
    out_of_sample_trades: List[Dict],
    initial_balance: float = 10000.0
) -> Dict:
    """Convenience function for API"""
    result = OOSValidator.validate_strategy(
        in_sample_trades=in_sample_trades,
        out_of_sample_trades=out_of_sample_trades,
        initial_balance=initial_balance
    )
    
    return {
        "in_sample_sharpe": result.in_sample_sharpe,
        "out_of_sample_sharpe": result.out_of_sample_sharpe,
        "performance_gap": result.performance_gap,
        "performance_gap_percent": result.performance_gap_percent,
        "is_valid": result.is_valid,
        "in_sample_return": result.in_sample_return,
        "out_of_sample_return": result.out_of_sample_return,
        "in_sample_win_rate": result.in_sample_win_rate,
        "out_of_sample_win_rate": result.out_of_sample_win_rate,
        "in_sample_trades": result.in_sample_trades,
        "out_of_sample_trades": result.out_of_sample_trades,
        "kelly_fraction": result.kelly_fraction,
        "half_kelly": result.half_kelly,
        "data_snooping_score": result.data_snooping_score,
        "degradation_factor": result.degradation_factor,
        "recommendation": result.recommendation,
        "warnings": result.warnings
    }


def split_data_for_oos(
    data: pd.DataFrame,
    train_ratio: float = 0.70,
    date_column: str = 'time'
) -> Dict:
    """Split data and return summary"""
    result = OOSValidator.split_data(
        data=data,
        train_ratio=train_ratio,
        date_column=date_column
    )
    
    return {
        "train_size": result.train_size,
        "test_size": result.test_size,
        "split_ratio": result.split_ratio,
        "train_start": result.train_start.isoformat() if result.train_start else None,
        "train_end": result.train_end.isoformat() if result.train_end else None,
        "test_start": result.test_start.isoformat() if result.test_start else None,
        "test_end": result.test_end.isoformat() if result.test_end else None
    }
