"""
Fix bot_configs table schema - add missing columns
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
print("Fixing bot_configs table schema")
print("=" * 70)

engine = create_engine(DATABASE_URL)

try:
    with engine.connect() as conn:
        # Get existing columns
        result = conn.execute(text("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name='bot_configs'
        """))
        existing_cols = {row[0] for row in result}

        # Define all required columns with their types and defaults
        required_columns = {
            'mt5_password_encrypted': 'VARCHAR',
            'swing_length': 'INTEGER DEFAULT 10',
            'ob_lookback': 'INTEGER DEFAULT 50',
            'fvg_min_size': 'FLOAT DEFAULT 0.3',
            'vp_lookback': 'INTEGER DEFAULT 100',
        }

        # Add missing columns
        for col_name, col_def in required_columns.items():
            if col_name not in existing_cols:
                print(f"Adding column: {col_name}")
                conn.execute(text(f"""
                    ALTER TABLE bot_configs
                    ADD COLUMN {col_name} {col_def}
                """))
                conn.commit()
                print(f"[OK] Added column: {col_name}")
            else:
                print(f"[INFO] Column '{col_name}' already exists")

        # Show final column list
        result = conn.execute(text("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name='bot_configs'
            ORDER BY ordinal_position
        """))
        columns = [row[0] for row in result]

        print("\n" + "=" * 70)
        print("[OK] Final bot_configs schema:")
        for col in columns:
            print(f"   - {col}")

    print("\n" + "=" * 70)
    print("[OK] Schema update completed successfully!")
    print("=" * 70)

except Exception as e:
    print(f"[ERROR] Failed to update schema: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
