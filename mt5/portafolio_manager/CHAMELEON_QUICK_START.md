# Chameleon Multi-Strategy - Quick Start Guide

## 🚀 5-Minute Setup

### Step 1: Compile Files (In Order)

Open MetaEditor and compile these files in sequence:

```
1. Include/Strategies/BaseStrategy.mqh
2. Include/Strategies/SniperStrategy.mqh
3. Include/Strategies/RubberBandStrategy.mqh
4. Include/Strategies/BreakoutStrategy.mqh
5. Include/Strategy_Performance_Tracker.mqh
6. Symbol_Engine.mq5
```

**Expected Result:** 0 errors, 0 warnings on each file

---

### Step 2: Attach EA to Chart

1. Open EURUSD M15 chart
2. Drag `Symbol_Engine.mq5` to chart
3. Use these settings for first test:

```
======= CHAMELEON MULTI-STRATEGY =======
InpEnableSniper = true
InpEnableRubberBand = true
InpEnableBreakout = true
InpAutoSwitchStrategy = true
InpEnableLegacyMode = false

======= RISK =======
InpRiskBase = 0.5%
InpMaxPositions = 3
```

4. Click OK

---

### Step 3: Verify Initialization

Check Terminal > Experts tab for these messages:

```
✓ Market_Phase_Analyzer indicator initialized
✓ Fibonacci_GoldenPocket indicator initialized
✓ Sniper Strategy initialized
✓ Rubber Band Strategy initialized
✓ Breakout Strategy initialized
✓ Strategy Performance Tracker initialized

🦎 CHAMELEON v2.0 - ADAPTIVE
```

**If you see errors:** Check that Phase 1-2 indicators are compiled:
- `Indicators/Market_Phase_Analyzer.mq5`
- `Indicators/Fibonacci_GoldenPocket.mq5`

---

### Step 4: Watch Dashboard

Dashboard should display:

```
===========================================
  🦎 CHAMELEON v2.0: EURUSD
===========================================
Phase: TRENDING / RANGING / VOLATILE
Strategy: Sniper / RubberBand / Breakout (Auto)
Sniper: 0 trades | 0.0% WR | PF 0.00 | ON
RubberBand: 0 trades | 0.0% WR | PF 0.00 | ON
Breakout: 0 trades | 0.0% WR | PF 0.00 | ON
```

---

### Step 5: Monitor First Trade

Watch for log messages:

```
🦎 CHAMELEON: Strategy Switch - None → Sniper (Phase: 1)
🦎 Sniper BUY Signal: Confluence=14.3
```

---

## 🎯 Strategy Reference

| Strategy | Phase | Entry | TP | Typical R:R |
|----------|-------|-------|----|----|
| **Sniper** | Trending | Golden Pocket + Structure | 161.8% ext | 1:2 |
| **Rubber Band** | Ranging | Range Extremes + RSI | 50% level | 1:1 |
| **Breakout** | Volatile | Clean Break + Volume | 200% ext | 1:2.5 |

---

## 🔧 Common Settings

### Conservative (Low Risk)
```
InpRiskBase = 0.25%
InpMinConfluenceEntry = 4
All 3 strategies enabled
```

### Balanced (Default)
```
InpRiskBase = 0.5%
InpMinConfluenceEntry = 4
All 3 strategies enabled
```

### Aggressive (High Risk)
```
InpRiskBase = 1.0%
InpMinConfluenceEntry = 3
All 3 strategies enabled
```

---

## 🐛 Troubleshooting

### No trades executing?
- Check market phase is not DORMANT
- Verify InpEnableLegacyMode = false
- Check news filter not blocking
- Check killzone filter active

### Strategy always "None"?
- Verify InpAutoSwitchStrategy = true
- Check Market_Phase_Analyzer buffer values
- Ensure not in legacy mode

### Performance tracker not updating?
- Check file write permissions
- Look for CSV file in Common Files folder
- Verify trades actually closing (not just opening)

---

## 📊 Testing Checklist

- [ ] All files compiled successfully
- [ ] Dashboard shows "CHAMELEON v2.0"
- [ ] Phase displayed (not UNDEFINED)
- [ ] Strategy name shown (not None)
- [ ] Performance metrics visible
- [ ] Strategy switches logged
- [ ] Trades executing correctly

---

## 📚 Full Documentation

- **Implementation Details:** `CHAMELEON_IMPLEMENTATION_SUMMARY.md`
- **Testing Guide:** `CHAMELEON_TESTING_GUIDE.md`
- **Original Plan:** `~/.claude/plans/chameleon-multi-strategy-plan.md`

---

## 🎓 What to Expect

### First Hour
- System initializing and learning market phase
- Few or no trades (normal during dormant phase)
- Dashboard updating every 5 seconds

### First Day
- 2-5 strategy switches (depending on market)
- 0-3 trades (varies by market conditions)
- Performance metrics start populating

### First Week
- Clear pattern of strategy usage emerges
- Win rate statistics become meaningful (>10 trades)
- Auto-disable rules may trigger (if strategy underperforms)

---

## ⚡ Quick Commands

**Disable a Strategy:**
```
Set InpEnableSniper = false (or RubberBand/Breakout)
Restart EA
```

**Switch to Manual Mode:**
```
Set InpAutoSwitchStrategy = false
Active strategy stays locked
```

**Revert to Legacy:**
```
Set InpEnableLegacyMode = true
Chameleon disabled, original system active
```

---

## 🎨 Strategy Icons in Logs

- 🦎 - Chameleon system message
- 🟢 - Strategy activated
- 🔴 - Strategy disabled
- ⚠️ - Warning/filter active
- ✅ - Initialization success

---

**Ready to Trade!** 🚀

Version: 1.0 | Date: 2026-02-19
