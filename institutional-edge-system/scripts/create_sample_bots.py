"""
Create sample bot configurations
"""

import os
import sys
from pathlib import Path

# Setup paths
# Setup paths
project_root = Path(__file__).parent.parent
# IMPORTANT: point to backend so we can import 'app.models.database' or just 'models.database'
# If backend/app is in path, then 'models.database' works if run from there
# Let's add 'backend/app' to path to make imports like 'from models.database' work 
# assuming 'models' is a folder inside 'app'
backend_app_path = project_root / "backend" / "app"
sys.path.insert(0, str(backend_app_path))

# Set working directory to project root
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



    # Create Main Portfolio Bot
    main_bot_name = "Institutional Scalper"
    
    # Check if main bot exists
    existing_bot = db.query(BotConfig).filter(
        BotConfig.user_id == admin.id,
        BotConfig.name == main_bot_name
    ).first()

    if not existing_bot:
        # Create the Container Bot Configuration
        bot = BotConfig(
            user_id=admin.id,
            name=main_bot_name,
            symbol="XAUUSD", # Primary Display Symbol
            symbol_type="commodities",
            timeframe="M5",
            risk_percent=1.0, # Default Per-Trade Risk (will be overriden by slots if needed)
            max_portfolio_risk_percent=4.0, # Max Risk: 4%
            max_positions_per_symbol=2,     # Max Pos/Symbol: 2
            
            min_confluence_score=6,
            max_trades=10, 
            
            # Global Winning Params (Defaults)
            tp_ratio=2.0,
            sl_atr_multiplier=1.5,
            tsl_mode="ATR",
            partial_tp_on=True,
            max_trade_duration_hours=4.0, 
        )
        db.add(bot)
        db.commit() # Commit to get ID
        db.refresh(bot)
        print(f"[OK] Created Main Bot: {bot.name}")
        
        # Define Slot Configurations
        slots_config = [
            {
                "slot_number": 1,
                "symbol": "EURJPY", # The Beast (Cross)
                "timeframe": "M5",
                "risk_percent": 0.75,
                "tp_ratio": 2.0,
                "sl_atr_multiplier": 1.5,
                "min_confluence_score": 7,
                "tsl_mode": "ATR",
                "enabled": True
            },
            {
                "slot_number": 2,
                "symbol": "GBPJPY", # The Dragon (Cross)
                "timeframe": "M5",
                "risk_percent": 0.75,
                "tp_ratio": 2.0,
                "sl_atr_multiplier": 1.5,
                "min_confluence_score": 7,
                "tsl_mode": "ATR",
                "enabled": True
            },
            {
                "slot_number": 3,
                "symbol": "EURGBP", # The Channel (Cross)
                "timeframe": "M5",
                "risk_percent": 1.0,
                "tp_ratio": 1.5,
                "sl_atr_multiplier": 1.0,
                "min_confluence_score": 7,
                "tsl_mode": "ATR",
                "enabled": True
            },
            {
                "slot_number": 4,
                "symbol": "AUDJPY", # Risk Proxy (Cross)
                "timeframe": "M5",
                "risk_percent": 0.75,
                "tp_ratio": 2.0,
                "sl_atr_multiplier": 1.5,
                "min_confluence_score": 7,
                "tsl_mode": "ATR",
                "enabled": True
            }
        ]

        # Create Slots
        from models.database import BotSlot
        for slot_data in slots_config:
            slot = BotSlot(
                bot_config_id=bot.id,
                **slot_data
            )
            db.add(slot)
            print(f"   [+] Added Slot {slot_data['slot_number']}: {slot_data['symbol']}")

    else:
        print(f"[INFO] Bot '{main_bot_name}' already exists")

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
