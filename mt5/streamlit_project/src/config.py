"""
Configuration Management - Centralized configuration with environment variable support.
Manages all configurable parameters, paths, and thresholds for the application.
"""

import os
from pathlib import Path
from typing import Optional
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Config:
    """Centralized configuration manager."""

    # ========== Project Paths ==========
    PROJECT_ROOT = Path(__file__).parent.parent

    # MT5 Sets Directory (configurable via environment)
    DEFAULT_SETS_PATH = os.getenv(
        "MT5_SETS_PATH",
        r"C:\Users\gamparo\Desktop\Projects\advanced_fibonacci_pro_v7\mt5\portafolio_manager\sets"
    )
    MT5_SETS_PATH = Path(DEFAULT_SETS_PATH)

    # Database Path
    DATABASE_PATH = Path(os.getenv(
        "DATABASE_PATH",
        str(PROJECT_ROOT / "data" / "trading.db")
    ))

    # Logs Directory
    LOGS_DIR = Path(os.getenv(
        "LOGS_DIR",
        str(PROJECT_ROOT / "logs")
    ))

    # ========== MT5 Connection Settings ==========
    MT5_TIMEOUT = int(os.getenv("MT5_TIMEOUT", "60000"))  # milliseconds
    MT5_LOGIN = os.getenv("MT5_LOGIN", "")  # Optional login
    MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")  # Optional password
    MT5_SERVER = os.getenv("MT5_SERVER", "")  # Optional server

    # ========== Portfolio Governor Settings ==========

    # Correlation Settings
    CORRELATION_TIMEFRAME = os.getenv("CORRELATION_TIMEFRAME", "H1")
    CORRELATION_BARS = int(os.getenv("CORRELATION_BARS", "100"))
    CORRELATION_CACHE_TTL = int(os.getenv("CORRELATION_CACHE_TTL", "900"))  # 15 minutes in seconds
    CORRELATION_HIGH_THRESHOLD = float(os.getenv("CORRELATION_HIGH_THRESHOLD", "0.75"))

    # Group Generation Rules
    GROUP_SIZE = int(os.getenv("GROUP_SIZE", "4"))
    MAX_SAME_DRIVER = int(os.getenv("MAX_SAME_DRIVER", "2"))
    MAX_HIGH_CORR_PAIRS = int(os.getenv("MAX_HIGH_CORR_PAIRS", "1"))
    MIN_ASSET_CLASSES = int(os.getenv("MIN_ASSET_CLASSES", "2"))

    # Symbol Scoring Weights (0-100 scale)
    SCORE_SESSION_ACTIVITY_MAX = float(os.getenv("SCORE_SESSION_ACTIVITY_MAX", "20"))
    SCORE_TREND_ALIGNMENT_MAX = float(os.getenv("SCORE_TREND_ALIGNMENT_MAX", "25"))
    SCORE_SPREAD_QUALITY_MAX = float(os.getenv("SCORE_SPREAD_QUALITY_MAX", "15"))
    SCORE_VOLATILITY_MATCH_MAX = float(os.getenv("SCORE_VOLATILITY_MATCH_MAX", "15"))
    SCORE_HISTORICAL_PERF_MAX = float(os.getenv("SCORE_HISTORICAL_PERF_MAX", "25"))

    # Scoring Thresholds
    MIN_ACCEPTABLE_SCORE = float(os.getenv("MIN_ACCEPTABLE_SCORE", "40"))
    EXCELLENT_SCORE_THRESHOLD = float(os.getenv("EXCELLENT_SCORE_THRESHOLD", "75"))

    # ========== Analytics Settings ==========

    # Risk-Free Rate for Sharpe Ratio (annual %)
    RISK_FREE_RATE = float(os.getenv("RISK_FREE_RATE", "4.5"))

    # Performance Calculation Settings
    TRADING_DAYS_PER_YEAR = int(os.getenv("TRADING_DAYS_PER_YEAR", "252"))
    MIN_TRADES_FOR_STATS = int(os.getenv("MIN_TRADES_FOR_STATS", "30"))

    # Drawdown Alert Thresholds
    MAX_DRAWDOWN_WARNING = float(os.getenv("MAX_DRAWDOWN_WARNING", "10.0"))  # %
    MAX_DRAWDOWN_CRITICAL = float(os.getenv("MAX_DRAWDOWN_CRITICAL", "20.0"))  # %

    # ========== Data Fetching Settings ==========

    # Historical Data Limits
    MAX_TRADES_TO_FETCH = int(os.getenv("MAX_TRADES_TO_FETCH", "10000"))
    MAX_HISTORY_DAYS = int(os.getenv("MAX_HISTORY_DAYS", "365"))

    # Chart Settings
    DEFAULT_CHART_BARS = int(os.getenv("DEFAULT_CHART_BARS", "500"))

    # ========== Logging Settings ==========

    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
    LOG_MAX_BYTES = int(os.getenv("LOG_MAX_BYTES", "10485760"))  # 10 MB
    LOG_BACKUP_COUNT = int(os.getenv("LOG_BACKUP_COUNT", "5"))
    LOG_FORMAT = os.getenv(
        "LOG_FORMAT",
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    # ========== Cache Settings ==========

    CACHE_ENABLED = os.getenv("CACHE_ENABLED", "true").lower() == "true"
    SYMBOL_SCORES_CACHE_TTL = int(os.getenv("SYMBOL_SCORES_CACHE_TTL", "60"))  # seconds
    GROUPS_CACHE_TTL = int(os.getenv("GROUPS_CACHE_TTL", "300"))  # 5 minutes

    # ========== UI Settings ==========

    PAGE_TITLE = os.getenv("PAGE_TITLE", "Elite MT5 Trading Intelligence Platform")
    THEME = os.getenv("THEME", "dark")
    SHOW_WARNINGS = os.getenv("SHOW_WARNINGS", "true").lower() == "true"

    # Number of top groups to display
    TOP_GROUPS_DISPLAY = int(os.getenv("TOP_GROUPS_DISPLAY", "5"))

    # ========== Development Settings ==========

    DEBUG_MODE = os.getenv("DEBUG_MODE", "false").lower() == "true"
    ENABLE_PROFILING = os.getenv("ENABLE_PROFILING", "false").lower() == "true"

    @classmethod
    def validate(cls) -> bool:
        """
        Validate configuration settings.

        Returns:
            True if configuration is valid

        Raises:
            ValueError if critical settings are invalid
        """
        # Validate paths
        if not cls.MT5_SETS_PATH.exists():
            raise ValueError(f"MT5 Sets path does not exist: {cls.MT5_SETS_PATH}")

        # Ensure directories exist
        cls.LOGS_DIR.mkdir(parents=True, exist_ok=True)
        cls.DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)

        # Validate numeric ranges
        if not 0 <= cls.CORRELATION_HIGH_THRESHOLD <= 1:
            raise ValueError("CORRELATION_HIGH_THRESHOLD must be between 0 and 1")

        if cls.GROUP_SIZE < 2:
            raise ValueError("GROUP_SIZE must be at least 2")

        # Validate scoring weights sum to 100
        total_score = (
            cls.SCORE_SESSION_ACTIVITY_MAX +
            cls.SCORE_TREND_ALIGNMENT_MAX +
            cls.SCORE_SPREAD_QUALITY_MAX +
            cls.SCORE_VOLATILITY_MATCH_MAX +
            cls.SCORE_HISTORICAL_PERF_MAX
        )
        if abs(total_score - 100) > 0.01:
            raise ValueError(f"Scoring weights must sum to 100, got {total_score}")

        return True

    @classmethod
    def get_summary(cls) -> dict:
        """Get configuration summary for debugging."""
        return {
            "mt5_sets_path": str(cls.MT5_SETS_PATH),
            "database_path": str(cls.DATABASE_PATH),
            "logs_dir": str(cls.LOGS_DIR),
            "correlation_threshold": cls.CORRELATION_HIGH_THRESHOLD,
            "group_size": cls.GROUP_SIZE,
            "cache_enabled": cls.CACHE_ENABLED,
            "debug_mode": cls.DEBUG_MODE,
            "log_level": cls.LOG_LEVEL
        }


# Create global config instance
config = Config()

# Validate on import (optional, can be disabled for testing)
if not os.getenv("SKIP_CONFIG_VALIDATION", "").lower() == "true":
    try:
        config.validate()
    except ValueError as e:
        # Log warning but don't crash - let app handle it
        print(f"Configuration validation warning: {e}")
