import sys
import os

# Add current directory to path so we can import app
sys.path.append(os.getcwd())

from sqlalchemy import text
from app.api.database import engine

def add_column():
    with engine.connect() as conn:
        try:
            # Check if column exists first to avoid error
            result = conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='bot_configs' AND column_name='cooldown_minutes'"))
            if result.fetchone():
                print("Column cooldown_minutes already exists.")
                return

            conn.execute(text("ALTER TABLE bot_configs ADD COLUMN cooldown_minutes INTEGER DEFAULT 15"))
            conn.commit()
            print("Successfully added cooldown_minutes column")
        except Exception as e:
            print(f"Error: {e}")

if __name__ == "__main__":
    add_column()
