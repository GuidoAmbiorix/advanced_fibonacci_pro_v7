"""
Database Initialization Script
Creates all database tables for the Institutional Edge PRO system.
"""

import sys
sys.path.append('backend/app')

from api.database import init_db
from loguru import logger

logger.info("=" * 60)
logger.info("Initializing Database...")
logger.info("=" * 60)

try:
    init_db()
    logger.info("[SUCCESS] Database initialized successfully!")
    logger.info("All tables created")
    logger.info("=" * 60)
    logger.info("\nYou can now:")
    logger.info("1. Start the backend server: python backend/app/main.py")
    logger.info("2. Access the API docs at: http://localhost:8000/docs")
    logger.info("=" * 60)
except Exception as e:
    logger.error("[FAILED] Database initialization failed!")
    logger.error(f"Error: {e}")
    logger.info("\nTroubleshooting:")
    logger.info("1. Check DATABASE_URL in .env file")
    logger.info("2. If using PostgreSQL, make sure it's running")
    logger.info("3. If using PostgreSQL, create the database first:")
    logger.info("   createdb institutional_edge")
    logger.info("4. For development, you can use SQLite (already configured in .env)")
    sys.exit(1)
