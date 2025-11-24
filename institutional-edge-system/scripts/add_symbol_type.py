"""
Add symbol_type column to bot_configs table
"""

import os
import sys
from pathlib import Path

# Setup paths
project_root = Path(__file__).parent
backend_path = project_root / "backend" / "app"
sys.path.insert(0, str(backend_path))

# Set working directory
os.chdir(str(project_root))

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load environment
load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5433/institutional_edge')

print("=" * 70)
print("Adding symbol_type column to bot_configs table")
print("=" * 70)

engine = create_engine(DATABASE_URL)

try:
    with engine.connect() as conn:
        # Check if column already exists
        result = conn.execute(text("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name='bot_configs' AND column_name='symbol_type'
        """))

        if result.fetchone():
            print("[INFO] Column 'symbol_type' already exists")
        else:
            # Add the column
            conn.execute(text("""
                ALTER TABLE bot_configs
                ADD COLUMN symbol_type VARCHAR DEFAULT 'forex'
            """))
            conn.commit()
            print("[OK] Added 'symbol_type' column to bot_configs table")

        # Update existing records
        # Set BTCUSD to crypto
        conn.execute(text("""
            UPDATE bot_configs
            SET symbol_type = 'crypto'
            WHERE symbol LIKE '%BTC%' OR symbol LIKE '#%'
        """))
        conn.commit()
        print("[OK] Updated existing bot configs with correct symbol_type")

        # Show updated configs
        result = conn.execute(text("SELECT id, name, symbol, symbol_type FROM bot_configs"))
        configs = result.fetchall()

        if configs:
            print("\nCurrent bot configurations:")
            for config in configs:
                print(f"   ID {config[0]}: {config[1]} - {config[2]} ({config[3]})")

    print("\n" + "=" * 70)
    print("[OK] Database update completed successfully!")
    print("=" * 70)

except Exception as e:
    print(f"[ERROR] Failed to update database: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
