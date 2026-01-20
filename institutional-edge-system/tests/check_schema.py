
import sqlite3
import os

# Try to find the database file
db_path = "app.db" # Default guess
if not os.path.exists(db_path):
    # Search common locations
    possible_paths = ["backend/app.db", "database.db", "backend/database.db", "sql_app.db"]
    for p in possible_paths:
        if os.path.exists(p):
            db_path = p
            break

print(f"Checking database at: {db_path}")

if not os.path.exists(db_path):
    print("❌ Database file not found")
    sys.exit(1)

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get columns for bot_slots
    cursor.execute("PRAGMA table_info(bot_slots)")
    columns = cursor.fetchall()
    
    print("\nColumns in bot_slots:")
    found_cols = [col[1] for col in columns]
    for col in columns:
        print(f" - {col[1]} ({col[2]})")
        
    # Check for expected new columns
    expected = [
        "engine_type", "session_mode", "zigzag_lookback", 
        "enable_order_blocks", "enable_liquidity_sweep"
    ]
    
    print("\nMissing Columns:")
    for exp in expected:
        if exp not in found_cols:
            print(f" ❌ {exp} MISSING")
        else:
            print(f" ✅ {exp} FOUND")
            
    conn.close()

except Exception as e:
    print(f"Error: {e}")
