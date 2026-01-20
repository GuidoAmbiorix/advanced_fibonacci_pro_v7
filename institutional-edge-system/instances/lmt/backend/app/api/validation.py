"""
============================================================================
OOS Validation & Bias Detection API Endpoints
============================================================================
Provides out-of-sample testing and bias detection for backtesting.
Based on "Quantitative Trading" by Dr. Ernest P. Chan.
"""

from typing import List, Optional, Dict
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from app.api import database
from app.backtesting.oos_validation import OOSValidator, validate_oos
from app.backtesting.bias_detector import BiasDetector, check_biases

router = APIRouter()


# ============================================================================
# Request/Response Models
# ============================================================================

class TradeData(BaseModel):
    """Trade data for validation"""
    entry_time: Optional[str] = None
    exit_time: Optional[str] = None
    entry_price: float
    exit_price: float
    pnl: float
    type: str = "BUY"
    exit_reason: Optional[str] = None


class OOSValidateRequest(BaseModel):
    """Request for OOS validation"""
    in_sample_trades: List[TradeData]
    out_of_sample_trades: List[TradeData]
    initial_balance: float = Field(default=10000.0, gt=0)


class BiasCheckRequest(BaseModel):
    """Request for bias checking"""
    trades: List[TradeData]
    strategy_params: Optional[Dict] = None


class SplitDataRequest(BaseModel):
    """Request for data splitting"""
    prices: List[float]
    timestamps: Optional[List[str]] = None
    train_ratio: float = Field(default=0.70, ge=0.5, le=0.9)


# ============================================================================
# OOS Validation Endpoints
# ============================================================================

@router.post("/oos/validate")
def validate_out_of_sample(request: OOSValidateRequest):
    """
    Validate strategy by comparing in-sample to out-of-sample performance.
    
    Returns metrics comparing training vs testing performance including:
    - Sharpe ratio comparison
    - Performance degradation
    - Data snooping score
    - Validation recommendation
    """
    is_trades = [t.dict() for t in request.in_sample_trades]
    oos_trades = [t.dict() for t in request.out_of_sample_trades]
    
    result = validate_oos(
        in_sample_trades=is_trades,
        out_of_sample_trades=oos_trades,
        initial_balance=request.initial_balance
    )
    
    return {
        **result,
        "timestamp": datetime.utcnow().isoformat()
    }


@router.get("/oos/thresholds")
def get_oos_thresholds():
    """
    Get the current thresholds used for OOS validation.
    """
    return {
        "min_acceptable_oos_sharpe": OOSValidator.MIN_ACCEPTABLE_OOS_SHARPE,
        "max_acceptable_degradation": OOSValidator.MAX_ACCEPTABLE_DEGRADATION,
        "min_trades_for_significance": OOSValidator.MIN_TRADES_FOR_SIGNIFICANCE,
        "description": {
            "min_acceptable_oos_sharpe": "Minimum Sharpe ratio required in OOS period",
            "max_acceptable_degradation": "Maximum allowed performance drop from IS to OOS",
            "min_trades_for_significance": "Minimum trades needed for statistical significance"
        }
    }


@router.post("/oos/split-preview")
def preview_data_split(request: SplitDataRequest):
    """
    Preview how data would be split for OOS testing.
    
    Returns split indices and sizes without performing actual splitting.
    """
    total = len(request.prices)
    split_idx = int(total * request.train_ratio)
    
    return {
        "total_samples": total,
        "train_size": split_idx,
        "test_size": total - split_idx,
        "train_ratio": request.train_ratio,
        "train_range": f"0 to {split_idx - 1}",
        "test_range": f"{split_idx} to {total - 1}",
        "recommendation": (
            "Adequate split" if (total - split_idx) >= 30 
            else "Warning: Test set may be too small for reliable results"
        )
    }


# ============================================================================
# Bias Detection Endpoints
# ============================================================================

@router.post("/bias/check")
def check_backtesting_biases(request: BiasCheckRequest):
    """
    Check for common backtesting biases.
    
    Analyzes trades for:
    - Look-ahead bias
    - Data snooping bias
    - Perfect trade patterns
    - Time distribution bias
    - Parameter sensitivity
    """
    trades = [t.dict() for t in request.trades]
    
    result = check_biases(
        trades=trades,
        strategy_params=request.strategy_params
    )
    
    return result


@router.get("/bias/types")
def get_bias_types():
    """
    Get descriptions of all bias types that are checked.
    """
    return {
        "bias_types": {
            "Look-Ahead Bias": {
                "description": "Using future information in past decisions",
                "examples": [
                    "Buying at the exact low of the day",
                    "Selling at the exact high",
                    "Using end-of-day prices for intraday decisions"
                ],
                "prevention": "Use only information available at decision time"
            },
            "Data Snooping": {
                "description": "Over-optimization on historical data",
                "examples": [
                    "Testing hundreds of parameter combinations",
                    "Selecting strategy after seeing results",
                    "Adding parameters until backtest looks good"
                ],
                "prevention": "Use out-of-sample testing, limit parameters, pre-register strategy"
            },
            "Survivorship Bias": {
                "description": "Only testing on assets that still exist",
                "examples": [
                    "Backtesting only on current S&P 500 stocks",
                    "Ignoring delisted stocks",
                    "Using only successful funds"
                ],
                "prevention": "Include delisted securities, use point-in-time data"
            },
            "Perfect Trades": {
                "description": "Unrealistically good trade execution",
                "examples": [
                    "100% win rate",
                    "Zero drawdown",
                    "Always hitting take profit"
                ],
                "prevention": "Include realistic slippage, commissions, partial fills"
            },
            "Time Distribution": {
                "description": "Trades clustered in favorable periods only",
                "examples": [
                    "Only trading during specific market conditions",
                    "Avoiding all volatile periods",
                    "Cherry-picking trade dates"
                ],
                "prevention": "Ensure trades distributed across full test period"
            }
        }
    }


@router.get("/bias/quick-check/{trade_count}")
def quick_bias_assessment(
    trade_count: int,
    win_rate: float = Query(..., ge=0, le=100, description="Win rate %"),
    profit_factor: float = Query(..., gt=0, description="Profit factor"),
    max_drawdown: float = Query(..., ge=0, description="Max drawdown %"),
    num_parameters: int = Query(default=5, ge=1, description="Strategy parameters")
):
    """
    Quick bias assessment without full trade data.
    
    Provides instant feedback on whether metrics seem realistic.
    """
    warnings = []
    score = 100
    
    # Check win rate
    if win_rate > 85:
        warnings.append(f"Win rate ({win_rate}%) is suspiciously high")
        score -= 30
    elif win_rate > 75:
        warnings.append(f"Win rate ({win_rate}%) is unusually high")
        score -= 15
    
    # Check profit factor
    if profit_factor > 5:
        warnings.append(f"Profit factor ({profit_factor}) is exceptionally high")
        score -= 30
    elif profit_factor > 3:
        warnings.append(f"Profit factor ({profit_factor}) is high")
        score -= 15
    
    # Check drawdown
    if max_drawdown == 0 and trade_count > 10:
        warnings.append("Zero drawdown is unrealistic")
        score -= 40
    elif max_drawdown < 2 and trade_count > 20:
        warnings.append(f"Very low drawdown ({max_drawdown}%) may indicate issues")
        score -= 20
    
    # Check parameters vs trades
    trades_per_param = trade_count / num_parameters
    if trades_per_param < 5:
        warnings.append(f"Only {trades_per_param:.1f} trades per parameter - overfitting risk")
        score -= 25
    elif trades_per_param < 10:
        warnings.append(f"Low trade count per parameter ({trades_per_param:.1f})")
        score -= 10
    
    # Determine status
    if score >= 80:
        status = "PASS"
        message = "Metrics appear realistic"
    elif score >= 50:
        status = "WARN"
        message = "Some metrics may be unrealistic"
    else:
        status = "FAIL"
        message = "Metrics suggest significant bias issues"
    
    return {
        "status": status,
        "score": max(0, score),
        "message": message,
        "warnings": warnings,
        "input_metrics": {
            "trade_count": trade_count,
            "win_rate": win_rate,
            "profit_factor": profit_factor,
            "max_drawdown": max_drawdown,
            "num_parameters": num_parameters
        }
    }
