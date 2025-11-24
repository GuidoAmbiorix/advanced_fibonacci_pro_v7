"""
Update bot 1 to Bitcoin Alpha
"""

import os
import sys
from pathlib import Path

# Setup paths
project_root = Path(__file__).parent
backend_path = project_root / "backend" / "app"
sys.path.insert(0, str(backend_path))

# Set working directory
os.chdir(str(project_root))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

# Load environment
load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5433/institutional_edge')

print("Updating bot configuration 1...")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
db = SessionLocal()

try:
    from models.database import BotConfig

    # Get bot 1
    bot = db.query(BotConfig).filter(BotConfig.id == 1).first()
    if bot:
        bot.name = "Bitcoin Alpha"
        bot.symbol = "#BTCUSD"
        bot.timeframe = "H1"
        db.commit()
        print(f"[OK] Updated bot 1: {bot.name} ({bot.symbol} {bot.timeframe})")
    else:
        print("[ERROR] Bot 1 not found")

except Exception as e:
    print(f"[ERROR] {e}")
    import traceback
    traceback.print_exc()
finally:
    db.close()
