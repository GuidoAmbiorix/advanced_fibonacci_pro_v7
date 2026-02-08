"""
Performance Alerts System
=========================
Monitors trading performance and generates automated alerts for:
- Sharpe degradation
- Drawdown thresholds
- Correlation spikes
- Win rate drops
- Symbol underperformance

Also manages OptimizationSchedule and priority scoring.
"""

import sqlite3
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Tuple
import json


class AlertsSystem:
    def __init__(self, db_path: str):
        self.db_path = db_path

    def get_connection(self):
        return sqlite3.connect(self.db_path, check_same_thread=False)

    # =========================================================================
    # ALERT GENERATION
    # =========================================================================

    def create_alert(
        self,
        alert_type: str,
        severity: str,
        title: str,
        message: str,
        symbol: str = None,
        metric_name: str = None,
        current_value: float = None,
        threshold_value: float = None,
        suggested_action: str = None
    ):
        """Create a new performance alert"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute("""
                INSERT INTO PerformanceAlerts (
                    timestamp, alert_type, severity, title, message,
                    symbol, metric_name, current_value, threshold_value,
                    suggested_action
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                int(datetime.now().timestamp()), alert_type, severity,
                title, message, symbol, metric_name, current_value,
                threshold_value, suggested_action
            ))

            conn.commit()
            print(f"🔔 Alert created: [{severity}] {title}")

        except Exception as e:
            print(f"❌ Error creating alert: {e}")
            conn.rollback()
        finally:
            conn.close()

    def check_sharpe_degradation(self):
        """Alert if Sharpe has dropped significantly since last optimization"""
        conn = self.get_connection()

        try:
            # Get symbols with optimization history
            df_schedule = pd.read_sql("""
                SELECT symbol, last_optimization_sharpe, current_sharpe, degradation_pct
                FROM OptimizationSchedule
                WHERE last_optimization_sharpe IS NOT NULL
            """, conn)

            for _, row in df_schedule.iterrows():
                symbol = row['symbol']
                last_opt_sharpe = row['last_optimization_sharpe']
                current_sharpe = row['current_sharpe'] if pd.notna(row['current_sharpe']) else 0
                degradation = row['degradation_pct'] if pd.notna(row['degradation_pct']) else 0

                # Alert if 30% degradation
                if degradation > 30:
                    self.create_alert(
                        alert_type='DEGRADATION',
                        severity='WARNING',
                        title=f'{symbol} Sharpe Degradation',
                        message=f'Sharpe dropped {degradation:.1f}% since last optimization',
                        symbol=symbol,
                        metric_name='sharpe_ratio',
                        current_value=current_sharpe,
                        threshold_value=last_opt_sharpe * 0.7,
                        suggested_action=f'Re-optimize {symbol} parameters'
                    )

                # Critical if 50% degradation
                elif degradation > 50:
                    self.create_alert(
                        alert_type='DEGRADATION',
                        severity='CRITICAL',
                        title=f'{symbol} Severe Sharpe Degradation',
                        message=f'Sharpe dropped {degradation:.1f}% - urgent re-optimization needed',
                        symbol=symbol,
                        metric_name='sharpe_ratio',
                        current_value=current_sharpe,
                        threshold_value=last_opt_sharpe * 0.5,
                        suggested_action=f'URGENT: Re-optimize or disable {symbol}'
                    )

        except Exception as e:
            print(f"❌ Error checking Sharpe degradation: {e}")
        finally:
            conn.close()

    def check_drawdown_threshold(self):
        """Alert if drawdown exceeds historical maximum"""
        conn = self.get_connection()

        try:
            # Get current drawdown
            df_current = pd.read_sql("""
                SELECT * FROM DrawdownHistory
                WHERE status = 'ongoing'
                ORDER BY id DESC LIMIT 1
            """, conn)

            if df_current.empty:
                return

            current_dd_pct = df_current['drawdown_pct'].iloc[0]

            # Get historical max
            df_historical = pd.read_sql("""
                SELECT MAX(drawdown_pct) as max_dd
                FROM DrawdownHistory
                WHERE status = 'recovered'
            """, conn)

            if not df_historical.empty and pd.notna(df_historical['max_dd'].iloc[0]):
                max_historical_dd = df_historical['max_dd'].iloc[0]

                # Alert if exceeds historical max by 20%
                if current_dd_pct > max_historical_dd * 1.2:
                    self.create_alert(
                        alert_type='DRAWDOWN',
                        severity='CRITICAL',
                        title='Drawdown Exceeds Historical Maximum',
                        message=f'Current DD: {current_dd_pct:.1f}% exceeds historical max ({max_historical_dd:.1f}%) by 20%',
                        metric_name='drawdown_pct',
                        current_value=current_dd_pct,
                        threshold_value=max_historical_dd * 1.2,
                        suggested_action='Consider reducing position sizes or pausing trading'
                    )

        except Exception as e:
            print(f"❌ Error checking drawdown threshold: {e}")
        finally:
            conn.close()

    def check_correlation_spike(self):
        """Alert if average correlation is too high"""
        conn = self.get_connection()

        try:
            # Get latest correlation matrix
            df_corr = pd.read_sql("""
                SELECT AVG(ABS(correlation)) as avg_corr
                FROM CorrelationMatrix
                WHERE timestamp = (SELECT MAX(timestamp) FROM CorrelationMatrix)
            """, conn)

            if not df_corr.empty and pd.notna(df_corr['avg_corr'].iloc[0]):
                avg_corr = df_corr['avg_corr'].iloc[0]

                # Alert if avg correlation > 0.75
                if avg_corr > 0.75:
                    self.create_alert(
                        alert_type='CORRELATION',
                        severity='WARNING',
                        title='High Portfolio Correlation',
                        message=f'Average correlation: {avg_corr:.2f} (threshold: 0.75)',
                        metric_name='avg_correlation',
                        current_value=avg_corr,
                        threshold_value=0.75,
                        suggested_action='Review symbol selection for diversification'
                    )

        except Exception as e:
            print(f"❌ Error checking correlation: {e}")
        finally:
            conn.close()

    def check_win_rate_drop(self):
        """Alert if 7-day rolling win rate drops below threshold"""
        conn = self.get_connection()

        try:
            # Get last 7 days performance
            seven_days_ago = (datetime.now() - timedelta(days=7)).strftime('%Y-%m-%d')

            df_daily = pd.read_sql("""
                SELECT AVG(win_rate) as avg_winrate
                FROM DailyPerformance
                WHERE date >= ?
            """, conn, params=(seven_days_ago,))

            if not df_daily.empty and pd.notna(df_daily['avg_winrate'].iloc[0]):
                avg_winrate = df_daily['avg_winrate'].iloc[0]

                # Alert if win rate < 40%
                if avg_winrate < 40:
                    self.create_alert(
                        alert_type='LOW_WINRATE',
                        severity='WARNING',
                        title='7-Day Win Rate Below Threshold',
                        message=f'7-day win rate: {avg_winrate:.1f}% (threshold: 40%)',
                        metric_name='win_rate',
                        current_value=avg_winrate,
                        threshold_value=40.0,
                        suggested_action='Review recent trades and consider strategy adjustment'
                    )

        except Exception as e:
            print(f"❌ Error checking win rate: {e}")
        finally:
            conn.close()

    def check_symbol_underperformance(self):
        """Alert if any symbol is consistently underperforming"""
        conn = self.get_connection()

        try:
            # Get last 30 days symbol performance
            thirty_days_ago = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')

            df_symbols = pd.read_sql("""
                SELECT
                    symbol,
                    AVG(sharpe_ratio) as avg_sharpe,
                    SUM(total_trades) as total_trades,
                    AVG(win_rate) as avg_winrate
                FROM SymbolPerformance
                WHERE date >= ?
                GROUP BY symbol
                HAVING total_trades > 10
            """, conn, params=(thirty_days_ago,))

            for _, row in df_symbols.iterrows():
                symbol = row['symbol']
                avg_sharpe = row['avg_sharpe'] if pd.notna(row['avg_sharpe']) else 0
                avg_winrate = row['avg_winrate'] if pd.notna(row['avg_winrate']) else 0

                # Alert if Sharpe < 0.3 and enough trades
                if avg_sharpe < 0.3 and row['total_trades'] > 10:
                    self.create_alert(
                        alert_type='SYMBOL_WEAK',
                        severity='INFO',
                        title=f'{symbol} Underperforming',
                        message=f'{symbol} Sharpe: {avg_sharpe:.2f}, Win Rate: {avg_winrate:.1f}%',
                        symbol=symbol,
                        metric_name='sharpe_ratio',
                        current_value=avg_sharpe,
                        threshold_value=0.3,
                        suggested_action=f'Consider re-optimizing or disabling {symbol}'
                    )

        except Exception as e:
            print(f"❌ Error checking symbol performance: {e}")
        finally:
            conn.close()

    def run_all_checks(self):
        """Run all alert checks"""
        print("\n🔍 Running performance alert checks...")

        self.check_sharpe_degradation()
        self.check_drawdown_threshold()
        self.check_correlation_spike()
        self.check_win_rate_drop()
        self.check_symbol_underperformance()

        # Count new unacknowledged alerts
        conn = self.get_connection()
        df_count = pd.read_sql("""
            SELECT COUNT(*) as new_alerts
            FROM PerformanceAlerts
            WHERE acknowledged = 0
            AND timestamp > ?
        """, conn, params=(int((datetime.now() - timedelta(hours=1)).timestamp()),))
        conn.close()

        new_alerts = df_count['new_alerts'].iloc[0]
        print(f"✅ Alert checks complete. {new_alerts} new alerts generated\n")

    # =========================================================================
    # OPTIMIZATION SCHEDULE MANAGEMENT
    # =========================================================================

    def update_optimization_schedule(self):
        """Update optimization schedule for all symbols"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            # Get all symbols
            symbols = pd.read_sql("SELECT DISTINCT symbol FROM SymbolConfigs", conn)['symbol'].tolist()

            for symbol in symbols:
                # Get last optimization
                df_last_opt = pd.read_sql("""
                    SELECT completed_at, best_sharpe
                    FROM OptimizationRuns
                    WHERE symbol = ? AND status = 'completed'
                    ORDER BY completed_at DESC LIMIT 1
                """, conn, params=(symbol,))

                last_opt_time = None
                last_opt_sharpe = None

                if not df_last_opt.empty:
                    last_opt_time = df_last_opt['completed_at'].iloc[0]
                    last_opt_sharpe = df_last_opt['best_sharpe'].iloc[0]

                # Get current performance (last 30 days)
                thirty_days_ago = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
                df_current = pd.read_sql("""
                    SELECT AVG(sharpe_ratio) as current_sharpe, AVG(win_rate) as current_winrate
                    FROM SymbolPerformance
                    WHERE symbol = ? AND date >= ?
                """, conn, params=(symbol, thirty_days_ago))

                current_sharpe = 0
                current_winrate = 0

                if not df_current.empty:
                    current_sharpe = df_current['current_sharpe'].iloc[0] if pd.notna(df_current['current_sharpe'].iloc[0]) else 0
                    current_winrate = df_current['current_winrate'].iloc[0] if pd.notna(df_current['current_winrate'].iloc[0]) else 0

                # Calculate degradation
                degradation_pct = 0
                if last_opt_sharpe and last_opt_sharpe > 0:
                    degradation_pct = ((last_opt_sharpe - current_sharpe) / last_opt_sharpe * 100)

                # Calculate priority score
                days_since_opt = 0
                if last_opt_time:
                    days_since_opt = (datetime.now().timestamp() - last_opt_time) / 86400

                priority_score = (
                    (degradation_pct / 100) * 0.5 +                          # 50% weight on degradation
                    (max(0, 1 - current_sharpe) * 0.3) +                     # 30% on low Sharpe
                    (min(1.0, days_since_opt / 365) * 0.2)                   # 20% on staleness
                )

                # Determine if needs re-optimization
                needs_reopt = 0
                degradation_reason = None

                if degradation_pct > 30:
                    needs_reopt = 1
                    degradation_reason = f'Sharpe dropped {degradation_pct:.1f}%'
                elif current_sharpe < 0.5 and last_opt_sharpe:
                    needs_reopt = 1
                    degradation_reason = 'Low Sharpe ratio (< 0.5)'
                elif days_since_opt > 60:
                    needs_reopt = 1
                    degradation_reason = 'Stale parameters (>60 days)'

                # Next scheduled optimization
                next_scheduled = None
                if last_opt_time:
                    next_scheduled = last_opt_time + (30 * 86400)  # +30 days

                # Update or insert
                cursor.execute("""
                    INSERT OR REPLACE INTO OptimizationSchedule (
                        symbol, last_optimization_time, last_optimization_sharpe,
                        current_sharpe, current_winrate, degradation_pct,
                        next_scheduled_optimization, needs_reoptimization,
                        priority_score, degradation_reason, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    symbol, last_opt_time, last_opt_sharpe,
                    current_sharpe, current_winrate, degradation_pct,
                    next_scheduled, needs_reopt, priority_score,
                    degradation_reason, int(datetime.now().timestamp())
                ))

            conn.commit()
            print(f"✅ OptimizationSchedule updated for {len(symbols)} symbols")

        except Exception as e:
            print(f"❌ Error updating OptimizationSchedule: {e}")
            conn.rollback()
        finally:
            conn.close()

    def get_optimization_priorities(self, limit: int = 5) -> pd.DataFrame:
        """Get top symbols needing optimization"""
        conn = self.get_connection()

        try:
            df = pd.read_sql("""
                SELECT * FROM OptimizationSchedule
                ORDER BY priority_score DESC, needs_reoptimization DESC
                LIMIT ?
            """, conn, params=(limit,))

            return df

        finally:
            conn.close()

    # =========================================================================
    # ALERT MANAGEMENT
    # =========================================================================

    def get_active_alerts(self, severity: str = None) -> pd.DataFrame:
        """Get unacknowledged alerts"""
        conn = self.get_connection()

        try:
            query = """
                SELECT * FROM PerformanceAlerts
                WHERE acknowledged = 0 AND resolved = 0
            """

            if severity:
                query += f" AND severity = '{severity}'"

            query += " ORDER BY timestamp DESC"

            df = pd.read_sql(query, conn)
            return df

        finally:
            conn.close()

    def acknowledge_alert(self, alert_id: int):
        """Mark alert as acknowledged"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute("""
                UPDATE PerformanceAlerts
                SET acknowledged = 1
                WHERE id = ?
            """, (alert_id,))

            conn.commit()
            print(f"✅ Alert {alert_id} acknowledged")

        except Exception as e:
            print(f"❌ Error acknowledging alert: {e}")
            conn.rollback()
        finally:
            conn.close()

    def resolve_alert(self, alert_id: int):
        """Mark alert as resolved"""
        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute("""
                UPDATE PerformanceAlerts
                SET resolved = 1, resolved_at = ?
                WHERE id = ?
            """, (int(datetime.now().timestamp()), alert_id))

            conn.commit()
            print(f"✅ Alert {alert_id} resolved")

        except Exception as e:
            print(f"❌ Error resolving alert: {e}")
            conn.rollback()
        finally:
            conn.close()


if __name__ == "__main__":
    # Test the alerts system
    import os
    db_path = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")

    alerts = AlertsSystem(db_path)

    print("=" * 70)
    print("ALERTS SYSTEM - TEST RUN")
    print("=" * 70)

    # Update optimization schedule
    alerts.update_optimization_schedule()

    # Run all checks
    alerts.run_all_checks()

    # Show priorities
    print("\n📊 Top Optimization Priorities:")
    df_priorities = alerts.get_optimization_priorities(5)
    if not df_priorities.empty:
        print(df_priorities[['symbol', 'priority_score', 'degradation_reason', 'current_sharpe']])
    else:
        print("No optimization data available yet")

    # Show active alerts
    print("\n🔔 Active Alerts:")
    df_alerts = alerts.get_active_alerts()
    if not df_alerts.empty:
        print(df_alerts[['severity', 'title', 'message']])
    else:
        print("No active alerts")
