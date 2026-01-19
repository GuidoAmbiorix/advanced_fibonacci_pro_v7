from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.api import database
from app.models.database import BotConfig, RiskProfile
from app.schemas import schemas # Assuming schemas are updated or we use generic dicts for now

router = APIRouter()

@router.get("/system", response_model=schemas.SystemInfoSchema)
async def get_system_info():
    from app.core.config import settings
    return {
        "max_drawdown": settings.MAX_DRAWDOWN_PERCENT,
        "max_daily_loss": settings.MAX_DAILY_LOSS_PERCENT,
        "symbol_suffix": settings.MT5_SYMBOL_SUFFIX,
        "symbol_prefix": settings.MT5_SYMBOL_PREFIX,
        "account_type": settings.ACCOUNT_TYPE,
        "instance_role": settings.INSTANCE_ROLE
    }

@router.get("/config/{bot_id}")
async def get_bot_settings(bot_id: int, db: Session = Depends(database.get_db)):
    config = db.query(BotConfig).filter(BotConfig.id == bot_id).first()
    if not config:
        raise HTTPException(status_code=404, detail="Bot config not found")
    return config

@router.put("/config/{bot_id}")
async def update_bot_settings(bot_id: int, settings: dict, db: Session = Depends(database.get_db)):
    config = db.query(BotConfig).filter(BotConfig.id == bot_id).first()
    if not config:
        raise HTTPException(status_code=404, detail="Bot config not found")
    
    for key, value in settings.items():
        # Skip primary key and foreign keys
        if key in ['id', 'user_id']:
            continue

        if hasattr(config, key):
            setattr(config, key, value)
            
    db.commit()
    db.refresh(config)
    return config

@router.get("/risk/{bot_id}", response_model=schemas.RiskProfile)
async def get_risk_profile(bot_id: int, db: Session = Depends(database.get_db)):
    profile = db.query(RiskProfile).filter(RiskProfile.bot_config_id == bot_id).first()
    if not profile:
        # Create default if not exists
        profile = RiskProfile(bot_config_id=bot_id)
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return profile

@router.put("/risk/{bot_id}", response_model=schemas.RiskProfile)
async def update_risk_profile(bot_id: int, settings: dict, db: Session = Depends(database.get_db)):
    profile = db.query(RiskProfile).filter(RiskProfile.bot_config_id == bot_id).first()
    if not profile:
        profile = RiskProfile(bot_config_id=bot_id)
        db.add(profile)
    
    for key, value in settings.items():
        # Skip primary key and foreign keys
        if key in ['id', 'bot_config_id']:
            continue
            
        if hasattr(profile, key):
            setattr(profile, key, value)
            
    db.commit()
    db.refresh(profile)
    return profile

# ============================================================================
# GLOBAL RISK CONTROL (KILL SWITCH)
# ============================================================================
from app.services.risk_manager import risk_manager
from pydantic import BaseModel

class KillSwitchValid(BaseModel):
    active: bool

@router.post("/kill-switch")
async def set_global_kill_switch(payload: KillSwitchValid):
    """
    Manually toggle Global Kill Switch
    """
    if payload.active:
        risk_manager.trigger_kill_switch("Manual Admin Override", source="USER_REQUEST")
    else:
        risk_manager.reset_kill_switch(source="USER_REQUEST")
    
    return {
        "status": "success", 
        "kill_switch": risk_manager.kill_switch_active,
        "reason": risk_manager.kill_switch_reason
    }

@router.get("/kill-switch")
async def get_kill_switch_status():
    """Get current Kill Switch status"""
    return {
        "active": risk_manager.kill_switch_active,
        "reason": risk_manager.kill_switch_reason
    }
