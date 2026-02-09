# H1 Trading Setup Guide - Complete Workflow

## 🎯 Step 1: Configure Dashboard Settings

### **Go to Trading Control Page**

1. **Set Trading Timeframe**
   - Select: `H1`
   - This tells the system to use H1 ATR for SL/TP calculation

2. **Set ATR Multiplier**
   - Slider: `1.0`
   - H1 recommended: 1.0 (tighter stops)
   - M5 recommended: 1.5 (wider stops for noise)

3. **Set Max Hold Time**
   - Input: `24` hours
   - H1 trades need more time to develop
   - M5 trades: 4 hours

4. **Click 💾 Save Configuration**

### **Expected Result:**

You'll see the estimated SL/TP:

```
📊 Estimated for H1: SL ≈ 50 pips | TP ≈ 100 pips (1:2 R:R)
```

**What this means:**

- System will fetch H1 ATR (~50 pips)
- Multiply by 1.0 = 50 pips SL
- TP = 2x SL = 100 pips
- Risk-based lot sizing will calculate lots based on 50-pip SL

---

## 🧠 Step 2: Train LSTM Models with Optuna

### **For Each Pair (EURUSD, GBPUSD, USDJPY, XAUUSD):**

1. **Go to Model Training → Tab 3.1: LSTM Model**

2. **Select Symbol**
   - Dropdown: `EURUSD` (start with most liquid)

3. **Select Timeframe**
   - Dropdown: `H1`

4. **Enable Optuna Optimization**
   - ✅ Check: `🔍 Optimize with Optuna`
   - Set trials: `20` (good balance of speed vs accuracy)
   - More trials = better params but slower

5. **Click 🚀 Train LSTM Model**

### **What Happens:**

**Phase 1: Optuna Optimization (20-30 minutes)**

```
🔍 Optimizing hyperparameters with 20 trials...
Trial 1/20: Accuracy 68.5%
Trial 2/20: Accuracy 71.2%
...
Trial 20/20: Accuracy 79.8%
```

**Phase 2: Best Params Found**

```json
{
  "lstm_units_1": 256,
  "lstm_units_2": 128,
  "dropout": 0.25,
  "learning_rate": 0.0023,
  "batch_size": 32
}
```

**Phase 3: Final Training (10-15 minutes)**

```
Training final model with best params...
Epoch 50/50 - Accuracy: 79.8%
Test Accuracy: 78.2% ✅
```

**Phase 4: Model Saved**

```
Model saved to database:
- ID: lstm_EURUSD_H1_20260209
- Type: LSTM
- Accuracy: 78.2%
- Optimized: Yes (Optuna 20 trials)
```

### **Repeat for All Pairs:**

| Pair   | Expected Accuracy | Training Time |
| ------ | ----------------- | ------------- |
| EURUSD | 75-80%            | ~40 min       |
| GBPUSD | 72-78%            | ~40 min       |
| USDJPY | 73-79%            | ~40 min       |
| XAUUSD | 78-85%            | ~40 min       |

**Total Time: ~2.5 hours for all 4 pairs**

---

## 💹 Step 3: Execute Trades

### **When Auto-Trader Runs:**

**1. Fetch Latest Prediction**

```python
prediction = get_prediction(symbol='EURUSD', timeframe='H1')
# Returns: {'direction': 'BUY', 'confidence': 0.82}
```

**2. Check Confidence**

```python
if confidence >= 0.70:  # Min confidence from dashboard
    proceed_to_trade()
```

**3. Get Entry Price**

```python
entry_price = get_current_price('EURUSD')
# Returns: 1.0850
```

**4. Read Timeframe from Database**

```python
timeframe = db.get_config('trading_timeframe', 'H1')
# Returns: 'H1'
```

**5. Fetch ATR for H1**

```python
atr = get_atr(symbol='EURUSD', timeframe='H1')
# Returns: 0.0050 (50 pips)
```

**6. Get ATR Multiplier from Database**

```python
atr_multiplier = db.get_config('atr_multiplier', '1.0')
# Returns: 1.0
```

**7. Calculate SL Distance**

```python
sl_distance = atr × atr_multiplier
sl_distance = 0.0050 × 1.0 = 0.0050 (50 pips)
```

**8. Calculate SL/TP Prices**

```python
# For BUY:
sl = entry_price - sl_distance
sl = 1.0850 - 0.0050 = 1.0800 (50 pips below)

tp = entry_price + (sl_distance × 2)
tp = 1.0850 + 0.0100 = 1.0950 (100 pips above)
```

**9. Calculate Lot Size (Risk-Based)**

```python
account_balance = 5000
risk_pct = 1.0  # From dashboard
risk_amount = 5000 × 0.01 = $50

# SL distance in pips
sl_pips = 50

# Lot size calculation
lot_size = risk_amount / (sl_pips × pip_value)
lot_size = 50 / (50 × 0.10) = 50 / 5 = 0.10 lots ✅
```

**10. Execute Trade**

```python
trade = {
    'symbol': 'EURUSD',
    'action': 'BUY',
    'volume': 0.10,
    'entry': 1.0850,
    'sl': 1.0800,
    'tp': 1.0950
}

execute_trade(trade)
```

### **Trade Confirmation:**

```
✅ Trade Executed:
Symbol: EURUSD
Direction: BUY
Entry: 1.0850
SL: 1.0800 (50 pips)
TP: 1.0950 (100 pips)
Lot Size: 0.10
Risk: $50 (1% of $5,000)
R:R: 1:2
```

---

## 📊 Complete Example: EURUSD H1 Trade

### **Setup:**

- Account: $5,000
- Risk per trade: 1% ($50)
- Timeframe: H1
- ATR Multiplier: 1.0
- Max Hold: 24 hours

### **Signal:**

- LSTM Prediction: BUY
- Confidence: 82%
- Entry: 1.0850

### **Calculation:**

```
1. H1 ATR: 50 pips
2. SL Distance: 50 × 1.0 = 50 pips
3. SL Price: 1.0850 - 0.0050 = 1.0800
4. TP Distance: 50 × 2 = 100 pips
5. TP Price: 1.0850 + 0.0100 = 1.0950
6. Lot Size: $50 / (50 pips × $0.10) = 0.10 lots
```

### **Trade Execution:**

```
Entry: 1.0850
SL: 1.0800 (-50 pips = -$50 if hit)
TP: 1.0950 (+100 pips = +$100 if hit)
Lot Size: 0.10
Max Hold: 24 hours
```

### **Possible Outcomes:**

**Scenario 1: TP Hit (Win)**

```
Exit: 1.0950
Profit: +100 pips = +$100
Return: +2% on risk
```

**Scenario 2: SL Hit (Loss)**

```
Exit: 1.0800
Loss: -50 pips = -$50
Return: -1% (as planned)
```

**Scenario 3: Breakeven (After 1:1)**

```
Price reaches 1.0900 (+50 pips)
SL moved to 1.0852 (breakeven + 2 pips)
Price reverses to 1.0852
Exit: 1.0852
Profit: +2 pips = +$2
Return: +0.04%
```

---

## ✅ Verification Checklist

### **After Step 1 (Dashboard Config):**

- [ ] Trading timeframe shows `H1`
- [ ] ATR multiplier shows `1.0`
- [ ] Max hold time shows `24` hours
- [ ] Estimated SL shows `~50 pips`
- [ ] Estimated TP shows `~100 pips`

### **After Step 2 (Model Training):**

- [ ] EURUSD H1 LSTM trained (accuracy >75%)
- [ ] GBPUSD H1 LSTM trained (accuracy >72%)
- [ ] USDJPY H1 LSTM trained (accuracy >73%)
- [ ] XAUUSD H1 LSTM trained (accuracy >78%)
- [ ] All models show "optimized_with_optuna: true"

### **After Step 3 (First Trade):**

- [ ] Trade executed with correct symbol
- [ ] Entry price is current market price
- [ ] SL is ~50 pips from entry
- [ ] TP is ~100 pips from entry (2x SL)
- [ ] Lot size is ~0.10 (for 50-pip SL with $50 risk)
- [ ] Risk is exactly $50 (1% of $5,000)

---

## 🚀 Quick Start Summary

**1. Dashboard Setup (2 minutes):**

```
Trading Control → H1 → ATR 1.0 → 24h → Save
```

**2. Train Models (2.5 hours):**

```
For each pair:
  Model Training → Tab 3.1 → Select pair → ✅ Optuna → 20 trials → Train
```

**3. Start Trading:**

```
Auto-trader will use H1 settings automatically
Check first trade to verify SL/TP calculation
```

**Done! Your system is now configured for H1 trading with Optuna-optimized models!** 🎉
