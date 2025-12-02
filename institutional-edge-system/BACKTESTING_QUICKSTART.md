# 🚀 BACKTESTING QUICK START GUIDE

## Prerequisites

### 1. Install Dependencies
```bash
cd backend
pip install -r requirements.txt
```

Key packages for backtesting:
- `matplotlib>=3.7.0` - Chart generation
- `numpy>=1.24.0` - Numerical computations
- `scipy>=1.10.0` - Statistical analysis
- `pandas==2.1.4` - Data manipulation
- `MetaTrader5==5.0.5430` - Data source

---

## 🏃 Running Your First Backtest

### Option 1: Quick Test (Recommended for First Run)

```bash
cd backend
python run_backtest.py
```

This will:
- Load **EURUSD H1** data from **2021-2023** (3 years)
- Run strategy with **confluence score ≥ 7** (conservative)
- Risk **1%** per trade, max **1 trade** at a time
- Apply **1 pip slippage** + **$7/lot commission** (realistic)
- Generate comprehensive reports in `backend/reports/`

### Option 2: Custom Configuration

Edit `run_backtest.py` and modify the config:

```python
config = BacktestConfig(
    # Account
    initial_balance=10000.0,      # Starting capital

    # Symbol & Timeframe
    symbol="EURUSD",              # Change to GBPUSD, XAUUSD, etc.
    timeframe="H1",               # H1, H4, D1

    # Date range
    start_date=datetime(2021, 1, 1),
    end_date=datetime(2023, 12, 31),

    # Strategy
    min_confluence_score=7,       # 6-9 (higher = fewer, better signals)
    risk_percent=1.0,             # 0.5-2.0% recommended
    max_trades=1,                 # 1-3 concurrent positions

    # Realism
    slippage_pips=1.0,            # Market spread + slippage
    commission_per_lot=7.0,       # Broker commission roundtrip
)
```

---

## 📊 Understanding the Output

### Console Output

```
============================================================================
INSTITUTIONAL EDGE PRO - BACKTEST
============================================================================
Loading data: 2021-01-01 to 2023-12-31
Backtesting on 15,642 bars
Starting backtest...
Processed 1000/15642 bars...
...
Calculating performance metrics...

📊 BACKTEST SUMMARY
--------------------------------------------------------------------
Total Trades:     127
Win Rate:         52.76%
Profit Factor:    2.34
Net Profit:       $3,245.67
Max Drawdown:     8.23%
Avg R:R:          2.87
Expectancy:       $25.56
Sharpe Ratio:     1.89
--------------------------------------------------------------------
VERDICT: ✅ PASS

================================================================
✅ STRATEGY VALIDATED - Ready for demo trading
================================================================
```

### Report Files Generated

In `backend/reports/`:

1. **`backtest_EURUSD_H1_equity.png`**
   - Equity curve over time
   - Green triangles = wins
   - Red triangles = losses
   - Shows growth trajectory

2. **`backtest_EURUSD_H1_distribution.png`**
   - Left: P&L histogram (distribution of wins/losses)
   - Right: Cumulative P&L per trade

3. **`backtest_EURUSD_H1_monthly.png`**
   - Monthly returns bar chart
   - Green bars = profitable months
   - Red bars = losing months

4. **`backtest_EURUSD_H1_drawdown.png`**
   - Drawdown % over time
   - Shows when equity was below peak

5. **`backtest_EURUSD_H1_summary.txt`**
   - Complete text summary with all metrics
   - Configuration used
   - Verdict (PASS/FAIL)

6. **`backtest_EURUSD_H1_trades.csv`**
   - Detailed trade log
   - Entry/exit times, prices, P&L, R multiples
   - Import into Excel for analysis

---

## ✅ Strategy Validation Criteria

Your strategy **PASSES** if ALL criteria are met:

| Metric | Minimum | Why It Matters |
|--------|---------|----------------|
| **Total Trades** | ≥ 50 | Statistical significance |
| **Win Rate** | ≥ 45% | Enough winners to be profitable |
| **Profit Factor** | ≥ 1.5 | Make $1.50 for every $1 lost |
| **Max Drawdown** | < 15% | Manageable risk |
| **Avg R:R** | ≥ 2.0 | Winners bigger than losers |
| **Expectancy** | > 0 | Positive edge |

**If ANY criteria fails → Do NOT trade live!**

---

## 🔧 Optimization Workflow

### Step 1: Baseline Test (Current)
Run with default settings (confluence = 7, risk = 1%)

### Step 2: Parameter Sweep

Test different confluence scores:
```python
for score in [6, 7, 8, 9]:
    config.min_confluence_score = score
    results = engine.run()
    # Compare metrics
```

### Step 3: Timeframe Analysis

Test H1, H4, D1 to find best fit:
```python
for tf in ["H1", "H4", "D1"]:
    config.timeframe = tf
    results = engine.run()
```

### Step 4: Out-of-Sample Validation

After finding best parameters on 2021-2023:
```python
# Test on unseen 2024 data
config.start_date = datetime(2024, 1, 1)
config.end_date = datetime(2024, 11, 1)
results = engine.run()
# Results should be similar to in-sample
```

---

## 🚨 Common Issues & Solutions

### Issue 1: "Failed to load data"

**Cause**: MT5 not running or not logged in

**Solution**:
1. Open MetaTrader 5
2. Login to your account
3. Make sure symbol (EURUSD) is in Market Watch
4. Run backtest again

**Alternative**: Use CSV data source
```python
# In data_loader.py
data = self.load_from_csv('data/EURUSD_H1_2021_2023.csv')
```

### Issue 2: "ModuleNotFoundError: No module named 'matplotlib'"

**Cause**: Dependencies not installed

**Solution**:
```bash
pip install matplotlib numpy scipy
```

### Issue 3: "No trades executed"

**Possible causes**:
- Confluence score too high (try 6 instead of 7)
- Not enough historical data (need 100+ bars for indicators)
- Strategy not generating signals

**Debug**:
```python
# Add logging in engine.py
logger.info(f"Signals found: {len(analysis.get('signals', []))}")
```

### Issue 4: Very Poor Results (Win Rate < 30%)

**This is GOOD information!** It means:
- Strategy needs improvement before live trading
- Saved you from losing real money
- Time to analyze why signals are failing

**Next steps**:
1. Review trade log CSV
2. Check which patterns are losing most
3. Adjust confluence scoring
4. Consider different timeframe

---

## 📈 Next Steps After PASS

1. **Run multiple backtests**:
   - Different symbols (GBPUSD, XAUUSD)
   - Different timeframes (H4, D1)
   - Different years (2019-2020, 2022-2023)

2. **Monte Carlo simulation** (future feature):
   - Randomize trade order
   - Test robustness
   - Estimate probability of future performance

3. **Walk-forward analysis** (future feature):
   - Optimize on 6 months → test on next 2 months
   - Repeat rolling window
   - More realistic than single backtest

4. **Demo trading** (if backtest PASSES):
   - 6-8 weeks on demo account
   - Must achieve similar metrics to backtest
   - Then consider live with small capital

---

## 🎯 Performance Benchmarks

### Excellent Strategy
- Win Rate: 50-60%
- Profit Factor: 2.5+
- Max DD: < 10%
- Sharpe: > 2.0

### Good Strategy
- Win Rate: 45-55%
- Profit Factor: 1.8-2.5
- Max DD: 10-15%
- Sharpe: 1.5-2.0

### Marginal Strategy (needs work)
- Win Rate: 40-45%
- Profit Factor: 1.5-1.8
- Max DD: 15-20%
- Sharpe: 1.0-1.5

### Poor Strategy (DO NOT TRADE)
- Win Rate: < 40%
- Profit Factor: < 1.5
- Max DD: > 20%
- Sharpe: < 1.0

---

## 💡 Pro Tips

1. **Start Conservative**:
   - Use confluence ≥ 7 first
   - Risk 0.5% while learning
   - Max 1 trade at a time

2. **Trust the Data**:
   - If backtest fails, strategy needs work
   - Don't curve-fit to make it pass
   - Realistic slippage/commission is essential

3. **Out-of-Sample is King**:
   - In-sample results can be misleading
   - Always validate on fresh data
   - 2024 data is your true test

4. **Drawdown Matters More Than Profit**:
   - Can you psychologically handle a 12% drawdown?
   - Can your account survive it?
   - Lower DD = sustainable trading

5. **Compare to Buy & Hold**:
   - If EURUSD went up 5% in 3 years
   - Your strategy should beat that significantly
   - Otherwise, why trade actively?

---

## 📞 Support

If you encounter issues:
1. Check logs in `backend/logs/backtest_*.log`
2. Review this guide's troubleshooting section
3. Examine the generated CSV trade log for patterns

---

**Ready to validate your strategy? Run:**
```bash
python run_backtest.py
```

**Good luck! 📊✨**
