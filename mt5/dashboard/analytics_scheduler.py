"""
Analytics Scheduler - Automated Job Scheduling
===============================================
Schedules and runs analytics tasks at regular intervals:
- Daily analytics aggregation (midnight)
- Weekly analytics aggregation (Sunday)
- Hourly alert checks
- Drawdown tracking

Can run standalone or be integrated into the dashboard app.

Usage:
    # Standalone mode
    python analytics_scheduler.py

    # Integration mode
    from analytics_scheduler import AnalyticsScheduler
    scheduler = AnalyticsScheduler(db_path)
    scheduler.start()
"""

import os
import time
from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
import logging

from analytics_engine import AnalyticsEngine
from alerts_system import AlertsSystem


class AnalyticsScheduler:
    def __init__(self, db_path: str = None):
        """
        Initialize the analytics scheduler.

        Args:
            db_path: Path to database file (defaults to env var or local file)
        """
        if db_path is None:
            self.db_path = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")
        else:
            self.db_path = db_path

        self.engine = AnalyticsEngine(self.db_path)
        self.alerts = AlertsSystem(self.db_path)

        # Initialize scheduler
        self.scheduler = BackgroundScheduler()

        # Configure logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger('AnalyticsScheduler')

    def setup_jobs(self):
        """Configure all scheduled jobs"""

        # Daily Analytics - Run at midnight (00:00)
        self.scheduler.add_job(
            func=self.run_daily_analytics,
            trigger=CronTrigger(hour=0, minute=0),
            id='daily_analytics',
            name='Daily Analytics Aggregation',
            replace_existing=True
        )
        self.logger.info("Scheduled: Daily analytics at midnight")

        # Weekly Analytics - Run on Sunday at 01:00
        self.scheduler.add_job(
            func=self.run_weekly_analytics,
            trigger=CronTrigger(day_of_week='sun', hour=1, minute=0),
            id='weekly_analytics',
            name='Weekly Analytics Aggregation',
            replace_existing=True
        )
        self.logger.info("Scheduled: Weekly analytics on Sunday at 01:00")

        # Hourly Alert Checks - Run every hour
        self.scheduler.add_job(
            func=self.run_alert_checks,
            trigger=IntervalTrigger(hours=1),
            id='hourly_alerts',
            name='Hourly Alert Checks',
            replace_existing=True
        )
        self.logger.info("Scheduled: Alert checks every hour")

        # Drawdown Tracking - Run every 4 hours
        self.scheduler.add_job(
            func=self.run_drawdown_tracking,
            trigger=IntervalTrigger(hours=4),
            id='drawdown_tracking',
            name='Drawdown Tracking',
            replace_existing=True
        )
        self.logger.info("Scheduled: Drawdown tracking every 4 hours")

        # Correlation Matrix - Run daily at 02:00
        self.scheduler.add_job(
            func=self.run_correlation_analysis,
            trigger=CronTrigger(hour=2, minute=0),
            id='correlation_analysis',
            name='Daily Correlation Analysis',
            replace_existing=True
        )
        self.logger.info("Scheduled: Correlation analysis at 02:00")

        # Optimization Schedule Update - Run every 6 hours
        self.scheduler.add_job(
            func=self.update_optimization_schedule,
            trigger=IntervalTrigger(hours=6),
            id='optimization_schedule',
            name='Update Optimization Schedule',
            replace_existing=True
        )
        self.logger.info("Scheduled: Optimization schedule update every 6 hours")

    def run_daily_analytics(self):
        """Daily analytics aggregation job"""
        try:
            self.logger.info("=" * 70)
            self.logger.info("RUNNING DAILY ANALYTICS AGGREGATION")
            self.logger.info("=" * 70)

            # Run for yesterday (completed day)
            yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

            self.engine.run_daily_aggregation(yesterday)

            self.logger.info("Daily analytics completed successfully")

        except Exception as e:
            self.logger.error(f"Error in daily analytics job: {e}", exc_info=True)

    def run_weekly_analytics(self):
        """Weekly analytics aggregation job"""
        try:
            self.logger.info("=" * 70)
            self.logger.info("RUNNING WEEKLY ANALYTICS AGGREGATION")
            self.logger.info("=" * 70)

            # Run for last week
            last_week = (datetime.now() - timedelta(days=7)).strftime('%Y-W%U')

            self.engine.run_weekly_aggregation(last_week)

            self.logger.info("Weekly analytics completed successfully")

        except Exception as e:
            self.logger.error(f"Error in weekly analytics job: {e}", exc_info=True)

    def run_alert_checks(self):
        """Hourly alert monitoring job"""
        try:
            self.logger.info("Running alert checks...")

            self.alerts.run_all_checks()

            self.logger.info("Alert checks completed")

        except Exception as e:
            self.logger.error(f"Error in alert checks job: {e}", exc_info=True)

    def run_drawdown_tracking(self):
        """Drawdown tracking job"""
        try:
            self.logger.info("Running drawdown tracking...")

            self.engine.track_drawdowns()

            self.logger.info("Drawdown tracking completed")

        except Exception as e:
            self.logger.error(f"Error in drawdown tracking job: {e}", exc_info=True)

    def run_correlation_analysis(self):
        """Correlation matrix calculation job"""
        try:
            self.logger.info("Running correlation analysis...")

            self.engine.calculate_correlation_matrix(period_days=30)

            self.logger.info("Correlation analysis completed")

        except Exception as e:
            self.logger.error(f"Error in correlation analysis job: {e}", exc_info=True)

    def update_optimization_schedule(self):
        """Update optimization schedule and priority scores"""
        try:
            self.logger.info("Updating optimization schedule...")

            self.alerts.update_optimization_schedule()

            self.logger.info("Optimization schedule updated")

        except Exception as e:
            self.logger.error(f"Error updating optimization schedule: {e}", exc_info=True)

    def start(self, run_immediate: bool = False):
        """
        Start the scheduler.

        Args:
            run_immediate: If True, run all jobs once immediately before starting schedule
        """
        self.setup_jobs()

        if run_immediate:
            self.logger.info("Running immediate execution of all jobs...")
            self.run_daily_analytics()
            self.run_alert_checks()
            self.run_drawdown_tracking()
            self.run_correlation_analysis()
            self.update_optimization_schedule()

        self.scheduler.start()
        self.logger.info("Analytics scheduler started successfully")
        self.logger.info(f"Active jobs: {len(self.scheduler.get_jobs())}")

        # Print job schedule
        self.print_schedule()

    def stop(self):
        """Stop the scheduler"""
        self.scheduler.shutdown()
        self.logger.info("Analytics scheduler stopped")

    def print_schedule(self):
        """Print current job schedule"""
        self.logger.info("\nScheduled Jobs:")
        self.logger.info("-" * 70)

        for job in self.scheduler.get_jobs():
            next_run = job.next_run_time.strftime('%Y-%m-%d %H:%M:%S') if job.next_run_time else 'N/A'
            self.logger.info(f"{job.name:30} | Next run: {next_run}")

        self.logger.info("-" * 70)

    def run_job_now(self, job_id: str):
        """
        Manually trigger a specific job.

        Args:
            job_id: ID of the job to run
        """
        job = self.scheduler.get_job(job_id)

        if job:
            self.logger.info(f"Manually triggering job: {job.name}")
            job.func()
        else:
            self.logger.error(f"Job not found: {job_id}")

    def is_running(self) -> bool:
        """Check if scheduler is running"""
        return self.scheduler.running


# Standalone mode
if __name__ == "__main__":
    print("=" * 70)
    print("ANALYTICS SCHEDULER - STANDALONE MODE")
    print("=" * 70)

    # Initialize scheduler
    scheduler = AnalyticsScheduler()

    # Start with immediate execution
    scheduler.start(run_immediate=True)

    print("\nScheduler is running. Press Ctrl+C to stop.\n")

    try:
        # Keep alive
        while True:
            time.sleep(60)

            # Print status every 5 minutes
            if int(time.time()) % 300 == 0:
                print(f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Scheduler status: Running")
                print(f"Active jobs: {len(scheduler.scheduler.get_jobs())}")

    except (KeyboardInterrupt, SystemExit):
        print("\n\nShutting down scheduler...")
        scheduler.stop()
        print("Scheduler stopped. Goodbye!")
