#!/usr/bin/env python3
"""
Run Analytics - CLI Utility for Analytics Operations
=====================================================
Manually run analytics operations from the command line.

Usage Examples:
    # Backfill last 30 days of analytics
    python run_analytics.py backfill --days 30

    # Run daily analytics for yesterday
    python run_analytics.py daily

    # Run daily analytics for specific date
    python run_analytics.py daily --date 2026-02-07

    # Run weekly analytics
    python run_analytics.py weekly

    # Run alert checks
    python run_analytics.py alerts

    # Start scheduler (runs in background)
    python run_analytics.py schedule

    # Train ML model
    python run_analytics.py ml-train

    # Generate ML predictions
    python run_analytics.py ml-predict

    # Full pipeline (backfill + train + predict)
    python run_analytics.py full-pipeline --days 30

Commands:
    backfill       - Backfill historical analytics
    daily          - Run daily aggregation
    weekly         - Run weekly aggregation
    alerts         - Run alert checks
    schedule       - Start analytics scheduler
    ml-train       - Train ML prediction model
    ml-predict     - Generate ML predictions
    ml-evaluate    - Evaluate ML predictions
    full-pipeline  - Run complete analytics pipeline
"""

import argparse
import os
import sys
from datetime import datetime, timedelta

# Import analytics modules
from analytics_engine import AnalyticsEngine
from alerts_system import AlertsSystem
from analytics_scheduler import AnalyticsScheduler
from ml_predictor import MLPredictor


def get_db_path():
    """Get database path from environment or default"""
    return os.getenv("DB_PATH", "PortfolioGovernor.sqlite")


def cmd_backfill(args):
    """Backfill historical analytics"""
    print("=" * 70)
    print(f"BACKFILLING ANALYTICS - Last {args.days} days")
    print("=" * 70)

    engine = AnalyticsEngine(get_db_path())
    engine.backfill_analytics(days=args.days)

    print("\n✅ Backfill complete!")


def cmd_daily(args):
    """Run daily analytics aggregation"""
    print("=" * 70)
    print("RUNNING DAILY ANALYTICS")
    print("=" * 70)

    engine = AnalyticsEngine(get_db_path())

    if args.date:
        date = args.date
    else:
        # Yesterday by default
        date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

    engine.run_daily_aggregation(date)

    print(f"\n✅ Daily analytics complete for {date}!")


def cmd_weekly(args):
    """Run weekly analytics aggregation"""
    print("=" * 70)
    print("RUNNING WEEKLY ANALYTICS")
    print("=" * 70)

    engine = AnalyticsEngine(get_db_path())

    if args.week:
        week = args.week
    else:
        # Last week by default
        week = (datetime.now() - timedelta(days=7)).strftime('%Y-W%U')

    engine.run_weekly_aggregation(week)

    print(f"\n✅ Weekly analytics complete for {week}!")


def cmd_alerts(args):
    """Run alert checks"""
    print("=" * 70)
    print("RUNNING ALERT CHECKS")
    print("=" * 70)

    alerts = AlertsSystem(get_db_path())

    # Update optimization schedule first
    print("\n1️⃣ Updating optimization schedule...")
    alerts.update_optimization_schedule()

    # Run all alert checks
    print("\n2️⃣ Running alert checks...")
    alerts.run_all_checks()

    # Show active alerts
    print("\n3️⃣ Active Alerts:")
    print("-" * 70)

    df_alerts = alerts.get_active_alerts()

    if not df_alerts.empty:
        for _, alert in df_alerts.iterrows():
            severity_icon = {
                'INFO': 'ℹ️',
                'WARNING': '⚠️',
                'CRITICAL': '🔴'
            }.get(alert['severity'], '❓')

            print(f"{severity_icon} [{alert['severity']}] {alert['title']}")
            print(f"   {alert['message']}")
            if alert['suggested_action']:
                print(f"   → {alert['suggested_action']}")
            print()
    else:
        print("✅ No active alerts")

    # Show optimization priorities
    print("\n4️⃣ Optimization Priorities:")
    print("-" * 70)

    df_priorities = alerts.get_optimization_priorities(5)

    if not df_priorities.empty:
        for _, row in df_priorities.iterrows():
            print(f"{row['symbol']:10} | Priority: {row['priority_score']:.3f} | Sharpe: {row['current_sharpe']:.2f}")
            if row['degradation_reason']:
                print(f"           → {row['degradation_reason']}")
    else:
        print("No optimization data available")

    print("\n✅ Alert checks complete!")


def cmd_schedule(args):
    """Start analytics scheduler"""
    print("=" * 70)
    print("STARTING ANALYTICS SCHEDULER")
    print("=" * 70)

    scheduler = AnalyticsScheduler(get_db_path())

    # Start with immediate execution if requested
    scheduler.start(run_immediate=args.immediate)

    print("\n✅ Scheduler started!")
    print("Press Ctrl+C to stop.\n")

    try:
        import time
        while True:
            time.sleep(60)
    except (KeyboardInterrupt, SystemExit):
        print("\n\nStopping scheduler...")
        scheduler.stop()
        print("✅ Scheduler stopped. Goodbye!")


def cmd_ml_train(args):
    """Train ML prediction model"""
    print("=" * 70)
    print("TRAINING ML PREDICTION MODEL")
    print("=" * 70)

    predictor = MLPredictor(get_db_path())

    # Train model
    metrics = predictor.train_model(n_estimators=args.n_estimators)

    if metrics:
        # Save model
        if args.save:
            predictor.save_model(args.save)

        print("\n✅ ML training complete!")
    else:
        print("\n❌ ML training failed (insufficient data)")


def cmd_ml_predict(args):
    """Generate ML predictions"""
    print("=" * 70)
    print("GENERATING ML PREDICTIONS")
    print("=" * 70)

    predictor = MLPredictor(get_db_path())

    # Load model if specified
    if args.load:
        if not predictor.load_model(args.load):
            print("❌ Failed to load model. Train new model first.")
            return
    else:
        # Train new model
        print("\n1️⃣ Training model...")
        metrics = predictor.train_model(n_estimators=50)
        if not metrics:
            print("❌ Training failed")
            return

    # Generate predictions
    print("\n2️⃣ Generating predictions...")
    predictor.generate_predictions(date=args.date)

    print("\n✅ Predictions complete!")


def cmd_ml_evaluate(args):
    """Evaluate ML predictions"""
    print("=" * 70)
    print("EVALUATING ML PREDICTIONS")
    print("=" * 70)

    predictor = MLPredictor(get_db_path())

    # Evaluate predictions
    metrics = predictor.evaluate_predictions(date=args.date)

    if metrics:
        print("\n✅ Evaluation complete!")
    else:
        print("\n❌ No predictions to evaluate")


def cmd_full_pipeline(args):
    """Run complete analytics pipeline"""
    print("=" * 70)
    print("RUNNING FULL ANALYTICS PIPELINE")
    print("=" * 70)

    db_path = get_db_path()

    # Step 1: Backfill analytics
    print("\n📊 STEP 1: Backfilling Analytics")
    print("-" * 70)
    engine = AnalyticsEngine(db_path)
    engine.backfill_analytics(days=args.days)

    # Step 2: Run correlation analysis
    print("\n📊 STEP 2: Correlation Analysis")
    print("-" * 70)
    engine.calculate_correlation_matrix(period_days=30)

    # Step 3: Track drawdowns
    print("\n📊 STEP 3: Drawdown Tracking")
    print("-" * 70)
    engine.track_drawdowns()

    # Step 4: Update optimization schedule
    print("\n📊 STEP 4: Optimization Schedule")
    print("-" * 70)
    alerts = AlertsSystem(db_path)
    alerts.update_optimization_schedule()

    # Step 5: Run alert checks
    print("\n📊 STEP 5: Alert Checks")
    print("-" * 70)
    alerts.run_all_checks()

    # Step 6: Train ML model
    print("\n📊 STEP 6: ML Model Training")
    print("-" * 70)
    predictor = MLPredictor(db_path)
    metrics = predictor.train_model(n_estimators=100)

    # Step 7: Generate predictions
    if metrics:
        print("\n📊 STEP 7: Generate Predictions")
        print("-" * 70)
        predictor.generate_predictions()

        # Save model
        predictor.save_model("ml_model.pkl")

    print("\n" + "=" * 70)
    print("✅ FULL PIPELINE COMPLETE!")
    print("=" * 70)


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description="Analytics Operations CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    subparsers = parser.add_subparsers(dest='command', help='Command to run')

    # Backfill command
    parser_backfill = subparsers.add_parser('backfill', help='Backfill historical analytics')
    parser_backfill.add_argument('--days', type=int, default=30, help='Number of days to backfill (default: 30)')
    parser_backfill.set_defaults(func=cmd_backfill)

    # Daily command
    parser_daily = subparsers.add_parser('daily', help='Run daily analytics')
    parser_daily.add_argument('--date', type=str, help='Date in YYYY-MM-DD format (default: yesterday)')
    parser_daily.set_defaults(func=cmd_daily)

    # Weekly command
    parser_weekly = subparsers.add_parser('weekly', help='Run weekly analytics')
    parser_weekly.add_argument('--week', type=str, help='Week in YYYY-Www format (default: last week)')
    parser_weekly.set_defaults(func=cmd_weekly)

    # Alerts command
    parser_alerts = subparsers.add_parser('alerts', help='Run alert checks')
    parser_alerts.set_defaults(func=cmd_alerts)

    # Schedule command
    parser_schedule = subparsers.add_parser('schedule', help='Start analytics scheduler')
    parser_schedule.add_argument('--immediate', action='store_true', help='Run all jobs immediately on start')
    parser_schedule.set_defaults(func=cmd_schedule)

    # ML Train command
    parser_ml_train = subparsers.add_parser('ml-train', help='Train ML prediction model')
    parser_ml_train.add_argument('--n-estimators', type=int, default=100, help='Number of trees (default: 100)')
    parser_ml_train.add_argument('--save', type=str, default='ml_model.pkl', help='Save model to file')
    parser_ml_train.set_defaults(func=cmd_ml_train)

    # ML Predict command
    parser_ml_predict = subparsers.add_parser('ml-predict', help='Generate ML predictions')
    parser_ml_predict.add_argument('--date', type=str, help='Prediction date (default: tomorrow)')
    parser_ml_predict.add_argument('--load', type=str, help='Load model from file')
    parser_ml_predict.set_defaults(func=cmd_ml_predict)

    # ML Evaluate command
    parser_ml_evaluate = subparsers.add_parser('ml-evaluate', help='Evaluate ML predictions')
    parser_ml_evaluate.add_argument('--date', type=str, help='Date to evaluate (default: yesterday)')
    parser_ml_evaluate.set_defaults(func=cmd_ml_evaluate)

    # Full Pipeline command
    parser_full = subparsers.add_parser('full-pipeline', help='Run complete analytics pipeline')
    parser_full.add_argument('--days', type=int, default=30, help='Number of days to backfill (default: 30)')
    parser_full.set_defaults(func=cmd_full_pipeline)

    # Parse arguments
    args = parser.parse_args()

    # Show help if no command
    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Run command
    args.func(args)


if __name__ == "__main__":
    main()
