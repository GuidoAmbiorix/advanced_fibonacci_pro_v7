"""
Clean all killzone windows from the PostgreSQL database.
"""
import os
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent))
from src.database import DatabaseManager
from dotenv import load_dotenv

load_dotenv()

def main():
    """Clean all killzone windows from database."""
    db_url = os.environ.get('DATABASE_URL')
    if not db_url:
        print("ERROR: DATABASE_URL environment variable not set")
        sys.exit(1)

    print(f"Connecting to PostgreSQL database...")
    db = DatabaseManager(db_url=db_url)

    with db.get_connection() as conn:
        cursor = conn.execute("SELECT count(*) as cnt FROM killzone_windows")
        count = cursor.fetchone()['cnt']
        print(f"Found {count} killzone entries.")

        print("Deleting all killzone entries...")
        conn.execute("DELETE FROM killzone_windows")
        conn.commit()

        cursor = conn.execute("SELECT count(*) as cnt FROM killzone_windows")
        new_count = cursor.fetchone()['cnt']
        print(f"Remaining entries: {new_count}")

    db.close()
    print("Done. Please restart the trader to reload killzones from config.yaml.")

if __name__ == '__main__':
    main()
