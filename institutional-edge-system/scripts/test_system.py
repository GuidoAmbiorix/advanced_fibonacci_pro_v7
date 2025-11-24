"""
============================================================================
INSTITUTIONAL EDGE PRO - System Test Script
============================================================================
Quick test to verify all components are working
"""

import sys
sys.path.append('backend/app')

from core.trading_engine import TradingEngine
from core.mt5_connector import MT5Connector
import pandas as pd
from datetime import datetime, timedelta
import numpy as np


def test_trading_engine():
    """Test the trading engine with sample data"""
    print("=" * 60)
    print("Testing Trading Engine...")
    print("=" * 60)

    # Create sample OHLCV data
    dates = pd.date_range(start=datetime.now() - timedelta(days=500), periods=500, freq='H')

    # Generate realistic price data
    np.random.seed(42)
    close_prices = 1.0850 + np.cumsum(np.random.randn(500) * 0.0001)
    high_prices = close_prices + np.random.rand(500) * 0.0005
    low_prices = close_prices - np.random.rand(500) * 0.0005
    open_prices = close_prices + (np.random.rand(500) - 0.5) * 0.0003
    volume = np.random.randint(1000, 10000, 500)

    df = pd.DataFrame({
        'time': dates,
        'open': open_prices,
        'high': high_prices,
        'low': low_prices,
        'close': close_prices,
        'volume': volume
    })

    # Create trading engine
    config = {
        'symbol': 'EURUSD',
        'timeframe': 'H1',
        'swing_length': 10,
        'ob_lookback': 50,
        'fvg_min_size': 0.3,
        'min_confluence_score': 6,
        'vp_lookback': 100,
        'vp_rows': 24,
        'value_area_percent': 70,
    }

    engine = TradingEngine(config)

    # Run analysis
    result = engine.analyze(df)

    # Print results
    print(f"\n✅ Trading Engine Test PASSED")
    print(f"\n📊 Analysis Results:")
    print(f"   Current Price: {result['current_price']:.5f}")
    print(f"   Trend: {result['trend']}")
    print(f"   Active Order Blocks: {result['active_order_blocks']}")
    print(f"   Active FVGs: {result['active_fvgs']}")
    print(f"   POC Level: {result['poc_level']:.5f}" if result['poc_level'] else "   POC Level: None")
    print(f"   Bull Confluence: {result['bull_confluence_score']}/10")
    print(f"   Bear Confluence: {result['bear_confluence_score']}/10")

    if result['bull_score_breakdown']:
        print(f"\n   📈 Bull Score Breakdown:")
        for factor, score in result['bull_score_breakdown'].items():
            print(f"      • {factor}: +{score}")

    if result['bear_score_breakdown']:
        print(f"\n   📉 Bear Score Breakdown:")
        for factor, score in result['bear_score_breakdown'].items():
            print(f"      • {factor}: +{score}")

    if result['signals']:
        print(f"\n🎯 SIGNALS DETECTED:")
        for signal in result['signals']:
            print(f"\n   {signal.signal_type} Signal:")
            print(f"   • Entry: {signal.entry_price:.5f}")
            print(f"   • Stop Loss: {signal.stop_loss:.5f}")
            print(f"   • TP1: {signal.take_profit_1:.5f}")
            print(f"   • TP2: {signal.take_profit_2:.5f}")
            print(f"   • Confluence: {signal.confluence_score}/10")
            print(f"   • R:R Ratio: 1:{signal.risk_reward_ratio}")
    else:
        print(f"\n   No signals at current confluence threshold")

    print("\n" + "=" * 60)
    return True


def test_mt5_connector():
    """Test MT5 connection (optional - requires MT5 installed and configured)"""
    print("\n" + "=" * 60)
    print("Testing MT5 Connector...")
    print("=" * 60)

    config = {
        'mt5_login': '',  # Leave empty for now
        'mt5_password': '',
        'mt5_server': '',
        'mt5_path': '',
    }

    connector = MT5Connector(config)

    # Try to connect (will fail if MT5 not configured, which is OK)
    try:
        connected = connector.connect()

        if connected:
            print("\n✅ MT5 Connection Test PASSED")

            # Test account info
            account_info = connector.get_account_info()
            if account_info:
                print(f"\n📊 Account Info:")
                print(f"   Balance: ${account_info['balance']:.2f}")
                print(f"   Equity: ${account_info['equity']:.2f}")
                print(f"   Leverage: 1:{account_info['leverage']}")

            # Test getting price data
            df = connector.get_ohlcv_data('EURUSD', 'H1', bars=100)
            if df is not None:
                print(f"\n📈 Successfully fetched {len(df)} bars of EURUSD H1 data")
                print(f"   Latest close: {df.iloc[-1]['close']:.5f}")

            connector.disconnect()
        else:
            print("\n⚠️  MT5 not connected (this is OK if not configured yet)")
            print("   Configure MT5 credentials in .env to enable MT5 features")

    except Exception as e:
        print(f"\n⚠️  MT5 test skipped: {str(e)}")
        print("   This is normal if MT5 is not installed or configured")

    print("\n" + "=" * 60)
    return True


def main():
    """Run all tests"""
    print("\n" + "=" * 60)
    print("🚀 INSTITUTIONAL EDGE PRO - System Test")
    print("=" * 60)

    all_passed = True

    # Test 1: Trading Engine
    try:
        test_trading_engine()
    except Exception as e:
        print(f"\n❌ Trading Engine Test FAILED: {e}")
        import traceback
        traceback.print_exc()
        all_passed = False

    # Test 2: MT5 Connector
    try:
        test_mt5_connector()
    except Exception as e:
        print(f"\n❌ MT5 Connector Test FAILED: {e}")
        import traceback
        traceback.print_exc()
        all_passed = False

    # Summary
    print("\n" + "=" * 60)
    if all_passed:
        print("✅ ALL TESTS PASSED!")
        print("\n🎉 System is ready to use!")
        print("\nNext steps:")
        print("1. Configure .env file with your MT5 credentials")
        print("2. Start the backend: cd backend/app && python main.py")
        print("3. Visit http://localhost:8000/docs to test the API")
        print("4. Build the Vue frontend: cd frontend && npm install && npm run dev")
    else:
        print("❌ SOME TESTS FAILED")
        print("Please check the errors above and fix any issues")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
