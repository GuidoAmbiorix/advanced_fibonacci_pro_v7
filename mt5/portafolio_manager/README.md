# Portfolio Manager System

## 🧠 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    PORTFOLIO GOVERNOR                           │
│  • Runs on ONE chart only                                       │
│  • Monitors all positions across symbols                        │
│  • Tracks: DD, Exposure, Rolling PF, Correlation Groups         │
│  • Publishes risk multiplier via GlobalVariables                │
└─────────────────────────────────────────────────────────────────┘
                            ▲ ▼
           ┌────────────────┼────────────────┐
           │                │                │
   ┌───────▼───────┐ ┌──────▼──────┐ ┌───────▼───────┐
   │ XAUUSD Engine │ │ NAS100 Engine│ │ GBPJPY Engine │
   │ Magic: 100001 │ │ Magic: 100002│ │ Magic: 100003 │
   │ Asks Governor │ │ Asks Governor│ │ Asks Governor │
   └───────────────┘ └──────────────┘ └───────────────┘
```

## 📁 Files

| File                           | Purpose                                    |
| ------------------------------ | ------------------------------------------ |
| `Portfolio_Governor.mq5`       | Central brain - run on ONE chart           |
| `Symbol_Engine.mq5`            | Per-symbol EA - run on each trading symbol |
| `Include/PortfolioGlobals.mqh` | Shared definitions and communication bus   |

## 🚀 How to Use

### Step 1: Start the Governor

1. Open ANY chart (e.g., EURUSD M5)
2. Attach `Portfolio_Governor.mq5`
3. Configure portfolio limits
4. Dashboard will show "ACTIVE"

### Step 2: Start Symbol Engines

1. Open chart for each symbol you want to trade (e.g., XAUUSD M15)
2. Attach `Symbol_Engine.mq5`
3. **IMPORTANT**: Use unique Magic Number for each symbol:
   - XAUUSD: 100001
   - NAS100: 100002
   - GBPJPY: 100003
   - etc.
4. Each engine will connect to Governor

### Step 3: Monitor

- Governor dashboard shows total exposure, DD, rolling PF
- Each Symbol Engine shows its confluence scores
- Trading automatically pauses if DD > threshold or PF < 1.0

## ⚙️ Governor Settings

| Setting            | Default | Description                    |
| ------------------ | ------- | ------------------------------ |
| Max Portfolio Risk | 2.0%    | Total exposure limit           |
| Max Symbol Risk    | 0.6%    | Per-symbol limit               |
| Max Group Risk     | 1.0%    | Per-correlation-group limit    |
| DD Pause Level     | 8.0%    | Stop trading if exceeded       |
| PF Pause Level     | 1.0     | Stop if rolling PF drops below |

## 🔗 Correlation Groups

Symbols are automatically grouped to prevent over-exposure:

| Group   | Symbols                              |
| ------- | ------------------------------------ |
| USD     | EURUSD, GBPUSD, USDJPY, XAUUSD, etc. |
| JPY     | USDJPY, GBPJPY, EURJPY, etc.         |
| GBP     | GBPUSD, GBPJPY, EURGBP, etc.         |
| Metals  | XAUUSD, XAGUSD                       |
| Indices | NAS100, US30, SP500, DAX             |

## 📊 How Risk Scaling Works

```
Symbol Engine wants 0.25% risk
     ↓
Governor checks:
  • DD = 4% → Risk multiplier = 0.75
  • Total exposure = 1.5%
  • Group exposure = 0.4%
     ↓
Governor approves: 0.25% × 0.75 = 0.1875%
     ↓
Symbol Engine opens trade with 0.1875% risk
```

## 🎯 Key Benefits

1. **Lower DD** - Correlation awareness prevents stacked losses
2. **Higher PF** - Risk scales based on market fit
3. **Automatic Safety** - Trading pauses on drawdown
4. **Scalable** - Add more symbols without code changes
