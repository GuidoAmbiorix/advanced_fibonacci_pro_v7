"""
Database Migration Script - TradingView Integration (Phases 3-5)

Adds new tables:
- user_annotations
- annotation_templates
- grid_configurations
- backtest_heatmap_data
- strategy_comparisons

Also adds new columns to existing tables:
- bot_slots: respect_user_zones, daily_pnl, last_signal_time, last_trade_time
- backtest_sessions: avg_trade_duration_hours, largest_win, largest_loss, consecutive_wins, consecutive_losses
"""

from sqlalchemy import create_engine, text
from loguru import logger
import os

# Database URL
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./sql_app.db")

def run_migration():
    """Execute the migration"""
    logger.info("🚀 Starting TradingView Integration Migration...")

    engine = create_engine(DATABASE_URL)

    with engine.connect() as conn:
        try:
            # Start transaction
            trans = conn.begin()

            logger.info("📝 Creating new tables...")

            # 1. Create user_annotations table
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS user_annotations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    slot_id INTEGER NOT NULL,
                    annotation_type VARCHAR(50) NOT NULL,
                    coordinates TEXT NOT NULL,
                    label VARCHAR(100),
                    color VARCHAR(20) DEFAULT '#3B82F6',
                    opacity INTEGER DEFAULT 30,
                    notes TEXT,
                    trade_action VARCHAR(20) DEFAULT 'NEUTRAL',
                    zone_type VARCHAR(50),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (slot_id) REFERENCES bot_slots(id) ON DELETE CASCADE
                )
            """))
            logger.info("✅ Created user_annotations table")

            # 2. Create annotation_templates table
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS annotation_templates (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER,
                    template_name VARCHAR(100) NOT NULL,
                    description TEXT,
                    annotations TEXT NOT NULL,
                    is_public BOOLEAN DEFAULT 0,
                    use_count INTEGER DEFAULT 0,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                )
            """))
            logger.info("✅ Created annotation_templates table")

            # 3. Create grid_configurations table
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS grid_configurations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER,
                    name VARCHAR(100) DEFAULT 'My Grid',
                    layout VARCHAR(10) NOT NULL,
                    slot_ids TEXT NOT NULL,
                    show_stats BOOLEAN DEFAULT 1,
                    show_signals BOOLEAN DEFAULT 1,
                    auto_refresh_interval INTEGER DEFAULT 5,
                    is_default BOOLEAN DEFAULT 0,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                )
            """))
            logger.info("✅ Created grid_configurations table")

            # 4. Create backtest_heatmap_data table
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS backtest_heatmap_data (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id INTEGER NOT NULL,
                    price_low REAL NOT NULL,
                    price_high REAL NOT NULL,
                    bin_size INTEGER NOT NULL,
                    entry_count INTEGER DEFAULT 0,
                    buy_count INTEGER DEFAULT 0,
                    sell_count INTEGER DEFAULT 0,
                    total_pnl REAL DEFAULT 0.0,
                    win_count INTEGER DEFAULT 0,
                    loss_count INTEGER DEFAULT 0,
                    win_rate REAL DEFAULT 0.0,
                    avg_pnl REAL DEFAULT 0.0,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (session_id) REFERENCES backtest_sessions(id) ON DELETE CASCADE
                )
            """))
            logger.info("✅ Created backtest_heatmap_data table")

            # 5. Create strategy_comparisons table
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS strategy_comparisons (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name VARCHAR(100) NOT NULL,
                    description TEXT,
                    session_ids TEXT NOT NULL,
                    notes TEXT,
                    insights TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """))
            logger.info("✅ Created strategy_comparisons table")

            logger.info("📝 Adding new columns to existing tables...")

            # 6. Add columns to bot_slots (check if they exist first)
            try:
                conn.execute(text("""
                    ALTER TABLE bot_slots ADD COLUMN respect_user_zones BOOLEAN DEFAULT 1
                """))
                logger.info("✅ Added respect_user_zones to bot_slots")
            except Exception as e:
                logger.warning(f"⚠️  respect_user_zones column may already exist: {e}")

            try:
                conn.execute(text("""
                    ALTER TABLE bot_slots ADD COLUMN daily_pnl REAL DEFAULT 0.0
                """))
                logger.info("✅ Added daily_pnl to bot_slots")
            except Exception as e:
                logger.warning(f"⚠️  daily_pnl column may already exist: {e}")

            try:
                conn.execute(text("""
                    ALTER TABLE bot_slots ADD COLUMN last_signal_time TIMESTAMP
                """))
                logger.info("✅ Added last_signal_time to bot_slots")
            except Exception as e:
                logger.warning(f"⚠️  last_signal_time column may already exist: {e}")

            try:
                conn.execute(text("""
                    ALTER TABLE bot_slots ADD COLUMN last_trade_time TIMESTAMP
                """))
                logger.info("✅ Added last_trade_time to bot_slots")
            except Exception as e:
                logger.warning(f"⚠️  last_trade_time column may already exist: {e}")

            # 7. Add columns to backtest_sessions
            try:
                conn.execute(text("""
                    ALTER TABLE backtest_sessions ADD COLUMN avg_trade_duration_hours REAL
                """))
                logger.info("✅ Added avg_trade_duration_hours to backtest_sessions")
            except Exception as e:
                logger.warning(f"⚠️  avg_trade_duration_hours column may already exist: {e}")

            try:
                conn.execute(text("""
                    ALTER TABLE backtest_sessions ADD COLUMN largest_win REAL
                """))
                logger.info("✅ Added largest_win to backtest_sessions")
            except Exception as e:
                logger.warning(f"⚠️  largest_win column may already exist: {e}")

            try:
                conn.execute(text("""
                    ALTER TABLE backtest_sessions ADD COLUMN largest_loss REAL
                """))
                logger.info("✅ Added largest_loss to backtest_sessions")
            except Exception as e:
                logger.warning(f"⚠️  largest_loss column may already exist: {e}")

            try:
                conn.execute(text("""
                    ALTER TABLE backtest_sessions ADD COLUMN consecutive_wins INTEGER DEFAULT 0
                """))
                logger.info("✅ Added consecutive_wins to backtest_sessions")
            except Exception as e:
                logger.warning(f"⚠️  consecutive_wins column may already exist: {e}")

            try:
                conn.execute(text("""
                    ALTER TABLE backtest_sessions ADD COLUMN consecutive_losses INTEGER DEFAULT 0
                """))
                logger.info("✅ Added consecutive_losses to backtest_sessions")
            except Exception as e:
                logger.warning(f"⚠️  consecutive_losses column may already exist: {e}")

            # Commit transaction
            trans.commit()

            logger.info("🎉 Migration completed successfully!")
            logger.info("✨ TradingView Integration tables and columns are ready to use")

        except Exception as e:
            trans.rollback()
            logger.error(f"❌ Migration failed: {e}")
            logger.exception("Full error:")
            raise

if __name__ == "__main__":
    run_migration()
