# ForTraders 3% Daily Drawdown Configuration

## 🚨 CRITICAL: Spread Configuration Issue

### The Problem

You reported that trading is blocked with "Spread too wide: 50 > 50 points" on your ForTraders server.

**This is a BROKER DIGIT FORMAT issue, not a spread problem!**

### Understanding the Issue

MT5 brokers use either:
- **5-digit pricing**: 10 points = 1 pip (most common)
- **3-digit pricing**: 1 point = 1 pip (older brokers)

The spread checking code in `Symbol_Engine.mq5:2267-2288` uses `symbolInfo.Spread()` which returns **points**, not pips.

### Diagnosis

**Run this diagnostic script to determine your broker format:**

```
Scripts/Spread_Diagnostics_ForTraders.mq5
```

This will tell you:
1. Whether ForTraders uses 5-digit or 3-digit pricing
2. The current spread in both points and pips
3. Recommended `InpMaxSpreadPoints` values for each pair

### The Fix

#### If ForTraders is 5-DIGIT (Most Likely):

Current setting `InpMaxSpreadPoints=50` = **5 pips** = NORMAL ✅

**Problem**: The spread IS actually 5 pips, which is too wide for EURUSD during normal hours.

**Solution**: Use the optimized settings provided:
- EURUSD: `InpMaxSpreadPoints=25` (2.5 pips)
- GBPUSD: `InpMaxSpreadPoints=35` (3.5 pips)
- USDJPY: `InpMaxSpreadPoints=25` (2.5 pips)
- GBPJPY: `InpMaxSpreadPoints=45` (4.5 pips)
- XAUUSD: `InpMaxSpreadPoints=250` (25 cents)

**Why it's blocking**: Your broker's spread is likely 5+ pips during:
- Asian session (low liquidity)
- News events
- Market open/close
- Weekend rollover

#### If ForTraders is 3-DIGIT (Unlikely):

Current setting `InpMaxSpreadPoints=50` = **50 pips** = TOO HIGH ❌

**Problem**: 50 pips is impossibly high - no trades will ever pass this filter.

**Solution**: Change to:
- EURUSD: `InpMaxSpreadPoints=3` (3 pips)
- GBPUSD: `InpMaxSpreadPoints=4` (4 pips)
- USDJPY: `InpMaxSpreadPoints=3` (3 pips)
- GBPJPY: `InpMaxSpreadPoints=5` (5 pips)
- XAUUSD: `InpMaxSpreadPoints=30` (30 cents)

---

## 📋 ForTraders Challenge Parameters

| Limit Type | Value | Safety Buffer |
|------------|-------|---------------|
| **Daily Drawdown** | 3.0% | Set to 2.9% |
| **Max Drawdown** | 5.0% | Set to 4.9% |
| **Monthly DD** | 10.0%* | Not applicable (5% max applies) |

*Monthly limit doesn't matter because 5% max drawdown would fail the challenge first.

---

## 🎯 Risk Configuration Strategy

### Individual Symbol Risk (InpRiskBase)

| Symbol | Risk/Trade | Reason |
|--------|-----------|---------|
| EURUSD | 0.35% | Balanced major, moderate volatility |
| GBPUSD | 0.30% | Reduced (more volatile than EURUSD) |
| USDJPY | 0.35% | Clean trending pair |
| GBPJPY | 0.25% | Most volatile, smallest size |
| XAUUSD | 0.30% | Large ATR swings, conservative |

### Why These Small Percentages?

**Math:**
- Daily limit: 2.9% (safety buffer below 3.0%)
- Pause level: 2.9% DD
- Normal → Reduced: 2.0% DD

**Worst Case Scenario:**
- Starting at 0% DD
- Take 8 consecutive losses at 0.35% each
- Total DD: 8 × 0.35% = 2.8%
- Still below 2.9% pause level ✅

**With Governor Scaling:**
- At 2.0% DD: Risk reduces to 0.35% × 0.50 = 0.175%
- Need 5 more losses to hit 2.9%: 2.0% + (5 × 0.175%) = 2.875%

### Portfolio Governor Settings

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `InpMaxPortfolioRisk` | 2.5% | Max total exposure across all symbols |
| `InpDD_Normal` | 2.0% | Start risk reduction early |
| `InpDD_Reduced` | 2.5% | Second tier reduction |
| `InpDD_Pause` | 2.9% | Emergency stop (0.1% before limit) |
| `InpDD_ReducedMult` | 0.50 | Cut risk in HALF when DD > 2.0% |

---

## 📊 Confluence Requirements

Higher confluence = Better quality signals = Higher win rate needed for tight DD limits

| Symbol | Confluence | Reason |
|--------|-----------|---------|
| EURUSD | 16 | Increased from 14 (ultra-high quality) |
| GBPUSD | 17 | Strict (volatile pair) |
| USDJPY | 16 | High quality required |
| GBPJPY | 18 | ULTRA STRICT (most volatile) |
| XAUUSD | 17 | Gold needs best signals only |

**Trade-off:**
- Higher confluence = Fewer trades
- But: Higher win rate per trade
- Result: Better suited for tight drawdown limits

---

## 🛡️ Safety Features

### 1. Drawdown Governor (Multi-Tier)

```
DD = 0-2.0%:    Normal trading (100% risk)
DD = 2.0-2.5%:  Reduced trading (50% risk)
DD = 2.5-2.9%:  Heavily reduced (50% risk)
DD ≥ 2.9%:      PAUSED (0% risk) ⛔
```

### 2. Per-Symbol Limits

```
InpDailyMaxLoss_R=2.0
```

**Example (EURUSD):**
- Base risk: 0.35%
- Max loss: 2R × 0.35% = 0.7%
- After 2R loss: 90-minute cooldown
- Prevents single pair from consuming DD budget

### 3. Correlation Guard

```
InpHighCorrelation=0.70
InpCorrelationReduction=0.50
```

**Example:**
- EURUSD position open (0.35% risk)
- GBPUSD signal appears
- Correlation = 0.75 (high)
- GBPUSD risk reduced: 0.30% × 0.50 = 0.15%
- Prevents double exposure to same EUR move

### 4. Max Daily Trades

```
InpMaxDailyTrades=5 per symbol
```

Max 25 trades/day across 5 symbols. Prevents overtrading.

---

## 🚀 Quick Start Guide

### Step 1: Run Diagnostic

1. Open MT5 on ForTraders server
2. Tools → MQL5 → Scripts
3. Run: `Spread_Diagnostics_ForTraders.mq5`
4. Check output - note if 5-digit or 3-digit broker

### Step 2: Choose Configuration Files

**If 5-digit broker (likely):**
Use the `_optimized.set` files as-is:
- `eurusd_optimized.set`
- `gbpusd_optimized.set`
- `usdjpy_optimized.set`
- `GBPJPY_optimized.set`
- `XAUUSD_optimized.set`
- `governor_ForTraders_3pct.set`

**If 3-digit broker (unlikely):**
Edit each `_optimized.set` file:
- EURUSD: Change `InpMaxSpreadPoints=25` to `InpMaxSpreadPoints=3`
- GBPUSD: Change `InpMaxSpreadPoints=35` to `InpMaxSpreadPoints=4`
- USDJPY: Change `InpMaxSpreadPoints=25` to `InpMaxSpreadPoints=3`
- GBPJPY: Change `InpMaxSpreadPoints=45` to `InpMaxSpreadPoints=5`
- XAUUSD: Change `InpMaxSpreadPoints=250` to `InpMaxSpreadPoints=30`

### Step 3: Load Configurations

1. **Portfolio_Governor.mq5**: Load `governor_ForTraders_3pct.set`
2. **Symbol_Engine.mq5** (EURUSD): Load `eurusd_optimized.set`
3. **Symbol_Engine.mq5** (GBPUSD): Load `gbpusd_optimized.set`
4. **Symbol_Engine.mq5** (USDJPY): Load `usdjpy_optimized.set`
5. **Symbol_Engine.mq5** (GBPJPY): Load `GBPJPY_optimized.set`
6. **Metals_Engine.mq5** (XAUUSD): Load `XAUUSD_optimized.set`

### Step 4: Monitor Spread

Watch the Expert Advisor logs:
```
⚠️ Spread too wide: 35 > 25 points
```

**If you see this:**
- It's WORKING CORRECTLY ✅
- Blocking trades when spread is too wide (3.5 pips)
- Wait for London/NY session when spreads tighten

**When spreads are normal (1.0-2.5 pips):**
- No spread warnings
- Trades will execute normally

---

## 📈 Expected Trading Behavior

### Normal Market Conditions

**Active Hours** (London Open 08:00-12:00 GMT, NY Open 13:00-17:00 GMT):
- EURUSD spread: 0.6-1.5 pips → Trades allowed ✅
- GBPUSD spread: 0.8-2.5 pips → Trades allowed ✅
- USDJPY spread: 0.6-1.5 pips → Trades allowed ✅
- GBPJPY spread: 1.5-3.5 pips → Trades allowed ✅
- XAUUSD spread: $0.15-$0.25 → Trades allowed ✅

**Quiet Hours** (Asian session, late NY):
- EURUSD spread: 2.0-5.0 pips → Often blocked ⛔
- GBPUSD spread: 3.0-6.0 pips → Often blocked ⛔
- USDJPY spread: May still trade (Asian pair)
- XAUUSD spread: $0.30-$0.50 → Often blocked ⛔

**This is GOOD - we only trade during prime liquidity!**

### Trade Frequency Estimates

**Per Symbol:**
- EURUSD: 1-2 trades/day
- GBPUSD: 1 trade/day (stricter confluence)
- USDJPY: 1-2 trades/day
- GBPJPY: 0-1 trade/day (ultra-strict confluence)
- XAUUSD: 1 trade/day

**Total Portfolio: 4-7 trades/day**

High confluence = Fewer trades, but higher quality

---

## ⚠️ Troubleshooting

### Issue: "Spread too wide" constantly

**Check:**
1. What time is it? (Asian session = normal for high spreads)
2. Run diagnostic script - verify spread is actually wide
3. Is there news in next 60 minutes? (News filter blocks trading)

**Solutions:**
- Wait for London/NY session
- If spread NEVER drops below limit → broker issue (contact ForTraders)

### Issue: No trades at all

**Check:**
1. Confluence too high? (Try reducing by 1-2 points temporarily)
2. Chop filter active? (Low volatility periods block trades)
3. Trend filter? (Must have trend for entries)
4. Drawdown governor paused? (Check if DD ≥ 2.9%)

### Issue: Hit 2.9% drawdown too quickly

**Check:**
1. Are all 5 symbols trading simultaneously? (Reduce active symbols)
2. Consecutive losses? (System should pause after 2 losses per symbol)
3. Governor working? (Check logs for "Risk scaled to X%")

**Solutions:**
- Reduce `InpRiskBase` by 0.05% across all symbols
- Increase confluence by 1 point
- Enable only 3 symbols (EURUSD, USDJPY, XAUUSD)

---

## 📁 File Summary

### Optimized Configuration Files

| File | Purpose | Key Changes |
|------|---------|-------------|
| `eurusd_optimized.set` | EURUSD H1 config | Risk 0.35%, Spread 25pts, Confluence 16 |
| `gbpusd_optimized.set` | GBPUSD H1 config | Risk 0.30%, Spread 35pts, Confluence 17 |
| `usdjpy_optimized.set` | USDJPY H1 config | Risk 0.35%, Spread 25pts, Confluence 16 |
| `GBPJPY_optimized.set` | GBPJPY H1 config | Risk 0.25%, Spread 45pts, Confluence 18 |
| `XAUUSD_optimized.set` | Gold H1 config | Risk 0.30%, Spread 250pts, Confluence 17 |
| `governor_ForTraders_3pct.set` | Portfolio manager | DD 2.9%, Portfolio Risk 2.5% |

### Diagnostic Tools

| File | Purpose |
|------|---------|
| `Spread_Diagnostics_ForTraders.mq5` | Determine broker digit format and optimal spreads |

---

## 🎓 Key Concepts

### Why Small Risk Per Trade?

**ForTraders Challenge Math:**
```
Daily Limit: 3.0%
Safety Buffer: -0.1% (pause at 2.9%)
Usable DD: 2.9%

If Risk = 0.35%:
  Max consecutive losses: 2.9% ÷ 0.35% = 8.3 trades

If Risk = 0.50%:
  Max consecutive losses: 2.9% ÷ 0.50% = 5.8 trades

If Risk = 1.00%:
  Max consecutive losses: 2.9% ÷ 1.00% = 2.9 trades ❌
```

**Smaller risk = More breathing room for drawdowns**

### Why High Confluence?

**Win Rate Impact:**
```
Confluence 12: Win rate ~55%, RR ~2.5
Confluence 16: Win rate ~65%, RR ~2.5

10 trades at 0.35% risk:

Confluence 12 (55% WR):
  Wins: 5.5 × 2.5R = +4.8%
  Losses: 4.5 × 1R = -1.6%
  Net: +3.2%
  Drawdown: Up to -1.6%

Confluence 16 (65% WR):
  Wins: 6.5 × 2.5R = +5.7%
  Losses: 3.5 × 1R = -1.2%
  Net: +4.5%
  Drawdown: Up to -1.2%
```

**Higher confluence = Lower drawdown risk**

### Why Spread Filters?

**Wide spread = Hidden cost:**
```
Entry: 1.0500 (normal spread 0.8 pips)
  Immediate drawdown: -0.8 pips

Entry: 1.0500 (wide spread 5.0 pips)
  Immediate drawdown: -5.0 pips ❌

Must move 5 pips just to break even!
```

**Spread filter = Only trade in favorable conditions**

---

## ✅ Success Checklist

- [ ] Run `Spread_Diagnostics_ForTraders.mq5`
- [ ] Verify broker digit format (5-digit vs 3-digit)
- [ ] Load appropriate .set files
- [ ] Verify spread limits match broker format
- [ ] Governor loaded with 2.9% daily limit
- [ ] Monitor during London/NY session for normal trading
- [ ] Confirm trades execute when spreads are tight
- [ ] Check that trades are blocked during wide spreads
- [ ] Verify drawdown governor scaling at 2.0% DD
- [ ] Test pause mechanism at 2.9% DD (paper trade first!)

---

## 📞 Support

If you continue to have spread issues after running the diagnostic:

1. **Post diagnostic output** from `Spread_Diagnostics_ForTraders.mq5`
2. **Include screenshots** of spread warnings from Expert logs
3. **Note the time** when spread issues occur (check if Asian session)
4. **Verify symbol quotes** in Market Watch (are prices updating?)

---

**Created:** 2024-02-20
**Version:** 1.0
**For:** ForTraders FTTrading-Server Challenge (3% Daily / 5% Max DD)
