import os
import sys

# Add current directory to path to allow imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.api.database import SessionLocal, init_db
from app.models.database import BotConfig, User

def seed_db():
    print("Initializing database...")
    init_db()
    
    db = SessionLocal()
    try:
        print("Checking for existing data...")
        
        # Create default user if not exists
        user = db.query(User).filter(User.email == "admin@example.com").first()
        if not user:
            user = User(
                email="admin@example.com",
                username="admin",
                hashed_password="hashed_password_here", # In a real app, hash this
                is_active=True,
                is_admin=True
            )
            db.add(user)
            db.commit()
            db.refresh(user)
            print(f"✅ Created default user: {user.email} (ID: {user.id})")
        else:
            print(f"ℹ️ User already exists: {user.email} (ID: {user.id})")
        
        # Create default bot configs for requested symbols
        symbols = [
            "EURUSD", "GBPUSD", "USDJPY", "USDCAD", "AUDUSD", 
            "NZDUSD", "GBPJPY", "EURJPY", "XAUUSD", "GBPCAD"
        ]
        
        for i, symbol in enumerate(symbols, 1):
            bot_name = f"{symbol} H1 Strategy"
            bot = db.query(BotConfig).filter(BotConfig.symbol == symbol).first()
            
            if not bot:
                bot = BotConfig(
                    user_id=user.id,
                    name=bot_name,
                    symbol=symbol,
                    timeframe="H1",
                    risk_percent=1.0,
                    max_trades=5,
                    is_active=False,
                    min_confluence_score=6,
                    swing_length=10,
                    ob_lookback=50,
                    fvg_min_size=0.3,
                    vp_lookback=100
                )
                db.add(bot)
                print(f"✅ Created bot config: {bot.name}")
            else:
                print(f"ℹ️ Bot config already exists: {bot.name}")
        
        db.commit()
            
        print("\nDatabase seeding completed successfully!")
            
    except Exception as e:
        print(f"❌ Error seeding database: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    seed_db()
