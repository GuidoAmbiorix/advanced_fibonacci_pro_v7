"""
============================================================================
Signals Scanner API - Real-time Trading Signals for Manual Trading
============================================================================
Uses the xau_pro engine to scan for entry opportunities.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime, timedelta
from pydantic import BaseModel
import pandas as pd

from app.api import database
from app.core.socket_server import sio
from app.engines.xau_pro.core import InstitutionalGoldEngine
from app.core.mt5_connector import mt5_connector
from app.services.alert_service import alert_service
from loguru import logger

router = APIRouter()

# ============================================================================
# SCHEMAS
# ============================================================================

class SignalResponse(BaseModel):
    symbol: str
    signal_type: str  # BUY or SELL
    price: float
    stop_loss: float
    take_profit_1: float
    take_profit_2: Optional[float] = None
    confluence_score: int
    strategy: str
    timeframe: str
    timestamp: str
    metadata: Optional[dict] = {}

class ScanRequest(BaseModel):
    symbols: List[str] = ["XAUUSD"]
    timeframe: str = "M15"

class ScanResponse(BaseModel):
    signals: List[SignalResponse]
    scanned_at: str
    symbols_scanned: List[str]

# ============================================================================
# TIMEFRAME MAPPING
# ============================================================================

TIMEFRAME_MAP = {
    'M1': 1,
    'M5': 5,
    'M15': 15,
    'M30': 30,
    'H1': 60,
    'H4': 240,
    'D1': 1440
}

# Higher timeframe for confirmation
HTF_MAP = {
    'M1': 'M5',
    'M5': 'M15',
    'M15': 'H1',
    'H1': 'H4',
    'H4': 'D1',
    'D1': 'W1'
}

# ============================================================================
# ENDPOINTS
# ============================================================================

@router.get("/scan", response_model=ScanResponse)
async def scan_signals(
    symbols: str = Query("XAUUSD", description="Comma-separated symbols"),
    timeframe: str = Query("M15", description="Timeframe (M5, M15, H1, H4)")
):
    """
    On-demand signal scan for specified symbols.
    Returns any signals found by the xau_pro engine.
    """
    symbol_list = [s.strip().upper() for s in symbols.split(",")]
    all_signals = []
    
    for symbol in symbol_list:
        try:
            signal = await _scan_symbol(symbol, timeframe)
            if signal:
                all_signals.extend(signal)
        except Exception as e:
            logger.warning(f"Failed to scan {symbol}: {e}")
    
    return ScanResponse(
        signals=all_signals,
        scanned_at=datetime.utcnow().isoformat(),
        symbols_scanned=symbol_list
    )


@router.get("/scan/{symbol}")
async def scan_single_symbol(
    symbol: str,
    timeframe: str = Query("M15")
):
    """Scan a single symbol for signals."""
    signals = await _scan_symbol(symbol.upper(), timeframe)
    
    return {
        "symbol": symbol.upper(),
        "timeframe": timeframe,
        "signals": signals,
        "scanned_at": datetime.utcnow().isoformat()
    }


@router.post("/emit-test")
async def emit_test_signal():
    """Emit a test signal for frontend debugging."""
    test_signal = {
        "symbol": "XAUUSD",
        "signal_type": "BUY",
        "price": 2345.67,
        "stop_loss": 2340.00,
        "take_profit_1": 2360.00,
        "confluence_score": 95,
        "strategy": "XAU_PRO_v4 (Test)",
        "timeframe": "M15",
        "timestamp": datetime.utcnow().isoformat(),
        "metadata": {"test": True}
    }
    
    await sio.emit('signal_generated', test_signal)
    logger.info(f"📡 Emitted test signal: {test_signal}")
    
    return {"status": "ok", "signal": test_signal}


# ============================================================================
# INTERNAL FUNCTIONS
# ============================================================================

async def _scan_symbol(symbol: str, timeframe: str) -> List[dict]:
    """
    Internal function to scan a symbol for signals using xau_pro engine.
    """
    logger.info(f"📡 Scanning {symbol} on {timeframe}...")
    
    # 1. Check MT5 connection
    if not mt5_connector.is_connected:
        connected = mt5_connector.connect()
        if not connected:
            logger.warning(f"⚠️ MT5 not connected, returning empty signals for {symbol}")
            return []
    
    # 2. Get timeframe constants
    tf_mins = TIMEFRAME_MAP.get(timeframe, 15)
    htf = HTF_MAP.get(timeframe, 'H1')
    htf_mins = TIMEFRAME_MAP.get(htf, 60)
    
    # 3. Fetch candle data
    try:
        # Main timeframe - last 200 candles
        df = mt5_connector.get_rates(symbol, timeframe, count=200)
        if df is None or len(df) < 50:
            logger.warning(f"⚠️ Not enough data for {symbol} {timeframe}")
            return []
        
        # Higher timeframe for confirmation
        df_htf = mt5_connector.get_rates(symbol, htf, count=100)
        
        # Daily for bias (optional)
        df_daily = mt5_connector.get_rates(symbol, 'D1', count=30)
        
    except Exception as e:
        logger.error(f"❌ Failed to fetch data for {symbol}: {e}")
        return []
    
    # 4. Configure engine
    config = {
        'symbol': symbol,
        'rr_ratio': 2.0,
        'sl_atr_multiplier': 1.5,
        'rsi_buy_threshold': 45,
        'rsi_sell_threshold': 55,
        'macd_fast': 8,
        'macd_slow': 21,
        'macd_signal': 5,
        'atr_period': 14,
        'rsi_period': 14,
        'zigzag_lookback': 12,
        'session_mode': 'BOTH_KZ',
        # SMC Settings
        'enable_order_blocks': True,
        'enable_liquidity_sweep': True,
        'enable_fvg': True,
        'ob_lookback': 20,
        'sweep_lookback': 10,
        'fvg_min_size_atr': 0.5
    }
    
    engine = InstitutionalGoldEngine(config)
    
    # 5. Run analysis
    try:
        analysis = engine.analyze(df, df_htf, df_daily)
        raw_signals = analysis.get('signals', [])
        
        if not raw_signals:
            logger.info(f"📭 No signals found for {symbol} {timeframe}")
            return []
        
        # 6. Format signals for response
        signals = []
        for sig in raw_signals:
            formatted = SignalResponse(
                symbol=sig.get('symbol', symbol),
                signal_type=sig.get('signal_type', 'BUY'),
                price=sig.get('price', 0),
                stop_loss=sig.get('stop_loss', 0),
                take_profit_1=sig.get('take_profit_1', 0),
                take_profit_2=sig.get('take_profit_2'),
                confluence_score=sig.get('confluence_score', 0),
                strategy=sig.get('strategy', 'XAU_PRO'),
                timeframe=timeframe,
                timestamp=sig.get('time', datetime.utcnow().isoformat()),
                metadata=sig.get('metadata', {})
            )
            signals.append(formatted)
            
            # Emit via WebSocket
            await sio.emit('signal_generated', formatted.dict())
            logger.info(f"📡 Signal emitted: {formatted.symbol} {formatted.signal_type} @ {formatted.price}")
            
            # Send to Discord
            await _send_signal_to_discord(formatted)
        
        return signals
        
    except Exception as e:
        logger.error(f"❌ Engine analysis failed for {symbol}: {e}")
        return []


async def _send_signal_to_discord(signal: SignalResponse):
    """
    Format and send signal to Discord via alert_service.
    Uses the DISCORD_WEBHOOK_SIGNALS_URL for dedicated signals channel.
    """
    try:
        # Determine emoji based on signal type
        emoji = "📈" if signal.signal_type == "BUY" else "📉"
        
        # Format price with appropriate decimals
        decimals = 2 if "XAU" in signal.symbol or "JPY" in signal.symbol else 5
        
        # Build message
        title = f"{emoji} {signal.signal_type} Signal: {signal.symbol}"
        message = f"**Strategy:** {signal.strategy}\n**Timeframe:** {signal.timeframe}"
        
        # Build fields for Discord embed
        fields = [
            {"name": "🎯 Entry", "value": f"`{signal.price:.{decimals}f}`", "inline": True},
            {"name": "🛑 Stop Loss", "value": f"`{signal.stop_loss:.{decimals}f}`", "inline": True},
            {"name": "💰 Take Profit", "value": f"`{signal.take_profit_1:.{decimals}f}`", "inline": True},
            {"name": "📊 Score", "value": f"`{signal.confluence_score}/100`", "inline": True},
        ]
        
        # Add SMC metadata if present
        if signal.metadata:
            smc_tags = []
            if signal.metadata.get('in_order_block'):
                smc_tags.append("🟣 Order Block")
            if signal.metadata.get('liquidity_swept'):
                smc_tags.append("🟡 Liquidity Sweep")
            if signal.metadata.get('in_fvg'):
                smc_tags.append("🔵 Fair Value Gap")
            if signal.metadata.get('fib_level'):
                smc_tags.append(f"📐 Fib {signal.metadata['fib_level']}")
            
            if smc_tags:
                fields.append({"name": "🧠 SMC Confluence", "value": "\n".join(smc_tags), "inline": False})
        
        # Determine level (color) based on confluence score
        level = "SUCCESS" if signal.confluence_score >= 90 else "INFO"
        
        await alert_service.send_alert(
            title=title,
            message=message,
            level=level,
            fields=fields
        )
        
        logger.info(f"📣 Signal sent to Discord: {signal.symbol} {signal.signal_type}")
        
    except Exception as e:
        logger.error(f"❌ Failed to send signal to Discord: {e}")
