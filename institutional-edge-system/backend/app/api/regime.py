"""
============================================================================
Market Regime Detection API Endpoints
============================================================================
Provides market regime detection for adaptive trading strategies.
Based on "Quantitative Trading" by Dr. Ernest P. Chan.
"""

from typing import List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
import pandas as pd

from app.api import database
from app.core.regime_detector import RegimeDetector, MarketRegime, VolatilityRegime, detect_market_regime

router = APIRouter()


# ============================================================================
# Request/Response Models
# ============================================================================

class RegimeFromPricesRequest(BaseModel):
    """Request to detect regime from price data"""
    close_prices: List[float] = Field(..., min_items=20, description="List of closing prices")
    high_prices: Optional[List[float]] = Field(None, description="Optional high prices")
    low_prices: Optional[List[float]] = Field(None, description="Optional low prices")
    lookback: int = Field(default=100, ge=20, le=500, description="Analysis lookback period")


class RegimeResponse(BaseModel):
    """Response with regime detection results"""
    regime: str
    volatility: str
    regime_confidence: float
    volatility_percentile: float
    trend_strength: float
    mean_reversion_score: float
    regime_duration_bars: int
    hurst_exponent: Optional[float]
    recommendation: str
    analysis_details: dict
    timestamp: str


# ============================================================================
# Endpoints
# ============================================================================

@router.post("/detect", response_model=RegimeResponse)
def detect_regime_from_prices(request: RegimeFromPricesRequest):
    """
    Detect market regime from provided price data.
    
    Uses Hurst Exponent, variance ratio, and trend analysis to determine
    if the market is trending (momentum) or mean-reverting.
    
    Returns:
        Regime classification with confidence and trading recommendations
    """
    result = detect_market_regime(
        close_prices=request.close_prices,
        high_prices=request.high_prices,
        low_prices=request.low_prices,
        lookback=request.lookback
    )
    
    return RegimeResponse(
        regime=result["regime"],
        volatility=result["volatility"],
        regime_confidence=result["regime_confidence"],
        volatility_percentile=result["volatility_percentile"],
        trend_strength=result["trend_strength"],
        mean_reversion_score=result["mean_reversion_score"],
        regime_duration_bars=result["regime_duration_bars"],
        hurst_exponent=result["hurst_exponent"],
        recommendation=result["recommendation"],
        analysis_details=result["analysis_details"],
        timestamp=datetime.utcnow().isoformat()
    )


@router.get("/current/{symbol}")
async def get_current_regime(
    symbol: str,
    timeframe: str = Query(default="H1", description="Timeframe: M5, M15, H1, H4, D1"),
    lookback: int = Query(default=100, ge=20, le=500, description="Analysis lookback")
):
    """
    Get current market regime for a specific symbol.
    
    Fetches OHLCV data from MT5 and analyzes the regime.
    """
    try:
        # Import MT5 connector from main app context
        from app.main import mt5_connector
        
        if not mt5_connector or not mt5_connector.connected:
            raise HTTPException(status_code=503, detail="MT5 not connected")
        
        # Get OHLCV data
        df = mt5_connector.get_ohlcv_data(symbol, timeframe, bars=lookback + 50)
        
        if df is None or len(df) < 20:
            raise HTTPException(
                status_code=404, 
                detail=f"Insufficient data for {symbol} {timeframe}"
            )
        
        # Convert to lists for regime detection
        close_prices = df['close'].tolist()
        high_prices = df['high'].tolist() if 'high' in df.columns else None
        low_prices = df['low'].tolist() if 'low' in df.columns else None
        
        result = detect_market_regime(
            close_prices=close_prices,
            high_prices=high_prices,
            low_prices=low_prices,
            lookback=lookback
        )
        
        return {
            "symbol": symbol,
            "timeframe": timeframe,
            **result,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analysis error: {str(e)}")


@router.get("/multi-symbol")
async def get_multi_symbol_regimes(
    symbols: str = Query(..., description="Comma-separated symbols: EURUSD,GBPUSD,USDJPY"),
    timeframe: str = Query(default="H1", description="Timeframe"),
    lookback: int = Query(default=100, ge=20, le=500)
):
    """
    Get regime analysis for multiple symbols at once.
    
    Useful for portfolio-level regime monitoring.
    """
    try:
        from app.main import mt5_connector
        
        if not mt5_connector or not mt5_connector.connected:
            raise HTTPException(status_code=503, detail="MT5 not connected")
        
        symbol_list = [s.strip().upper() for s in symbols.split(",")]
        results = {}
        
        for symbol in symbol_list:
            try:
                df = mt5_connector.get_ohlcv_data(symbol, timeframe, bars=lookback + 50)
                
                if df is None or len(df) < 20:
                    results[symbol] = {"error": "Insufficient data"}
                    continue
                
                close_prices = df['close'].tolist()
                result = detect_market_regime(
                    close_prices=close_prices,
                    lookback=lookback
                )
                
                results[symbol] = {
                    "regime": result["regime"],
                    "volatility": result["volatility"],
                    "confidence": result["regime_confidence"],
                    "trend_strength": result["trend_strength"]
                }
                
            except Exception as e:
                results[symbol] = {"error": str(e)}
        
        return {
            "timeframe": timeframe,
            "regimes": results,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Multi-symbol analysis error: {str(e)}")


@router.get("/summary")
async def get_regime_summary():
    """
    Get a summary of what each regime means and how to trade it.
    
    Educational endpoint for understanding regime-based trading.
    """
    return {
        "regimes": {
            "TRENDING_BULL": {
                "description": "Market shows persistent upward momentum",
                "hurst_range": "> 0.55",
                "strategy": "Momentum / Trend-following",
                "entry_type": "Buy breakouts, buy dips to support",
                "exit_type": "Trail stops, use momentum exhaustion signals",
                "fibonacci_use": "Extensions for targets, retracements for entries"
            },
            "TRENDING_BEAR": {
                "description": "Market shows persistent downward momentum",
                "hurst_range": "> 0.55 (with negative trend)",
                "strategy": "Momentum shorts / Trend-following",
                "entry_type": "Sell rallies, sell breakdowns",
                "exit_type": "Trail stops, cover at support levels",
                "fibonacci_use": "Extensions for targets, retracements for entry"
            },
            "MEAN_REVERTING": {
                "description": "Market oscillates around a mean value",
                "hurst_range": "< 0.45",
                "strategy": "Mean-reversion / Range trading",
                "entry_type": "Buy at support/oversold, sell at resistance/overbought",
                "exit_type": "Fixed targets at mean or opposite extreme",
                "fibonacci_use": "Retracements for both entries AND targets"
            },
            "NEUTRAL": {
                "description": "No clear market regime detected",
                "hurst_range": "0.45 - 0.55",
                "strategy": "Wait or reduce size",
                "entry_type": "Be selective, wait for clearer signals",
                "exit_type": "Use tighter stops",
                "fibonacci_use": "Standard levels, no bias"
            }
        },
        "volatility_regimes": {
            "HIGH": {
                "description": "Above 80th percentile volatility",
                "adjustment": "Reduce position size, widen stops",
                "opportunity": "Larger moves possible, higher reward potential"
            },
            "NORMAL": {
                "description": "20th-80th percentile volatility",
                "adjustment": "Normal position sizing",
                "opportunity": "Standard market conditions"
            },
            "LOW": {
                "description": "Below 20th percentile volatility",
                "adjustment": "May increase size slightly, expect breakout soon",
                "opportunity": "Low risk entries, volatility expansion likely"
            }
        },
        "hurst_exponent": {
            "description": "Measure of long-term memory in time series",
            "interpretation": {
                "0.0 - 0.45": "Mean-reverting (anti-persistent)",
                "0.45 - 0.55": "Random walk (no memory)",
                "0.55 - 1.0": "Trending (persistent)"
            }
        }
    }
