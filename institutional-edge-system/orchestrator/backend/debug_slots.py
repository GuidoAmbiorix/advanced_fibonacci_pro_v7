
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.models.database import Base, BotSlot
import os

# Use the path from docker-compose or standard local path
if os.path.exists("backend.db"):
    db_path = "backend.db"
elif os.path.exists("app/backend.db"):
    db_path = "app/backend.db"
else:
    # Try absolute path based on user's workspace
    db_path = r"c:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\institutional-edge-system\backend\backend.db"

print(f"Connecting to DB at: {db_path}")
SQLALCHEMY_DATABASE_URL = f"sqlite:///{db_path}"

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
db = SessionLocal()

try:
    print("\n--- Inspecting Bot Slots ---")
    slots = db.query(BotSlot).all()
    for slot in slots:
        print(f"ID: {slot.id} | Symbol: {slot.symbol} | Enabled: {slot.enabled}")
        print(f"  > Trading Session: '{slot.trading_session}'")
        print(f"  > Engine Type: {slot.engine_type}")
        print(f"  > Config Config: {slot.engine_config}") # Check if json config overrides it
        print("-" * 30)
finally:
    db.close()
