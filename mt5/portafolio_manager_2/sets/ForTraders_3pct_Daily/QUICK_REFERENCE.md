# ForTraders 3% Challenge - Quick Reference Card

## 🎯 Challenge Parameters
```
Daily Drawdown Limit:    3.0% (pause at 2.9%)
Max Drawdown Limit:      5.0% (pause at 4.9%)
```

## 📊 Risk Per Symbol

| Symbol | Risk/Trade | Max Spread | Confluence | Max Daily Loss |
|--------|-----------|------------|------------|----------------|
| EURUSD | 0.35% | 25 pts (2.5 pips) | 16 | 2R (0.7%) |
| GBPUSD | 0.30% | 35 pts (3.5 pips) | 17 | 2R (0.6%) |
| USDJPY | 0.35% | 25 pts (2.5 pips) | 16 | 2R (0.7%) |
| GBPJPY | 0.25% | 45 pts (4.5 pips) | 18 | 2R (0.5%) |
| XAUUSD | 0.30% | 250 pts (25¢) | 17 | 2R (0.6%) |

**Note**: Spread values assume 5-digit broker. If 3-digit, divide by 10.

## 🛡️ Governor Settings

```ini
InpMaxPortfolioRisk = 2.5%    # Max total exposure
InpDD_Normal        = 2.0%    # Start risk reduction
InpDD_Reduced       = 2.5%    # Heavy risk reduction
InpDD_Pause         = 2.9%    # Emergency stop
InpDD_ReducedMult   = 0.50    # Cut risk by 50% when triggered
```

## 📉 Drawdown Response

```
DD 0-2.0%:     Normal trading (100% risk)
DD 2.0-2.5%:   Reduced trading (50% risk)
DD 2.5-2.9%:   Heavily reduced (50% risk)
DD ≥ 2.9%:     PAUSED ⛔
```

## 🔧 Spread Diagnostic

**Run this first:**
```
Scripts/Spread_Diagnostics_ForTraders.mq5
```

**If 5-digit broker**: Use configs as-is
**If 3-digit broker**: Divide all spread values by 10

## ⏰ Best Trading Hours

| Session | Time (GMT) | Spread Quality |
|---------|-----------|----------------|
| Asian | 00:00-08:00 | ❌ Wide spreads |
| London Open | 08:00-12:00 | ✅ Best |
| NY Open | 13:00-17:00 | ✅ Best |
| Late NY | 18:00-22:00 | ⚠️ Widening |

## 🎲 Expected Performance

**Daily:**
- Trades: 4-7 setups across 5 symbols
- Win Rate: ~60-65% (high confluence)
- Avg R: 2.5R
- Target: +0.5% to +1.5% per day

**Weekly:**
- Trades: 20-35 setups
- Target: +3% to +5%
- Max Drawdown: <2% (stay under Normal threshold)

## 🚨 Common Issues

### "Spread too wide: X > Y points"
- ✅ **GOOD** - Filter working correctly
- Wait for London/NY session
- Check time (Asian = normal for wide spreads)

### No trades executing
- Check confluence (might be too high)
- Check killzone filter (are you in active session?)
- Check chop filter (low volatility blocks trades)
- Check drawdown (paused at 2.9%?)

### Hitting daily limit too fast
- Reduce `InpRiskBase` by 0.05% all symbols
- Increase confluence by +1 all symbols
- Trade only 3 symbols instead of 5

## 📁 Configuration Files

```
governor_ForTraders_3pct.set    → Portfolio_Governor.mq5
eurusd_optimized.set            → Symbol_Engine.mq5 (EURUSD)
gbpusd_optimized.set            → Symbol_Engine.mq5 (GBPUSD)
usdjpy_optimized.set            → Symbol_Engine.mq5 (USDJPY)
GBPJPY_optimized.set            → Symbol_Engine.mq5 (GBPJPY)
XAUUSD_optimized.set            → Metals_Engine.mq5 (XAUUSD)
```

## 🧮 Risk Calculator

**Example: 5 trades, all open simultaneously**
```
EURUSD: 0.35%
GBPUSD: 0.30% → Scaled to 0.15% (EUR correlation)
USDJPY: 0.35%
GBPJPY: 0.25% → Scaled to 0.125% (JPY correlation)
XAUUSD: 0.30%
─────────────
TOTAL:  1.375% ✅ (below 2.5% limit)
```

**After 2.0% DD hit:**
```
All risks × 0.50:
EURUSD: 0.175%
GBPUSD: 0.075%  (scaled twice)
USDJPY: 0.175%
GBPJPY: 0.0625% (scaled twice)
XAUUSD: 0.150%
─────────────
TOTAL:  0.6375% ✅
```

## ✅ Daily Checklist

- [ ] Check current DD% (must be <2.9%)
- [ ] Verify spreads reasonable (London/NY hours)
- [ ] Governor active (check logs)
- [ ] Max 5 trades per symbol per day
- [ ] Monitor correlation guard (EUR/JPY pairs)
- [ ] Check news calendar (avoid high-impact events)

## 🎯 Monthly Goal

**Conservative Challenge Pass:**
- Daily: +0.5% average (+10% per month)
- Weekly: +2.5% (+10% per month)
- Monthly: +10%
- Max DD: <3%

**Goal**: Consistency over big wins. Protect capital first!

---

**Print this page and keep at your desk!**
