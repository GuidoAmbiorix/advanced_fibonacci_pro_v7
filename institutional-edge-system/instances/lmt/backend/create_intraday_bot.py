
import asyncio
import os
import sys

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.api.database import SessionLocal, engine
from app.models.database import User, BotConfig, BotSlot, RiskProfile, Base
from sqlalchemy import text

async def create_intraday_bot():
    """Create the Stable Duo Portfolio Bot (Optimized H1 Safe Mode)"""
    
    db = SessionLocal()
    
    try:
        # Get admin user
        admin = db.query(User).filter(User.id == 1).first()
        if not admin:
            print("👤 Creating Default Admin User...")
            admin = User(email="admin@example.com", hashed_password="hashed_password", is_active=True, is_superuser=True)
            db.add(admin)
            db.commit()
            
        print("🔄 Updating 'Stable Duo Portfolio' (H1 Optimized)...")
        
        # 1. DROP BotSlots table to force schema update (since we added columns)
        try:
            print("R force-refreshing 'bot_slots' table schema...")
            BotSlot.__table__.drop(engine)
            print("R Dropped old bot_slots table.")
        except Exception as e:
            print(f"R Table drop skipped (might not exist): {e}")

        # Re-create all tables
        Base.metadata.create_all(bind=engine)
        print("R Schema updated.")

        # 2. Clean up old bots
        old_bots = db.query(BotConfig).filter(BotConfig.name.in_(["Stable Duo Portfolio", "Gold Scalper Pro", "Balanced Portfolio"])).all()
        for old in old_bots:
            db.delete(old)
        db.commit()

        # ==================================================================================
        # 1. CREATE BOT CONFIGURATION
        # ==================================================================================
        BOT_NAME = "Stable Duo Portfolio"
        print(f"🛠️ Creating Bot Config: {BOT_NAME}...")
        
        bot_config = BotConfig(
            user_id=admin.id,
            name=BOT_NAME,
            symbol="EURJPY",  # Primary symbol
            is_active=True,
            timeframe="H1",
            risk_percent=0.5,  # SAFE MODE
            daily_loss_limit_percent=3.0,
            max_portfolio_risk_percent=1.0, 
            max_positions_per_symbol=2,
            
            # Global Defaults
            enable_vwap_strategy=True,
            enable_stoch_strategy=True,
            enable_institutional_strategy=True,
            enable_fibonacci_strategy=True,
            use_adx_filter=True,
            min_confluence_score=7,
            sl_atr_multiplier=1.2,
            tp_ratio=2.0,
            trailing_sl=True,
            tsl_mode="TIERED",
            tsl_activation_r=1.0,
            tsl_atr_period=14,
            tsl_atr_multiplier=1.2,
            rsi_period=14,
            rsi_overbought=70,
            rsi_oversold=30,
            max_trade_duration_hours=4.0,
            partial_tp_on=False,
            partial_tp_amount=0.0
        )
        db.add(bot_config)
        db.flush()
        
        # Risk Profile
        risk_profile = RiskProfile(
            bot_config_id=bot_config.id,
            max_daily_loss=3.0,
            max_total_dd=10.0,
            is_halted=False
        )
        db.add(risk_profile)
        
        # ==============================================================================
        # SLOT 1: EUR/JPY (Momentum Core) -> H1 Filter = TRUE
        # ==============================================================================
        slot1 = BotSlot(
            bot_config_id=bot_config.id,
            symbol="EURJPY",
            timeframe="H1", # R H1 Momentum
            direction_filter="BOTH",
            enabled=True,
            
            # Risk & Strategy
            risk_percent=0.5, 
            tp_ratio=2.0,
            sl_atr_multiplier=1.2, 
            min_confluence_score=7,
            max_trade_duration_hours=4.0,
            
            # Indicators
            rsi_period=9,     
            rsi_overbought=75,
            rsi_oversold=25,
            
            # Srat logic
            use_adx_filter=True,
            use_h1_trend_filter=True, # R MOMENTUM: Enable H1 Filter
            
            # TSL
            tsl_mode="TIERED",
            magic_number=2001
        )
        db.add(slot1)
        
        # ==============================================================================
        # SLOT 2: EUR/GBP (Range Stabilizer) -> H1 Filter = FALSE
        # ==============================================================================
        slot2 = BotSlot(
            bot_config_id=bot_config.id,
            symbol="EURGBP",
            timeframe="H1", # R H1 for Range
            direction_filter="BOTH",
            enabled=True,
            
            # Risk & Strategy (Range Focused)
            risk_percent=0.7, # 0.6 - 0.8%
            tp_ratio=1.4,     # 1.3 - 1.5
            sl_atr_multiplier=1.2, 
            min_confluence_score=7,
            max_trade_duration_hours=4.0,
            
            # Indicators
            rsi_period=14,    
            rsi_overbought=60, # Tighter range
            rsi_oversold=40,
            
            # Strat logic
            use_adx_filter=True, 
            use_h1_trend_filter=False, # ❌ RANGE: Disable H1 Trend Filter
            
            # Custom Range Logic
            stoch_k_period=9,    # Faster Stoch
            stoch_d_period=3,
            vwap_use_trend_filter=False, # R Mean Reversion (Ignore EMA Trend)
            
            # TSL - ATR Mode
            tsl_mode="ATR",
            tsl_activation_r=1.0,
            magic_number=2002
        )
        db.add(slot2)
        
        db.commit()
        print(f"R Created '{BOT_NAME}' successfully!")
        return True
        
    except Exception as e:
        print(f"❌ Error creating bot: {e}")
        db.rollback()
        import traceback
        traceback.print_exc()
        return False
    finally:
        db.close()

if __name__ == "__main__":
    asyncio.run(create_intraday_bot())
