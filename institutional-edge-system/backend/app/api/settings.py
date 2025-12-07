from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.api import database
from app.models.database import BotConfig, RiskProfile
from app.schemas import schemas # Assuming schemas are updated or we use generic dicts for now

router = APIRouter()

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
        if hasattr(profile, key):
            setattr(profile, key, value)
            
    db.commit()
    db.refresh(profile)
    return profile
