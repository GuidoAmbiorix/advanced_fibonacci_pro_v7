import optuna
import pandas as pd
import numpy as np
from database_manager import DatabaseManager
from optimizer_config import PARAM_SPACES, OPTIMIZATION_SETTINGS

class PortfolioOptimizer:
    def __init__(self, db_manager):
        self.db = db_manager
        
    def objective(self, trial, symbol, df_data):
        """
        Objective function for Optuna.
        Simulates trading performance based on expanded parameter set.
        """
        # 1. Suggest Parameters
        space = PARAM_SPACES.get("default")
        if "JPY" in symbol: space = {**space, **PARAM_SPACES.get("JPY", {})}
        elif "XAU" in symbol: space = {**space, **PARAM_SPACES.get("XAU", {})}
        
        # Helper to get suggestion safely
        def suggest(name):
            conf = space.get(name, PARAM_SPACES["default"].get(name))
            if conf["type"] == "int":
                return trial.suggest_int(name, conf["low"], conf["high"], step=conf.get("step", 1))
            else:
                return trial.suggest_float(name, conf["low"], conf["high"], step=conf.get("step", 0.1))

        # Core Params
        risk_base = suggest("risk_base")
        fixed_tp_r = suggest("fixed_tp_r")
        
        # Indicators
        rsi_period = suggest("rsi_period")
        rsi_oversold = suggest("rsi_oversold")
        rsi_overbought = suggest("rsi_overbought")
        
        ema_period = suggest("ema_period")
        ema_min_slope = suggest("ema_min_slope")
        
        # Exits
        trail_start_r = suggest("trail_start_r")
        trail_atr_mult = suggest("trail_atr_mult")
        
        # 2. Enhanced Vectorized Backtest
        df = df_data.copy()
        
        # Indicators
        # RSI
        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=rsi_period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=rsi_period).mean()
        rs = gain / loss
        df['rsi'] = 100 - (100 / (1 + rs))
        
        # EMA
        df['ema'] = df['close'].ewm(span=ema_period, adjust=False).mean()
        df['ema_slope'] = (df['ema'] - df['ema'].shift(5)) / 5 # Simple 5-bar slope
        
        # ATR (14 default for calculation, separate param possible)
        df['tr'] = np.maximum(df['high'] - df['low'], np.abs(df['high'] - df['close'].shift(1)))
        df['atr'] = df['tr'].rolling(window=14).mean()
        
        # Signal Generation (Proxy for Confluence)
        # Long: Close > EMA + Slope Positive + RSI < Overbought
        # Short: Close < EMA + Slope Negative + RSI > Oversold
        # Note: This is an *optimization proxy*, not the exact MQL5 strategy, but tunes the same inputs.
        
        df['signal'] = 0
        
        # Vectorized Conditions
        long_cond = (df['close'] > df['ema']) & (df['ema_slope'] > ema_min_slope) & (df['rsi'] < rsi_overbought)
        short_cond = (df['close'] < df['ema']) & (df['ema_slope'] < -ema_min_slope) & (df['rsi'] > rsi_oversold)
        
        df.loc[long_cond, 'signal'] = 1
        df.loc[short_cond, 'signal'] = -1
        
        # Simulation Loop
        trades = []
        equity = 10000
        
        # Skip warmup
        start_idx = max(rsi_period, ema_period) + 20
        
        for i in range(start_idx, len(df)):
            if df['signal'].iloc[i] == 0: continue
            
            # Throttle: Don't take trade if recent one taken? (Simplified: allow all unique signals)
            
            entry_price = df['close'].iloc[i]
            direction = df['signal'].iloc[i]
            atr = df['atr'].iloc[i]
            if np.isnan(atr) or atr == 0: continue
            
            sl_dist = atr * 1.5 # Fixed base structure
            tp_dist = sl_dist * fixed_tp_r
            
            # Trailing Logic Variables
            trail_active_price = entry_price + (sl_dist * trail_start_r) if direction == 1 else entry_price - (sl_dist * trail_start_r)
            current_sl = entry_price - sl_dist if direction == 1 else entry_price + sl_dist
            
            # Look ahead loop (Slow but accurate for trailing)
            outcome = 0 
            pnl = 0
            
            # Simulate max 100 bars duration
            for j in range(1, 100): 
                if i + j >= len(df): break
                
                bar = df.iloc[i+j]
                high = bar['high']
                low = bar['low']
                
                if direction == 1: # Long
                    # Check SL
                    if low <= current_sl:
                        outcome = -1
                        break
                    
                    # Check TP
                    if high >= entry_price + tp_dist:
                        outcome = 1
                        break
                        
                    # Trailing Update
                    if high >= trail_active_price:
                        new_sl = high - (atr * trail_atr_mult)
                        if new_sl > current_sl:
                            current_sl = new_sl
                            
                else: # Short
                    # Check SL
                    if high >= current_sl:
                        outcome = -1
                        break
                        
                    # Check TP
                    if low <= entry_price - tp_dist:
                        outcome = 1
                        break
                        
                    # Trailing Update
                    if low <= trail_active_price:
                        new_sl = low + (atr * trail_atr_mult)
                        if new_sl < current_sl:
                            current_sl = new_sl

            # Calculate Result
            if outcome == 1:
                profit = (risk_base / 100.0) * equity * fixed_tp_r
                equity += profit
                trades.append(fixed_tp_r)
            elif outcome == -1:
                # If trailed out, loss might be smaller or profit small
                # Simplified: Full loss or BE? 
                # For optimizer speed, we assume full loss if SL hit, or partial if trailed.
                # Accurate PnL:
                exit_price = current_sl
                dist = (exit_price - entry_price) * direction
                r_result = dist / sl_dist
                
                amount = (risk_base / 100.0) * equity * r_result
                equity += amount
                trades.append(r_result)

        # Metric: Sharpe Ratio substitute
        if len(trades) < OPTIMIZATION_SETTINGS["min_trades"]:
            return -10 # Penalty
            
        returns = np.array(trades)
        sharpe = np.mean(returns) / (np.std(returns) + 1e-6)
        
        # Penalize huge drawdowns
        return sharpe

    def run_optimization(self, symbol):
        """Runs optimization for a specific symbol."""
        print(f"🚀 Starting Optimization for {symbol}...")
        
        # 1. Load Data
        df = self.db.get_market_data(symbol, 5, limit=5000) # M5 data
        if df.empty or len(df) < 100:
            print(f"⚠️ Not enough data for {symbol}")
            return None
            
        # 2. Create Study
        study = optuna.create_study(direction="maximize")
        study.optimize(lambda trial: self.objective(trial, symbol, df), n_trials=OPTIMIZATION_SETTINGS["n_trials"])
        
        best_params = study.best_params
        print(f"✅ Optimization Complete for {symbol}. Best Params: {best_params}")
        
        return best_params

    def update_db(self, symbol, params):
        """Updates the database with optimized parameters."""
        
        current_configs = self.db.load_configs()
        if not current_configs.empty:
            row = current_configs[current_configs['symbol'] == symbol]
            if not row.empty:
                config = row.to_dict('records')[0]
                
                # Merge existing config with new params
                config.update(params)
                
                if self.db.save_config(config):
                     # Verify
                     if self.db.verify_config_sync(symbol, params):
                         msg = f"✅ Verified: DB Updated for {symbol}"
                         print(msg)
                         return True, msg
                     else:
                         msg = f"❌ WARNING: Verification Failed for {symbol}. Values might not have persisted."
                         print(msg)
                         return False, msg
                else:
                    msg = f"❌ Database Save Failed for {symbol}. Check logs/schema."
                    print(msg)
                    return False, msg
            else:
                return False, f"Symbol {symbol} not found in DB."
        return False, "Could not load configs."
