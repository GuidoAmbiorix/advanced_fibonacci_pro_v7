
from app.backtesting.metrics import MetricsCalculator
from app.backtesting.models import BacktestTrade, BacktestMetrics
from datetime import datetime

# Mock Trades
trades = []

# Trade 1: Win $100
t1 = BacktestTrade(
    entry_time=datetime.now(),
    entry_price=1.1000,
    signal_type="BUY",
    volume=0.1,
    stop_loss=1.0900,
    take_profit=1.1100,
    status="CLOSED"
)
t1.pnl = 100.0
t1.exit_price = 1.1100
trades.append(t1)

# Trade 2: Win $150
t2 = BacktestTrade(
    entry_time=datetime.now(),
    entry_price=1.1000,
    signal_type="BUY",
    volume=0.1,
    stop_loss=1.0900,
    take_profit=1.1150,
    status="CLOSED"
)
t2.pnl = 150.0
t2.exit_price = 1.1150
trades.append(t2)

# Trade 3: Loss $50
t3 = BacktestTrade(
    entry_time=datetime.now(),
    entry_price=1.1000,
    signal_type="BUY",
    volume=0.1,
    stop_loss=1.0950,
    take_profit=1.1200,
    status="CLOSED"
)
t3.pnl = -50.0
t3.exit_price = 1.0950
trades.append(t3)

# Trade 4: Loss $60
t4 = BacktestTrade(
    entry_time=datetime.now(),
    entry_price=1.1000,
    signal_type="BUY",
    volume=0.1,
    stop_loss=1.0940,
    take_profit=1.1200,
    status="CLOSED"
)
t4.pnl = -60.0
t4.exit_price = 1.0940
trades.append(t4)

# Trade 5: Win $100
t5 = BacktestTrade(
    entry_time=datetime.now(),
    entry_price=1.1000,
    signal_type="BUY",
    volume=0.1,
    stop_loss=1.0900,
    take_profit=1.1100,
    status="CLOSED"
)
t5.pnl = 100.0
t5.exit_price = 1.1100
t5.exit_time = datetime.now()
trades.append(t5)


print("--- Running Metrics Calculation ---")
metrics = MetricsCalculator.calculate_all(trades, initial_balance=10000.0)

print(f"Total Trades: {metrics.total_trades}")
print(f"Win Rate: {metrics.win_rate}%")
print(f"Total Profit: {metrics.total_profit}")
print(f"Total Loss: {metrics.total_loss}")
print(f"Profit Factor: {metrics.profit_factor}")
print(f"Avg Win: {metrics.average_win}")
print(f"Avg Loss: {metrics.average_loss}")
print(f"Kelly Fraction: {metrics.kelly_fraction}")
print(f"Half Kelly: {metrics.half_kelly}")
print(f"Sharpe Ratio: {metrics.sharpe_ratio}")

# Verify Logic
# Wins: 100, 150, 100 = 350. Avg Win = 116.66
# Losses: -50, -60 = -110. Avg Loss = 55.0
# PF = 350 / 110 = 3.18
# Win Rate = 3/5 = 60%
# R Ratio = 116.66 / 55 = 2.12
# Kelly = 0.60 - (0.40 / 2.12) = 0.60 - 0.188 = 0.41 (41%)
