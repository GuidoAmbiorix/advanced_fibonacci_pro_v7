"""
Check signal confirmations in the database.
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

sys.path.append(str(Path(__file__).parent))
from src.database import DatabaseManager

load_dotenv()

def main():
    db = DatabaseManager()

    print("=== Checking Database ===\n")

    # Check predictions
    with db.get_connection() as conn:
        cursor = conn.execute("SELECT COUNT(*) as cnt FROM predictions")
        pred_count = cursor.fetchone()['cnt']
        print(f"Total predictions: {pred_count}")

        if pred_count > 0:
            cursor = conn.execute("SELECT * FROM predictions ORDER BY timestamp DESC LIMIT 5")
            recent = cursor.fetchall()
            print("\nRecent predictions:")
            for p in recent:
                print(f"  - {p['symbol']} {p['prediction_direction']} {p['confidence']:.1%} at {p['timestamp']}")

    print("\n" + "="*50 + "\n")

    # Check signal confirmations
    with db.get_connection() as conn:
        cursor = conn.execute("SELECT COUNT(*) as cnt FROM signal_confirmations")
        signal_count = cursor.fetchone()['cnt']
        print(f"Total signal confirmations: {signal_count}")

        if signal_count > 0:
            cursor = conn.execute("SELECT * FROM signal_confirmations ORDER BY created_at DESC LIMIT 5")
            recent = cursor.fetchall()
            print("\nRecent signals:")
            for s in recent:
                print(f"  - {s['symbol']} {s['direction']} status={s['status']} score={s['confirmation_score']:.1f} at {s['created_at']}")

        # Check by status
        cursor = conn.execute("SELECT status, COUNT(*) as cnt FROM signal_confirmations GROUP BY status")
        status_counts = cursor.fetchall()
        if status_counts:
            print("\nSignals by status:")
            for row in status_counts:
                print(f"  - {row['status']}: {row['cnt']}")

    db.close()

if __name__ == '__main__':
    main()
