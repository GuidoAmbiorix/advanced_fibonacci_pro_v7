import pandas as pd
import glob
import os

def analyze_csv(file_path):
    try:
        df = pd.read_csv(file_path)
        if df.empty:
            return None
        
        total_trades = len(df)
        wins = len(df[df['pnl'] > 0])
        win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
        
        gross_profit = df[df['pnl'] > 0]['pnl'].sum()
        gross_loss = abs(df[df['pnl'] < 0]['pnl'].sum())
        net_profit = gross_profit - gross_loss
        profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else 0
        
        return {
            'Symbol': os.path.basename(file_path).split('_')[1],
            'Trades': total_trades,
            'Win Rate': win_rate,
            'PF': profit_factor,
            'Net PnL': net_profit
        }
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return None

print(f"{'Symbol':<10} {'Trades':<8} {'Win Rate':<10} {'PF':<8} {'Net PnL':<12}")
print("-" * 60)

files = glob.glob("reports/backtest_*_M15_trades.csv")
for f in files:
    res = analyze_csv(f)
    if res:
        print(f"{res['Symbol']:<10} {res['Trades']:<8} {res['Win Rate']:.1f}%{'':<5} {res['PF']:.2f}{'':<4} ${res['Net PnL']:.2f}")
