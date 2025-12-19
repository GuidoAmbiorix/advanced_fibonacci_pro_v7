"""
============================================================================
Create Gold Bot - Auto-creates XAUUSD bot with winning configuration
============================================================================
"""

import sys
sys.path.insert(0, '.')

from app.api.database import SessionLocal, engine
from app.models.database import Base, BotConfig, User

# Create tables if they don't exist
Base.metadata.create_all(bind=engine)

def create_gold_bot():
    """Create XAUUSD bot with winning configuration"""
    db = SessionLocal()
    try:
        # Get default user (ID=1)
        user = db.query(User).filter(User.id == 1).first()
        if not user:
            print("❌ No user found. Run ensure_user.py first.")
            return False
        
        # Check if Gold bot already exists
        existing_bot = db.query(BotConfig).filter(
            BotConfig.user_id == user.id,
            BotConfig.symbol == "XAUUSDm"
        ).first()
        
        if existing_bot:
            print(f"✅ Gold bot already exists: {existing_bot.name} (ID: {existing_bot.id})")
            # Update with winning config
            existing_bot.timeframe = "M5"
            existing_bot.risk_percent = 0.001
            existing_bot.min_confluence_score = 5
            existing_bot.use_adx_filter = False
            existing_bot.enable_vwap_strategy = True
            existing_bot.enable_stoch_strategy = True
            existing_bot.enable_institutional_strategy = True
            existing_bot.enable_fibonacci_strategy = True
            existing_bot.trailing_sl = True
            existing_bot.tsl_mode = "ATR"
            existing_bot.tsl_activation_r = 0.0
            existing_bot.partial_tp_on = True
            existing_bot.partial_tp_amount = 1.0
            # Scalping Speed Settings
            existing_bot.tp_ratio = 2.0
            existing_bot.sl_atr_multiplier = 1.0
            existing_bot.max_trade_duration_hours = 0.0
            existing_bot.is_active = False  # User activates manually
            db.commit()
            print("✅ Gold bot config updated with winning settings!")
            return True
        
        # Create new Gold bot with winning config
        gold_bot = BotConfig(
            user_id=user.id,
            name="🥇 Gold Scalper Pro",
            
            # Trading Parameters - GOLD WINNING CONFIG
            symbol="XAUUSDm",
            symbol_type="forex",
            timeframe="M5",
            risk_percent=0.001,  # Critical: 0.001% for Gold
            min_confluence_score=5,
            max_trades=3,
            
            # Smart Money Settings
            swing_length=10,
            ob_lookback=50,
            fvg_min_size=0.3,
            vp_lookback=100,
            
            # Strategy Selection - ALL ON
            use_adx_filter=False,  # OFF for Gold winning
            enable_vwap_strategy=True,
            enable_stoch_strategy=True,
            enable_institutional_strategy=True,
            enable_fibonacci_strategy=True,
            
            # RSI Settings
            rsi_period=14,
            rsi_overbought=70,
            rsi_oversold=30,
            
            # Trade Management - WINNING CONFIG
            be_trigger=1.0,
            trailing_sl=True,  # ON for Gold
            trailing_step=1.0,
            trailing_distance=1.5,
            tsl_mode="ATR",  # ATR recommended for Gold
            tsl_activation_r=0.0,  # Immediate
            tsl_atr_period=14,
            tsl_atr_multiplier=1.5,
            
            # Partial TP - 100%
            partial_tp_on=True,
            partial_tp_amount=1.0,
            
            # Scalping Speed Settings - GOLD WINNING
            tp_ratio=2.0,  # 2.0R TP (winning config)
            sl_atr_multiplier=1.0,  # 1.0 ATR SL (winning config)
            max_trade_duration_hours=0.0,  # No limit (winning config)
            
            # Risk & Filters
            max_spread=50.0,  # Higher for Gold spreads
            trading_hours_start="00:00",
            trading_hours_end="23:59",
            daily_loss_limit_percent=3.0,
            cooldown_minutes=5,
            
            # Bot Status
            is_active=False  # User activates manually
        )
        
        db.add(gold_bot)
        db.commit()
        db.refresh(gold_bot)
        
        print("=" * 60)
        print("🥇 GOLD SCALPER PRO BOT CREATED!")
        print("=" * 60)
        print(f"   ID: {gold_bot.id}")
        print(f"   Name: {gold_bot.name}")
        print(f"   Symbol: {gold_bot.symbol}")
        print(f"   Timeframe: {gold_bot.timeframe}")
        print(f"   Risk: {gold_bot.risk_percent}%")
        print(f"   TSL Mode: {gold_bot.tsl_mode}")
        print(f"   Partial TP: {gold_bot.partial_tp_amount * 100}%")
        print("=" * 60)
        print("👉 Activate in Execution Dashboard to start trading!")
        print()
        
        return True
        
    except Exception as e:
        print(f"❌ Error creating Gold bot: {e}")
        db.rollback()
        return False
    finally:
        db.close()


if __name__ == "__main__":
    create_gold_bot()
