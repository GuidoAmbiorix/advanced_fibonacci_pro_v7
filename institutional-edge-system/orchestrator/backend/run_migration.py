from sqlalchemy import create_engine, text
import sys
import os

# Add parent dir to path to allow imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.config import settings

def migrate():
    print("Starting migration...")
    
    # Construct DB URL
    database_url = settings.DATABASE_URL
    
    # Force SQLite fallback finding the file
    if os.path.exists("sql_app.db"):
        print("Found sql_app.db, forcing SQLite mode...")
        database_url = "sqlite:///sql_app.db"
    
    elif "asyncpg" in database_url:
        database_url = database_url.replace("postgresql+asyncpg://", "postgresql+psycopg2://")
    
    # Force port fix if mismatch
    if ":5433" in database_url and "sqlite" not in database_url:
        print("Swapping port 5433 -> 5432 for migration connection...")
        database_url = database_url.replace(":5433", ":5432")

    connect_args = {}
    if "sqlite" in database_url:
        connect_args["check_same_thread"] = False
    
    engine = create_engine(database_url, connect_args=connect_args)

    with engine.connect() as conn:
        trans = conn.begin()
        
        # --- BotConfig ---
        try:
            print("Checking bot_configs.engine_type...")
            conn.execute(text("SELECT engine_type FROM bot_configs LIMIT 1"))
            print(" - Exists")
        except Exception:
            print(" - Missing. Adding engine_type...")
            conn.execute(text("ALTER TABLE bot_configs ADD COLUMN engine_type VARCHAR DEFAULT 'ADAPTIVE'"))

        try:
            print("Checking bot_configs.engine_config...")
            conn.execute(text("SELECT engine_config FROM bot_configs LIMIT 1"))
            print(" - Exists")
        except Exception:
            print(" - Missing. Adding engine_config...")
            if "sqlite" in database_url:
                 conn.execute(text("ALTER TABLE bot_configs ADD COLUMN engine_config TEXT DEFAULT '{}'"))
            else:
                 conn.execute(text("ALTER TABLE bot_configs ADD COLUMN engine_config JSON DEFAULT '{}'"))

        # --- BotSlot ---
        try:
            print("Checking bot_slots.engine_type...")
            conn.execute(text("SELECT engine_type FROM bot_slots LIMIT 1"))
            print(" - Exists")
        except Exception:
             print(" - Missing. Adding engine_type...")
             conn.execute(text("ALTER TABLE bot_slots ADD COLUMN engine_type VARCHAR DEFAULT 'ADAPTIVE'"))

        try:
            print("Checking bot_slots.engine_config...")
            conn.execute(text("SELECT engine_config FROM bot_slots LIMIT 1"))
            print(" - Exists")
        except Exception:
             print(" - Missing. Adding engine_config...")
             if "sqlite" in database_url:
                  conn.execute(text("ALTER TABLE bot_slots ADD COLUMN engine_config TEXT DEFAULT '{}'"))
             else:
                  conn.execute(text("ALTER TABLE bot_slots ADD COLUMN engine_config JSON DEFAULT '{}'"))
        
        trans.commit()
        print("Migration complete!")

if __name__ == "__main__":
    migrate()
