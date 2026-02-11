"""
Check portfolio configuration and allocations.
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

sys.path.append(str(Path(__file__).parent))
from src.database import DatabaseManager

load_dotenv()

def main():
    db = DatabaseManager()

    print("=== Portfolio Configuration Check ===\n")

    # Check active portfolio config
    active_portfolio_id = db.get_config('active_portfolio_id')
    print(f"Active portfolio ID: {active_portfolio_id}")

    if not active_portfolio_id:
        print("\n❌ No active portfolio set!")
        print("   Go to Trading Control page and select a portfolio")
    else:
        print(f"\n✓ Active portfolio: {active_portfolio_id}")

        # Get portfolio details
        portfolio = db.get_portfolio(int(active_portfolio_id))
        if portfolio:
            print(f"  Name: {portfolio['name']}")
            print(f"  Capital: ${portfolio['current_capital']:.2f}")

            # Check allocations
            allocations = db.get_allocations(int(active_portfolio_id))
            print(f"\n  Allocations: {len(allocations)}")

            if not allocations:
                print("  ❌ No allocations found!")
                print("     Go to Portfolios page and add symbol allocations")
            else:
                print("  ✓ Allocations configured:")
                for alloc in allocations:
                    print(f"    - {alloc['symbol']}: {alloc['weight']*100:.1f}% (Strategy: {alloc.get('strategy_name', 'N/A')})")
        else:
            print(f"\n  ❌ Portfolio ID {active_portfolio_id} not found!")

    # Check recent predictions
    print("\n" + "="*50)
    print("Recent Predictions:\n")

    with db.get_connection() as conn:
        cursor = conn.execute("""
            SELECT symbol, prediction_direction, confidence, timestamp
            FROM predictions
            ORDER BY timestamp DESC
            LIMIT 5
        """)
        predictions = cursor.fetchall()

        if predictions:
            for p in predictions:
                print(f"  {p['symbol']} {p['prediction_direction']} {p['confidence']:.1%} at {p['timestamp']}")
        else:
            print("  No predictions found")

    # Check signal confirmations
    print("\n" + "="*50)
    print("Signal Confirmations:\n")

    with db.get_connection() as conn:
        cursor = conn.execute("""
            SELECT COUNT(*) as cnt FROM signal_confirmations
        """)
        count = cursor.fetchone()['cnt']
        print(f"  Total signals: {count}")

        if count > 0:
            cursor = conn.execute("""
                SELECT symbol, status, created_at
                FROM signal_confirmations
                ORDER BY created_at DESC
                LIMIT 5
            """)
            signals = cursor.fetchall()
            print("\n  Recent signals:")
            for s in signals:
                print(f"    {s['symbol']} - {s['status']} at {s['created_at']}")

    db.close()

if __name__ == '__main__':
    main()
