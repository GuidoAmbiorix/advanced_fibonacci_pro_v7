"""
Run Backtest
Entry point for running portfolio backtests.
"""

import sys
import os
from datetime import datetime, timedelta
from pathlib import Path
import pandas as pd
import yaml

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from symbols.xauusd_agent import XAUUSDAgent
from symbols.nas100_agent import NAS100Agent
from symbols.gbpjpy_agent import GBPJPYAgent
from portfolio.governor import PortfolioGovernor
from engine.backtest_engine import BacktestEngine, BacktestConfig


def load_symbol_config(symbol: str) -> dict:
    """Load symbol configuration from YAML."""
    try:
        with open('config/symbols.yaml', 'r') as f:
            config = yaml.safe_load(f)
            return config.get('symbols', {}).get(symbol, {})
    except FileNotFoundError:
        print(f"Warning: symbols.yaml not found, using defaults for {symbol}")
        return {}


def load_sample_data(symbol: str, timeframe: str = 'M15') -> pd.DataFrame:
    """Load historical data from CSV."""
    data_path = Path(f'data/historical/{symbol}_{timeframe}.csv')
    
    if data_path.exists():
        df = pd.read_csv(data_path, parse_dates=['time'])
        df = df.set_index('time')
        return df
    
    # Generate sample data if not found
    print(f"No data found for {symbol}, generating sample data...")
    return generate_sample_data(symbol, 5000)


def generate_sample_data(symbol: str, bars: int = 5000) -> pd.DataFrame:
    """Generate sample OHLCV data for testing."""
    import numpy as np
    
    # Base prices for different symbols
    base_prices = {
        'XAUUSD': 2000.0,
        'NAS100': 18000.0,
        'GBPJPY': 190.0,
    }
    
    base = base_prices.get(symbol, 1.1000)
    volatility = base * 0.001  # 0.1% volatility
    
    # Generate random walk
    np.random.seed(42)
    
    dates = pd.date_range(
        end=datetime.now(),
        periods=bars,
        freq='15min'
    )
    
    returns = np.random.normal(0.0001, 0.002, bars)
    prices = base * np.cumprod(1 + returns)
    
    # Generate OHLCV
    df = pd.DataFrame({
        'open': prices,
        'high': prices * (1 + np.random.uniform(0, 0.005, bars)),
        'low': prices * (1 - np.random.uniform(0, 0.005, bars)),
        'close': prices * (1 + np.random.normal(0, 0.002, bars)),
        'volume': np.random.randint(1000, 100000, bars),
    }, index=dates)
    
    df.index.name = 'time'
    
    return df


def run_single_symbol_backtest(symbol: str = 'XAUUSD'):
    """Run backtest on a single symbol."""
    print(f"\n{'='*60}")
    print(f"  🧪 SINGLE SYMBOL BACKTEST: {symbol}")
    print(f"{'='*60}\n")
    
    # Load config
    config = load_symbol_config(symbol)
    
    # Create agent
    agent_classes = {
        'XAUUSD': XAUUSDAgent,
        'NAS100': NAS100Agent,
        'GBPJPY': GBPJPYAgent,
    }
    
    agent_class = agent_classes.get(symbol, XAUUSDAgent)
    agent = agent_class(config)
    
    # Create governor
    governor = PortfolioGovernor('config/portfolio.yaml')
    
    # Load data
    df = load_sample_data(symbol)
    
    # Configure backtest
    bt_config = BacktestConfig(
        start_date=df.index[200],  # Skip first 200 bars for warmup
        end_date=df.index[-1],
        initial_equity=10000.0,
        spread_pips={symbol: 5},
    )
    
    # Create and run engine
    engine = BacktestEngine(
        agents={symbol: agent},
        governor=governor,
        config=bt_config,
    )
    
    engine.load_data(symbol, df)
    
    # Run backtest
    result = engine.run()
    
    # Print results
    print(result.summary())
    
    return result


def run_portfolio_backtest(symbols: list = ['XAUUSD', 'NAS100', 'GBPJPY']):
    """Run multi-symbol portfolio backtest."""
    print(f"\n{'='*60}")
    print(f"  📊 PORTFOLIO BACKTEST: {', '.join(symbols)}")
    print(f"{'='*60}\n")
    
    agent_classes = {
        'XAUUSD': XAUUSDAgent,
        'NAS100': NAS100Agent,
        'GBPJPY': GBPJPYAgent,
    }
    
    agents = {}
    all_data = {}
    
    # Create agents and load data
    for symbol in symbols:
        config = load_symbol_config(symbol)
        agent_class = agent_classes.get(symbol, XAUUSDAgent)
        agents[symbol] = agent_class(config)
        
        df = load_sample_data(symbol)
        all_data[symbol] = df
    
    # Find common date range
    start_dates = [df.index[200] for df in all_data.values()]
    end_dates = [df.index[-1] for df in all_data.values()]
    
    common_start = max(start_dates)
    common_end = min(end_dates)
    
    # Create governor
    governor = PortfolioGovernor('config/portfolio.yaml')
    
    # Configure backtest
    bt_config = BacktestConfig(
        start_date=common_start,
        end_date=common_end,
        initial_equity=10000.0,
        spread_pips={s: 5 for s in symbols},
    )
    
    # Create engine
    engine = BacktestEngine(
        agents=agents,
        governor=governor,
        config=bt_config,
    )
    
    # Load all data
    for symbol, df in all_data.items():
        engine.load_data(symbol, df)
    
    # Run backtest
    result = engine.run()
    
    # Print results
    print(result.summary())
    
    # Print per-symbol breakdown
    print("\n📈 PER-SYMBOL BREAKDOWN:")
    print("-" * 40)
    for symbol, trades in result.symbol_trades.items():
        wins = sum(1 for t in trades if t.profit > 0)
        total = len(trades)
        pnl = sum(t.profit for t in trades)
        print(f"  {symbol}: {total} trades, {wins/total*100 if total else 0:.0f}% win, ${pnl:+,.2f}")
    
    return result


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Portfolio Engine Backtest')
    parser.add_argument('--symbol', '-s', type=str, default=None,
                        help='Single symbol to backtest')
    parser.add_argument('--portfolio', '-p', action='store_true',
                        help='Run full portfolio backtest')
    parser.add_argument('--symbols', nargs='+', default=['XAUUSD', 'NAS100', 'GBPJPY'],
                        help='Symbols for portfolio backtest')
    
    args = parser.parse_args()
    
    if args.symbol:
        result = run_single_symbol_backtest(args.symbol)
    else:
        result = run_portfolio_backtest(args.symbols)
    
    # Visualize results if lightweight-charts available
    try:
        from visualization.chart_manager import plot_backtest_results
        
        print("\n📊 Opening chart visualization...")
        # Plot first symbol
        first_symbol = list(result.symbol_trades.keys())[0] if result.symbol_trades else None
        if first_symbol:
            from engine.backtest_engine import BacktestEngine
            # Visualization would go here
            
    except ImportError:
        print("\n💡 Install lightweight-charts for visual results:")
        print("   pip install lightweight-charts")


if __name__ == '__main__':
    main()
