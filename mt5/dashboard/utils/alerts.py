"""
Alert System for MT5 Dashboard
Handles email and Telegram notifications
"""

import os
import json
from datetime import datetime
from typing import Dict, Any, List


class AlertManager:
    """Manage alerts and notifications"""

    def __init__(self, config_path: str = None):
        """Initialize alert manager"""
        self.config_path = config_path or os.path.join(
            os.path.dirname(__file__), '..', 'alert_config.json'
        )
        self.config = self.load_config()

    def load_config(self) -> Dict[str, Any]:
        """Load alert configuration"""
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Error loading alert config: {e}")

        # Default configuration
        return {
            'email': {
                'enabled': False,
                'smtp_server': '',
                'smtp_port': 587,
                'from_email': '',
                'to_email': '',
                'password': ''
            },
            'telegram': {
                'enabled': False,
                'bot_token': '',
                'chat_id': ''
            },
            'alert_types': {
                'new_position': True,
                'position_closed': True,
                'daily_target_hit': True,
                'daily_loss_limit': True,
                'drawdown_5pct': True,
                'drawdown_10pct': True,
                'drawdown_15pct': True,
                'max_positions_reached': False,
                'high_score_signal': True
            },
            'thresholds': {
                'daily_target': 500,
                'daily_loss_limit': -300,
                'high_score_signal': 18
            }
        }

    def save_config(self, config: Dict[str, Any]):
        """Save alert configuration"""
        try:
            with open(self.config_path, 'w') as f:
                json.dump(config, f, indent=2)
            self.config = config
            return True
        except Exception as e:
            print(f"Error saving alert config: {e}")
            return False

    def send_email(self, subject: str, body: str) -> bool:
        """Send email alert"""
        if not self.config['email']['enabled']:
            return False

        try:
            import smtplib
            from email.mime.text import MIMEText
            from email.mime.multipart import MIMEMultipart

            msg = MIMEMultipart()
            msg['From'] = self.config['email']['from_email']
            msg['To'] = self.config['email']['to_email']
            msg['Subject'] = subject

            msg.attach(MIMEText(body, 'html'))

            server = smtplib.SMTP(
                self.config['email']['smtp_server'],
                self.config['email']['smtp_port']
            )
            server.starttls()
            server.login(
                self.config['email']['from_email'],
                self.config['email']['password']
            )

            server.send_message(msg)
            server.quit()

            return True

        except Exception as e:
            print(f"Error sending email: {e}")
            return False

    def send_telegram(self, message: str) -> bool:
        """Send Telegram alert"""
        if not self.config['telegram']['enabled']:
            return False

        try:
            import requests

            url = f"https://api.telegram.org/bot{self.config['telegram']['bot_token']}/sendMessage"
            data = {
                'chat_id': self.config['telegram']['chat_id'],
                'text': message,
                'parse_mode': 'HTML'
            }

            response = requests.post(url, data=data, timeout=10)
            return response.status_code == 200

        except Exception as e:
            print(f"Error sending Telegram message: {e}")
            return False

    def send_alert(self, alert_type: str, data: Dict[str, Any]) -> Dict[str, bool]:
        """
        Send alert via configured channels

        Args:
            alert_type: Type of alert (new_position, position_closed, etc.)
            data: Alert data dictionary

        Returns:
            Dict with success status for each channel
        """
        # Check if this alert type is enabled
        if not self.config['alert_types'].get(alert_type, False):
            return {'email': False, 'telegram': False}

        # Format message based on alert type
        subject, message = self.format_alert(alert_type, data)

        results = {}

        # Send via email
        if self.config['email']['enabled']:
            results['email'] = self.send_email(subject, message)
        else:
            results['email'] = False

        # Send via Telegram
        if self.config['telegram']['enabled']:
            telegram_message = self.format_telegram_message(alert_type, data)
            results['telegram'] = self.send_telegram(telegram_message)
        else:
            results['telegram'] = False

        return results

    def format_alert(self, alert_type: str, data: Dict[str, Any]) -> tuple:
        """Format alert message for email"""
        subject = ""
        body = ""

        if alert_type == "new_position":
            subject = f"🟢 New Position Opened: {data.get('symbol')}"
            body = f"""
            <h2>New Position Opened</h2>
            <ul>
                <li><strong>Symbol:</strong> {data.get('symbol')}</li>
                <li><strong>Type:</strong> {data.get('type')}</li>
                <li><strong>Lots:</strong> {data.get('lots')}</li>
                <li><strong>Entry Price:</strong> {data.get('entry_price')}</li>
                <li><strong>Score:</strong> {data.get('score')}</li>
                <li><strong>Time:</strong> {data.get('time')}</li>
            </ul>
            """

        elif alert_type == "position_closed":
            profit = data.get('profit', 0)
            emoji = "🟢" if profit > 0 else "🔴"
            subject = f"{emoji} Position Closed: {data.get('symbol')} - ${profit:.2f}"
            body = f"""
            <h2>Position Closed</h2>
            <ul>
                <li><strong>Symbol:</strong> {data.get('symbol')}</li>
                <li><strong>Profit:</strong> ${profit:.2f}</li>
                <li><strong>Close Price:</strong> {data.get('close_price')}</li>
                <li><strong>Exit Reason:</strong> {data.get('exit_reason')}</li>
                <li><strong>Time:</strong> {data.get('time')}</li>
            </ul>
            """

        elif alert_type == "daily_target_hit":
            subject = "🎯 Daily Profit Target Hit!"
            body = f"""
            <h2>Daily Target Achieved!</h2>
            <p>Congratulations! You've hit your daily profit target.</p>
            <ul>
                <li><strong>Target:</strong> ${data.get('target'):.2f}</li>
                <li><strong>Current P/L:</strong> ${data.get('current_pl'):.2f}</li>
                <li><strong>Time:</strong> {data.get('time')}</li>
            </ul>
            """

        elif alert_type == "daily_loss_limit":
            subject = "⚠️ Daily Loss Limit Reached"
            body = f"""
            <h2>Daily Loss Limit</h2>
            <p><strong>Warning:</strong> Daily loss limit has been reached.</p>
            <ul>
                <li><strong>Limit:</strong> ${data.get('limit'):.2f}</li>
                <li><strong>Current P/L:</strong> ${data.get('current_pl'):.2f}</li>
                <li><strong>Time:</strong> {data.get('time')}</li>
            </ul>
            <p>Consider stopping trading for today.</p>
            """

        elif alert_type in ["drawdown_5pct", "drawdown_10pct", "drawdown_15pct"]:
            pct = alert_type.split('_')[1]
            subject = f"🔴 Drawdown Alert: {pct} Reached"
            body = f"""
            <h2>Drawdown Alert</h2>
            <p><strong>Warning:</strong> Account drawdown has reached {pct}.</p>
            <ul>
                <li><strong>Current Drawdown:</strong> {data.get('drawdown_pct'):.2f}%</li>
                <li><strong>Peak Equity:</strong> ${data.get('peak_equity'):.2f}</li>
                <li><strong>Current Equity:</strong> ${data.get('current_equity'):.2f}</li>
                <li><strong>Time:</strong> {data.get('time')}</li>
            </ul>
            """

        elif alert_type == "high_score_signal":
            subject = f"🔥 Elite Signal: {data.get('symbol')} - Score {data.get('score'):.1f}"
            body = f"""
            <h2>Elite Signal Detected</h2>
            <ul>
                <li><strong>Symbol:</strong> {data.get('symbol')}</li>
                <li><strong>Direction:</strong> {data.get('direction')}</li>
                <li><strong>Score:</strong> {data.get('score'):.1f} / 30</li>
                <li><strong>Allowed:</strong> {data.get('allowed')}</li>
                <li><strong>Time:</strong> {data.get('time')}</li>
            </ul>
            """

        return subject, body

    def format_telegram_message(self, alert_type: str, data: Dict[str, Any]) -> str:
        """Format alert message for Telegram"""
        if alert_type == "new_position":
            return f"""
🟢 <b>New Position</b>

Symbol: {data.get('symbol')}
Type: {data.get('type')}
Lots: {data.get('lots')}
Entry: {data.get('entry_price')}
Score: {data.get('score')}
            """.strip()

        elif alert_type == "position_closed":
            profit = data.get('profit', 0)
            emoji = "🟢" if profit > 0 else "🔴"
            return f"""
{emoji} <b>Position Closed</b>

Symbol: {data.get('symbol')}
Profit: ${profit:.2f}
Reason: {data.get('exit_reason')}
            """.strip()

        elif alert_type == "daily_target_hit":
            return f"""
🎯 <b>Daily Target Hit!</b>

Target: ${data.get('target'):.2f}
Current P/L: ${data.get('current_pl'):.2f}
            """.strip()

        elif alert_type == "daily_loss_limit":
            return f"""
⚠️ <b>Daily Loss Limit</b>

Limit: ${data.get('limit'):.2f}
Current P/L: ${data.get('current_pl'):.2f}

Consider stopping for today.
            """.strip()

        elif alert_type.startswith("drawdown_"):
            return f"""
🔴 <b>Drawdown Alert</b>

Drawdown: {data.get('drawdown_pct'):.2f}%
Peak: ${data.get('peak_equity'):.2f}
Current: ${data.get('current_equity'):.2f}
            """.strip()

        elif alert_type == "high_score_signal":
            return f"""
🔥 <b>Elite Signal</b>

Symbol: {data.get('symbol')}
Direction: {data.get('direction')}
Score: {data.get('score'):.1f}/30
Allowed: {data.get('allowed')}
            """.strip()

        return ""

    def test_connection(self, channel: str) -> tuple:
        """
        Test alert channel connection

        Args:
            channel: 'email' or 'telegram'

        Returns:
            (success: bool, message: str)
        """
        test_data = {
            'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }

        if channel == 'email':
            subject = "MT5 Dashboard - Test Email"
            body = f"""
            <h2>Test Email</h2>
            <p>This is a test email from your MT5 Portfolio Dashboard.</p>
            <p>Time: {test_data['time']}</p>
            <p>If you received this, your email configuration is working correctly!</p>
            """

            success = self.send_email(subject, body)
            return (success, "Email sent successfully!" if success else "Failed to send email")

        elif channel == 'telegram':
            message = f"""
<b>MT5 Dashboard - Test Message</b>

Time: {test_data['time']}

If you received this, your Telegram configuration is working correctly!
            """.strip()

            success = self.send_telegram(message)
            return (success, "Telegram message sent!" if success else "Failed to send Telegram message")

        return (False, "Invalid channel")
