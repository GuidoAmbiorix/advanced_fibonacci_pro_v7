"""
Optuna Hyperparameter Optimization for TensorFlow Models
"""
import optuna
import logging
from typing import Dict, Tuple
import numpy as np
from tensorflow import keras

logger = logging.getLogger(__name__)


class OptunaOptimizer:
    """Optuna-based hyperparameter optimization for TensorFlow models."""
    
    def __init__(self, db_manager):
        self.db = db_manager
        self.logger = logging.getLogger(__name__)

    def _get_best_val_acc(self, history) -> float:
        """Robustly retrieve the best validation accuracy from history."""
        h = history.history
        # Try common variants
        acc_keys = [k for k in h.keys() if 'val' in k.lower() and 'acc' in k.lower()]
        if not acc_keys:
            # Fallback to any metric containing 'acc'
            acc_keys = [k for k in h.keys() if 'acc' in k.lower()]
            
        if acc_keys:
            # Use the first matching key
            return max(h[acc_keys[0]])
        
        # Absolute fallback
        return 0.0
    
    def optimize_lstm(self, X_train, y_train, X_val, y_val, n_trials=20) -> Dict:
        """
        Optimize LSTM hyperparameters using Optuna.
        
        Args:
            X_train: Training sequences (samples, timesteps, features)
            y_train: Training labels
            X_val: Validation sequences
            y_val: Validation labels
            n_trials: Number of optimization trials
            
        Returns:
            Dictionary of best hyperparameters
        """
        from src.training.tf_models import build_lstm_model
        
        def objective(trial):
            # Suggest hyperparameters
            lstm_units_1 = trial.suggest_categorical('lstm_units_1', [64, 128, 256])
            lstm_units_2 = trial.suggest_categorical('lstm_units_2', [32, 64, 128])
            dropout = trial.suggest_float('dropout', 0.1, 0.5)
            learning_rate = trial.suggest_float('learning_rate', 1e-4, 1e-2, log=True)
            batch_size = trial.suggest_categorical('batch_size', [16, 32, 64])
            
            # Build model with suggested params
            model = build_lstm_model(
                sequence_length=X_train.shape[1],
                n_features=X_train.shape[2],
                lstm_units=[lstm_units_1, lstm_units_2],
                dropout_rate=dropout,
                learning_rate=learning_rate
            )
            
            # Train with early stopping
            early_stop = keras.callbacks.EarlyStopping(
                monitor='val_loss',
                patience=5,
                restore_best_weights=True
            )
            
            history = model.fit(
                X_train, y_train,
                validation_data=(X_val, y_val),
                epochs=30,  # Fewer epochs for optimization
                batch_size=batch_size,
                callbacks=[early_stop],
                verbose=0
            )
            
            # Return best validation accuracy
            return self._get_best_val_acc(history)
        
        # Create study and optimize
        study = optuna.create_study(direction='maximize')
        study.optimize(objective, n_trials=n_trials, show_progress_bar=True)
        
        self.logger.info(f"Best LSTM params: {study.best_params}")
        self.logger.info(f"Best validation accuracy: {study.best_value:.4f}")
        
        return study.best_params
    
    def optimize_cnn_lstm(self, X_train, y_train, X_val, y_val, n_trials=20) -> Dict:
        """
        Optimize CNN-LSTM hyperparameters using Optuna.
        
        Args:
            X_train: Training sequences
            y_train: Training labels
            X_val: Validation sequences
            y_val: Validation labels
            n_trials: Number of optimization trials
            
        Returns:
            Dictionary of best hyperparameters
        """
        from src.training.tf_models import build_cnn_lstm_model
        
        def objective(trial):
            # Suggest hyperparameters
            conv_filters = trial.suggest_categorical('conv_filters', [32, 64, 128])
            kernel_size = trial.suggest_categorical('kernel_size', [3, 5, 7])
            lstm_units = trial.suggest_categorical('lstm_units', [64, 128, 256])
            dropout = trial.suggest_float('dropout', 0.1, 0.5)
            learning_rate = trial.suggest_float('learning_rate', 1e-4, 1e-2, log=True)
            batch_size = trial.suggest_categorical('batch_size', [16, 32, 64])
            
            # Build model
            model = build_cnn_lstm_model(
                sequence_length=X_train.shape[1],
                n_features=X_train.shape[2],
                cnn_filters=[conv_filters],
                kernel_size=kernel_size,
                lstm_units=[lstm_units],
                dropout_rate=dropout,
                learning_rate=learning_rate
            )
            
            # Train
            early_stop = keras.callbacks.EarlyStopping(
                monitor='val_loss',
                patience=5,
                restore_best_weights=True
            )
            
            history = model.fit(
                X_train, y_train,
                validation_data=(X_val, y_val),
                epochs=30,
                batch_size=batch_size,
                callbacks=[early_stop],
                verbose=0
            )
            
            # Return best validation accuracy
            return self._get_best_val_acc(history)
        
        # Optimize
        study = optuna.create_study(direction='maximize')
        study.optimize(objective, n_trials=n_trials, show_progress_bar=True)
        
        self.logger.info(f"Best CNN-LSTM params: {study.best_params}")
        self.logger.info(f"Best validation accuracy: {study.best_value:.4f}")
        
        return study.best_params
    
    def optimize_bilstm_attention(self, X_train, y_train, X_val, y_val, n_trials=15) -> Dict:
        """
        Optimize BiLSTM with Attention hyperparameters.
        
        Args:
            X_train: Training sequences
            y_train: Training labels
            X_val: Validation sequences
            y_val: Validation labels
            n_trials: Number of optimization trials
            
        Returns:
            Dictionary of best hyperparameters
        """
        from src.training.tf_models import build_bidirectional_lstm_model
        
        def objective(trial):
            # Suggest hyperparameters
            lstm_units = trial.suggest_categorical('lstm_units', [64, 128, 256])
            dropout = trial.suggest_float('dropout', 0.1, 0.5)
            learning_rate = trial.suggest_float('learning_rate', 1e-4, 1e-2, log=True)
            batch_size = trial.suggest_categorical('batch_size', [16, 32, 64])
            
            # Build model
            model = build_bidirectional_lstm_model(
                sequence_length=X_train.shape[1],
                n_features=X_train.shape[2],
                lstm_units=[lstm_units],
                dropout_rate=dropout,
                learning_rate=learning_rate
            )

            
            # Train
            early_stop = keras.callbacks.EarlyStopping(
                monitor='val_loss',
                patience=5,
                restore_best_weights=True
            )
            
            history = model.fit(
                X_train, y_train,
                validation_data=(X_val, y_val),
                epochs=30,
                batch_size=batch_size,
                callbacks=[early_stop],
                verbose=0
            )
            
            # Return best validation accuracy
            return self._get_best_val_acc(history)
        
        # Optimize
        study = optuna.create_study(direction='maximize')
        study.optimize(objective, n_trials=n_trials, show_progress_bar=True)
        
        self.logger.info(f"Best BiLSTM-Attention params: {study.best_params}")
        self.logger.info(f"Best validation accuracy: {study.best_value:.4f}")
        
        return study.best_params
