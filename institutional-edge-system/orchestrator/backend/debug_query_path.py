
import os
from app.core.config import settings
from app.api.database import SessionLocal
from app.models.database import BotSlot

print(f"CWD: {os.getcwd()}")
print(f"DATABASE_URL: {settings.DATABASE_URL}")

db = SessionLocal()
slots = db.query(BotSlot).all()
print(f"Total slots in DB: {len(slots)}")
db.close()
