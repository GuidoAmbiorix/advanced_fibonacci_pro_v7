"""
Diagnostic script to test prediction service directly
"""
import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))

print("=" * 60)
print("PREDICTION SERVICE DIAGNOSTIC TEST")
print("=" * 60)

# Check source code directly
print("\nChecking source file...")
source_file = Path(__file__).parent / "src" / "trading" / "prediction_service.py"
print(f"Source file: {source_file}")
print(f"File exists: {source_file.exists()}")

if source_file.exists():
    with open(source_file, 'r', encoding='utf-8') as f:
        content = f.read()

    if "v2.0" in content:
        print("[OK] Source file has v2.0 marker - NEW CODE IN FILE")
    else:
        print("[FAIL] Source file does NOT have v2.0 marker - OLD CODE IN FILE!")

    if "AUTO-FETCH" in content:
        print("[OK] Source file has AUTO-FETCH logic")
    else:
        print("[FAIL] Source file does NOT have AUTO-FETCH logic")

    # Count the v2.0 markers
    v2_count = content.count("v2.0")
    print(f"Found {v2_count} occurrences of 'v2.0' in source file")

    # Check for specific new logs
    if "PORTFOLIO PREDICTION START" in content:
        print("[OK] Has new portfolio logging")
    else:
        print("[FAIL] Missing new portfolio logging")

    if "Fetched" in content and "bars from DB" in content:
        print("[OK] Has new data fetch logging")
    else:
        print("[FAIL] Missing new data fetch logging")

print("\n" + "=" * 60)
print("Attempting to import module...")
print("=" * 60)

try:
    from src.trading.prediction_service import PredictionService
    print("[OK] Module imported successfully")

    # Check if imported class has the new code
    import inspect
    source = inspect.getsource(PredictionService._generate_prediction)

    if "v2.0" in source:
        print("[OK] Imported class has v2.0 marker - NEW CODE LOADED IN MEMORY")
    else:
        print("[FAIL] Imported class does NOT have v2.0 marker - OLD CODE IN MEMORY!")

    if "AUTO-FETCH" in source:
        print("[OK] Imported class has AUTO-FETCH logic")
    else:
        print("[FAIL] Imported class does NOT have AUTO-FETCH logic")

except Exception as e:
    print(f"[FAIL] Failed to import: {e}")
    import traceback
    traceback.print_exc()

print("\nDone!")
