"""
Prediction Service - Generates ML predictions for allocated portfolio symbols

This service runs in the background and generates predictions every 5 minutes
for all symbols that have active allocations in the selected portfolio.
"""

import logging
import pickle
import pandas as pd
from datetime import datetime, timedelta
from pathlib import Path
import sys

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))
from src.database import DatabaseManager
from src.features import create_talib_features, create_basic_features

class PredictionService:
    """Generates predictions for portfolio-allocated symbols."""
    
    def __init__(self, db: DatabaseManager):
        self.db = db
        self.logger = logging.getLogger(__name__)
        
    def generate_predictions_for_portfolio(self, portfolio_id: int):
        """Generate predictions for all allocated symbols in a portfolio."""
        allocations = self.db.get_allocations(portfolio_id)
        
        if not allocations:
            self.logger.info(f"No allocations found for portfolio {portfolio_id}")
            return
        
        for alloc in allocations:
            if alloc['weight'] <= 0:
                continue
                
            symbol = alloc['symbol']
            model_id = alloc['model_id']
            
            try:
                self._generate_prediction(symbol, model_id)
            except Exception as e:
                self.logger.error(f"Failed to generate prediction for {symbol}: {e}")
    
    def _generate_prediction(self, symbol: str, model_id: int):
        """Generate a single prediction for a symbol using a specific model."""
        # Get model metadata
        model_meta = self.db.get_model(model_id)
        if not model_meta:
            self.logger.error(f"Model {model_id} not found")
            return
        
        model_path = model_meta['file_path']
        timeframe = model_meta.get('timeframe', 'H1')
        
        # Load model to get features list
        model_file = Path(model_path)
        if not model_file.exists():
            self.logger.warning(f"Model file not found: {model_path}")
            # Try to find substitute model for same symbol/timeframe
            # Pattern: mlp_optuna_{symbol}_{timeframe}_*.pkl
            try:
                models_dir = Path("/app/models")
                if models_dir.exists():
                    # Construct pattern based on expected naming convention
                    # We need symbol and timeframe. Metadata from DB has 'hyperparameters' which usually has them
                    # Or we can guess from the filename payload
                    # Let's try to match the prefix of the missing file
                    filename = model_file.name
                    parts = filename.split('_')
                    # e.g. mlp_optuna_EURUSD_M15_2026...
                    if len(parts) >= 4:
                        prefix = "_".join(parts[:4]) # mlp_optuna_EURUSD_M15
                        candidates = list(models_dir.glob(f"{prefix}*.pkl"))
                        if candidates:
                            # Sort by modification time (latest first)
                            candidates.sort(key=lambda x: x.stat().st_mtime, reverse=True)
                            model_file = candidates[0]
                            self.logger.info(f"Found substitute model: {model_file}")
                        else:
                             self.logger.error(f"No substitute models found for pattern {prefix}")
                             return
                    else:
                        return
                else:
                    return
            except Exception as e:
                self.logger.error(f"Error searching for substitute model: {e}")
                return
        
        with open(model_file, 'rb') as f:
            model_data = pickle.load(f)
        
        framework = model_data.get('framework', 'standard')
        
        # Phase 7: Handle Hybrid Ensembles
        if framework == 'hybrid':
            self.logger.info(f"Loading hybrid ensemble for {symbol}")
            ensemble = model_data['ensemble']
            tf_model_paths = model_data.get('tf_model_paths', {})
            
            # Reconstruct TF models in the wrappers
            from tensorflow import keras
            from src.training.ensemble_trainer import TensorFlowWrapper
            
            for name, est in ensemble.estimators_:
                if isinstance(est, TensorFlowWrapper):
                    path = tf_model_paths.get(name) or est.model_path
                    if path and Path(path).exists():
                        self.logger.debug(f"Loading TF model part '{name}' from {path}")
                        # Use custom_objects if needed
                        from src.training.tf_models import AttentionLayer
                        est.model = keras.models.load_model(path, custom_objects={'AttentionLayer': AttentionLayer})
                    else:
                        self.logger.error(f"TF model part '{name}' not found at {path}")
                        return
            
            model = ensemble
            scaler = model_data['scaler']
            features = model_data['features']
        else:
            model = model_data['model']
            scaler = model_data['scaler']
            features = model_data.get('features', [])
            if not features and 'feature_names' in model_data:
                features = model_data['feature_names']
        
        # Auto-detect if TA-Lib features are used
        talib_indicators = ['ADX', 'MACD', 'RSI', 'SMA_', 'EMA_', 'ATR', 'BBANDS', 'STOCH', 'WILLR', 'ROC', 'CCI', 'OBV', 'MFI', 'AD']
        use_talib = any(any(indicator in feat for indicator in talib_indicators) for feat in features)
        
        self.logger.info(f"Generating prediction for {symbol} using {'TA-Lib' if use_talib else 'basic'} features")
        
        # Get market data (need more bars for TA-Lib indicators)
        bars_needed = 100 if use_talib else 50
        query = """
            SELECT * FROM market_data 
            WHERE symbol = ? AND timeframe = ?
            ORDER BY timestamp DESC
            LIMIT ?
        """
        with self.db.get_connection() as conn:
            df = pd.read_sql_query(query, conn, params=(symbol, timeframe, bars_needed))
        
        if len(df) < 50:
            self.logger.warning(f"Not enough data for {symbol} (got {len(df)} bars)")
            return
        
        # Create features
        df = df.sort_values('timestamp')
        
        if use_talib:
            df = create_talib_features(df)
        else:
            df = create_basic_features(df)
        
        df = df.dropna()
        
        if len(df) == 0:
            self.logger.warning(f"No data after feature creation for {symbol}")
            return
        
        # Get latest features
        latest = df.iloc[-1]
        
        # Check for missing features
        missing_features = [f for f in features if f not in df.columns]
        if missing_features:
            self.logger.error(f"Missing features for {symbol}: {missing_features[:5]}")
            return
        
        # Prepare input as DataFrame to preserve feature names
        X = pd.DataFrame([[latest[f] for f in features]], columns=features)
        X_scaled = scaler.transform(X)
        
        # Make prediction
        prediction = model.predict(X_scaled)[0]
        confidence = model.predict_proba(X_scaled)[0].max()
        
        direction = "BUY" if prediction == 1 else "SELL"
        
        # Save to database
        window_start = pd.to_datetime(latest['timestamp'])
        window_end = window_start + timedelta(hours=1)
        
        self.db.insert_prediction(
            model_id=model_id,
            symbol=symbol,
            prediction_direction=direction,
            confidence=confidence,
            window_start=window_start,
            window_end=window_end,
            prediction_horizon=1
        )
        
        self.logger.info(f"✅ Generated prediction for {symbol}: {direction} ({confidence:.1%})")
