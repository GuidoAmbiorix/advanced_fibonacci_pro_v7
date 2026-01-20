
import psycopg2
import sys

# Connection details from local_config.env
DB_CONFIG = {
    "dbname": "institutional_edge",
    "user": "postgres",
    "password": "postgres",
    "host": "localhost",
    "port": "5433"
}

def check_and_migrage():
    try:
        print(f"Connecting to PostgreSQL at {DB_CONFIG['host']}:{DB_CONFIG['port']}...")
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = True
        cur = conn.cursor()
        
        # Check columns in bot_slots
        cur.execute("""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'bot_slots';
        """)
        columns = {row[0]: row[1] for row in cur.fetchall()}
        
        print("\nExisting Columns in bot_slots:")
        for col in columns:
            print(f" - {col}")
            
        # Define missing columns to check and add
        # Based on app/models/database.py Updates
        new_columns = [
            ("engine_type", "VARCHAR DEFAULT 'ADAPTIVE'"),
            ("engine_config", "JSONB DEFAULT '{}'"),
            ("confirmation_timeframe", "VARCHAR"),
            ("session_mode", "VARCHAR DEFAULT 'BOTH_KZ'"),
            ("zigzag_lookback", "INTEGER DEFAULT 12"),
            ("enable_order_blocks", "BOOLEAN DEFAULT TRUE"),
            ("ob_lookback", "INTEGER DEFAULT 20"),
            ("enable_liquidity_sweep", "BOOLEAN DEFAULT TRUE"),
            ("sweep_lookback", "INTEGER DEFAULT 10"),
            ("enable_fvg", "BOOLEAN DEFAULT TRUE"),
            ("fvg_min_size_atr", "FLOAT DEFAULT 0.5"),
            ("rsi_buy_threshold", "INTEGER DEFAULT 40"), # Mapped from rsi_oversold in model? No, model uses rsi_oversold. 
            # Wait, API mapping: rsi_oversold -> rsi_buy_threshold in Engine, but DB uses rsi_oversold.
            # Let's check BotSlot model again.
            # Model has: rsi_oversold, rsi_overbought.
            # Missing in DB? OLD DB might have them.
            
            # New Institutional 3.0 fields:
            ("trading_session", "VARCHAR DEFAULT 'BOTH_KZ'"),
            ("session_end_action", "VARCHAR DEFAULT 'HOLD'"),
            ("session_start_utc", "VARCHAR DEFAULT '07:00'"),
            ("session_end_utc", "VARCHAR DEFAULT '15:00'"),
            ("use_daily_bias", "BOOLEAN DEFAULT FALSE"),
            
            # Strategies not usually in old version?
            ("use_h1_trend_filter", "BOOLEAN DEFAULT FALSE"),
            ("stoch_k_period", "INTEGER DEFAULT 14"),
            ("stoch_d_period", "INTEGER DEFAULT 3"),
            ("vwap_use_trend_filter", "BOOLEAN DEFAULT TRUE"),
        ]
        
        print("\nChecking for missing columns...")
        for col_name, col_def in new_columns:
            if col_name not in columns:
                print(f" ⚠️ Missing: {col_name}. Adding...")
                try:
                    query = f"ALTER TABLE bot_slots ADD COLUMN {col_name} {col_def};"
                    cur.execute(query)
                    print(f" ✅ Added {col_name}")
                except Exception as e:
                    print(f" ❌ Failed to add {col_name}: {e}")
            else:
                print(f" ✅ Exists: {col_name}")
                
        # Close connection
        cur.close()
        conn.close()
        print("\nSchema Check Complete.")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_and_migrage()
