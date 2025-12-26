"""
============================================================================
Slots API - CRUD for Trading Slots
============================================================================
Manage portfolio bot slots with full persistence
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from loguru import logger

from app.api.database import get_db
from app.models.database import BotSlot, BotConfig

router = APIRouter()


# ==================== Pydantic Schemas ====================

class SlotCreate(BaseModel):
    bot_config_id: int
    symbol: str = "EURUSD"
    direction_filter: str = "BOTH"
    timeframe: str = "M5"
    risk_percent: float = 1.0
    tp_ratio: float = 2.0
    sl_atr_multiplier: float = 1.5
    tsl_mode: str = "TIERED"
    rsi_period: int = 14
    rsi_overbought: int = 70
    rsi_oversold: int = 30
    min_confluence_score: int = 7
    max_trade_duration_hours: float = 0.0
    enable_vwap_strategy: bool = True
    enable_stoch_strategy: bool = True
    enable_institutional_strategy: bool = True
    enable_fibonacci_strategy: bool = True
    partial_tp_on: bool = True
    partial_tp_amount: float = 1.0
    tp_ratio: float = 2.0
    sl_atr_multiplier: float = 1.5
    enabled: bool = True
    
    # Institutional Control
    confirmation_timeframe: Optional[str] = None
    trading_session: str = "ALL"
    session_end_action: str = "HOLD"
    use_daily_bias: bool = False


class SlotUpdate(BaseModel):
    symbol: Optional[str] = None
    direction_filter: Optional[str] = None
    timeframe: Optional[str] = None
    risk_percent: Optional[float] = None
    tsl_mode: Optional[str] = None
    rsi_period: Optional[int] = None
    rsi_overbought: Optional[int] = None
    rsi_oversold: Optional[int] = None
    min_confluence_score: Optional[int] = None
    max_trade_duration_hours: Optional[float] = None
    enable_vwap_strategy: Optional[bool] = None
    enable_stoch_strategy: Optional[bool] = None
    enable_institutional_strategy: Optional[bool] = None
    enable_fibonacci_strategy: Optional[bool] = None
    partial_tp_on: Optional[bool] = None
    partial_tp_amount: Optional[float] = None
    tp_ratio: Optional[float] = None
    sl_atr_multiplier: Optional[float] = None
    enabled: Optional[bool] = None
    
    # Institutional ControlUpdate
    confirmation_timeframe: Optional[str] = None
    trading_session: Optional[str] = None
    session_end_action: Optional[str] = None
    use_daily_bias: Optional[bool] = None


class SlotResponse(BaseModel):
    id: int
    bot_config_id: int
    symbol: str
    direction_filter: str
    timeframe: str
    risk_percent: float
    tsl_mode: str
    rsi_period: int
    rsi_overbought: int
    rsi_oversold: int
    min_confluence_score: int
    max_trade_duration_hours: float
    enable_vwap_strategy: bool
    enable_stoch_strategy: bool
    enable_institutional_strategy: bool
    enable_fibonacci_strategy: bool
    partial_tp_on: bool
    partial_tp_amount: float
    tp_ratio: float
    sl_atr_multiplier: float
    enabled: bool
    
    # Institutional Control
    confirmation_timeframe: Optional[str]
    trading_session: str
    session_end_action: str
    use_daily_bias: bool
    created_at: datetime

    class Config:
        from_attributes = True


# ==================== CRUD Endpoints ====================

@router.get("/", response_model=List[SlotResponse])
async def list_slots(bot_config_id: Optional[int] = None, db: Session = Depends(get_db)):
    """List all slots, optionally filtered by bot_config_id"""
    query = db.query(BotSlot)
    if bot_config_id:
        query = query.filter(BotSlot.bot_config_id == bot_config_id)
    slots = query.order_by(BotSlot.id).all()
    return slots


@router.get("/{slot_id}", response_model=SlotResponse)
async def get_slot(slot_id: int, db: Session = Depends(get_db)):
    """Get a single slot by ID"""
    slot = db.query(BotSlot).filter(BotSlot.id == slot_id).first()
    if not slot:
        raise HTTPException(status_code=404, detail="Slot not found")
    return slot


@router.post("/", response_model=SlotResponse)
async def create_slot(slot: SlotCreate, db: Session = Depends(get_db)):
    """Create a new slot"""
    # Verify bot_config exists
    config = db.query(BotConfig).filter(BotConfig.id == slot.bot_config_id).first()
    if not config:
        raise HTTPException(status_code=404, detail="BotConfig not found")
    
    # Timeframe Hierarchy Map
    TF_MAP = {
        "M1": 1, "M5": 5, "M15": 15, "M30": 30, 
        "H1": 60, "H4": 240, "D1": 1440
    }
    
    # Validation: Confirmation TF >= Entry TF
    if slot.confirmation_timeframe:
        entry_mins = TF_MAP.get(slot.timeframe, 0)
        confirm_mins = TF_MAP.get(slot.confirmation_timeframe, 0)
        
        if confirm_mins < entry_mins:
            raise HTTPException(
                status_code=400, 
                detail=f"Confirmation TF ({slot.confirmation_timeframe}) cannot be lower than Entry TF ({slot.timeframe})"
            )

    db_slot = BotSlot(**slot.dict())
    db.add(db_slot)
    db.commit()
    db.refresh(db_slot)
    
    logger.info(f"Created slot {db_slot.id} for {slot.symbol} [Session: {slot.trading_session}]")
    return db_slot


@router.put("/{slot_id}", response_model=SlotResponse)
async def update_slot(slot_id: int, slot: SlotUpdate, db: Session = Depends(get_db)):
    """Update an existing slot"""
    db_slot = db.query(BotSlot).filter(BotSlot.id == slot_id).first()
    if not db_slot:
        raise HTTPException(status_code=404, detail="Slot not found")
    
    update_data = slot.dict(exclude_unset=True)
    
    # Validation: Confirmation TF >= Entry TF (if changing)
    if "confirmation_timeframe" in update_data or "timeframe" in update_data:
        TF_MAP = {
            "M1": 1, "M5": 5, "M15": 15, "M30": 30, 
            "H1": 60, "H4": 240, "D1": 1440
        }
        
        new_entry = update_data.get("timeframe", db_slot.timeframe)
        new_confirm = update_data.get("confirmation_timeframe", db_slot.confirmation_timeframe)
        
        if new_confirm:
            entry_mins = TF_MAP.get(new_entry, 0)
            confirm_mins = TF_MAP.get(new_confirm, 0)
            
            if confirm_mins < entry_mins:
                raise HTTPException(
                    status_code=400, 
                    detail=f"Confirmation TF ({new_confirm}) cannot be lower than Entry TF ({new_entry})"
                )
    
    for key, value in update_data.items():
        setattr(db_slot, key, value)
    
    db.commit()
    db.refresh(db_slot)
    
    logger.info(f"Updated slot {slot_id}")
    return db_slot


@router.delete("/{slot_id}")
async def delete_slot(slot_id: int, db: Session = Depends(get_db)):
    """Delete a slot"""
    db_slot = db.query(BotSlot).filter(BotSlot.id == slot_id).first()
    if not db_slot:
        raise HTTPException(status_code=404, detail="Slot not found")
    
    db.delete(db_slot)
    db.commit()
    
    logger.info(f"Deleted slot {slot_id}")
    return {"success": True, "message": f"Slot {slot_id} deleted"}


@router.post("/bulk-sync")
async def bulk_sync_slots(
    bot_config_id: int,
    slots: List[SlotCreate],
    db: Session = Depends(get_db)
):
    """
    Sync frontend slots to database.
    Deletes existing slots and recreates from provided list.
    """
    # Verify bot_config exists
    config = db.query(BotConfig).filter(BotConfig.id == bot_config_id).first()
    if not config:
        raise HTTPException(status_code=404, detail="BotConfig not found")
    
    # Delete existing slots
    db.query(BotSlot).filter(BotSlot.bot_config_id == bot_config_id).delete()
    
    # Create new slots
    created = []
    for slot_data in slots:
        slot_data.bot_config_id = bot_config_id
        db_slot = BotSlot(**slot_data.dict())
        db.add(db_slot)
        created.append(db_slot)
    
    db.commit()
    
    logger.info(f"Bulk synced {len(created)} slots for config {bot_config_id}")
    return {"success": True, "synced": len(created)}
