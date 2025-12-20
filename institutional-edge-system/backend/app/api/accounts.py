"""
============================================================================
Account API - MT5 Account Management
============================================================================
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from loguru import logger

from app.api.database import get_db
from app.models.database import MT5Account, User
from app.core.crypto import encrypt_password, decrypt_password

router = APIRouter()


# ============================================================================
# SCHEMAS
# ============================================================================

class AccountCreate(BaseModel):
    name: str
    login: str
    password: str  # Plain text - will be encrypted
    server: str
    symbol_prefix: str = ""
    symbol_suffix: str = ""
    account_type: str = "demo"
    max_drawdown_percent: float = 8.0
    max_daily_dd_percent: float = 3.0


class AccountUpdate(BaseModel):
    name: Optional[str] = None
    login: Optional[str] = None
    password: Optional[str] = None
    server: Optional[str] = None
    symbol_prefix: Optional[str] = None
    symbol_suffix: Optional[str] = None
    account_type: Optional[str] = None
    max_drawdown_percent: Optional[float] = None
    max_daily_dd_percent: Optional[float] = None


class AccountResponse(BaseModel):
    id: int
    name: str
    login: str
    server: str
    symbol_prefix: str
    symbol_suffix: str
    account_type: str
    max_drawdown_percent: float
    max_daily_dd_percent: float
    starting_balance: float
    is_active: bool
    created_at: datetime
    last_connected: Optional[datetime]
    
    class Config:
        from_attributes = True


# ============================================================================
# ENDPOINTS
# ============================================================================

@router.get("/", response_model=List[AccountResponse])
async def list_accounts(db: Session = Depends(get_db)):
    """List all MT5 accounts"""
    # Get first user (or current authenticated user)
    user = db.query(User).first()
    if not user:
        return []
    
    accounts = db.query(MT5Account).filter(MT5Account.user_id == user.id).all()
    return accounts


@router.post("/", response_model=AccountResponse)
async def create_account(account: AccountCreate, db: Session = Depends(get_db)):
    """Create a new MT5 account"""
    # Get first user
    user = db.query(User).first()
    if not user:
        raise HTTPException(status_code=400, detail="No user found")
    
    # Encrypt password
    encrypted_password = encrypt_password(account.password)
    
    new_account = MT5Account(
        user_id=user.id,
        name=account.name,
        login=account.login,
        password_encrypted=encrypted_password,
        server=account.server,
        symbol_prefix=account.symbol_prefix,
        symbol_suffix=account.symbol_suffix,
        account_type=account.account_type,
        max_drawdown_percent=account.max_drawdown_percent,
        max_daily_dd_percent=account.max_daily_dd_percent,
        is_active=False
    )
    
    db.add(new_account)
    db.commit()
    db.refresh(new_account)
    
    logger.info(f"Created MT5 account: {new_account.name} ({new_account.login})")
    return new_account


@router.get("/{account_id}", response_model=AccountResponse)
async def get_account(account_id: int, db: Session = Depends(get_db)):
    """Get a specific account by ID"""
    account = db.query(MT5Account).filter(MT5Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    return account


@router.put("/{account_id}", response_model=AccountResponse)
async def update_account(account_id: int, update: AccountUpdate, db: Session = Depends(get_db)):
    """Update an account"""
    account = db.query(MT5Account).filter(MT5Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    update_data = update.dict(exclude_unset=True)
    
    # Handle password encryption if provided
    if 'password' in update_data and update_data['password']:
        update_data['password_encrypted'] = encrypt_password(update_data.pop('password'))
    elif 'password' in update_data:
        update_data.pop('password')
    
    for key, value in update_data.items():
        setattr(account, key, value)
    
    db.commit()
    db.refresh(account)
    
    logger.info(f"Updated MT5 account: {account.name}")
    return account


@router.delete("/{account_id}")
async def delete_account(account_id: int, db: Session = Depends(get_db)):
    """Delete an account"""
    account = db.query(MT5Account).filter(MT5Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    if account.is_active:
        raise HTTPException(status_code=400, detail="Cannot delete active account. Disconnect first.")
    
    db.delete(account)
    db.commit()
    
    logger.info(f"Deleted MT5 account: {account.name}")
    return {"success": True, "message": f"Account {account.name} deleted"}


@router.post("/{account_id}/connect")
async def connect_account(account_id: int, db: Session = Depends(get_db)):
    """Connect to an MT5 account and set it as active"""
    account = db.query(MT5Account).filter(MT5Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    # Deactivate all other accounts
    db.query(MT5Account).filter(MT5Account.id != account_id).update({"is_active": False})
    
    # Try to connect to MT5 and get real balance
    real_balance = None
    try:
        import MetaTrader5 as mt5
        
        # Decrypt password
        decrypted_password = decrypt_password(account.password_encrypted)
        
        # Initialize MT5
        if not mt5.initialize():
            logger.warning("MT5 not initialized, will use stored balance")
        else:
            # Try to connect with credentials
            login_result = mt5.login(
                login=int(account.login),
                password=decrypted_password,
                server=account.server
            )
            
            if login_result:
                # Get account info
                account_info = mt5.account_info()
                if account_info:
                    real_balance = account_info.balance
                    logger.info(f"MT5 connected: Balance = ${real_balance:,.2f}")
                    
                    # Update starting_balance with real balance
                    account.starting_balance = real_balance
                    account.daily_starting_balance = real_balance
            else:
                logger.warning(f"MT5 login failed: {mt5.last_error()}")
    except Exception as e:
        logger.warning(f"Could not connect to MT5: {e}")
    
    # Activate this account
    account.is_active = True
    account.last_connected = datetime.utcnow()
    
    db.commit()
    
    logger.info(f"Connected to MT5 account: {account.name} ({account.login})")
    return {
        "success": True,
        "message": f"Connected to {account.name}",
        "account_id": account.id,
        "balance": real_balance or account.starting_balance
    }


@router.post("/{account_id}/disconnect")
async def disconnect_account(account_id: int, db: Session = Depends(get_db)):
    """Disconnect from an MT5 account"""
    account = db.query(MT5Account).filter(MT5Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    account.is_active = False
    db.commit()
    
    logger.info(f"Disconnected from MT5 account: {account.name}")
    return {"success": True, "message": f"Disconnected from {account.name}"}


@router.get("/active/current", response_model=Optional[AccountResponse])
async def get_active_account(db: Session = Depends(get_db)):
    """Get the currently active account"""
    account = db.query(MT5Account).filter(MT5Account.is_active == True).first()
    return account


@router.get("/risk-status/{account_id}")
async def get_risk_status(account_id: int, db: Session = Depends(get_db)):
    """Get the current risk status for an account"""
    account = db.query(MT5Account).filter(MT5Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    # TODO: Get actual balance from MT5
    current_balance = account.starting_balance  # Placeholder
    
    from app.core.prop_firm_manager import PropFirmManager
    manager = PropFirmManager(
        max_drawdown_percent=account.max_drawdown_percent,
        max_daily_dd_percent=account.max_daily_dd_percent,
        starting_balance=account.starting_balance
    )
    
    return manager.get_risk_status(current_balance)
