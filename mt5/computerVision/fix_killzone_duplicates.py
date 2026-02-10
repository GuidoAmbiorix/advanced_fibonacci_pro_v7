import sqlite3
import os
from pathlib import Path

# Path to database
# Try different locations based on project structure
possible_paths = [
    Path("mt5/computerVision/data/cv_agent.db"),
    Path("data/cv_agent.db"),
    Path("../data/cv_agent.db")
]

db_path = None
for p in possible_paths:
    if p.exists():
        db_path = p
        break

if not db_path:
    # If not found, try to resolve relative to this script
    script_dir = Path(__file__).parent
    db_path = script_dir / "mt5" / "computerVision" / "data" / "cv_agent.db"
    if not db_path.exists():
        db_path = script_dir / "data" / "cv_agent.db"

if not db_path.exists():
    print(f"Database not found. Checked: {[str(p) for p in possible_paths]}")
    exit(1)

print(f"Connecting to database at {db_path}...")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

try:
    # 1. Count current entries
    cursor.execute("SELECT count(*) FROM killzone_windows")
    total_count = cursor.fetchone()[0]
    cursor.execute("SELECT count(DISTINCT name) FROM killzone_windows")
    unique_count = cursor.fetchone()[0]
    
    print(f"Total killzone entries: {total_count}")
    print(f"Unique killzone names: {unique_count}")
    
    if total_count > unique_count:
        print("Duplicates detected. Cleaning up...")
        
        # 2. Keep only the latest entry for each name
        cursor.execute("""
            DELETE FROM killzone_windows 
            WHERE id NOT IN (
                SELECT MAX(id) 
                FROM killzone_windows 
                GROUP BY name
            )
        """)
        print(f"Deleted {total_count - unique_count} duplicates.")
    else:
        print("No duplicates found.")
        
    # 3. Add UNIQUE constraint to the table by recreating or adding index
    # SQLite doesn't support ADD CONSTRAINT UNIQUE on existing columns easily
    # But we can create a UNIQUE INDEX
    print("Creating unique index on 'name'...")
    cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_killzone_name ON killzone_windows(name)")
    
    conn.commit()
    print("Optimization complete.")
    
except Exception as e:
    print(f"Error: {e}")
    conn.rollback()
finally:
    conn.close()

print("Done.")
