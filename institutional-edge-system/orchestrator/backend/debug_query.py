
from app.api.database import SessionLocal
from app.models.database import BotSlot

print("--- DEBUG QUERY START ---")
db = SessionLocal()
try:
    slots = db.query(BotSlot).all()
    print(f"Total slots in DB: {len(slots)}")
    for s in slots:
        print(f"ID: {s.id}, Symbol: '{s.symbol}', Enabled: {s.enabled}, Session: '{s.trading_session}'")

    target = "XAUUSD"
    print(f"Attempting query for Symbol='{target}', Enabled=True")
    slot = db.query(BotSlot).filter(BotSlot.symbol == target, BotSlot.enabled == True).first()
    print(f"Query Result: {slot}")
    if slot:
        print(f"Found Slot ID: {slot.id}")
    else:
        print("Slot NOT found via ORM query.")
finally:
    db.close()
print("--- DEBUG QUERY END ---")
