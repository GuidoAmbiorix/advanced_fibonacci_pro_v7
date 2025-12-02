import asyncio
import os
import sys

# Add parent directory to path to import app modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.core.config import settings
from sqlalchemy import create_engine, text

def fix_schema():
    # Force sync driver for this script
    db_url = settings.DATABASE_URL.replace("postgresql+asyncpg", "postgresql+psycopg2")
    print(f"Connecting to database: {db_url}")
    engine = create_engine(db_url)
    
    with engine.connect() as conn:
        print("Checking bot_configs table schema...")
        
        # List of columns to check/add
        columns = [
            ("tsl_mode", "VARCHAR"),
            ("tsl_activation_r", "FLOAT DEFAULT 0.0"),
            ("tsl_atr_period", "INTEGER DEFAULT 14"),
            ("tsl_atr_multiplier", "FLOAT DEFAULT 1.5"),
            ("partial_tp_on", "BOOLEAN DEFAULT FALSE"),
            ("partial_tp_amount", "FLOAT DEFAULT 0.5"),
            ("trailing_sl", "BOOLEAN DEFAULT FALSE"),
            ("trailing_step", "FLOAT DEFAULT 1.0"),
            ("trailing_distance", "FLOAT DEFAULT 1.5"),
            ("be_trigger", "FLOAT DEFAULT 1.0")
        ]
        
        for col_name, col_type in columns:
            try:
                # Try to select the column to see if it exists
                conn.execute(text(f"SELECT {col_name} FROM bot_configs LIMIT 1"))
                print(f"Column {col_name} exists.")
            except Exception:
                print(f"Column {col_name} missing. Adding...")
                try:
                    conn.execute(text(f"ALTER TABLE bot_configs ADD COLUMN {col_name} {col_type}"))
                    conn.commit()
                    print(f"Added column {col_name}.")
                except Exception as e:
                    print(f"Failed to add {col_name}: {e}")
                    
        print("Schema check complete.")

if __name__ == "__main__":
    fix_schema()
