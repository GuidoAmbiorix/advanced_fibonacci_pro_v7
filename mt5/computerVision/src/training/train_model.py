"""
ML Model Trainer for CV Trading Agent with TA-Lib Features

This script trains an MLP classifier using advanced technical indicators.
"""

import sys
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import pickle
from datetime import datetime

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))
from src.database import DatabaseManager
from src.features import prepare_training_data, TALIB_AVAILABLE

print(f"TA-Lib available: {TALIB_AVAILABLE}")

def train_model(symbol='EURUSD', timeframe='H1', use_talib=True):
    """Train an MLP model with advanced features."""
    print(f"\n{'='*60}")
    print(f"Training model for {symbol} {timeframe}")
    print(f"Using TA-Lib features: {use_talib and TALIB_AVAILABLE}")
    print(f"{'='*60}\n")
    
    db = DatabaseManager()
    
    # Get market data
    print("📥 Fetching market data...")
    query = """
        SELECT * FROM market_data 
        WHERE symbol = %s AND timeframe = %s
        ORDER BY timestamp DESC
        LIMIT 1000
    """
    with db.get_connection() as conn:
        cursor = conn.execute(query, (symbol, timeframe))

        rows = cursor.fetchall()

        df = pd.DataFrame([dict(row) for row in rows]) if rows else pd.DataFrame()
    
    if len(df) < 100:
        print(f"❌ Not enough data for {symbol}. Need at least 100 bars, got {len(df)}")
        print("Please run the MT5 bridge to sync data first.")
        return
    
    print(f"✅ Got {len(df)} bars of data")
    
    # Prepare training data with TA-Lib features
    print("\n🔧 Creating features...")
    X, y, feature_names, _ = prepare_training_data(df, use_talib=use_talib)
    
    print(f"✅ Created {len(feature_names)} features:")
    for i, feat in enumerate(feature_names, 1):
        print(f"   {i}. {feat}")
    
    print(f"\n📊 Training data shape: {X.shape}")
    print(f"   Samples: {len(X)}")
    print(f"   Features: {len(feature_names)}")
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    
    # Train model
    print("\n🚀 Training MLP classifier...")
    model = MLPClassifier(
        hidden_layer_sizes=(50, 30),
        activation='relu',
        max_iter=500,
        random_state=42,
        early_stopping=True,
        validation_fraction=0.2,
        verbose=False
    )
    
    model.fit(X_train_scaled, y_train)
    
    # Evaluate
    train_acc = model.score(X_train_scaled, y_train)
    test_acc = model.score(X_test_scaled, y_test)
    
    print(f"\n📈 Results:")
    print(f"   Training accuracy: {train_acc:.2%}")
    print(f"   Validation accuracy: {test_acc:.2%}")
    
    # Save model
    print("\n💾 Saving model...")
    model_dir = Path(__file__).parent.parent.parent / 'models'
    model_dir.mkdir(exist_ok=True)
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    model_filename = f"mlp_{symbol}_{timeframe}_{timestamp}.pkl"
    model_path = model_dir / model_filename
    
    # Save model, scaler, and feature names
    with open(model_path, 'wb') as f:
        pickle.dump({
            'model': model,
            'scaler': scaler,
            'features': feature_names,
            'use_talib': use_talib and TALIB_AVAILABLE
        }, f)
    
    # Save to database
    model_id = db.save_model(
        name=f"MLP_{symbol}_{timeframe}",
        version=timestamp,
        model_type='MLPClassifier',
        file_path=str(model_path),
        training_accuracy=train_acc,
        validation_accuracy=test_acc,
        parameters={
            'hidden_layers': [50, 30],
            'activation': 'relu',
            'features': feature_names,
            'use_talib': use_talib and TALIB_AVAILABLE,
            'n_features': len(feature_names)
        }
    )
    
    # Set as active model
    db.set_active_model(model_id)
    
    print(f"\n✅ Model saved successfully!")
    print(f"   Model ID: {model_id}")
    print(f"   File: {model_path}")
    print(f"   Training accuracy: {train_acc:.2%}")
    print(f"   Validation accuracy: {test_acc:.2%}")
    print(f"\nModel is now active and ready for predictions!")

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Train ML model for trading')
    parser.add_argument('--symbol', default='EURUSD', help='Trading symbol')
    parser.add_argument('--timeframe', default='H1', help='Timeframe')
    
    args = parser.parse_args()
    
    train_model(args.symbol, args.timeframe)
