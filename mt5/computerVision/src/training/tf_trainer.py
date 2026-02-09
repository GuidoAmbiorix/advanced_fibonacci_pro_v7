"""
TensorFlow Training Pipeline

Handles training, evaluation, and saving of TensorFlow models.
"""

import sys
from pathlib import Path
import numpy as np
import pandas as pd
import pickle
from datetime import datetime
from typing import Tuple, Dict, Any
import tensorflow as tf
from tensorflow import keras

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))

from src.training.sequence_generator import prepare_sequences_for_training
from src.training.tf_models import (
    build_lstm_model,
    build_cnn_lstm_model,
    build_bidirectional_lstm_model,
    get_callbacks,
    print_model_summary
)
from src.database import DatabaseManager
from src.features import prepare_training_data


class TensorFlowTrainer:
    """
    Trainer for TensorFlow/Keras models.
    """
    
    def __init__(self, db: DatabaseManager = None):
        """
        Initialize trainer.
        
        Args:
            db: Database manager instance
        """
        self.db = db or DatabaseManager()
        self.model = None
        self.history = None
        self.scaler = None
        self.feature_names = None
        self.sequence_info = None
    
    def prepare_data(self, symbol: str, timeframe: str,
                    sequence_length: int = 20,
                    use_talib: bool = True,
                    test_size: float = 0.2,
                    val_size: float = 0.1) -> Tuple:
        """
        Prepare data for training.
        
        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            sequence_length: Sequence length for LSTM
            use_talib: Use TA-Lib features
            test_size: Test set proportion
            val_size: Validation set proportion
            
        Returns:
            (X_train, X_val, X_test, y_train, y_val, y_test, scaler, feature_names, info)
        """
        print(f"\n{'='*60}")
        print(f"Preparing data for {symbol} {timeframe}")
        print(f"{'='*60}\n")
        
        # Get market data from database
        query = """
            SELECT * FROM market_data 
            WHERE symbol = ? AND timeframe = ?
            ORDER BY timestamp DESC
            LIMIT 2000
        """
        with self.db.get_connection() as conn:
            df = pd.read_sql_query(query, conn, params=(symbol, timeframe))
        
        if len(df) < 100:
            raise ValueError(f"Not enough data for {symbol}. Need at least 100 bars, got {len(df)}")
        
        print(f"✅ Got {len(df)} bars of data")
        
        # Prepare features
        print("\n🔧 Creating features...")
        X, y, feature_names = prepare_training_data(df, use_talib=use_talib)
        
        print(f"✅ Created {len(feature_names)} features")
        
        # Scale features
        from sklearn.preprocessing import StandardScaler
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        
        # Create sequences
        X_train, X_val, X_test, y_train, y_val, y_test, info = prepare_sequences_for_training(
            X_scaled, y,
            sequence_length=sequence_length,
            test_size=test_size,
            val_size=val_size,
            shuffle=False,  # Don't shuffle time series
            random_state=42
        )
        
        # Store for later use
        self.scaler = scaler
        self.feature_names = feature_names
        self.sequence_info = info
        
        return X_train, X_val, X_test, y_train, y_val, y_test, scaler, feature_names, info
    
    def train_lstm(self, X_train, y_train, X_val, y_val,
                   lstm_units: list = [128, 64],
                   dense_units: list = [32, 16],
                   dropout_rate: float = 0.3,
                   use_attention: bool = True,
                   learning_rate: float = 0.001,
                   epochs: int = 100,
                   batch_size: int = 32,
                   model_save_path: str = None) -> Tuple[keras.Model, Any]:
        """
        Train LSTM model.
        
        Args:
            X_train: Training sequences
            y_train: Training labels
            X_val: Validation sequences
            y_val: Validation labels
            lstm_units: LSTM layer units
            dense_units: Dense layer units
            dropout_rate: Dropout rate
            use_attention: Use attention mechanism
            learning_rate: Learning rate
            epochs: Number of epochs
            batch_size: Batch size
            model_save_path: Path to save model
            
        Returns:
            (model, history)
        """
        print(f"\n{'='*60}")
        print("Training LSTM Model")
        print(f"{'='*60}\n")
        
        # Build model
        sequence_length = X_train.shape[1]
        n_features = X_train.shape[2]
        
        model = build_lstm_model(
            sequence_length=sequence_length,
            n_features=n_features,
            lstm_units=lstm_units,
            dense_units=dense_units,
            dropout_rate=dropout_rate,
            use_attention=use_attention,
            learning_rate=learning_rate
        )
        
        print_model_summary(model)
        
        # Prepare callbacks
        if model_save_path is None:
            model_save_path = f"models/tensorflow/lstm_temp.h5"
        
        Path(model_save_path).parent.mkdir(parents=True, exist_ok=True)
        
        callbacks = get_callbacks(
            model_path=model_save_path,
            patience=15,
            min_delta=0.0001
        )
        
        # Train
        print("🚀 Starting training...")
        history = model.fit(
            X_train, y_train,
            validation_data=(X_val, y_val),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=callbacks,
            verbose=1
        )
        
        self.model = model
        self.history = history
        
        return model, history
    
    def train_cnn_lstm(self, X_train, y_train, X_val, y_val,
                       cnn_filters: list = [64, 32],
                       kernel_size: int = 3,
                       lstm_units: list = [128, 64],
                       dense_units: list = [32],
                       dropout_rate: float = 0.3,
                       use_attention: bool = True,
                       learning_rate: float = 0.001,
                       epochs: int = 100,
                       batch_size: int = 32,
                       model_save_path: str = None) -> Tuple[keras.Model, Any]:
        """
        Train CNN-LSTM model.
        
        Args:
            X_train: Training sequences
            y_train: Training labels
            X_val: Validation sequences
            y_val: Validation labels
            cnn_filters: CNN filter counts
            kernel_size: CNN kernel size
            lstm_units: LSTM layer units
            dense_units: Dense layer units
            dropout_rate: Dropout rate
            use_attention: Use attention
            learning_rate: Learning rate
            epochs: Number of epochs
            batch_size: Batch size
            model_save_path: Path to save model
            
        Returns:
            (model, history)
        """
        print(f"\n{'='*60}")
        print("Training CNN-LSTM Model")
        print(f"{'='*60}\n")
        
        # Build model
        sequence_length = X_train.shape[1]
        n_features = X_train.shape[2]
        
        model = build_cnn_lstm_model(
            sequence_length=sequence_length,
            n_features=n_features,
            cnn_filters=cnn_filters,
            kernel_size=kernel_size,
            lstm_units=lstm_units,
            dense_units=dense_units,
            dropout_rate=dropout_rate,
            use_attention=use_attention,
            learning_rate=learning_rate
        )
        
        print_model_summary(model)
        
        # Prepare callbacks
        if model_save_path is None:
            model_save_path = f"models/tensorflow/cnn_lstm_temp.h5"
        
        Path(model_save_path).parent.mkdir(parents=True, exist_ok=True)
        
        callbacks = get_callbacks(
            model_path=model_save_path,
            patience=15,
            min_delta=0.0001
        )
        
        # Train
        print("🚀 Starting training...")
        history = model.fit(
            X_train, y_train,
            validation_data=(X_val, y_val),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=callbacks,
            verbose=1
        )
        
        self.model = model
        self.history = history
        
        return model, history
    
    def evaluate(self, X_test, y_test) -> Dict[str, float]:
        """
        Evaluate model on test set.
        
        Args:
            X_test: Test sequences
            y_test: Test labels
            
        Returns:
            Dictionary of metrics
        """
        if self.model is None:
            raise ValueError("No model trained yet")
        
        print(f"\n{'='*60}")
        print("Evaluating Model")
        print(f"{'='*60}\n")
        
        # Evaluate
        results = self.model.evaluate(X_test, y_test, verbose=1)
        
        # Get metric names
        metric_names = self.model.metrics_names
        
        # Create results dict
        metrics = {name: value for name, value in zip(metric_names, results)}
        
        print(f"\n📊 Test Results:")
        for name, value in metrics.items():
            print(f"   {name}: {value:.4f}")
        
        return metrics
    
    def save_model(self, symbol: str, timeframe: str, model_type: str,
                   train_metrics: Dict, test_metrics: Dict,
                   hyperparameters: Dict) -> int:
        """
        Save model to database and disk.
        
        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            model_type: Model type (LSTM, CNN-LSTM, etc.)
            train_metrics: Training metrics
            test_metrics: Test metrics
            hyperparameters: Model hyperparameters
            
        Returns:
            Model ID in database
        """
        print(f"\n💾 Saving model...")
        
        # Create model directory
        model_dir = Path('models/tensorflow')
        model_dir.mkdir(parents=True, exist_ok=True)
        
        # Generate timestamp
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # Save TensorFlow model
        model_filename = f"{model_type.lower()}_{symbol}_{timeframe}_{timestamp}.h5"
        model_path = model_dir / model_filename
        self.model.save(model_path)
        
        # Save metadata (scaler, feature names, etc.)
        metadata_filename = f"{model_type.lower()}_{symbol}_{timeframe}_{timestamp}_metadata.pkl"
        metadata_path = model_dir / metadata_filename
        
        metadata = {
            'scaler': self.scaler,
            'features': self.feature_names,
            'sequence_info': self.sequence_info,
            'use_talib': True,
            'model_type': model_type,
            'framework': 'tensorflow'
        }
        
        with open(metadata_path, 'wb') as f:
            pickle.dump(metadata, f)
        
        # Save to database
        model_id = self.db.save_model(
            name=f"{model_type}_{symbol}_{timeframe}",
            version=timestamp,
            model_type=model_type,
            file_path=str(model_path),
            training_accuracy=train_metrics.get('accuracy', 0.0),
            validation_accuracy=test_metrics.get('accuracy', 0.0),
            parameters={
                **hyperparameters,
                'features': self.feature_names,
                'n_features': len(self.feature_names),
                'sequence_length': self.sequence_info['sequence_length'],
                'framework': 'tensorflow',
                'metadata_path': str(metadata_path)
            }
        )
        
        print(f"✅ Model saved successfully!")
        print(f"   Model ID: {model_id}")
        print(f"   Model file: {model_path}")
        print(f"   Metadata file: {metadata_path}")
        
        return model_id


def train_tensorflow_model(symbol: str = 'EURUSD',
                          timeframe: str = 'H1',
                          model_type: str = 'LSTM',
                          sequence_length: int = 20,
                          **kwargs) -> int:
    """
    Complete training pipeline for TensorFlow models.
    
    Args:
        symbol: Trading symbol
        timeframe: Timeframe
        model_type: 'LSTM' or 'CNN-LSTM'
        sequence_length: Sequence length
        **kwargs: Additional hyperparameters
        
    Returns:
        Model ID
    """
    trainer = TensorFlowTrainer()
    
    # Prepare data
    X_train, X_val, X_test, y_train, y_val, y_test, scaler, features, info = trainer.prepare_data(
        symbol=symbol,
        timeframe=timeframe,
        sequence_length=sequence_length
    )
    
    # Train model
    if model_type.upper() == 'LSTM':
        model, history = trainer.train_lstm(
            X_train, y_train, X_val, y_val,
            **kwargs
        )
    elif model_type.upper() == 'CNN-LSTM':
        model, history = trainer.train_cnn_lstm(
            X_train, y_train, X_val, y_val,
            **kwargs
        )
    else:
        raise ValueError(f"Unknown model type: {model_type}")
    
    # Evaluate
    test_metrics = trainer.evaluate(X_test, y_test)
    
    # Get training metrics
    train_metrics = {
        'accuracy': history.history['accuracy'][-1],
        'loss': history.history['loss'][-1]
    }
    
    # Save model
    model_id = trainer.save_model(
        symbol=symbol,
        timeframe=timeframe,
        model_type=model_type,
        train_metrics=train_metrics,
        test_metrics=test_metrics,
        hyperparameters=kwargs
    )
    
    return model_id


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Train TensorFlow model for trading')
    parser.add_argument('--symbol', default='EURUSD', help='Trading symbol')
    parser.add_argument('--timeframe', default='H1', help='Timeframe')
    parser.add_argument('--model-type', default='LSTM', choices=['LSTM', 'CNN-LSTM'], help='Model type')
    parser.add_argument('--sequence-length', type=int, default=20, help='Sequence length')
    parser.add_argument('--epochs', type=int, default=50, help='Number of epochs')
    
    args = parser.parse_args()
    
    model_id = train_tensorflow_model(
        symbol=args.symbol,
        timeframe=args.timeframe,
        model_type=args.model_type,
        sequence_length=args.sequence_length,
        epochs=args.epochs
    )
    
    print(f"\n✅ Training complete! Model ID: {model_id}")
