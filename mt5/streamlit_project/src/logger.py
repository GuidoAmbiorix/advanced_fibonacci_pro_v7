"""
Logging Framework - Centralized logging with rotating file handlers.
Provides structured logging for all application components.
"""

import logging
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional
from .config import config


# Global logger registry
_loggers = {}


def setup_logger(
    name: str,
    level: Optional[str] = None,
    log_to_file: bool = True,
    log_to_console: bool = True
) -> logging.Logger:
    """
    Setup and configure a logger instance.

    Args:
        name: Logger name (typically __name__ of the module)
        level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_to_file: Enable file logging with rotation
        log_to_console: Enable console logging

    Returns:
        Configured logger instance
    """
    # Return existing logger if already created
    if name in _loggers:
        return _loggers[name]

    # Create logger
    logger = logging.getLogger(name)
    log_level = level or config.LOG_LEVEL
    logger.setLevel(getattr(logging, log_level))

    # Prevent duplicate handlers
    if logger.handlers:
        logger.handlers.clear()

    # Create formatter
    formatter = logging.Formatter(config.LOG_FORMAT)

    # Console handler
    if log_to_console:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)  # Console shows INFO and above
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

    # File handler with rotation
    if log_to_file:
        # Ensure logs directory exists
        config.LOGS_DIR.mkdir(parents=True, exist_ok=True)

        # Main application log
        log_file = config.LOGS_DIR / f"{name.replace('.', '_')}.log"
        file_handler = RotatingFileHandler(
            log_file,
            maxBytes=config.LOG_MAX_BYTES,
            backupCount=config.LOG_BACKUP_COUNT,
            encoding='utf-8'
        )
        file_handler.setLevel(getattr(logging, log_level))
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

        # Error-only log
        error_log_file = config.LOGS_DIR / f"{name.replace('.', '_')}_errors.log"
        error_handler = RotatingFileHandler(
            error_log_file,
            maxBytes=config.LOG_MAX_BYTES,
            backupCount=config.LOG_BACKUP_COUNT,
            encoding='utf-8'
        )
        error_handler.setLevel(logging.ERROR)
        error_handler.setFormatter(formatter)
        logger.addHandler(error_handler)

    # Store in registry
    _loggers[name] = logger

    return logger


def get_logger(name: str) -> logging.Logger:
    """
    Get or create a logger instance.

    Args:
        name: Logger name (typically __name__)

    Returns:
        Logger instance
    """
    if name not in _loggers:
        return setup_logger(name)
    return _loggers[name]


def log_exception(logger: logging.Logger, message: str, exc_info: bool = True):
    """
    Log an exception with full traceback.

    Args:
        logger: Logger instance
        message: Error message
        exc_info: Include exception info in log
    """
    logger.error(message, exc_info=exc_info)


def log_mt5_error(logger: logging.Logger, operation: str, error_code: int, error_msg: str):
    """
    Log MT5-specific errors with standardized format.

    Args:
        logger: Logger instance
        operation: MT5 operation that failed
        error_code: MT5 error code
        error_msg: MT5 error message
    """
    logger.error(
        f"MT5 Error during {operation}: Code {error_code} - {error_msg}"
    )


def log_performance(logger: logging.Logger, operation: str, duration_ms: float):
    """
    Log performance metrics for operations.

    Args:
        logger: Logger instance
        operation: Operation name
        duration_ms: Duration in milliseconds
    """
    if duration_ms > 1000:  # Log slow operations
        logger.warning(f"Slow operation: {operation} took {duration_ms:.2f}ms")
    else:
        logger.debug(f"Performance: {operation} took {duration_ms:.2f}ms")


def log_data_quality(logger: logging.Logger, check_name: str, passed: bool, details: str = ""):
    """
    Log data quality checks.

    Args:
        logger: Logger instance
        check_name: Name of the quality check
        passed: Whether check passed
        details: Additional details
    """
    level = logging.INFO if passed else logging.WARNING
    status = "PASSED" if passed else "FAILED"
    message = f"Data Quality [{check_name}]: {status}"
    if details:
        message += f" - {details}"
    logger.log(level, message)


class LogContext:
    """Context manager for logging operation start/end with timing."""

    def __init__(self, logger: logging.Logger, operation: str, level: int = logging.INFO):
        self.logger = logger
        self.operation = operation
        self.level = level
        self.start_time = None

    def __enter__(self):
        import time
        self.start_time = time.time()
        self.logger.log(self.level, f"Starting: {self.operation}")
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        import time
        duration_ms = (time.time() - self.start_time) * 1000

        if exc_type is not None:
            self.logger.error(
                f"Failed: {self.operation} (after {duration_ms:.2f}ms)",
                exc_info=True
            )
        else:
            self.logger.log(
                self.level,
                f"Completed: {self.operation} ({duration_ms:.2f}ms)"
            )
        return False  # Don't suppress exceptions


# Initialize main application logger
app_logger = setup_logger("mt5_platform", log_to_console=True, log_to_file=True)


def initialize_logging():
    """
    Initialize logging system for the entire application.
    Call this once at application startup.
    """
    app_logger.info("=" * 80)
    app_logger.info("MT5 Trading Intelligence Platform - Starting")
    app_logger.info("=" * 80)
    app_logger.info(f"Log Level: {config.LOG_LEVEL}")
    app_logger.info(f"Logs Directory: {config.LOGS_DIR}")
    app_logger.info(f"Debug Mode: {config.DEBUG_MODE}")


def shutdown_logging():
    """
    Clean shutdown of logging system.
    Call this at application exit.
    """
    app_logger.info("=" * 80)
    app_logger.info("MT5 Trading Intelligence Platform - Shutting Down")
    app_logger.info("=" * 80)

    # Close all handlers
    for logger in _loggers.values():
        for handler in logger.handlers[:]:
            handler.close()
            logger.removeHandler(handler)
