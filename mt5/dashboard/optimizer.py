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
        Simulates trading performance based on parameters.
        """
        # 1. Suggest Parameters based on Symbol Group
        space = PARAM_SPACES.get("default")
        if "JPY" in symbol: space = {**space, **PARAM_SPACES.get("JPY")}
        elif "XAU" in symbol: space = {**space, **PARAM_SPACES.get("XAU")}
        
        risk_base = trial.suggest_float("risk_base", space["risk_base"]["low"], space["risk_base"]["high"], step=space["risk_base"]["step"])
        fixed_tp_r = trial.suggest_float("fixed_tp_r", space["fixed_tp_r"]["low"], space["fixed_tp_r"]["high"], step=space["fixed_tp_r"]["step"])
        
        # 2. Simple Vectorized Backtest (Proxy for MQL5 Logic)
        # We assume entry logic is "good enough" and optimize Risk/Management
        # Using simple Volatility Breakout as proxy for "Signal"
        
        df = df_data.copy()
        
        # Calculate ATR (Simple approximation)
        df['tr'] = np.maximum(df['high'] - df['low'], np.abs(df['high'] - df['close'].shift(1)))
        df['atr'] = df['tr'].rolling(window=14).mean()
        
        # Signal: Close > High[1] (Bull), Close < Low[1] (Bear)
        df['signal'] = 0
        df.loc[df['close'] > df['high'].shift(1), 'signal'] = 1
        df.loc[df['close'] < df['low'].shift(1), 'signal'] = -1
        
        # Simulate PnL
        # Stop Loss = ATR * 1.5
        # Take Profit = Stop Loss * fixed_tp_r
        
        trades = []
        equity = 10000
        
        for i in range(20, len(df)):
            if df['signal'].iloc[i] != 0:
                atr = df['atr'].iloc[i]
                if np.isnan(atr): continue
                
                sl_dist = atr * 1.5
                tp_dist = sl_dist * fixed_tp_r
                
                # Check outcome (Simplified: did it hit TP or SL first in next N bars?)
                # Looking ahead 50 bars
                future = df.iloc[i+1 : i+50]
                if future.empty: continue
                
                entry_price = df['close'].iloc[i]
                direction = df['signal'].iloc[i]
                
                outcome = 0 # -1 loss, 1 win, 0 timeout
                
                if direction == 1: # Long
                    tp_price = entry_price + tp_dist
                    sl_price = entry_price - sl_dist
                    
                    # Vectorized check
                    hit_tp = future[future['high'] >= tp_price].index.min()
                    hit_sl = future[future['low'] <= sl_price].index.min()
                else: # Short
                    tp_price = entry_price - tp_dist
                    sl_price = entry_price + sl_dist
                    
                    hit_tp = future[future['low'] <= tp_price].index.min()
                    hit_sl = future[future['high'] >= sl_price].index.min()
                
                # Determine winner
                if pd.isna(hit_tp) and pd.isna(hit_sl):
                    outcome = 0
                elif pd.isna(hit_sl):
                    outcome = 1
                elif pd.isna(hit_tp):
                    outcome = -1
                else:
                    outcome = 1 if hit_tp < hit_sl else -1
                
                # Calculate Result
                if outcome == 1:
                    profit = (risk_base / 100) * equity * fixed_tp_r
                    equity += profit
                    trades.append(fixed_tp_r)
                elif outcome == -1:
                    loss = (risk_base / 100) * equity
                    equity -= loss
                    trades.append(-1.0)
                    
        # Metric: Sharpe Ratio substitute (Mean / StdDev of R-multiples)
        if len(trades) < OPTIMIZATION_SETTINGS["min_trades"]:
            return -9999 # Penalty
            
        returns = np.array(trades)
        sharpe = np.mean(returns) / (np.std(returns) + 1e-6)
        
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
        # Convert params to match DB schema keys
        # e.g., 'fixed_tp_r' matches. 
        # Add symbol and magic (fetch existing to preserve magic)
        
        current_configs = self.db.load_configs()
        if not current_configs.empty:
            row = current_configs[current_configs['symbol'] == symbol]
            if not row.empty:
                config = row.to_dict('records')[0]
                # Update with optimized values
                config.update(params)
                self.db.save_config(config)
                print(f"💾 Updated DB for {symbol}")
