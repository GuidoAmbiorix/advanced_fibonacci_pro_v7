"""
Signal Confirmation Manager - Orchestrates Signal Lifecycle

Manages the complete signal validation lifecycle:
1. Signal Registration: New predictions registered for validation
2. Confirmation Window: Validates signals before execution
3. Status Tracking: PENDING → CONFIRMED/REJECTED/EXPIRED → EXECUTED
4. Execution Approval: Gates signals before trading

This is the orchestrator that ties together:
- SignalValidator (validation logic)
- CooldownManager (overtrading prevention)
- DatabaseManager (persistence)
"""

import logging
import json
import numpy as np
from typing import List, Dict, Tuple, Optional
from datetime import datetime, timedelta
import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))

from src.trading.signal_validator import SignalValidator
from src.trading.cooldown_manager import CooldownManager


def convert_to_serializable(obj):
    """
    Convert numpy types and other non-serializable types to Python native types for JSON serialization.
    """
    if isinstance(obj, (np.integer, np.int64, np.int32)):
        return int(obj)
    elif isinstance(obj, (np.floating, np.float64, np.float32)):
        return float(obj)
    elif isinstance(obj, (np.bool_, bool)):
        return bool(obj)
    elif isinstance(obj, np.ndarray):
        return obj.tolist()
    elif isinstance(obj, dict):
        return {key: convert_to_serializable(value) for key, value in obj.items()}
    elif isinstance(obj, list):
        return [convert_to_serializable(item) for item in obj]
    elif isinstance(obj, tuple):
        return tuple(convert_to_serializable(item) for item in obj)
    else:
        return obj


class SignalConfirmationManager:
    """
    Orchestrates signal confirmation lifecycle from registration to execution.
    """

    def __init__(self, db_manager, config: Dict, signal_validator: SignalValidator,
                 cooldown_manager: CooldownManager):
        """
        Initialize Signal Confirmation Manager.

        Args:
            db_manager: DatabaseManager instance
            config: Configuration dictionary
            signal_validator: SignalValidator instance
            cooldown_manager: CooldownManager instance
        """
        self.db = db_manager
        self.config = config
        self.validator = signal_validator
        self.cooldown_manager = cooldown_manager
        self.logger = logging.getLogger(__name__)

        # Get confirmation settings
        self.confirmation_config = config.get('signal_confirmation', {})
        self.enabled = self.confirmation_config.get('enabled', True)
        self.confirmation_window_seconds = self.confirmation_config.get('confirmation_window_seconds', 180)
        self.min_confirmation_score = self.confirmation_config.get('min_confirmation_score', 70)

        self.logger.info(f"📋 Signal Confirmation Manager initialized (window: {self.confirmation_window_seconds}s)")

    def register_new_signal(self, prediction: dict, trading_timeframe: str = 'H1') -> Optional[int]:
        """
        Register new signal for confirmation tracking.

        Args:
            prediction: Prediction dictionary from database
            trading_timeframe: Trading timeframe

        Returns:
            Signal confirmation ID (None if registration failed)
        """
        if not self.enabled:
            return None

        try:
            symbol = prediction['symbol']
            direction = prediction['prediction_direction']
            confidence = prediction['confidence']
            prediction_id = prediction['id']

            # Calculate confirmation window
            signal_time = datetime.now()
            window_end = signal_time + timedelta(seconds=self.confirmation_window_seconds)

            self.logger.info(f"📝 Registering signal: {direction} {symbol} (confidence: {confidence:.1%})")

            # Insert into signal_confirmations table
            query = """
                INSERT INTO signal_confirmations
                (prediction_id, symbol, direction, initial_confidence,
                 status, signal_generated_at, confirmation_window_end)
                VALUES (%s, %s, %s, %s, 'PENDING', %s, %s)
            """

            with self.db.get_connection() as conn:
                cursor = conn.execute(
                    query,
                    (prediction_id, symbol, direction, confidence, signal_time, window_end)
                )
                conn.commit()
                signal_id = cursor.lastrowid

            self.logger.info(f"✅ Signal registered: ID={signal_id}, window ends at {window_end.strftime('%H:%M:%S')}")

            # Immediately start validation (don't wait for window end)
            self._validate_signal(signal_id, prediction, trading_timeframe)

            return signal_id

        except Exception as e:
            self.logger.error(f"Error registering signal: {e}")
            return None

    def _validate_signal(self, signal_id: int, prediction: dict, trading_timeframe: str):
        """
        Validate a signal using SignalValidator.

        Args:
            signal_id: Signal confirmation ID
            prediction: Prediction dictionary
            trading_timeframe: Trading timeframe
        """
        try:
            symbol = prediction['symbol']
            direction = prediction['prediction_direction']

            # Run validation
            is_valid, confirmation_score, validation_details = self.validator.validate_signal(
                prediction, trading_timeframe
            )

            # Extract individual scores (ensure they're floats, not booleans or other types)
            scores = validation_details.get('scores', {})
            mtf_score = float(scores.get('mtf_alignment', 0))
            momentum_score = float(scores.get('momentum_confluence', 0))
            volume_score = float(scores.get('volume_confirmation', 0))
            trend_score = float(scores.get('trend_strength', 0))
            fibonacci_score = float(scores.get('fibonacci_alignment', 50))
            smc_score = float(scores.get('smc_confluence', 50))

            # Clamp scores to 0-100 range (in case of calculation errors)
            mtf_score = max(0.0, min(100.0, mtf_score))
            momentum_score = max(0.0, min(100.0, momentum_score))
            volume_score = max(0.0, min(100.0, volume_score))
            trend_score = max(0.0, min(100.0, trend_score))
            fibonacci_score = max(0.0, min(100.0, fibonacci_score))
            smc_score = max(0.0, min(100.0, smc_score))

            # Determine MTF alignment
            mtf_details = validation_details.get('mtf', {})
            should_trade = mtf_details.get('should_trade', True)
            mtf_alignment = 1 if should_trade else -1

            # Extract Fibonacci and SMC details
            fibonacci_details = validation_details.get('fibonacci', {})
            smc_details = validation_details.get('smc', {})

            # Determine status
            if confirmation_score >= self.min_confirmation_score:
                status = 'CONFIRMED'
                confirmed_at = datetime.now()
                rejection_reason = None
            else:
                status = 'REJECTED'
                confirmed_at = None
                rejection_reason = f"Score {confirmation_score:.1f} below threshold {self.min_confirmation_score}"

            # Update signal in database
            update_query = """
                UPDATE signal_confirmations
                SET status = %s,
                    confirmation_score = %s,
                    mtf_alignment = %s,
                    mtf_score = %s,
                    momentum_score = %s,
                    volume_score = %s,
                    trend_score = %s,
                    fibonacci_score = %s,
                    smc_score = %s,
                    fibonacci_details = %s,
                    smc_details = %s,
                    confirmed_at = %s,
                    rejection_reason = %s,
                    validation_details = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """

            # Convert numpy types to Python native types for JSON serialization
            import psycopg2.extras
            serializable_details = convert_to_serializable(validation_details)
            serializable_fib_details = convert_to_serializable(fibonacci_details)
            serializable_smc_details = convert_to_serializable(smc_details)

            with self.db.get_connection() as conn:
                conn.execute(
                    update_query,
                    (status, confirmation_score, mtf_alignment, mtf_score,
                     momentum_score, volume_score, trend_score,
                     fibonacci_score, smc_score,
                     psycopg2.extras.Json(serializable_fib_details), psycopg2.extras.Json(serializable_smc_details),
                     confirmed_at, rejection_reason, psycopg2.extras.Json(serializable_details),
                     signal_id)
                )
                conn.commit()

            if status == 'CONFIRMED':
                self.logger.info(f"✅ Signal {signal_id} CONFIRMED: {symbol} {direction} (score: {confirmation_score:.1f})")
            else:
                self.logger.warning(f"❌ Signal {signal_id} REJECTED: {symbol} {direction} ({rejection_reason})")

        except Exception as e:
            self.logger.error(f"Error validating signal {signal_id}: {e}")

    def process_pending_signals(self):
        """
        Process all pending signals:
        - Check if confirmation window expired
        - Mark expired signals as EXPIRED
        - Signals are validated immediately on registration, so just check expiration
        """
        if not self.enabled:
            return

        try:
            # Find signals that haven't been validated yet or have expired windows
            query = """
                SELECT * FROM signal_confirmations
                WHERE status = 'PENDING'
                OR (status = 'CONFIRMED'
                    AND confirmation_window_end < CURRENT_TIMESTAMP
                    AND executed_at IS NULL)
            """

            with self.db.get_connection() as conn:
                rows = conn.execute(query).fetchall()

            for row in rows:
                signal_id = row['id']
                status = row['status']
                window_end = datetime.fromisoformat(row['confirmation_window_end'])

                # Check if window expired
                if datetime.now() > window_end:
                    if status == 'CONFIRMED':
                        # Confirmed but not executed in time - mark as expired
                        self._mark_expired(signal_id, row['symbol'])
                    elif status == 'PENDING':
                        # Never validated - mark as expired
                        self._mark_expired(signal_id, row['symbol'])

        except Exception as e:
            self.logger.error(f"Error processing pending signals: {e}")

    def _mark_expired(self, signal_id: int, symbol: str):
        """Mark signal as expired."""
        try:
            query = """
                UPDATE signal_confirmations
                SET status = 'EXPIRED',
                    rejection_reason = 'Confirmation window expired',
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """

            with self.db.get_connection() as conn:
                conn.execute(query, (signal_id,))
                conn.commit()

            self.logger.info(f"⏰ Signal {signal_id} EXPIRED: {symbol}")

        except Exception as e:
            self.logger.error(f"Error marking signal {signal_id} as expired: {e}")

    def get_confirmed_signals(self) -> List[Dict]:
        """
        Get signals that passed validation and are ready to trade.

        Returns:
            List of confirmed signals ready for execution
        """
        if not self.enabled:
            return []

        try:
            query = """
                SELECT sc.*, p.symbol, p.prediction_direction, p.confidence
                FROM signal_confirmations sc
                JOIN predictions p ON sc.prediction_id = p.id
                WHERE sc.status = 'CONFIRMED'
                AND sc.executed_at IS NULL
                AND sc.confirmation_window_end > CURRENT_TIMESTAMP
                ORDER BY sc.confirmation_score DESC, sc.confirmed_at ASC
            """

            with self.db.get_connection() as conn:
                rows = conn.execute(query).fetchall()

            signals = [dict(row) for row in rows]

            if signals:
                self.logger.info(f"📊 Found {len(signals)} confirmed signal(s) ready for execution")

            return signals

        except Exception as e:
            self.logger.error(f"Error getting confirmed signals: {e}")
            return []

    def can_execute_signal(self, signal: Dict) -> Tuple[bool, str]:
        """
        Final gate before execution - check all conditions.

        Args:
            signal: Signal confirmation dictionary

        Returns:
            (can_execute, reason)
        """
        symbol = signal['symbol']
        signal_id = signal['id']

        # Check if signal is still in CONFIRMED status
        if signal['status'] != 'CONFIRMED':
            return False, f"Signal not confirmed (status: {signal['status']})"

        # Check if confirmation window still valid
        window_end = datetime.fromisoformat(signal['confirmation_window_end'])
        if datetime.now() > window_end:
            return False, "Confirmation window expired"

        # Check cooldown
        can_trade, cooldown_reason = self.cooldown_manager.can_trade(symbol)
        if not can_trade:
            return False, f"Cooldown: {cooldown_reason}"

        # Check if already executed
        if signal['executed_at'] is not None:
            return False, "Signal already executed"

        return True, "OK"

    def mark_signal_executed(self, signal_id: int):
        """
        Mark signal as executed after trade is placed.

        Args:
            signal_id: Signal confirmation ID
        """
        try:
            query = """
                UPDATE signal_confirmations
                SET status = 'EXECUTED',
                    executed_at = CURRENT_TIMESTAMP,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """

            with self.db.get_connection() as conn:
                conn.execute(query, (signal_id,))
                conn.commit()

            self.logger.info(f"✅ Signal {signal_id} marked as EXECUTED")

        except Exception as e:
            self.logger.error(f"Error marking signal {signal_id} as executed: {e}")

    def get_signal_stats(self, hours: int = 24) -> Dict:
        """
        Get signal confirmation statistics for monitoring.

        Args:
            hours: Time window for statistics

        Returns:
            Dictionary with statistics
        """
        try:
            time_window = datetime.now() - timedelta(hours=hours)

            query = """
                SELECT
                    status,
                    COUNT(*) as count,
                    AVG(confirmation_score) as avg_score
                FROM signal_confirmations
                WHERE signal_generated_at > %s
                GROUP BY status
            """

            with self.db.get_connection() as conn:
                rows = conn.execute(query, (time_window,)).fetchall()

            stats = {
                'time_window_hours': hours,
                'by_status': {}
            }

            total = 0
            for row in rows:
                status = row['status']
                count = row['count']
                avg_score = row['avg_score'] if row['avg_score'] else 0

                stats['by_status'][status] = {
                    'count': count,
                    'avg_score': round(avg_score, 1)
                }
                total += count

            stats['total_signals'] = total

            # Calculate confirmation rate
            confirmed = stats['by_status'].get('CONFIRMED', {}).get('count', 0)
            executed = stats['by_status'].get('EXECUTED', {}).get('count', 0)
            stats['confirmation_rate'] = round((confirmed + executed) / total * 100, 1) if total > 0 else 0

            return stats

        except Exception as e:
            self.logger.error(f"Error getting signal stats: {e}")
            return {'error': str(e)}

    def cleanup_old_signals(self, days: int = 7):
        """
        Clean up old signal confirmations to keep database lean.

        Args:
            days: Keep signals newer than this many days
        """
        try:
            cutoff = datetime.now() - timedelta(days=days)

            query = """
                DELETE FROM signal_confirmations
                WHERE signal_generated_at < %s
                AND status IN ('REJECTED', 'EXPIRED', 'EXECUTED')
            """

            with self.db.get_connection() as conn:
                cursor = conn.execute(query, (cutoff,))
                deleted = cursor.rowcount
                conn.commit()

                if deleted > 0:
                    self.logger.info(f"🧹 Cleaned up {deleted} old signal(s) (older than {days} days)")

        except Exception as e:
            self.logger.error(f"Error cleaning up signals: {e}")
