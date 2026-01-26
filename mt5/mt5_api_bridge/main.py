"""
MT5 REST API Bridge - FastAPI server to expose MT5 Terminal data via HTTP.
Runs inside Docker container with access to MT5 via Wine.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import MetaTrader5 as mt5
from typing import Dict, List, Optional
import uvicorn
from datetime import datetime
import time

app = FastAPI(
    title="MT5 REST API Bridge",
    description="REST API to access MetaTrader 5 Terminal data",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize MT5 connection
@app.on_event("startup")
async def startup():
    """Initialize MT5 on startup."""
    print("Initializing MT5 connection...")
    max_retries = 5
    for i in range(max_retries):
        if mt5.initialize():
            print(f"✅ MT5 initialized successfully!")
            terminal_info = mt5.terminal_info()
            if terminal_info:
                print(f"Terminal: {terminal_info.company} - {terminal_info.name}")
            return
        print(f"❌ MT5 initialization failed (attempt {i+1}/{max_retries})")
        time.sleep(5)
    
    print("FATAL: Could not initialize MT5 after retries")

@app.on_event("shutdown")
async def shutdown():
    """Shutdown MT5 on app shutdown."""
    mt5.shutdown()
    print("MT5 connection closed")

# ==================== HEALTH & STATUS ====================

@app.get("/")
async def root():
    """Root endpoint."""
    return {"message": "MT5 REST API Bridge", "status": "running"}

@app.get("/health")
async def health_check():
    """Check if MT5 is connected and healthy."""
    terminal_info = mt5.terminal_info()
    account_info = mt5.account_info()
    
    if not terminal_info:
        raise HTTPException(status_code=503, detail="MT5 Terminal not connected")
    
    if not account_info:
        raise HTTPException(status_code=503, detail="MT5 Account not connected")
    
    return {
        "status": "healthy",
        "mt5_connected": True,
        "terminal": {
            "company": terminal_info.company,
            "name": terminal_info.name,
            "path": terminal_info.path,
            "connected": terminal_info.connected
        },
        "account": {
            "login": account_info.login,
            "server": account_info.server,
            "balance": account_info.balance,
            "equity": account_info.equity
        }
    }

# ==================== ACCOUNT INFO ====================

@app.get("/account")
async def get_account_info():
    """Get MT5 account information."""
    account = mt5.account_info()
    if not account:
        raise HTTPException(status_code=404, detail="Account info not available")
    
    return {
        "login": str(account.login),
        "server": account.server,
        "name": account.name,
        "company": account.company,
        "balance": account.balance,
        "equity": account.equity,
        "margin": account.margin,
        "margin_free": account.margin_free,
        "margin_level": account.margin_level,
        "profit": account.profit,
        "currency": account.currency,
        "leverage": account.leverage
    }

# ==================== GLOBAL VARIABLES ====================

@app.get("/globalvariables")
async def get_global_variables(prefix: Optional[str] = None):
    """
    Get all global variables or filtered by prefix.
    
    Args:
        prefix: Optional prefix filter (e.g., "PG_", "GovernorMultiplier_")
    """
    gv_tuple = mt5.global_variables_get()
    
    if not gv_tuple:
        return {"variables": {}, "count": 0}
    
    gv_dict = dict(gv_tuple)
    
    if prefix:
        gv_dict = {k: v for k, v in gv_dict.items() if k.startswith(prefix)}
    
    return {
        "variables": gv_dict,
        "count": len(gv_dict)
    }

@app.get("/globalvariables/{var_name}")
async def get_global_variable(var_name: str):
    """Get specific global variable value."""
    gv_tuple = mt5.global_variables_get()
    
    if gv_tuple:
        gv_dict = dict(gv_tuple)
        if var_name in gv_dict:
            return {
                "name": var_name,
                "value": gv_dict[var_name],
                "exists": True
            }
    
    raise HTTPException(status_code=404, detail=f"Variable '{var_name}' not found")

class GlobalVariableSet(BaseModel):
    name: str
    value: float

@app.post("/globalvariables")
async def set_global_variable(gv: GlobalVariableSet):
    """Set global variable value."""
    success = mt5.global_variable_set(gv.name, gv.value)
    
    if not success:
        raise HTTPException(status_code=500, detail="Failed to set variable")
    
    return {
        "success": True,
        "name": gv.name,
        "value": gv.value
    }

@app.delete("/globalvariables/{var_name}")
async def delete_global_variable(var_name: str):
    """Delete global variable."""
    success = mt5.global_variable_del(var_name)
    
    if not success:
        raise HTTPException(status_code=500, detail="Failed to delete variable")
    
    return {
        "success": True,
        "deleted": var_name
    }

# ==================== POSITIONS ====================

@app.get("/positions")
async def get_positions(symbol: Optional[str] = None):
    """
    Get open positions.
    
    Args:
        symbol: Optional symbol filter
    """
    if symbol:
        positions = mt5.positions_get(symbol=symbol)
    else:
        positions = mt5.positions_get()
    
    if positions is None:
        return {"positions": [], "count": 0}
    
    positions_list = []
    for pos in positions:
        positions_list.append({
            "ticket": pos.ticket,
            "symbol": pos.symbol,
            "type": pos.type,
            "volume": pos.volume,
            "price_open": pos.price_open,
            "sl": pos.sl,
            "tp": pos.tp,
            "price_current": pos.price_current,
            "profit": pos.profit,
            "swap": pos.swap,
            "magic": pos.magic,
            "time": pos.time,
            "comment": pos.comment
        })
    
    return {
        "positions": positions_list,
        "count": len(positions_list)
    }

# ==================== HISTORY ====================

@app.get("/history/deals")
async def get_history_deals(
    date_from: int,
    date_to: int,
    symbol: Optional[str] = None
):
    """
    Get historical deals.
    
    Args:
        date_from: Unix timestamp start
        date_to: Unix timestamp end
        symbol: Optional symbol filter
    """
    from_date = datetime.fromtimestamp(date_from)
    to_date = datetime.fromtimestamp(date_to)
    
    if symbol:
        deals = mt5.history_deals_get(from_date, to_date, group=symbol)
    else:
        deals = mt5.history_deals_get(from_date, to_date)
    
    if deals is None:
        return {"deals": [], "count": 0}
    
    deals_list = []
    for deal in deals:
        deals_list.append({
            "ticket": deal.ticket,
            "order": deal.order,
            "time": deal.time,
            "type": deal.type,
            "entry": deal.entry,
            "magic": deal.magic,
            "position_id": deal.position_id,
            "volume": deal.volume,
            "price": deal.price,
            "commission": deal.commission,
            "swap": deal.swap,
            "profit": deal.profit,
            "symbol": deal.symbol,
            "comment": deal.comment
        })
    
    return {
        "deals": deals_list,
        "count": len(deals_list)
    }

@app.get("/history/orders")
async def get_history_orders(date_from: int, date_to: int):
    """Get historical orders."""
    from_date = datetime.fromtimestamp(date_from)
    to_date = datetime.fromtimestamp(date_to)
    
    orders = mt5.history_orders_get(from_date, to_date)
    
    if orders is None:
        return {"orders": [], "count": 0}
    
    orders_list = []
    for order in orders:
        orders_list.append({
            "ticket": order.ticket,
            "time_setup": order.time_setup,
            "time_done": order.time_done,
            "type": order.type,
            "state": order.state,
            "magic": order.magic,
            "position_id": order.position_id,
            "volume_initial": order.volume_initial,
            "volume_current": order.volume_current,
            "price_open": order.price_open,
            "sl": order.sl,
            "tp": order.tp,
            "symbol": order.symbol,
            "comment": order.comment
        })
    
    return {
        "orders": orders_list,
        "count": len(orders_list)
    }

# ==================== SYMBOLS ====================

@app.get("/symbols")
async def get_symbols():
    """Get all available symbols."""
    symbols = mt5.symbols_get()
    
    if symbols is None:
        return {"symbols": [], "count": 0}
    
    symbols_list = []
    for symbol in symbols:
        symbols_list.append({
            "name": symbol.name,
            "description": symbol.description,
            "visible": symbol.visible,
            "select": symbol.select,
            "bid": symbol.bid,
            "ask": symbol.ask,
            "spread": symbol.spread,
            "digits": symbol.digits,
            "point": symbol.point
        })
    
    return {
        "symbols": symbols_list,
        "count": len(symbols_list)
    }

# ==================== TERMINAL INFO ====================

@app.get("/terminal")
async def get_terminal_info():
    """Get MT5 terminal information."""
    terminal = mt5.terminal_info()
    
    if not terminal:
        raise HTTPException(status_code=503, detail="Terminal info not available")
    
    return {
        "company": terminal.company,
        "name": terminal.name,
        "language": terminal.language,
        "path": terminal.path,
        "data_path": terminal.data_path,
        "commondata_path": terminal.commondata_path,
        "build": terminal.build,
        "connected": terminal.connected,
        "dlls_allowed": terminal.dlls_allowed,
        "trade_allowed": terminal.tradeapi_disabled,
        "email_enabled": terminal.email_enabled,
        "ftp_enabled": terminal.ftp_enabled,
        "notifications_enabled": terminal.notifications_enabled
    }

# ==================== Start Server ====================

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8001,
        log_level="info"
    )
