"""
MT5 HTTP API Server
Exposes MetaTrader5 data via REST API endpoints for remote access
"""
import MetaTrader5 as mt5
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime
import pandas as pd
import uvicorn

app = FastAPI(title="MT5 API Server", version="1.0.0")

# Enable CORS for Streamlit dashboard
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize MT5 on startup
@app.on_event("startup")
async def startup_event():
    if not mt5.initialize():
        print(f"MT5 initialization failed: {mt5.last_error()}")
    else:
        print("MT5 initialized successfully")

@app.on_event("shutdown")
async def shutdown_event():
    mt5.shutdown()


# Health check
@app.get("/health")
async def health_check():
    """Check if MT5 is connected and API is running"""
    terminal_info = mt5.terminal_info()
    if terminal_info is None:
        return {"status": "unhealthy", "mt5_connected": False}

    return {
        "status": "healthy",
        "mt5_connected": True,
        "terminal": terminal_info._asdict() if terminal_info else None
    }


# Account Information
@app.get("/account/info")
async def get_account_info():
    """Get account information"""
    account_info = mt5.account_info()
    if account_info is None:
        raise HTTPException(status_code=500, detail=f"Failed to get account info: {mt5.last_error()}")

    return account_info._asdict()


# Positions
@app.get("/positions")
async def get_positions(symbol: Optional[str] = None):
    """Get all open positions or for specific symbol"""
    if symbol:
        positions = mt5.positions_get(symbol=symbol)
    else:
        positions = mt5.positions_get()

    if positions is None:
        raise HTTPException(status_code=500, detail=f"Failed to get positions: {mt5.last_error()}")

    return [pos._asdict() for pos in positions]


# Orders
@app.get("/orders")
async def get_orders(symbol: Optional[str] = None):
    """Get all pending orders or for specific symbol"""
    if symbol:
        orders = mt5.orders_get(symbol=symbol)
    else:
        orders = mt5.orders_get()

    if orders is None:
        raise HTTPException(status_code=500, detail=f"Failed to get orders: {mt5.last_error()}")

    return [order._asdict() for order in orders]


# Deals History
@app.get("/history/deals")
async def get_deals_history(
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    days: int = 30
):
    """Get deals history"""
    from datetime import datetime, timedelta

    if from_date and to_date:
        date_from = datetime.fromisoformat(from_date)
        date_to = datetime.fromisoformat(to_date)
    else:
        date_to = datetime.now()
        date_from = date_to - timedelta(days=days)

    deals = mt5.history_deals_get(date_from, date_to)

    if deals is None:
        raise HTTPException(status_code=500, detail=f"Failed to get deals: {mt5.last_error()}")

    return [deal._asdict() for deal in deals]


# Orders History
@app.get("/history/orders")
async def get_orders_history(
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    days: int = 30
):
    """Get orders history"""
    from datetime import datetime, timedelta

    if from_date and to_date:
        date_from = datetime.fromisoformat(from_date)
        date_to = datetime.fromisoformat(to_date)
    else:
        date_to = datetime.now()
        date_from = date_to - timedelta(days=days)

    orders = mt5.history_orders_get(date_from, date_to)

    if orders is None:
        raise HTTPException(status_code=500, detail=f"Failed to get orders: {mt5.last_error()}")

    return [order._asdict() for order in orders]


# Symbols
@app.get("/symbols")
async def get_symbols(group: Optional[str] = None):
    """Get available symbols"""
    if group:
        symbols = mt5.symbols_get(group=group)
    else:
        symbols = mt5.symbols_get()

    if symbols is None:
        raise HTTPException(status_code=500, detail=f"Failed to get symbols: {mt5.last_error()}")

    return [sym._asdict() for sym in symbols]


@app.get("/symbols/{symbol}/info")
async def get_symbol_info(symbol: str):
    """Get symbol information"""
    info = mt5.symbol_info(symbol)
    if info is None:
        raise HTTPException(status_code=404, detail=f"Symbol {symbol} not found")

    return info._asdict()


# Market data
@app.get("/symbols/{symbol}/tick")
async def get_last_tick(symbol: str):
    """Get last tick for symbol"""
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        raise HTTPException(status_code=404, detail=f"No tick data for {symbol}")

    return tick._asdict()


@app.get("/symbols/{symbol}/rates")
async def get_rates(
    symbol: str,
    timeframe: str = "H1",
    count: int = 100
):
    """Get historical rates (OHLCV data)"""
    # Timeframe mapping
    timeframes = {
        "M1": mt5.TIMEFRAME_M1,
        "M5": mt5.TIMEFRAME_M5,
        "M15": mt5.TIMEFRAME_M15,
        "M30": mt5.TIMEFRAME_M30,
        "H1": mt5.TIMEFRAME_H1,
        "H4": mt5.TIMEFRAME_H4,
        "D1": mt5.TIMEFRAME_D1,
        "W1": mt5.TIMEFRAME_W1,
        "MN1": mt5.TIMEFRAME_MN1,
    }

    if timeframe not in timeframes:
        raise HTTPException(status_code=400, detail=f"Invalid timeframe. Use: {list(timeframes.keys())}")

    rates = mt5.copy_rates_from_pos(symbol, timeframes[timeframe], 0, count)

    if rates is None or len(rates) == 0:
        raise HTTPException(status_code=404, detail=f"No rates data for {symbol}")

    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')

    return df.to_dict('records')


# Terminal Info
@app.get("/terminal/info")
async def get_terminal_info():
    """Get terminal information"""
    info = mt5.terminal_info()
    if info is None:
        raise HTTPException(status_code=500, detail="Failed to get terminal info")

    return info._asdict()


# Version info
@app.get("/version")
async def get_version():
    """Get MT5 version"""
    return {
        "mt5_version": mt5.version(),
        "api_version": "1.0.0"
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
