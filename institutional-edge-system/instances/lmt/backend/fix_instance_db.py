
import sqlite3
import json
import os

# Set DB Path 
# IMPORTANT: This matches the path used by the application in the container
DB_PATH = "/app/data/instance_1.db"

def fix_db():
    if not os.path.exists(DB_PATH):
        print(f"Error: DB not found at {DB_PATH}")
        return

    print(f"Opening DB: {DB_PATH}")
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # 1. Ensure BotConfig exists
    c.execute("SELECT id FROM bot_configs WHERE id=1")
    if not c.fetchone():
        print("Creating default BotConfig...")
        c.execute("""
            INSERT INTO bot_configs (
                id, user_id, name, symbol, timeframe, risk_percent,
                min_confluence_score, max_trades, is_active, created_at, updated_at
            ) VALUES (1, 1, 'Instance Bot', 'XAUUSD', 'M5', 1.0, 7, 3, 1, datetime('now'), datetime('now'))
        """)
    
    # 2. Check for BotSlot
    c.execute("SELECT id FROM bot_slots WHERE symbol='XAUUSD'")
    existing_slot = c.fetchone()
    
    # If exists, we delete and recreate to ensure ALL columns are set correctly
    if existing_slot:
        print(f"Deleting existing XAUUSD slot {existing_slot[0]} to re-seed...")
        c.execute("DELETE FROM bot_slots WHERE id=?", (existing_slot[0],))
        
    print("Inserting new BotSlot with FULL schema...")
    
    # Define sensible defaults for ALL columns used in trading.py
    slot_data = {
        "bot_config_id": 1,
        "symbol": "XAUUSD",
        "enabled": 1,
        "direction_filter": "BOTH",
        "engine_type": "ADAPTIVE",
        "engine_config": "{}", # JSON string
        "timeframe": "M5",
        "confirmation_timeframe": "H1",
        "use_daily_bias": 0,
        "trading_session": "BOTH_KZ", # The Critical Fix
        "session_mode": "BOTH_KZ",
        "session_start_utc": "07:00",
        "session_end_utc": "15:00",
        "session_end_action": "HOLD",
        "risk_percent": 1.0,
        "tp_ratio": 2.0,
        "sl_atr_multiplier": 1.4,
        "macd_fast": 6,
        "macd_slow": 18,
        "macd_signal": 9,
        "use_adx_filter": 0,
        "enable_vwap_strategy": 1,
        "enable_stoch_strategy": 1,
        "enable_institutional_strategy": 1,
        "enable_fibonacci_strategy": 1,
        "use_h1_trend_filter": 0,
        "stoch_k_period": 14,
        "stoch_d_period": 3,
        "vwap_use_trend_filter": 1,
        "rsi_period": 14,
        "rsi_overbought": 70,
        "rsi_oversold": 30,
        "zigzag_lookback": 12,
        "enable_order_blocks": 1,
        "ob_lookback": 20,
        "enable_liquidity_sweep": 1,
        "sweep_lookback": 10,
        "enable_fvg": 1,
        "fvg_min_size_atr": 0.5,
        "enable_trailing_stop": 1,
        "tsl_mode": "TIERED",
        "tsl_activation_r": 0.0,
        "partial_tp_on": 1,
        "partial_tp_amount": 0.5,
        "max_trade_duration_hours": 2.0,
        "min_confluence_score": 7,
        "magic_number": 8888,
        "respect_user_zones": 1,
        "daily_pnl": 0.0
    }

    columns = ", ".join(slot_data.keys())
    placeholders = ", ".join(["?"] * len(slot_data))
    values = tuple(slot_data.values())

    query = f"INSERT INTO bot_slots ({columns}, created_at) VALUES ({placeholders}, datetime('now'))"
    
    try:
        c.execute(query, values)
        conn.commit()
        print(f"R Database patched successfully. 'trading_session' set to '{slot_data['trading_session']}'.")
    except Exception as e:
        print(f"❌ Failed to insert slot: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    fix_db()
