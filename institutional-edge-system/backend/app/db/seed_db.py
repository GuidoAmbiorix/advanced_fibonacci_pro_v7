
import logging
from app.api.database import SessionLocal
from app.models.database import BotConfig, BotSlot
from datetime import datetime

logger = logging.getLogger(__name__)

def seed_database():
    """Foundational data seeding - Ensures 'Institutional Gold' config exists"""
    db = SessionLocal()
    try:
        # 1. Ensure BotConfig exists
        config = db.query(BotConfig).filter(BotConfig.id == 1).first()
        if not config:
            logger.info("🌱 Seeding Default BotConfig...")
            config = BotConfig(
                id=1,
                user_id=1, # Assumes Admin user exists (handled in main.py)
                name="Institutional Gold Bot",
                symbol="XAUUSD",
                timeframe="M5",
                risk_percent=1.0,
                min_confluence_score=7,
                max_trades=3,
                is_active=True
            )
            db.add(config)
            db.commit()
        
        # 2. Ensure XAUUSD BotSlot exists (or update it)
        slot = db.query(BotSlot).filter(BotSlot.symbol == "XAUUSD").first()
        
        # Define User's Specific "Slot 2" Configuration
        slot_data = {
            "bot_config_id": 1,
            "symbol": "XAUUSD",
            "enabled": True,
            "direction_filter": "BOTH",
            "engine_type": "Institutional Gold (XAU PRO)", # Mapped to ADAPTIVE internally if needed, or keep string
            "engine_config": {},
            "timeframe": "M5",
            "confirmation_timeframe": "M30", # User requested M30
            "use_daily_bias": False,
            
            # Session Control
            "trading_session": "BOTH_KZ", # London + NY
            "session_mode": "BOTH_KZ",
            "session_start_utc": "07:00",
            "session_end_utc": "15:00",
            "session_end_action": "HOLD", # User: No New Entries
            
            # Risk & Money Man
            "risk_percent": 0.2, # User: 0.2
            "tp_ratio": 1.5,     # User: 1.5
            "sl_atr_multiplier": 0.5, # User: 0.5
            
            # Momentum (MACD)
            "macd_fast": 5,      # User: 5
            "macd_slow": 13,     # User: 13
            "macd_signal": 6,    # User: 6
            
            # Value (RSI)
            "rsi_period": 9,     # User: 9
            "rsi_overbought": 57, # User: Sell Floor 57
            "rsi_oversold": 43,   # User: Buy Ceiling 43
            
            # Structure (ZigZag)
            "zigzag_lookback": 8, # User: 8
            
            # Smart Money (SMC)
            "enable_order_blocks": True, "ob_lookback": 14, # User: 14
            "enable_liquidity_sweep": True, "sweep_lookback": 6, # User: 6
            "enable_fvg": True, "fvg_min_size_atr": 0.3, # User: 0.3
            
            # TSL & Partials
            "enable_trailing_stop": True,
            "tsl_mode": "ATR", # User: ATR
            "tsl_activation_r": 0.0,
            "partial_tp_on": True,
            "partial_tp_amount": 0.5,
            
            # Limits
            "max_trade_duration_hours": 0.0, # 0 = no limit
            "min_confluence_score": 7,
            "magic_number": 8888,
            "respect_user_zones": True,
            "daily_pnl": 0.0
        }

        if not slot:
            logger.info("🌱 Seeding XAUUSD BotSlot (Institutional Gold)...")
            slot = BotSlot(**slot_data)
            db.add(slot)
            logger.info("✅ Created XAUUSD BotSlot.")
        else:
            logger.info("🔄 Updating XAUUSD BotSlot with User Specs...")
            # Update existing slot attributes
            for key, value in slot_data.items():
                setattr(slot, key, value)
            logger.info("✅ Updated XAUUSD BotSlot.")
            
        db.commit()

    except Exception as e:
        logger.error(f"❌ Database seeding failed: {e}")
        db.rollback()
    finally:
        db.close()
