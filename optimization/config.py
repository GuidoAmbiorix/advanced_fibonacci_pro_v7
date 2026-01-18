"""
Configuration settings for MT5 Native optimization.
"""
import os
from pathlib import Path

# MT5 Installation (auto-detect or override)
MT5_PATH = os.environ.get("MT5_PATH", None)  # None = auto-detect

# Database
DATA_DIR = Path(__file__).parent.parent / "data"
DB_PATH = DATA_DIR / "optimization.db"

# Ensure data directory exists
DATA_DIR.mkdir(exist_ok=True)

# Default optimization settings
DEFAULT_N_TRIALS = 100
DEFAULT_DEPOSIT = 10000
DEFAULT_TIMEFRAME = "H1"
DEFAULT_SYMBOL = "XAUUSD"

# Date ranges
DEFAULT_DATE_FROM = "2024.01.01"
DEFAULT_DATE_TO = "2024.12.31"

print(f"✅ Configuration loaded - Database: {DB_PATH}")
