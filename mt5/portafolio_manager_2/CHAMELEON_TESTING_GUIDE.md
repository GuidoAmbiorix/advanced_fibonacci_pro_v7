# Chameleon Multi-Strategy System - Testing Guide

## Overview

The Chameleon Multi-Strategy System implements three specialized trading strategies that automatically adapt to different market conditions:

- **Sniper Strategy** - Trend-following with golden pocket entries (PHASE_TRENDING)
- **Rubber Band Strategy** - Mean reversion at range extremes (PHASE_RANGING)
- **Breakout Strategy** - Volatility expansion capture (PHASE_VOLATILE)

---

## Compilation Instructions

### 1. Compile Indicators (In Order)

All indicators must compile without errors before the EA can run.

```
1. Market_Phase_Analyzer.mq5
   Location: Indicators/Market_Phase_Analyzer.mq5

2. Fibonacci_GoldenPocket.mq5
   Location: Indicators/Fibonacci_GoldenPocket.mq5

3. SMC_Confluence.mq5 (if not already compiled)
   Location: Indicators/SMC_Confluence.mq5

4. Volume_Confluence.mq5 (if not already compiled)
   Location: Indicators/Volume_Confluence.mq5

5. MTF_Confluence.mq5 (if not already compiled)
   Location: Indicators/MTF_Confluence.mq5
```

**How to Compile:**
- In MetaEditor, open each file
- Press F7 or click Compile button
- Check for 0 errors, 0 warnings (warnings acceptable if documented)

### 2. Compile Expert Advisor

```
Symbol_Engine.mq5
Location: Symbol_Engine.mq5
```

**Expected Output:**
```
0 error(s), 0 warning(s)
Successfully compiled (or number of milliseconds)
```

### 3. Verify Include Files

Ensure all strategy files are present:
```
Include/Strategies/BaseStrategy.mqh
Include/Strategies/SniperStrategy.mqh
Include/Strategies/RubberBandStrategy.mqh
Include/Strategies/BreakoutStrategy.mqh
Include/Strategy_Performance_Tracker.mqh
```

---

## Strategy Tester Configuration

### Test 1: Individual Strategy Testing

Run each strategy separately to validate regime-specific performance.

#### A) Sniper Strategy Test (Trending Markets)

**Symbol:** EURUSD
**Timeframe:** M15
**Period:** January 2024 - December 2024 (1 year)
**Mode:** Every tick based on real ticks

**EA Settings:**
```
InpEnableSniper = true
InpEnableRubberBand = false
InpEnableBreakout = false
InpAutoSwitchStrategy = false  // Manual selection
InpRiskBase = 0.5%
InpMinConfluenceEntry = 12.0
```

**Success Criteria:**
- Win Rate: > 50%
- Profit Factor: > 1.5
- Total Trades: > 50
- Avg R:R: > 1:1.5
- Drawdown: < 15%

#### B) Rubber Band Strategy Test (Ranging Markets)

**Symbol:** GBPJPY (known for ranging)
**Timeframe:** M15
**Period:** January 2024 - December 2024

**EA Settings:**
```
InpEnableSniper = false
InpEnableRubberBand = true
InpEnableBreakout = false
InpAutoSwitchStrategy = false
InpRiskBase = 0.5%
InpMinConfluenceEntry = 10.0
```

**Success Criteria:**
- Win Rate: > 55%
- Profit Factor: > 1.3
- Total Trades: > 30
- Avg R:R: > 1:1
- Drawdown: < 12%

#### C) Breakout Strategy Test (Volatile Markets)

**Symbol:** XAUUSD (Gold - high volatility)
**Timeframe:** M15
**Period:** January 2024 - December 2024

**EA Settings:**
```
InpEnableSniper = false
InpEnableRubberBand = false
InpEnableBreakout = true
InpAutoSwitchStrategy = false
InpRiskBase = 0.5%
InpMinConfluenceEntry = 14.0
```

**Success Criteria:**
- Win Rate: > 45%
- Profit Factor: > 1.8
- Total Trades: > 40
- Avg R:R: > 1:2
- Drawdown: < 18%

### Test 2: Auto-Switching Strategy (Complete System)

**Symbol:** EURUSD
**Timeframe:** M15
**Period:** January 2023 - December 2025 (3 years)
**Mode:** Every tick based on real ticks

**EA Settings:**
```
InpEnableSniper = true
InpEnableRubberBand = true
InpEnableBreakout = true
InpAutoSwitchStrategy = true  // Let Market_Phase_Analyzer decide
InpRiskBase = 0.5%
```

**Success Criteria:**
- Total Profit: > Best Individual Strategy
- Profit Factor: > 1.4
- Total Trades: > 100
- Strategy Switch Frequency: 2-5 per day
- Each Strategy Win Rate: > 45%
- Drawdown: < 20%

---

## Visual Validation Checklist

### 1. Market Phase Detection

Open chart with Market_Phase_Analyzer indicator attached.

**Check:**
- [ ] TRENDING phase shows when ADX > 25 and strong directional movement
- [ ] RANGING phase shows when price oscillates in clear box
- [ ] VOLATILE phase shows during news events / breakouts
- [ ] DORMANT phase shows during low volume periods (Asian session, etc.)
- [ ] Phase transitions are smooth (not whipsawing)

### 2. Fibonacci Levels

Open chart with Fibonacci_GoldenPocket indicator attached.

**Check:**
- [ ] Swing high/low detected correctly (matches manual ZigZag)
- [ ] Golden pocket (61.8%-78.6%) highlighted clearly
- [ ] Fibonacci levels align with manual drawing
- [ ] Levels update when new swings form
- [ ] 127.2% extension marked (fake-out detection)

### 3. Strategy Execution

Run EA on demo account for 1 week.

**Check:**
- [ ] Sniper entries occur in golden pocket during trends
- [ ] Rubber Band entries occur at range extremes
- [ ] Breakout entries occur on clean range breaks
- [ ] Stop losses placed correctly per strategy
- [ ] Take profit levels match strategy specifications
- [ ] Strategy switches logged in journal

### 4. Dashboard Display

**Check:**
- [ ] Current market phase displayed correctly
- [ ] Active strategy name shown
- [ ] Performance metrics per strategy visible
- [ ] Win rate, profit factor, trade count accurate
- [ ] Strategy enabled/disabled status clear

---

## Performance Comparison Metrics

Create spreadsheet to compare results:

| Metric | Current System | Sniper Only | RubberBand Only | Breakout Only | Auto-Switch |
|--------|----------------|-------------|-----------------|---------------|-------------|
| Total Trades | | | | | |
| Win Rate % | | | | | |
| Profit Factor | | | | | |
| Net Profit $ | | | | | |
| Max Drawdown % | | | | | |
| Avg R:R | | | | | |
| Sharpe Ratio | | | | | |

**Expected Improvements:**
- Auto-Switch should outperform any single strategy
- Total trades should increase 30-50%
- Win rate should improve 10-15%
- Profit factor should improve 20-30%
- Drawdown should reduce 15-25%

---

## Debug Mode Testing

### Enable Verbose Logging

Modify EA to add detailed print statements:

```cpp
// In OnTick()
Print("[CHAMELEON] Phase: ", PhaseToString(currentPhase),
      " | Active Strategy: ", GetActiveStrategyName(),
      " | Sniper Score: ", sniperScore,
      " | RubberBand Score: ", rubberBandScore,
      " | Breakout Score: ", breakoutScore);
```

**Monitor Logs For:**
- Phase detection changes
- Strategy switches
- Confluence score calculations
- Entry/exit decisions

### Common Issues & Solutions

**Issue 1: Indicator handles INVALID**
- Solution: Check indicator compilation
- Verify indicator file paths in iCustom() calls
- Ensure indicators folder structure correct

**Issue 2: No trades executed**
- Solution: Check market phase detection (might be DORMANT/UNDEFINED)
- Verify confluence thresholds not too high
- Check filters (news, killzone, session)

**Issue 3: Frequent strategy switching (whipsawing)**
- Solution: Add minimum regime duration check
- Implement transition buffer zones
- Review phase detection parameters

**Issue 4: Poor performance in specific regime**
- Solution: Check strategy confluence calculations
- Verify indicator buffer mappings
- Review entry logic for that strategy

---

## Forward Testing Protocol

### Week 1-2: Demo Account Testing

**Setup:**
- Account: Demo $10,000
- Symbol: EURUSD
- Timeframe: M15
- Settings: Conservative (Risk 0.25%, Auto-switch ON)

**Daily Checklist:**
- [ ] Review trades (winners vs losers)
- [ ] Verify strategy selection matched market phase
- [ ] Check for false signals
- [ ] Monitor strategy performance metrics
- [ ] Review logs for errors

**Week 1 Expected Results:**
- 5-10 trades total
- 2-4 strategy switches per day
- Win rate 45-55%
- No major errors in logs

### Week 3-4: Live Micro Account Testing

**Setup:**
- Account: Live $100-500 (micro lots)
- Symbol: EURUSD
- Timeframe: M15
- Settings: Production (Risk 0.5%, Auto-switch ON)

**Daily Checklist:**
- [ ] Verify slippage acceptable (< 2 pips)
- [ ] Check execution speed
- [ ] Monitor spread during entries
- [ ] Review strategy tracker metrics
- [ ] Compare with demo results

### Week 5-6: Full Live Deployment

**Setup:**
- Account: Live production account
- Symbols: EURUSD, GBPUSD, USDJPY
- Timeframe: M15
- Settings: Production (Risk 0.5%, Auto-switch ON)

**Weekly Review:**
- [ ] Performance vs backtest
- [ ] Strategy distribution (% trades per strategy)
- [ ] Risk management effectiveness
- [ ] Auto-disable triggers (if any)

---

## Optimization Guidelines

### DO NOT Over-Optimize

**Good Parameters to Optimize:**
- Risk percentages (0.25% - 1.0%)
- Confluence thresholds per strategy (±2 points)
- Session/killzone filters (on/off)

**BAD Parameters to Optimize (Keep Fixed):**
- Indicator calculation periods (use defaults)
- Fibonacci ratios (use standard 61.8%, 78.6%)
- Phase detection thresholds (research-based)
- Strategy entry logic (coded from plan)

### Walk-Forward Analysis

**Procedure:**
1. Optimize on 6 months data (Jan-Jun 2024)
2. Test forward on next 3 months (Jul-Sep 2024)
3. Verify results within 20% of optimized
4. If pass, use settings for next period
5. If fail, review strategy logic (not parameters)

---

## Success Criteria Summary

### Minimum Acceptable Performance

**Individual Strategies:**
- Sniper: WR > 50%, PF > 1.5, RR > 1:1.5
- RubberBand: WR > 55%, PF > 1.3, RR > 1:1
- Breakout: WR > 45%, PF > 1.8, RR > 1:2

**Auto-Switch System:**
- Total WR > 50%
- Total PF > 1.4
- Net Profit > Best Individual Strategy
- Max DD < 20%
- Strategy switches 2-5 per day (not whipsawing)

### Deployment Readiness Checklist

- [ ] All 3 strategies pass individual backtests
- [ ] Auto-switch system passes 3-year backtest
- [ ] Visual validation confirms correct phase detection
- [ ] Demo testing shows stable performance (2 weeks)
- [ ] No critical errors in logs
- [ ] Strategy performance tracker working
- [ ] Auto-disable logic tested
- [ ] Documentation reviewed and understood

---

## Emergency Procedures

### If Strategy Underperforms

1. Check performance tracker metrics
2. Review last 10 trades (entry quality)
3. Verify market phase alignment
4. Check for news events / flash crashes
5. Manually disable strategy if needed
6. Investigate indicator data (buffer values)

### If System Crashes/Freezes

1. Check indicator handles (might be invalid)
2. Review logs for stack overflow / memory errors
3. Restart EA (will reload performance data from CSV)
4. Verify all indicators still working
5. Test on demo before re-enabling live

### If Auto-Disable Triggered

1. Review strategy performance report
2. Check reason for disable in tracker
3. Analyze recent trades for patterns
4. Determine if market condition or strategy issue
5. Re-enable manually only after investigation
6. Consider parameter adjustment if systemic

---

## Contact & Support

**Documentation:**
- Plan: `chameleon-multi-strategy-plan.md`
- Code: `Include/Strategies/`
- Performance: `strategy_performance_[SYMBOL].csv`

**Debugging:**
- Enable print statements in strategy classes
- Use Visual Debugger in MetaEditor
- Review Expert logs in Terminal

**Updates:**
- Version tracking in file headers
- Change log in git commits
- Performance data persists across restarts

---

## Conclusion

The Chameleon Multi-Strategy System represents a professional-grade adaptive trading framework. Proper testing is critical to validate the regime-detection logic and strategy-specific performance. Follow this guide systematically, and maintain detailed records of all test results.

**Remember:** The goal is not perfect backtests, but robust real-world performance across different market conditions.

---

**Version:** 1.0
**Last Updated:** 2026-02-19
**Status:** Ready for Phase 3-6 Testing
