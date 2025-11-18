# Fibonacci Pro EA - User Guide

## MetaTrader 5 Expert Advisor - Fully Automated Trading Bot

**Version:** 1.0
**Platform:** MetaTrader 5
**Converted from:** TradingView Pine Script v7 - Advanced Fibonacci Trading System

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Features](#features)
4. [Input Parameters](#input-parameters)
5. [Trading Logic](#trading-logic)
6. [Risk Management](#risk-management)
7. [Usage Instructions](#usage-instructions)
8. [Optimization Tips](#optimization-tips)
9. [Troubleshooting](#troubleshooting)
10. [Disclaimer](#disclaimer)

---

## Overview

**Fibonacci Pro EA** is a comprehensive automated trading system based on Fibonacci retracement and extension levels combined with multiple technical indicators. The EA is fully automated and manages trades from entry to exit with multiple take profit levels.

### Key Capabilities

✅ **Fully Automated Trading** - Opens and closes trades automatically
✅ **Advanced Fibonacci Analysis** - Auto-detection of swing points and levels
✅ **Multi-Timeframe Confirmation** - Analyzes higher timeframes for trend alignment
✅ **AI-Enhanced Signals** - Scoring system based on multiple confluence factors
✅ **Smart Money Tracking** - Detects institutional activity and accumulation/distribution
✅ **Partial Profit Taking** - Scales out of positions at TP1, TP2, TP3
✅ **Dynamic Risk Management** - ATR-based or Fibonacci-based stop losses
✅ **On-Chart Dashboard** - Real-time performance metrics and signal strength

---

## Installation

### Step 1: Copy Files

1. Copy `FibonacciPro_EA.mq5` to your MetaTrader 5 data folder:
   - Open MT5
   - Go to **File → Open Data Folder**
   - Navigate to **MQL5 → Experts**
   - Paste the `.mq5` file there

### Step 2: Compile

1. Open **MetaEditor** (F4 in MT5)
2. Find `FibonacciPro_EA.mq5` in the Navigator
3. Double-click to open it
4. Click **Compile** button (F7) or **Compile** from menu
5. Ensure there are no errors (0 errors, 0 warnings)

### Step 3: Attach to Chart

1. In MT5, open the chart for your desired symbol and timeframe
2. In the **Navigator** window, expand **Expert Advisors**
3. Drag `FibonacciPro_EA` onto the chart
4. Check **Allow Algo Trading** in the dialog
5. Configure input parameters (see below)
6. Click **OK**

### Step 4: Enable Auto Trading

1. Click the **Algo Trading** button in the toolbar (should turn green)
2. You should see a smiling face icon in the top-right corner of your chart

---

## Features

### 1. Fibonacci Analysis

- **Automatic Swing Detection**: Identifies swing highs and lows based on lookback period
- **Multiple Fibonacci Levels**:
  - Retracements: 23.6%, 38.2%, 50%, 61.8%, 78.6%, 88.6%
  - Extensions: 127.2%, 161.8%, 261.8%
- **Golden Zone**: Highlights the 61.8%-65% zone (high probability reversal area)
- **Kill Zone**: Marks the 88.6% level (extreme reversal zone)

### 2. Technical Indicators

- **RSI (Relative Strength Index)**: Momentum and divergence detection
- **MACD (Moving Average Convergence Divergence)**: Trend and momentum confirmation
- **Stochastic Oscillator**: Overbought/oversold conditions
- **ATR (Average True Range)**: Volatility measurement for dynamic stops

### 3. Multi-Timeframe Analysis

- Automatically selects higher timeframes based on current chart
- Confirms trend direction across multiple timeframes
- Filters signals that don't align with higher timeframe trends

### 4. Volume Analysis

- Volume spike detection
- Bullish vs bearish volume classification
- Volume moving average comparison
- Cumulative Volume Delta (CVD)

### 5. Smart Money Tracking

- **Institutional Volume Detection**: Identifies unusually large volume bars
- **Accumulation/Distribution**: Detects smart money positioning
- **Order Flow Analysis**: Tracks buying vs selling pressure

### 6. Signal Scoring System

Each signal receives a score from 0-10 based on:
- Fibonacci confluence (proximity to key levels)
- Technical indicator alignment
- Volume confirmation
- Multi-timeframe agreement
- Smart money activity

**Signal Modes:**
- **Aggressive**: Threshold 4/10 (more signals, lower accuracy)
- **Moderate**: Threshold 6/10 (balanced)
- **Conservative**: Threshold 8/10 (fewer signals, higher accuracy)
- **Custom**: Set your own threshold

### 7. Risk Management

**Stop Loss Methods:**
- **Fixed Percentage**: Based on account balance
- **Dynamic ATR**: Multiple of Average True Range
- **Swing Points**: Based on recent swing high/low
- **Fibonacci Based**: Uses 78.6% level

**Position Sizing:**
- Automatically calculates lot size based on risk percentage
- Accounts for stop loss distance
- Respects broker's min/max lot size

### 8. Partial Profit Taking

Scales out of winning positions:
- **TP1**: Close 50% at 0.5x risk/reward (configurable)
- **TP2**: Close 30% at 1.0x risk/reward (configurable)
- **TP3**: Close remaining 20% at 1.5x risk/reward (configurable)

Allows you to secure profits while letting winners run!

---

## Input Parameters

### Professional Mode Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Enable Professional Features** | true | Master switch for all advanced features |
| **Multi-Timeframe Analysis** | true | Enable higher timeframe confirmation |
| **AI-Enhanced Signals** | true | Use advanced scoring system |
| **Smart Money Tracking** | true | Track institutional activity |
| **Volume Profile Analysis** | true | Analyze volume patterns |

### Fibonacci Settings

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| **Lookback Period** | 89 | 21-233 | Bars to look back for swing detection (Fibonacci numbers recommended) |
| **Swing Detection Sensitivity** | 5 | 2-21 | Lower = more sensitive to swings |
| **Show Golden Zone** | true | - | Highlight 61.8-65% zone |
| **Show Kill Zone** | true | - | Highlight 88.6% level |

### Fibonacci Levels

Enable/disable specific levels:
- 0.236, 0.382, 0.500, 0.618, 0.786 (Retracements)
- 1.272, 1.618, 2.618 (Extensions)

### Technical Indicators

| Parameter | Default | Description |
|-----------|---------|-------------|
| **RSI Integration** | true | Use RSI in signal generation |
| **RSI Period** | 14 | RSI calculation period |
| **RSI Overbought** | 70 | Overbought threshold |
| **RSI Oversold** | 30 | Oversold threshold |
| **MACD Integration** | true | Use MACD in signal generation |
| **MACD Fast** | 12 | Fast EMA period |
| **MACD Slow** | 26 | Slow EMA period |
| **MACD Signal** | 9 | Signal line period |
| **Stochastic Integration** | true | Use Stochastic in signal generation |
| **Stochastic Period** | 14 | Stochastic calculation period |

### Volume Analysis

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Volume Confirmation Required** | true | Only trade with volume confirmation |
| **Volume MA Length** | 20 | Moving average period for volume |
| **Volume Spike Multiplier** | 1.5 | Volume must be x times MA to qualify |

### Signal Configuration

| Parameter | Default | Options | Description |
|-----------|---------|---------|-------------|
| **Signal Mode** | Conservative | Aggressive/Moderate/Conservative/Custom | Trading aggressiveness |
| **Enable Long Signals** | true | - | Allow long trades |
| **Enable Short Signals** | true | - | Allow short trades |
| **Custom Confluence Required** | 4 | 1-7 | Used when Signal Mode = Custom |

### Risk Management

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Stop Loss Method** | Dynamic ATR | How to calculate stop loss distance |
| **ATR Length** | 14 | ATR calculation period |
| **ATR Multiplier** | 1.5 | Multiply ATR by this for stop distance |
| **Risk:Reward Ratio** | 2.0 | Target profit vs risk ratio |
| **Max Risk % per Trade** | 2.0 | Percentage of account to risk |
| **Account Size** | 10000 | Manual account size (0 = auto) |

### Profit Management

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Use Partial Take Profit** | true | Enable scaling out |
| **% to Close at TP1** | 50.0 | Portion to close at first target |
| **% to Close at TP2** | 30.0 | Portion to close at second target |
| **% to Close at TP3** | 20.0 | Remaining portion at final target |
| **TP1 at x RR Ratio** | 0.5 | TP1 = 0.5 * RR Ratio |
| **TP2 at x RR Ratio** | 1.0 | TP2 = 1.0 * RR Ratio |
| **TP3 at x RR Ratio** | 1.5 | TP3 = 1.5 * RR Ratio |

### Multi-Timeframe

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Higher Timeframe 1** | Auto | First higher timeframe (0 = auto-select) |
| **Higher Timeframe 2** | Auto | Second higher timeframe (0 = auto-select) |

**Auto-Selection Logic:**
- M1 → M5, M15
- M5 → M15, H1
- M15 → H1, H4
- H1 → H4, D1
- H4 → D1, W1

### Advanced Features

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Show Analytics Dashboard** | true | Display on-chart statistics |
| **Show Performance Metrics** | true | Track win rate and P/L |
| **Magic Number** | 123456 | Unique identifier for EA's trades |
| **Trade Comment** | FiboPro | Comment added to all trades |

---

## Trading Logic

### Signal Generation Process

1. **Calculate Fibonacci Levels**
   - Detect swing high and swing low
   - Calculate all retracement and extension levels
   - Identify Golden Zone and Kill Zone

2. **Analyze Technical Indicators**
   - RSI: Check momentum and divergences
   - MACD: Verify trend direction and crossovers
   - Stochastic: Confirm overbought/oversold
   - ATR: Measure volatility

3. **Multi-Timeframe Confirmation**
   - Check RSI on higher timeframes
   - Verify MACD alignment on higher timeframes
   - Ensure trend agreement across timeframes

4. **Volume Analysis**
   - Calculate volume moving average
   - Detect volume spikes
   - Classify volume as bullish or bearish
   - Analyze cumulative volume delta

5. **Smart Money Detection**
   - Identify institutional volume
   - Track accumulation/distribution
   - Monitor order flow imbalances

6. **Score Calculation**
   - **Fibonacci Confluence**: +1 to +4 points based on level
   - **Technical Indicators**: +2 points each for bullish/bearish alignment
   - **Volume**: +3 points for confirming volume
   - **Multi-Timeframe**: +3 points for trend alignment
   - **Smart Money**: +2 points for accumulation/distribution
   - **Total Score**: Normalized to 0-10 scale

7. **Signal Decision**
   - Compare Bull Score and Bear Score to threshold
   - Apply volume confirmation if required
   - Check if longs/shorts are enabled
   - Generate BUY or SELL signal

### Trade Execution

**LONG Trade:**
```
Entry: Current Ask price
Stop Loss: Calculated based on selected method
TP1: Entry + (SL Distance × RR Ratio × 0.5)
TP2: Entry + (SL Distance × RR Ratio × 1.0)
TP3: Entry + (SL Distance × RR Ratio × 1.5)
Lot Size: Auto-calculated based on risk %
```

**SHORT Trade:**
```
Entry: Current Bid price
Stop Loss: Calculated based on selected method
TP1: Entry - (SL Distance × RR Ratio × 0.5)
TP2: Entry - (SL Distance × RR Ratio × 1.0)
TP3: Entry - (SL Distance × RR Ratio × 1.5)
Lot Size: Auto-calculated based on risk %
```

### Trade Management

- **One Position at a Time**: Closes current before opening new
- **Partial Exits**: Closes portions at each TP level
- **Performance Tracking**: Records win/loss and P/L
- **Dashboard Updates**: Real-time display of current status

---

## Risk Management

### Recommended Settings

**Conservative (Low Risk):**
```
Signal Mode: Conservative
Max Risk %: 1.0-1.5%
RR Ratio: 2.0-3.0
Stop Loss Method: Dynamic ATR
ATR Multiplier: 2.0
```

**Moderate (Balanced):**
```
Signal Mode: Moderate
Max Risk %: 2.0%
RR Ratio: 2.0
Stop Loss Method: Dynamic ATR
ATR Multiplier: 1.5
```

**Aggressive (Higher Risk):**
```
Signal Mode: Aggressive
Max Risk %: 2.5-3.0%
RR Ratio: 1.5-2.0
Stop Loss Method: Swing Points
```

### Important Risk Considerations

⚠️ **Never risk more than 2-3% per trade**
⚠️ **Always test on demo account first**
⚠️ **Use proper position sizing**
⚠️ **Monitor drawdown carefully**
⚠️ **Stop trading after significant losses**

---

## Usage Instructions

### For Beginners

1. **Start with Demo Account**
   - Test for at least 1 month on demo
   - Verify the EA works as expected
   - Understand the signals and logic

2. **Use Conservative Settings**
   - Signal Mode: Conservative
   - Max Risk: 1%
   - Enable all filters (MTF, Volume, Smart Money)

3. **Trade Major Pairs**
   - EUR/USD, GBP/USD, USD/JPY
   - Higher liquidity = more reliable signals
   - Lower spreads = better execution

4. **Choose Appropriate Timeframe**
   - H1 (1 Hour): Good balance of signals and reliability
   - H4 (4 Hour): Fewer but higher quality signals
   - D1 (Daily): Very conservative, long-term approach

### For Experienced Traders

1. **Optimize Parameters**
   - Backtest different lookback periods
   - Test various signal thresholds
   - Optimize for your trading style

2. **Combine with Analysis**
   - Use the EA's signals as confirmation
   - Add your own market analysis
   - Consider fundamental factors

3. **Adjust for Market Conditions**
   - Trending markets: Enable extensions, higher RR
   - Ranging markets: Focus on retracements
   - High volatility: Increase ATR multiplier

4. **Portfolio Approach**
   - Run on multiple pairs
   - Diversify timeframes
   - Manage overall portfolio risk

---

## Optimization Tips

### Strategy Tester

1. **Open Strategy Tester** (Ctrl+R in MT5)
2. **Select Settings:**
   - Expert Advisor: FibonacciPro_EA
   - Symbol: Your choice (e.g., EURUSD)
   - Period: Your choice (e.g., H1)
   - Date Range: At least 1 year of data
   - Model: Every tick (most accurate)

3. **Optimize These Parameters:**
   - Lookback Period: 55, 89, 144
   - Swing Strength: 3, 5, 8
   - ATR Multiplier: 1.0, 1.5, 2.0
   - Signal Mode: All options
   - RR Ratio: 1.5, 2.0, 2.5, 3.0

4. **Analyze Results:**
   - Win Rate > 50%
   - Profit Factor > 1.5
   - Max Drawdown < 20%
   - Sharp Ratio > 1.0

### Walk-Forward Analysis

1. Optimize on in-sample data (e.g., 2022-2023)
2. Validate on out-of-sample data (e.g., 2024)
3. Ensure results remain consistent
4. Re-optimize periodically (quarterly)

---

## Troubleshooting

### EA Not Opening Trades

**Possible Causes:**
- Signal threshold too high → Lower to Moderate or Aggressive
- Volume confirmation blocking → Disable if low volume instrument
- No recent swing points → Increase lookback period
- Wrong timeframe → Try H1 or H4
- Algo trading disabled → Click Algo Trading button

### Trades Closing Too Early

**Possible Causes:**
- Partial TP enabled → Adjust TP percentages
- Stop loss too tight → Increase ATR multiplier
- Broker's stop level too large → Use higher timeframe

### Poor Performance

**Possible Causes:**
- Not optimized for symbol/timeframe → Run optimization
- Market conditions changed → Re-optimize or pause trading
- Spread too high → Trade during liquid hours
- Slippage issues → Use better broker or VPS

### Compilation Errors

**Possible Causes:**
- MQL5 version outdated → Update MetaTrader 5
- Missing libraries → Ensure Trade.mqh exists
- Syntax errors → Check code carefully

### Dashboard Not Showing

**Possible Causes:**
- Show Dashboard = false → Enable in inputs
- Objects disabled → Check chart properties
- Chart too small → Zoom out or enlarge window

---

## Best Practices

### Do's ✅

✅ Test on demo for at least 1 month
✅ Use proper risk management (1-2% per trade)
✅ Keep a trading journal
✅ Monitor performance regularly
✅ Use a VPS for 24/7 trading
✅ Trade during liquid market hours
✅ Optimize for specific instruments
✅ Update EA when necessary

### Don'ts ❌

❌ Risk more than 3% per trade
❌ Trade during major news events (unless optimized for it)
❌ Use on untested symbols/timeframes
❌ Ignore drawdown limits
❌ Over-optimize (curve fitting)
❌ Trade without stop losses
❌ Change parameters mid-session
❌ Expect 100% win rate

---

## Performance Expectations

### Realistic Expectations

- **Win Rate**: 45-65% (depending on mode)
- **Profit Factor**: 1.3-2.0
- **Average RR**: 1.5-2.5
- **Max Drawdown**: 10-25%
- **Monthly Return**: 3-10% (conservative)

### Factors Affecting Performance

1. **Market Conditions**
   - Trending vs ranging markets
   - Volatility levels
   - Liquidity

2. **Broker Conditions**
   - Spread size
   - Slippage
   - Execution speed
   - Commission structure

3. **Configuration**
   - Signal mode selected
   - Risk parameters
   - Filters enabled
   - Timeframe used

---

## Disclaimer

**IMPORTANT NOTICE:**

This Expert Advisor is provided for **educational and informational purposes only**.

⚠️ **Risk Warning:**
- Trading forex and CFDs involves substantial risk of loss
- Past performance does NOT guarantee future results
- You may lose all of your invested capital
- Only trade with money you can afford to lose
- Seek independent financial advice if necessary

⚠️ **No Guarantees:**
- This EA does not guarantee profits
- Results vary based on market conditions, broker, and settings
- Developer is not responsible for any losses incurred

⚠️ **Backtesting Disclaimer:**
- Backtesting results do not represent actual trading
- Live trading results will differ from backtesting
- Slippage, spread, and market conditions affect real performance

⚠️ **Usage Agreement:**
- By using this EA, you accept full responsibility for your trading decisions
- You acknowledge the risks involved in automated trading
- You will not hold the developer liable for any losses

---

## Support & Updates

For questions, issues, or suggestions:
- Review this user guide thoroughly
- Test on demo account first
- Keep a detailed log of issues
- Check for EA updates periodically

---

## Version History

**v1.0** (Current)
- Initial release
- Full conversion from TradingView Pine Script v7
- All features implemented
- Fully automated trading
- Multi-timeframe analysis
- Partial profit taking
- Smart money tracking
- On-chart dashboard

---

**Happy Trading! 📈**

Remember: The best EA is one combined with your own knowledge and experience. Use this tool wisely and always practice proper risk management.
