import optuna
import pandas as pd
import numpy as np
import time
from database_manager import DatabaseManager
from optimizer_config import (
    PARAM_SPACES, OPTIMIZATION_SETTINGS, TOTAL_PARAM_COUNT,
    TIMEFRAMES, get_timeframe_settings
)
from metrics import PerformanceMetrics, MultiObjectiveMetrics
from mt5_tester import MT5Tester
import logging

logger = logging.getLogger("Optimizer")

class PortfolioOptimizer:
    def __init__(self, db_manager, timeframe=None):
        self.db = db_manager
        self.timeframe = timeframe or OPTIMIZATION_SETTINGS.get("default_timeframe", 15)
        self.tf_settings = get_timeframe_settings(self.timeframe)
        self.tester = MT5Tester()

    def validate_params(self, params):
        """
        Ensure parameter combinations are logically valid.
        Returns: (is_valid: bool, issues: list[str])
        """
        issues = []

        # RSI bounds check
        if params.get('rsi_oversold', 30) >= params.get('rsi_overbought', 70):
            issues.append("rsi_oversold must be < rsi_overbought")

        # TP constraints
        if params.get('min_tp_r', 1.0) > params.get('max_tp_r', 5.0):
            issues.append("min_tp_r cannot exceed max_tp_r")

        # Trail logic
        if params.get('trail_start_r', 1.0) > params.get('fixed_tp_r', 3.0):
            issues.append("trail_start_r should not exceed fixed_tp_r")

        # Fibonacci zone logic
        fib_low = params.get('fib_level_low', 0.618)
        fib_high = params.get('fib_level_high', 0.786)
        if fib_low > fib_high:
            issues.append("fib_level_low must be <= fib_level_high")

        # Partial TP validation
        if params.get('use_partial_tp', 0) == 1:
            partial_pct = params.get('partial_close_percent', 0.5)
            if not (0.0 < partial_pct < 1.0):
                issues.append("partial_close_percent must be between 0 and 1")

        # Kelly fraction validation
        if params.get('use_kelly', 0) == 1:
            kelly_frac = params.get('kelly_fraction', 0.25)
            if not (0.0 < kelly_frac <= 0.5):
                issues.append("kelly_fraction must be between 0 and 0.5")

        # News filter validation
        if params.get('use_news_filter', 0) == 1:
            if params.get('news_minutes_before', 30) < 0:
                issues.append("news_minutes_before cannot be negative")
            if params.get('news_minutes_after', 30) < 0:
                issues.append("news_minutes_after cannot be negative")

        # Risk limits
        if params.get('risk_base', 0.5) > params.get('max_risk', 2.0):
            issues.append("risk_base should not exceed max_risk")

        # ATR validation
        if params.get('atr_sl_multiplier', 1.5) < 0.5:
            issues.append("atr_sl_multiplier too small (min 0.5)")

        # Trade management
        if params.get('max_trades_per_day', 5) < 1:
            issues.append("max_trades_per_day must be at least 1")

        return len(issues) == 0, issues

    def objective_guardian_db(self, trial, symbol):
        """
        High-Fidelity Backtesting using MT5 Strategy Tester via DB Bridge.
        """
        # Suggest Parameters (Reuse logic from objective)
        space = PARAM_SPACES.get("default")
        if "JPY" in symbol: space = {**space, **PARAM_SPACES.get("JPY", {})}
        elif "XAU" in symbol: space = {**space, **PARAM_SPACES.get("XAU", {})}
        
        def suggest(name):
            conf = space.get(name, PARAM_SPACES["default"].get(name))
            if conf["type"] == "int":
                return trial.suggest_int(name, conf["low"], conf["high"], step=conf.get("step", 1))
            else:
                return trial.suggest_float(name, conf["low"], conf["high"], step=conf.get("step", 0.1))

        # Build Data Dict for DB Update
        params = {}
        for key in space.keys():
            params[key] = suggest(key)
        
        # Override magic number for testing to isolate results
        test_magic = 999999
        params['magicNumber'] = test_magic 
            
        # Update Database
        if not self.tester.prepare_db(params, symbol):
            logger.error("Failed to prepare DB for trial")
            return -100 # Penalty
            
        # Clean previous results for this symbol/magic
        self.tester.clean_symbol_trades(symbol)
            
        # Run Tester
        # Use period from settings
        period = self.tf_settings['timeframe_name']
        self.tester.create_ini_file(symbol, period=period)
        
        if not self.tester.run_tester():
            logger.error("MT5 Tester Failed")
            return -100
            
        # Get Results
        result = self.tester.get_result(symbol, magic=test_magic)
        
        if not result or result['count'] == 0:
            return -100
            
        # Metric: Profit (Simple for now, can be sophisticated later)
        # Optuna maximizes this value
        return result['profit']

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
        # Use timeframe-specific minimum trades
        min_trades = self.tf_settings['min_trades']
        if len(trades) < min_trades:
            return -10 # Penalty
            
        returns = np.array(trades)
        sharpe = np.mean(returns) / (np.std(returns) + 1e-6)
        
        # Penalize huge drawdowns
        return sharpe

    def objective_multi(self, trial, symbol, df_data):
        """
        Multi-objective optimization function.
        Returns tuple of objectives for Pareto optimization.

        Returns: (sharpe, win_rate, -max_dd, profit_factor)
        """
        # Run same backtest logic as objective()
        space = PARAM_SPACES.get("default")
        if "JPY" in symbol: space = {**space, **PARAM_SPACES.get("JPY", {})}
        elif "XAU" in symbol: space = {**space, **PARAM_SPACES.get("XAU", {})}

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

        # Backtest (same as objective())
        df = df_data.copy()

        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=rsi_period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=rsi_period).mean()
        rs = gain / loss
        df['rsi'] = 100 - (100 / (1 + rs))

        df['ema'] = df['close'].ewm(span=ema_period, adjust=False).mean()
        df['ema_slope'] = (df['ema'] - df['ema'].shift(5)) / 5

        df['tr'] = np.maximum(df['high'] - df['low'], np.abs(df['high'] - df['close'].shift(1)))
        df['atr'] = df['tr'].rolling(window=14).mean()

        df['signal'] = 0

        long_cond = (df['close'] > df['ema']) & (df['ema_slope'] > ema_min_slope) & (df['rsi'] < rsi_overbought)
        short_cond = (df['close'] < df['ema']) & (df['ema_slope'] < -ema_min_slope) & (df['rsi'] > rsi_oversold)

        df.loc[long_cond, 'signal'] = 1
        df.loc[short_cond, 'signal'] = -1

        trades = []
        equity = 10000
        start_idx = max(rsi_period, ema_period) + 20

        for i in range(start_idx, len(df)):
            if df['signal'].iloc[i] == 0: continue

            entry_price = df['close'].iloc[i]
            direction = df['signal'].iloc[i]
            atr = df['atr'].iloc[i]
            if np.isnan(atr) or atr == 0: continue

            sl_dist = atr * 1.5
            tp_dist = sl_dist * fixed_tp_r

            trail_active_price = entry_price + (sl_dist * trail_start_r) if direction == 1 else entry_price - (sl_dist * trail_start_r)
            current_sl = entry_price - sl_dist if direction == 1 else entry_price + sl_dist

            outcome = 0

            for j in range(1, 100):
                if i + j >= len(df): break

                bar = df.iloc[i+j]
                high = bar['high']
                low = bar['low']

                if direction == 1:
                    if low <= current_sl:
                        outcome = -1
                        break
                    if high >= entry_price + tp_dist:
                        outcome = 1
                        break
                    if high >= trail_active_price:
                        new_sl = high - (atr * trail_atr_mult)
                        if new_sl > current_sl:
                            current_sl = new_sl
                else:
                    if high >= current_sl:
                        outcome = -1
                        break
                    if low <= entry_price - tp_dist:
                        outcome = 1
                        break
                    if low <= trail_active_price:
                        new_sl = low + (atr * trail_atr_mult)
                        if new_sl < current_sl:
                            current_sl = new_sl

            if outcome == 1:
                profit = (risk_base / 100.0) * equity * fixed_tp_r
                equity += profit
                trades.append(fixed_tp_r)
            elif outcome == -1:
                exit_price = current_sl
                dist = (exit_price - entry_price) * direction
                r_result = dist / sl_dist
                amount = (risk_base / 100.0) * equity * r_result
                equity += amount
                trades.append(r_result)

        # Calculate multiple objectives
        if len(trades) < OPTIMIZATION_SETTINGS["min_trades"]:
            return (-10, 0, -1, 0)  # Penalty values

        # Calculate all objectives using MultiObjectiveMetrics
        sharpe, win_rate, max_dd, profit_factor = MultiObjectiveMetrics.calculate_objectives(
            trades,
            PerformanceMetrics.calculate_equity_curve(trades)
        )

        # Return tuple (Optuna will maximize all except we negate max_dd)
        return (sharpe, win_rate, -max_dd, profit_factor)

    def run_multi_objective_optimization(self, symbol):
        """
        Run multi-objective optimization using Pareto front.

        Returns:
            Dictionary with best balanced solution and Pareto front info
        """
        print(f"🎯 Starting Multi-Objective Optimization for {symbol} on {self.tf_settings['timeframe_name']}...")
        start_time = int(time.time())

        # Load data with timeframe-specific limit
        data_limit = self.tf_settings['data_limit']
        df_full = self.db.get_market_data(symbol, self.timeframe, limit=data_limit)
        if df_full.empty or len(df_full) < 100:
            print(f"⚠️ Not enough data for {symbol}")
            return None

        # Create multi-objective study
        study = optuna.create_study(
            directions=["maximize", "maximize", "maximize", "maximize"]
        )

        # Run optimization
        study.optimize(
            lambda trial: self.objective_multi(trial, symbol, df_full),
            n_trials=OPTIMIZATION_SETTINGS["n_trials"] * 2  # More trials for multi-objective
        )

        # Get Pareto front solutions
        pareto_trials = study.best_trials

        if len(pareto_trials) == 0:
            print(f"❌ No valid trials found")
            return None

        print(f"📊 Found {len(pareto_trials)} Pareto-optimal solutions")

        # Select best balanced solution using composite score
        weights = OPTIMIZATION_SETTINGS.get("objective_weights", [0.4, 0.3, 0.2, 0.1])
        scores = []

        for trial in pareto_trials:
            sharpe, win_rate, neg_dd, pf = trial.values
            composite = MultiObjectiveMetrics.composite_score(
                sharpe, win_rate, -neg_dd, pf, weights
            )
            scores.append((composite, trial))

        best_trial = max(scores, key=lambda x: x[0])[1]

        print(f"✅ Multi-Objective Optimization Complete")
        print(f"   Best Composite Score: {max(scores, key=lambda x: x[0])[0]:.3f}")
        print(f"   Sharpe: {best_trial.values[0]:.3f}")
        print(f"   Win Rate: {best_trial.values[1]*100:.1f}%")
        print(f"   Max DD: {-best_trial.values[2]*100:.1f}%")
        print(f"   Profit Factor: {best_trial.values[3]:.2f}")

        # Log to database
        run_data = {
            'symbol': symbol,
            'mode': f'multi_objective_{self.tf_settings["timeframe_name"]}',
            'status': 'completed',
            'started_at': start_time,
            'completed_at': int(time.time()),
            'n_trials': OPTIMIZATION_SETTINGS["n_trials"] * 2,
            'best_sharpe': best_trial.values[0],
            'best_params': best_trial.params,
            'param_count': len(best_trial.params)
        }

        self.db.log_optimization_run(run_data)

        return {
            'best_params': best_trial.params,
            'sharpe': best_trial.values[0],
            'win_rate': best_trial.values[1],
            'max_dd': -best_trial.values[2],
            'profit_factor': best_trial.values[3],
            'composite_score': max(scores, key=lambda x: x[0])[0],
            'pareto_front_size': len(pareto_trials),
            'param_count': len(best_trial.params)
        }

    def run_guardian_optimization(self, symbol):
        """
        Run High-Fidelity "Guardian" Optimization using MT5 Tester.
        """
        print(f"🛡️ Starting Guardian (High-Fidelity) Optimization for {symbol}...")
        start_time = int(time.time())
        
        # 1. Create Study
        study = optuna.create_study(direction="maximize")
        
        # 2. Optimize
        # Fewer trials because it's slower (MT5 backtest)
        n_trials = OPTIMIZATION_SETTINGS.get("guardian_trials", 20) 
        
        study.optimize(
            lambda trial: self.objective_guardian_db(trial, symbol),
            n_trials=n_trials
        )
        
        best_params = study.best_params
        best_value = study.best_value
        
        print(f"✅ Guardian Optimization Complete for {symbol}")
        print(f"   Best Value: {best_value}")
        print(f"   Best Params: {best_params}")
        
        # 3. Log to DB
        run_data = {
            'symbol': symbol,
            'mode': f'guardian_db_{self.tf_settings["timeframe_name"]}',
            'status': 'completed',
            'started_at': start_time,
            'completed_at': int(time.time()),
            'n_trials': n_trials,
            'best_sharpe': best_value, # Using profit as proxy for now
            'best_params': best_params,
            'param_count': len(best_params)
        }
        
        self.db.log_optimization_run(run_data)
        
        return {
            'best_params': best_params,
            'best_value': best_value,
            'param_count': len(best_params),
            'study': study
        }

    def objective_deterministic(self, symbol, df_data, params):
        """
        Run backtest with fixed parameters (for validation).
        Uses same logic as objective() but without trial.suggest_*().
        """
        # Use provided params dict directly
        risk_base = params.get("risk_base", 0.3)
        fixed_tp_r = params.get("fixed_tp_r", 3.0)

        # Indicators
        rsi_period = params.get("rsi_period", 14)
        rsi_oversold = params.get("rsi_oversold", 30)
        rsi_overbought = params.get("rsi_overbought", 70)

        ema_period = params.get("ema_period", 100)
        ema_min_slope = params.get("ema_min_slope", 0.1)

        # Exits
        trail_start_r = params.get("trail_start_r", 1.0)
        trail_atr_mult = params.get("trail_atr_mult", 2.0)

        # Run same backtest logic
        df = df_data.copy()

        # Indicators
        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=rsi_period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=rsi_period).mean()
        rs = gain / loss
        df['rsi'] = 100 - (100 / (1 + rs))

        df['ema'] = df['close'].ewm(span=ema_period, adjust=False).mean()
        df['ema_slope'] = (df['ema'] - df['ema'].shift(5)) / 5

        df['tr'] = np.maximum(df['high'] - df['low'], np.abs(df['high'] - df['close'].shift(1)))
        df['atr'] = df['tr'].rolling(window=14).mean()

        df['signal'] = 0

        long_cond = (df['close'] > df['ema']) & (df['ema_slope'] > ema_min_slope) & (df['rsi'] < rsi_overbought)
        short_cond = (df['close'] < df['ema']) & (df['ema_slope'] < -ema_min_slope) & (df['rsi'] > rsi_oversold)

        df.loc[long_cond, 'signal'] = 1
        df.loc[short_cond, 'signal'] = -1

        # Simulation
        trades = []
        equity = 10000
        start_idx = max(rsi_period, ema_period) + 20

        for i in range(start_idx, len(df)):
            if df['signal'].iloc[i] == 0: continue

            entry_price = df['close'].iloc[i]
            direction = df['signal'].iloc[i]
            atr = df['atr'].iloc[i]
            if np.isnan(atr) or atr == 0: continue

            sl_dist = atr * 1.5
            tp_dist = sl_dist * fixed_tp_r

            trail_active_price = entry_price + (sl_dist * trail_start_r) if direction == 1 else entry_price - (sl_dist * trail_start_r)
            current_sl = entry_price - sl_dist if direction == 1 else entry_price + sl_dist

            outcome = 0

            for j in range(1, 100):
                if i + j >= len(df): break

                bar = df.iloc[i+j]
                high = bar['high']
                low = bar['low']

                if direction == 1:
                    if low <= current_sl:
                        outcome = -1
                        break
                    if high >= entry_price + tp_dist:
                        outcome = 1
                        break
                    if high >= trail_active_price:
                        new_sl = high - (atr * trail_atr_mult)
                        if new_sl > current_sl:
                            current_sl = new_sl
                else:
                    if high >= current_sl:
                        outcome = -1
                        break
                    if low <= entry_price - tp_dist:
                        outcome = 1
                        break
                    if low <= trail_active_price:
                        new_sl = low + (atr * trail_atr_mult)
                        if new_sl < current_sl:
                            current_sl = new_sl

            if outcome == 1:
                profit = (risk_base / 100.0) * equity * fixed_tp_r
                equity += profit
                trades.append(fixed_tp_r)
            elif outcome == -1:
                exit_price = current_sl
                dist = (exit_price - entry_price) * direction
                r_result = dist / sl_dist
                amount = (risk_base / 100.0) * equity * r_result
                equity += amount
                trades.append(r_result)

        if len(trades) < OPTIMIZATION_SETTINGS["min_trades"]:
            return -10

        returns = np.array(trades)
        sharpe = np.mean(returns) / (np.std(returns) + 1e-6)

        return sharpe

    def run_optimization(self, symbol, enable_oos_test=None):
        """
        Runs optimization for a specific symbol with optional OOS validation.

        Args:
            symbol: Trading symbol
            enable_oos_test: Enable out-of-sample validation (defaults to config setting)

        Returns:
            Dictionary with results including train/test metrics
        """
        print(f"🚀 Starting Optimization for {symbol} on {self.tf_settings['timeframe_name']}...")

        # Track optimization run
        start_time = int(time.time())

        # Use config default if not specified
        if enable_oos_test is None:
            enable_oos_test = OPTIMIZATION_SETTINGS.get("enable_oos_validation", True)

        # 1. Load Data with timeframe-specific limit
        data_limit = self.tf_settings['data_limit']
        df_full = self.db.get_market_data(symbol, self.timeframe, limit=data_limit)

        print(f"   Timeframe: {self.tf_settings['timeframe_name']}")
        print(f"   Data points: {len(df_full)}")
        print(f"   Min trades required: {self.tf_settings['min_trades']}")
        if df_full.empty or len(df_full) < 100:
            print(f"⚠️ Not enough data for {symbol}")
            return None

        if enable_oos_test and len(df_full) > 200:
            # Split into train (80%) and test (20%)
            split_idx = int(len(df_full) * 0.8)
            df_train = df_full[:split_idx]
            df_test = df_full[split_idx:]

            print(f"📊 Data split: Train={len(df_train)} bars, Test={len(df_test)} bars")

            # Optimize on training set
            study = optuna.create_study(direction="maximize")
            study.optimize(
                lambda trial: self.objective(trial, symbol, df_train),
                n_trials=OPTIMIZATION_SETTINGS["n_trials"]
            )

            best_params = study.best_params
            train_sharpe = study.best_value

            # Validate params
            is_valid, issues = self.validate_params(best_params)
            if not is_valid:
                print(f"⚠️ WARNING: Parameter validation issues: {issues}")

            # Validate on test set
            print(f"🧪 Running out-of-sample validation...")
            test_sharpe = self.objective_deterministic(symbol, df_test, best_params)

            # Calculate overfitting metric
            oos_degradation = train_sharpe - test_sharpe

            if oos_degradation > OPTIMIZATION_SETTINGS.get("oos_degradation_threshold", 0.5):
                overfitting_risk = "HIGH"
                print(f"⚠️ WARNING: OOS degradation {oos_degradation:.2f} - possible overfitting")
            elif oos_degradation > 0.2:
                overfitting_risk = "MEDIUM"
                print(f"ℹ️ OOS degradation {oos_degradation:.2f} - moderate overfitting")
            else:
                overfitting_risk = "LOW"
                print(f"✅ OOS degradation {oos_degradation:.2f} - good generalization")

            # Log to database
            run_data = {
                'symbol': symbol,
                'mode': f'single_{self.tf_settings["timeframe_name"]}',
                'status': 'completed',
                'started_at': start_time,
                'completed_at': int(time.time()),
                'n_trials': OPTIMIZATION_SETTINGS["n_trials"],
                'best_sharpe': train_sharpe,
                'best_params': best_params,
                'train_sharpe': train_sharpe,
                'test_sharpe': test_sharpe,
                'oos_degradation': oos_degradation,
                'param_count': len(best_params),
                'overfitting_risk': overfitting_risk
            }

            self.db.log_optimization_run(run_data)

            print(f"✅ Optimization Complete for {symbol}")
            print(f"   Train Sharpe: {train_sharpe:.3f}")
            print(f"   Test Sharpe:  {test_sharpe:.3f}")
            print(f"   Degradation:  {oos_degradation:.3f}")

            return {
                'best_params': best_params,
                'train_sharpe': train_sharpe,
                'test_sharpe': test_sharpe,
                'oos_degradation': oos_degradation,
                'overfitting_risk': overfitting_risk,
                'param_count': len(best_params),
                'study': study  # Return study for analysis
            }
        else:
            # Original behavior without OOS testing
            study = optuna.create_study(direction="maximize")
            study.optimize(
                lambda trial: self.objective(trial, symbol, df_full),
                n_trials=OPTIMIZATION_SETTINGS["n_trials"]
            )

            best_params = study.best_params
            best_sharpe = study.best_value

            # Log to database
            run_data = {
                'symbol': symbol,
                'mode': f'single_{self.tf_settings["timeframe_name"]}',
                'status': 'completed',
                'started_at': start_time,
                'completed_at': int(time.time()),
                'n_trials': OPTIMIZATION_SETTINGS["n_trials"],
                'best_sharpe': best_sharpe,
                'best_params': best_params,
                'param_count': len(best_params)
            }

            self.db.log_optimization_run(run_data)

            print(f"✅ Optimization Complete for {symbol}. Best Sharpe: {best_sharpe:.3f}")

            return {
                'best_params': best_params,
                'best_sharpe': best_sharpe,
                'param_count': len(best_params),
                'study': study  # Return study for analysis
            }

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


class WalkForwardOptimizer:
    """
    Implements rolling window optimization to test parameter stability.

    This class performs walk-forward analysis by:
    - Dividing historical data into overlapping windows
    - Optimizing on each training window
    - Testing on the following out-of-sample window
    - Analyzing stability of results across windows
    """

    def __init__(self, db_manager, timeframe=None):
        self.db = db_manager
        self.timeframe = timeframe or OPTIMIZATION_SETTINGS.get("default_timeframe", 15)
        self.optimizer = PortfolioOptimizer(db_manager, timeframe=self.timeframe)
        self.tf_settings = get_timeframe_settings(self.timeframe)

    def run_walk_forward(self, symbol, train_bars=200, test_bars=50, step=50, n_trials=50):
        """
        Run walk-forward analysis.

        Args:
            symbol: Trading symbol
            train_bars: Number of bars in training window
            test_bars: Number of bars in test window
            step: Step size for rolling window
            n_trials: Number of optimization trials per window

        Returns:
            Dictionary with walk-forward results and stability metrics
        """
        print(f"🔄 Starting Walk-Forward Analysis for {symbol} on {self.tf_settings['timeframe_name']}")
        print(f"   Train: {train_bars} bars, Test: {test_bars} bars, Step: {step} bars")

        data_limit = self.tf_settings['data_limit']
        df_full = self.db.get_market_data(symbol, self.timeframe, limit=data_limit)

        if df_full.empty or len(df_full) < train_bars + test_bars:
            print(f"⚠️ Not enough data for walk-forward analysis")
            return None

        results = []
        start = 0
        window_num = 0

        while start + train_bars + test_bars <= len(df_full):
            window_num += 1
            df_train = df_full[start:start+train_bars]
            df_test = df_full[start+train_bars:start+train_bars+test_bars]

            print(f"\n📊 Window {window_num}: Training bars {start}-{start+train_bars}")

            # Optimize on this window
            study = optuna.create_study(direction="maximize")
            study.optimize(
                lambda trial: self.optimizer.objective(trial, symbol, df_train),
                n_trials=n_trials
            )

            train_sharpe = study.best_value
            best_params = study.best_params

            # Test on OOS window
            test_sharpe = self.optimizer.objective_deterministic(symbol, df_test, best_params)

            degradation = train_sharpe - test_sharpe

            results.append({
                'window': window_num,
                'window_start': start,
                'train_sharpe': train_sharpe,
                'test_sharpe': test_sharpe,
                'degradation': degradation,
                'best_params': best_params
            })

            print(f"   Train Sharpe: {train_sharpe:.3f}, Test Sharpe: {test_sharpe:.3f}, Degradation: {degradation:.3f}")

            start += step

        # Analyze stability
        train_sharpes = [r['train_sharpe'] for r in results]
        test_sharpes = [r['test_sharpe'] for r in results]
        degradations = [r['degradation'] for r in results]

        avg_train_sharpe = np.mean(train_sharpes)
        avg_test_sharpe = np.mean(test_sharpes)
        avg_degradation = np.mean(degradations)
        std_degradation = np.std(degradations)

        # Stability score: 1.0 is perfect, closer to 0 means unstable
        stability_score = max(0, 1.0 - abs(avg_degradation) - std_degradation)

        print(f"\n✅ Walk-Forward Analysis Complete")
        print(f"   Windows: {len(results)}")
        print(f"   Avg Train Sharpe: {avg_train_sharpe:.3f}")
        print(f"   Avg Test Sharpe:  {avg_test_sharpe:.3f}")
        print(f"   Avg Degradation:  {avg_degradation:.3f} ± {std_degradation:.3f}")
        print(f"   Stability Score:  {stability_score:.3f}")

        return {
            'symbol': symbol,
            'windows': results,
            'num_windows': len(results),
            'avg_train_sharpe': avg_train_sharpe,
            'avg_test_sharpe': avg_test_sharpe,
            'avg_degradation': avg_degradation,
            'std_degradation': std_degradation,
            'stability_score': stability_score,
            'train_bars': train_bars,
            'test_bars': test_bars,
            'step': step
        }

    def analyze_parameter_importance(self, study):
        """
        Use Optuna's built-in importance evaluator to determine
        which parameters matter most for the objective.

        Args:
            study: Completed Optuna study

        Returns:
            Dictionary with importance scores and top parameters
        """
        try:
            from optuna.importance import get_param_importances

            importances = get_param_importances(study)

            # Sort by importance
            sorted_importances = sorted(importances.items(), key=lambda x: x[1], reverse=True)

            return {
                'importances': dict(sorted_importances),
                'top_5': sorted_importances[:5],
                'top_10': sorted_importances[:10]
            }
        except Exception as e:
            print(f"⚠️ Could not calculate parameter importance: {e}")
            return {
                'importances': {},
                'top_5': [],
                'top_10': []
            }


class PortfolioLevelOptimizer:
    """
    Optimizes portfolio-wide parameters considering correlation.

    Instead of optimizing each symbol independently, this optimizer:
    1. Considers correlation matrix between symbols
    2. Allocates risk based on diversification benefit
    3. Optimizes global parameters (max portfolio risk, correlation threshold)
    """

    def __init__(self, db_manager, symbols):
        self.db = db_manager
        self.symbols = symbols
        self.correlation_matrix = None
        self.optimizer = PortfolioOptimizer(db_manager)

    def calculate_correlation_matrix(self, lookback_bars=500):
        """
        Calculate return correlation between all symbols.

        Args:
            lookback_bars: Number of bars to use for correlation calculation

        Returns:
            Correlation matrix as DataFrame
        """
        print(f"📊 Calculating correlation matrix for {len(self.symbols)} symbols...")

        returns_dict = {}

        for symbol in self.symbols:
            df = self.db.get_market_data(symbol, 5, limit=lookback_bars)

            if not df.empty and len(df) > 10:
                # Calculate returns
                returns = df['close'].pct_change().dropna()
                returns_dict[symbol] = returns
            else:
                print(f"⚠️ Insufficient data for {symbol}, excluding from correlation")

        if len(returns_dict) < 2:
            print("❌ Need at least 2 symbols with data for correlation analysis")
            return None

        # Align all series to same timestamps
        df_returns = pd.DataFrame(returns_dict)

        # Fill missing values with 0 (or use forward fill)
        df_returns = df_returns.fillna(0)

        # Calculate correlation
        self.correlation_matrix = df_returns.corr()

        print(f"✅ Correlation matrix calculated")
        print(f"   Average correlation: {self.correlation_matrix.values[np.triu_indices_from(self.correlation_matrix.values, k=1)].mean():.3f}")

        return self.correlation_matrix

    def objective_portfolio(self, trial, market_data_dict):
        """
        Optimize portfolio-level parameters.

        Global parameters:
        - max_portfolio_risk: Overall risk ceiling
        - correlation_threshold: Max correlation before reducing size
        - risk_allocation_mode: 'equal', 'volatility_weighted', 'inverse_correlation'
        """

        # Suggest portfolio-level params
        max_portfolio_risk = trial.suggest_float('max_portfolio_risk', 1.0, 5.0, step=0.5)
        corr_threshold = trial.suggest_float('correlation_threshold', 0.5, 0.9, step=0.1)
        risk_allocation = trial.suggest_categorical(
            'risk_allocation_mode',
            ['equal', 'volatility_weighted', 'inverse_correlation']
        )

        # Simulate portfolio with these settings
        combined_returns = []
        symbol_trade_counts = {}

        for symbol in self.symbols:
            if symbol not in market_data_dict or market_data_dict[symbol].empty:
                continue

            df = market_data_dict[symbol]

            # Use simplified backtest (could use full objective method here)
            # For speed, we'll use a simplified version

            # Get trades from objective method
            try:
                # Run optimization objective to get trades
                sharpe = self.optimizer.objective(trial, symbol, df)

                # This is simplified - in production you'd want to track actual trades
                # For now, we'll estimate based on Sharpe and data size
                if sharpe > 0:
                    # Estimate trade count and returns
                    estimated_trades = len(df) // 50  # Rough estimate
                    symbol_trade_counts[symbol] = estimated_trades

                    # Generate synthetic returns based on Sharpe
                    synthetic_returns = np.random.normal(
                        sharpe * 0.1,  # Mean based on Sharpe
                        0.1,  # Std dev
                        estimated_trades
                    )

                    # Apply correlation-based scaling
                    if self.correlation_matrix is not None and symbol in self.correlation_matrix.columns:
                        high_corr_count = sum(
                            1 for corr in self.correlation_matrix[symbol]
                            if abs(corr) > corr_threshold and corr != 1.0
                        )

                        # Reduce size if highly correlated with others
                        corr_penalty = 1.0 / (1 + high_corr_count * 0.3)
                    else:
                        corr_penalty = 1.0

                    # Scale returns
                    scaled_returns = synthetic_returns * corr_penalty
                    combined_returns.extend(scaled_returns)

            except Exception as e:
                print(f"⚠️ Error processing {symbol}: {e}")
                continue

        if len(combined_returns) < 10:
            return -10  # Penalty for insufficient trades

        # Calculate portfolio metrics
        returns_array = np.array(combined_returns)
        portfolio_sharpe = np.mean(returns_array) / (np.std(returns_array) + 1e-6)

        # Penalty for exceeding max risk
        max_return = np.max(np.abs(returns_array))
        if max_return > max_portfolio_risk:
            portfolio_sharpe *= 0.5  # Heavy penalty

        return portfolio_sharpe

    def run_portfolio_optimization(self, n_trials=50):
        """
        Run portfolio-level optimization.

        Args:
            n_trials: Number of optimization trials

        Returns:
            Dictionary with portfolio optimization results
        """
        print(f"🎯 Starting Portfolio-Level Optimization")
        print(f"   Symbols: {', '.join(self.symbols)}")
        print(f"   Trials: {n_trials}")

        # Calculate correlation
        self.calculate_correlation_matrix()

        if self.correlation_matrix is None:
            print("❌ Could not calculate correlation matrix")
            return None

        # Load market data for all symbols
        print("📊 Loading market data for all symbols...")
        market_data = {}
        for symbol in self.symbols:
            df = self.db.get_market_data(symbol, 5, limit=2000)
            if not df.empty:
                market_data[symbol] = df
                print(f"   ✅ {symbol}: {len(df)} bars")
            else:
                print(f"   ⚠️ {symbol}: No data")

        if len(market_data) == 0:
            print("❌ No market data available")
            return None

        # Run optimization
        print(f"\n🧠 Running portfolio optimization...")
        study = optuna.create_study(direction="maximize")

        study.optimize(
            lambda trial: self.objective_portfolio(trial, market_data),
            n_trials=n_trials
        )

        best_params = study.best_params
        portfolio_sharpe = study.best_value

        print(f"\n✅ Portfolio Optimization Complete")
        print(f"   Portfolio Sharpe: {portfolio_sharpe:.3f}")
        print(f"   Best Parameters:")
        for param, value in best_params.items():
            print(f"     {param}: {value}")

        # Analyze correlation impact
        high_corr_pairs = []
        if self.correlation_matrix is not None:
            for i in range(len(self.correlation_matrix)):
                for j in range(i+1, len(self.correlation_matrix)):
                    corr = self.correlation_matrix.iloc[i, j]
                    if abs(corr) > best_params.get('correlation_threshold', 0.7):
                        high_corr_pairs.append({
                            'symbol1': self.correlation_matrix.index[i],
                            'symbol2': self.correlation_matrix.columns[j],
                            'correlation': corr
                        })

        return {
            'best_params': best_params,
            'portfolio_sharpe': portfolio_sharpe,
            'correlation_matrix': self.correlation_matrix.to_dict() if self.correlation_matrix is not None else {},
            'high_correlation_pairs': high_corr_pairs,
            'symbols_count': len(market_data)
        }
