from sqlalchemy import Column, Integer, String, Float, DateTime, PrimaryKeyConstraint
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

# We use a separate Base for TimescaleDB models if needed, 
# but sharing the same Base is usually fine if we manage tables carefully.
# For clarity, let's import the Base from database.py if possible, 
# or just define these and ensure they are initialized.
from app.models.database import Base

class MarketCandle(Base):
    """
    OHLCV Data stored in TimescaleDB hypertable.
    """
    __tablename__ = "market_candles"

    time = Column(DateTime, nullable=False, primary_key=True)
    symbol = Column(String, nullable=False, primary_key=True)
    timeframe = Column(String, nullable=False, primary_key=True)
    
    open = Column(Float, nullable=False)
    high = Column(Float, nullable=False)
    low = Column(Float, nullable=False)
    close = Column(Float, nullable=False)
    volume = Column(Float, nullable=False)
    
    # Optional: Add indicators or other computed values if we want to store them
    # rsi = Column(Float, nullable=True)
    
    # TimescaleDB requires a composite primary key that includes the time column.
    # We rely on SQLAlchemy to define the schema, but the hypertable conversion 
    # happens via SQL commands (usually in migration or init script).
    
class MarketTick(Base):
    """
    Tick data stored in TimescaleDB hypertable.
    """
    __tablename__ = "market_ticks"

    time = Column(DateTime, nullable=False, primary_key=True)
    symbol = Column(String, nullable=False, primary_key=True)
    
    bid = Column(Float, nullable=False)
    ask = Column(Float, nullable=False)
    last = Column(Float, nullable=False)
    volume = Column(Float, nullable=False)
    flags = Column(Integer, nullable=True)
