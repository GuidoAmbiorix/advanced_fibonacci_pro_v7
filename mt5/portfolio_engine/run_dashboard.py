"""
Run Dashboard
Entry point for launching the portfolio dashboard visualization.
"""

import sys
from pathlib import Path
import pandas as pd
import asyncio

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))


def run_static_dashboard(symbols: list = ['XAUUSD', 'NAS100']):
    """Run a static dashboard with sample data."""
    from visualization.dashboard import Dashboard
    from run_backtest import load_sample_data
    
    print(f"\n{'='*60}")
    print(f"  📊 PORTFOLIO DASHBOARD")
    print(f"  Symbols: {', '.join(symbols)}")
    print(f"{'='*60}\n")
    
    # Create dashboard
    dashboard = Dashboard(symbols, layout='2x1')
    
    # Load data for each symbol
    for symbol in symbols:
        df = load_sample_data(symbol)
        dashboard.set_symbol_data(symbol, df)
    
    # Update metrics with sample values
    dashboard.update_metrics(
        equity=10250.00,
        dd=2.5,
        pf=1.85,
        positions=3
    )
    
    print("🚀 Launching dashboard...")
    print("   Close the window to exit.\n")
    
    dashboard.show(block=True)


def run_chart_demo():
    """Run a simple chart demonstration."""
    from visualization.chart_manager import ChartManager
    from run_backtest import load_sample_data
    
    print(f"\n{'='*60}")
    print(f"  📈 CHART DEMO")
    print(f"{'='*60}\n")
    
    # Load sample data
    df = load_sample_data('XAUUSD')
    
    # Create chart
    cm = ChartManager(title="XAUUSD M15", toolbox=True)
    cm.set_data(df)
    
    # Add 200 EMA
    ema_200 = df['close'].ewm(span=200, adjust=False).mean()
    ema_df = pd.DataFrame({
        'time': df.index,
        'EMA 200': ema_200
    })
    cm.add_line('EMA 200', ema_df, color='#2962FF', width=2)
    
    # Add some sample Fibonacci levels
    recent_high = df['high'].rolling(20).max().iloc[-1]
    recent_low = df['low'].rolling(20).min().iloc[-1]
    
    cm.add_horizontal_line(recent_high, color='#4CAF50', label='Swing High')
    cm.add_horizontal_line(recent_low, color='#F44336', label='Swing Low')
    
    # Add golden zone
    swing_range = recent_high - recent_low
    fib_618 = recent_high - (swing_range * 0.618)
    fib_786 = recent_high - (swing_range * 0.786)
    
    cm.add_horizontal_line(fib_618, color='#FF9800', label='61.8%')
    cm.add_horizontal_line(fib_786, color='#FF5722', label='78.6%')
    
    # Add topbar info
    cm.add_topbar_text('symbol', 'XAUUSD')
    cm.add_topbar_text('tf', 'M15')
    
    print("🚀 Launching chart...")
    print("   Use drawing tools on the left")
    print("   Close the window to exit.\n")
    
    cm.show(block=True)


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Portfolio Dashboard')
    parser.add_argument('--demo', '-d', action='store_true',
                        help='Run chart demo')
    parser.add_argument('--symbols', nargs='+', default=['XAUUSD', 'NAS100'],
                        help='Symbols to display')
    
    args = parser.parse_args()
    
    try:
        if args.demo:
            run_chart_demo()
        else:
            run_static_dashboard(args.symbols)
            
    except ImportError as e:
        print(f"\n❌ Error: {e}")
        print("\n💡 Install required packages:")
        print("   pip install lightweight-charts pywebview")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        raise


if __name__ == '__main__':
    main()
