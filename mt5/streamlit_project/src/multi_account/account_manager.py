"""
Account Manager - Multi-account support for MT5 trading dashboard.
Automatically detects current account and loads appropriate configuration.
"""

import MetaTrader5 as mt5
import sqlite3
import json
from typing import Dict, List, Optional
from datetime import datetime
from pathlib import Path
from ..logger import get_logger

logger = get_logger(__name__)


class AccountManager:
    """
    Manages multiple MT5 accounts with per-account configuration.
    
    Features:
    - Auto-detects current MT5 account
    - Stores account-specific preferences
    - Manages separate databases per account
    - Lists known accounts for switching
    """
    
    def __init__(self, db_path: str = "data/accounts.db"):
        """
        Initialize Account Manager.
        
        Args:
            db_path: Path to accounts database
        """
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.init_database()
        
    def init_database(self):
        """Create accounts table if not exists."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS accounts (
                    account_id INTEGER PRIMARY KEY,
                    login TEXT NOT NULL,
                    server TEXT,
                    name TEXT,
                    broker TEXT,
                    first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    last_used TIMESTAMP,
                    config TEXT,
                    notes TEXT
                )
            """)
            
            conn.commit()
            conn.close()
            logger.info("Accounts database initialized")
            
        except Exception as e:
            logger.error(f"Error initializing accounts database: {e}")
    
    def get_current_account(self) -> Optional[Dict]:
        """
        Get current MT5 account information.
        
        Returns:
            Dict with account info or None if not connected
        """
        try:
            account_info = mt5.account_info()
            if not account_info:
                return None
            
            account = {
                'login': str(account_info.login),
                'server': account_info.server,
                'name': account_info.name,
                'broker': account_info.company,
                'balance': account_info.balance,
                'equity': account_info.equity,
                'currency': account_info.currency,
                'leverage': account_info.leverage
            }
            
            # Register/update in database
            self._register_account(account)
            
            return account
            
        except Exception as e:
            logger.error(f"Error getting current account: {e}")
            return None
    
    def _register_account(self, account: Dict):
        """Register or update account in database."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Check if account exists
            cursor.execute(
                "SELECT account_id FROM accounts WHERE login = ?",
                (account['login'],)
            )
            
            if cursor.fetchone():
                # Update last_used
                cursor.execute(
                    "UPDATE accounts SET last_used = ?, server = ?, name = ?, broker = ? WHERE login = ?",
                    (datetime.now(), account['server'], account['name'], account['broker'], account['login'])
                )
            else:
                # Insert new account
                cursor.execute(
                    "INSERT INTO accounts (login, server, name, broker, last_used) VALUES (?, ?, ?, ?, ?)",
                    (account['login'], account['server'], account['name'], account['broker'], datetime.now())
                )
            
            conn.commit()
            conn.close()
            
        except Exception as e:
            logger.error(f"Error registering account: {e}")
    
    def get_account_config(self, login: str) -> Dict:
        """
        Load configuration for specific account.
        
        Args:
            login: Account login number
            
        Returns:
            Dict with configuration
        """
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute(
                "SELECT config FROM accounts WHERE login = ?",
                (login,)
            )
            
            result = cursor.fetchone()
            conn.close()
            
            if result and result[0]:
                return json.loads(result[0])
            
            # Return default config
            return self._get_default_config()
            
        except Exception as e:
            logger.error(f"Error loading config for account {login}: {e}")
            return self._get_default_config()
    
    def save_account_config(self, login: str, config: Dict):
        """
        Save configuration for specific account.
        
        Args:
            login: Account login number
            config: Configuration dict
        """
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            config_json = json.dumps(config)
            
            cursor.execute(
                "UPDATE accounts SET config = ? WHERE login = ?",
                (config_json, login)
            )
            
            conn.commit()
            conn.close()
            
            logger.info(f"Saved config for account {login}")
            
        except Exception as e:
            logger.error(f"Error saving config for account {login}: {e}")
    
    def list_known_accounts(self) -> List[Dict]:
        """
        Get list of all known accounts.
        
        Returns:
            List of account dicts (sorted by last_used)
        """
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT login, server, name, broker, last_used
                FROM accounts
                ORDER BY last_used DESC
            """)
            
            accounts = []
            for row in cursor.fetchall():
                accounts.append({
                    'login': row[0],
                    'server': row[1],
                    'name': row[2],
                    'broker': row[3],
                    'last_used': row[4]
                })
            
            conn.close()
            return accounts
            
        except Exception as e:
            logger.error(f"Error listing accounts: {e}")
            return []
    
    def get_account_database_path(self, login: str) -> str:
        """
        Get database path for specific account.
        
        Args:
            login: Account login number
            
        Returns:
            Path string (e.g., "data/trading_12345678.db")
        """
        return f"data/trading_{login}.db"
    
    def _get_default_config(self) -> Dict:
        """Get default configuration."""
        return {
            'auto_refresh': True,
            'refresh_interval': 10,
            'days_to_fetch': 30,
            'initial_balance': 10000.0,
            'theme': 'dark',
            'timezone': 'UTC'
        }
    
    def delete_account(self, login: str):
        """
        Remove account from database.
        
        Args:
            login: Account login number
        """
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM accounts WHERE login = ?", (login,))
            
            conn.commit()
            conn.close()
            
            logger.info(f"Deleted account {login}")
            
        except Exception as e:
            logger.error(f"Error deleting account {login}: {e}")
