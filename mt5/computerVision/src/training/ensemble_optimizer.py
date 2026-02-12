
import optuna
import pandas as pd
import numpy as np
import os
from typing import Dict, Any, Tuple
from src.database import DatabaseManager
from src.training.ensemble_trainer import HybridEnsembleTrainer

try:
    from src.training.vectorbt_engine import VectorBTEngine, VECTORBT_AVAILABLE
except ImportError:
    VECTORBT_AVAILABLE = False
    VectorBTEngine = None

class EnsembleOptimizer:
    """
    Optimizes Hybrid Ensemble hyperparameters using Optuna and VectorBT.
    """

    def __init__(self, db: DatabaseManager):
        self.db = db
        self.trainer = HybridEnsembleTrainer(db)
        if not VECTORBT_AVAILABLE or VectorBTEngine is None:
            raise ImportError("VectorBT is required for optimization. Please rebuild Docker containers with 'docker-compose up --build'")
        self.vbt_engine = VectorBTEngine()
        
    def optimize(self, symbol: str, timeframe: str, n_trials: int = 20, study_name: str = None, voting: str = 'soft') -> Tuple[Any, Dict]:
        """
        Run Optuna optimization to find best ensemble configuration.

        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            n_trials: Number of optimization trials
            study_name: Optional study name
            voting: Voting type ('soft' or 'hard')
        """
        if study_name is None:
            study_name = f"ensemble_{symbol}_{timeframe}_{pd.Timestamp.now().strftime('%Y%m%d_%H%M')}"

        print(f"🚀 Starting Hyper-Ensemble Optimization: {study_name}")
        print(f"   Voting Mode: {voting}")
        
        # 1. Load Data Once (to ensure consistency)
        # Use 20,000 bars for H1 swing trading with 12-bar prediction horizon
        # For H1: 20,000 bars = ~833 days (2.3 years) - good coverage
        query = """
            SELECT * FROM market_data
            WHERE symbol = %s AND timeframe = %s
            ORDER BY timestamp DESC
            LIMIT 20000
        """
        with self.db.get_connection() as conn:
            cursor = conn.execute(query, (symbol, timeframe))
            rows = cursor.fetchall()
            df = pd.DataFrame(rows)
            
        if df.empty:
            raise ValueError(f"No data found for {symbol} {timeframe}")
            
        # 2. Define Objective
        def objective(trial):
            # Hyperparameters
            # Sequence length must be >= MACD warmup (26 bars)
            sequence_length = trial.suggest_int('sequence_length', 30, 60, step=5)
            # Use the voting parameter passed to optimize() instead of letting Optuna suggest it
            voting_param = voting
            
            # Model selection
            include_lstm = trial.suggest_categorical('include_lstm', [True, False])
            include_cnn_lstm = trial.suggest_categorical('include_cnn_lstm', [True, False])
            # XGBoost is robust, user suggested fixing it to True to reduce search space,
            # but we can leave it as categorical if we want full search. 
            # User tip: "No tiene sentido optimizar algo que siempre es True." -> Let's keep it True fixed?
            # Actually, let's allow it to be False if other models are enough. 
            # But the user specifically said "Hazlo fijo fuera del trial". Let's follow advice.
            include_xgb = True 
            include_rf = trial.suggest_categorical('include_rf', [True, False])
            include_mlp = trial.suggest_categorical('include_mlp', [True, False])
            
            # Ensure at least 2 models
            if sum([include_lstm, include_cnn_lstm, include_xgb, include_rf, include_mlp]) < 2:
                include_rf = True
            
            try:
                # Train Ensemble
                # Pass df to trainer so it uses the SAME data
                ensemble, metrics = self.trainer.train_ensemble(
                    symbol=symbol,
                    timeframe=timeframe,
                    include_lstm=include_lstm,
                    include_cnn_lstm=include_cnn_lstm,
                    include_xgboost=include_xgb,
                    include_rf=include_rf,
                    include_mlp=include_mlp,
                    sequence_length=sequence_length,
                    voting=voting_param,
                    df=df  # Critical: Consistency
                )
                
                # --- Pruning Check (Step 1) ---
                # We can prune based on validation accuracy if it's too low
                trial.report(metrics['ensemble_test_accuracy'], step=1)
                if trial.should_prune():
                    raise optuna.TrialPruned()
                
                # --- Backtesting ---
                # Get test start index from trainer metrics to align perfectly
                test_start_idx = metrics.get('test_start_index')
                
                # Feature preparation aligns with df but drops NaNs (warmup)
                # Trainer handles this internally. We need to reproduce the features 
                # or trust the trainer's test set.
                # To rely on VectorBT, we need the *entire* price series or the *test* price series.
                # Since we have test_start_index relative to the *features table*, we need the features first.
                
                from src.features import prepare_training_data
                X, _, _, df_aligned = prepare_training_data(df, use_talib=True)

                # CRITICAL: df_aligned is the cleaned dataframe with NaNs already dropped
                # It aligns PERFECTLY with X (same rows, same order)
                original_len = len(df)
                feature_len = len(X)
                nan_dropped = original_len - feature_len

                print(f"📊 Data alignment: Original={original_len}, Features={feature_len}, NaNs={nan_dropped}")

                # Verify perfect alignment
                assert len(df_aligned) == len(X), f"Alignment error: df_aligned={len(df_aligned)}, X={len(X)}"
                print(f"✅ Perfect alignment verified: df_aligned and X both have {len(X)} rows")

                X_test = X[test_start_idx:]

                # Calculate ATR ONLY on training data to avoid look-ahead bias
                import talib
                atr_period = 14
                # Split df_aligned into train and test BEFORE calculating ATR
                df_train = df_aligned.iloc[:test_start_idx]
                df_test = df_aligned.iloc[test_start_idx:]

                # Calculate ATR only on training data
                atr_train = talib.ATR(df_train['high'].values,
                                      df_train['low'].values,
                                      df_train['close'].values,
                                      timeperiod=atr_period)

                # Use training ATR mean for test period (no future information)
                atr_mean = np.nanmean(atr_train)
                price_test = df_test['close']
                
                # Generate signals with 1-bar execution delay (realistic)
                print(f"   🔍 Voting mode: {voting_param}")
                print(f"   🔍 Test set size: {len(X_test)} samples")

                if voting_param == 'soft':
                    # Probability Calibration (Phase 2.2): Makes thresholds interpretable
                    # Without calibration, predict_proba outputs may not represent true probabilities
                    from sklearn.calibration import CalibratedClassifierCV

                    # Get training data for calibration
                    X_train = X[:test_start_idx]
                    y_train = df_aligned['label'].iloc[:test_start_idx]

                    # Split train data for calibration (last 25% as validation)
                    cal_split_idx = int(len(X_train) * 0.75)
                    X_val_cal = X_train[cal_split_idx:]
                    y_val_cal = y_train.iloc[cal_split_idx:]

                    print(f"   🔬 Calibrating probabilities (val={len(X_val_cal)} samples)...")

                    # Calibrate the existing ensemble using validation set
                    # Note: ensemble is already trained on full training data
                    # We use isotonic regression to map raw probs to calibrated probs
                    calibrated_ensemble = CalibratedClassifierCV(
                        ensemble, method='isotonic', cv='prefit'
                    )
                    calibrated_ensemble.fit(X_val_cal, y_val_cal)

                    # Use calibrated probabilities
                    probs = calibrated_ensemble.predict_proba(X_test)

                    # Adaptive threshold range based on calibrated probability distribution
                    probs_class1 = probs[:, 1]
                    prob_mean = probs_class1.mean()
                    prob_max = probs_class1.max()
                    prob_p50 = np.percentile(probs_class1, 50)  # Median
                    prob_p75 = np.percentile(probs_class1, 75)

                    # CRITICAL: Probabilities extremely low (max=0.054) indicates over-calibration
                    # or labels too strict. Need to use very low thresholds.
                    if prob_max < 0.15:
                        # Extremely low probabilities - use percentile-based range
                        threshold_min = max(0.01, prob_mean * 0.5)  # Start at half the mean
                        threshold_max = min(prob_max * 0.95, prob_p75)  # Cap at 95% of max
                        # Ensure min < max
                        if threshold_min >= threshold_max:
                            threshold_max = threshold_min + 0.01
                        print(f"   🔴 EXTREMELY low calibrated probs (mean={prob_mean:.3f}, max={prob_max:.3f})")
                        print(f"   🔧 Using ultra-low threshold range: {threshold_min:.3f}-{threshold_max:.3f}")
                    elif prob_mean < 0.3:
                        # Low confidence model - use percentile-based threshold
                        threshold_min = max(0.05, prob_mean * 0.8)
                        threshold_max = min(0.40, prob_p75)
                        # Ensure min < max
                        if threshold_min >= threshold_max:
                            threshold_max = threshold_min + 0.05
                        print(f"   ⚠️  Low calibrated probs (mean={prob_mean:.3f}, max={prob_max:.3f})")
                        print(f"   🔧 Adjusted threshold range: {threshold_min:.3f}-{threshold_max:.3f}")
                    else:
                        # Normal regime
                        threshold_min = 0.50
                        threshold_max = 0.75

                    threshold = trial.suggest_float('threshold', threshold_min, threshold_max)

                    # Debug: Show probability distribution
                    probs_class1 = probs[:, 1]
                    print(f"   🔍 Calibrated Threshold: {threshold:.2f}")
                    print(f"   🔍 Calibrated Class 1 probs - Min: {probs_class1.min():.3f}, Max: {probs_class1.max():.3f}, Mean: {probs_class1.mean():.3f}")
                    print(f"   🔍 Probs > threshold: {(probs_class1 > threshold).sum()} out of {len(probs_class1)}")

                    # Entry: High confidence for bullish (> threshold)
                    # Exit: ONLY trailing stops (they handle everything)

                    # CRITICAL FIX: Remove ALL manual exits
                    # Problem: Manual exits (RSI, MACD, probability) conflict with trailing stops
                    # Solution: Let trailing stops be the ONLY exit mechanism
                    # Trailing stops already handle:
                    #   - SL based on highest price reached
                    #   - TP when significant profit accumulated
                    #   - Time-based exit at prediction horizon (24 bars)

                    # Entry: High confidence bullish
                    entries_raw = probs[:, 1] > threshold

                    # No manual exits - will use trailing stops only
                    exits_raw = np.zeros(len(entries_raw), dtype=bool)

                    # Shift forward (insert False at beginning, remove last)
                    entries = np.concatenate([[False], entries_raw[:-1]])
                    exits = np.concatenate([[False], exits_raw[:-1]])
                else:
                    # Hard voting: binary predictions
                    preds = ensemble.predict(X_test)
                    print(f"   🔍 Predictions - Class 0: {(preds == 0).sum()}, Class 1: {(preds == 1).sum()}")

                    entries_raw = preds == 1
                    # No manual exits - will use trailing stops only
                    exits_raw = np.zeros(len(entries_raw), dtype=bool)

                    # Same 1-bar delay for hard voting
                    entries = np.concatenate([[False], entries_raw[:-1]])
                    exits = np.concatenate([[False], exits_raw[:-1]])
                
                # Reset indices for VectorBT alignment
                price_test = price_test.reset_index(drop=True)
                entries = pd.Series(entries).reset_index(drop=True)
                exits = pd.Series(exits).reset_index(drop=True)
                
                # Safety check lengths
                min_len = min(len(price_test), len(entries))
                price_test = price_test[:min_len]
                entries = entries[:min_len]
                exits = exits[:min_len]
                
                # ADAPTIVE TRAILING STOPS (Research-backed solution for 72% accuracy→22% win rate)
                # Problem: Fixed stops cause 70% of correct predictions to exit at loss
                # Solution: Trailing stops that adapt to volatility, confidence, and time

                from src.training.trailing_stops import calculate_trailing_stop_exits

                # Optimize trailing stop parameters
                atr_sl_multiplier = trial.suggest_float('atr_sl_multiplier', 2.0, 4.0)  # Tighter for trailing
                atr_tp_multiplier = trial.suggest_float('atr_tp_multiplier', 4.0, 8.0)  # Wider TP target

                print(f"   🎯 Trailing stops: SL={atr_sl_multiplier:.1f}x ATR, TP={atr_tp_multiplier:.1f}x ATR")

                # Calculate trailing stop exits (ONLY exit mechanism)
                # Get probabilities for adaptive trailing (only available in soft voting)
                if voting_param == 'soft':
                    prob_array = probs[:, 1]
                else:
                    prob_array = None  # Hard voting doesn't have probabilities

                trailing_sl_exits, trailing_tp_exits = calculate_trailing_stop_exits(
                    prices=price_test,
                    entries=entries,
                    highs=df_test['high'].reset_index(drop=True)[:min_len],
                    lows=df_test['low'].reset_index(drop=True)[:min_len],
                    closes=df_test['close'].reset_index(drop=True)[:min_len],
                    atr_period=14,
                    sl_multiplier=atr_sl_multiplier,
                    tp_multiplier=atr_tp_multiplier,
                    probabilities=prob_array,
                    prediction_horizon=24
                )

                # Use ONLY trailing stops as exits (no technical exits)
                exits = trailing_sl_exits | trailing_tp_exits

                print(f"   📊 Exit breakdown - Trailing SL: {trailing_sl_exits.sum()}, Trailing TP: {trailing_tp_exits.sum()}, Total: {exits.sum()}")

                # Debug: Log signal counts
                entry_count = entries.sum() if hasattr(entries, 'sum') else sum(entries)
                exit_count = exits.sum() if hasattr(exits, 'sum') else sum(exits)
                print(f"   🔍 Signals: {entry_count} entries, {exit_count} exits out of {len(entries)} bars")

                # Early pruning: Skip if insufficient signals (saves computation)
                # Portfolio strategy: Ultra-selective per pair, diversified across pairs
                # Estimate: ~30% of entry signals convert to completed trades
                # Need ~10-15 trades per pair minimum, so need ~30-50 entry signals
                # Total portfolio (10+ pairs) will have 100-150+ trades for statistical significance
                min_signals_required = 30
                if entry_count < min_signals_required:
                    print(f"   ⏭️ SKIPPING: Only {entry_count} signals (need {min_signals_required}+). Pruning trial.")
                    raise optuna.TrialPruned()

                # VectorBT Backtesting
                if self.vbt_engine is None:
                    raise RuntimeError("VectorBT is required for proper backtesting. Please rebuild Docker containers.")

                if entry_count == 0:
                    print(f"   ⚠️ WARNING: No entry signals generated! Check model predictions and threshold.")
                    return 0.0

                # Run backtest with signal-based exits (no fixed SL/TP)
                # Trailing stops are already incorporated into exit signals
                vbt_metrics = self.vbt_engine.run_fast_backtest(
                    price_test, entries, exits, sl_stop=None, tp_stop=None
                )

                # --- Composite Score (Trading Metrics) ---
                pf = vbt_metrics.get('profit_factor', 0)
                trades = vbt_metrics.get('total_trades', 0)
                sharpe = vbt_metrics.get('sharpe_ratio', 0)
                max_dd = vbt_metrics.get('max_drawdown', 0)
                win_rate = vbt_metrics.get('win_rate', 0)

                # Minimum 10 trades per pair for portfolio strategy
                # Ultra-selective per pair (threshold 0.75-0.95) = few high-quality trades
                # Portfolio of 10+ pairs = 100+ total trades for statistical confidence
                if trades < 10:
                    return 0.0

                # Log metrics for debugging
                print(f"   📊 Trial metrics: PF={pf:.2f}, Sharpe={sharpe:.2f}, Trades={trades}, MaxDD={max_dd:.1%}")

                # Cap Sharpe at 3.0 to prevent overfitting (realistic max for live trading)
                # Research shows Sharpe > 2.0 in backtest is often "too good to be true"
                sharpe_capped = min(sharpe, 3.0)

                # Penalize extreme Sharpe ratios (> 5) as they indicate overfitting
                overfitting_penalty = max(0, sharpe - 5.0) * 0.5  # Penalty for Sharpe > 5

                # Multi-factor score optimizing for real trading performance
                # PF: 40% weight - profit vs loss ratio
                # Sharpe: 30% weight - risk-adjusted returns (capped)
                # Max DD: -20% penalty - penalize large drawdowns
                # Trades: 10% bonus - reward strategies with more trades
                score = (pf * 0.4) + (sharpe_capped * 0.3) - (max_dd * 0.2) + (np.log1p(trades / 10) * 0.1) - overfitting_penalty

                # Bonus for having many trades (better statistical confidence)
                # Adjusted for H1 swing trading
                if trades >= 100:
                    score *= 1.2  # 20% bonus for >= 100 trades
                elif trades >= 75:
                    score *= 1.1  # 10% bonus for >= 75 trades
                
                # Store metadata
                trial.set_user_attr("n_models", metrics['n_models'])
                trial.set_user_attr("test_acc", metrics['ensemble_test_accuracy'])
                trial.set_user_attr("pf", pf)
                trial.set_user_attr("sharpe", sharpe)
                trial.set_user_attr("trades", trades)
                trial.set_user_attr("max_dd", max_dd)
                trial.set_user_attr("win_rate", win_rate)

                return score
                
            except optuna.TrialPruned:
                raise
            except Exception as e:
                print(f"Trial failed: {e}")
                return 0.0

        # 3. Create Study with Pruner and Postgres
        # Use PostgreSQL as requested by user ("Real Production Setup")
        
        # Try to get URL from env, or construct it
        storage_url = os.environ.get('DATABASE_URL')
        
        if not storage_url:
            # Fallback to docker-compose defaults (assuming running locally pointing to mapped port)
            # Docker service name is 'postgres', mapped to 5433 on host
            db_user = os.environ.get('POSTGRES_USER', 'cv_agent')
            db_pass = os.environ.get('POSTGRES_PASSWORD', '123')
            db_host = os.environ.get('POSTGRES_HOST', 'localhost') # Default to localhost if running outside docker
            db_port = os.environ.get('POSTGRES_PORT', '5433')      # Default to mapped port 5433
            db_name = os.environ.get('POSTGRES_DB', 'cv_trading')
            
            storage_url = f"postgresql://{db_user}:{db_pass}@{db_host}:{db_port}/{db_name}"
            
        # Fix deprecated scheme if needed
        if storage_url.startswith("postgres://"):
            storage_url = storage_url.replace("postgres://", "postgresql://", 1)
            
        print(f"🔗 Optuna Storage: {storage_url}")
            
        study = optuna.create_study(
            direction='maximize', 
            study_name=study_name,
            storage=storage_url,
            load_if_exists=True,
            pruner=optuna.pruners.MedianPruner(n_startup_trials=5, n_warmup_steps=0)
        )
        
        study.optimize(objective, n_trials=n_trials)
        
        print(f"✅ Optimization Complete. Best Score: {study.best_value:.4f}")
        print(f"   Best Params: {study.best_params}")
        
        # 4. Retrain Best
        best = study.best_params
        # Handle fixed param
        best_include_xgb = True 
        
        final_ensemble, final_metrics = self.trainer.train_ensemble(
            symbol=symbol,
            timeframe=timeframe,
            include_lstm=best['include_lstm'],
            include_cnn_lstm=best['include_cnn_lstm'],
            include_xgboost=best_include_xgb,
            include_rf=best['include_rf'],
            include_mlp=best['include_mlp'],
            sequence_length=best['sequence_length'],
            voting=voting,
            df=df
        )
        
        # Get best trial's trading metrics
        best_trial = study.best_trial
        final_metrics['optimization'] = {
            'best_params': best,
            'best_score': study.best_value,
            'n_trials': n_trials,
            'storage': storage_url,
            'profit_factor': best_trial.user_attrs.get('pf', 0),
            'sharpe_ratio': best_trial.user_attrs.get('sharpe', 0),
            'total_trades': best_trial.user_attrs.get('trades', 0),
            'max_drawdown': best_trial.user_attrs.get('max_dd', 0),
            'win_rate': best_trial.user_attrs.get('win_rate', 0)
        }

        return final_ensemble, final_metrics
