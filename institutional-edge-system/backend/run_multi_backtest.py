"""
Multi-Symbol Backtest Comparison
Compares EURUSD, XAUUSD, USDJPY, GBPUSD on H4
"""

import sys
from pathlib import Path
from datetime import datetime
import csv

sys.path.insert(0, str(Path(__file__).parent))

from app.backtesting.engine import BacktestEngine
from app.backtesting.models import BacktestConfig
from loguru import logger

# Symbols to test
SYMBOLS = ["EURUSD", "USDCAD", "USDJPY", "GBPUSD"]

def run_backtest_for_symbol(symbol: str) -> dict:
    """Run backtest for a single symbol and return results"""
    
    config = BacktestConfig(
        initial_balance=20.0,
        symbol=symbol,
        timeframe="H1",
        start_date=datetime(2022, 1, 1),
        end_date=datetime(2023, 12, 31),
        min_confluence_score=7,
        risk_percent=3.0,
        max_trades=3,
        swing_length=10,
        ob_lookback=50,
        fvg_min_size=0.3,
        vp_lookback=100,
        slippage_pips=1.0,
        scalping_mode=False,
    )
    
    engine = BacktestEngine(config)
    
    try:
        results = engine.run()
        
        # Generate report files
        report_name = f"backtest_{symbol}_{config.timeframe}"
        engine.generate_report(results, report_name=report_name)
        
        return results
    except Exception as e:
        logger.error(f"Error running {symbol}: {e}")
        return None


def main():
    print("=" * 70)
    print("  COMPARATIVA MULTI-SYMBOL - H1 SWING - 2 AÑOS (2022-2023)")
    print("  Capital: $20 | Riesgo: 3% | Mode: SWING")
    print("=" * 70)
    print()
    
    all_results = {}
    
    for symbol in SYMBOLS:
        print(f"⏳ Procesando {symbol}...")
        results = run_backtest_for_symbol(symbol)
        
        if results:
            all_results[symbol] = results
            
            # Read trades from CSV
            trades_file = f"reports/backtest_{symbol}_H1_trades.csv"
            try:
                with open(trades_file, 'r') as f:
                    trades = list(csv.DictReader(f))
                    wins = len([t for t in trades if float(t['pnl']) > 0])
                    total = len(trades)
                    wr = wins/total*100 if total > 0 else 0
                    
                    gp = sum(float(t['pnl']) for t in trades if float(t['pnl']) > 0)
                    gl = abs(sum(float(t['pnl']) for t in trades if float(t['pnl']) < 0))
                    net = gp - gl
                    pf = gp/gl if gl > 0 else 0
                    
                    all_results[symbol]['win_rate'] = wr
                    all_results[symbol]['total_trades'] = total
                    all_results[symbol]['net_pnl'] = net
                    all_results[symbol]['profit_factor'] = pf
                    
                    print(f"   ✅ {symbol}: {total} trades, {wr:.0f}% WR, PF: {pf:.2f}")
            except:
                print(f"   ⚠️ {symbol}: No trades file")
        else:
            print(f"   ❌ {symbol}: Error")
    
    # Print comparison table
    print()
    print("=" * 70)
    print("  📊 TABLA COMPARATIVA")
    print("=" * 70)
    print(f"{'Symbol':<10} {'Trades':<8} {'Win Rate':<10} {'PF':<8} {'Net PnL':<12} {'%/Mes':<8}")
    print("-" * 70)
    
    for symbol in SYMBOLS:
        if symbol in all_results:
            r = all_results[symbol]
            if hasattr(r, 'metrics') and r.metrics.total_trades > 0:
                m = r.metrics
                monthly = m.net_profit / 10 / 24 * 100
                print(f"{symbol:<10} {m.total_trades:<8} {m.win_rate:.0f}%{'':<7} {m.profit_factor:.2f}{'':<5} ${m.net_profit:.2f}{'':<7} {monthly:.2f}%")
            elif 'total_trades' in r:
                monthly = r['net_pnl'] / 10 / 24 * 100
                print(f"{symbol:<10} {r['total_trades']:<8} {r['win_rate']:.0f}%{'':<7} {r['profit_factor']:.2f}{'':<5} ${r['net_pnl']:.2f}{'':<7} {monthly:.2f}%")
    
    print("=" * 70)
    
    # Best symbol  
    best_pnl = 0
    best_symbol = ""
    for symbol in SYMBOLS:
        if symbol in all_results:
            r = all_results[symbol]
            if hasattr(r, 'metrics'):
                if r.metrics.net_profit > best_pnl:
                    best_pnl = r.metrics.net_profit
                    best_symbol = symbol
    
    print(f"\n🏆 MEJOR SÍMBOLO: {best_symbol} con ${best_pnl:.2f} de ganancia")


if __name__ == "__main__":
    main()
