# Python Portfolio Trading Engine

A professional-grade Python portfolio management system with:

- **Multi-symbol support** (XAUUSD, NAS100, GBPJPY, etc.)
- **Confluence Ladder** trading strategy
- **Portfolio Governor** for centralized risk management
- **TradingView-style charts** via lightweight-charts-python
- **MT5 Bridge** for live trading execution

```
┌──────────────────────────────────────────────────────────────┐
│                     PYTHON CORE                              │
│  (Single Source of Truth - Same Logic for Backtest & Live)   │
│                                                              │
│  • Symbol Agents (Confluence Ladder logic)                   │
│  • Portfolio Governor (DD, PF, Correlation, Risk)            │
│  • Backtest Engine                                           │
│  • Visualization (lightweight-charts-python)                 │
└─────────────────────────▲─────────────────▲──────────────────┘
                          │                 │
               ┌──────────┴──────┐   ┌──────┴──────┐
               │   MT5 Bridge    │   │   CSV/DB    │
               │   (Execution)   │   │   (Data)    │
               └─────────────────┘   └─────────────┘
```

## 🚀 Quick Start

### 1. Install Dependencies

```bash
cd portfolio_engine
pip install -r requirements.txt
```

### 2. Run Backtest

```bash
# Single symbol
python run_backtest.py --symbol XAUUSD

# Full portfolio
python run_backtest.py --portfolio
```

### 3. Launch Dashboard

```bash
# Chart demo
python run_dashboard.py --demo

# Full dashboard
python run_dashboard.py --symbols XAUUSD NAS100
```

## 📁 Project Structure

```
portfolio_engine/
│
├── config/
│   ├── symbols.yaml      # Symbol configurations
│   ├── portfolio.yaml    # Portfolio limits
│   └── risk.yaml         # Risk parameters
│
├── data/
│   └── historical/       # CSV data files
│
├── indicators/
│   ├── fibonacci.py      # Fib zones & swings
│   ├── rsi.py            # RSI calculation
│   ├── ema.py            # EMA with slope
│   └── atr.py            # ATR & chop filter
│
├── symbols/
│   ├── base_agent.py     # Confluence Ladder base
│   ├── xauusd_agent.py   # Gold agent
│   ├── nas100_agent.py   # NASDAQ agent
│   └── gbpjpy_agent.py   # GBP/JPY agent
│
├── portfolio/
│   ├── governor.py       # Portfolio governor
│   ├── metrics.py        # PF, DD, Sharpe
│   ├── correlation.py    # Group management
│   └── exposure.py       # Position tracking
│
├── engine/
│   ├── backtest_engine.py  # Bar-by-bar simulation
│   └── event_bus.py        # Event system
│
├── visualization/
│   ├── chart_manager.py   # lightweight-charts wrapper
│   └── dashboard.py       # Multi-symbol dashboard
│
├── execution/
│   ├── mt5_bridge.py     # MT5 API wrapper
│   └── order_mapper.py   # Signal → Order
│
├── run_backtest.py       # Backtest entry point
└── run_dashboard.py      # Dashboard entry point
```

## ⚙️ Configuration

### symbols.yaml - Symbol Settings

```yaml
symbols:
  XAUUSD:
    timeframe: M15
    swing_lookback: 20
    fib_level_low: 0.618
    fib_level_high: 0.786
    rsi_oversold: 45
    rsi_overbought: 55
    ema_period: 200
    session_filter: LONDON_NY
```

### portfolio.yaml - Risk Limits

```yaml
portfolio:
  max_total_exposure: 2.0%
  max_symbol_exposure: 0.6%
  max_group_exposure: 1.0%

drawdown:
  normal: 3.0% # Normal trading
  reduced: 5.0% # 50% risk
  pause: 8.0% # Stop trading
```

## 🧠 Confluence Ladder System

Entry requires **4+ confluence points** out of 6:

1. ✅ **Trend aligned** - Price > EMA + EMA rising
2. ✅ **Structure valid** - Proper swing order
3. ✅ **Golden zone** - 61.8-78.6% retracement
4. ✅ **RSI confirmation** - Oversold/overbought
5. ✅ **RSI momentum** - Rising/falling
6. ✅ **Displacement** - Recent impulse candle

### Add-on Logic

| Condition                | Action                 |
| ------------------------ | ---------------------- |
| Entry                    | Score ≥ 4, Risk: 0.25% |
| +1.5R profit + Score ≥ 4 | Add-on #1, Risk: 0.15% |
| +2.5R profit + Score ≥ 5 | Add-on #2, Risk: 0.10% |

## 📊 Portfolio Governor

The Governor controls all trading decisions:

```
Symbol Engine: "Can I trade 0.25% risk?"
     ↓
Governor checks: DD=4%, PF=1.8, Group=0.5%
     ↓
Governor: "Approved at 0.19% (scaled by 0.75)"
     ↓
Trade opens with reduced risk
```

### Risk Multipliers

| Condition | Multiplier  |
| --------- | ----------- |
| DD < 3%   | 100%        |
| DD 3-5%   | 75-50%      |
| DD > 8%   | 0% (paused) |
| PF < 1.0  | 0% (paused) |
| PF < 1.2  | 40%         |
| PF > 2.5  | 110%        |

## 📈 Visualization

Built on [lightweight-charts-python](https://lightweight-charts-python.readthedocs.io/):

- Interactive TradingView-style charts
- Trade markers (entries/exits)
- Fibonacci levels
- RSI subchart
- Multi-symbol dashboard
- Real-time updates

## 🔗 MT5 Integration

For live trading, the MT5 bridge provides:

```python
from execution.mt5_bridge import MT5Bridge

bridge = MT5Bridge(magic_number=100001)
bridge.connect()

# Get account info
info = bridge.get_account_info()

# Place order
success, ticket, msg = bridge.place_order(
    symbol='XAUUSD',
    order_type=OrderType.BUY,
    volume=0.01,
    sl=1950.00,
    tp=2050.00
)
```

## 📝 License

MIT License - Use freely for personal and commercial projects.
