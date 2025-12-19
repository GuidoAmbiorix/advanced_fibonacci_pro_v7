import sys
import os
from sqlalchemy import text

# Add the parent directory to sys.path to allow importing app modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.api.database import engine

def update_schema():
    print("Starting schema update...")
    with engine.connect() as connection:
        # List of columns to add
        columns = [
            ("rsi_period", "INTEGER DEFAULT 14"),
            ("rsi_overbought", "INTEGER DEFAULT 70"),
            ("rsi_oversold", "INTEGER DEFAULT 30")
        ]
        
        for col_name, col_type in columns:
            try:
                print(f"Adding column {col_name}...")
                connection.execute(text(f"ALTER TABLE bot_configs ADD COLUMN {col_name} {col_type}"))
                print(f"Successfully added {col_name}")
            except Exception as e:
                # Check if error is because column already exists
                if "already exists" in str(e):
                    print(f"Column {col_name} already exists, skipping.")
                else:
                    print(f"Error adding {col_name}: {e}")
        
        connection.commit()
    print("Schema update completed.")

if __name__ == "__main__":
    update_schema()
