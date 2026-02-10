"""
Cooldown Manager - Prevents Overtrading

Manages trading cooldowns to prevent:
- Rapid-fire trading on same symbol
- Revenge trading after losses
- Overtrading during volatile periods

Cooldown types:
1. Per-symbol cooldown: Wait between trades on same symbol
2. Loss cooldown: Extended wait after stop loss
3. Global cooldown: Minimum time between ANY trades
4. Rapid signal cooldown: Penalty for too many signals
"""

import logging
from typing import Optional, Tuple, Dict
from datetime import datetime, timedelta
import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))


class CooldownManager:
    """
    Manages trading cooldowns to prevent overtrading.
    """

    def __init__(self, db_manager, config: Dict):
        """
        Initialize Cooldown Manager.

        Args:
            db_manager: DatabaseManager instance
            config: Configuration dictionary with cooldown settings
        """
        self.db = db_manager
        self.config = config
        self.logger = logging.getLogger(__name__)

        # Get cooldown settings
        cooldown_config = config.get('cooldowns', {})
        self.enabled = cooldown_config.get('enabled', True)

        self.symbol_cooldown_minutes = cooldown_config.get('symbol_cooldown_minutes', 60)
        self.loss_cooldown_minutes = cooldown_config.get('loss_cooldown_minutes', 180)
        self.global_cooldown_minutes = cooldown_config.get('global_cooldown_minutes', 15)
        self.rapid_signal_threshold = cooldown_config.get('rapid_signal_threshold', 3)
        self.rapid_signal_cooldown_minutes = cooldown_config.get('rapid_signal_cooldown_minutes', 120)

        self.logger.info(f"🛡️ Cooldown Manager initialized (enabled: {self.enabled})")

    def is_symbol_in_cooldown(self, symbol: str) -> Tuple[bool, Optional[datetime]]:
        """
        Check if symbol is currently in cooldown.

        Args:
            symbol: Trading symbol

        Returns:
            (in_cooldown, cooldown_end_time)
        """
        if not self.enabled:
            return False, None

        try:
            query = """
                SELECT cooldown_end_time, reason
                FROM trade_cooldowns
                WHERE symbol = ?
                AND cooldown_end_time > datetime('now')
            """

            with self.db.get_connection() as conn:
                row = conn.execute(query, (symbol,)).fetchone()

                if row:
                    cooldown_end = datetime.fromisoformat(row['cooldown_end_time'])
                    reason = row['reason']
                    remaining = (cooldown_end - datetime.now()).total_seconds() / 60

                    self.logger.info(f"⏳ {symbol} in cooldown: {reason} (remaining: {remaining:.1f} min)")
                    return True, cooldown_end

            return False, None

        except Exception as e:
            self.logger.error(f"Error checking cooldown: {e}")
            return False, None

    def is_global_cooldown_active(self) -> Tuple[bool, Optional[datetime]]:
        """
        Check if global cooldown is active (minimum time between ANY trades).

        Returns:
            (in_cooldown, cooldown_end_time)
        """
        if not self.enabled or self.global_cooldown_minutes == 0:
            return False, None

        try:
            # Get most recent cooldown end time across all symbols
            query = """
                SELECT MAX(last_trade_time) as last_trade
                FROM trade_cooldowns
            """

            with self.db.get_connection() as conn:
                row = conn.execute(query).fetchone()

                if row and row['last_trade']:
                    last_trade = datetime.fromisoformat(row['last_trade'])
                    global_cooldown_end = last_trade + timedelta(minutes=self.global_cooldown_minutes)

                    if datetime.now() < global_cooldown_end:
                        remaining = (global_cooldown_end - datetime.now()).total_seconds() / 60
                        self.logger.info(f"⏳ Global cooldown active (remaining: {remaining:.1f} min)")
                        return True, global_cooldown_end

            return False, None

        except Exception as e:
            self.logger.error(f"Error checking global cooldown: {e}")
            return False, None

    def set_cooldown(self, symbol: str, reason: str = 'TRADE_EXECUTED',
                    direction: str = None, custom_minutes: int = None):
        """
        Set cooldown period after trade.

        Args:
            symbol: Trading symbol
            reason: Cooldown reason ('TRADE_EXECUTED', 'STOP_LOSS', 'RAPID_SIGNALS')
            direction: Trade direction ('BUY', 'SELL')
            custom_minutes: Override default cooldown duration
        """
        if not self.enabled:
            return

        # Determine cooldown duration
        if custom_minutes is not None:
            duration = custom_minutes
        elif reason == 'STOP_LOSS':
            duration = self.loss_cooldown_minutes
        elif reason == 'RAPID_SIGNALS':
            duration = self.rapid_signal_cooldown_minutes
        else:
            duration = self.symbol_cooldown_minutes

        now = datetime.now()
        cooldown_end = now + timedelta(minutes=duration)

        try:
            # Insert or replace cooldown
            query = """
                INSERT OR REPLACE INTO trade_cooldowns
                (symbol, last_trade_time, cooldown_end_time, reason, trade_direction)
                VALUES (?, ?, ?, ?, ?)
            """

            with self.db.get_connection() as conn:
                conn.execute(query, (symbol, now, cooldown_end, reason, direction))
                conn.commit()

            self.logger.info(f"🛡️ Cooldown set: {symbol} for {duration} min ({reason})")

        except Exception as e:
            self.logger.error(f"Error setting cooldown: {e}")

    def check_rapid_signals(self, symbol: str, window_minutes: int = 60) -> Tuple[bool, int]:
        """
        Check if symbol has too many signals in time window.

        Args:
            symbol: Trading symbol
            window_minutes: Time window to check

        Returns:
            (is_rapid, signal_count)
        """
        try:
            # Count signals in window
            window_start = datetime.now() - timedelta(minutes=window_minutes)

            query = """
                SELECT COUNT(*) as count
                FROM signal_confirmations
                WHERE symbol = ?
                AND signal_generated_at > ?
            """

            with self.db.get_connection() as conn:
                row = conn.execute(query, (symbol, window_start)).fetchone()
                count = row['count'] if row else 0

            is_rapid = count >= self.rapid_signal_threshold

            if is_rapid:
                self.logger.warning(f"⚠️ Rapid signals detected: {symbol} ({count} in {window_minutes} min)")

            return is_rapid, count

        except Exception as e:
            self.logger.error(f"Error checking rapid signals: {e}")
            return False, 0

    def can_trade(self, symbol: str) -> Tuple[bool, str]:
        """
        Check if trading is allowed (considering all cooldowns).

        Args:
            symbol: Trading symbol

        Returns:
            (can_trade, reason)
        """
        if not self.enabled:
            return True, "Cooldowns disabled"

        # Check symbol-specific cooldown
        in_cooldown, cooldown_end = self.is_symbol_in_cooldown(symbol)
        if in_cooldown:
            remaining = (cooldown_end - datetime.now()).total_seconds() / 60
            return False, f"Symbol in cooldown ({remaining:.1f} min remaining)"

        # Check global cooldown
        global_cooldown, global_end = self.is_global_cooldown_active()
        if global_cooldown:
            remaining = (global_end - datetime.now()).total_seconds() / 60
            return False, f"Global cooldown active ({remaining:.1f} min remaining)"

        # Check rapid signals
        is_rapid, count = self.check_rapid_signals(symbol)
        if is_rapid:
            # Auto-set rapid signal cooldown
            self.set_cooldown(symbol, reason='RAPID_SIGNALS')
            return False, f"Too many signals ({count} in 60 min), cooldown applied"

        return True, "OK"

    def cleanup_expired_cooldowns(self):
        """
        Remove expired cooldowns from database.
        Call this periodically to keep table clean.
        """
        try:
            query = """
                DELETE FROM trade_cooldowns
                WHERE cooldown_end_time < datetime('now')
            """

            with self.db.get_connection() as conn:
                cursor = conn.execute(query)
                deleted = cursor.rowcount
                conn.commit()

                if deleted > 0:
                    self.logger.debug(f"🧹 Cleaned up {deleted} expired cooldown(s)")

        except Exception as e:
            self.logger.error(f"Error cleaning cooldowns: {e}")

    def get_cooldown_status(self, symbol: str = None) -> Dict:
        """
        Get current cooldown status for monitoring/dashboard.

        Args:
            symbol: Optional symbol to check (None = all symbols)

        Returns:
            Dictionary with cooldown status
        """
        try:
            if symbol:
                query = """
                    SELECT * FROM trade_cooldowns
                    WHERE symbol = ?
                    AND cooldown_end_time > datetime('now')
                """
                params = (symbol,)
            else:
                query = """
                    SELECT * FROM trade_cooldowns
                    WHERE cooldown_end_time > datetime('now')
                    ORDER BY cooldown_end_time ASC
                """
                params = ()

            with self.db.get_connection() as conn:
                rows = conn.execute(query, params).fetchall()

                cooldowns = []
                for row in rows:
                    cooldown_end = datetime.fromisoformat(row['cooldown_end_time'])
                    remaining = (cooldown_end - datetime.now()).total_seconds() / 60

                    cooldowns.append({
                        'symbol': row['symbol'],
                        'reason': row['reason'],
                        'direction': row['trade_direction'],
                        'cooldown_end': row['cooldown_end_time'],
                        'remaining_minutes': round(remaining, 1)
                    })

                return {
                    'enabled': self.enabled,
                    'active_cooldowns': len(cooldowns),
                    'cooldowns': cooldowns
                }

        except Exception as e:
            self.logger.error(f"Error getting cooldown status: {e}")
            return {'enabled': self.enabled, 'error': str(e)}

    def get_cooldown_settings(self) -> Dict:
        """
        Get current cooldown configuration.

        Returns:
            Dictionary with cooldown settings
        """
        return {
            'enabled': self.enabled,
            'symbol_cooldown_minutes': self.symbol_cooldown_minutes,
            'loss_cooldown_minutes': self.loss_cooldown_minutes,
            'global_cooldown_minutes': self.global_cooldown_minutes,
            'rapid_signal_threshold': self.rapid_signal_threshold,
            'rapid_signal_cooldown_minutes': self.rapid_signal_cooldown_minutes
        }
