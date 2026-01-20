from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Any
from datetime import datetime

from app.api import deps, database
from app.models.database import BacktestSession, BacktestHeatmapData, StrategyComparison, BacktestTrade
from app.schemas import schemas

router = APIRouter()

# ============================================================================
# HEATMAP
# ============================================================================

@router.get("/backtest/{session_id}/heatmap", response_model=schemas.HeatmapResponse)
def get_heatmap(
    session_id: int,
    bin_size: int = 20, # pips/points
    regenerate: bool = False,
    db: Session = Depends(database.get_db)
):
    """
    Get or generate entry zone heatmap analysis.
    """
    session = db.query(BacktestSession).filter(BacktestSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # In real implementation: Check if Heatmap data exists, or calculate from trades
    # For now, return empty or mock structure to ensure API validity
    
    mock_bin = schemas.HeatmapBinData(
         price_low=1.0000,
         price_high=1.0020,
         price_range="1.0000-1.0020",
         entry_count=0,
         buy_count=0,
         sell_count=0,
         total_pnl=0.0,
         win_count=0,
         loss_count=0,
         win_rate=0.0,
         avg_pnl=0.0
    )

    return schemas.HeatmapResponse(
        session_id=session_id,
        bins=[],
        bin_size=bin_size,
        total_entries=0,
        most_active_zone=mock_bin,
        best_win_rate_zone=mock_bin
    )

# ============================================================================
# STRATEGY COMPARISON
# ============================================================================

@router.post("/comparisons", response_model=schemas.ComparisonResponse)
def create_comparison(
    comp: schemas.ComparisonCreate,
    db: Session = Depends(database.get_db)
):
    """
    Create a new calculation comparing multiple backtest sessions.
    """
    db_obj = StrategyComparison(
        name=comp.name,
        description=comp.description,
        session_ids=comp.session_ids,
        notes=comp.notes,
        insights="Comparison created."
    )
    db.add(db_obj)
    db.commit()
    db.refresh(db_obj)
    
    return schemas.ComparisonResponse(
        id=db_obj.id,
        name=db_obj.name,
        description=db_obj.description,
        session_ids=db_obj.session_ids,
        metrics=[], # Would populate with calculated diffs
        notes=db_obj.notes,
        insights=db_obj.insights,
        created_at=db_obj.created_at,
        updated_at=db_obj.updated_at
    )

@router.get("/comparisons/{comparison_id}", response_model=schemas.ComparisonResponse)
def get_comparison(
    comparison_id: int,
    db: Session = Depends(database.get_db)
):
    comp = db.query(StrategyComparison).filter(StrategyComparison.id == comparison_id).first()
    if not comp:
        raise HTTPException(status_code=404, detail="Comparison not found")
        
    return schemas.ComparisonResponse(
        id=comp.id,
        name=comp.name,
        description=comp.description,
        session_ids=comp.session_ids,
        metrics=[],
        notes=comp.notes,
        insights=comp.insights,
        created_at=comp.created_at,
        updated_at=comp.updated_at
    )

# ============================================================================
# VISUALIZATION DATA
# ============================================================================

@router.get("/backtest/{session_id}/playback-data", response_model=schemas.BacktestPlaybackData)
def get_playback_data(
    session_id: int,
    db: Session = Depends(database.get_db)
):
    """
    Get full OHLCV and trade data for playback.
    """
    session = db.query(BacktestSession).filter(BacktestSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
        
    return schemas.BacktestPlaybackData(
        session_id=session.id,
        symbol=session.symbol,
        timeframe=session.timeframe,
        start_date=session.start_date,
        end_date=session.end_date,
        initial_balance=session.initial_balance,
        candles=[], # To be filled with actual OHLCV
        equity_curve=[],
        trades=[],
        metrics={}
    )

@router.get("/backtest/{session_id}/trade-distribution", response_model=schemas.TradeDistribution)
def get_trade_distribution(
    session_id: int,
    db: Session = Depends(database.get_db)
):
    """
    Get trade analytics by hour/day.
    """
    return schemas.TradeDistribution(
        by_hour={},
        by_day={},
        pnl_histogram=[]
    )
