from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from app.api import deps, database
from app.models.database import GridConfiguration, BotSlot, BotConfig
from app.schemas import schemas

router = APIRouter()

# ============================================================================
# GRID CONFIGURATIONS
# ============================================================================

@router.post("/grid-configs", response_model=schemas.GridConfigResponse)
def create_grid_config(
    config: schemas.GridConfigCreate,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Save a new grid layout configuration.
    """
    user_id = 1 # Default admin

    db_obj = GridConfiguration(
        user_id=user_id,
        name=config.name,
        layout=config.layout,
        slot_ids=config.slot_ids,
        show_stats=config.show_stats,
        show_signals=config.show_signals,
        auto_refresh_interval=config.auto_refresh_interval
    )
    db.add(db_obj)
    db.commit()
    db.refresh(db_obj)
    return db_obj

@router.get("/grid-configs", response_model=List[schemas.GridConfigResponse])
def get_grid_configs(
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Get all grid configurations for the user.
    """
    user_id = 1
    configs = db.query(GridConfiguration).filter(GridConfiguration.user_id == user_id).all()
    return configs

# ============================================================================
# QUICK STATS
# ============================================================================

@router.get("/slots/{slot_id}/quick-stats", response_model=schemas.SlotQuickStats)
def get_slot_quick_stats(
    slot_id: int,
    db: Session = Depends(database.get_db)
):
    """
    Get lightweight statistics (price, PnL) for a slot card.
    """
    slot = db.query(BotSlot).filter(BotSlot.id == slot_id).first()
    if not slot:
        raise HTTPException(status_code=404, detail="Slot not found")
        
    # In a real implementation, we'd fetch live price from cache/MT5
    # For now, return DB values
    
    return schemas.SlotQuickStats(
        slot_id=slot.id,
        symbol=slot.symbol,
        timeframe=slot.timeframe,
        status="ACTIVE" if slot.enabled else "PAUSED",
        daily_pnl=slot.daily_pnl or 0.0,
        total_trades=0, # Need to count today's trades
        active_signal=None # Or fetch last signal
    )

@router.get("/slots/quick-stats/bulk", response_model=List[schemas.SlotQuickStats])
def get_bulk_quick_stats(
    slot_ids: str = Query(..., description="Comma separated list of slot IDs"),
    db: Session = Depends(database.get_db)
):
    """
    Get quick stats for multiple slots efficiently.
    """
    try:
        ids = [int(x) for x in slot_ids.split(',')]
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid slot_ids format")
        
    slots = db.query(BotSlot).filter(BotSlot.id.in_(ids)).all()
    
    results = []
    for slot in slots:
        results.append(schemas.SlotQuickStats(
            slot_id=slot.id,
            symbol=slot.symbol,
            timeframe=slot.timeframe,
            status="ACTIVE" if slot.enabled else "PAUSED",
            daily_pnl=slot.daily_pnl or 0.0,
            total_trades=0,
            active_signal=None
        ))
    return results
