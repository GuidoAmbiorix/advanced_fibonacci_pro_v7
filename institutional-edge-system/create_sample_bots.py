"""
Create sample bot configurations
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
from models.database import BotConfig, User
from dotenv import load_dotenv

# Load environment
load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5433/institutional_edge')

print("=" * 70)
print("Creating sample bot configurations")
print("=" * 70)

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
db = SessionLocal()

try:
    # Get or create admin user
    admin = db.query(User).filter(User.email == "admin@institutional-edge.com").first()

    if not admin:
        print("[ERROR] Admin user not found. Run init_database.py first.")
        sys.exit(1)

    # Create bot configurations
    bots = [
        {
            "name": "Bitcoin Alpha",
            "symbol": "BTCUSD",
            "symbol_type": "crypto",
            "timeframe": "H1",
            "risk_percent": 2.0,
            "min_confluence_score": 6,
            "max_trades": 3,
        },
        {
            "name": "EURUSD Trader",
            "symbol": "EURUSD",
            "symbol_type": "forex",
            "timeframe": "H1",
            "risk_percent": 2.0,
            "min_confluence_score": 6,
            "max_trades": 3,
        },
        {
            "name": "GBPUSD Trader",
            "symbol": "GBPUSD",
            "symbol_type": "forex",
            "timeframe": "H1",
            "risk_percent": 2.0,
            "min_confluence_score": 6,
            "max_trades": 3,
        },
        {
            "name": "Ethereum Pro",
            "symbol": "ETHUSD",
            "symbol_type": "crypto",
            "timeframe": "H1",
            "risk_percent": 2.0,
            "min_confluence_score": 6,
            "max_trades": 3,
        },
    ]

    for bot_data in bots:
        # Check if bot already exists
        existing = db.query(BotConfig).filter(
            BotConfig.user_id == admin.id,
            BotConfig.symbol == bot_data["symbol"]
        ).first()

        if not existing:
            bot = BotConfig(
                user_id=admin.id,
                **bot_data
            )
            db.add(bot)
            print(f"[OK] Created bot: {bot_data['name']} ({bot_data['symbol']})")
        else:
            print(f"[INFO] Bot for {bot_data['symbol']} already exists")

    db.commit()

    # Show all bots
    all_bots = db.query(BotConfig).all()
    print("\n" + "=" * 70)
    print(f"Total bot configurations: {len(all_bots)}")
    for bot in all_bots:
        print(f"   ID {bot.id}: {bot.name} - {bot.symbol} ({bot.symbol_type}) - {bot.timeframe}")

    print("\n" + "=" * 70)
    print("[OK] Sample bots created successfully!")
    print("=" * 70)

except Exception as e:
    print(f"[ERROR] Failed to create bots: {e}")
    import traceback
    traceback.print_exc()
    db.rollback()
    sys.exit(1)
finally:
    db.close()
