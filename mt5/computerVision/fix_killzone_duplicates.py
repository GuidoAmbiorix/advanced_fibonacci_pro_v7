"""
Fix killzone duplicate entries in PostgreSQL database.
"""
import os
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent))
from src.database import DatabaseManager
from dotenv import load_dotenv

load_dotenv()

def main():
    """Remove duplicate killzones and add unique constraint."""
    db_url = os.environ.get('DATABASE_URL')
    if not db_url:
        print("ERROR: DATABASE_URL environment variable not set")
        sys.exit(1)

    print(f"Connecting to PostgreSQL database...")
    db = DatabaseManager(db_url=db_url)

    try:
        with db.get_connection() as conn:
            # Count current entries
            cursor = conn.execute("SELECT count(*) as total_count FROM killzone_windows")
            total_count = cursor.fetchone()['total_count']

            cursor = conn.execute("SELECT count(DISTINCT name) as unique_count FROM killzone_windows")
            unique_count = cursor.fetchone()['unique_count']

            print(f"Total killzone entries: {total_count}")
            print(f"Unique killzone names: {unique_count}")

            if total_count > unique_count:
                print("Duplicates detected. Cleaning up...")

                # Keep only the latest entry for each name
                conn.execute("""
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

            # Add UNIQUE constraint if it doesn't exist
            print("Ensuring unique constraint on 'name'...")
            conn.execute("""
                ALTER TABLE killzone_windows
                DROP CONSTRAINT IF EXISTS killzone_windows_name_unique
            """)
            conn.execute("""
                ALTER TABLE killzone_windows
                ADD CONSTRAINT killzone_windows_name_unique UNIQUE (name)
            """)

            conn.commit()
            print("Optimization complete.")

    except Exception as e:
        print(f"Error: {e}")
    finally:
        db.close()

    print("Done.")

if __name__ == '__main__':
    main()
