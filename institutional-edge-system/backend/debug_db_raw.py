
import sqlite3
import os

db_path = "/app/data/instance_1.db"
if not os.path.exists(db_path):
    print(f"DB not found at {db_path}, trying app/backend.db")
    db_path = "app/backend.db"

if not os.path.exists(db_path):
    print("DB NOT FOUND!")
    exit(1)

print(f"Opening DB: {db_path}")
conn = sqlite3.connect(db_path)
c = conn.cursor()

try:
    print("\n--- Minimal Check ---")
    c.execute("PRAGMA table_info(bot_slots)")
    columns = c.fetchall()
    col_names = [col[1] for col in columns]
    
    if "trading_session" in col_names:
        print("trading_session: FOUND")
        c.execute("SELECT id, symbol, min_confluence_score, trading_session, enabled FROM bot_slots")
        for row in c.fetchall():
            print(f"Slot {row[0]} ({row[1]}) Enabled:{row[4]} Session:{row[3]}")
    else:
        print("trading_session: MISSING")

    if "session_mode" in col_names:
        print("session_mode: FOUND")
    else:
        print("session_mode: MISSING")

    print("\n--- BotConfig Check ---")
    c.execute("PRAGMA table_info(bot_configs)")
    columns = c.fetchall()
    col_names = [col[1] for col in columns]
    print(f"BotConfig Columns: {col_names}")
    
    if "trading_session" in col_names:
        print("BotConfig.trading_session: FOUND")
    else:
        print("BotConfig.trading_session: MISSING")

    c.execute("SELECT id, name FROM bot_configs")
    for row in c.fetchall():
        print(f"BotConfig {row[0]}: {row[1]}")

except Exception as e:
    print(f"Error: {e}")
finally:
    conn.close()
