"""
Optuna Hyperparameter Optimization for Trading Models

This script uses Optuna to automatically find the best hyperparameters
for the trading model, including architecture, learning rate, and features.
"""

import sys
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split, cross_val_score
import optuna
from optuna.pruners import MedianPruner
from optuna.samplers import TPESampler
import pickle
from datetime import datetime

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))
from src.database import DatabaseManager
from src.features import prepare_training_data, TALIB_AVAILABLE


def objective(trial, X_train, X_test, y_train, y_test):
    """
    Optuna objective function to optimize.
    
    Args:
        trial: Optuna trial object
        X_train, X_test, y_train, y_test: Training and test data
        
    Returns:
        Validation accuracy (to maximize)
    """
    # Suggest hyperparameters
    n_layers = trial.suggest_int('n_layers', 1, 4)
    
    # Build hidden layer sizes
    hidden_layers = []
    for i in range(n_layers):
        layer_size = trial.suggest_int(f'layer_{i}_size', 16, 256, log=True)
        hidden_layers.append(layer_size)
    
    # Other hyperparameters
    activation = trial.suggest_categorical('activation', ['relu', 'tanh'])
    learning_rate = trial.suggest_float('learning_rate_init', 1e-5, 1e-2, log=True)
    alpha = trial.suggest_float('alpha', 1e-5, 1e-1, log=True)  # L2 regularization
    batch_size = trial.suggest_categorical('batch_size', [32, 64, 128, 256])
    
    # Create model
    model = MLPClassifier(
        hidden_layer_sizes=tuple(hidden_layers),
        activation=activation,
        learning_rate_init=learning_rate,
        alpha=alpha,
        batch_size=batch_size,
        max_iter=500,
        random_state=42,
        early_stopping=True,
        validation_fraction=0.2,
        verbose=False
    )
    
    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    
    # Train model
    model.fit(X_train_scaled, y_train)
    
    # Evaluate
    accuracy = model.score(X_test_scaled, y_test)
    
    return accuracy


def optimize_hyperparameters(symbol='EURUSD', timeframe='H1', n_trials=50):
    """
    Run Optuna optimization to find best hyperparameters.
    
    Args:
        symbol: Trading symbol
        timeframe: Timeframe
        n_trials: Number of optimization trials
        
    Returns:
        Best parameters dictionary
    """
    print(f"\n{'='*70}")
    print(f"🔍 OPTUNA HYPERPARAMETER OPTIMIZATION")
    print(f"{'='*70}")
    print(f"Symbol: {symbol}")
    print(f"Timeframe: {timeframe}")
    print(f"Trials: {n_trials}")
    print(f"TA-Lib: {TALIB_AVAILABLE}")
    print(f"{'='*70}\n")
    
    db = DatabaseManager()
    
    # Get market data
    print("📥 Fetching market data...")
    query = """
        SELECT * FROM market_data 
        WHERE symbol = ? AND timeframe = ?
        ORDER BY timestamp DESC
        LIMIT 1000
    """
    with db.get_connection() as conn:
        df = pd.read_sql_query(query, conn, params=(symbol, timeframe))
    
    if len(df) < 100:
        print(f"❌ Not enough data for {symbol}. Need at least 100 bars, got {len(df)}")
        return None
    
    print(f"✅ Got {len(df)} bars of data")
    
    # Prepare training data
    print("\n🔧 Creating features...")
    X, y, feature_names = prepare_training_data(df, use_talib=True)
    
    print(f"✅ Created {len(feature_names)} features")
    print(f"📊 Training data shape: {X.shape}")
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Create Optuna study
    print(f"\n🚀 Starting Optuna optimization ({n_trials} trials)...")
    print("This may take several minutes...\n")
    
    study = optuna.create_study(
        direction='maximize',
        sampler=TPESampler(seed=42),
        pruner=MedianPruner(n_startup_trials=5, n_warmup_steps=10)
    )
    
    # Run optimization
    study.optimize(
        lambda trial: objective(trial, X_train, X_test, y_train, y_test),
        n_trials=n_trials,
        show_progress_bar=True
    )
    
    # Results
    print(f"\n{'='*70}")
    print(f"📊 OPTIMIZATION RESULTS")
    print(f"{'='*70}")
    print(f"Best validation accuracy: {study.best_value:.2%}")
    print(f"Best trial: #{study.best_trial.number}")
    print(f"\n🏆 Best Hyperparameters:")
    for key, value in study.best_params.items():
        print(f"   {key}: {value}")
    
    # Train final model with best parameters
    print(f"\n{'='*70}")
    print(f"🎯 Training final model with best parameters...")
    print(f"{'='*70}\n")
    
    best_params = study.best_params
    
    # Build hidden layers from best params
    n_layers = best_params['n_layers']
    hidden_layers = tuple([best_params[f'layer_{i}_size'] for i in range(n_layers)])
    
    # Create final model
    final_model = MLPClassifier(
        hidden_layer_sizes=hidden_layers,
        activation=best_params['activation'],
        learning_rate_init=best_params['learning_rate_init'],
        alpha=best_params['alpha'],
        batch_size=best_params['batch_size'],
        max_iter=1000,  # More iterations for final model
        random_state=42,
        early_stopping=True,
        validation_fraction=0.2,
        verbose=True
    )
    
    # Scale and train
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    
    final_model.fit(X_train_scaled, y_train)
    
    # Evaluate
    train_acc = final_model.score(X_train_scaled, y_train)
    test_acc = final_model.score(X_test_scaled, y_test)
    
    print(f"\n📈 Final Model Results:")
    print(f"   Training accuracy: {train_acc:.2%}")
    print(f"   Validation accuracy: {test_acc:.2%}")
    
    # Save model
    print("\n💾 Saving optimized model...")
    model_dir = Path(__file__).parent.parent.parent / 'models'
    model_dir.mkdir(exist_ok=True)
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    model_filename = f"mlp_optuna_{symbol}_{timeframe}_{timestamp}.pkl"
    model_path = model_dir / model_filename
    
    with open(model_path, 'wb') as f:
        pickle.dump({
            'model': final_model,
            'scaler': scaler,
            'features': feature_names,
            'use_talib': TALIB_AVAILABLE,
            'optuna_params': best_params,
            'optuna_score': study.best_value
        }, f)
    
    # Save to database
    model_id = db.save_model(
        name=f"MLP_Optuna_{symbol}_{timeframe}",
        version=timestamp,
        model_type='MLPClassifier_Optimized',
        file_path=str(model_path),
        training_accuracy=train_acc,
        validation_accuracy=test_acc,
        parameters={
            'hidden_layers': list(hidden_layers),
            'activation': best_params['activation'],
            'learning_rate': best_params['learning_rate_init'],
            'alpha': best_params['alpha'],
            'batch_size': best_params['batch_size'],
            'features': feature_names,
            'use_talib': TALIB_AVAILABLE,
            'n_features': len(feature_names),
            'optimization_method': 'Optuna',
            'n_trials': n_trials,
            'best_trial_score': study.best_value
        }
    )
    
    # Set as active model
    db.set_active_model(model_id)
    
    print(f"\n✅ Optimized model saved successfully!")
    print(f"   Model ID: {model_id}")
    print(f"   File: {model_path}")
    print(f"   Validation accuracy: {test_acc:.2%}")
    print(f"\n🎉 Model is now active and ready for predictions!")
    
    return study.best_params


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Optimize ML model hyperparameters with Optuna')
    parser.add_argument('--symbol', default='EURUSD', help='Trading symbol')
    parser.add_argument('--timeframe', default='H1', help='Timeframe')
    parser.add_argument('--trials', type=int, default=50, help='Number of optimization trials')
    
    args = parser.parse_args()
    
    optimize_hyperparameters(args.symbol, args.timeframe, args.trials)
