"""
============================================================================
Kelly Criterion API Endpoints
============================================================================
Provides optimal position sizing calculations using the Kelly Criterion.
Based on "Quantitative Trading" by Dr. Ernest P. Chan.
"""

from typing import List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from app.api import database
from app.models.database import Trade
from app.core.kelly_optimizer import KellyOptimizer, KellyResult, calculate_kelly

router = APIRouter()


# ============================================================================
# Request/Response Models
# ============================================================================

class KellyCalculateRequest(BaseModel):
    """Request to calculate Kelly from win rate and R:R"""
    win_rate: float = Field(..., ge=0, le=100, description="Win rate as percentage (0-100)")
    avg_win: float = Field(..., gt=0, description="Average winning trade in dollars")
    avg_loss: float = Field(..., gt=0, description="Average losing trade in dollars (positive)")
    account_balance: float = Field(default=10000.0, gt=0, description="Current account balance")


class KellyFromTradesRequest(BaseModel):
    """Request to calculate Kelly from P&L list"""
    pnl_list: List[float] = Field(..., min_items=1, description="List of trade P&L values")
    account_balance: float = Field(default=10000.0, gt=0, description="Current account balance")


class MultiStrategyRequest(BaseModel):
    """Request for multi-strategy allocation"""
    strategy_returns: List[List[float]] = Field(..., description="List of return lists per strategy")
    strategy_names: Optional[List[str]] = Field(None, description="Optional names for strategies")


class PositionSizeRequest(BaseModel):
    """Request for position sizing"""
    entry_price: float = Field(..., gt=0, description="Entry price")
    stop_loss_pips: float = Field(..., gt=0, description="Stop loss distance in pips")
    account_balance: float = Field(default=10000.0, gt=0, description="Account balance")
    pip_value: float = Field(default=10.0, gt=0, description="Pip value per lot")
    kelly_fraction: str = Field(default="half", description="Kelly fraction: 'full', 'half', 'quarter'")
    win_rate: float = Field(default=55.0, ge=0, le=100, description="Win rate for calculation")
    avg_win: float = Field(default=100.0, gt=0, description="Average win")
    avg_loss: float = Field(default=50.0, gt=0, description="Average loss")


class KellyResponse(BaseModel):
    """Response with Kelly calculation results"""
    optimal_leverage: float
    half_kelly: float
    quarter_kelly: float
    recommended_leverage: float
    expected_growth_rate: float
    sharpe_ratio: float
    win_rate: float
    avg_win: float
    avg_loss: float
    risk_reward_ratio: float
    optimal_position_dollars: float
    max_risk_dollars: float
    warnings: List[str]


# ============================================================================
# Endpoints
# ============================================================================

@router.post("/calculate", response_model=KellyResponse)
def calculate_kelly_from_stats(request: KellyCalculateRequest):
    """
    Calculate optimal Kelly leverage from win rate and average win/loss.
    
    Uses the discrete Kelly formula: f* = (bp - q) / b
    
    Where:
    - b = odds (avg_win / avg_loss)
    - p = probability of winning
    - q = probability of losing (1 - p)
    """
    result = KellyOptimizer.calculate_kelly_from_winrate(
        win_rate=request.win_rate,
        avg_win=request.avg_win,
        avg_loss=request.avg_loss,
        account_balance=request.account_balance
    )
    
    return KellyResponse(
        optimal_leverage=result.optimal_leverage,
        half_kelly=result.half_kelly,
        quarter_kelly=result.quarter_kelly,
        recommended_leverage=result.recommended_leverage,
        expected_growth_rate=result.expected_growth_rate,
        sharpe_ratio=result.sharpe_ratio,
        win_rate=result.win_rate,
        avg_win=result.avg_win,
        avg_loss=result.avg_loss,
        risk_reward_ratio=result.risk_reward_ratio,
        optimal_position_dollars=result.optimal_position_dollars,
        max_risk_dollars=result.max_risk_dollars,
        warnings=result.warnings
    )


@router.post("/calculate-from-trades", response_model=KellyResponse)
def calculate_kelly_from_trades(request: KellyFromTradesRequest):
    """
    Calculate optimal Kelly leverage from a list of historical trade P&Ls.
    
    Uses the continuous Kelly formula: f* = m / σ²
    
    Where:
    - m = mean return
    - σ² = variance of returns
    """
    result = KellyOptimizer.calculate_kelly_from_trades(
        pnl_list=request.pnl_list,
        account_balance=request.account_balance
    )
    
    return KellyResponse(
        optimal_leverage=result.optimal_leverage,
        half_kelly=result.half_kelly,
        quarter_kelly=result.quarter_kelly,
        recommended_leverage=result.recommended_leverage,
        expected_growth_rate=result.expected_growth_rate,
        sharpe_ratio=result.sharpe_ratio,
        win_rate=result.win_rate,
        avg_win=result.avg_win,
        avg_loss=result.avg_loss,
        risk_reward_ratio=result.risk_reward_ratio,
        optimal_position_dollars=result.optimal_position_dollars,
        max_risk_dollars=result.max_risk_dollars,
        warnings=result.warnings
    )


@router.get("/from-history", response_model=KellyResponse)
def calculate_kelly_from_history(
    days: int = Query(default=90, ge=7, le=365, description="Number of days to analyze"),
    account_balance: float = Query(default=10000.0, gt=0, description="Current account balance"),
    db: Session = Depends(database.get_db)
):
    """
    Calculate Kelly from actual trading history in the database.
    
    Fetches closed trades from the last N days and calculates optimal position sizing.
    """
    # Get trades from history
    start_date = datetime.utcnow() - timedelta(days=days)
    
    trades = db.query(Trade).filter(
        Trade.opened_at >= start_date,
        Trade.status == "CLOSED"
    ).all()
    
    if not trades:
        raise HTTPException(
            status_code=404,
            detail=f"No closed trades found in the last {days} days"
        )
    
    # Extract P&L values
    pnl_list = [t.profit_loss for t in trades if t.profit_loss is not None]
    
    if not pnl_list:
        raise HTTPException(
            status_code=400,
            detail="No valid P&L data found in trades"
        )
    
    result = KellyOptimizer.calculate_kelly_from_trades(
        pnl_list=pnl_list,
        account_balance=account_balance
    )
    
    return KellyResponse(
        optimal_leverage=result.optimal_leverage,
        half_kelly=result.half_kelly,
        quarter_kelly=result.quarter_kelly,
        recommended_leverage=result.recommended_leverage,
        expected_growth_rate=result.expected_growth_rate,
        sharpe_ratio=result.sharpe_ratio,
        win_rate=result.win_rate,
        avg_win=result.avg_win,
        avg_loss=result.avg_loss,
        risk_reward_ratio=result.risk_reward_ratio,
        optimal_position_dollars=result.optimal_position_dollars,
        max_risk_dollars=result.max_risk_dollars,
        warnings=result.warnings
    )


@router.post("/multi-strategy")
def calculate_multi_strategy_allocation(request: MultiStrategyRequest):
    """
    Calculate optimal capital allocation across multiple strategies.
    
    Uses the matrix Kelly formula: F* = C⁻¹ × M
    
    Where:
    - F* = optimal allocation vector
    - C = covariance matrix
    - M = mean returns vector
    """
    result = KellyOptimizer.calculate_multi_strategy_allocation(
        strategy_returns=request.strategy_returns,
        strategy_names=request.strategy_names
    )
    
    return result


@router.post("/position-size")
def calculate_position_size(request: PositionSizeRequest):
    """
    Calculate specific position size for a trade using Kelly.
    
    Returns recommended lot size based on Kelly fraction and risk parameters.
    """
    # First calculate Kelly
    kelly_result = KellyOptimizer.calculate_kelly_from_winrate(
        win_rate=request.win_rate,
        avg_win=request.avg_win,
        avg_loss=request.avg_loss,
        account_balance=request.account_balance
    )
    
    # Then calculate position size
    position = KellyOptimizer.calculate_position_size(
        kelly_result=kelly_result,
        account_balance=request.account_balance,
        entry_price=request.entry_price,
        stop_loss_pips=request.stop_loss_pips,
        pip_value=request.pip_value,
        use_kelly_fraction=request.kelly_fraction
    )
    
    return {
        "kelly": {
            "optimal_leverage": kelly_result.optimal_leverage,
            "half_kelly": kelly_result.half_kelly,
            "recommended": kelly_result.recommended_leverage
        },
        "position": position
    }


@router.get("/quick")
def quick_kelly_calculation(
    win_rate: float = Query(..., ge=0, le=100, description="Win rate %"),
    risk_reward: float = Query(..., gt=0, description="Risk/Reward ratio"),
    account_balance: float = Query(default=10000.0, gt=0)
):
    """
    Quick Kelly calculation from win rate and R:R ratio.
    
    Simplified endpoint for fast calculations.
    """
    # Calculate avg_win and avg_loss from R:R
    avg_loss = 100.0  # Assume $100 base loss
    avg_win = avg_loss * risk_reward
    
    result = calculate_kelly(
        win_rate=win_rate,
        avg_win=avg_win,
        avg_loss=avg_loss,
        account_balance=account_balance
    )
    
    return result
