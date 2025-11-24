"""
Add AI confidence columns to signals table
"""

import os
import sys
from pathlib import Path

# Setup paths
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load environment
load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5433/institutional_edge')

print("=" * 70)
print("Adding AI columns to signals table")
print("=" * 70)

engine = create_engine(DATABASE_URL)

try:
    with engine.connect() as conn:
        # Check if columns already exist
        result = conn.execute(text("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name='signals' AND column_name IN ('ai_confidence', 'ai_recommendation')
        """))

        existing_cols = {row[0] for row in result}

        if 'ai_confidence' not in existing_cols:
            conn.execute(text("""
                ALTER TABLE signals
                ADD COLUMN ai_confidence FLOAT DEFAULT 0.0
            """))
            conn.commit()
            print("[OK] Added 'ai_confidence' column to signals table")
        else:
            print("[INFO] Column 'ai_confidence' already exists")

        if 'ai_recommendation' not in existing_cols:
            conn.execute(text("""
                ALTER TABLE signals
                ADD COLUMN ai_recommendation VARCHAR DEFAULT 'UNCERTAIN'
            """))
            conn.commit()
            print("[OK] Added 'ai_recommendation' column to signals table")
        else:
            print("[INFO] Column 'ai_recommendation' already exists")

    print("\n" + "=" * 70)
    print("[OK] Database migration completed successfully!")
    print("=" * 70)

except Exception as e:
    print(f"[ERROR] Failed to update database: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
