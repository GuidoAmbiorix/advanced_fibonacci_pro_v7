import sqlite3
import os
from pathlib import Path

# Path to database
db_path = Path("data/cv_agent.db")

if not db_path.exists():
    print(f"Database not found at {db_path}")
    exit(1)

print(f"Connecting to database at {db_path}...")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Check current count
cursor.execute("SELECT count(*) FROM killzone_windows")
count = cursor.fetchone()[0]
print(f"Found {count} killzone entries.")

# Delete all entries
print("Deleting all killzone entries...")
cursor.execute("DELETE FROM killzone_windows")
conn.commit()

# Verify
cursor.execute("SELECT count(*) FROM killzone_windows")
new_count = cursor.fetchone()[0]
print(f"Remaining entries: {new_count}")

conn.close()
print("Done. Please restart the trader to reload killzones from config.yaml.")
