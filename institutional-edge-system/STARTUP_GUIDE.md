# 🚀 INSTITUTIONAL EDGE PRO - Startup Guide

## Quick Start

Simply run:
```bash
start_all.bat
```

You'll see a menu with 4 options:

---

## Menu Options

### Option 1: Backtest Only ✅ **RECOMMENDED FIRST**

**Use this when:**
- You want to validate the strategy before trading
- Testing new parameters (confluence score, risk %, timeframe)
- Analyzing historical performance

**What it does:**
- Opens a separate window
- Runs `python run_backtest.py`
- Generates reports in `backend/reports/`
- Shows performance metrics in console

**After completion:**
- Check console for verdict (✅ PASS or ❌ FAIL)
- Review charts in `backend/reports/`
- Read `backtest_EURUSD_H1_summary.txt`
- Analyze `backtest_EURUSD_H1_trades.csv`

**Next step:** If PASS → proceed to Option 2 for live trading

---

### Option 2: Live Trading System 📊

**Use this when:**
- Your backtest passed validation
- Ready for demo or live trading
- Need the full web interface

**What it starts:**
1. **Infrastructure** (Docker containers)
   - PostgreSQL database
   - Redis cache
   - RabbitMQ message queue
   - PgAdmin interface

2. **Backend API** (Python FastAPI)
   - REST API on http://localhost:8000
   - Swagger docs at http://localhost:8000/docs
   - Trading engine
   - Risk manager

3. **Frontend UI** (Vue.js)
   - Web interface at http://localhost:5173
   - Dashboard
   - Charts
   - Trade management

4. **Trade Worker** (Background service)
   - Monitors markets
   - Executes signals
   - Manages positions

**Access points:**
- 🌐 **Frontend**: http://localhost:5173
- 📘 **API Docs**: http://localhost:8000/docs
- 🐰 **RabbitMQ**: http://localhost:15672 (guest/guest)
- 🗄️ **PgAdmin**: http://localhost:5050

---

### Option 3: Full Suite (Backtest + Live Trading) 🔥

**Use this when:**
- You want to see both backtest results AND start live system
- Comparing historical vs real-time performance
- Development/testing workflow

**What it does:**
1. First: Opens backtest window
2. Waits 10 seconds
3. Then: Starts all live trading services

**Important:**
- Backtest runs in separate window (check it!)
- Live system starts while backtest is running
- You can compare results side-by-side

**Workflow:**
1. Wait for backtest to finish
2. Review results in `backend/reports/`
3. If PASS → use the live system that's already running
4. If FAIL → close live system windows and fix strategy

---

### Option 4: Exit

Safely exits without starting anything.

---

## Recommended Workflow

### First Time Setup:

```
1. Run start_all.bat
2. Choose Option 1 (Backtest Only)
3. Wait for completion (~2-10 minutes depending on data)
4. Review results
5. If PASS ✅:
   - Run start_all.bat again
   - Choose Option 2 (Live Trading)
   - Start demo trading
6. If FAIL ❌:
   - Review trade log CSV
   - Adjust parameters in run_backtest.py
   - Try Option 1 again
```

### Daily Usage (After Validation):

```
1. Run start_all.bat
2. Choose Option 2 (Live Trading)
3. Access web UI at http://localhost:5173
```

### Development/Testing:

```
1. Run start_all.bat
2. Choose Option 3 (Full Suite)
3. Monitor both backtest and live performance
```

---

## Configuration

### Backtest Settings

Edit `backend/run_backtest.py`:

```python
config = BacktestConfig(
    # Change these:
    symbol="EURUSD",              # GBPUSD, XAUUSD, etc.
    timeframe="H1",               # H1, H4, D1
    start_date=datetime(2021, 1, 1),
    end_date=datetime(2023, 12, 31),
    min_confluence_score=7,       # 6-9 (higher = stricter)
    risk_percent=1.0,             # 0.5-2.0%
)
```

### Live Trading Settings

Edit `backend/.env`:
```
MT5_LOGIN=your_account
MT5_PASSWORD=your_password
MT5_SERVER=your_broker
RISK_PERCENT=1.0
MIN_CONFLUENCE_SCORE=7
```

---

## Windows Layout

### Option 1 (Backtest Only):
```
┌─────────────────────────┐
│   Main Menu (closes)    │
└─────────────────────────┘

┌─────────────────────────┐
│  Backtest Window        │
│  (shows progress)       │
└─────────────────────────┘
```

### Option 2 (Live Trading):
```
┌─────────────────────────┐
│   Main Menu (paused)    │
└─────────────────────────┘

┌──────────┬──────────┬──────────┬──────────┐
│ Backend  │ Frontend │  Worker  │ Browser  │
│   API    │   Dev    │  Service │    UI    │
└──────────┴──────────┴──────────┴──────────┘
```

### Option 3 (Full Suite):
```
┌─────────────────────────┐
│   Main Menu (paused)    │
└─────────────────────────┘

┌─────────────────────────┐
│  Backtest Window        │
└─────────────────────────┘

┌──────────┬──────────┬──────────┬──────────┐
│ Backend  │ Frontend │  Worker  │ Browser  │
│   API    │   Dev    │  Service │    UI    │
└──────────┴──────────┴──────────┴──────────┘
```

---

## Troubleshooting

### Backtest window closes immediately
**Cause**: Python error or missing dependencies

**Fix**:
```bash
cd backend
pip install -r requirements.txt
python run_backtest.py  # Run manually to see error
```

### "Port already in use" errors
**Cause**: Previous session still running

**Fix**:
```bash
# Stop all containers
docker-compose down

# Kill Python processes
taskkill /F /IM python.exe

# Kill Node processes
taskkill /F /IM node.exe

# Try again
start_all.bat
```

### Frontend won't load
**Cause**: npm dependencies not installed

**Fix**:
```bash
cd frontend
npm install
cd ..
start_all.bat
```

### Database connection errors
**Cause**: Docker not running or containers not started

**Fix**:
1. Start Docker Desktop
2. Wait for it to fully start
3. Run `start_all.bat` → Option 2

### MT5 "Not connected" error
**Cause**: MetaTrader 5 not running or not logged in

**Fix**:
1. Open MetaTrader 5
2. Login to your account
3. Ensure auto-login is enabled
4. Try again

---

## Performance Tips

### Fast Backtest:
- Use shorter date range (1 year instead of 3)
- Use higher timeframe (H4 instead of H1)
- Reduce lookback windows in config

### Optimal Live Trading:
- Close unnecessary browser tabs
- Keep only essential windows open
- Monitor system resources (Task Manager)

---

## Files Generated

### Backtest Reports (after Option 1 or 3):
```
backend/reports/
├── backtest_EURUSD_H1_equity.png        (equity curve chart)
├── backtest_EURUSD_H1_distribution.png  (P&L histogram)
├── backtest_EURUSD_H1_monthly.png       (monthly returns)
├── backtest_EURUSD_H1_drawdown.png      (drawdown chart)
├── backtest_EURUSD_H1_summary.txt       (text summary)
└── backtest_EURUSD_H1_trades.csv        (detailed trade log)
```

### Logs:
```
backend/logs/
├── backtest_2024_12_02_14_30.log  (backtest logs)
├── trading_bot.log                 (live trading logs)
└── api.log                         (API logs)
```

---

## Quick Commands Reference

| Task | Command |
|------|---------|
| Start system | `start_all.bat` |
| Backtest only | Choose Option 1 |
| Live trading | Choose Option 2 |
| Full suite | Choose Option 3 |
| Stop Docker | `docker-compose down` |
| View logs | `backend/logs/` |
| View reports | `backend/reports/` |
| API docs | http://localhost:8000/docs |
| Frontend | http://localhost:5173 |

---

## Success Checklist

Before live trading, ensure:

- [ ] Backtest shows ✅ PASS verdict
- [ ] Win rate ≥ 45%
- [ ] Profit factor ≥ 1.5
- [ ] Max drawdown < 15%
- [ ] Average R:R ≥ 2.0
- [ ] At least 50+ trades in backtest
- [ ] Reviewed all charts in reports/
- [ ] Understand the strategy logic
- [ ] MT5 connected and logged in
- [ ] Using demo account first (6-8 weeks)

---

**Ready to start? Run `start_all.bat` and choose your option!** 🚀
