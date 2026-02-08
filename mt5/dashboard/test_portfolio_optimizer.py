#!/usr/bin/env python3
"""
Test script for Portfolio-Level Optimizer

Run this to test the new portfolio optimization approach.
"""

import sys
import logging
from database_manager import DatabaseManager
from portfolio_optimizer import PortfolioLevelOptimizer
from optimizer_config_v2 import (
    FROZEN_PARAMS,
    TUNABLE_PARAMS,
    FORBIDDEN_PARAMS,
    get_param_info
)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)


def test_parameter_classification():
    """Test the 3-tier parameter classification."""
    print("\n" + "="*70)
    print("PARAMETER CLASSIFICATION TEST")
    print("="*70)

    info = get_param_info()

    print(f"\n📊 Parameter Summary:")
    print(f"   Frozen (architecture):    {info['frozen_count']:3d} params")
    print(f"   Tunable (optimization):   {info['tunable_count']:3d} params")
    print(f"   Forbidden (fixed logic):  {info['forbidden_count']:3d} params")
    print(f"   TOTAL:                    {info['total_count']:3d} params")

    print(f"\n🔒 Frozen Parameters (Strategy Architecture):")
    for key, value in list(FROZEN_PARAMS.items())[:10]:
        print(f"   {key:30s} = {value}")
    if len(FROZEN_PARAMS) > 10:
        print(f"   ... and {len(FROZEN_PARAMS) - 10} more")

    print(f"\n🎯 Tunable Parameters (Will Be Optimized):")
    for key, config in TUNABLE_PARAMS.items():
        print(f"   {key:30s} : {config['low']:6} to {config['high']:6} (step={config.get('step', 'auto')})")

    print(f"\n🚫 Forbidden Parameters (Fixed Defaults):")
    for key, value in list(FORBIDDEN_PARAMS.items())[:10]:
        print(f"   {key:30s} = {value}")
    if len(FORBIDDEN_PARAMS) > 10:
        print(f"   ... and {len(FORBIDDEN_PARAMS) - 10} more")

    print("\n" + "="*70)
    print("✅ Parameter classification test PASSED")
    print("="*70)


def test_quick_optimization():
    """Run a quick portfolio optimization (5 trials for testing)."""
    print("\n" + "="*70)
    print("QUICK PORTFOLIO OPTIMIZATION TEST")
    print("="*70)

    # Initialize
    db = DatabaseManager()
    optimizer = PortfolioLevelOptimizer(db, timeframe=15)

    # Override symbols for quick test (use just 3 symbols)
    optimizer.symbols = ['EURUSD', 'GBPUSD', 'USDJPY']
    print(f"\nTest symbols: {optimizer.symbols}")

    # Run optimization with just 5 trials (quick test)
    print("\nRunning 5 trial optimization (quick test)...")
    results = optimizer.run_portfolio_optimization(n_trials=5)

    # Display results
    print("\n" + "="*70)
    print("RESULTS")
    print("="*70)
    print(f"\nBest Portfolio Sharpe: {results['portfolio_metrics']['portfolio_sharpe']:.3f}")
    print(f"Avg Correlation:       {results['portfolio_metrics']['avg_correlation']:.3f}")
    print(f"Diversification Ratio: {results['portfolio_metrics']['diversification_ratio']:.3f}")
    print(f"Worst Symbol Sharpe:   {results['portfolio_metrics']['worst_symbol_sharpe']:.3f}")
    print(f"Optimization Time:     {results['elapsed_time']:.1f}s")

    print(f"\n📊 Individual Symbol Performance:")
    for symbol, result in results['symbol_results'].items():
        print(f"   {symbol}: Sharpe={result['sharpe']:.3f}, Trades={result['n_trades']}")

    print(f"\n🎯 Optimized Parameters (Tunable Only):")
    for key in TUNABLE_PARAMS.keys():
        if key in results['best_params']:
            print(f"   {key:30s} = {results['best_params'][key]}")

    print("\n" + "="*70)
    print("✅ Quick optimization test PASSED")
    print("="*70)

    return results


def test_full_optimization():
    """Run full portfolio optimization (100 trials on all symbols)."""
    print("\n" + "="*70)
    print("FULL PORTFOLIO OPTIMIZATION")
    print("="*70)
    print("\n⚠️  This will take 10-30 minutes depending on your hardware.")

    response = input("\nProceed with full optimization? (yes/no): ").strip().lower()
    if response != 'yes':
        print("Skipping full optimization.")
        return None

    # Initialize
    db = DatabaseManager()
    optimizer = PortfolioLevelOptimizer(db, timeframe=15)

    print(f"\nOptimizing {len(optimizer.symbols)} symbols:")
    print(f"   {', '.join(optimizer.symbols)}")

    # Run full optimization
    results = optimizer.run_portfolio_optimization(n_trials=100)

    # Save results
    print("\nSaving results to database...")
    save_success = optimizer.save_portfolio_results(results)

    if save_success:
        print("✅ All symbols saved to database successfully!")
    else:
        print("⚠️  Some symbols failed to save. Check logs above.")

    return results


def main():
    """Main test function."""
    print("\n" + "="*70)
    print("PORTFOLIO-LEVEL OPTIMIZER TEST SUITE")
    print("="*70)

    # Test 1: Parameter classification
    test_parameter_classification()

    # Test 2: Quick optimization
    input("\nPress Enter to run quick optimization test (5 trials)...")
    quick_results = test_quick_optimization()

    # Test 3: Full optimization (optional)
    input("\nPress Enter to continue to full optimization option...")
    full_results = test_full_optimization()

    print("\n" + "="*70)
    print("ALL TESTS COMPLETE!")
    print("="*70)

    if full_results:
        print("\n🎉 Portfolio optimization complete and saved to database!")
        print("   You can now restart your MT5 EA to use the new parameters.")
    else:
        print("\n📝 Quick test complete. Run full optimization when ready.")

    print("\nNext steps:")
    print("  1. Review the optimized parameters above")
    print("  2. Check portfolio metrics (Sharpe, correlation, diversification)")
    print("  3. If satisfied, run full optimization and save to database")
    print("  4. Restart MT5 EA to apply new parameters")
    print("  5. Monitor live performance vs backtest expectations")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user.")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Test failed with error:")
        print(f"   {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
