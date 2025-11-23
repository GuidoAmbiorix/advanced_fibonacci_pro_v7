"""
Quick Database Connection Test
Tests if the PostgreSQL database is accessible and working
"""

import sys
from pathlib import Path

# Add backend to path
backend_path = Path(__file__).parent / 'backend' / 'app'
sys.path.insert(0, str(backend_path))

from sqlalchemy import create_engine, text
from dotenv import load_dotenv
from loguru import logger
import os

# Load environment variables
load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5432/institutional_edge')

def test_connection():
    """Test database connection"""
    logger.info("Testing database connection...")
    logger.info(f"Database URL: {DATABASE_URL.split('@')[1] if '@' in DATABASE_URL else DATABASE_URL}")

    try:
        # Create engine
        engine = create_engine(DATABASE_URL, pool_pre_ping=True)

        # Test connection
        with engine.connect() as conn:
            # Execute simple query
            result = conn.execute(text("SELECT version()"))
            version = result.fetchone()[0]

            logger.success("✅ Connection successful!")
            logger.info(f"PostgreSQL version: {version.split(',')[0]}")

            # Check if database exists
            result = conn.execute(text("SELECT current_database()"))
            db_name = result.fetchone()[0]
            logger.info(f"Connected to database: {db_name}")

            # List tables
            result = conn.execute(text(
                "SELECT tablename FROM pg_catalog.pg_tables "
                "WHERE schemaname = 'public' ORDER BY tablename"
            ))
            tables = [row[0] for row in result]

            if tables:
                logger.success(f"Found {len(tables)} tables:")
                for table in tables:
                    logger.info(f"  - {table}")
            else:
                logger.warning("No tables found. Run 'python init_db.py' to create them.")

            return True

    except Exception as e:
        logger.error(f"❌ Connection failed: {e}")
        logger.info("\nTroubleshooting:")
        logger.info("1. Is Docker running? Check with: docker ps")
        logger.info("2. Is the database container running? Check with: docker-compose ps")
        logger.info("3. Start the database: docker-compose up -d")
        logger.info("4. Check logs: docker-compose logs postgres")
        return False


if __name__ == "__main__":
    logger.info("=" * 70)
    logger.info("Database Connection Test")
    logger.info("=" * 70)

    if test_connection():
        logger.info("\n" + "=" * 70)
        logger.success("✅ Database is ready to use!")
        logger.info("=" * 70)
    else:
        logger.info("\n" + "=" * 70)
        logger.error("❌ Database connection failed")
        logger.info("=" * 70)
        sys.exit(1)
