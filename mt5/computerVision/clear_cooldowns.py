"""
Clear all cooldowns to allow trading.
Use this after fixing the ID=0 bug that caused rapid signal accumulation.
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

sys.path.append(str(Path(__file__).parent))
load_dotenv()

from src.database import DatabaseManager

def main():
    """Clear all cooldowns."""
    db = DatabaseManager()

    try:
        with db.get_connection() as conn:
            # Count current cooldowns
            cursor = conn.execute("SELECT COUNT(*) as count FROM trade_cooldowns")
            count = cursor.fetchone()['count']
            print(f"Found {count} active cooldown(s)")

            # Delete all cooldowns
            conn.execute("DELETE FROM trade_cooldowns")
            conn.commit()

            print(f"✅ Cleared all cooldowns")
            print("Signals can now execute (if they pass validation)")

    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        db.close()

if __name__ == '__main__':
    main()
