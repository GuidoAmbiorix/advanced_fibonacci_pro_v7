import sys
from pathlib import Path

# Add project root to path
root_dir = Path(__file__).parent
sys.path.append(str(root_dir))
sys.path.append(str(root_dir / "mt5" / "computerVision"))

from mt5.computerVision.src.database.db_manager import DatabaseManager

def test_initialization():
    print("Initializing DatabaseManager (Trial 1)...")
    db = DatabaseManager()
    
    windows = db.get_killzone_windows(active_only=False)
    print(f"Windows after Trial 1: {len(windows)}")
    
    print("\nInitializing DatabaseManager (Trial 2)...")
    db2 = DatabaseManager()
    
    windows2 = db.get_killzone_windows(active_only=False)
    print(f"Windows after Trial 2: {len(windows2)}")
    
    if len(windows) == len(windows2):
        print("\nSUCCESS: No duplicates created!")
    else:
        print(f"\nFAILURE: Duplicates created! Count grew from {len(windows)} to {len(windows2)}")

if __name__ == "__main__":
    test_initialization()
