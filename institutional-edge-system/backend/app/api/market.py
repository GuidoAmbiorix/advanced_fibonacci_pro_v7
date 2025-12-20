from fastapi import APIRouter, HTTPException, Query
from typing import List, Optional, Dict
from app.core.mt5_connector import MT5Connector
from app.core.config import settings

router = APIRouter()

# Initialize connector (will use the one from main.py if shared, or create new)
# Better to import the shared instance from main, but circular imports are tricky.
# Usually we use dependency injection or a singleton.
# For now, we'll assume the connector is available via a dependency or we create a new one.
# But creating a new one might not share the connection state if not careful.
# Let's use the pattern from other files. 
# Actually, other files don't seem to use mt5_connector directly except main.py?
# Let's check stats.py again. It uses database.
# Let's check backtest.py. It creates its own connector?
# No, backtest.py uses BacktestEngine which creates a connector.

# We need a way to access the global mt5_connector.
# In main.py: from app.core.mt5_connector import MT5Connector
# and it initializes it.
# We can't import 'app.main' here.

# Solution: Create a dependency in app/api/deps.py or similar?
# Or just instantiate it here? MT5 allows multiple init calls?
# Yes, mt5.initialize() is idempotent.
# But we need the login state.

# Let's look at how we can get the connector.
# Maybe we can add a dependency `get_mt5_connector`.

# For now, I will instantiate it here. It should pick up the existing connection if initialized.
connector = MT5Connector(settings.dict())

@router.get("/history/{symbol}/{timeframe}")
async def get_market_history(
    symbol: str,
    timeframe: str,
    bars: int = Query(100, ge=1, le=5000),
    symbol_type: Optional[str] = "forex"
):
    """
    Get OHLCV history for a symbol
    """
    # Ensure connection
    if not connector.connected:
        connector.connect()
        
    # Fetch data
    # The connector handles symbol normalization (suffix) automatically now.
    df = connector.get_ohlcv_data(symbol, timeframe, bars)
    
    if df is None or df.empty:
        raise HTTPException(status_code=404, detail=f"No data found for {symbol}")
        
    # Convert to list of dicts
    records = df.to_dict('records')
    
    # Format dates
    for record in records:
        if 'time' in record:
            record['time'] = record['time'].isoformat()
            
    return records


@router.get("/positions")
async def get_open_positions():
    """
    Get all open positions from MT5
    """
    # Ensure connection
    if not connector.connected:
        connector.connect()
    
    positions = connector.get_open_positions()
    
    return positions
