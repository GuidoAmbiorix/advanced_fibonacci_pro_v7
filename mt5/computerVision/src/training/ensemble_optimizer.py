
import optuna
import pandas as pd
import numpy as np
import os
from typing import Dict, Any, Tuple
from src.database import DatabaseManager
from src.training.ensemble_trainer import HybridEnsembleTrainer
from src.training.vectorbt_engine import VectorBTEngine

class EnsembleOptimizer:
    """
    Optimizes Hybrid Ensemble hyperparameters using Optuna and VectorBT.
    """
    
    def __init__(self, db: DatabaseManager):
        self.db = db
        self.trainer = HybridEnsembleTrainer(db)
        self.vbt_engine = VectorBTEngine()
        
    def optimize(self, symbol: str, timeframe: str, n_trials: int = 20, study_name: str = None) -> Tuple[Any, Dict]:
        """
        Run Optuna optimization to find best ensemble configuration.
        """
        if study_name is None:
            study_name = f"ensemble_{symbol}_{timeframe}_{pd.Timestamp.now().strftime('%Y%m%d_%H%M')}"
            
        print(f"🚀 Starting Hyper-Ensemble Optimization: {study_name}")
        
        # 1. Load Data Once (to ensure consistency)
        query = """
            SELECT * FROM market_data
            WHERE symbol = %s AND timeframe = %s
            ORDER BY timestamp DESC
            LIMIT 2000
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
            sequence_length = trial.suggest_int('sequence_length', 10, 60, step=5)
            voting = trial.suggest_categorical('voting', ['soft', 'hard'])
            
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
                    voting=voting,
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
                X, _, _ = prepare_training_data(df, use_talib=True)
                
                # X has length = len(df) - NaN_drop
                # test_start_idx is index in X where test starts
                
                X_test = X[test_start_idx:]
                
                # Align Price
                # df aligned with X is the last len(X) rows of df
                df_aligned = df.iloc[-len(X):]
                price_test = df_aligned['close'].iloc[test_start_idx:]
                
                # Generate signals
                if voting == 'soft':
                    probs = ensemble.predict_proba(X_test)
                    threshold = trial.suggest_float('threshold', 0.5, 0.8)
                    entries = probs[:, 1] > threshold
                    exits = probs[:, 1] < 0.4
                else:
                    preds = ensemble.predict(X_test)
                    entries = preds == 1
                    exits = preds == 0
                
                # Reset indices for VectorBT alignment
                price_test = price_test.reset_index(drop=True)
                entries = pd.Series(entries).reset_index(drop=True)
                exits = pd.Series(exits).reset_index(drop=True)
                
                # Safety check lengths
                min_len = min(len(price_test), len(entries))
                price_test = price_test[:min_len]
                entries = entries[:min_len]
                exits = exits[:min_len]
                
                # Risk Params
                sl = trial.suggest_float('stop_loss', 0.005, 0.05)
                tp = trial.suggest_float('take_profit', 0.01, 0.10)
                
                # VectorBT
                vbt_metrics = self.vbt_engine.run_fast_backtest(
                    price_test, entries, exits, sl_stop=sl, tp_stop=tp
                )
                
                # --- Composite Score (User Improvement) ---
                pf = vbt_metrics.get('profit_factor', 0)
                trades = vbt_metrics.get('total_trades', 0)
                sharpe = vbt_metrics.get('sharpe_ratio', 0)
                
                if trades < 5: # Minimum trades penalty
                    return 0.0
                    
                # Score = PF * 0.5 + Sharpe * 0.3 + Log(Trades) * 0.2
                # Log(Trades) helps favor strategies that actually trade frequently enough to be significant
                score = (pf * 0.5) + (sharpe * 0.3) + (np.log1p(trades) * 0.2)
                
                # Store metadata
                trial.set_user_attr("n_models", metrics['n_models'])
                trial.set_user_attr("test_acc", metrics['ensemble_test_accuracy'])
                trial.set_user_attr("pf", pf)
                trial.set_user_attr("sharpe", sharpe)
                trial.set_user_attr("trades", trades)
                
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
            voting=best['voting'],
            df=df
        )
        
        final_metrics['optimization'] = {
            'best_params': best,
            'best_score': study.best_value,
            'n_trials': n_trials,
            'storage': storage_url # Log storage used
        }
        
        return final_ensemble, final_metrics
