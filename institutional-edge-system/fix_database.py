"""
Fix database schema - Add all missing columns
"""

import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5433/institutional_edge')

print("Connecting to database...")
engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    # Add all missing columns
    print("Adding missing columns...")
    conn.execute(text("ALTER TABLE bot_configs ADD COLUMN IF NOT EXISTS mt5_password_encrypted VARCHAR"))
    conn.execute(text("ALTER TABLE bot_configs ADD COLUMN IF NOT EXISTS swing_length INTEGER DEFAULT 10"))
    conn.execute(text("ALTER TABLE bot_configs ADD COLUMN IF NOT EXISTS ob_lookback INTEGER DEFAULT 50"))
    conn.execute(text("ALTER TABLE bot_configs ADD COLUMN IF NOT EXISTS fvg_min_size FLOAT DEFAULT 0.3"))
    conn.execute(text("ALTER TABLE bot_configs ADD COLUMN IF NOT EXISTS vp_lookback INTEGER DEFAULT 100"))
    conn.commit()
    print("All columns added successfully!")

print("Database schema fixed!")
