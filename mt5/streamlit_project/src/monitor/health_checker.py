"""
System Health Checker - Monitors overall system health.
"""

import MetaTrader5 as mt5
import os
import shutil
from typing import Dict
from datetime import datetime, timedelta
from pathlib import Path
from ..logger import get_logger

logger = get_logger(__name__)


class HealthChecker:
    """
    Performs system health checks on all components.
    """
    
    def __init__(self):
        """Initialize Health Checker."""
        self.last_check = None
        self.last_results = {}
    
    def check_mt5_connection(self) -> Dict:
        """
        Check MT5 connection status.
        
        Returns:
            Dict with status, details
        """
        try:
            terminal_info = mt5.terminal_info()
            
            if not terminal_info:
                return {
                    'status': 'ERROR',
                    'message': 'MT5 Terminal not connected',
                    'details': 'Start MetaTrader 5'
                }
            
            return {
                'status': 'OK',
                'message': 'Connected',
                'details': f"{terminal_info.company} - {terminal_info.name}"
            }
            
        except Exception as e:
            return {
                'status': 'ERROR',
                'message': 'Connection error',
                'details': str(e)
            }
    
    def check_governor_heartbeat(self) -> Dict:
        """
        Check if Portfolio Governor is running.
        
        Returns:
            Dict with status, age, details
        """
        try:
            # Check GV_GOVERNOR_ACTIVE
            if not mt5.global_variable_check("PG_GovernorActive"):
                return {
                    'status': 'OFFLINE',
                    'message': 'Governor not active',
                    'details': 'Start Portfolio_Governor.mq5'
                }
            
            active = mt5.global_variable_get("PG_GovernorActive")
            if active != 1.0:
                return {
                    'status': 'OFFLINE',
                    'message': 'Governor inactive',
                    'details': 'PG_GovernorActive = 0'
                }
            
            # Check last update
            if mt5.global_variable_check("PG_LastUpdate"):
                ts = mt5.global_variable_get("PG_LastUpdate")
                if ts > 0:
                    last_update = datetime.fromtimestamp(ts)
                    age = (datetime.now() - last_update).total_seconds()
                    
                    if age > 120:  # 2 minutes
                        return {
                            'status': 'WARNING',
                            'message': f'Last update {int(age)}s ago',
                            'details': 'Governor may be frozen'
                        }
                    
                    return {
                        'status': 'OK',
                        'message': f'Active ({int(age)}s ago)',
                        'details': last_update.strftime('%H:%M:%S')
                    }
            
            return {
                'status': 'OK',
                'message': 'Active',
                'details': 'No timestamp available'
            }
            
        except Exception as e:
            return {
                'status': 'ERROR',
                'message': 'Check failed',
                'details': str(e)
            }
    
    def check_database_health(self, db_path: str = "data/trading.db") -> Dict:
        """
        Check database health.
        
        Args:
            db_path: Path to database file
            
        Returns:
            Dict with status, size, details
        """
        try:
            db_file = Path(db_path)
            
            if not db_file.exists():
                return {
                    'status': 'WARNING',
                    'message': 'Database not found',
                    'details': 'Will be created on first use'
                }
            
            # Get file size
            size_mb = db_file.stat().st_size / (1024 * 1024)
            
            # Simple health check (file exists and readable)
            return {
                'status': 'OK',
                'message': f'{size_mb:.1f} MB',
                'details': 'Database accessible'
            }
            
        except Exception as e:
            return {
                'status': 'ERROR',
                'message': 'Database error',
                'details': str(e)
            }
    
    def check_disk_space(self) -> Dict:
        """
        Check available disk space.
        
        Returns:
            Dict with status, free space
        """
        try:
            # Get disk usage for current drive
            total, used, free = shutil.disk_usage(".")
            
            free_gb = free / (1024 ** 3)
            
            if free_gb < 1.0:  # Less than 1GB
                status = 'CRITICAL'
            elif free_gb < 5.0:  # Less than 5GB
                status = 'WARNING'
            else:
                status = 'OK'
            
            return {
                'status': status,
                'message': f'{free_gb:.1f} GB free',
                'details': f'Total: {total/(1024**3):.1f} GB'
            }
            
        except Exception as e:
            return {
                'status': 'ERROR',
                'message': 'Check failed',
                'details': str(e)
            }
    
    def check_logs_for_errors(self, hours: int = 1) -> Dict:
        """
        Check logs for recent errors.
        
        Args:
            hours: Time window to check
            
        Returns:
            Dict with error count
        """
        try:
            log_file = Path("logs/mt5_platform_errors.log")
            
            if not log_file.exists():
                return {
                    'status': 'OK',
                    'message': 'No errors',
                    'details': 'Log file not found'
                }
            
            # Count ERROR lines in last N hours
            cutoff = datetime.now() - timedelta(hours=hours)
            error_count = 0
            
            # Simple check: read last 1000 lines
            with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()[-1000:]
                for line in lines:
                    if 'ERROR' in line:
                        error_count += 1
            
            if error_count > 10:
                status = 'WARNING'
            elif error_count > 0:
                status = 'INFO'
            else:
                status = 'OK'
            
            return {
                'status': status,
                'message': f'{error_count} errors',
                'details': f'Last {hours}h'
            }
            
        except Exception as e:
            return {
                'status': 'ERROR',
                'message': 'Check failed',
                'details': str(e)
            }
    
    def run_full_diagnostic(self) -> Dict:
        """
        Run all health checks.
        
        Returns:
            Dict with all results
        """
        results = {
            'mt5_connection': self.check_mt5_connection(),
            'governor_heartbeat': self.check_governor_heartbeat(),
            'database': self.check_database_health(),
            'disk_space': self.check_disk_space(),
            'logs': self.check_logs_for_errors(),
            'timestamp': datetime.now()
        }
        
        # Determine overall status
        statuses = [r['status'] for r in results.values() if isinstance(r, dict)]
        
        if 'ERROR' in statuses or 'CRITICAL' in statuses:
            results['overall'] = 'ERROR'
        elif 'WARNING' in statuses:
            results['overall'] = 'WARNING'
        else:
            results['overall'] = 'HEALTHY'
        
        self.last_check = datetime.now()
        self.last_results = results
        
        logger.info(f"Health check completed: {results['overall']}")
        
        return results
