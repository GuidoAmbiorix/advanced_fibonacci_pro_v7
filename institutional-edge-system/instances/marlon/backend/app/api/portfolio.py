"""
Portfolio API Endpoints

Provides portfolio-level analytics: correlation, risk summary, templates.
"""

from fastapi import APIRouter, HTTPException
from typing import List, Optional
from pydantic import BaseModel
from loguru import logger

from app.core.correlation import CorrelationCalculator
from app.core.portfolio_risk import PortfolioRiskManager
from app.core.mt5_connector import MT5Connector
from app.core.config import settings

router = APIRouter()

# Initialize connector (shared instance)
connector = MT5Connector(settings.dict())


class SlotsRequest(BaseModel):
    symbols: List[str]
    configs: Optional[List[dict]] = None


@router.get("/correlation")
async def get_correlation_matrix(
    symbols: str,  # Comma-separated symbols
    timeframe: str = "H1",
    bars: int = 500
):
    """
    Calculate correlation matrix between symbols.
    
    Example: /api/portfolio/correlation?symbols=EURUSD,USDJPY,GBPJPY&timeframe=H1
    """
    try:
        # Ensure connection
        if not connector.connected:
            connector.connect()
        
        # Parse symbols
        symbol_list = [s.strip() for s in symbols.split(',') if s.strip()]
        
        if len(symbol_list) < 2:
            raise HTTPException(400, "Need at least 2 symbols for correlation")
        
        # Calculate correlations
        calc = CorrelationCalculator(connector)
        result = calc.calculate_correlation_matrix(symbol_list, timeframe, bars)
        
        return result
        
    except Exception as e:
        logger.error(f"Correlation calculation error: {e}")
        raise HTTPException(500, str(e))


@router.post("/risk-summary")
async def get_risk_summary(request: SlotsRequest):
    """
    Get comprehensive portfolio risk summary.
    
    Body: { "symbols": ["EURUSD", "USDJPY"], "configs": [...] }
    """
    try:
        # Ensure connection
        if not connector.connected:
            connector.connect()
        
        # Build slot configs from request
        slots_config = []
        for i, symbol in enumerate(request.symbols):
            config = request.configs[i] if request.configs and i < len(request.configs) else {}
            slots_config.append({
                'symbol': symbol,
                'risk_percent': config.get('risk_percent', 1.0),
                'enabled': config.get('enabled', True)
            })
        
        # Get risk summary
        risk_manager = PortfolioRiskManager(
            max_portfolio_risk=4.0,
            max_correlation_risk=0.7
        )
        
        result = risk_manager.get_portfolio_summary(connector, slots_config)
        
        return result
        
    except Exception as e:
        logger.error(f"Risk summary error: {e}")
        raise HTTPException(500, str(e))


@router.get("/risk-summary-simple")
async def get_risk_summary_simple():
    """
    Get simple risk summary (current positions only).
    """
    try:
        # Ensure connection
        if not connector.connected:
            connector.connect()
        
        account = connector.get_account_info() or {}
        positions = connector.get_open_positions() or []
        
        balance = account.get('balance', 0)
        equity = account.get('equity', 0)
        
        # Group by symbol
        by_symbol = {}
        for pos in positions:
            sym = pos.get('symbol', 'Unknown')
            if sym not in by_symbol:
                by_symbol[sym] = {'count': 0, 'profit': 0, 'volume': 0}
            by_symbol[sym]['count'] += 1
            by_symbol[sym]['profit'] += pos.get('profit', 0)
            by_symbol[sym]['volume'] += pos.get('volume', 0)
        
        return {
            'balance': round(balance, 2),
            'equity': round(equity, 2),
            'drawdown_percent': round((balance - equity) / balance * 100, 2) if balance > 0 else 0,
            'open_positions': len(positions),
            'total_profit': round(sum(p.get('profit', 0) for p in positions), 2),
            'by_symbol': by_symbol
        }
        
    except Exception as e:
        logger.error(f"Simple risk summary error: {e}")
        raise HTTPException(500, str(e))
