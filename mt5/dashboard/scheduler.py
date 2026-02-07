# Optimization Scheduler Module
# Background service to run optimizations on schedule

import schedule
import time
import threading
from datetime import datetime
from database_manager import DatabaseManager
from optimizer import PortfolioOptimizer

class OptimizationScheduler:
    """
    Background service to run optimizations on schedule.

    Modes:
    - Daily: Optimize at specific time each day
    - Weekly: Optimize on specific day/time each week
    - Monthly: First day of month
    - On-demand: Triggered by user
    """

    def __init__(self, db_path):
        self.db_manager = DatabaseManager(db_path)
        self.running = False
        self.thread = None
        self.last_run = None
        self.next_run = None

    def optimize_all_symbols(self):
        """Run bulk optimization for all configured symbols."""
        print(f"\n{'='*60}")
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Starting scheduled optimization...")
        print(f"{'='*60}\n")

        self.last_run = datetime.now()

        try:
            optimizer = PortfolioOptimizer(self.db_manager)

            # Load symbols
            configs = self.db_manager.load_configs()
            if configs.empty:
                print("⚠️ No symbols configured. Skipping optimization.")
                return

            symbols = configs['symbol'].tolist()
            print(f"📋 Found {len(symbols)} symbols to optimize")

            results = {
                'successful': 0,
                'failed': 0,
                'skipped': 0
            }

            for idx, symbol in enumerate(symbols, 1):
                print(f"\n[{idx}/{len(symbols)}] Optimizing {symbol}...")

                try:
                    # Backup current config before optimization
                    self.db_manager.backup_config(symbol, reason="scheduled_optimization")

                    # Run optimization with OOS validation
                    result = optimizer.run_optimization(symbol, enable_oos_test=True)

                    if result and result.get('best_params'):
                        # Update database
                        success, msg = optimizer.update_db(symbol, result['best_params'])

                        if success:
                            print(f"  ✅ {symbol}: Optimized successfully!")
                            print(f"     Train Sharpe: {result.get('train_sharpe', 'N/A'):.3f}")
                            print(f"     Test Sharpe: {result.get('test_sharpe', 'N/A'):.3f}")
                            print(f"     OOS Risk: {result.get('overfitting_risk', 'N/A')}")
                            results['successful'] += 1

                            # Log to database
                            self.db_manager.log_event(
                                "Scheduler",
                                "INFO",
                                f"Scheduled optimization completed for {symbol}"
                            )
                        else:
                            print(f"  ❌ {symbol}: Failed to save - {msg}")
                            results['failed'] += 1
                    else:
                        print(f"  ⚠️ {symbol}: No results produced")
                        results['skipped'] += 1

                except Exception as e:
                    print(f"  ❌ {symbol}: Error - {str(e)}")
                    results['failed'] += 1

                    # Log error
                    self.db_manager.log_event(
                        "Scheduler",
                        "ERROR",
                        f"Scheduled optimization failed for {symbol}: {str(e)}"
                    )

            print(f"\n{'='*60}")
            print(f"📊 Scheduled Optimization Complete")
            print(f"   ✅ Successful: {results['successful']}")
            print(f"   ❌ Failed: {results['failed']}")
            print(f"   ⚠️ Skipped: {results['skipped']}")
            print(f"{'='*60}\n")

            # Log summary
            self.db_manager.log_event(
                "Scheduler",
                "INFO",
                f"Bulk scheduled optimization complete: {results['successful']}/{len(symbols)} successful"
            )

        except Exception as e:
            print(f"❌ Scheduler error: {str(e)}")
            self.db_manager.log_event(
                "Scheduler",
                "ERROR",
                f"Scheduler error: {str(e)}"
            )

    def start_scheduler(self, schedule_type='daily', hour=2, minute=0, weekday='monday'):
        """
        Start background scheduler.

        Args:
            schedule_type: 'daily', 'weekly', 'monthly'
            hour: 0-23 (UTC)
            minute: 0-59
            weekday: 'monday', 'tuesday', etc. (for weekly mode)
        """
        if self.running:
            print("⚠️ Scheduler is already running!")
            return False

        # Clear any existing schedules
        schedule.clear()

        # Set up schedule based on type
        if schedule_type == 'daily':
            schedule.every().day.at(f"{hour:02d}:{minute:02d}").do(self.optimize_all_symbols)
            print(f"📅 Daily scheduler set for {hour:02d}:{minute:02d} UTC")

        elif schedule_type == 'weekly':
            weekday_method = getattr(schedule.every(), weekday.lower())
            weekday_method.at(f"{hour:02d}:{minute:02d}").do(self.optimize_all_symbols)
            print(f"📅 Weekly scheduler set for {weekday.capitalize()} at {hour:02d}:{minute:02d} UTC")

        elif schedule_type == 'monthly':
            # Check if it's first day of month every day
            def monthly_check():
                if datetime.now().day == 1:
                    self.optimize_all_symbols()

            schedule.every().day.at(f"{hour:02d}:{minute:02d}").do(monthly_check)
            print(f"📅 Monthly scheduler set for 1st of month at {hour:02d}:{minute:02d} UTC")

        else:
            print(f"❌ Invalid schedule type: {schedule_type}")
            return False

        # Calculate next run time
        next_job = schedule.next_run()
        self.next_run = next_job

        print(f"⏰ Next scheduled run: {next_job}")

        # Start background thread
        self.running = True

        def scheduler_loop():
            """Background loop that runs scheduled tasks."""
            print("🔄 Scheduler thread started")

            while self.running:
                schedule.run_pending()
                time.sleep(60)  # Check every minute

            print("🛑 Scheduler thread stopped")

        self.thread = threading.Thread(target=scheduler_loop, daemon=True)
        self.thread.start()

        # Log to database
        self.db_manager.log_event(
            "Scheduler",
            "INFO",
            f"Scheduler started: {schedule_type} at {hour:02d}:{minute:02d}"
        )

        return True

    def stop_scheduler(self):
        """Stop background scheduler."""
        if not self.running:
            print("⚠️ Scheduler is not running")
            return False

        print("🛑 Stopping scheduler...")
        self.running = False
        schedule.clear()

        # Wait for thread to finish (with timeout)
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=5)

        print("✅ Scheduler stopped")

        # Log to database
        self.db_manager.log_event(
            "Scheduler",
            "INFO",
            "Scheduler stopped"
        )

        return True

    def get_status(self):
        """Get current scheduler status."""
        return {
            'running': self.running,
            'last_run': self.last_run,
            'next_run': schedule.next_run() if self.running else None,
            'jobs_count': len(schedule.jobs)
        }

    def run_now(self):
        """Manually trigger optimization immediately."""
        if self.running:
            print("⚡ Running manual optimization...")
            self.optimize_all_symbols()
            return True
        else:
            print("⚠️ Scheduler must be started first")
            return False


# Singleton instance for the scheduler
_scheduler_instance = None

def get_scheduler(db_path):
    """Get or create scheduler instance."""
    global _scheduler_instance
    if _scheduler_instance is None:
        _scheduler_instance = OptimizationScheduler(db_path)
    return _scheduler_instance
