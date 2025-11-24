"""
Add default bot configurations to database
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

print("=" * 70)
print("Adding Bot Configurations to Database")
print("=" * 70)
print(f"\nDatabase URL: {DATABASE_URL.split('@')[1] if '@' in DATABASE_URL else DATABASE_URL}")

# Create engine and session
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
db = SessionLocal()

try:
    from models.database import BotConfig, User

    # Check if admin user exists
    admin = db.query(User).filter(User.email == "admin@institutional-edge.com").first()
    if not admin:
        print("[ERROR] Admin user not found. Please run init_database.py first")
        sys.exit(1)

    print(f"[OK] Found admin user (ID: {admin.id})")

    # Check existing bots
    existing_bots = db.query(BotConfig).all()
    print(f"[INFO] Found {len(existing_bots)} existing bot configurations")

    # Bot configurations to create
    bot_configs = [
        {
            'id': 1,
            'name': 'Bitcoin Alpha',
            'symbol': '#BTCUSD',
            'timeframe': 'H1',
            'risk_percent': 2.0,
            'min_confluence_score': 6,
            'max_trades': 3,
            'swing_length': 10,
            'ob_lookback': 50,
            'fvg_min_size': 0.3,
            'vp_lookback': 100,
            'is_active': False
        },
        {
            'id': 2,
            'name': 'Euro Sniper',
            'symbol': 'EURUSD',
            'timeframe': 'H1',
            'risk_percent': 2.0,
            'min_confluence_score': 6,
            'max_trades': 3,
            'swing_length': 10,
            'ob_lookback': 50,
            'fvg_min_size': 0.3,
            'vp_lookback': 100,
            'is_active': False
        }
    ]

    for config in bot_configs:
        # Check if bot already exists
        existing = db.query(BotConfig).filter(BotConfig.id == config['id']).first()

        if existing:
            print(f"[INFO] Bot '{config['name']}' (ID: {config['id']}) already exists")
        else:
            # Create new bot
            bot = BotConfig(
                id=config['id'],
                user_id=admin.id,
                name=config['name'],
                symbol=config['symbol'],
                timeframe=config['timeframe'],
                risk_percent=config['risk_percent'],
                min_confluence_score=config['min_confluence_score'],
                max_trades=config['max_trades'],
                swing_length=config['swing_length'],
                ob_lookback=config['ob_lookback'],
                fvg_min_size=config['fvg_min_size'],
                vp_lookback=config['vp_lookback'],
                is_active=config['is_active']
            )
            db.add(bot)
            print(f"[OK] Created bot '{config['name']}' (ID: {config['id']}) for {config['symbol']} {config['timeframe']}")

    # Commit all changes
    db.commit()

    # Verify
    all_bots = db.query(BotConfig).all()
    print(f"\n[OK] Total bot configurations in database: {len(all_bots)}")
    for bot in all_bots:
        print(f"   - ID {bot.id}: {bot.name} ({bot.symbol} {bot.timeframe})")

    print("\n" + "=" * 70)
    print("[OK] Bot configurations added successfully!")
    print("=" * 70)

except Exception as e:
    print(f"[ERROR] Failed to add bot configurations: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
finally:
    db.close()
