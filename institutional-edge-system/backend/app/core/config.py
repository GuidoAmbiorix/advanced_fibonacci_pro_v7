"""
============================================================================
Application Configuration
============================================================================
"""

from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    """Application settings loaded from environment variables"""

    # Application
    APP_NAME: str = "Institutional Edge Pro"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    SECRET_KEY: str

    # Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # MetaTrader 5
    MT5_LOGIN: str = ""
    MT5_PASSWORD: str = ""
    MT5_SERVER: str = ""
    MT5_PATH: str = ""

    # Trading Parameters
    DEFAULT_SYMBOL: str = "EURUSD"
    DEFAULT_TIMEFRAME: str = "H1"
    DEFAULT_RISK_PERCENT: float = 2.0
    MAX_RISK_PERCENT: float = 5.0
    MIN_CONFLUENCE_SCORE: int = 6

    # Database
    DATABASE_URL: str
    DATABASE_POOL_SIZE: int = 20
    DATABASE_MAX_OVERFLOW: int = 0

    # Redis
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 0
    REDIS_PASSWORD: str = ""

    # RabbitMQ
    RABBITMQ_HOST: str = "localhost"
    RABBITMQ_PORT: int = 5672
    RABBITMQ_USER: str = "guest"
    RABBITMQ_PASSWORD: str = "guest"

    # CORS
    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:5173"

    @property
    def cors_origins_list(self) -> List[str]:
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",")]

    # JWT
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    # Logging
    LOG_LEVEL: str = "INFO"
    LOG_FILE: str = "logs/trading.log"

    # Alerts
    TELEGRAM_BOT_TOKEN: str = ""
    TELEGRAM_CHAT_ID: str = ""
    ENABLE_EMAIL_ALERTS: bool = False
    EMAIL_HOST: str = ""
    EMAIL_PORT: int = 587
    EMAIL_USER: str = ""
    EMAIL_PASSWORD: str = ""

    model_config = {"extra": "ignore", "env_file": (".env", ".env.local", "local_config.env"), "case_sensitive": True}


# Global settings instance
settings = Settings()
