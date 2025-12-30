
from app.backtesting.metrics import MetricsCalculator
from app.backtesting.models import BacktestTrade
from datetime import datetime
import random
import statistics

# Goal: Replicate Sharpe 4.00 but Kelly 0.0
# Params from report: Best 292, Worst -175. Win Rate ~60%.

trades = []

# Generate 100 trades
# 60 wins, 40 losses
# Wins around $120 (Median $117)
# Losses around $-100?

for i in range(60):
    t = BacktestTrade(
        entry_time=datetime.now(),
        entry_price=1.1000,
        signal_type="BUY",
        volume=0.1,
        stop_loss=1.0900,
        take_profit=1.1100,
        status="CLOSED"
    )
    t.pnl = float(random.randint(100, 200)) # Avg ~150
    if i == 0: t.pnl = 292.0 # Best
    t.exit_time = datetime.now()
    trades.append(t)

for i in range(40):
    t = BacktestTrade(
        entry_time=datetime.now(),
        entry_price=1.1000,
        signal_type="BUY",
        volume=0.1,
        stop_loss=1.0900,
        take_profit=1.1100,
        status="CLOSED"
    )
    t.pnl = float(random.randint(-175, -50)) # Avg ~-110
    if i == 0: t.pnl = -175.0 # Worst
    t.exit_time = datetime.now()
    trades.append(t)

metrics = MetricsCalculator.calculate_all(trades, initial_balance=10000.0)

print(f"Total Trades: {metrics.total_trades}")
print(f"Win Rate: {metrics.win_rate:.2f}%")
print(f"Sharpe: {metrics.sharpe_ratio:.2f}")
print(f"Profit Factor: {metrics.profit_factor:.2f}")
print(f"Kelly: {metrics.kelly_fraction:.4f}")
print(f"Expectancy: {metrics.expectancy:.2f}")
print(f"Avg Win: {metrics.average_win:.2f}")
print(f"Avg Loss: {metrics.average_loss:.2f}")

if metrics.expectancy <= 0:
    print("WARNING: Expectancy is Negative!")
