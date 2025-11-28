from fastapi import APIRouter, HTTPException, Depends
from typing import Dict
from app.services.alphavantage_service import alphavantage_service
from app.core.security import get_current_user

router = APIRouter()

@router.get("/{symbol}", response_model=Dict)
async def get_fundamentals(
    symbol: str,
    current_user: Dict = Depends(get_current_user)
):
    """
    Get fundamental data for a symbol (Company Overview + Sentiment)
    """
    overview = await alphavantage_service.get_company_overview(symbol)
    sentiment = await alphavantage_service.get_sentiment(symbol)
    
    if not overview and not sentiment:
        raise HTTPException(status_code=404, detail="Fundamental data not found")
        
    return {
        "overview": overview,
        "sentiment": sentiment
    }
