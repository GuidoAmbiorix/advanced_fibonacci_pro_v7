"""
Hybrid Ensemble Trainer

Combines TensorFlow models (LSTM, CNN-LSTM) with Scikit-Learn models (XGBoost, RF, MLP)
for improved prediction accuracy through ensemble voting.
"""

import sys
from pathlib import Path
import numpy as np
import pickle
from typing import List, Dict, Tuple, Any
from datetime import datetime

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))

from src.database import DatabaseManager
from src.training.sequence_generator import prepare_sequences_for_training
from src.features import prepare_training_data

try:
    import os
    import tensorflow as tf
    from tensorflow import keras

    # Force CPU usage (disable GPU)
    os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
    tf.config.set_visible_devices([], 'GPU')

    # Import custom layers to register them with Keras
    from src.training.tf_models import AttentionLayer
    TENSORFLOW_AVAILABLE = True
    print("✅ TensorFlow configured for CPU")
except ImportError:
    TENSORFLOW_AVAILABLE = False
    print("⚠️ TensorFlow not available")

from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier, VotingClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.base import BaseEstimator, ClassifierMixin

try:
    from xgboost import XGBClassifier
    XGBOOST_AVAILABLE = True
except ImportError:
    XGBOOST_AVAILABLE = False

try:
    from lightgbm import LGBMClassifier
    LIGHTGBM_AVAILABLE = True
except ImportError:
    LIGHTGBM_AVAILABLE = False


class TensorFlowWrapper(BaseEstimator, ClassifierMixin):
    """
    Wrapper to make TensorFlow models compatible with Scikit-Learn ensemble.
    """
    
    _estimator_type = "classifier"
    
    def __init__(self, model: Any, sequence_length: int):
        """
        Initialize wrapper.

        Args:
            model: Trained TensorFlow model
            sequence_length: Sequence length used for training
        """
        self.model = model
        self.sequence_length = sequence_length
        self.classes_ = np.array([0, 1])
        self.n_features_in_ = None
        self._is_fitted = False
        self.model_path = None # For serialization
        
    def __sklearn_tags__(self):
        """Explicit tags for scikit-learn 1.6+ compatibility."""
        # Return a simple tags object that works with all sklearn versions
        class Tags:
            def __init__(self):
                self.estimator_type = "classifier"
                self.requires_y = True
                self.binary_only = False
                self.allow_nan = False
        return Tags()

    def _get_tags(self):
        """Tags for older scikit-learn versions."""
        return {"estimator_type": "classifier"}

    def __sklearn_clone__(self):
        """
        Prevent cloning of the wrapper since the model is already trained.
        """
        cloned = TensorFlowWrapper(self.model, self.sequence_length)
        cloned.n_features_in_ = self.n_features_in_
        cloned._is_fitted = self._is_fitted
        cloned.model_path = self.model_path
        return cloned

    def __getstate__(self):
        """Custom state for pickling - remove model object."""
        state = self.__dict__.copy()
        if 'model' in state:
            # We don't pickle the model object itself
            del state['model']
        return state

    def __setstate__(self, state):
        """Restore state - model remains None until loaded manually."""
        self.__dict__.update(state)
        # self.model will be loaded by PredictionService or similar
        self.model = None
    
    def fit(self, X, y=None):
        """
        Dummy fit method to satisfy Scikit-Learn.

        Args:
            X: Training data
            y: Target labels
        Returns:
            self
        """
        if hasattr(X, "shape"):
            self.n_features_in_ = X.shape[1]
        # Mark as fitted for sklearn 1.8+ compatibility
        self._is_fitted = True
        return self
    
    def predict(self, X):
        """
        Predict classes.

        Args:
            X: Input features (tabular or sequences)

        Returns:
            Predicted classes
        """
        # If X is tabular, convert to sequences
        if len(X.shape) == 2:
            X_seq = self._create_sequences(X)
            # Get predictions for sequences
            seq_probs = self.model.predict(X_seq, verbose=0)
            seq_preds = np.argmax(seq_probs, axis=1)

            # Pad predictions for first sequence_length samples
            # Use the first prediction for padding
            if len(seq_preds) > 0:
                padding = np.full(self.sequence_length, seq_preds[0])
                return np.concatenate([padding, seq_preds])
            else:
                # If no sequences, return default predictions
                return np.zeros(len(X), dtype=int)
        else:
            X_seq = X
            probs = self.model.predict(X_seq, verbose=0)
            return np.argmax(probs, axis=1)
    
    def predict_proba(self, X):
        """
        Predict class probabilities.

        Args:
            X: Input features

        Returns:
            Class probabilities
        """
        # If X is tabular, convert to sequences
        if len(X.shape) == 2:
            X_seq = self._create_sequences(X)
            # Get probability predictions for sequences
            seq_probs = self.model.predict(X_seq, verbose=0)

            # Pad probabilities for first sequence_length samples
            # Use the first prediction for padding
            if len(seq_probs) > 0:
                padding = np.tile(seq_probs[0], (self.sequence_length, 1))
                return np.vstack([padding, seq_probs])
            else:
                # If no sequences, return default probabilities (50/50)
                return np.full((len(X), 2), 0.5)
        else:
            X_seq = X
            return self.model.predict(X_seq, verbose=0)
    
    def _create_sequences(self, X):
        """
        Create sequences from tabular data.
        
        Args:
            X: Tabular features (n_samples, n_features)
            
        Returns:
            Sequences (n_sequences, sequence_length, n_features)
        """
        sequences = []
        
        for i in range(self.sequence_length, len(X)):
            seq = X[i - self.sequence_length:i]
            sequences.append(seq)
        
        return np.array(sequences)


class HybridEnsembleTrainer:
    """
    Train hybrid ensemble combining TensorFlow and Scikit-Learn models.
    """
    
    def __init__(self, db: DatabaseManager = None):
        """
        Initialize trainer.
        
        Args:
            db: Database manager
        """
        self.db = db or DatabaseManager()
        self.models = {}
        self.ensemble = None
        self.scaler = None
        self.feature_names = None
    
    def train_ensemble(self, symbol: str, timeframe: str,
                       include_lstm: bool = True,
                       include_cnn_lstm: bool = True,
                       include_xgboost: bool = True,
                       include_rf: bool = True,
                       include_mlp: bool = True,
                       sequence_length: int = 20,
                       voting: str = 'soft',
                       df: pd.DataFrame = None) -> Tuple[Any, Dict]:
        """
        Train hybrid ensemble.
        
        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            include_lstm: Include LSTM model
            include_cnn_lstm: Include CNN-LSTM model
            include_xgboost: Include XGBoost
            include_rf: Include Random Forest
            include_mlp: Include MLP
            sequence_length: Sequence length for LSTM models
            voting: 'soft' or 'hard' voting
            df: Optional pre-loaded DataFrame (prevents reloading from DB)
            
        Returns:
            (ensemble, metrics)
        """
        print(f"\n{'='*60}")
        print(f"Training Hybrid Ensemble for {symbol} {timeframe}")
        print(f"{'='*60}\n")
        
        # Prepare data
        if df is None:
            print("📥 Fetching data from DB...")
            query = """
                SELECT * FROM market_data
                WHERE symbol = %s AND timeframe = %s
                ORDER BY timestamp DESC
                LIMIT 2000
            """
            import pandas as pd
            with self.db.get_connection() as conn:
                cursor = conn.execute(query, (symbol, timeframe))
                rows = cursor.fetchall()
                df = pd.DataFrame(rows)
        else:
            print("📥 Using provided DataFrame...")
        
        # Create features
        X, y, feature_names = prepare_training_data(df, use_talib=True)
        self.feature_names = feature_names

        # Validate data size
        min_required = sequence_length + 100  # Minimum samples needed
        if len(X) < min_required:
            raise ValueError(
                f"Insufficient data: {len(X)} samples. "
                f"Need at least {min_required} samples "
                f"(sequence_length={sequence_length} + 100 for training)."
            )

        # Scale features
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        self.scaler = scaler
        
        # Split data
        from sklearn.model_selection import train_test_split
        X_train_tab, X_test_tab, y_train, y_test = train_test_split(
            X_scaled, y, test_size=0.2, random_state=42, shuffle=False
        )

        # Convert y to numpy array if it's a pandas Series
        y_train_array = y_train.values if hasattr(y_train, 'values') else y_train
        y_test_array = y_test.values if hasattr(y_test, 'values') else y_test

        # Create sequences for TensorFlow models
        X_train_seq, X_val_seq, X_test_seq, y_train_seq, y_val_seq, y_test_seq, info = prepare_sequences_for_training(
            X_train_tab, y_train_array,
            sequence_length=sequence_length,
            test_size=0.2,
            val_size=0.1,
            shuffle=False
        )
        
        estimators = []
        
        # Train TensorFlow models
        if TENSORFLOW_AVAILABLE:
            if include_lstm:
                print("\n🔷 Training LSTM model...")
                from src.training.tf_models import build_lstm_model, get_callbacks
                
                lstm_model = build_lstm_model(
                    sequence_length=sequence_length,
                    n_features=X_train_seq.shape[2],
                    lstm_units=[128, 64],
                    dense_units=[32],
                    dropout_rate=0.3,
                    use_attention=True
                )
                
                lstm_model.fit(
                    X_train_seq, y_train_seq,
                    validation_data=(X_val_seq, y_val_seq),
                    epochs=50,
                    batch_size=32,
                    callbacks=get_callbacks('models/temp_lstm.keras', patience=10),
                    verbose=0
                )
                
                lstm_wrapper = TensorFlowWrapper(lstm_model, sequence_length)
                estimators.append(('lstm', lstm_wrapper))
                self.models['lstm'] = lstm_model
                print("   ✅ LSTM trained")
            
            if include_cnn_lstm:
                print("\n🔷 Training CNN-LSTM model...")
                from src.training.tf_models import build_cnn_lstm_model
                
                cnn_lstm_model = build_cnn_lstm_model(
                    sequence_length=sequence_length,
                    n_features=X_train_seq.shape[2],
                    cnn_filters=[64, 32],
                    lstm_units=[128, 64],
                    dense_units=[32],
                    dropout_rate=0.3,
                    use_attention=True
                )
                
                cnn_lstm_model.fit(
                    X_train_seq, y_train_seq,
                    validation_data=(X_val_seq, y_val_seq),
                    epochs=50,
                    batch_size=32,
                    callbacks=get_callbacks('models/temp_cnn_lstm.keras', patience=10),
                    verbose=0
                )
                
                cnn_lstm_wrapper = TensorFlowWrapper(cnn_lstm_model, sequence_length)
                estimators.append(('cnn_lstm', cnn_lstm_wrapper))
                self.models['cnn_lstm'] = cnn_lstm_model
                print("   ✅ CNN-LSTM trained")
        
        # Train Scikit-Learn models on tabular data
        if include_xgboost and XGBOOST_AVAILABLE:
            print("\n🔶 Training XGBoost...")
            xgb = XGBClassifier(
                n_estimators=100,
                max_depth=5,
                random_state=42,
                use_label_encoder=False,
                eval_metric='logloss'
            )
            xgb.fit(X_train_tab, y_train)
            estimators.append(('xgboost', xgb))
            self.models['xgboost'] = xgb
            print("   ✅ XGBoost trained")
        
        if include_rf:
            print("\n🔶 Training Random Forest...")
            rf = RandomForestClassifier(
                n_estimators=100,
                max_depth=10,
                random_state=42,
                n_jobs=-1
            )
            rf.fit(X_train_tab, y_train)
            estimators.append(('random_forest', rf))
            self.models['random_forest'] = rf
            print("   ✅ Random Forest trained")
        
        if include_mlp:
            print("\n🔶 Training MLP...")
            mlp = MLPClassifier(
                hidden_layer_sizes=(128, 64, 32),
                max_iter=100,
                random_state=42,
                early_stopping=True
            )
            mlp.fit(X_train_tab, y_train)
            estimators.append(('mlp', mlp))
            self.models['mlp'] = mlp
            print("   ✅ MLP trained")
        
        # Create ensemble
        print(f"\n🎯 Creating {voting} voting ensemble with {len(estimators)} models...")
        # Use n_jobs=1 to avoid parallelization issues with TensorFlow models
        ensemble = VotingClassifier(estimators=estimators, voting=voting, n_jobs=1)
        ensemble.fit(X_train_tab, y_train)
        
        self.ensemble = ensemble
        
        # Evaluate
        print("\n📊 Evaluating ensemble...")
        train_acc = ensemble.score(X_train_tab, y_train)
        test_acc = ensemble.score(X_test_tab, y_test)
        
        # Calculate metrics
        from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
        
        y_pred = self.ensemble.predict(X_test_tab)
        y_pred_proba = self.ensemble.predict_proba(X_test_tab)
        
        metrics = {
            'ensemble_test_accuracy': accuracy_score(y_test_array, y_pred),
            'ensemble_precision': precision_score(y_test_array, y_pred, zero_division=0),
            'ensemble_recall': recall_score(y_test_array, y_pred, zero_division=0),
            'ensemble_f1': f1_score(y_test_array, y_pred, zero_division=0),
            'n_models': len(self.ensemble.estimators_),
            # CRITICAL: Return the index where test set starts to align backtest
            'test_start_index': len(X_train_tab), 
            'total_samples': len(X)
        }
        
        print(f"✅ Ensemble Trained. Test Acc: {metrics['ensemble_test_accuracy']:.2%}")
        
        return self.ensemble, metrics
    
    def save_ensemble(self, symbol: str, timeframe: str, metrics: Dict) -> int:
        """
        Save ensemble to database and disk.
        
        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            metrics: Ensemble metrics
            
        Returns:
            Model ID
        """
        print(f"\n💾 Saving hybrid ensemble...")
        
        # Create directory
        model_dir = Path('models/ensemble')
        model_dir.mkdir(parents=True, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # Save ensemble
        ensemble_path = model_dir / f"hybrid_ensemble_{symbol}_{timeframe}_{timestamp}.pkl"
        
        # Phase 7: Handle TF models separately for serialization
        tf_model_paths = {}
        for name, est in self.ensemble.estimators_:
            if isinstance(est, TensorFlowWrapper):
                tf_path = model_dir / f"tf_part_{name}_{symbol}_{timeframe}_{timestamp}.keras"
                est.model.save(str(tf_path))
                tf_model_paths[name] = str(tf_path)
                est.model_path = str(tf_path) # Update wrapper with its path
        
        ensemble_data = {
            'ensemble': self.ensemble,
            'scaler': self.scaler,
            'features': self.feature_names,
            'tf_model_paths': tf_model_paths,
            'metrics': metrics,
            'use_talib': True,
            'framework': 'hybrid'
        }
        
        with open(ensemble_path, 'wb') as f:
            pickle.dump(ensemble_data, f)
        
        # Save to database
        model_id = self.db.save_model(
            name=f"Hybrid_Ensemble_{symbol}_{timeframe}",
            version=timestamp,
            model_type='HybridEnsemble',
            file_path=str(ensemble_path),
            training_accuracy=metrics['ensemble_train_accuracy'],
            validation_accuracy=metrics['ensemble_test_accuracy'],
            parameters={
                'n_models': metrics['n_models'],
                'model_names': metrics['model_names'],
                'individual_scores': metrics['individual_scores'],
                'features': self.feature_names,
                'n_features': len(self.feature_names),
                'framework': 'hybrid',
                'tf_model_paths': tf_model_paths
            }
        )
        
        print(f"✅ Ensemble saved!")
        print(f"   Model ID: {model_id}")
        print(f"   File: {ensemble_path}")
        
        return model_id


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Train hybrid ensemble')
    parser.add_argument('--symbol', default='EURUSD', help='Trading symbol')
    parser.add_argument('--timeframe', default='H1', help='Timeframe')
    parser.add_argument('--sequence-length', type=int, default=20, help='Sequence length')
    
    args = parser.parse_args()
    
    trainer = HybridEnsembleTrainer()
    ensemble, metrics = trainer.train_ensemble(
        symbol=args.symbol,
        timeframe=args.timeframe,
        sequence_length=args.sequence_length
    )
    
    model_id = trainer.save_ensemble(args.symbol, args.timeframe, metrics)
    
    print(f"\n✅ Hybrid ensemble training complete! Model ID: {model_id}")
