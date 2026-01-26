"""
Alert Manager - Intelligent alert system for trading dashboard.
Monitors EA health, Governor thresholds, and generates notifications.
"""

import MetaTrader5 as mt5
from typing import List, Dict
from datetime import datetime, timedelta
from ..logger import get_logger

logger = get_logger(__name__)


class AlertManager:
    """
    Manages alerts and notifications for the dashboard.
    
    Alert Types:
    - CRITICAL: EA offline, DD limit, trading paused
    - WARNING: High DD, low PF, correlation issues
    - INFO: Trade closed, sync successful
    """
    
    ALERT_TYPES = {
        'CRITICAL': {'color': 'red', 'icon': '🔴', 'sound': True},
        'WARNING': {'color': 'orange', 'icon': '🟡', 'sound': False},
        'INFO': {'color': 'green', 'icon': '🟢', 'sound': False}
    }
    
    def __init__(self, max_alerts: int = 100):
        """
        Initialize Alert Manager.
        
        Args:
            max_alerts: Maximum alerts to keep in memory
        """
        self.alerts = []
        self.max_alerts = max_alerts
        self.last_check = {}
    
    def check_ea_health(self, ea_statuses: Dict[str, Dict]) -> List[Dict]:
        """
        Check EA health and generate alerts.
        
        Args:
            ea_statuses: Dict from EAStatusChecker
            
        Returns:
            List of new alerts
        """
        new_alerts = []
        
        for symbol, status in ea_statuses.items():
            # Alert if EA offline
            if status['status'] == 'OFFLINE':
                # Check if already alerted recently (avoid spam)
                last_alert_key = f"ea_offline_{symbol}"
                if self._should_alert(last_alert_key, minutes=5):
                    alert = self._create_alert(
                        'CRITICAL',
                        f"EA {symbol} is OFFLINE",
                        f"Symbol Engine for {symbol} has been offline for >2 minutes"
                    )
                    new_alerts.append(alert)
                    self.last_check[last_alert_key] = datetime.now()
            
            # Alert if EA inactive but should be active
            elif status['status'] == 'INACTIVE' and status['governor_multiplier'] == 1.0:
                last_alert_key = f"ea_inactive_{symbol}"
                if self._should_alert(last_alert_key, minutes=10):
                    alert = self._create_alert(
                        'WARNING',
                        f"EA {symbol} inactive despite Governor = 1.0",
                        f"Check if Symbol_Engine is attached to {symbol} chart"
                    )
                    new_alerts.append(alert)
                    self.last_check[last_alert_key] = datetime.now()
        
        return new_alerts
    
    def check_governor_thresholds(self, metrics: Dict) -> List[Dict]:
        """
        Check Governor metrics against thresholds.
        
        Args:
            metrics: Dict from GovernorMonitor
            
        Returns:
            List of new alerts
        """
        new_alerts = []
        
        if not metrics.get('active'):
            # Governor offline
            if self._should_alert('governor_offline', minutes=5):
                alert = self._create_alert(
                    'CRITICAL',
                    "Portfolio Governor OFFLINE",
                    "Start Portfolio_Governor.mq5 on MT5"
                )
                new_alerts.append(alert)
                self.last_check['governor_offline'] = datetime.now()
            return new_alerts
        
        # Check DD threshold
        dd = metrics.get('dd', 0.0)
        if dd >= 7.0:  # Warning at 7%, critical at 8%
            if self._should_alert('high_dd', minutes=15):
                severity = 'CRITICAL' if dd >= 8.0 else 'WARNING'
                alert = self._create_alert(
                    severity,
                    f"Portfolio DD: {dd:.1f}%",
                    f"Drawdown is {'at limit' if dd >= 8.0 else 'approaching limit (8.0%)'}"
                )
                new_alerts.append(alert)
                self.last_check['high_dd'] = datetime.now()
        
        # Check Daily DD
        daily_dd = metrics.get('daily_dd', 0.0)
        if daily_dd >= 2.5:  # Daily limit usually 3%
            if self._should_alert('high_daily_dd', minutes=30):
                alert = self._create_alert(
                    'WARNING',
                    f"Daily DD: {daily_dd:.1f}%",
                    "Approaching daily drawdown limit"
                )
                new_alerts.append(alert)
                self.last_check['high_daily_dd'] = datetime.now()
        
        # Check PF threshold
        pf = metrics.get('pf', 0.0)
        if pf > 0 and pf < 1.2:  # Low PF
            if self._should_alert('low_pf', minutes=60):
                alert = self._create_alert(
                    'WARNING',
                    f"Low Rolling PF: {pf:.2f}",
                    "Profit Factor below 1.2 threshold"
                )
                new_alerts.append(alert)
                self.last_check['low_pf'] = datetime.now()
        
        # Check if trading paused
        if not metrics.get('trading_enabled'):
            if self._should_alert('trading_paused', minutes=10):
                alert = self._create_alert(
                    'WARNING',
                    "Trading PAUSED by Governor",
                    "Check Governor status and resume if appropriate"
                )
                new_alerts.append(alert)
                self.last_check['trading_paused'] = datetime.now()
        
        return new_alerts
    
    def add_info_alert(self, title: str, message: str):
        """
        Manually add an INFO alert.
        
        Args:
            title: Alert title
            message: Alert message
        """
        alert = self._create_alert('INFO', title, message)
        self.alerts.append(alert)
        self._trim_alerts()
    
    def get_recent_alerts(self, minutes: int = 60) -> List[Dict]:
        """
        Get alerts from last N minutes.
        
        Args:
            minutes: Time window
            
        Returns:
            List of recent alerts
        """
        cutoff = datetime.now() - timedelta(minutes=minutes)
        return [a for a in self.alerts if a['timestamp'] >= cutoff]
    
    def get_all_alerts(self) -> List[Dict]:
        """Get all alerts."""
        return self.alerts
    
    def clear_alerts(self):
        """Clear all alerts."""
        self.alerts = []
        self.last_check = {}
        logger.info("Cleared all alerts")
    
    def _create_alert(self, severity: str, title: str, message: str) -> Dict:
        """Create alert dict."""
        alert = {
            'severity': severity,
            'title': title,
            'message': message,
            'timestamp': datetime.now(),
            'icon': self.ALERT_TYPES[severity]['icon'],
            'color': self.ALERT_TYPES[severity]['color'],
            'sound': self.ALERT_TYPES[severity]['sound']
        }
        
        self.alerts.append(alert)
        self._trim_alerts()
        
        logger.info(f"Alert {severity}: {title}")
        return alert
    
    def _should_alert(self, key: str, minutes: int) -> bool:
        """
        Check if should alert for this key (anti-spam).
        
        Args:
            key: Alert key
            minutes: Cooldown period
            
        Returns:
            True if should alert
        """
        if key not in self.last_check:
            return True
        
        elapsed = (datetime.now() - self.last_check[key]).total_seconds() / 60
        return elapsed >= minutes
    
    def _trim_alerts(self):
        """Keep only max_alerts most recent."""
        if len(self.alerts) > self.max_alerts:
            self.alerts = self.alerts[-self.max_alerts:]
