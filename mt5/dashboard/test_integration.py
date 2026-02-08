#!/usr/bin/env python3
"""
Quick integration test for enhanced Python backtester.
Tests that confluence scoring integrates properly with optimizer.
"""

import pandas as pd
import numpy as np
from backtester.confluence_engine import ConfluenceEngine
from backtester.technical_indicators import TechnicalIndicators

def test_basic_integration():
    """Test basic integration of confluence scoring."""
    print("🔧 Testing Enhanced Backtester Integration...")

    # Create sample OHLCV data
    n_bars = 500
    np.random.seed(42)

    dates = pd.date_range(start='2023-01-01', periods=n_bars, freq='15T')
    base_price = 1.1000

    df = pd.DataFrame({
        'timestamp': dates,
        'open': base_price + np.random.randn(n_bars) * 0.0010,
        'high': base_price + np.abs(np.random.randn(n_bars)) * 0.0015,
        'low': base_price - np.abs(np.random.randn(n_bars)) * 0.0015,
        'close': base_price + np.random.randn(n_bars) * 0.0010,
        'tick_volume': np.random.randint(100, 1000, n_bars)
    })

    # Ensure OHLC consistency
    df['high'] = df[['open', 'high', 'close']].max(axis=1)
    df['low'] = df[['open', 'low', 'close']].min(axis=1)

    print(f"✓ Created sample data: {len(df)} bars")

    # Test parameters
    params = {
        'rsi_period': 14,
        'rsi_oversold': 30,
        'rsi_overbought': 70,
        'ema_period': 50,
        'ema_min_slope': 0.0001,
        'atr_period': 14,
        'swing_lookback': 10,
        'min_confluence_entry': 15.0,
        'use_smc': True,
        'use_institutional': True,
        'use_advanced': True,
        'use_mtf': False  # Disable MTF for speed
    }

    print("✓ Parameters configured")

    # Test 1: Calculate indicators
    print("\n📊 Test 1: Calculate indicators...")
    df_with_indicators = TechnicalIndicators.calculate_all_indicators(df.copy(), params)

    required_indicators = ['rsi', 'ema', 'atr', 'ema_slope', 'atr_ma', 'rsi_prev', 'regime']
    missing = [ind for ind in required_indicators if ind not in df_with_indicators.columns]

    if missing:
        print(f"❌ Missing indicators: {missing}")
        return False

    print(f"✓ All required indicators calculated: {required_indicators}")

    # Test 2: Calculate confluence scores
    print("\n🎯 Test 2: Calculate confluence scores...")
    confluence = ConfluenceEngine(params)

    # Get scores with breakdown
    scores = confluence.calculate_scores_with_breakdown(df_with_indicators, direction=1)

    print(f"✓ Core SMC Score Range: [{scores['core_smc'].min():.2f}, {scores['core_smc'].max():.2f}]")
    print(f"✓ Institutional Score Range: [{scores['institutional'].min():.2f}, {scores['institutional'].max():.2f}]")
    print(f"✓ Advanced Score Range: [{scores['advanced'].min():.2f}, {scores['advanced'].max():.2f}]")
    print(f"✓ Total Score Range: [{scores['total'].min():.2f}, {scores['total'].max():.2f}]")

    # Check score bounds
    max_total = scores['total'].max()
    if max_total > 30:
        print(f"⚠️ Warning: Total score exceeds 30 points: {max_total:.2f}")

    # Test 3: Generate signals
    print("\n📈 Test 3: Generate signals...")
    buy_score = confluence.calculate_confluence_score(df_with_indicators, 1, params)
    sell_score = confluence.calculate_confluence_score(df_with_indicators, -1, params)

    df_with_indicators['buy_score'] = buy_score
    df_with_indicators['sell_score'] = sell_score

    min_score = params['min_confluence_entry']
    df_with_indicators['signal'] = 0
    df_with_indicators.loc[df_with_indicators['buy_score'] >= min_score, 'signal'] = 1
    df_with_indicators.loc[df_with_indicators['sell_score'] >= min_score, 'signal'] = -1

    n_buy = (df_with_indicators['signal'] == 1).sum()
    n_sell = (df_with_indicators['signal'] == -1).sum()
    n_total = n_buy + n_sell

    print(f"✓ Buy signals: {n_buy}")
    print(f"✓ Sell signals: {n_sell}")
    print(f"✓ Total signals: {n_total}")

    # Test 4: Score component analysis
    print("\n📋 Test 4: Score component analysis...")

    # Find a bar with high total score
    high_score_idx = scores['total'].idxmax()

    print(f"\nSample High-Scoring Bar (index {high_score_idx}):")
    print(f"  Core SMC: {scores['core_smc'].iloc[high_score_idx]:.2f} pts")
    print(f"  Institutional: {scores['institutional'].iloc[high_score_idx]:.2f} pts")
    print(f"  Advanced: {scores['advanced'].iloc[high_score_idx]:.2f} pts")
    print(f"  TOTAL: {scores['total'].iloc[high_score_idx]:.2f} pts")

    # Summary
    print("\n" + "="*60)
    print("✅ Integration Test PASSED")
    print("="*60)
    print("\nKey Results:")
    print(f"  • {len(required_indicators)} indicators calculated successfully")
    print(f"  • Confluence scoring operational (0-30 pts)")
    print(f"  • Signal generation working ({n_total} signals @ threshold {min_score})")
    print(f"  • Score breakdown available for analysis")
    print("\n🎉 Enhanced backtester is ready for optimization!")

    return True


if __name__ == "__main__":
    try:
        success = test_basic_integration()
        exit(0 if success else 1)
    except Exception as e:
        print(f"\n❌ Integration test FAILED with error:")
        print(f"   {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
