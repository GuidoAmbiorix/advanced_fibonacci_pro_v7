"""
============================================================================
Database Connection and Session Management
============================================================================
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator
from app.core.config import settings
from app.models.database import Base


# Convert asyncpg URL to psycopg2 format if needed
database_url = settings.DATABASE_URL
if "asyncpg" in database_url:
    database_url = database_url.replace("postgresql+asyncpg://", "postgresql+psycopg2://")

# Create database engine
connect_args = {}
if "sqlite" in database_url:
    connect_args["check_same_thread"] = False
    # SQLite doesn't support pool_size/max_overflow with default pool
    engine = create_engine(
        database_url,
        connect_args=connect_args,
        pool_pre_ping=True,
    )
else:
    engine = create_engine(
        database_url,
        pool_size=settings.DATABASE_POOL_SIZE,
        max_overflow=settings.DATABASE_MAX_OVERFLOW,
        pool_pre_ping=True,
    )

# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db():
    """Initialize database - create all tables"""
    Base.metadata.create_all(bind=engine)


def get_db() -> Generator[Session, None, None]:
    """
    Dependency for getting database session

    Usage:
        @app.get("/endpoint")
        def endpoint(db: Session = Depends(get_db)):
            # Use db here
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
