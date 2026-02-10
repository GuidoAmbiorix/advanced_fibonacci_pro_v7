"""
Comprehensive verification script for PostgreSQL-only migration.
Tests database connection, operations, and verifies no SQLite remnants.
"""
import os
import sys
from datetime import datetime
from pathlib import Path
import pandas as pd

# Add project root to path
sys.path.append(str(Path(__file__).parent))

from src.database import DatabaseManager
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def test_connection():
    """Test basic PostgreSQL connection."""
    print("\n=== Test 1: Database Connection ===")
    try:
        db = DatabaseManager()
        print("✓ Database connection successful")
        db.close()
        return True
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return False

def test_market_data(db):
    """Test market data insertion and retrieval."""
    print("\n=== Test 2: Market Data Operations ===")
    try:
        # Create test data
        test_data = pd.DataFrame({
            'timestamp': [datetime.now()],
            'open': [1.1234],
            'high': [1.1250],
            'low': [1.1220],
            'close': [1.1245],
            'tick_volume': [1000],
            'spread': [2],
            'real_volume': [0]
        })

        # Insert
        db.insert_market_data('EURUSD', 'H1', test_data)
        print("✓ Market data inserted")

        # Retrieve
        retrieved = db.get_market_data('EURUSD', 'H1', limit=10)
        print(f"✓ Market data retrieved: {len(retrieved)} rows")

        return True
    except Exception as e:
        print(f"✗ Market data test failed: {e}")
        return False

def test_config(db):
    """Test configuration operations."""
    print("\n=== Test 3: Configuration Operations ===")
    try:
        # Set config
        db.set_config('test_key', 'test_value')
        print("✓ Config value set")

        # Get config
        value = db.get_config('test_key')
        assert value == 'test_value', f"Expected 'test_value', got '{value}'"
        print("✓ Config value retrieved correctly")

        return True
    except Exception as e:
        print(f"✗ Config test failed: {e}")
        return False

def test_logging(db):
    """Test logging operations."""
    print("\n=== Test 4: Logging Operations ===")
    try:
        # Insert log
        db.log('INFO', 'TEST', 'Migration verification test')
        print("✓ Log entry created")

        # Retrieve logs
        logs = db.get_logs(component='TEST', limit=5)
        assert len(logs) > 0, "No logs retrieved"
        print(f"✓ Logs retrieved: {len(logs)} entries")

        return True
    except Exception as e:
        print(f"✗ Logging test failed: {e}")
        return False

def test_models(db):
    """Test model operations."""
    print("\n=== Test 5: Model Operations ===")
    try:
        # Insert model
        model_id = db.insert_model(
            name='test_model',
            version='1.0',
            model_type='LSTM',
            hyperparameters={'layers': 3, 'units': 64},
            training_accuracy=0.85,
            validation_accuracy=0.82
        )
        print(f"✓ Model inserted with ID: {model_id}")

        # Retrieve model
        model = db.get_model(model_id)
        assert model is not None, "Model not found"
        assert model['name'] == 'test_model', "Model name mismatch"
        print("✓ Model retrieved correctly")

        return True
    except Exception as e:
        print(f"✗ Model test failed: {e}")
        return False

def test_killzones(db):
    """Test killzone operations."""
    print("\n=== Test 6: Killzone Operations ===")
    try:
        # Get killzones
        killzones = db.get_killzone_windows(active_only=False)
        print(f"✓ Killzones retrieved: {len(killzones)} entries")

        return True
    except Exception as e:
        print(f"✗ Killzone test failed: {e}")
        return False

def verify_no_sqlite_code():
    """Verify no SQLite code remains."""
    print("\n=== Test 7: SQLite Code Verification ===")

    import subprocess

    # Check for sqlite3 imports
    result = subprocess.run(
        ['grep', '-r', 'import sqlite3', '--include=*.py', '--exclude-dir=.git'],
        cwd=Path(__file__).parent,
        capture_output=True,
        text=True
    )

    if result.returncode == 0 and result.stdout.strip():
        print(f"✗ Found sqlite3 imports:\n{result.stdout}")
        return False
    else:
        print("✓ No sqlite3 imports found")

    # Check for cv_agent.db references
    result = subprocess.run(
        ['grep', '-r', 'cv_agent.db', '--include=*.py', '--exclude-dir=.git'],
        cwd=Path(__file__).parent,
        capture_output=True,
        text=True
    )

    if result.returncode == 0 and result.stdout.strip():
        print(f"✗ Found cv_agent.db references:\n{result.stdout}")
        return False
    else:
        print("✓ No cv_agent.db references found")

    # Check for PRAGMA commands
    result = subprocess.run(
        ['grep', '-r', 'PRAGMA', '--include=*.py', '--exclude-dir=.git'],
        cwd=Path(__file__).parent,
        capture_output=True,
        text=True
    )

    if result.returncode == 0 and result.stdout.strip():
        print(f"✗ Found PRAGMA commands:\n{result.stdout}")
        return False
    else:
        print("✓ No PRAGMA commands found")

    return True

def verify_database_manager():
    """Verify DatabaseManager only uses PostgreSQL."""
    print("\n=== Test 8: DatabaseManager Verification ===")

    db_manager_path = Path(__file__).parent / "src" / "database" / "db_manager.py"
    with open(db_manager_path, 'r') as f:
        content = f.read()

    # Check for removed items
    checks = [
        ('sqlite3', '✗ sqlite3 import found'),
        ('POSTGRES_AVAILABLE', '✗ POSTGRES_AVAILABLE flag found'),
        ('PostgresConnectionWrapper', '✗ Old PostgresConnectionWrapper found'),
        ('_convert_query_to_postgres', '✗ Query conversion method found'),
        ('self.db_type', '✗ Database type checking found'),
        ('INSERT OR REPLACE', '✗ SQLite syntax found'),
    ]

    failed = []
    for search_term, error_msg in checks:
        if search_term in content:
            failed.append(error_msg)

    if failed:
        for msg in failed:
            print(msg)
        return False
    else:
        print("✓ DatabaseManager is PostgreSQL-only")
        return True

def main():
    """Run all verification tests."""
    print("=" * 60)
    print("PostgreSQL Migration Verification")
    print("=" * 60)

    # Check environment
    db_url = os.environ.get('DATABASE_URL')
    if not db_url:
        print("\n✗ DATABASE_URL environment variable not set")
        print("  Please ensure .env file exists with DATABASE_URL configured")
        sys.exit(1)

    print(f"\nDATABASE_URL: {db_url}")

    # Test connection first
    if not test_connection():
        print("\n✗ Cannot proceed without database connection")
        print("  Please ensure PostgreSQL is running:")
        print("  $ docker-compose up postgres -d")
        sys.exit(1)

    # Run all tests
    db = None
    try:
        db = DatabaseManager()

        results = {
            'Market Data': test_market_data(db),
            'Configuration': test_config(db),
            'Logging': test_logging(db),
            'Models': test_models(db),
            'Killzones': test_killzones(db),
            'SQLite Code': verify_no_sqlite_code(),
            'DatabaseManager': verify_database_manager(),
        }

        # Summary
        print("\n" + "=" * 60)
        print("Test Summary")
        print("=" * 60)

        passed = sum(1 for v in results.values() if v)
        total = len(results)

        for test_name, result in results.items():
            status = "✓ PASS" if result else "✗ FAIL"
            print(f"{test_name:20} {status}")

        print("-" * 60)
        print(f"Total: {passed}/{total} tests passed")
        print("=" * 60)

        if passed == total:
            print("\n🎉 All tests passed! Migration successful!")
            sys.exit(0)
        else:
            print(f"\n⚠ {total - passed} test(s) failed")
            sys.exit(1)

    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        if db:
            db.close()

if __name__ == '__main__':
    main()
