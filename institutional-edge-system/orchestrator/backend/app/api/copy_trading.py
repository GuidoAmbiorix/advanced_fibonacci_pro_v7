
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Dict, Any
from pydantic import BaseModel

from app.api import database
from app.models.database import CopyGroup, CopyConfig, MT5Account, BotConfig
from loguru import logger

router = APIRouter()

# --- Pydantic Models for Request/Response ---

class CopyGroupCreate(BaseModel):
    name: str
    description: str = None
    master_account_id: int

class CopyConfigCreate(BaseModel):
    group_id: int
    slave_account_id: int
    mode: str = "MULTIPLIER" # MULTIPLIER, FIXED_LOT, RISK_PERCENT
    risk_multiplier: float = 1.0
    fixed_lot_size: float = 0.01



class CopyConfigUpdate(BaseModel):
    mode: str = None
    risk_multiplier: float = None
    fixed_lot_size: float = None
    is_active: bool = None
    is_suspended: bool = None

class AccountCreate(BaseModel):
    name: str
    login: str
    password: str
    server: str
    account_type: str = "demo"

# --- Endpoints ---

@router.get("/groups", response_model=List[Dict[str, Any]])
async def get_copy_groups(db: Session = Depends(database.get_db)):
    """List all Copy Trading Groups with their details"""
    groups = db.query(CopyGroup).all()
    result = []
    
    for group in groups:
        master = db.query(MT5Account).filter(MT5Account.id == group.master_account_id).first()
        slaves_data = []
        for config in group.slaves:
            slave_acc = db.query(MT5Account).filter(MT5Account.id == config.slave_account_id).first()
            slaves_data.append({
                "config_id": config.id,
                "slave_account_id": config.slave_account_id,
                "slave_name": slave_acc.name if slave_acc else "Unknown",
                "slave_login": slave_acc.login if slave_acc else "Unknown",
                "mode": config.mode,
                "risk_multiplier": config.risk_multiplier,
                "is_active": config.is_active,
                "status": "SUSPENDED" if config.is_suspended else ("ACTIVE" if config.is_active else "DISABLED")
            })
            
        result.append({
            "id": group.id,
            "name": group.name,
            "description": group.description,
            "master_account_id": group.master_account_id,
            "master_name": master.name if master else "Unknown",
            "is_active": group.is_active,
            "slaves": slaves_data
        })
    return result

@router.post("/groups")
async def create_copy_group(payload: CopyGroupCreate, db: Session = Depends(database.get_db)):
    """Create a new Copy Group (Master)"""
    # Verify Master exists
    master = db.query(MT5Account).filter(MT5Account.id == payload.master_account_id).first()
    if not master:
        raise HTTPException(status_code=404, detail="Master account not found")
        
    new_group = CopyGroup(
        name=payload.name,
        description=payload.description,
        master_account_id=payload.master_account_id,
        is_active=True
    )
    db.add(new_group)
    db.commit()
    db.refresh(new_group)
    return new_group

@router.post("/configs")
async def add_slave_to_group(payload: CopyConfigCreate, db: Session = Depends(database.get_db)):
    """Link a Slave Account to a Master Group"""
    # Verify Group and Slave exist
    group = db.query(CopyGroup).filter(CopyGroup.id == payload.group_id).first()
    if not group:
        raise HTTPException(status_code=404, detail="Copy Group not found")
        
    slave = db.query(MT5Account).filter(MT5Account.id == payload.slave_account_id).first()
    if not slave:
        raise HTTPException(status_code=404, detail="Slave account not found")

    # Check if already linked
    existing = db.query(CopyConfig).filter(
        CopyConfig.group_id == payload.group_id,
        CopyConfig.slave_account_id == payload.slave_account_id
    ).first()
    
    if existing:
        raise HTTPException(status_code=400, detail="Slave already in this group")

    new_config = CopyConfig(
        group_id=payload.group_id,
        slave_account_id=payload.slave_account_id,
        mode=payload.mode,
        risk_multiplier=payload.risk_multiplier,
        fixed_lot_size=payload.fixed_lot_size,
        is_active=True
    )
    db.add(new_config)
    db.commit()
    db.refresh(new_config)
    return new_config

@router.put("/configs/{config_id}")
async def update_copy_config(config_id: int, payload: CopyConfigUpdate, db: Session = Depends(database.get_db)):
    """Update Risk Settings for a Slave"""
    config = db.query(CopyConfig).filter(CopyConfig.id == config_id).first()
    if not config:
        raise HTTPException(status_code=404, detail="Configuration not found")
        
    update_data = payload.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(config, key, value)
        
    db.commit()
    return config

@router.get("/accounts/available-masters")
async def get_available_masters(db: Session = Depends(database.get_db)):
    """Get accounts that can be Masters (usually defined by Admin or BotConfig)"""
    # For now, any account can be master, but usually ones with BotConfig are masters
    # Simply returning all accounts for flexibility
    accounts = db.query(MT5Account).filter(MT5Account.is_active == True).all()
    return [{"id": a.id, "name": a.name, "login": a.login} for a in accounts]

@router.get("/accounts/available-slaves")
async def get_available_slaves(db: Session = Depends(database.get_db)):
    """Get accounts that can be Slaves (Workers)"""
    # Logic: Accounts with role 'SLAVE' or just any account
    # We will filter by name convention or metadata if available, for now return all active
    accounts = db.query(MT5Account).filter(MT5Account.is_active == True).all()
    return [{"id": a.id, "name": a.name, "login": a.login} for a in accounts]

@router.post("/accounts")
async def register_account(payload: AccountCreate, db: Session = Depends(database.get_db)):
    """Register a new MT5 Account"""
    from app.core.crypto import encrypt_password
    
    # Check duplicate
    existing = db.query(MT5Account).filter(MT5Account.login == payload.login).first()
    if existing:
        raise HTTPException(status_code=400, detail="Account login already exists")
        
    # Get Admin User (Default)
    # Get Admin User (Default)
    from app.models.database import User
    user = db.query(User).filter(User.email == "admin@gmail.com").first()
    if not user:
        # Auto-create Admin User if missing
        from app.core.security import get_password_hash
        user = User(
            email="admin@gmail.com", 
            username="admin",
            hashed_password=get_password_hash("admin12345"),
            is_active=True, 
            is_admin=True
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    new_account = MT5Account(
        user_id=user.id,
        name=payload.name,
        login=payload.login,
        password_encrypted=encrypt_password(payload.password),
        server=payload.server,
        account_type=payload.account_type,
        is_active=True
    )
    db.add(new_account)
    db.commit()
    db.refresh(new_account)
    return {"id": new_account.id, "name": new_account.name}
