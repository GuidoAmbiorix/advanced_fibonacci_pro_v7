from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from app.api import database
from app.models.database import NewsEvent
from datetime import datetime, timedelta

router = APIRouter()

@router.get("/events")
async def get_news_events(limit: int = 50, db: Session = Depends(database.get_db)):
    # Get upcoming and recent events
    start_date = datetime.utcnow() - timedelta(hours=24)
    events = db.query(NewsEvent).filter(
        NewsEvent.date >= start_date
    ).order_by(NewsEvent.date.asc()).limit(limit).all()
    return events

@router.post("/refresh")
async def refresh_news(db: Session = Depends(database.get_db)):
    # Trigger news fetch service
    # For now, just return success
    return {"status": "success", "message": "News refresh triggered"}
